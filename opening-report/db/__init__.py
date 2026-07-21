"""Storage backends for the scidb-beta runtime adapter.

Selects a backend at import time based on environment variables:
  - DATABASE_URL → PostgresStore (SQLAlchemy async + PostgreSQL/asyncpg)
  - REDIS_URL   → RedisStore (Redis for jobs/analysis/rate-limit + pub/sub)
  - (neither)   → MemoryStore (default in-memory dicts)

Object storage is independent: S3Store when S3_BUCKET is set, otherwise
LocalDiskStore rooted at DATA_DIR.
"""
from .store import (
    Store,
    MemoryStore,
    RedisStore,
    PostgresStore,
    get_store,
    normalize_database_url_for_async,
)
from .s3_store import (
    LocalDiskStore,
    ObjectKeyError,
    S3Store,
    get_object_store,
    sanitize_key,
)

__all__ = [
    "Store",
    "MemoryStore",
    "RedisStore",
    "PostgresStore",
    "get_store",
    "normalize_database_url_for_async",
    "S3Store",
    "LocalDiskStore",
    "ObjectKeyError",
    "get_object_store",
    "sanitize_key",
]
