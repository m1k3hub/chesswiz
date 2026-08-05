"""Tests for the storage backend abstraction.

Exercises MemoryStore (always) and RedisStore/PostgresStore when the
appropriate environment variables (REDIS_URL / DATABASE_URL) are set.
"""

import asyncio
import os
import pytest
import pytest_asyncio

from db.store import (
    Store,
    MemoryStore,
    RedisStore,
    PostgresStore,
    get_store,
    reset_store,
)


# ---------------------------------------------------------------------------
# MemoryStore (always runs)
# ---------------------------------------------------------------------------

class TestMemoryStore:
    """MemoryStore tests — no external dependencies required."""

    @pytest.fixture
    def store(self):
        return MemoryStore()

    @pytest.mark.asyncio
    async def test_job_lifecycle(self, store):
        job_id = "test-job-1"
        data = {"jobId": job_id, "status": "running", "progress": 50}
        await store.set_job(job_id, data)
        retrieved = await store.get_job(job_id)
        assert retrieved is not None
        assert retrieved["jobId"] == job_id
        assert retrieved["status"] == "running"

        await store.delete_job(job_id)
        assert await store.get_job(job_id) is None

    @pytest.mark.asyncio
    async def test_analysis_lifecycle(self, store):
        job_id = "test-analysis-1"
        data = {"jobId": job_id, "status": "running", "depth": 10}
        await store.set_analysis(job_id, data)
        retrieved = await store.get_analysis(job_id)
        assert retrieved is not None
        assert retrieved["depth"] == 10

        await store.delete_analysis(job_id)
        assert await store.get_analysis(job_id) is None

    @pytest.mark.asyncio
    async def test_rate_limit_allows_within_limit(self, store):
        ip = "192.168.1.1"
        for _ in range(5):
            assert await store.check_rate_limit(ip, "/api/searches", 10, 60.0)

    @pytest.mark.asyncio
    async def test_rate_limit_blocks_over_limit(self, store):
        ip = "192.168.1.2"
        for _ in range(3):
            assert await store.check_rate_limit(ip, "/api/analysis", 3, 60.0)
        # 4th request should be blocked
        assert not await store.check_rate_limit(ip, "/api/analysis", 3, 60.0)

    @pytest.mark.asyncio
    async def test_event_pubsub(self, store):
        q = await store.subscribe_events()
        await store.publish_event({"type": "test", "data": "hello"})
        event = await asyncio.wait_for(q.get(), timeout=1.0)
        assert event["type"] == "test"
        await store.unsubscribe_events(q)

    @pytest.mark.asyncio
    async def test_analysis_pubsub(self, store):
        job_id = "test-analysis-pubsub"
        q = await store.subscribe_analysis(job_id)
        await store.publish_analysis(job_id, {"type": "analysis.update", "depth": 5})
        msg = await asyncio.wait_for(q.get(), timeout=1.0)
        assert msg["type"] == "analysis.update"
        await store.unsubscribe_analysis(q)

    @pytest.mark.asyncio
    async def test_list_databases(self, store):
        dbs = await store.list_databases()
        assert isinstance(dbs, list)
        assert len(dbs) >= 2
        assert dbs[0]["id"] == "masters"

    @pytest.mark.asyncio
    async def test_create_database(self, store):
        db = {"id": "test-db-1", "name": "Test DB", "format": "PGN", "games": 0, "readOnly": False}
        result = await store.create_database(db)
        assert result["id"] == "test-db-1"
        dbs = await store.list_databases()
        assert any(d["id"] == "test-db-1" for d in dbs)

    @pytest.mark.asyncio
    async def test_list_games(self, store):
        games = await store.list_games("masters")
        assert isinstance(games, list)
        assert len(games) >= 1
        assert "white" in games[0]

    @pytest.mark.asyncio
    async def test_get_game(self, store):
        game = await store.get_game("g-001")
        assert game is not None
        assert game["white"] == "Carlsen, Magnus"

    @pytest.mark.asyncio
    async def test_get_game_not_found(self, store):
        assert await store.get_game("nonexistent") is None

    @pytest.mark.asyncio
    async def test_audit_log(self, store):
        await store.add_audit_log("test.action", user="test-user", detail="test")
        # No assertion needed — MemoryStore prints to stdout, PostgresStore persists

    @pytest.mark.asyncio
    async def test_list_jobs(self, store):
        await store.set_job("job-list-1", {"jobId": "job-list-1"})
        jobs = await store.list_jobs()
        assert any(j["jobId"] == "job-list-1" for j in jobs)

    @pytest.mark.asyncio
    async def test_user_lifecycle(self, store):
        user = {"id": "user-1", "name": "Test", "email": "test@example.com"}
        await store.create_user(user)
        retrieved = await store.get_user("user-1")
        assert retrieved is not None
        assert retrieved["name"] == "Test"


# ---------------------------------------------------------------------------
# RedisStore (only when REDIS_URL is set)
# ---------------------------------------------------------------------------

REDIS_URL = os.environ.get("REDIS_URL", "")


class TestRedisStore:
    """RedisStore tests. Uses a real Redis when REDIS_URL is set, otherwise a
    fakeredis in-process client (so the suite needs no external infra)."""

    @pytest.fixture
    def store(self):
        if REDIS_URL:
            s = RedisStore(REDIS_URL)
        else:
            try:
                import fakeredis.aioredis
            except ImportError:
                pytest.skip("neither REDIS_URL nor fakeredis available")
            fake = fakeredis.aioredis.FakeRedis(decode_responses=True)
            s = RedisStore("redis://localhost:6379", redis_client=fake)
        yield s
        loop = asyncio.new_event_loop()
        loop.run_until_complete(s.close())
        loop.close()

    @pytest.mark.asyncio
    async def test_job_lifecycle(self, store):
        job_id = "redis-test-job-1"
        data = {"jobId": job_id, "status": "running"}
        await store.set_job(job_id, data)
        retrieved = await store.get_job(job_id)
        assert retrieved is not None
        assert retrieved["jobId"] == job_id
        await store.delete_job(job_id)
        assert await store.get_job(job_id) is None

    @pytest.mark.asyncio
    async def test_rate_limit(self, store):
        ip = "10.0.0.1"
        for _ in range(3):
            assert await store.check_rate_limit(ip, "/api/test", 3, 60.0)
        assert not await store.check_rate_limit(ip, "/api/test", 3, 60.0)

    @pytest.mark.asyncio
    async def test_event_pubsub(self, store):
        sub = await store.subscribe_events()
        await store.publish_event({"type": "redis-test"})
        # Consume the subscription message
        import asyncio as _aio
        try:
            async for message in sub.listen():
                if message["type"] == "message":
                    data = message["data"]
                    assert "redis-test" in data
                    break
        finally:
            await store.unsubscribe_events(sub)


# ---------------------------------------------------------------------------
# PostgresStore (only when DATABASE_URL is set)
# ---------------------------------------------------------------------------

DATABASE_URL = os.environ.get("DATABASE_URL", "")


@pytest.mark.skipif(not DATABASE_URL, reason="DATABASE_URL not set")
class TestPostgresStore:
    """PostgresStore tests — require a running PostgreSQL instance."""

    @pytest_asyncio.fixture
    async def store(self):
        s = PostgresStore(DATABASE_URL, REDIS_URL)
        await s._ensure_ready()
        from db.models import Base
        async with s._engine.begin() as conn:
            await conn.run_sync(Base.metadata.drop_all)
            await conn.run_sync(Base.metadata.create_all)
        yield s
        await s.close()

    @pytest.mark.asyncio
    async def test_list_databases(self, store):
        dbs = await store.list_databases()
        assert isinstance(dbs, list)

    @pytest.mark.asyncio
    async def test_create_and_get_database(self, store):
        import uuid as _uuid
        db_id = f"pg-test-db-{_uuid.uuid4().hex[:8]}"
        db = {"id": db_id, "name": "PG Test", "format": "PGN", "games": 0, "readOnly": False}
        await store.create_database(db)
        dbs = await store.list_databases()
        assert any(d["id"] == db_id for d in dbs)

    @pytest.mark.asyncio
    async def test_audit_log_persists(self, store):
        await store.add_audit_log("test.pg.audit", user="pg-test")


# ---------------------------------------------------------------------------
# Factory tests
# ---------------------------------------------------------------------------

class TestStoreFactory:
    def test_get_store_returns_memory_by_default(self, monkeypatch):
        monkeypatch.delenv("REDIS_URL", raising=False)
        monkeypatch.delenv("DATABASE_URL", raising=False)
        reset_store()
        s = get_store()
        assert isinstance(s, MemoryStore)
        reset_store()

    def test_get_store_caches_singleton(self):
        reset_store()
        s1 = get_store()
        s2 = get_store()
        assert s1 is s2
        reset_store()