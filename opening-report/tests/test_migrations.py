"""Tests for Alembic migrations.

Two layers of coverage that need no running PostgreSQL server:

1. Offline SQL generation (``alembic upgrade --sql``) — asserts migration
   0002 emits the expected DDL (workspaces/analysis tables, new jobs and
   audit_logs columns).
2. Online upgrade/downgrade against a temporary SQLite file — verifies the
   resulting schema end-to-end (tables + columns + indexes) and that
   downgrade to 0001 removes the 0002 objects.

Skipped automatically when alembic is not installed.
"""

from __future__ import annotations

import os

import pytest

alembic = pytest.importorskip("alembic")  # noqa: E402 — gated import
from alembic import command  # noqa: E402
from alembic.config import Config  # noqa: E402

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT_LOCATION = os.path.join(PROJECT_ROOT, "db", "migrations")


def _make_config(url: str) -> Config:
    cfg = Config()
    cfg.set_main_option("script_location", SCRIPT_LOCATION)
    cfg.set_main_option("sqlalchemy.url", url)
    return cfg


class TestOfflineSql:
    """Offline (--sql) rendering of the full migration chain."""

    def test_offline_sql_contains_0002_objects(self, monkeypatch, capsys):
        url = "postgresql://user:pass@localhost:5432/scidb_test"
        monkeypatch.setenv("DATABASE_URL", url)
        cfg = _make_config(url)
        command.upgrade(cfg, "base:head", sql=True)
        out = capsys.readouterr().out
        assert "CREATE TABLE workspaces" in out
        assert "CREATE TABLE analysis" in out
        # jobs extensions
        assert "ADD COLUMN payload" in out
        assert "ADD COLUMN result" in out
        assert "ADD COLUMN error" in out
        assert "ADD COLUMN user_id" in out
        assert "ADD COLUMN updated_at" in out
        # audit_logs extensions (user_id already asserted above)
        assert "ADD COLUMN ip" in out
        assert "ADD COLUMN route" in out

    def test_offline_sql_with_asyncpg_url(self, monkeypatch, capsys):
        """env.py rewrites +asyncpg URLs so offline mode needs no asyncpg."""
        url = "postgresql+asyncpg://user:pass@localhost:5432/scidb_test"
        monkeypatch.setenv("DATABASE_URL", url)
        cfg = _make_config(url)
        command.upgrade(cfg, "base:head", sql=True)  # must not raise
        assert "CREATE TABLE workspaces" in capsys.readouterr().out


class TestSqliteRoundTrip:
    """Online upgrade/downgrade on a throwaway SQLite database file."""

    def test_upgrade_head_and_downgrade(self, monkeypatch, tmp_path):
        sa = pytest.importorskip("sqlalchemy")
        db_file = tmp_path / "migrations.db"
        url = f"sqlite:///{db_file}"
        monkeypatch.setenv("DATABASE_URL", url)
        cfg = _make_config(url)

        command.upgrade(cfg, "head")

        engine = sa.create_engine(url)
        try:
            inspector = sa.inspect(engine)
            tables = set(inspector.get_table_names())
            assert {"databases", "games", "users", "audit_logs", "jobs"} <= tables
            assert "workspaces" in tables
            assert "analysis" in tables

            job_cols = {c["name"] for c in inspector.get_columns("jobs")}
            assert {"payload", "result", "error", "user_id", "updated_at"} <= job_cols

            audit_cols = {c["name"] for c in inspector.get_columns("audit_logs")}
            assert {"user_id", "ip", "route"} <= audit_cols

            ws_indexes = {ix["name"] for ix in inspector.get_indexes("workspaces")}
            assert "ix_workspaces_user_id" in ws_indexes
            job_indexes = {ix["name"] for ix in inspector.get_indexes("jobs")}
            assert "ix_jobs_status" in job_indexes

            # Downgrade back to 0001: the 0002 objects disappear.
            command.downgrade(cfg, "0001_initial")
            inspector = sa.inspect(engine)
            tables_after = set(inspector.get_table_names())
            assert "workspaces" not in tables_after
            assert "analysis" not in tables_after
            job_cols_after = {c["name"] for c in inspector.get_columns("jobs")}
            assert "payload" not in job_cols_after
            assert "updated_at" not in job_cols_after

            # And upgrade again to prove the chain is re-runnable.
            command.upgrade(cfg, "head")
            inspector = sa.inspect(engine)
            assert "workspaces" in set(inspector.get_table_names())
        finally:
            engine.dispose()


class TestModelsMatchMigrations:
    """The ORM metadata and the migrations must describe the same schema."""

    def test_metadata_contains_0002_tables_and_columns(self):
        from db.models import Base

        tables = Base.metadata.tables
        assert "workspaces" in tables
        assert "analysis" in tables

        job_cols = set(tables["jobs"].columns.keys())
        assert {"payload", "result", "error", "user_id", "updated_at"} <= job_cols

        audit_cols = set(tables["audit_logs"].columns.keys())
        assert {"user_id", "ip", "route"} <= audit_cols

        ws_cols = set(tables["workspaces"].columns.keys())
        assert {"id", "user_id", "name", "layout", "share_token", "created_at", "updated_at"} <= ws_cols
