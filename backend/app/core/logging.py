"""Structured application logging.

Provides a single ``configure_logging()`` entrypoint and a ``request_id`` context
variable that is stamped onto every log record. In deployed environments logs are
emitted as one JSON object per line (machine-parseable for Sentry / log aggregation,
per MyBill.md §12); locally they render as readable console lines.

No PII is logged by this module. Callers must not pass receipt totals or item names
into log messages (MyBill.md §11 — "No PII logged in application logs").
"""

from __future__ import annotations

import json
import logging
import sys
from contextvars import ContextVar
from typing import Any

# Per-request correlation id, populated by RequestContextMiddleware and surfaced in
# both the response envelope's ``meta.request_id`` and every log line for that request.
request_id_ctx: ContextVar[str | None] = ContextVar("request_id", default=None)

_RESERVED_RECORD_KEYS = frozenset(logging.LogRecord("", 0, "", 0, "", (), None).__dict__)


class RequestIdFilter(logging.Filter):
    """Attach the current request id (if any) to every log record."""

    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = request_id_ctx.get()
        return True


class JsonFormatter(logging.Formatter):
    """Render log records as single-line JSON objects."""

    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "timestamp": self.formatTime(record, "%Y-%m-%dT%H:%M:%S%z"),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
            "request_id": getattr(record, "request_id", None),
        }
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)

        # Include any structured ``extra={...}`` fields the caller attached.
        for key, value in record.__dict__.items():
            if key not in _RESERVED_RECORD_KEYS and key not in payload:
                payload[key] = value

        return json.dumps(payload, default=str)


class ConsoleFormatter(logging.Formatter):
    """Human-readable single-line formatter for local development."""

    _FMT = "%(asctime)s %(levelname)-7s [%(request_id)s] %(name)s: %(message)s"

    def __init__(self) -> None:
        super().__init__(fmt=self._FMT, datefmt="%H:%M:%S")

    def format(self, record: logging.LogRecord) -> str:
        if getattr(record, "request_id", None) is None:
            record.request_id = "-"
        return super().format(record)


def configure_logging(*, level: str = "INFO", json_output: bool = False) -> None:
    """Configure the root logger. Idempotent — safe to call more than once.

    Args:
        level: Minimum log level (e.g. ``"INFO"``, ``"DEBUG"``).
        json_output: Emit JSON lines when ``True``, console format otherwise.
    """

    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter() if json_output else ConsoleFormatter())
    handler.addFilter(RequestIdFilter())

    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(level.upper())

    # Let uvicorn's access/error logs flow through our handler instead of its own.
    for name in ("uvicorn", "uvicorn.access", "uvicorn.error"):
        logger = logging.getLogger(name)
        logger.handlers.clear()
        logger.propagate = True


def get_logger(name: str) -> logging.Logger:
    """Return a module-scoped logger. Thin wrapper for a consistent import site."""

    return logging.getLogger(name)
