"""Receipt schemas."""

from __future__ import annotations

from datetime import datetime
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
    created_at: datetime


class Receipt(BaseModel):
    """A receipt and its pages.

    A receipt holds 1..N images (decision 24): the first is created at upload, further
    pages are appended for receipts too long to photograph in one shot. Parsed fields
    (store, date, totals, items) are absent until OCR completes and are added to the read
    models in Phase 2/3.
    """

    id: UUID
    status: ReceiptStatus
    created_at: datetime
    # Ordered by page number. A receipt created via upload always has at least one.
    images: list[ReceiptImage] = []

    @property
    def page_count(self) -> int:
        return len(self.images)
