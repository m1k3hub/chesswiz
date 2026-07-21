"""TTL cache tests (Phase 2): memory backend, factory, Redis backend (optional).

Run with:  pytest tests/test_cache.py -v
"""

import asyncio
import importlib.util

import pytest

import cache as cache_mod
from cache import MemoryTtlCache, RedisTtlCache, cache_key, get_cache, hash_payload, reset_cache


@pytest.fixture(autouse=True)
def _reset_cache_singleton():
    reset_cache()
    yield
    reset_cache()


# ---------------------------------------------------------------------------
# Key helpers
# ---------------------------------------------------------------------------

def test_cache_key_namespaced():
    key = cache_key("games", "masters", "list")
    assert key.startswith("scidb:cache:v1:")
    assert "games" in key and "masters" in key and "list" in key


def test_hash_payload_stable_and_order_insensitive():
    a = hash_payload({"x": 1, "y": [1, 2]})
    b = hash_payload({"y": [1, 2], "x": 1})
    c = hash_payload({"x": 2, "y": [1, 2]})
    assert a == b
    assert a != c
    assert len(a) == 32


# ---------------------------------------------------------------------------
# MemoryTtlCache
# ---------------------------------------------------------------------------

def test_memory_set_get_roundtrip():
    c = MemoryTtlCache()
    asyncio.run(c.set("k", {"v": 1}, ttl=60))
    assert asyncio.run(c.get("k")) == {"v": 1}


def test_memory_miss_returns_none():
    c = MemoryTtlCache()
    assert asyncio.run(c.get("nope")) is None


def test_memory_expiry():
    c = MemoryTtlCache()
    asyncio.run(c.set("k", "v", ttl=0.05))
    assert asyncio.run(c.get("k")) == "v"
    import time
    time.sleep(0.08)
    assert asyncio.run(c.get("k")) is None


def test_memory_zero_ttl_not_stored():
    c = MemoryTtlCache()
    asyncio.run(c.set("k", "v", ttl=0))
    assert asyncio.run(c.get("k")) is None


def test_memory_lru_eviction():
    c = MemoryTtlCache(maxsize=2)
    asyncio.run(c.set("a", 1, ttl=60))
    asyncio.run(c.set("b", 2, ttl=60))
    asyncio.run(c.set("c", 3, ttl=60))  # evicts "a" (oldest)
    assert asyncio.run(c.get("a")) is None
    assert asyncio.run(c.get("b")) == 2
    assert asyncio.run(c.get("c")) == 3


def test_memory_clear_prefix():
    c = MemoryTtlCache()
    prefix = cache_key("games", "masters")
    asyncio.run(c.set(cache_key("games", "masters", "list"), [1], ttl=60))
    asyncio.run(c.set(cache_key("games", "masters", "detail"), [2], ttl=60))
    asyncio.run(c.set(cache_key("databases", "list"), [3], ttl=60))
    asyncio.run(c.clear_prefix(prefix))
    assert asyncio.run(c.get(cache_key("games", "masters", "list"))) is None
    assert asyncio.run(c.get(cache_key("games", "masters", "detail"))) is None
    assert asyncio.run(c.get(cache_key("databases", "list"))) == [3]


def test_memory_delete():
    c = MemoryTtlCache()
    asyncio.run(c.set("k", "v", ttl=60))
    asyncio.run(c.delete("k"))
    assert asyncio.run(c.get("k")) is None


# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------

def test_factory_defaults_to_memory(monkeypatch):
    monkeypatch.delenv("REDIS_URL", raising=False)
    c = get_cache()
    assert isinstance(c, MemoryTtlCache)


def test_factory_singleton(monkeypatch):
    monkeypatch.delenv("REDIS_URL", raising=False)
    assert get_cache() is get_cache()


def test_factory_redis_when_url_set(monkeypatch):
    if importlib.util.find_spec("redis") is None:
        pytest.skip("redis-py not installed")
    monkeypatch.setenv("REDIS_URL", "redis://localhost:6379/0")
    c = get_cache()
    assert isinstance(c, RedisTtlCache)


# ---------------------------------------------------------------------------
# RedisTtlCache (fakeredis when available)
# ---------------------------------------------------------------------------

@pytest.fixture
def fake_redis():
    if importlib.util.find_spec("fakeredis") is None:
        pytest.skip("fakeredis not installed")
    import fakeredis.aioredis
    return fakeredis.aioredis.FakeRedis(decode_responses=True)


def test_redis_set_get_roundtrip(fake_redis):
    c = RedisTtlCache(client=fake_redis)
    asyncio.run(c.set("k", {"v": 42}, ttl=60))
    assert asyncio.run(c.get("k")) == {"v": 42}


def test_redis_miss_returns_none(fake_redis):
    c = RedisTtlCache(client=fake_redis)
    assert asyncio.run(c.get("missing")) is None


def test_redis_clear_prefix(fake_redis):
    c = RedisTtlCache(client=fake_redis)
    asyncio.run(c.set("scidb:cache:v1:games:m:list", [1], ttl=60))
    asyncio.run(c.set("scidb:cache:v1:databases:list", [2], ttl=60))
    asyncio.run(c.clear_prefix("scidb:cache:v1:games"))
    assert asyncio.run(c.get("scidb:cache:v1:games:m:list")) is None
    assert asyncio.run(c.get("scidb:cache:v1:databases:list")) == [2]


def test_redis_fail_open_on_error():
    """A broken backend must behave like a cache miss, never raise."""

    class _Broken:
        async def get(self, key):
            raise ConnectionError("redis down")

        async def set(self, *a, **kw):
            raise ConnectionError("redis down")

    c = RedisTtlCache(client=_Broken())
    assert asyncio.run(c.get("k")) is None
    asyncio.run(c.set("k", "v", ttl=60))  # must not raise


# ---------------------------------------------------------------------------
# Adapter integration: cached GET endpoints and invalidation
# ---------------------------------------------------------------------------

def test_adapter_caches_databases_and_invalidates_on_create(monkeypatch):
    """Second list is served from cache; a create invalidates it."""
    monkeypatch.delenv("REDIS_URL", raising=False)
    reset_cache()
    from fastapi.testclient import TestClient
    from runtime_adapter import app

    client = TestClient(app)
    c = get_cache()
    assert isinstance(c, MemoryTtlCache)

    assert asyncio.run(c.get(cache_key("databases", "list"))) is None
    r1 = client.get("/api/databases")
    assert r1.status_code == 200
    # Now the list must be cached
    assert asyncio.run(c.get(cache_key("databases", "list"))) is not None

    r2 = client.post("/api/databases", json={"name": "Cache Test", "format": "PGN", "games": 0, "readOnly": False})
    assert r2.status_code == 200
    # Create invalidated the cached list
    assert asyncio.run(c.get(cache_key("databases", "list"))) is None
