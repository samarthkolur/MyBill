"""OCR engines behind a single interface (MyBill.md §8, DESIGN.md decision 27).

``OCRProvider`` is the seam: the parser and the worker only ever see ``OCRResult``, so the
engine can be swapped without touching them. The concrete implementation is RapidOCR — the
PaddleOCR PP-OCR models exported to ONNX: free, fully offline (no per-page cost, receipts
never leave the host), and ~83MB against PaddlePaddle's multi-GB install.
"""

from __future__ import annotations

import asyncio
import time
from typing import Any, Protocol

from app.core.logging import get_logger
from app.schemas.ocr import BoundingBox, OCRLine, OCRResult

logger = get_logger("app.ocr")


class OCRError(Exception):
    """Raised when an engine fails to process an image at all."""


class OCRProvider(Protocol):
    """Extracts text + geometry + confidence from an image (MyBill.md §8)."""

    async def extract(self, image_bytes: bytes) -> OCRResult: ...


class RapidOCRProvider:
    """RapidOCR (PP-OCR models via onnxruntime).

    The engine is built lazily and reused: construction loads three ONNX models, so doing
    it per receipt would dominate the runtime. Inference is CPU-bound and synchronous, so
    it runs in a thread rather than blocking the event loop — the Celery worker is
    otherwise free to do nothing else while a receipt is being read.
    """

    name = "rapidocr"

    def __init__(self, engine: Any | None = None):
        self._engine = engine
        self._lock = asyncio.Lock()

    async def _get_engine(self) -> Any:
        if self._engine is not None:
            return self._engine
        # Guard construction: two concurrent first-calls would otherwise each load the
        # models, briefly doubling memory for no benefit.
        async with self._lock:
            if self._engine is None:
                self._engine = await asyncio.to_thread(self._build_engine)
        return self._engine

    @staticmethod
    def _build_engine() -> Any:
        try:
            from rapidocr import RapidOCR
        except ImportError as exc:  # pragma: no cover - import guard
            raise OCRError(
                "rapidocr is not installed. Install the 'ocr' dependency group."
            ) from exc
        return RapidOCR()

    async def extract(self, image_bytes: bytes) -> OCRResult:
        """Run detection + recognition over one image."""

        engine = await self._get_engine()
        started = time.perf_counter()
        try:
            raw = await asyncio.to_thread(engine, image_bytes)
        except Exception as exc:
            raise OCRError(f"OCR engine failed: {exc}") from exc
        duration_ms = int((time.perf_counter() - started) * 1000)

        result = OCRResult(
            lines=self._to_lines(raw),
            provider=self.name,
            model="PP-OCRv6",
            duration_ms=duration_ms,
        )
        logger.info(
            "ocr_extracted",
            extra={
                "lines": len(result.lines),
                "mean_confidence": round(result.mean_confidence, 3),
                "duration_ms": duration_ms,
            },
        )
        return result

    @staticmethod
    def _to_lines(raw: Any) -> list[OCRLine]:
        """Map RapidOCR's parallel arrays into engine-agnostic lines.

        A blank image legitimately yields no detections, and the arrays are None rather
        than empty in that case — that's an empty result, not a failure.
        """

        texts = getattr(raw, "txts", None)
        boxes = getattr(raw, "boxes", None)
        scores = getattr(raw, "scores", None)
        if not texts or boxes is None or scores is None:
            return []

        lines: list[OCRLine] = []
        for text, box, score in zip(texts, boxes, scores, strict=False):
            # Each box is 4 corner points and may be rotated; reduce to the enclosing
            # rectangle, which is all the row/column grouping needs.
            xs = [float(p[0]) for p in box]
            ys = [float(p[1]) for p in box]
            lines.append(
                OCRLine(
                    text=str(text).strip(),
                    box=BoundingBox(x_min=min(xs), y_min=min(ys), x_max=max(xs), y_max=max(ys)),
                    # Clamp: a provider returning 1.0000001 shouldn't fail validation.
                    confidence=max(0.0, min(1.0, float(score))),
                )
            )
        return [line for line in lines if line.text]
