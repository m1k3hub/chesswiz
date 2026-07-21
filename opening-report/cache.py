"""TTL cache for idempotent GET responses (Phase 2 performance hardening).

Backends:
  - ``MemoryTtlCache`` — in-process LRU with monotonic-clock expiry (default)
  - ``RedisTtlCache``  — Redis-backed, shared across workers (``REDIS_URL``)

The cache is fail-open: backend errors are logged and treated as misses so a
cache outage never takes down the API.

Key scheme: ``scidb:cache:v1:<namespace>:...`` — use ``cache_key()`` to build
keys and ``clear_prefix(cache_key("<namespace>"))`` to invalidate a whole
namespace after mutations.
"""

from __future__ import annotations

import hashlib
import json
import logging
import os
import time
from collections import OrderedDict
from typing import Any

log = logging.getLogger(__name__)

_KEY_PREFIX = "scidb:cache:v1:"


def cache_key(*parts: object) -> str:
    """Build a namespaced cache key from string-able parts."""
    return _KEY_PREFIX + ":".join(str(p) for p in parts)


def hash_payload(payload: Any) -> str:
    """Return a stable short hash for a JSON-able payload (query body/params)."""
    canonical = json.dumps(payload, sort_keys=True, default=str)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:32]


def _record(hit: bool, backend: str) -> None:
    """Report a cache hit/miss to the metrics module (best effort)."""
    try:
        from metrics import record_cache_result
        record_cache_result(hit, backend)
    except Exception:
        pass


class MemoryTtlCache:
    """In-process LRU cache with per-key TTL (monotonic clock)."""

    backend_name = "memory"

    def __init__(self, maxsize: int = 1024) -> None:
        self._maxsize = max(1, maxsize)
        # key -> (expires_at_monotonic, value)
        self._data: "OrderedDict[str, tuple[float, Any]]" = OrderedDict()

    async def get(self, key: str) -> Any | None:
        item = self._data.get(key)
        if item is None:
            _record(False, self.backend_name)
            return None
        expires_at, value = item
        if expires_at <= time.monotonic():
            self._data.pop(key, None)
            _record(False, self.backend_name)
            return None
        self._data.move_to_end(key)
        _record(True, self.backend_name)
        return value

    async def set(self, key: str, value: Any, ttl: float) -> None:
        if ttl <= 0:
            return
        self._evict_expired()
        self._data[key] = (time.monotonic() + ttl, value)
        self._data.move_to_end(key)
        while len(self._data) > self._maxsize:
            self._data.popitem(last=False)

    async def delete(self, key: str) -> None:
        self._data.pop(key, None)

    async def clear_prefix(self, prefix: str) -> None:
        doomed = [k for k in self._data if k.startswith(prefix)]
        for k in doomed:
            self._data.pop(k, None)

    async def close(self) -> None:
        self._data.clear()

    def _evict_expired(self) -> None:
        now = time.monotonic()
        doomed = [k for k, (exp, _) in self._data.items() if exp <= now]
        for k in doomed:
            self._data.pop(k, None)


class RedisTtlCache:
    """Redis-backed TTL cache shared across workers."""

    backend_name = "redis"

    def __init__(self, redis_url: str = "", *, client: Any = None) -> None:
        self._redis_url = redis_url
        self._redis = client

    async def _ensure_redis(self):
        if self._redis is None:
            import redis.asyncio as aioredis  # type: ignore
            self._redis = aioredis.from_url(self._redis_url, decode_responses=True)
        return self._redis

    async def get(self, key: str) -> Any | None:
        try:
            r = await self._ensure_redis()
            raw = await r.get(key)
        except Exception as exc:  # fail-open
            log.warning("cache get failed (%s); treating as miss", exc)
            _record(False, self.backend_name)
            return None
        if raw is None:
            _record(False, self.backend_name)
            return None
        _record(True, self.backend_name)
        try:
            return json.loads(raw)
        except (TypeError, ValueError):
            return raw

    async def set(self, key: str, value: Any, ttl: float) -> None:
        if ttl <= 0:
            return
        try:
            r = await self._ensure_redis()
            await r.set(key, json.dumps(value, default=str), ex=max(1, int(ttl)))
        except Exception as exc:  # fail-open
            log.warning("cache set failed (%s); skipping", exc)

    async def delete(self, key: str) -> None:
        try:
            r = await self._ensure_redis()
            await r.delete(key)
        except Exception as exc:
            log.warning("cache delete failed (%s); skipping", exc)

    async def clear_prefix(self, prefix: str) -> None:
        try:
            r = await self._ensure_redis()
            async for k in r.scan_iter(match=f"{prefix}*"):
                await r.unlink(k)
        except Exception as exc:
            log.warning("cache clear_prefix failed (%s); skipping", exc)

    async def close(self) -> None:
        if self._redis is not None:
            try:
                await self._redis.close()
            except Exception:
                pass
            self._redis = None


# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------

_cache_instance: MemoryTtlCache | RedisTtlCache | None = None


def get_cache() -> MemoryTtlCache | RedisTtlCache:
    """Return the shared cache backend (Redis when REDIS_URL is set)."""
    global _cache_instance
    if _cache_instance is not None:
        return _cache_instance
    redis_url = os.environ.get("REDIS_URL", "")
    if redis_url:
        try:
            import redis.asyncio  # noqa: F401
            _cache_instance = RedisTtlCache(redis_url)
            return _cache_instance
        except ImportError:
            log.warning("REDIS_URL is set but redis-py is not installed; using in-memory cache")
    _cache_instance = MemoryTtlCache(
        maxsize=int(os.environ.get("SCIDB_CACHE_MAXSIZE", "1024"))
    )
    return _cache_instance


def reset_cache() -> None:
    """Drop the cache singleton (test isolation helper)."""
    global _cache_instance
    _cache_instance = None
