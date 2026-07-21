"""SQLAlchemy ORM models for PostgreSQL persistence.

Tables:
  - databases  : chess databases (id, name, format, games, read_only)
  - games      : game summaries (id, database_id, white, black, elo, eco, ...)
  - users      : user records (id, name, email, profile)
  - audit_logs : audit trail (id, action, details, user_id, ip, route, ts)
  - jobs       : long-running job records (id, type, status, progress, payload)
  - analysis   : engine-analysis records keyed by job_id (durable shadow of
                 the Redis live store)
  - workspaces : saved workspace layouts (id, user_id, name, layout, share)

Schema is owned by Alembic migrations (db/migrations/versions). The models
here must stay in sync with the migrations; ``Base.metadata.create_all`` is
only used as a development convenience when no migration has been applied.
"""

from __future__ import annotations

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    Text,
    func,
)
from sqlalchemy.orm import DeclarativeBase, relationship


class Base(DeclarativeBase):
    pass


class Database(Base):
    __tablename__ = "databases"

    id = Column(String(64), primary_key=True)
    name = Column(String(256), nullable=False)
    format = Column(String(16), nullable=False, default="PGN")
    games = Column(Integer, nullable=False, default=0)
    read_only = Column(Boolean, nullable=False, default=False)

    games_rel = relationship("Game", back_populates="database_rel", cascade="all, delete-orphan")


class Game(Base):
    __tablename__ = "games"

    id = Column(String(128), primary_key=True)
    database_id = Column(String(64), ForeignKey("databases.id"), nullable=False)
    white = Column(String(256), nullable=False)
    white_elo = Column(Integer, nullable=False, default=0)
    black = Column(String(256), nullable=False)
    black_elo = Column(Integer, nullable=False, default=0)
    event = Column(String(256), default="")
    site = Column(String(256), default="")
    date = Column(String(16), default="")
    result = Column(String(16), default="")
    eco = Column(String(8), default="")

    database_rel = relationship("Database", back_populates="games_rel")


class User(Base):
    __tablename__ = "users"

    id = Column(String(128), primary_key=True)
    name = Column(String(256), default="")
    email = Column(String(256), default="")
    profile = Column(Text, default="{}")


class AuditLog(Base):
    __tablename__ = "audit_logs"

    id = Column(String(64), primary_key=True)
    action = Column(String(64), nullable=False)
    details = Column(Text, default="{}")
    timestamp = Column(Float, nullable=False)
    # Added in migration 0002 (all nullable for backward compatibility)
    user_id = Column(String(128), nullable=True)
    ip = Column(String(64), nullable=True)
    route = Column(String(256), nullable=True)


class Job(Base):
    __tablename__ = "jobs"

    id = Column(String(128), primary_key=True)
    job_type = Column(String(32), nullable=False)
    status = Column(String(16), nullable=False, default="pending")
    progress = Column(Integer, default=0)
    total = Column(Integer, default=100)
    database_id = Column(String(64), nullable=True)
    created_at = Column(DateTime, server_default=func.now())
    # Added in migration 0002
    payload = Column(Text, default="{}")
    result = Column(Text, nullable=True)
    error = Column(Text, nullable=True)
    user_id = Column(String(128), nullable=True)
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class Analysis(Base):
    """Durable shadow of an engine-analysis record (live copy lives in Redis)."""

    __tablename__ = "analysis"

    job_id = Column(String(128), primary_key=True)
    payload = Column(Text, default="{}")
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())


class Workspace(Base):
    __tablename__ = "workspaces"

    id = Column(String(128), primary_key=True)
    user_id = Column(String(128), nullable=True, index=True)
    name = Column(String(256), default="")
    layout = Column(Text, default="{}")
    share_token = Column(String(64), nullable=True, unique=True)
    created_at = Column(DateTime, server_default=func.now())
    updated_at = Column(DateTime, server_default=func.now(), onupdate=func.now())
