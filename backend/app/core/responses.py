"""Standard API response envelope (MyBill.md §5).

Every endpoint returns the same shape so clients (and the Flutter Dio layer) can parse
responses uniformly::

    {
      "success": true,
      "data": { ... } | null,
      "meta": { "request_id": "uuid", "page": 1, "total": 42 } | null,
      "error": { "code": "not_found", "message": "..." } | null
    }

Helpers here build that envelope; the ``request_id`` is filled in automatically from
the logging context so callers never have to thread it through by hand.
"""

from __future__ import annotations

from pydantic import BaseModel

from app.core.logging import request_id_ctx


class Meta(BaseModel):
    """Envelope metadata. ``page``/``total`` are only set on paginated responses."""

    request_id: str | None = None
    page: int | None = None
    total: int | None = None


class ErrorDetail(BaseModel):
    """Machine-readable error payload."""

    code: str
    message: str


class ApiResponse[T](BaseModel):
    """The uniform response envelope returned by every endpoint."""

    success: bool
    data: T | None = None
    meta: Meta | None = None
    error: ErrorDetail | None = None


def success[T](
    data: T | None = None,
    *,
    page: int | None = None,
    total: int | None = None,
) -> ApiResponse[T]:
    """Build a success envelope, stamping the current request id into ``meta``."""

    return ApiResponse[T](
        success=True,
        data=data,
        meta=Meta(request_id=request_id_ctx.get(), page=page, total=total),
        error=None,
    )


def error(code: str, message: str) -> ApiResponse[None]:
    """Build an error envelope, stamping the current request id into ``meta``."""

    return ApiResponse[None](
        success=False,
        data=None,
        meta=Meta(request_id=request_id_ctx.get()),
        error=ErrorDetail(code=code, message=message),
    )
