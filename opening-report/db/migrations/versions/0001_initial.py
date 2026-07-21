"""Initial migration: create databases, games, users, audit_logs, jobs tables.

Revision ID: 0001_initial
Create Date: 2025-07-20
"""
from alembic import op
import sqlalchemy as sa

revision = "0001_initial"
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "databases",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("name", sa.String(256), nullable=False),
        sa.Column("format", sa.String(16), nullable=False, server_default="PGN"),
        sa.Column("games", sa.Integer, nullable=False, server_default="0"),
        sa.Column("read_only", sa.Boolean, nullable=False, server_default=sa.text("false")),
    )

    op.create_table(
        "games",
        sa.Column("id", sa.String(128), primary_key=True),
        sa.Column("database_id", sa.String(64), sa.ForeignKey("databases.id"), nullable=False),
        sa.Column("white", sa.String(256), nullable=False),
        sa.Column("white_elo", sa.Integer, nullable=False, server_default="0"),
        sa.Column("black", sa.String(256), nullable=False),
        sa.Column("black_elo", sa.Integer, nullable=False, server_default="0"),
        sa.Column("event", sa.String(256), server_default=""),
        sa.Column("site", sa.String(256), server_default=""),
        sa.Column("date", sa.String(16), server_default=""),
        sa.Column("result", sa.String(16), server_default=""),
        sa.Column("eco", sa.String(8), server_default=""),
    )

    op.create_table(
        "users",
        sa.Column("id", sa.String(128), primary_key=True),
        sa.Column("name", sa.String(256), server_default=""),
        sa.Column("email", sa.String(256), server_default=""),
        sa.Column("profile", sa.Text, server_default="{}"),
    )

    op.create_table(
        "audit_logs",
        sa.Column("id", sa.String(64), primary_key=True),
        sa.Column("action", sa.String(64), nullable=False),
        sa.Column("details", sa.Text, server_default="{}"),
        sa.Column("timestamp", sa.Float, nullable=False),
    )

    op.create_table(
        "jobs",
        sa.Column("id", sa.String(128), primary_key=True),
        sa.Column("job_type", sa.String(32), nullable=False),
        sa.Column("status", sa.String(16), nullable=False, server_default="pending"),
        sa.Column("progress", sa.Integer, server_default="0"),
        sa.Column("total", sa.Integer, server_default="100"),
        sa.Column("database_id", sa.String(64), nullable=True),
        sa.Column("created_at", sa.DateTime, server_default=sa.func.now()),
    )


def downgrade() -> None:
    op.drop_table("jobs")
    op.drop_table("audit_logs")
    op.drop_table("users")
    op.drop_table("games")
    op.drop_table("databases")