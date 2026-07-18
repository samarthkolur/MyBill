"""Celery worker: the process that actually runs the OCR pipeline (MyBill.md §6, §12).

Started with ``celery -A app.worker worker``. The API enqueues ``process_receipt`` after an
upload; this process consumes it, builds a ``ReceiptPipeline``, and drives the receipt to
``done``/``failed``. Broker and result backend are the shared Redis.

The pipeline's collaborators are synchronous-async: the OCR provider and parser are held as
module-level singletons (building the OCR engine loads ONNX models — doing it per task would
dominate runtime), while the Supabase client is created per task since it's cheap next to
OCR. Each task body bridges into async with ``asyncio.run``.
"""

from __future__ import annotations

import asyncio
from uuid import UUID

from celery import Celery

from app.core.config import get_settings
from app.core.logging import configure_logging, get_logger
from app.integrations.ocr import RapidOCRProvider
from app.integrations.parser import HeuristicReceiptParser
from app.integrations.supabase import create_supabase_client
from app.repositories.parsed import PriceHistoryRepository, ReceiptItemRepository
from app.repositories.receipts import ReceiptImageRepository, ReceiptRepository
from app.repositories.reference import CategoryRepository, StoreRepository
from app.services.normalisation import ReceiptNormaliser
from app.services.pipeline import ReceiptPipeline

logger = get_logger("app.worker")

_settings = get_settings()
configure_logging(level=_settings.log_level, json_output=_settings.log_json)

celery_app = Celery(
    "mybill",
    broker=_settings.celery_broker_url,
    backend=_settings.celery_result_backend,
)
celery_app.conf.update(
    task_track_started=True,
    # One receipt at a time per worker process — OCR is CPU-bound, so prefetching more just
    # ties up receipts behind a busy worker.
    worker_prefetch_multiplier=1,
    task_acks_late=True,
)

# Built once and reused across tasks in this long-lived process. The OCR engine loads its
# models lazily on first use, so importing this module (e.g. by the API to enqueue) stays cheap.
_ocr = RapidOCRProvider()
_parser = HeuristicReceiptParser()


@celery_app.task(name="process_receipt")
def process_receipt(receipt_id: str, user_id: str) -> None:
    """Run the OCR pipeline for one receipt. Idempotent — safe to re-run for the same id."""

    asyncio.run(_process(UUID(receipt_id), UUID(user_id)))


async def _process(receipt_id: UUID, user_id: UUID) -> None:
    client = await create_supabase_client(get_settings())
    normaliser = ReceiptNormaliser(
        receipts=ReceiptRepository(client),
        stores=StoreRepository(client),
        categories=CategoryRepository(client),
        items=ReceiptItemRepository(client),
        prices=PriceHistoryRepository(client),
    )
    pipeline = ReceiptPipeline(
        client=client,
        images=ReceiptImageRepository(client),
        receipts=ReceiptRepository(client),
        ocr=_ocr,
        parser=_parser,
        normaliser=normaliser,
    )
    await pipeline.process(receipt_id=receipt_id, user_id=user_id)
