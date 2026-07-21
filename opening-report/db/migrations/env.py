# Alembic configuration for scidb-beta runtime adapter.
#
# Run migrations with:
#   cd opening-report
#   DATABASE_URL=postgresql://user:pass@localhost:5432/scidb \
#   alembic upgrade head
#
# Notes:
#   * Migrations always run on a *synchronous* driver. If DATABASE_URL uses
#     the async runtime driver (``postgresql+asyncpg://``) it is rewritten to
#     the synchronous ``postgresql+psycopg2://`` form here.
#   * ``sqlalchemy.url`` may also be set directly (tests do this); the
#     DATABASE_URL environment variable takes precedence when present.

from alembic import context
from sqlalchemy import engine_from_config, pool

import os
import sys

# Make the project root (the directory containing the ``db`` package)
# importable. env.py lives at <root>/db/migrations/env.py, so the project
# root is three directory levels up.
_PROJECT_ROOT = os.path.dirname(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
)
if _PROJECT_ROOT not in sys.path:
    sys.path.insert(0, _PROJECT_ROOT)

from db.models import Base

config = context.config


def _sync_database_url(url: str) -> str:
    """Rewrite async driver URLs to their synchronous migration equivalents."""
    if "+asyncpg" in url:
        return url.replace("+asyncpg", "+psycopg2")
    if url.startswith("sqlite+aiosqlite://"):
        return "sqlite://" + url[len("sqlite+aiosqlite://"):]
    return url


# Override sqlalchemy.url with DATABASE_URL if set
database_url = os.environ.get("DATABASE_URL", "")
if database_url:
    config.set_main_option("sqlalchemy.url", _sync_database_url(database_url))
else:
    configured = config.get_main_option("sqlalchemy.url")
    if configured:
        config.set_main_option("sqlalchemy.url", _sync_database_url(configured))

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata)
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
