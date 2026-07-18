"""The seam between the API and the Celery worker.

The upload service needs to *kick off* background processing without depending on Celery
directly — that keeps the service unit-testable with a fake queue and keeps the (heavy)
worker module out of the API's import path. ``TaskQueue`` is that seam; ``CeleryTaskQueue``
is the real implementation, which lazily imports the Celery task only when it actually
enqueues.
"""

from __future__ import annotations

from typing import Protocol
from uuid import UUID

from app.core.logging import get_logger

logger = get_logger("app.tasks")


class TaskQueue(Protocol):
    """Enqueues background work for the OCR pipeline."""

    def enqueue_receipt_processing(self, *, receipt_id: UUID, user_id: UUID) -> None: ...


class CeleryTaskQueue:
    """Hands a receipt to the Celery worker via the ``process_receipt`` task."""

    def enqueue_receipt_processing(self, *, receipt_id: UUID, user_id: UUID) -> None:
        # Imported lazily: the worker module builds the Celery app (and holds the OCR
        # provider), which the API process should neither import nor initialise at startup.
        from app.worker import process_receipt

        process_receipt.delay(str(receipt_id), str(user_id))
        logger.info("receipt_processing_enqueued", extra={"receipt_id": str(receipt_id)})
