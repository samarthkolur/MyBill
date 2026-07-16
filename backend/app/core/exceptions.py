"""Application exceptions and their HTTP handlers.

Any error that reaches the client is rendered through the same response envelope
(``app.core.responses.error``) so failures are as uniform as successes. Unhandled
exceptions are caught, logged with a traceback, and returned as a generic 500 that
never leaks internal detail to the client.
"""

from __future__ import annotations

from fastapi import FastAPI, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.core.logging import get_logger
from app.core.responses import error

logger = get_logger("app.error")


class AppError(Exception):
    """Base class for expected, client-facing application errors.

    Raise a subclass (or this directly) anywhere in the service layer; the registered
    handler turns it into a well-formed error envelope with the right status code.
    """

    status_code: int = status.HTTP_400_BAD_REQUEST
    code: str = "app_error"

    def __init__(self, message: str, *, code: str | None = None, status_code: int | None = None):
        super().__init__(message)
        self.message = message
        if code is not None:
            self.code = code
        if status_code is not None:
            self.status_code = status_code


class NotFoundError(AppError):
    status_code = status.HTTP_404_NOT_FOUND
    code = "not_found"


class UnauthorizedError(AppError):
    status_code = status.HTTP_401_UNAUTHORIZED
    code = "unauthorized"


class ForbiddenError(AppError):
    status_code = status.HTTP_403_FORBIDDEN
    code = "forbidden"


def _envelope(status_code: int, code: str, message: str) -> JSONResponse:
    return JSONResponse(
        status_code=status_code,
        content=error(code=code, message=message).model_dump(),
    )


def register_exception_handlers(app: FastAPI) -> None:
    """Attach envelope-producing handlers for app, HTTP, validation, and 500 errors."""

    @app.exception_handler(AppError)
    async def _handle_app_error(_: Request, exc: AppError) -> JSONResponse:
        return _envelope(exc.status_code, exc.code, exc.message)

    @app.exception_handler(StarletteHTTPException)
    async def _handle_http_error(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        detail = exc.detail if isinstance(exc.detail, str) else "HTTP error"
        return _envelope(exc.status_code, f"http_{exc.status_code}", detail)

    @app.exception_handler(RequestValidationError)
    async def _handle_validation_error(_: Request, exc: RequestValidationError) -> JSONResponse:
        # Summarise field errors without echoing submitted values (may contain PII).
        fields = (
            ", ".join(".".join(str(p) for p in e["loc"][1:]) for e in exc.errors()) or "request"
        )
        return _envelope(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "validation_error",
            f"Validation failed for: {fields}",
        )

    @app.exception_handler(Exception)
    async def _handle_unexpected_error(_: Request, exc: Exception) -> JSONResponse:
        logger.exception("unhandled_exception", extra={"error_type": type(exc).__name__})
        return _envelope(
            status.HTTP_500_INTERNAL_SERVER_ERROR,
            "internal_error",
            "An unexpected error occurred.",
        )
