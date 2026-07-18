"""Tests for the OCR pipeline orchestrator.

Fakes stand in for each collaborator (storage, OCR, parser, normaliser, repos) so these
assert the *orchestration*: the status transitions, the multi-page stacking handed to the
parser, and that any failure marks the receipt failed and re-raises.
"""

from __future__ import annotations

from typing import Any
from uuid import uuid4

import pytest

from app.schemas.ocr import BoundingBox, OCRLine, OCRResult
from app.schemas.parser import CanonicalReceipt
from app.services.pipeline import PipelineError, ReceiptPipeline

_PARSER_VERSION = "heuristic-0.1.0"


# ---------------------------------------------------------------------------
# Fakes
# ---------------------------------------------------------------------------
class _FakeBucket:
    async def download(self, key: str) -> bytes:
        return key.encode()


class _FakeStorage:
    def __init__(self) -> None:
        self._bucket = _FakeBucket()

    def from_(self, _name: str) -> _FakeBucket:
        return self._bucket


class _FakeClient:
    def __init__(self) -> None:
        self.storage = _FakeStorage()


class _FakeImages:
    def __init__(self, pages: list[dict[str, Any]]) -> None:
        self._pages = pages

    async def list_for_receipt(self, *, receipt_id: Any) -> list[dict[str, Any]]:
        return self._pages


class _FakeReceipts:
    def __init__(self) -> None:
        self.status_updates: list[str] = []

    async def update_fields(
        self, *, receipt_id: Any, user_id: Any, fields: dict[str, Any]
    ) -> dict[str, Any]:
        if "status" in fields:
            self.status_updates.append(fields["status"])
        return {"id": str(receipt_id), **fields}


class _FakeOCR:
    """Returns a queued OCRResult per page; optionally raises."""

    name = "fake-ocr"

    def __init__(self, results: list[OCRResult] | None = None, *, fail: bool = False) -> None:
        self._results = list(results or [])
        self._fail = fail

    async def extract(self, _image_bytes: bytes) -> OCRResult:
        if self._fail:
            raise RuntimeError("ocr exploded")
        return self._results.pop(0)


class _FakeParser:
    """Captures the OCRResult it was handed and returns a preset canonical receipt."""

    def __init__(self, canonical: CanonicalReceipt) -> None:
        self._canonical = canonical
        self.seen: OCRResult | None = None

    async def parse(self, ocr: OCRResult) -> CanonicalReceipt:
        self.seen = ocr
        return self._canonical


class _FakeNormaliser:
    def __init__(self, *, fail: bool = False) -> None:
        self._fail = fail
        self.persisted: list[Any] = []
        self.failed: list[Any] = []

    async def persist(
        self, *, receipt_id: Any, user_id: Any, canonical: CanonicalReceipt
    ) -> dict[str, Any]:
        if self._fail:
            raise RuntimeError("persist failed")
        self.persisted.append(receipt_id)
        return {"status": "done"}

    async def mark_failed(self, *, receipt_id: Any, user_id: Any) -> None:
        self.failed.append(receipt_id)


def _line(text: str, y: float) -> OCRLine:
    box = BoundingBox(x_min=0, y_min=y, x_max=50, y_max=y + 18)
    return OCRLine(text=text, box=box, confidence=0.95)


def _ocr(*lines: OCRLine, provider: str = "fake-ocr") -> OCRResult:
    return OCRResult(lines=list(lines), provider=provider, model="m")


def _canonical() -> CanonicalReceipt:
    return CanonicalReceipt(parser_version=_PARSER_VERSION)


def _pages(n: int) -> list[dict[str, Any]]:
    return [{"image_url": f"u/r/page_{i}.jpg", "page_number": i} for i in range(1, n + 1)]


def _pipeline(
    *,
    pages: list[dict[str, Any]],
    ocr: _FakeOCR,
    parser: _FakeParser,
    normaliser: _FakeNormaliser,
    receipts: _FakeReceipts | None = None,
) -> ReceiptPipeline:
    return ReceiptPipeline(
        client=_FakeClient(),
        images=_FakeImages(pages),  # type: ignore[arg-type]
        receipts=receipts or _FakeReceipts(),  # type: ignore[arg-type]
        ocr=ocr,  # type: ignore[arg-type]
        parser=parser,  # type: ignore[arg-type]
        normaliser=normaliser,  # type: ignore[arg-type]
    )


# ---------------------------------------------------------------------------
# Happy path + status transitions
# ---------------------------------------------------------------------------
async def test_process_runs_stages_and_marks_processing_then_persists() -> None:
    receipts = _FakeReceipts()
    parser = _FakeParser(_canonical())
    normaliser = _FakeNormaliser()
    pipeline = _pipeline(
        pages=_pages(1),
        ocr=_FakeOCR([_ocr(_line("AMUL MILK", 0))]),
        parser=parser,
        normaliser=normaliser,
        receipts=receipts,
    )
    rid, uid = uuid4(), uuid4()

    await pipeline.process(receipt_id=rid, user_id=uid)

    # Marked processing on the way in; persisted (which marks done) at the end; never failed.
    assert receipts.status_updates == ["processing"]
    assert normaliser.persisted == [rid]
    assert normaliser.failed == []


# ---------------------------------------------------------------------------
# Multi-page stacking
# ---------------------------------------------------------------------------
async def test_multiple_pages_are_stacked_vertically_for_the_parser() -> None:
    parser = _FakeParser(_canonical())
    pipeline = _pipeline(
        pages=_pages(2),
        ocr=_FakeOCR([_ocr(_line("PAGE ONE", 10)), _ocr(_line("PAGE TWO", 10))]),
        parser=parser,
        normaliser=_FakeNormaliser(),
    )

    await pipeline.process(receipt_id=uuid4(), user_id=uuid4())

    assert parser.seen is not None
    lines = parser.seen.lines
    # Both pages' text is present, and page two sits below page one — its y was shifted past
    # page one's bottom plus the gap, so row grouping can't merge the two pages.
    assert [line.text for line in lines] == ["PAGE ONE", "PAGE TWO"]
    assert lines[0].box.y_min == 10
    assert lines[1].box.y_min > lines[0].box.y_max


async def test_combined_result_carries_provider_metadata() -> None:
    parser = _FakeParser(_canonical())
    pipeline = _pipeline(
        pages=_pages(1),
        ocr=_FakeOCR([_ocr(_line("X", 0), provider="rapidocr")]),
        parser=parser,
        normaliser=_FakeNormaliser(),
    )

    await pipeline.process(receipt_id=uuid4(), user_id=uuid4())

    assert parser.seen is not None
    assert parser.seen.provider == "rapidocr"


# ---------------------------------------------------------------------------
# Failure paths — all mark failed and re-raise
# ---------------------------------------------------------------------------
async def test_no_pages_marks_failed_and_raises() -> None:
    normaliser = _FakeNormaliser()
    pipeline = _pipeline(
        pages=[],
        ocr=_FakeOCR(),
        parser=_FakeParser(_canonical()),
        normaliser=normaliser,
    )
    rid = uuid4()

    with pytest.raises(PipelineError):
        await pipeline.process(receipt_id=rid, user_id=uuid4())
    assert normaliser.failed == [rid]


async def test_ocr_failure_marks_failed_and_raises() -> None:
    normaliser = _FakeNormaliser()
    pipeline = _pipeline(
        pages=_pages(1),
        ocr=_FakeOCR(fail=True),
        parser=_FakeParser(_canonical()),
        normaliser=normaliser,
    )
    rid = uuid4()

    with pytest.raises(RuntimeError, match="ocr exploded"):
        await pipeline.process(receipt_id=rid, user_id=uuid4())
    assert normaliser.failed == [rid]


async def test_persist_failure_marks_failed_and_raises() -> None:
    normaliser = _FakeNormaliser(fail=True)
    pipeline = _pipeline(
        pages=_pages(1),
        ocr=_FakeOCR([_ocr(_line("X", 0))]),
        parser=_FakeParser(_canonical()),
        normaliser=normaliser,
    )
    rid = uuid4()

    with pytest.raises(RuntimeError, match="persist failed"):
        await pipeline.process(receipt_id=rid, user_id=uuid4())
    assert normaliser.failed == [rid]
