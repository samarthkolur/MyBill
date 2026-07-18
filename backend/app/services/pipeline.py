"""The OCR pipeline, chained end to end (MyBill.md §6).

``ReceiptPipeline`` takes a ``pending`` receipt of uploaded page images and drives it to
``done``: mark it ``processing``, OCR every page, parse the combined text into a
``CanonicalReceipt``, and normalise that into the database. Each stage is its own swappable
component (``OCRProvider``, ``ReceiptParser``, ``ReceiptNormaliser``); this is the
orchestration that wires them into one flow, and it's what the Celery task runs.

The whole thing is idempotent: re-running for a receipt id OCRs the same images and
normalises onto the same rows (the item/price writes replace by receipt id), so a retry
converges rather than duplicating. Image pre-processing (deskew/binarise, MyBill.md §6
Stage 1) is not in the chain yet — it slots in ahead of OCR when it lands.
"""

from __future__ import annotations

from typing import Any
from uuid import UUID

from app.core.logging import get_logger
from app.integrations.ocr import OCRProvider
from app.integrations.parser import ReceiptParser
from app.repositories.receipts import ReceiptImageRepository, ReceiptRepository
from app.schemas.ocr import BoundingBox, OCRLine, OCRResult
from app.schemas.receipt import ReceiptStatus
from app.services.normalisation import ReceiptNormaliser

logger = get_logger("app.pipeline")

_BUCKET = "receipts"

# Vertical gap inserted between one page's text and the next when stacking a multi-page
# receipt into a single OCRResult, so the parser's row grouping never merges the bottom of
# one page with the top of the next.
_PAGE_GAP = 200.0


class PipelineError(Exception):
    """A receipt could not be processed (no pages, OCR failure, parse/persist error)."""


class ReceiptPipeline:
    """Runs upload → OCR → parse → normalise for one receipt."""

    def __init__(
        self,
        *,
        client: Any,
        images: ReceiptImageRepository,
        receipts: ReceiptRepository,
        ocr: OCRProvider,
        parser: ReceiptParser,
        normaliser: ReceiptNormaliser,
        bucket: str = _BUCKET,
    ):
        self._client = client
        self._images = images
        self._receipts = receipts
        self._ocr = ocr
        self._parser = parser
        self._normaliser = normaliser
        self._bucket = bucket

    async def process(self, *, receipt_id: UUID, user_id: UUID) -> None:
        """Drive one receipt from ``pending`` to ``done`` (or ``failed`` on any error)."""

        await self._receipts.update_fields(
            receipt_id=receipt_id,
            user_id=user_id,
            fields={"status": ReceiptStatus.PROCESSING.value},
        )
        try:
            pages = await self._images.list_for_receipt(receipt_id=receipt_id)
            if not pages:
                raise PipelineError(f"Receipt {receipt_id} has no pages to process.")

            ocr_result = await self._ocr_pages(pages)
            canonical = await self._parser.parse(ocr_result)
            await self._normaliser.persist(
                receipt_id=receipt_id, user_id=user_id, canonical=canonical
            )
            logger.info(
                "receipt_processed",
                extra={
                    "receipt_id": str(receipt_id),
                    "pages": len(pages),
                    "lines": len(ocr_result.lines),
                    "items": len(canonical.items),
                },
            )
        except Exception:
            # Any failure leaves a durable trail: the receipt is marked failed (MyBill.md §6)
            # so the user sees it didn't parse, rather than a receipt stuck in processing.
            logger.exception("receipt_processing_failed", extra={"receipt_id": str(receipt_id)})
            await self._normaliser.mark_failed(receipt_id=receipt_id, user_id=user_id)
            raise

    async def _ocr_pages(self, pages: list[dict[str, Any]]) -> OCRResult:
        """OCR every page and stack the results into one OCRResult.

        A multi-page receipt is one logical bill, so the pages are concatenated vertically —
        each page's boxes are shifted down past the previous page — and parsed as a single
        document. Pages are processed in the order the repository returns them (page number).
        """

        combined: list[OCRLine] = []
        provider = getattr(self._ocr, "name", "unknown")
        model: str | None = None
        y_offset = 0.0

        for page in pages:
            data = await self._download(str(page["image_url"]))
            result = await self._ocr.extract(data)
            provider, model = result.provider, result.model
            for line in result.lines:
                box = line.box
                combined.append(
                    OCRLine(
                        text=line.text,
                        confidence=line.confidence,
                        box=BoundingBox(
                            x_min=box.x_min,
                            x_max=box.x_max,
                            y_min=box.y_min + y_offset,
                            y_max=box.y_max + y_offset,
                        ),
                    )
                )
            page_bottom = max((line.box.y_max for line in result.lines), default=0.0)
            y_offset += page_bottom + _PAGE_GAP

        return OCRResult(lines=combined, provider=provider, model=model)

    async def _download(self, object_key: str) -> bytes:
        """Fetch a page's bytes from the private Storage bucket."""

        data = await self._client.storage.from_(self._bucket).download(object_key)
        return bytes(data)
