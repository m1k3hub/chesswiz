"""Structured JSON logging with request-id correlation (Phase 2 observability).

- ``configure_logging()`` installs structlog with a JSON renderer when
  structlog is installed; otherwise it falls back to stdlib logging with the
  request id injected via a ``logging.Filter``.
- ``RequestIdMiddleware`` (pure ASGI) propagates or generates an
  ``X-Request-ID`` per request, exposes it through ``get_request_id()``, and
  adds it to every response.
- ``RequestLoggingMiddleware`` emits one structured access-log line per HTTP
  request (method, path, status, duration).
- ``init_sentry()`` enables Sentry error tracking when ``SENTRY_DSN`` is set
  and ``sentry-sdk`` is installed.

Environment variables:
    SCIDB_LOG_LEVEL             Log level (default INFO)
    SENTRY_DSN                  Sentry DSN (empty = disabled)
    SENTRY_TRACES_SAMPLE_RATE   Sentry traces sample rate (default 0.1)
    SCIDB_ENV                   Deployment environment label (default development)
"""

from __future__ import annotations

import contextvars
import logging
import os
import sys
import time
import uuid
from typing import Any

_request_id_var: contextvars.ContextVar[str] = contextvars.ContextVar(
    "scidb_request_id", default=""
)


def get_request_id() -> str:
    """Return the request id bound to the current context (or "")."""
    return _request_id_var.get()


def _structlog_available() -> bool:
    try:
        import structlog  # noqa: F401
        return True
    except ImportError:
        return False


def _add_request_id_processor(logger: Any, method: str, event_dict: dict) -> dict:
    rid = get_request_id()
    if rid:
        event_dict.setdefault("request_id", rid)
    return event_dict


class _RequestIdFilter(logging.Filter):
    """Inject the current request id into stdlib log records."""

    def filter(self, record: logging.LogRecord) -> bool:
        record.request_id = get_request_id() or "-"  # type: ignore[attr-defined]
        return True


_configured = False


def configure_logging(level: str | None = None) -> None:
    """Configure process-wide logging. Idempotent."""
    global _configured
    if _configured:
        return
    _configured = True

    level_name = (level or os.environ.get("SCIDB_LOG_LEVEL", "INFO")).upper()
    level_num = getattr(logging, level_name, logging.INFO)

    if _structlog_available():
        import structlog

        structlog.configure(
            processors=[
                structlog.contextvars.merge_contextvars,
                structlog.processors.add_log_level,
                structlog.processors.TimeStamper(fmt="iso", utc=True),
                _add_request_id_processor,
                structlog.processors.StackInfoRenderer(),
                structlog.processors.format_exc_info,
                structlog.processors.JSONRenderer(),
            ],
            wrapper_class=structlog.make_filtering_bound_logger(level_num),
            logger_factory=structlog.PrintLoggerFactory(sys.stdout),
            cache_logger_on_first_use=True,
        )
        # Route stdlib logging (uvicorn, sqlalchemy, ...) through structlog's
        # JSON renderer as well so the whole process emits one format.
        root = logging.getLogger()
        root.handlers.clear()
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(
            structlog.stdlib.ProcessorFormatter(
                foreign_pre_chain=[
                    structlog.stdlib.add_log_level,
                    structlog.stdlib.add_logger_name,
                    structlog.processors.TimeStamper(fmt="iso", utc=True),
                    _add_request_id_processor,
                ],
                processors=[
                    structlog.stdlib.ProcessorFormatter.remove_processors_meta,
                    structlog.processors.JSONRenderer(),
                ],
            )
        )
        root.addHandler(handler)
        root.setLevel(level_num)
    else:
        root = logging.getLogger()
        root.handlers.clear()
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(
            logging.Formatter(
                '{"ts":"%(asctime)s","level":"%(levelname)s","logger":"%(name)s",'
                '"request_id":"%(request_id)s","msg":%(message)s}',
            )
        )

        class _JsonMessageFilter(logging.Filter):
            """Best-effort JSON quoting of the stdlib log message."""

            def filter(self, record: logging.LogRecord) -> bool:
                import json as _json
                try:
                    msg = record.getMessage()
                except Exception:
                    msg = str(record.msg)
                record.message = _json.dumps(msg, ensure_ascii=False)  # type: ignore[attr-defined]
                record.msg = record.message
                record.args = ()
                return True

        handler.addFilter(_RequestIdFilter())
        handler.addFilter(_JsonMessageFilter())
        root.addHandler(handler)
        root.setLevel(level_num)


def get_logger(name: str | None = None) -> Any:
    """Return a structured logger (structlog) or stdlib logger fallback."""
    if _structlog_available():
        import structlog
        return structlog.get_logger(name) if name else structlog.get_logger()
    return logging.getLogger(name or "scidb")


class RequestIdMiddleware:
    """Pure-ASGI middleware that binds an X-Request-ID to each request.

    Reads the inbound ``X-Request-ID`` header when present, otherwise
    generates a UUID4 hex id. The id is bound to a contextvar (and to
    structlog's contextvars when available) and echoed on the response.
    """

    def __init__(self, app: Any, header_name: str = "x-request-id") -> None:
        self.app = app
        self.header_name = header_name

    async def __call__(self, scope: dict, receive: Any, send: Any) -> None:
        if scope.get("type") not in ("http", "websocket"):
            await self.app(scope, receive, send)
            return

        request_id = ""
        for key, value in scope.get("headers", []):
            if key.decode("latin-1").lower() == self.header_name:
                request_id = value.decode("latin-1")
                break
        if not request_id:
            request_id = uuid.uuid4().hex

        token = _request_id_var.set(request_id)
        structlog_bound = False
        if _structlog_available():
            import structlog
            structlog.contextvars.bind_contextvars(request_id=request_id)
            structlog_bound = True

        async def send_with_request_id(message: dict) -> None:
            if message.get("type") == "http.response.start":
                headers = message.setdefault("headers", [])
                headers.append((self.header_name.encode("latin-1"), request_id.encode("latin-1")))
            await send(message)

        try:
            await self.app(scope, receive, send_with_request_id)
        finally:
            if structlog_bound:
                import structlog
                structlog.contextvars.unbind_contextvars("request_id")
            _request_id_var.reset(token)


class RequestLoggingMiddleware:
    """Pure-ASGI access-log middleware (one structured line per request)."""

    def __init__(self, app: Any, *, logger_name: str = "scidb.access", skip_paths: frozenset[str] = frozenset({"/metrics"})) -> None:
        self.app = app
        self.log = get_logger(logger_name)
        self.skip_paths = skip_paths

    async def __call__(self, scope: dict, receive: Any, send: Any) -> None:
        if scope.get("type") != "http":
            await self.app(scope, receive, send)
            return

        start = time.perf_counter()
        status = 500

        async def send_wrapped(message: dict) -> None:
            nonlocal status
            if message.get("type") == "http.response.start":
                status = message.get("status", 500)
            await send(message)

        try:
            await self.app(scope, receive, send_wrapped)
        finally:
            path = scope.get("path", "")
            if path not in self.skip_paths:
                duration_ms = round((time.perf_counter() - start) * 1000, 2)
                method = scope.get("method", "?")
                if hasattr(self.log, "bind"):  # structlog
                    self.log.info(
                        "http.request",
                        method=method,
                        path=path,
                        status=status,
                        duration_ms=duration_ms,
                    )
                else:  # stdlib
                    self.log.info(
                        "http.request method=%s path=%s status=%s duration_ms=%s",
                        method, path, status, duration_ms,
                    )


def init_sentry() -> bool:
    """Initialise Sentry error tracking when SENTRY_DSN is configured.

    Returns True when Sentry was initialised, False otherwise. Never raises:
    a misconfigured Sentry must not prevent startup.
    """
    dsn = os.environ.get("SENTRY_DSN", "")
    if not dsn:
        return False
    try:
        import sentry_sdk
        from sentry_sdk.integrations.fastapi import FastApiIntegration
        from sentry_sdk.integrations.starlette import StarletteIntegration
    except ImportError:
        logging.getLogger(__name__).warning(
            "SENTRY_DSN is set but sentry-sdk is not installed; error tracking disabled"
        )
        return False
    try:
        sentry_sdk.init(
            dsn=dsn,
            environment=os.environ.get("SCIDB_ENV", "development"),
            traces_sample_rate=float(os.environ.get("SENTRY_TRACES_SAMPLE_RATE", "0.1")),
            integrations=[StarletteIntegration(), FastApiIntegration()],
            send_default_pii=False,
        )
        return True
    except Exception as exc:  # pragma: no cover - defensive
        logging.getLogger(__name__).warning("sentry init failed: %s", exc)
        return False
