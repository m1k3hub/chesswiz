#!/usr/bin/env python3
"""
engines/engine_pool.py — Concurrency limiter for UCI engine analyses.

The runtime adapter spawns one engine subprocess per analysis request.
Without a cap, a burst of ``POST /api/analysis/start`` requests would fork
an unbounded number of Stockfish processes and exhaust CPU/RSS on the host.
``EnginePool`` bounds that with a semaphore and a small amount of
bookkeeping used for stats and for a non-blocking ``try_acquire`` fast path
(so the HTTP endpoint can answer ``429`` immediately instead of queueing
unboundedly).

Usage in the endpoint::

    pool = get_engine_pool()
    if not await pool.try_acquire():
        return JSONResponse({"error": "engine busy", "engine": pool.stats()}, 429)
    asyncio.create_task(run_guarded(...))   # releases the slot in `finally`

or, with the context manager::

    async with pool.slot(timeout=5.0):
        ...  # run the engine

Configuration: ``SCIDB_ENGINE_MAX_CONCURRENT`` (default 4, clamp 1–64).
"""

from __future__ import annotations

import asyncio
import os
from contextlib import asynccontextmanager
from typing import AsyncIterator, Optional

__all__ = [
    "EnginePoolBusyError",
    "EnginePool",
    "get_engine_pool",
    "reset_engine_pool",
]

_DEFAULT_MAX_CONCURRENT = 4
_MAX_CONCURRENT_CEILING = 64


class EnginePoolBusyError(RuntimeError):
    """Raised by ``EnginePool.slot()`` when no slot becomes free in time."""


class EnginePool:
    """Semaphore bounding the number of concurrently running engines."""

    def __init__(self, max_concurrent: int = _DEFAULT_MAX_CONCURRENT):
        if max_concurrent < 1:
            raise ValueError("max_concurrent must be >= 1")
        self._max = int(max_concurrent)
        self._sem = asyncio.BoundedSemaphore(self._max)
        self._active = 0

    @property
    def max_concurrent(self) -> int:
        return self._max

    @property
    def active(self) -> int:
        """Number of slots currently checked out."""
        return self._active

    async def try_acquire(self) -> bool:
        """Acquire a slot without waiting. Returns False when the pool is full.

        Safe with respect to the underlying semaphore: the ``_active`` check
        and the semaphore's non-suspending fast path execute without an
        intervening await, so no other coroutine can slip in between.
        """
        if self._active >= self._max:
            return False
        # Capacity is guaranteed by the check above, so this returns
        # immediately (Semaphore.acquire does not suspend when value > 0
        # and no waiters exist).
        await self._sem.acquire()
        self._active += 1
        return True

    async def acquire(self, timeout: Optional[float] = None) -> bool:
        """Acquire a slot, waiting up to *timeout* seconds (None = forever).

        Returns True on success, False on timeout.
        """
        try:
            if timeout is None:
                await self._sem.acquire()
            else:
                # wait_for cancels the acquire on timeout; Semaphore handles
                # waiter cancellation correctly (no lost permit on 3.11+).
                await asyncio.wait_for(self._sem.acquire(), timeout)
        except asyncio.TimeoutError:
            return False
        self._active += 1
        return True

    def release(self) -> None:
        """Release a previously acquired slot."""
        if self._active <= 0:
            raise RuntimeError("EnginePool.release() without a matching acquire")
        self._active -= 1
        self._sem.release()

    @asynccontextmanager
    async def slot(self, timeout: Optional[float] = None) -> AsyncIterator[None]:
        """Async context manager holding a pool slot.

        Raises ``EnginePoolBusyError`` when no slot is available within
        *timeout* seconds.
        """
        ok = await self.acquire(timeout)
        if not ok:
            raise EnginePoolBusyError(
                f"no engine slot available within {timeout!r}s "
                f"(max_concurrent={self._max})"
            )
        try:
            yield
        finally:
            self.release()

    def stats(self) -> dict:
        """Snapshot of pool state for health/metrics responses."""
        return {
            "maxConcurrent": self._max,
            "active": self._active,
            "available": self._max - self._active,
        }


# ---------------------------------------------------------------------------
# Process-wide singleton
# ---------------------------------------------------------------------------

_pool: Optional[EnginePool] = None


def _max_concurrent_from_env() -> int:
    raw = os.environ.get("SCIDB_ENGINE_MAX_CONCURRENT", "").strip()
    if not raw:
        return _DEFAULT_MAX_CONCURRENT
    try:
        value = int(raw)
    except ValueError:
        return _DEFAULT_MAX_CONCURRENT
    return max(1, min(value, _MAX_CONCURRENT_CEILING))


def get_engine_pool() -> EnginePool:
    """Return the process-wide EnginePool, creating it on first use."""
    global _pool
    if _pool is None:
        _pool = EnginePool(_max_concurrent_from_env())
    return _pool


def reset_engine_pool() -> None:
    """Drop the singleton (used by tests to pick up new env settings)."""
    global _pool
    _pool = None
