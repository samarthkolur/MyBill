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


class Receipt(BaseModel):
    """A receipt row as returned to clients right after upload.

    Parsed fields (store, date, totals, items) are absent until OCR completes and are
    added to the read models in Phase 2/3.
    """

    id: UUID
    status: ReceiptStatus
    image_url: str
    created_at: datetime
