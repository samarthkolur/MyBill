"""OCR result schemas (MyBill.md §8).

The shape every ``OCRProvider`` returns, whatever engine is behind it. Geometry is the
point: a receipt has no ruled table, so the only thing that reconstructs
``ITEM … QTY … AMOUNT`` into a row is where the text sits on the page. Engines detect
those three as separate regions, so the parser regroups them by position.
"""

from __future__ import annotations

from pydantic import BaseModel, Field


class BoundingBox(BaseModel):
    """Axis-aligned box around a detected text region, in pixels.

    Engines return four corner points (which may be rotated); this is the enclosing
    rectangle, which is all the row/column grouping needs.
    """

    x_min: float
    y_min: float
    x_max: float
    y_max: float

    @property
    def center_y(self) -> float:
        """Vertical midpoint — what rows are grouped on."""

        return (self.y_min + self.y_max) / 2

    @property
    def height(self) -> float:
        return self.y_max - self.y_min

    @property
    def width(self) -> float:
        return self.x_max - self.x_min


class OCRLine(BaseModel):
    """One text region the engine detected, with where it was and how sure it is."""

    text: str
    box: BoundingBox
    confidence: float = Field(ge=0.0, le=1.0)


class OCRResult(BaseModel):
    """Everything an engine extracted from one image.

    Deliberately provider-agnostic: no engine-specific fields leak past this boundary, so
    swapping engines can't ripple into the parser. ``provider``/``model`` are carried for
    diagnostics — when a parse looks wrong, the first question is which engine produced it.
    """

    lines: list[OCRLine] = []
    provider: str
    model: str | None = None
    duration_ms: int | None = None

    @property
    def text(self) -> str:
        """All detected text, one region per line, in detection order."""

        return "\n".join(line.text for line in self.lines)

    @property
    def mean_confidence(self) -> float:
        """Average confidence, or 0.0 when nothing was detected.

        A low value is the signal to flag a receipt for review rather than trust the parse.
        """

        if not self.lines:
            return 0.0
        return sum(line.confidence for line in self.lines) / len(self.lines)
