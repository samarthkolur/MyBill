"""Tests for the OCR provider boundary.

Uses a fake engine: the real one loads ONNX models and takes seconds per image, which
would make the suite slow and dependent on the `ocr` dependency group being installed.
What matters here is the mapping into `OCRResult`, not that PP-OCR can read.
"""

from __future__ import annotations

from typing import Any

import pytest

from app.integrations.ocr import OCRError, RapidOCRProvider
from app.schemas.ocr import BoundingBox, OCRLine, OCRResult


class _FakeRaw:
    """Mimics RapidOCR's result object: parallel txts/boxes/scores arrays."""

    def __init__(self, txts: Any, boxes: Any, scores: Any) -> None:
        self.txts = txts
        self.boxes = boxes
        self.scores = scores


def _box(x_min: float, y_min: float, x_max: float, y_max: float) -> list[list[float]]:
    """Four corner points, the shape the engine actually returns."""

    return [[x_min, y_min], [x_max, y_min], [x_max, y_max], [x_min, y_max]]


class _FakeEngine:
    def __init__(self, raw: Any = None, fail: bool = False) -> None:
        self.raw = raw
        self.fail = fail
        self.calls = 0

    def __call__(self, image_bytes: bytes) -> Any:
        self.calls += 1
        if self.fail:
            raise RuntimeError("engine exploded")
        return self.raw


async def test_maps_engine_output_into_ocr_result() -> None:
    raw = _FakeRaw(
        txts=["AMUL MILK 1L", "66.00"],
        boxes=[_box(26, 300, 150, 318), _box(300, 301, 380, 319)],
        scores=[0.99, 1.0],
    )
    result = await RapidOCRProvider(engine=_FakeEngine(raw)).extract(b"jpeg")

    assert result.provider == "rapidocr"
    assert len(result.lines) == 2
    assert result.lines[0].text == "AMUL MILK 1L"
    # Geometry survives the boundary — the parser has nothing to group rows on without it.
    assert result.lines[0].box.x_min == 26
    assert result.lines[0].box.center_y == pytest.approx(309)
    assert result.duration_ms is not None


async def test_rotated_box_reduces_to_enclosing_rectangle() -> None:
    # A skewed photo yields a rotated quad; the parser only needs the bounding rect.
    raw = _FakeRaw(
        txts=["TOTAL"],
        boxes=[[[10.0, 50.0], [90.0, 44.0], [92.0, 70.0], [12.0, 76.0]]],
        scores=[0.95],
    )
    result = await RapidOCRProvider(engine=_FakeEngine(raw)).extract(b"jpeg")

    box = result.lines[0].box
    assert (box.x_min, box.x_max) == (10.0, 92.0)
    assert (box.y_min, box.y_max) == (44.0, 76.0)


async def test_blank_image_is_an_empty_result_not_an_error() -> None:
    # RapidOCR returns None arrays when it detects nothing. That's a blank photo, not a
    # failure — the caller decides what to do with zero lines.
    result = await RapidOCRProvider(engine=_FakeEngine(_FakeRaw(None, None, None))).extract(b"jpeg")

    assert result.lines == []
    assert result.mean_confidence == 0.0
    assert result.text == ""


async def test_engine_failure_raises_ocr_error() -> None:
    with pytest.raises(OCRError, match="OCR engine failed"):
        await RapidOCRProvider(engine=_FakeEngine(fail=True)).extract(b"jpeg")


async def test_engine_is_reused_across_calls() -> None:
    # Building the engine loads three ONNX models; doing it per receipt would dominate.
    engine = _FakeEngine(_FakeRaw(["X"], [_box(0, 0, 1, 1)], [0.9]))
    provider = RapidOCRProvider(engine=engine)
    await provider.extract(b"a")
    await provider.extract(b"b")

    assert engine.calls == 2


async def test_confidence_out_of_range_is_clamped() -> None:
    raw = _FakeRaw(["X"], [_box(0, 0, 1, 1)], [1.0000001])
    result = await RapidOCRProvider(engine=_FakeEngine(raw)).extract(b"jpeg")

    # Pydantic would reject >1.0; a provider's float noise shouldn't fail the receipt.
    assert result.lines[0].confidence == 1.0


async def test_empty_text_regions_are_dropped() -> None:
    raw = _FakeRaw(
        txts=["REAL", "   "],
        boxes=[_box(0, 0, 1, 1), _box(0, 2, 1, 3)],
        scores=[0.9, 0.5],
    )
    result = await RapidOCRProvider(engine=_FakeEngine(raw)).extract(b"jpeg")

    assert [line.text for line in result.lines] == ["REAL"]


def test_mean_confidence_and_text_helpers() -> None:
    result = OCRResult(
        provider="test",
        lines=[
            OCRLine(text="A", box=BoundingBox(x_min=0, y_min=0, x_max=1, y_max=1), confidence=0.8),
            OCRLine(text="B", box=BoundingBox(x_min=0, y_min=2, x_max=1, y_max=3), confidence=1.0),
        ],
    )

    assert result.text == "A\nB"
    assert result.mean_confidence == pytest.approx(0.9)
