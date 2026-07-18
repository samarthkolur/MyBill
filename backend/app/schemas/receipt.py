"""Receipt schemas."""

from __future__ import annotations

import datetime as dt
from decimal import Decimal
from enum import StrEnum
from uuid import UUID

from pydantic import BaseModel


class ReceiptStatus(StrEnum):
    """Processing lifecycle of a receipt (mirrors the DB CHECK constraint)."""

    PENDING = "pending"
    PROCESSING = "processing"
    DONE = "done"
    FAILED = "failed"


class ReceiptImage(BaseModel):
    """One page of a receipt (``public.receipt_images``).

    ``image_url`` is the Storage object key, not a fetchable URL — short-lived signed URLs
    are minted on read (design decision 19).
    """

    id: UUID
    receipt_id: UUID
    image_url: str
    page_number: int
    created_at: dt.datetime


class ReceiptItem(BaseModel):
    """A parsed line item (``public.receipt_items``) — the bill-detail read model.

    ``category`` is the resolved category *name* (e.g. "Dairy"), not the id, so the client
    can render it without a second lookup. ``needs_review`` flags a low-confidence line for
    the UI to highlight (MyBill.md §6).
    """

    id: UUID
    name: str
    brand: str | None = None
    category: str | None = None
    quantity: Decimal
    unit: str | None = None
    unit_price: Decimal
    total_price: Decimal
    ocr_confidence: float | None = None
    needs_review: bool = False


class ItemSearchResult(BaseModel):
    """A line item matched by search, with the bill it belongs to (MyBill.md §5).

    Carries enough receipt context (store, date, ``receipt_id``) for the client to show a
    useful result row and link back to the full bill.
    """

    id: UUID
    receipt_id: UUID
    name: str
    category: str | None = None
    quantity: Decimal
    unit: str | None = None
    unit_price: Decimal
    total_price: Decimal
    store_name: str | None = None
    date: dt.date | None = None


class Receipt(BaseModel):
    """A receipt with its pages and (once parsed) its summary fields.

    A receipt holds 1..N images (decision 24): the first is created at upload, further
    pages are appended for receipts too long to photograph in one shot. The parsed summary
    fields (store, date, totals) are null until OCR completes; line items are read
    separately via the items endpoint rather than joined onto every list row.
    """

    id: UUID
    status: ReceiptStatus
    created_at: dt.datetime
    # Parsed summary — populated from the row once status is done; null while pending.
    store_name: str | None = None
    date: dt.date | None = None
    time: dt.time | None = None
    total: Decimal | None = None
    tax: Decimal | None = None
    discount: Decimal | None = None
    payment_method: str | None = None
    ocr_confidence: float | None = None
    # Number of parsed line items, for the list view. None when not populated.
    item_count: int | None = None
    # Sum of the line items — an estimate of the bill when OCR found no printed total
    # (e.g. the total was cut off in the photo). Distinct from ``total`` (the printed
    # amount) so the client can label an estimate as such.
    item_total: Decimal | None = None
    # Ordered by page number. A receipt created via upload always has at least one.
    images: list[ReceiptImage] = []

    @property
    def page_count(self) -> int:
        return len(self.images)
