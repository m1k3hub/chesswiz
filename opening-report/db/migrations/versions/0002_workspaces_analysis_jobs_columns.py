"""Migration 0002: workspaces + analysis tables; extend jobs and audit_logs.

Additive only — safe to apply to a live database:
  - CREATE TABLE workspaces  (saved workspace layouts + share tokens)
  - CREATE TABLE analysis    (durable shadow of Redis analysis records)
  - ALTER TABLE jobs         ADD payload, result, error, user_id, updated_at
  - ALTER TABLE audit_logs   ADD user_id, ip, route
  - Indexes: ix_workspaces_user_id, ix_jobs_status

Downgrade notes: ``op.drop_column`` on SQLite requires SQLite >= 3.35
(satisfied by any CPython >= 3.10 build). PostgreSQL has no such restriction.

Revision ID: 0002_workspaces_analysis_jobs_columns
Revises: 0001_initial
Create Date: 2026-07-21
"""
from alembic import op
import sqlalchemy as sa

revision = "0002_workspaces_analysis_jobs_columns"
down_revision = "0001_initial"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # --- New tables ---------------------------------------------------------

    op.create_table(
        "workspaces",
        sa.Column("id", sa.String(128), primary_key=True),
        sa.Column("user_id", sa.String(128), nullable=True),
        sa.Column("name", sa.String(256), server_default=""),
        sa.Column("layout", sa.Text, server_default="{}"),
        sa.Column("share_token", sa.String(64), nullable=True, unique=True),
        sa.Column("created_at", sa.DateTime, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime, server_default=sa.func.now()),
    )
    op.create_index("ix_workspaces_user_id", "workspaces", ["user_id"])

    op.create_table(
        "analysis",
        sa.Column("job_id", sa.String(128), primary_key=True),
        sa.Column("payload", sa.Text, server_default="{}"),
        sa.Column("created_at", sa.DateTime, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime, server_default=sa.func.now()),
    )

    # --- Extend jobs --------------------------------------------------------

    op.add_column("jobs", sa.Column("payload", sa.Text, server_default="{}"))
    op.add_column("jobs", sa.Column("result", sa.Text, nullable=True))
    op.add_column("jobs", sa.Column("error", sa.Text, nullable=True))
    op.add_column("jobs", sa.Column("user_id", sa.String(128), nullable=True))
    op.add_column(
        "jobs",
        sa.Column("updated_at", sa.DateTime, server_default=sa.func.now()),
    )
    op.create_index("ix_jobs_status", "jobs", ["status"])

    # --- Extend audit_logs --------------------------------------------------

    op.add_column("audit_logs", sa.Column("user_id", sa.String(128), nullable=True))
    op.add_column("audit_logs", sa.Column("ip", sa.String(64), nullable=True))
    op.add_column("audit_logs", sa.Column("route", sa.String(256), nullable=True))


def downgrade() -> None:
    op.drop_column("audit_logs", "route")
    op.drop_column("audit_logs", "ip")
    op.drop_column("audit_logs", "user_id")

    op.drop_index("ix_jobs_status", table_name="jobs")
    op.drop_column("jobs", "updated_at")
    op.drop_column("jobs", "user_id")
    op.drop_column("jobs", "error")
    op.drop_column("jobs", "result")
    op.drop_column("jobs", "payload")

    op.drop_table("analysis")

    op.drop_index("ix_workspaces_user_id", table_name="workspaces")
    op.drop_table("workspaces")
