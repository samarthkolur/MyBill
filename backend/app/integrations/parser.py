"""Receipt parsers behind a single interface (MyBill.md §6, Stage 3).

``ReceiptParser`` is the seam between OCR and the database: it turns an ``OCRResult`` (text
fragments with geometry) into a ``CanonicalReceipt`` (a store, a date, totals, and line
items). The normalisation layer and the worker only ever see ``CanonicalReceipt``, so the
parsing strategy can be replaced — a smarter heuristic, or an LLM extractor — without
touching anything downstream.

``HeuristicReceiptParser`` is the first implementation: pure geometry + regex, no model and
no network. A receipt has no ruled table, so the one thing that reconstructs
``ITEM … QTY … AMOUNT`` into a row is *where* each fragment sits on the page. The engine
detects those as separate regions; this parser regroups them by vertical position, then
reads each row left-to-right. It is deliberately conservative — it would rather leave a
field null (a flagged partial parse) than guess — and every low-confidence result is marked
for review rather than trusted silently.
"""

from __future__ import annotations

import re
from datetime import date, datetime, time
from decimal import Decimal, InvalidOperation
from statistics import median
from typing import Protocol

from app.core.logging import get_logger
from app.schemas.ocr import OCRLine, OCRResult
from app.schemas.parser import (
    REVIEW_CONFIDENCE_THRESHOLD,
    CanonicalItem,
    CanonicalReceipt,
    CanonicalStore,
    CanonicalTotals,
)

logger = get_logger("app.parser")

PARSER_VERSION = "heuristic-0.1.0"

# A money amount: an optional currency marker then digits with a 2-decimal fraction. The
# decimals are required on purpose — an integer alone is indistinguishable from a quantity,
# a date part, or an item code, and a receipt prints prices as `66.00`, not `66`. Thousands
# separators (`1,240.00`) are tolerated and stripped before parsing.
_MONEY_RE = re.compile(r"(?:₹|rs\.?|inr)?\s*(\d{1,3}(?:,\d{3})*|\d+)\.(\d{2})\b", re.IGNORECASE)

# `2 x 66.00` / `2X66.00` — an explicit quantity times a unit price.
_QTY_TIMES_RE = re.compile(r"\b(\d+(?:\.\d+)?)\s*[x×]\s*(?:₹|rs\.?|inr)?\s*\d", re.IGNORECASE)

# A weight/volume/count printed in the item text: `1.5 kg`, `500g`, `2 pcs`.
_UNIT_RE = re.compile(r"\b(\d+(?:\.\d+)?)\s*(kg|g|l|ml|pcs|pc|nos|no)\b", re.IGNORECASE)

# Words that mark a row as part of the money summary rather than a purchased item, or as a
# column header. Either way the row is not a line item.
_SUMMARY_KEYWORDS = {
    "total",
    "subtotal",
    "sub total",
    "tax",
    "gst",
    "cgst",
    "sgst",
    "igst",
    "vat",
    "discount",
    "savings",
    "round",
    "roundoff",
    "change",
    "balance",
    "tender",
    "cash",
    "card",
    "upi",
    "paid",
    "amount",
    "qty",
    "rate",
    "mrp",
    "hsn",
}

# Payment methods, matched as whole words against the full receipt text.
_PAYMENT_KEYWORDS = {
    "upi": "UPI",
    "cash": "Cash",
    "card": "Card",
    "credit": "Card",
    "debit": "Card",
    "visa": "Card",
    "mastercard": "Card",
    "rupay": "Card",
    "paytm": "UPI",
    "gpay": "UPI",
    "phonepe": "UPI",
}

# Preliminary category assignment by keyword (MyBill.md §6 — "keyword mapping → LLM
# fallback"; the LLM fallback is deferred). First category with a hit wins, so the order
# resolves overlaps: a "face wash" is Personal Care before "wash" could pull it elsewhere.
# Imperfect by design — it is a cheap first pass, corrected later by the user or the LLM.
_CATEGORY_KEYWORDS: list[tuple[str, tuple[str, ...]]] = [
    (
        "Dairy",
        (
            "milk",
            "cheese",
            "butter",
            "yogurt",
            "yoghurt",
            "curd",
            "dahi",
            "paneer",
            "ghee",
            "cream",
            "lassi",
            "amul",
        ),
    ),
    (
        "Bakery",
        (
            "bread",
            "bun",
            "cake",
            "biscuit",
            "cookie",
            "pastry",
            "croissant",
            "rusk",
            "loaf",
            "muffin",
        ),
    ),
    ("Meat", ("chicken", "mutton", "fish", "egg", "prawn", "beef", "pork", "meat")),
    (
        "Produce",
        (
            "apple",
            "banana",
            "tomato",
            "onion",
            "potato",
            "vegetable",
            "veg",
            "fruit",
            "spinach",
            "carrot",
            "mango",
            "lemon",
            "ginger",
            "garlic",
            "chilli",
            "cucumber",
        ),
    ),
    (
        "Beverages",
        (
            "juice",
            "soda",
            "cola",
            "coffee",
            "tea",
            "water",
            "drink",
            "pepsi",
            "coke",
            "sprite",
            "redbull",
            "beverage",
        ),
    ),
    (
        "Snacks",
        (
            "chips",
            "namkeen",
            "kurkure",
            "lays",
            "chocolate",
            "candy",
            "wafer",
            "popcorn",
            "snack",
            "biscuits",
        ),
    ),
    (
        "Staples",
        (
            "rice",
            "atta",
            "flour",
            "dal",
            "sugar",
            "salt",
            "oil",
            "pulse",
            "wheat",
            "besan",
            "sooji",
            "maida",
            "masala",
        ),
    ),
    (
        "Personal Care",
        (
            "shampoo",
            "toothpaste",
            "toothbrush",
            "lotion",
            "sanitary",
            "razor",
            "deodorant",
            "handwash",
            "facewash",
            "conditioner",
            "soap",
        ),
    ),
    (
        "Household",
        (
            "detergent",
            "cleaner",
            "tissue",
            "phenyl",
            "harpic",
            "vim",
            "surf",
            "broom",
            "garbage",
            "dishwash",
            "napkin",
        ),
    ),
]

# Date formats seen on Indian grocery receipts, tried in order. Two-digit years are assumed
# 20xx. Day-first is preferred (`dd/mm`) because that's the local convention.
_DATE_PATTERNS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"\b(\d{4})[-/](\d{2})[-/](\d{2})\b"), "%Y-%m-%d"),
    (re.compile(r"\b(\d{1,2})[-/](\d{1,2})[-/](\d{4})\b"), "%d-%m-%Y"),
    (re.compile(r"\b(\d{1,2})[-/](\d{1,2})[-/](\d{2})\b"), "%d-%m-%y"),
    (re.compile(r"\b(\d{1,2})\s+([A-Za-z]{3,9})\s+(\d{4})\b"), "%d %b %Y"),
]

_TIME_RE = re.compile(r"\b([01]?\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?\s*(am|pm)?\b", re.IGNORECASE)


class ReceiptParser(Protocol):
    """Turns an ``OCRResult`` into a structured ``CanonicalReceipt`` (MyBill.md §6)."""

    async def parse(self, ocr: OCRResult) -> CanonicalReceipt: ...


class HeuristicReceiptParser:
    """Geometry + regex parser. No model, no network — deterministic and offline."""

    name = "heuristic"
    version = PARSER_VERSION

    async def parse(self, ocr: OCRResult) -> CanonicalReceipt:
        rows = _group_into_rows(ocr.lines)
        full_text = ocr.text

        items = _extract_items(rows)
        receipt_confidence = _receipt_confidence(items, ocr)
        needs_review = receipt_confidence < REVIEW_CONFIDENCE_THRESHOLD or any(
            item.needs_review for item in items
        )

        result = CanonicalReceipt(
            store=CanonicalStore(name=_extract_store(rows), chain=_extract_store(rows)),
            date=_extract_date(full_text),
            time=_extract_time(full_text),
            payment_method=_extract_payment_method(full_text),
            totals=_extract_totals(rows),
            items=items,
            ocr_confidence=receipt_confidence,
            needs_review=needs_review,
            parser_version=PARSER_VERSION,
        )
        logger.info(
            "receipt_parsed",
            extra={
                "items": len(result.items),
                "has_total": result.totals.total is not None,
                "has_date": result.date is not None,
                "confidence": round(result.ocr_confidence, 3),
                "needs_review": result.needs_review,
                "parser_version": PARSER_VERSION,
            },
        )
        return result


# ---------------------------------------------------------------------------
# Row reconstruction
# ---------------------------------------------------------------------------
def _group_into_rows(lines: list[OCRLine]) -> list[list[OCRLine]]:
    """Cluster fragments that share a printed row, top-to-bottom, then left-to-right.

    Fragments belong to the same row when their vertical centres are within a fraction of the
    typical line height — deriving the threshold from the median height makes it scale with
    image resolution instead of hard-coding pixels. Within a row, fragments are ordered by
    left edge so the row reads the way it was printed.
    """

    if not lines:
        return []

    tolerance = median(line.box.height for line in lines) * 0.6
    ordered = sorted(lines, key=lambda line: line.box.center_y)

    rows: list[list[OCRLine]] = []
    current: list[OCRLine] = []
    row_center = 0.0
    for line in ordered:
        if current and abs(line.box.center_y - row_center) > tolerance:
            rows.append(sorted(current, key=lambda ln: ln.box.x_min))
            current = []
        current.append(line)
        # Track the running mean centre so a slowly drifting baseline doesn't split a row.
        row_center = sum(ln.box.center_y for ln in current) / len(current)
    if current:
        rows.append(sorted(current, key=lambda ln: ln.box.x_min))
    return rows


def _row_text(row: list[OCRLine]) -> str:
    return " ".join(line.text for line in row).strip()


def _row_confidence(row: list[OCRLine]) -> float:
    return sum(line.confidence for line in row) / len(row) if row else 0.0


# ---------------------------------------------------------------------------
# Money / quantity parsing
# ---------------------------------------------------------------------------
def _money_values(text: str) -> list[Decimal]:
    """Every money amount in a string, left-to-right, as Decimals."""

    values: list[Decimal] = []
    for whole, frac in _MONEY_RE.findall(text):
        try:
            values.append(Decimal(f"{whole.replace(',', '')}.{frac}"))
        except InvalidOperation:  # pragma: no cover - regex already constrains the shape
            continue
    return values


def _quantize_money(value: Decimal) -> Decimal:
    return value.quantize(Decimal("0.01"))


def _quantize_qty(value: Decimal) -> Decimal:
    return value.quantize(Decimal("0.001"))


# ---------------------------------------------------------------------------
# Line items
# ---------------------------------------------------------------------------
def _is_summary_row(text: str) -> bool:
    lowered = text.lower()
    return any(keyword in lowered for keyword in _SUMMARY_KEYWORDS)


def _extract_items(rows: list[list[OCRLine]]) -> list[CanonicalItem]:
    items: list[CanonicalItem] = []
    for row in rows:
        text = _row_text(row)
        if _is_summary_row(text):
            continue  # a total/tax/header row, handled by _extract_totals
        item = _row_to_item(text, _row_confidence(row))
        if item is not None:
            items.append(item)
    return items


def _row_to_item(text: str, confidence: float) -> CanonicalItem | None:
    """Read one non-summary row as a line item, or ``None`` if it isn't one.

    A line item needs a price *and* a name. The name is whatever text precedes the first
    money amount; a row with money but no letters (a stray subtotal, a code) is not an item.
    """

    money = _money_values(text)
    if not money:
        return None

    # The name is the text before the first money token; strip the amounts, currency markers,
    # and a trailing `N x` quantity marker so the stored name is just the product ("Lays Chips
    # 2 x" → "Lays Chips"). A unit like "1L" is left in place — it's part of the product's
    # identity, not noise.
    name = _MONEY_RE.split(text)[0]
    name = re.sub(r"[₹]|(?:\brs\.?\b)|(?:\binr\b)", "", name, flags=re.IGNORECASE)
    name = re.sub(r"\s*\d+(?:\.\d+)?\s*[x×]\s*$", "", name, flags=re.IGNORECASE)
    name = name.strip(" -\t|:")
    if not re.search(r"[A-Za-z]{2,}", name):
        return None  # no real product name → not a purchased line

    quantity, unit = _extract_quantity_unit(text)

    # Recover quantity, unit price, and total together — the three columns aren't always all
    # printed, so each shape fills in the rest:
    #   `2 x 66.00 132.00` → qty 2, unit 66.00, total 132.00 (both amounts printed)
    #   `2 x 66.00`        → qty 2, unit 66.00, total derived as 132.00 (no line total)
    #   `62.00 124.00`     → two columns: unit 62.00, total 124.00
    #   `66.00`            → a single amount is both unit price and total, at quantity 1
    times = _QTY_TIMES_RE.search(text)
    if times:
        quantity = _quantize_qty(Decimal(times.group(1)))
        unit_price = _quantize_money(money[0])
        total_price = (
            _quantize_money(money[-1])
            if len(money) >= 2
            else _quantize_money(unit_price * quantity)
        )
    elif len(money) >= 2:
        unit_price = _quantize_money(money[0])
        total_price = _quantize_money(money[-1])
    else:
        total_price = _quantize_money(money[-1])
        unit_price = total_price

    if quantity <= 0:
        quantity = Decimal(1)

    normalised = _normalise_name(name)
    return CanonicalItem(
        name=name,
        name_normalised=normalised,
        category=_categorise(normalised),
        quantity=quantity,
        unit=unit,
        unit_price=unit_price,
        total_price=total_price,
        ocr_confidence=round(confidence, 3),
        needs_review=confidence < REVIEW_CONFIDENCE_THRESHOLD,
    )


def _extract_quantity_unit(text: str) -> tuple[Decimal, str | None]:
    """A weight/volume/count embedded in the item text (`1.5 kg`), else (1, None)."""

    match = _UNIT_RE.search(text)
    if not match:
        return Decimal(1), None
    unit = match.group(2).lower()
    unit = {"pc": "pcs", "no": "pcs", "nos": "pcs"}.get(unit, unit)
    return _quantize_qty(Decimal(match.group(1))), unit


def _normalise_name(name: str) -> str:
    """Lowercase, drop punctuation, collapse whitespace — the cross-store match key."""

    lowered = re.sub(r"[^a-z0-9\s]", " ", name.lower())
    return re.sub(r"\s+", " ", lowered).strip()


def _categorise(name_normalised: str) -> str | None:
    for category, keywords in _CATEGORY_KEYWORDS:
        if any(keyword in name_normalised for keyword in keywords):
            return category
    return None


# ---------------------------------------------------------------------------
# Totals
# ---------------------------------------------------------------------------
def _extract_totals(rows: list[list[OCRLine]]) -> CanonicalTotals:
    """Pull the money summary from the keyword-bearing rows.

    ``total`` is taken from a row that says "total" but not "subtotal" — the printed grand
    total, not the pre-tax subtotal. When several rows qualify (a receipt often repeats
    "TOTAL" for the card slip) the last one wins, since the final figure sits lowest.
    """

    totals = CanonicalTotals()
    for row in rows:
        text = _row_text(row)
        lowered = text.lower()
        money = _money_values(text)
        if not money:
            continue
        amount = _quantize_money(money[-1])

        if "subtotal" in lowered or "sub total" in lowered:
            totals.subtotal = amount
        elif "total" in lowered:
            totals.total = amount
        elif any(k in lowered for k in ("tax", "gst", "cgst", "sgst", "igst", "vat")):
            # Sum tax lines — CGST + SGST are printed separately but are one tax figure.
            totals.tax = _quantize_money((totals.tax or Decimal(0)) + amount)
        elif "discount" in lowered or "savings" in lowered:
            totals.discount = amount
    return totals


# ---------------------------------------------------------------------------
# Store, date, time, payment
# ---------------------------------------------------------------------------
def _extract_store(rows: list[list[OCRLine]]) -> str | None:
    """The store name from the header — the topmost row that reads like a name.

    Receipts print the store at the very top. The first row with real letters that isn't a
    line item (no price) and isn't a summary keyword is taken as the name.
    """

    for row in rows[:4]:
        text = _row_text(row)
        if _money_values(text) or _is_summary_row(text):
            continue
        if re.search(r"[A-Za-z]{2,}", text):
            return text.strip()
    return None


def _extract_date(text: str) -> date | None:
    for pattern, fmt in _DATE_PATTERNS:
        match = pattern.search(text)
        if not match:
            continue
        raw = " ".join(match.groups()) if fmt == "%d %b %Y" else "-".join(match.groups())
        normalised_fmt = fmt.replace("/", "-")
        try:
            return datetime.strptime(raw, normalised_fmt).date()
        except ValueError:
            continue  # e.g. a "13th month" false positive — try the next pattern
    return None


def _extract_time(text: str) -> time | None:
    match = _TIME_RE.search(text)
    if not match:
        return None
    hour, minute = int(match.group(1)), int(match.group(2))
    meridiem = (match.group(3) or "").lower()
    if meridiem == "pm" and hour < 12:
        hour += 12
    elif meridiem == "am" and hour == 12:
        hour = 0
    try:
        return time(hour, minute)
    except ValueError:  # pragma: no cover - regex already bounds the range
        return None


def _extract_payment_method(text: str) -> str | None:
    lowered = text.lower()
    for keyword, label in _PAYMENT_KEYWORDS.items():
        if re.search(rf"\b{keyword}\b", lowered):
            return label
    return None


# ---------------------------------------------------------------------------
# Confidence
# ---------------------------------------------------------------------------
def _receipt_confidence(items: list[CanonicalItem], ocr: OCRResult) -> float:
    """Receipt-level score: the mean item confidence, or the raw OCR mean when nothing
    parsed (a receipt that yielded no items is exactly the low-confidence case to flag)."""

    scored = [item.ocr_confidence for item in items if item.ocr_confidence is not None]
    if scored:
        return round(sum(scored) / len(scored), 3)
    return round(ocr.mean_confidence, 3)
