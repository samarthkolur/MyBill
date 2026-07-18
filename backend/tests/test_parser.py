"""Tests for the heuristic receipt parser.

The parser's whole job is geometry + text → structure, so these build ``OCRResult``s by
hand with explicit boxes and assert the ``CanonicalReceipt`` that comes out. No OCR engine
is involved — that boundary is covered by ``test_ocr``.
"""

from __future__ import annotations

from datetime import date, time
from decimal import Decimal

from app.integrations.parser import PARSER_VERSION, HeuristicReceiptParser
from app.schemas.ocr import BoundingBox, OCRLine, OCRResult

_ROW_H = 18.0
_ROW_GAP = 30.0  # centre-to-centre; comfortably past the grouping tolerance


def _line(text: str, x: float, row: int, *, width: float = 90.0, conf: float = 0.95) -> OCRLine:
    """A detected fragment at column ``x`` on visual row ``row`` (0-indexed, top-down)."""

    y_min = row * _ROW_GAP
    return OCRLine(
        text=text,
        box=BoundingBox(x_min=x, y_min=y_min, x_max=x + width, y_max=y_min + _ROW_H),
        confidence=conf,
    )


def _result(*lines: OCRLine) -> OCRResult:
    return OCRResult(lines=list(lines), provider="test")


async def _parse(*lines: OCRLine):
    return await HeuristicReceiptParser().parse(_result(*lines))


# ---------------------------------------------------------------------------
# Row reconstruction
# ---------------------------------------------------------------------------
async def test_fragments_on_one_visual_row_become_one_item() -> None:
    # Name and price are detected as separate regions at the same height — the parser must
    # rejoin them into a single line, which is the entire reason geometry is carried.
    receipt = await _parse(
        _line("AMUL MILK 1L", x=20, row=0),
        _line("66.00", x=320, row=0),
    )

    assert len(receipt.items) == 1
    item = receipt.items[0]
    assert item.name == "AMUL MILK 1L"
    assert item.total_price == Decimal("66.00")
    assert item.unit_price == Decimal("66.00")
    assert item.quantity == Decimal(1)


async def test_separate_rows_stay_separate_items() -> None:
    receipt = await _parse(
        _line("BREAD", x=20, row=0),
        _line("40.00", x=320, row=0),
        _line("EGGS", x=20, row=1),
        _line("60.00", x=320, row=1),
    )

    assert [item.name for item in receipt.items] == ["BREAD", "EGGS"]


# ---------------------------------------------------------------------------
# Quantity / unit price shapes
# ---------------------------------------------------------------------------
async def test_two_price_columns_are_unit_then_total() -> None:
    receipt = await _parse(
        _line("AMUL TAAZA MILK", x=20, row=0),
        _line("62.00", x=280, row=0),
        _line("124.00", x=360, row=0),
    )

    item = receipt.items[0]
    assert item.unit_price == Decimal("62.00")
    assert item.total_price == Decimal("124.00")


async def test_quantity_times_price_with_explicit_total() -> None:
    receipt = await _parse(
        _line("MAGGI 2 x 14.00", x=20, row=0),
        _line("28.00", x=340, row=0),
    )

    item = receipt.items[0]
    assert item.quantity == Decimal("2")
    assert item.unit_price == Decimal("14.00")
    assert item.total_price == Decimal("28.00")


async def test_quantity_times_price_derives_missing_total() -> None:
    # `3 x 20.00` with no printed line total — the total is derived, not left blank.
    receipt = await _parse(_line("PEPSI 3 x 20.00", x=20, row=0))

    item = receipt.items[0]
    assert item.quantity == Decimal("3")
    assert item.unit_price == Decimal("20.00")
    assert item.total_price == Decimal("60.00")
    # The `3 x` marker is stripped from the stored name — it's quantity, not product identity.
    assert item.name == "PEPSI"


async def test_implausibly_large_quantity_is_rejected() -> None:
    # A product/HSN/barcode code that happens to end in a unit letter ("8901030 g") must not
    # become the quantity — it would overflow the numeric(8,3) column and fail the receipt.
    receipt = await _parse(
        _line("SUGAR 8901030 g", x=20, row=0),
        _line("55.00", x=320, row=0),
    )

    item = receipt.items[0]
    assert item.quantity == Decimal("1")
    assert item.unit is None


async def test_leading_hsn_code_is_stripped_from_name() -> None:
    receipt = await _parse(
        _line("080112 COCONUT", x=20, row=0),
        _line("25.50", x=320, row=0),
    )
    assert receipt.items[0].name == "COCONUT"


async def test_weighed_item_pulls_kg_out_of_the_name() -> None:
    # 116.50/kg × 1.026 kg = 119.53 — the arithmetic identifies 1.026 as the weight, so it
    # becomes the quantity (kg) instead of being glued to the name.
    receipt = await _parse(
        _line("071320 L KABULI CHANA 1.026", x=20, row=0),
        _line("116.50", x=280, row=0),
        _line("119.53", x=380, row=0),
    )
    item = receipt.items[0]
    assert item.name == "KABULI CHANA"
    assert item.quantity == Decimal("1.026")
    assert item.unit == "kg"
    assert (item.unit_price, item.total_price) == (Decimal("116.50"), Decimal("119.53"))


async def test_counted_item_pulls_count_out_of_the_name() -> None:
    # 25.50 each × 13 = 331.50 → quantity 13, name clean.
    receipt = await _parse(
        _line("080112 COCONUT 13", x=20, row=0),
        _line("25.50", x=280, row=0),
        _line("331.50", x=380, row=0),
    )
    item = receipt.items[0]
    assert item.name == "COCONUT"
    assert item.quantity == Decimal("13")


async def test_pack_size_that_does_not_reconcile_stays_in_the_name() -> None:
    # "200g" is the pack size, not the quantity (89 × 200 ≠ 89); the trailing "1" is the
    # quantity. The pack size stays as part of the product identity.
    receipt = await _parse(
        _line("040610 NANDINI PANEER-200g 1", x=20, row=0),
        _line("89.00", x=360, row=0),
    )
    item = receipt.items[0]
    assert item.name == "NANDINI PANEER-200g"
    assert item.quantity == Decimal("1")


async def test_unit_one_pack_size_stays_in_the_name() -> None:
    # "1 kg" here is the pack size (quantity 1), not a separate quantity, so it stays with
    # the product rather than being pulled out.
    receipt = await _parse(
        _line("SUGAR 1 kg", x=20, row=0),
        _line("55.00", x=320, row=0),
    )

    item = receipt.items[0]
    assert item.name == "SUGAR 1 kg"
    assert item.quantity == Decimal("1")


async def test_embedded_weight_over_one_is_extracted() -> None:
    # "2 kg" reconciles (30.00/kg × 2 = 60.00), so it's the quantity, and the name is clean.
    receipt = await _parse(
        _line("SUGAR 2 kg", x=20, row=0),
        _line("30.00", x=280, row=0),
        _line("60.00", x=380, row=0),
    )

    item = receipt.items[0]
    assert item.name == "SUGAR"
    assert item.quantity == Decimal("2")
    assert item.unit == "kg"


# ---------------------------------------------------------------------------
# Summary rows: excluded from items, folded into totals
# ---------------------------------------------------------------------------
async def test_totals_are_read_and_kept_out_of_items() -> None:
    receipt = await _parse(
        _line("AMUL MILK", x=20, row=0),
        _line("66.00", x=320, row=0),
        _line("SUBTOTAL", x=20, row=1),
        _line("66.00", x=320, row=1),
        _line("CGST", x=20, row=2),
        _line("1.65", x=320, row=2),
        _line("SGST", x=20, row=3),
        _line("1.65", x=320, row=3),
        _line("DISCOUNT", x=20, row=4),
        _line("5.00", x=320, row=4),
        _line("TOTAL", x=20, row=5),
        _line("64.30", x=320, row=5),
    )

    # Only the real purchase is an item — none of the summary lines leak in.
    assert [item.name for item in receipt.items] == ["AMUL MILK"]
    assert receipt.totals.subtotal == Decimal("66.00")
    assert receipt.totals.total == Decimal("64.30")
    assert receipt.totals.discount == Decimal("5.00")
    # CGST + SGST are one tax figure.
    assert receipt.totals.tax == Decimal("3.30")


async def test_repeated_total_takes_the_last() -> None:
    receipt = await _parse(
        _line("TOTAL", x=20, row=0),
        _line("100.00", x=320, row=0),
        _line("TOTAL PAID", x=20, row=1),
        _line("100.00", x=320, row=1),
    )

    assert receipt.totals.total == Decimal("100.00")
    assert receipt.items == []


async def test_row_with_price_but_no_name_is_not_an_item() -> None:
    receipt = await _parse(_line("66.00", x=320, row=0))

    assert receipt.items == []


# ---------------------------------------------------------------------------
# Store, date, time, payment
# ---------------------------------------------------------------------------
async def test_store_name_from_header() -> None:
    receipt = await _parse(
        _line("DMart Supermarket", x=20, row=0),
        _line("AMUL MILK", x=20, row=2),
        _line("66.00", x=320, row=2),
    )

    assert receipt.store.name == "DMart Supermarket"
    assert receipt.store.chain == "DMart Supermarket"


async def test_date_formats() -> None:
    assert (await _parse(_line("Date: 15/06/2025", x=20, row=0))).date == date(2025, 6, 15)
    assert (await _parse(_line("2025-06-15", x=20, row=0))).date == date(2025, 6, 15)
    assert (await _parse(_line("15 Jun 2025", x=20, row=0))).date == date(2025, 6, 15)


async def test_impossible_date_is_ignored() -> None:
    # 45/13 matches the day-first shape but isn't a real date — the parser must not crash or
    # invent one.
    assert (await _parse(_line("Invoice 45/13/2025", x=20, row=0))).date is None


async def test_time_with_meridiem() -> None:
    assert (await _parse(_line("Time 06:42 PM", x=20, row=0))).time == time(18, 42)
    assert (await _parse(_line("18:42", x=20, row=0))).time == time(18, 42)


async def test_payment_method() -> None:
    assert (await _parse(_line("Paid via UPI", x=20, row=0))).payment_method == "UPI"
    assert (await _parse(_line("MASTERCARD ****1234", x=20, row=0))).payment_method == "Card"


# ---------------------------------------------------------------------------
# Categorisation + normalisation
# ---------------------------------------------------------------------------
async def test_category_keyword_mapping() -> None:
    receipt = await _parse(
        _line("Amul Milk", x=20, row=0),
        _line("66.00", x=320, row=0),
        _line("Britannia Bread", x=20, row=1),
        _line("40.00", x=320, row=1),
        _line("Widget XYZ", x=20, row=2),
        _line("10.00", x=320, row=2),
    )

    by_name = {item.name: item for item in receipt.items}
    assert by_name["Amul Milk"].category == "Dairy"
    assert by_name["Britannia Bread"].category == "Bakery"
    # No keyword hit → left uncategorised for the user / LLM fallback, not forced to "Other".
    assert by_name["Widget XYZ"].category is None


async def test_name_normalisation() -> None:
    receipt = await _parse(
        _line("Amul  Taaza (Full-Cream)!", x=20, row=0),
        _line("66.00", x=320, row=0),
    )

    assert receipt.items[0].name_normalised == "amul taaza full cream"


# ---------------------------------------------------------------------------
# Confidence / review flagging
# ---------------------------------------------------------------------------
async def test_low_confidence_item_and_receipt_flagged_for_review() -> None:
    receipt = await _parse(
        _line("BLURRY ITEM", x=20, row=0, conf=0.40),
        _line("99.00", x=320, row=0, conf=0.40),
    )

    assert receipt.items[0].needs_review is True
    assert receipt.needs_review is True
    assert receipt.ocr_confidence < 0.6


async def test_high_confidence_receipt_not_flagged() -> None:
    receipt = await _parse(
        _line("AMUL MILK", x=20, row=0, conf=0.98),
        _line("66.00", x=320, row=0, conf=0.98),
    )

    assert receipt.items[0].needs_review is False
    assert receipt.needs_review is False


async def test_empty_ocr_yields_empty_receipt_flagged_for_review() -> None:
    receipt = await HeuristicReceiptParser().parse(OCRResult(lines=[], provider="test"))

    assert receipt.items == []
    assert receipt.totals.total is None
    assert receipt.date is None
    # Nothing parsed is itself the low-confidence case worth surfacing.
    assert receipt.needs_review is True
    assert receipt.parser_version == PARSER_VERSION


# ---------------------------------------------------------------------------
# A fuller, realistic receipt end-to-end
# ---------------------------------------------------------------------------
async def test_realistic_receipt_end_to_end() -> None:
    receipt = await _parse(
        _line("DMart", x=120, row=0),
        _line("HSR Layout, Bengaluru", x=80, row=1),
        _line("Date: 15/06/2025", x=20, row=2),
        _line("18:42", x=320, row=2),
        _line("Amul Taaza Milk", x=20, row=3),
        _line("62.00", x=280, row=3),
        _line("124.00", x=360, row=3),
        _line("Britannia Bread", x=20, row=4),
        _line("40.00", x=340, row=4),
        _line("SUBTOTAL", x=20, row=5),
        _line("164.00", x=340, row=5),
        _line("TOTAL", x=20, row=6),
        _line("164.00", x=340, row=6),
        _line("Paid via UPI", x=20, row=7),
    )

    assert receipt.store.name == "DMart"
    assert receipt.date == date(2025, 6, 15)
    assert receipt.time == time(18, 42)
    assert receipt.payment_method == "UPI"
    assert [item.name for item in receipt.items] == ["Amul Taaza Milk", "Britannia Bread"]
    milk = receipt.items[0]
    assert (milk.unit_price, milk.total_price) == (Decimal("62.00"), Decimal("124.00"))
    assert milk.category == "Dairy"
    assert receipt.totals.subtotal == Decimal("164.00")
    assert receipt.totals.total == Decimal("164.00")
    assert receipt.parser_version == PARSER_VERSION
