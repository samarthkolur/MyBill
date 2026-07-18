"""Canonical receipt schemas — the parser's output (MyBill.md §6, Stage 3).

``CanonicalReceipt`` is the engine-agnostic, structured shape an OCR'd receipt is reduced
to *before* it touches the database. It sits behind the ``ReceiptParser`` seam exactly as
``OCRResult`` sits behind ``OCRProvider``: the normalisation layer (Stage 4) and the worker
only ever see this, so the parsing strategy can change without rippling outward.

Money is ``Decimal`` throughout — a receipt total reconciled with float arithmetic drifts by
a paisa and stops matching the printed total. Categories are carried as *names* here, not
``categories.id``: resolving a name to a UUID is a database concern that belongs to Stage 4,
and keeping it a name lets the parser stay ignorant of what's seeded in the table.
"""

from __future__ import annotations

import datetime as dt
from decimal import Decimal

from pydantic import BaseModel, Field

# A receipt (or item) at or below this OCR confidence is surfaced for manual correction
# rather than trusted silently (MyBill.md §6, "Low confidence (<0.6)").
REVIEW_CONFIDENCE_THRESHOLD = 0.6


class CanonicalStore(BaseModel):
    """The store a receipt came from, as read off the header.

    Every field is optional: a crumpled or partial photo may yield no legible header, and a
    receipt with unreadable store details is still worth parsing for its line items. ``chain``
    is the alias-resolved canonical name (``D-MART`` → ``DMart``); until Stage 4's alias table
    resolves it, it mirrors ``name``.
    """

    name: str | None = None
    address: str | None = None
    chain: str | None = None


class CanonicalTotals(BaseModel):
    """The money summary block. All optional — a missing total is a flagged partial parse,
    not a failure (MyBill.md §6, "Missing total")."""

    subtotal: Decimal | None = None
    tax: Decimal | None = None
    discount: Decimal | None = None
    total: Decimal | None = None


class CanonicalItem(BaseModel):
    """One parsed line item, in the shape ``receipt_items`` will be filled from.

    ``quantity`` defaults to 1: most grocery lines are a single unit with no printed
    quantity, and a line that reads only ``AMUL MILK 1L … 66.00`` is one unit at 66.00.
    """

    name: str
    name_normalised: str
    brand: str | None = None
    category: str | None = None  # category *name*, resolved to an id at Stage 4
    quantity: Decimal = Decimal(1)
    unit: str | None = None
    unit_price: Decimal
    total_price: Decimal
    ocr_confidence: float | None = Field(default=None, ge=0.0, le=1.0)
    # True when this item's confidence is below the review threshold — the DB write keeps it,
    # but the UI highlights it for the user to confirm.
    needs_review: bool = False


class CanonicalReceipt(BaseModel):
    """The whole receipt, structured. The unit the normalisation layer consumes.

    ``ocr_confidence`` is the receipt-level score (mean over line items, or the raw OCR mean
    when nothing parsed). ``needs_review`` rolls up the receipt: true when the overall score
    is low or any item needs review, so the caller can flag the receipt without re-inspecting
    every line. ``parser_version`` is stamped so a bad parse can be traced to the exact
    heuristic that produced it.
    """

    store: CanonicalStore = CanonicalStore()
    date: dt.date | None = None
    time: dt.time | None = None
    payment_method: str | None = None
    totals: CanonicalTotals = CanonicalTotals()
    items: list[CanonicalItem] = []
    ocr_confidence: float = Field(default=0.0, ge=0.0, le=1.0)
    needs_review: bool = False
    parser_version: str
