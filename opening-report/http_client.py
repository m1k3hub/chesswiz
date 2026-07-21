"""Shared asynchronous HTTP client with connection pooling and retries.

Phase 2 (performance hardening): replaces per-request ``httpx.AsyncClient``
construction in runtime_adapter.py with a single lifecycle-managed client.

Environment variables:
    SCIDB_HTTP_MAX_CONNECTIONS   Total connection pool size (default 100)
    SCIDB_HTTP_MAX_KEEPALIVE     Keep-alive connections (default 20)
    SCIDB_HTTP_TIMEOUT           Default request timeout seconds (default 15)
    SCIDB_HTTP_RETRIES           Max retry attempts for idempotent requests (default 3)
"""

from __future__ import annotations

import asyncio
import logging
import os
import random
from typing import Awaitable, Callable

import httpx2 as httpx

log = logging.getLogger(__name__)

_DEFAULT_TIMEOUT = float(os.environ.get("SCIDB_HTTP_TIMEOUT", "15"))
_MAX_RETRIES = int(os.environ.get("SCIDB_HTTP_RETRIES", "3"))
_RETRYABLE_STATUS = frozenset({429, 502, 503, 504})
_IDEMPOTENT_METHODS = frozenset({"GET", "HEAD", "OPTIONS"})
_BACKOFF_BASE = 0.25  # seconds
_BACKOFF_MAX = 4.0    # seconds
_DEFAULT_HEADERS = {
    "User-Agent": "scidb-beta-runtime/0.1",
    "Accept": "application/json",
}


def _parse_retry_after(value: str | None) -> float | None:
    """Parse a ``Retry-After`` header value (integer seconds only)."""
    if not value:
        return None
    try:
        return max(0.0, float(value.strip()))
    except ValueError:
        return None


class RetryTransport(httpx.AsyncBaseTransport):
    """Transport wrapper adding bounded retries with exponential backoff.

    Only idempotent methods (GET/HEAD/OPTIONS by default) are retried.
    Retries happen on transport-level errors (connect/read/pool timeouts,
    network errors) and on retryable status codes (429, 502, 503, 504).
    A ``Retry-After`` response header is honoured when present.
    """

    def __init__(
        self,
        wrapped: httpx.AsyncBaseTransport,
        *,
        max_retries: int = _MAX_RETRIES,
        retryable_statuses: frozenset[int] = _RETRYABLE_STATUS,
        retry_methods: frozenset[str] = _IDEMPOTENT_METHODS,
        sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
    ) -> None:
        self._wrapped = wrapped
        self._max_retries = max(0, max_retries)
        self._retryable_statuses = retryable_statuses
        self._retry_methods = retry_methods
        self._sleep = sleep

    async def handle_async_request(self, request: httpx.Request) -> httpx.Response:
        if request.method not in self._retry_methods or self._max_retries == 0:
            return await self._wrapped.handle_async_request(request)

        for attempt in range(self._max_retries + 1):
            try:
                response = await self._wrapped.handle_async_request(request)
            except httpx.TransportError:
                if attempt >= self._max_retries:
                    raise
                log.warning("http transport error, retrying (attempt %d)", attempt + 1)
                await self._backoff(attempt)
                continue

            if response.status_code not in self._retryable_statuses or attempt >= self._max_retries:
                return response

            retry_after = _parse_retry_after(response.headers.get("retry-after"))
            await response.aclose()  # release the connection before retrying
            log.warning(
                "http %s %s -> %d, retrying (attempt %d)",
                request.method, request.url, response.status_code, attempt + 1,
            )
            await self._backoff(attempt, retry_after)

        # Unreachable: the loop either returns or raises.
        raise RuntimeError("retry loop exited unexpectedly")  # pragma: no cover

    async def _backoff(self, attempt: int, retry_after: float | None = None) -> None:
        if retry_after is not None:
            delay = min(retry_after, _BACKOFF_MAX * 4)
        else:
            delay = min(_BACKOFF_BASE * (2 ** attempt), _BACKOFF_MAX)
        delay += random.uniform(0.0, max(0.05, delay * 0.1))  # jitter
        await self._sleep(delay)

    async def aclose(self) -> None:
        await self._wrapped.aclose()


_client: httpx.AsyncClient | None = None
_client_loop: "asyncio.AbstractEventLoop | None" = None


def _build_client() -> httpx.AsyncClient:
    limits = httpx.Limits(
        max_connections=int(os.environ.get("SCIDB_HTTP_MAX_CONNECTIONS", "100")),
        max_keepalive_connections=int(os.environ.get("SCIDB_HTTP_MAX_KEEPALIVE", "20")),
    )
    transport = RetryTransport(httpx.AsyncHTTPTransport(limits=limits))
    return httpx.AsyncClient(
        transport=transport,
        timeout=httpx.Timeout(_DEFAULT_TIMEOUT),
        headers=_DEFAULT_HEADERS,
        follow_redirects=True,
    )


def get_http_client() -> httpx.AsyncClient:
    """Return the shared AsyncClient, creating it on first use.

    The client is bound to the event loop that first used it. If the running
    loop changes (e.g. a fresh ``TestClient`` portal in another pytest module),
    the stale client is discarded — closing it best-effort when its loop is
    still alive — and a new one is created for the current loop.
    """
    global _client, _client_loop
    try:
        loop: asyncio.AbstractEventLoop | None = asyncio.get_running_loop()
    except RuntimeError:
        loop = None

    if _client is not None and loop is not _client_loop:
        old_client, old_loop = _client, _client_loop
        _client, _client_loop = None, None
        if old_loop is not None and old_loop.is_running():
            old_loop.call_soon_threadsafe(lambda: asyncio.ensure_future(old_client.aclose()))
        # else: the old loop is already closed; abandon the client, its
        # sockets were released when the loop was torn down.

    if _client is None:
        _client = _build_client()
        _client_loop = loop
    return _client


async def close_http_client() -> None:
    """Close the shared client (call from the FastAPI lifespan shutdown)."""
    global _client, _client_loop
    if _client is not None:
        await _client.aclose()
        _client = None
        _client_loop = None


def reset_http_client_for_tests() -> None:
    """Drop the singleton reference without closing (test isolation helper)."""
    global _client, _client_loop
    _client = None
    _client_loop = None
