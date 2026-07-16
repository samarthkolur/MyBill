"""HTTP middleware for cross-cutting request concerns."""

from __future__ import annotations

import time
import uuid
from collections.abc import Awaitable, Callable

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from app.core.logging import get_logger, request_id_ctx

logger = get_logger("app.request")

REQUEST_ID_HEADER = "X-Request-ID"

_NextCall = Callable[[Request], Awaitable[Response]]


class RequestContextMiddleware(BaseHTTPMiddleware):
    """Assign a request id, expose it to logs + responses, and log access lines.

    - Reuses an inbound ``X-Request-ID`` header if the client sent one (useful for
      tracing a mobile request end-to-end), otherwise generates a UUID4.
    - Publishes the id into the logging ``ContextVar`` so every log line for this
      request is correlated, and echoes it back in the response header.
    - Emits one structured access log per request with method, path, status, and
      duration. No query strings or bodies are logged (may contain PII).
    """

    async def dispatch(self, request: Request, call_next: _NextCall) -> Response:
        request_id = request.headers.get(REQUEST_ID_HEADER) or str(uuid.uuid4())
        token = request_id_ctx.set(request_id)
        start = time.perf_counter()

        try:
            response = await call_next(request)
        except Exception:
            duration_ms = (time.perf_counter() - start) * 1000
            logger.exception(
                "request_failed",
                extra={
                    "method": request.method,
                    "path": request.url.path,
                    "duration_ms": round(duration_ms, 2),
                },
            )
            raise
        else:
            duration_ms = (time.perf_counter() - start) * 1000
            response.headers[REQUEST_ID_HEADER] = request_id
            logger.info(
                "request_completed",
                extra={
                    "method": request.method,
                    "path": request.url.path,
                    "status_code": response.status_code,
                    "duration_ms": round(duration_ms, 2),
                },
            )
            return response
        finally:
            request_id_ctx.reset(token)
