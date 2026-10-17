#!/usr/bin/env python3
"""
runtime_adapter.py — scidb-beta web adapter service (REST + WebSocket).

Replaces and extends proxy_server.py with a FastAPI application that:
  1. Preserves the Lichess explorer/game proxy endpoints.
  2. Serves mock REST endpoints matching the frontend API contract.
  3. Streams job progress and engine analysis over WebSocket.
  4. Adds CORS for the Vite dev server.
  5. Optionally uses Redis for the event bus when REDIS_URL is set.
  6. Optionally uses S3 / S3-compatible object storage when S3_BUCKET is set,
     otherwise falls back to local disk ./data/.
  7. Supports streaming multipart file uploads (POST /api/databases/:id/import)
     and format conversion (POST /api/databases/:id/convert).

Run directly:

    python3 runtime_adapter.py                  # http://localhost:5001

Or with uvicorn:

    uvicorn runtime_adapter:app --host 0.0.0.0 --port 5001

Environment variables:

    REDIS_URL       If set, use Redis pub/sub for the event bus.
    S3_BUCKET       If set, use S3 (or S3-compatible) for file storage.
    S3_ENDPOINT     Custom S3 endpoint URL (e.g. Cloudflare R2).
    S3_KEY          S3 access key ID.
    S3_SECRET       S3 secret access key.
    S3_REGION       S3 region (default: us-east-1).
    DATA_DIR        Local disk storage directory (default: ./data).
"""

from __future__ import annotations

import asyncio
import io
import json
import os
import re
import time
import uuid
from collections import defaultdict
from contextlib import asynccontextmanager
from typing import Any

import httpx2 as httpx
import uvicorn
from fastapi import FastAPI, File, Header, Request, UploadFile, WebSocket, WebSocketDisconnect, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, PlainTextResponse, RedirectResponse
from pydantic import BaseModel, Field

import config
from play_routes import router as play_router
from play_ws import router as play_ws_router
from play_service import play_service
import security
from cache import cache_key, get_cache, hash_payload
from engines.engine_pool import EnginePool, get_engine_pool, reset_engine_pool, _max_concurrent_from_env
from engines.sandbox import EngineSandboxConfig, parse_engine_allowlist, validate_engine_binary
from http_client import close_http_client, get_http_client
from logging_config import (
    RequestIdMiddleware,
    RequestLoggingMiddleware,
    configure_logging,
    get_logger,
    init_sentry,
)
from metrics import MetricsMiddleware, metrics_endpoint, websocket_closed, websocket_opened
from db.store import get_store, Store, MemoryStore, PostgresStore, RedisStore

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

LICHESS_EXPLORER_BASE = "https://explorer.lichess.ovh"
LICHESS_GAME_BASE = "https://lichess.org"

REDIS_URL = os.environ.get("REDIS_URL", "")
DATA_DIR = os.environ.get("DATA_DIR", os.path.join(os.path.dirname(os.path.abspath(__file__)), "data"))

# --- Engine configuration ----------------------------------------------------
#
# The runtime adapter uses a real UCI engine (Stockfish) when the binary is
# available. Set STOCKFISH_PATH to the engine executable. If unset, the
# adapter searches a few well-known locations and the bundled
# ``engines/stockfish`` directory. When no engine is found it falls back to
# the mock simulation so tests and development still work.

_ENGINES_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "engines")
_BUNDLED_STOCKFISH_DIR = os.path.join(_ENGINES_DIR, "stockfish")


def _discover_stockfish_path() -> str:
    """Return the path to a Stockfish binary, or empty string if none found."""
    explicit = os.environ.get("STOCKFISH_PATH", "")
    if explicit and os.path.isfile(explicit) and os.access(explicit, os.X_OK):
        return explicit
    if explicit and os.path.isfile(explicit):
        return explicit  # let the subprocess fail if not executable

    # Search bundled directory
    if os.path.isdir(_BUNDLED_STOCKFISH_DIR):
        for name in sorted(os.listdir(_BUNDLED_STOCKFISH_DIR)):
            candidate = os.path.join(_BUNDLED_STOCKFISH_DIR, name)
            if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                return candidate

    # Search common system locations
    for candidate in ["/usr/bin/stockfish", "/usr/local/bin/stockfish"]:
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate

    return ""


STOCKFISH_PATH = _discover_stockfish_path()


def _available_engines() -> list[dict[str, str]]:
    """Return a list of engine descriptors for GET /api/engines."""
    engines = []
    if STOCKFISH_PATH:
        engines.append({
            "engineId": "stockfish",
            "name": "Stockfish",
            "path": STOCKFISH_PATH,
        })
    # Always include a mock entry so the UI has something to show
    engines.append({
        "engineId": "mock",
        "name": "Mock engine (simulated)",
        "path": "",
    })
    return engines


def _resolve_engine_path(engine_id: str) -> str:
    """Return the executable path for *engine_id*, or empty string for mock."""
    if engine_id == "stockfish":
        return STOCKFISH_PATH
    return ""


ENGINE_ALLOWLIST = parse_engine_allowlist(
    os.environ.get("SCIDB_ENGINE_ALLOWLIST", ""),
    STOCKFISH_PATH,
    _BUNDLED_STOCKFISH_DIR,
    _ENGINES_DIR,
)


def _build_engine_sandbox_config() -> EngineSandboxConfig:
    """Build the EngineSandboxConfig from environment variables."""
    raw_memory = os.environ.get("SCIDB_ENGINE_MEMORY_MB", "512").strip()
    try:
        memory_mb = max(64, int(raw_memory)) if raw_memory else 512
    except ValueError:
        memory_mb = 512
    raw_time = os.environ.get("SCIDB_ENGINE_TIME_LIMIT_S", "30.0").strip()
    try:
        time_limit_s = float(raw_time) if raw_time else 30.0
    except ValueError:
        time_limit_s = 30.0
    raw_as = os.environ.get("SCIDB_ENGINE_RLIMIT_AS_MB", "").strip()
    rlimit_as_mb: Optional[int] = None
    if raw_as:
        try:
            rlimit_as_mb = max(0, int(raw_as)) or None
        except ValueError:
            rlimit_as_mb = None
    raw_cpu = os.environ.get("SCIDB_ENGINE_CPU_TIME_S", "").strip()
    cpu_time_s: Optional[int] = None
    if raw_cpu:
        try:
            cpu_time_s = max(0, int(raw_cpu)) or None
        except ValueError:
            cpu_time_s = None
    return EngineSandboxConfig(
        memory_mb=memory_mb,
        rlimit_as_mb=rlimit_as_mb,
        cpu_time_s=cpu_time_s,
        sandbox_backend=os.environ.get("SCIDB_SANDBOX_BACKEND", "auto"),
        watchdog_interval_s=float(os.environ.get("SCIDB_WATCHDOG_INTERVAL_S", "0.5")),
    )


# ---------------------------------------------------------------------------
# Engine pool (concurrency limiter)
# ---------------------------------------------------------------------------

def get_engine_pool() -> EnginePool:
    """Return the process-wide engine pool, creating it on first call."""
    global _engine_pool
    if _engine_pool is None:
        _engine_pool = EnginePool(_max_concurrent_from_env())
    return _engine_pool


def reset_engine_pool() -> None:
    """Drop the engine pool singleton (used by tests)."""
    global _engine_pool
    _engine_pool = None


# Backward-compat alias used during migration.
_engine_pool: Optional[EnginePool] = None

S3_BUCKET = os.environ.get("S3_BUCKET", "")
S3_ENDPOINT = os.environ.get("S3_ENDPOINT", "")
S3_KEY = os.environ.get("S3_KEY", "")
S3_SECRET = os.environ.get("S3_SECRET", "")
S3_REGION = os.environ.get("S3_REGION", "us-east-1")

# ---------------------------------------------------------------------------
# Size limits
# ---------------------------------------------------------------------------

# MAX_UPLOAD_SIZE is defined exactly once here (see config.max_upload_size).
# Tests monkeypatch this module attribute to exercise the 413 paths.
MAX_UPLOAD_SIZE = config.max_upload_size()  # 256 MB default for PGN/database uploads
MAX_FEN_LENGTH = 4_096                # 4 KB max for FEN strings
MAX_PGN_LENGTH = 256 * 1024 * 1024  # 256 MB max for PGN payloads
MAX_CQL_LENGTH = 65_536              # 64 KB max for CQL queries

# ---------------------------------------------------------------------------
# Audit logging
# ---------------------------------------------------------------------------

_AUDIT_LOG_PATH = os.environ.get("AUDIT_LOG", "")  # empty = stdout

def _audit_log(action: str, **fields: Any) -> None:
    """Write one JSON line per audited action.

    Actions logged: imports, exports, deletes, maintenance, login/logout.
    When a persistent store is active (PostgresStore), logs are also written
    to the audit_logs table. Otherwise output goes to stdout (default) or a
    configurable AUDIT_LOG file path.
    """
    entry = {
        "timestamp": time.time(),
        "action": action,
        **fields,
    }
    line = json.dumps(entry, default=str, ensure_ascii=False)
    if _AUDIT_LOG_PATH:
        try:
            with open(_AUDIT_LOG_PATH, "a", encoding="utf-8") as f:
                f.write(line + "\n")
        except OSError:
            # Fall back to stdout if the file is not writable
            print(line, flush=True)
    else:
        print(line, flush=True)
    # Also persist to the store if it supports audit logging
    try:
        asyncio.get_running_loop().create_task(store.add_audit_log(action, **fields))
    except RuntimeError:
        # No event loop running (e.g. synchronous call); skip async store write
        pass

# ---------------------------------------------------------------------------
# Input validation (mirrors src/lib/validation.ts)
# ---------------------------------------------------------------------------

_FEN_PIECE_RE = re.compile(r"^[pnbrqkPNBRQK1-8/]+$")
_FEN_TURN_RE = re.compile(r"^[wb]$")
_FEN_CASTLING_RE = re.compile(r"^(K?Q?k?q?|-)$")
_FEN_EP_RE = re.compile(r"^([a-h][36]|-)$")
_PGN_HEADER_RE = re.compile(r"^\[\w+\s+\"[^\"]*\"\]$")


def _validate_fen(fen: str | None) -> bool:
    """Server-side FEN validation (mirrors src/lib/validation.ts)."""
    if not fen or not isinstance(fen, str):
        return False
    if len(fen) > MAX_FEN_LENGTH:
        return False
    parts = fen.strip().split()
    if len(parts) != 6:
        return False
    placement, turn, castling, ep, halfmove, fullmove = parts
    ranks = placement.split("/")
    if len(ranks) != 8:
        return False
    for rank in ranks:
        squares = 0
        for ch in rank:
            if ch in "12345678":
                squares += int(ch)
            elif ch in "pnbrqkPNBRQK":
                squares += 1
            else:
                return False
        if squares != 8:
            return False
    if not _FEN_TURN_RE.match(turn):
        return False
    if not _FEN_CASTLING_RE.match(castling):
        return False
    if not _FEN_EP_RE.match(ep):
        return False
    if not halfmove.isdigit():
        return False
    if not fullmove.isdigit() or int(fullmove) == 0:
        return False
    return True


def _validate_pgn(pgn: str | None) -> bool:
    """Server-side PGN validation (basic structural check)."""
    if not pgn or not isinstance(pgn, str):
        return False
    if len(pgn) > MAX_PGN_LENGTH:
        return False
    trimmed = pgn.strip()
    if not trimmed:
        return False
    lines = trimmed.split("\n")
    movetext_started = False
    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        if stripped.startswith("["):
            if movetext_started:
                return False
            if not _PGN_HEADER_RE.match(stripped):
                return False
        else:
            movetext_started = True
    movetext = " ".join(l for l in lines if not l.strip().startswith("[") and l.strip())
    if not movetext:
        return True  # headers-only is valid
    import re as _re
    has_result = bool(_re.search(r"\b(1-0|0-1|1/2-1/2|\*)\b", movetext))
    has_move = bool(_re.search(r"\d+\.\s*[a-hNBRQKO]", movetext)) or bool(_re.search(r"\b[NBRQK]?[a-h]?[1-8]", movetext))
    return has_result or has_move


def _validate_cql(cql: str | None) -> bool:
    """Server-side CQL validation (basic structural check)."""
    if not cql or not isinstance(cql, str):
        return False
    if len(cql) > MAX_CQL_LENGTH:
        return False
    trimmed = cql.strip()
    if not trimmed:
        return False
    if re.search(r"<\s*(script|iframe|object|embed)", trimmed, re.IGNORECASE):
        return False
    depth = 0
    for ch in trimmed:
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth < 0:
                return False
    return depth == 0


# ---------------------------------------------------------------------------
# Rate limiting (delegated to the configured Store for shared state)
# ---------------------------------------------------------------------------

_RATE_LIMIT_WINDOW = 60.0  # seconds
_RATE_LIMIT_MAX_REQUESTS: dict[str, int] = {
    "/api/searches": 30,
    "/api/analysis/start": 20,
    "/api/databases/{database_id}/import": 10,
    "/api/play": 120,
}

# In-memory rate-limit state (used by MemoryStore when no Redis/Postgres store
# is configured). Tests import and clear this dict to reset state between runs;
# the MemoryStore instance shares this exact dict (wired up below where the
# store is created), so clearing it also resets the store-side buckets.
_rate_buckets: dict = defaultdict(lambda: defaultdict(list))


async def _check_rate_limit(client_ip: str, route_key: str) -> bool:
    """Return True if the request is within the rate limit, False if exceeded.

    Delegates to the configured store so rate-limit state is shared across
    workers when Redis or PostgreSQL is configured (RedisStore uses a sorted
    set; MemoryStore falls back to the in-process sliding window above).
    """
    max_req = _RATE_LIMIT_MAX_REQUESTS.get(route_key, 0)
    if max_req == 0:
        return True  # no limit configured
    return await store.check_rate_limit(client_ip, route_key, max_req, _RATE_LIMIT_WINDOW)


def _client_ip(request: Request) -> str:
    """Extract the client IP for rate limiting and audit logging.

    ``X-Forwarded-For`` is only trusted when SCIDB_TRUST_PROXY_HOPS > 0
    (see security.client_ip); otherwise the direct peer is used, which is
    spoof-proof.
    """
    peer = request.client.host if request.client else "unknown"
    return security.client_ip(
        peer,
        request.headers.get("x-forwarded-for"),
        config.trust_proxy_hops(),
    )

# ---------------------------------------------------------------------------
# Redis event bus (optional)
# ---------------------------------------------------------------------------

_redis_client = None

def _get_redis():
    """Return a redis client if REDIS_URL is set, else None."""
    global _redis_client
    if not REDIS_URL:
        return None
    if _redis_client is None:
        try:
            import redis.asyncio as aioredis  # type: ignore
            _redis_client = aioredis.from_url(REDIS_URL, decode_responses=True)
        except ImportError:
            print("WARNING: REDIS_URL is set but redis-py is not installed. Falling back to in-memory event bus.")
            return None
    return _redis_client


# ---------------------------------------------------------------------------
# Object storage abstraction
# ---------------------------------------------------------------------------

_s3_client = None


def _get_s3():
    """Return a boto3 S3 client if S3_BUCKET is set, else None."""
    global _s3_client
    if not S3_BUCKET:
        return None
    if _s3_client is None:
        try:
            import boto3  # type: ignore
            _s3_client = boto3.client(
                "s3",
                endpoint_url=S3_ENDPOINT or None,
                aws_access_key_id=S3_KEY or None,
                aws_secret_access_key=S3_SECRET or None,
                region_name=S3_REGION,
            )
        except ImportError:
            print("WARNING: S3_BUCKET is set but boto3 is not installed. Falling back to local disk.")
            return None
    return _s3_client


async def _store_file(key: str, data: bytes) -> str:
    """Store a file and return its storage key.

    Uses S3 if configured, otherwise writes to local disk under DATA_DIR.
    """
    s3 = _get_s3()
    if s3:
        s3.put_object(Bucket=S3_BUCKET, Key=key, Body=data)
        return key

    os.makedirs(DATA_DIR, exist_ok=True)
    filepath = os.path.join(DATA_DIR, key.replace("/", os.sep))
    # Defense in depth: never write outside DATA_DIR, even if a caller lets a
    # crafted key (``..``, symlink, absolute path) slip through.
    filepath = security.ensure_within_directory(DATA_DIR, filepath)
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    with open(filepath, "wb") as f:
        f.write(data)
    return key


async def _retrieve_file(key: str) -> bytes | None:
    """Retrieve a file by storage key. Returns None if not found."""
    s3 = _get_s3()
    if s3:
        try:
            resp = s3.get_object(Bucket=S3_BUCKET, Key=key)
            return resp["Body"].read()
        except Exception:
            return None

    filepath = os.path.join(DATA_DIR, key.replace("/", os.sep))
    # Defense in depth: never read outside DATA_DIR.
    filepath = security.ensure_within_directory(DATA_DIR, filepath)
    if os.path.exists(filepath):
        with open(filepath, "rb") as f:
            return f.read()
    return None


# ---------------------------------------------------------------------------
# Store abstraction (Memory / Redis / PostgreSQL)
# ---------------------------------------------------------------------------

store: Store = get_store()

# Share the module-level rate-limit buckets with any in-memory rate-limit
# backend the store uses, so that ``_rate_buckets.clear()`` (used by tests)
# also resets store-side state, and so rate limiting behaves identically
# whether reached via the store or the legacy module dict. When the store is
# a PostgresStore without Redis, its in-memory event backend holds the
# buckets; with Redis/Postgres backing, state is shared via the server.
def _share_memory_rate_buckets(s: Store) -> None:
    if isinstance(s, MemoryStore):
        s._rate_buckets = _rate_buckets
        return
    fallback = getattr(s, "_memory_fallback", None)
    if isinstance(fallback, MemoryStore):
        fallback._rate_buckets = _rate_buckets


_share_memory_rate_buckets(store)

# Keep the old global dicts as thin proxies for backward compatibility with
# tests that may still import them directly.
_JOBS: dict[str, dict[str, Any]] = {}
_ANALYSIS: dict[str, dict[str, Any]] = {}

# Event bus: job_id -> list of asyncio.Queue (one per subscriber)
_EVENT_SUBSCRIBERS: dict[str, list[asyncio.Queue]] = {}
# Global event subscribers (receive all events)
_GLOBAL_EVENT_SUBSCRIBERS: list[asyncio.Queue] = []
# Analysis subscribers: job_id -> list of asyncio.Queue
_ANALYSIS_SUBSCRIBERS: dict[str, list[asyncio.Queue]] = {}

@asynccontextmanager
async def _lifespan(app: FastAPI):
    """Startup/shutdown lifecycle.

    Startup validates the security configuration and refuses to start when
    it is unsafe. Shutdown closes the shared HTTP client and the store backend.
    """
    security.validate_security_config()
    yield
    await close_http_client()
    try:
        await store.close()
    except Exception:
        pass


app = FastAPI(title="scidb-beta Runtime Adapter", version="0.1.0", lifespan=_lifespan)
app.include_router(play_router, prefix="/api")
app.include_router(play_ws_router)

# CORS is environment-driven (SCIDB_ALLOWED_ORIGINS). Wildcard origins are
# never combined with credentials; in production they are a startup error.
app.add_middleware(CORSMiddleware, **config.cors_settings())

# Phase 2 observability middlewares. The last middleware added runs first
# (outermost), so RequestIdMiddleware wraps access-logging and metrics and the
# request id is available to both.
app.add_middleware(MetricsMiddleware)
app.add_middleware(RequestLoggingMiddleware)
app.add_middleware(RequestIdMiddleware)

configure_logging()
init_sentry()
log = get_logger("scidb.adapter")


# ---------------------------------------------------------------------------
# Event bus helpers
# ---------------------------------------------------------------------------

_EVENT_BUS_CHANNEL = "scidb:events"
_ANALYSIS_BUS_CHANNEL = "scidb:analysis"


async def _ws_receive_or_disconnect(websocket: WebSocket) -> None:
    """Await a receive on *websocket*; raise WebSocketDisconnect on close.

    Used as the "disconnection probe" leg of ``asyncio.wait`` in the
    WebSocket event loops so that a client disconnect is detected promptly
    instead of blocking forever on ``queue.get()`` / ``pubsub.listen()``.
    """
    await websocket.receive()  # raises WebSocketDisconnect on close


async def _publish_event(event: dict[str, Any]) -> None:
    """Publish an event to all global subscribers (in-memory or Redis)."""
    await store.publish_event(event)
    # Also notify in-process queues for backward compatibility
    for queue in _GLOBAL_EVENT_SUBSCRIBERS:
        await queue.put(event)


async def _publish_analysis(job_id: str, data: dict[str, Any]) -> None:
    """Publish an analysis update to subscribers of a specific job."""
    await store.publish_analysis(job_id, data)
    # Also notify in-process queues for backward compatibility
    for queue in _ANALYSIS_SUBSCRIBERS.get(job_id, []):
        await queue.put(data)


async def _simulate_job_progress(job_id: str, job_type: str, total: int = 100) -> None:
    """Simulate progress for a long-running job and publish events."""
    job = await store.get_job(job_id)
    if not job:
        return
    for step in range(1, total + 1):
        await asyncio.sleep(0.05)  # 50ms per step
        job["progress"] = step
        job["status"] = "running"
        await store.set_job(job_id, job)
        await _publish_event({
            "type": "job.progress",
            "jobId": job_id,
            "jobType": job_type,
            "progress": step,
            "total": total,
            "timestamp": time.time(),
        })
    job["status"] = "complete"
    job["progress"] = total
    await store.set_job(job_id, job)
    await _publish_event({
        "type": "job.complete",
        "jobId": job_id,
        "jobType": job_type,
        "progress": total,
        "total": total,
        "timestamp": time.time(),
    })


async def _simulate_analysis(job_id: str, depth: int, multi_pv: int) -> None:
    """Simulate engine analysis and stream updates to subscribers.

    Used as a fallback when no real UCI engine binary is available.
    """
    job = await store.get_analysis(job_id)
    if not job:
        return
    base_lines = [
        {"pv": "e2e4 e7e5", "eval": "+0.35", "depth": 18},
        {"pv": "d2d4 d7d5", "eval": "+0.28", "depth": 18},
        {"pv": "c2c4 e7e6", "eval": "+0.20", "depth": 18},
    ]
    lines = base_lines[:multi_pv]
    current_depth = 0
    target = depth

    while current_depth < target:
        # Re-fetch to detect stop requests from the /api/analysis/{id}/stop endpoint
        latest = await store.get_analysis(job_id)
        if not latest or latest.get("status") != "running":
            break
        current_depth += 1
        await asyncio.sleep(0.3)
        job["depth"] = current_depth
        job["nodes"] = (current_depth * 1_200_000) + (current_depth * 37_000)
        job["nps"] = 1_200_000 + (current_depth % 5) * 80_000
        job["lines"] = [
            {
                "pv": ln["pv"].split(" ")[:2 + current_depth // 6] and " ".join(ln["pv"].split(" ")[:2 + current_depth // 6]) or ln["pv"],
                "eval": f"{float(ln['eval']) + (current_depth % 3 - 1) * 0.03:+.2f}",
                "depth": current_depth,
            }
            for ln in lines
        ]
        await store.set_analysis(job_id, job)
        await _publish_analysis(job_id, {**job, "type": "analysis.update"})

    # Only mark as complete if the loop finished naturally (not stopped)
    latest = await store.get_analysis(job_id)
    if latest and latest.get("status") == "stopped":
        job["status"] = "stopped"
    else:
        job["status"] = "complete"
    await store.set_analysis(job_id, job)
    final_type = "analysis.stopped" if job["status"] == "stopped" else "analysis.complete"
    await _publish_analysis(job_id, {**job, "type": final_type})


# --- Real UCI engine integration -------------------------------------------

async def _run_real_analysis(
    job_id: str,
    engine_path: str,
    fen: str,
    depth: int,
    multi_pv: int,
    *,
    cpu_limit: int = 100,
    memory_mb: int = 512,
    time_limit_s: float = 30.0,
) -> None:
    """Run a real UCI engine analysis and stream updates to subscribers."""
    from engines.stockfish_worker import UciWorker

    job = await store.get_analysis(job_id)
    if not job:
        return

    # Validate against the binary allowlist before spawning.
    try:
        engine_path = validate_engine_binary(engine_path, ENGINE_ALLOWLIST)
    except Exception as exc:
        job["status"] = "error"
        job["error"] = f"not-allowed: {exc}"
        await store.set_analysis(job_id, job)
        await _publish_analysis(job_id, {**job, "type": "analysis.error"})
        return

    # Local queue receives updates from the worker
    local_queue: asyncio.Queue = asyncio.Queue()

    worker = UciWorker(
        engine_path,
        cpu_limit=cpu_limit,
        memory_mb=memory_mb,
        time_limit_s=time_limit_s,
        sandbox=_build_engine_sandbox_config(),
        allowlist=ENGINE_ALLOWLIST,
    )

    # Run the worker in the background
    worker_task = asyncio.create_task(
        worker.start(fen, depth=depth, multi_pv=multi_pv, queue=local_queue)
    )

    try:
        while True:
            # Re-fetch to detect stop requests from the /api/analysis/{id}/stop endpoint
            latest = await store.get_analysis(job_id)
            if latest and latest.get("status") == "stopped":
                await worker.stop()
                break

            try:
                msg = await asyncio.wait_for(local_queue.get(), timeout=1.0)
            except asyncio.TimeoutError:
                if worker_task.done():
                    break
                continue

            msg_type = msg.get("type", "")

            if msg_type == "analysis.update":
                job["depth"] = msg.get("depth", job.get("depth", 0))
                job["nodes"] = msg.get("nodes", job.get("nodes", 0))
                job["nps"] = msg.get("nps", job.get("nps", 0))
                lines = msg.get("lines", [])
                if lines:
                    job["lines"] = lines
                await store.set_analysis(job_id, job)
                await _publish_analysis(job_id, {**job, "type": "analysis.update"})
            elif msg_type == "analysis.complete":
                job["depth"] = msg.get("depth", job.get("depth", 0))
                job["nodes"] = msg.get("nodes", job.get("nodes", 0))
                job["nps"] = msg.get("nps", job.get("nps", 0))
                lines = msg.get("lines", [])
                if lines:
                    job["lines"] = lines
                job["status"] = "complete"
                await store.set_analysis(job_id, job)
                await _publish_analysis(job_id, {**job, "type": "analysis.complete"})
                break
            elif msg_type == "analysis.error":
                job["status"] = "error"
                job["error"] = msg.get("error", "engine-error")
                await store.set_analysis(job_id, job)
                await _publish_analysis(job_id, {**job, "type": "analysis.error"})
                break
    finally:
        if not worker_task.done():
            await worker.stop()
            try:
                await asyncio.wait_for(worker_task, timeout=3.0)
            except asyncio.TimeoutError:
                worker_task.cancel()
        await worker.quit()


# ---------------------------------------------------------------------------
# Mock data
# ---------------------------------------------------------------------------

MOCK_DATABASES = [
    {"id": "masters", "name": "Master Games", "format": "SCI", "games": 2_400_000, "readOnly": True},
    {"id": "repertoire", "name": "My Repertoire", "format": "PGN", "games": 1842, "readOnly": False},
]

MOCK_GAMES = [
    {"id": "g-001", "white": "Carlsen, Magnus", "whiteElo": 2855, "black": "Nepomniachtchi, Ian", "blackElo": 2782, "event": "WCh 2021", "site": "Dubai UAE", "date": "2021.12.03", "result": "½–½", "eco": "A45"},
    {"id": "g-002", "white": "Kasparov, Garry", "whiteElo": 2810, "black": "Karpov, Anatoly", "blackElo": 2725, "event": "Linares", "site": "Linares ESP", "date": "1993.03.02", "result": "1-0", "eco": "D37"},
    {"id": "g-003", "white": "Polgar, Judit", "whiteElo": 2735, "black": "Anand, Viswanathan", "blackElo": 2774, "event": "Hoogeveen", "site": "Hoogeveen NED", "date": "2003.10.16", "result": "0-1", "eco": "B90"},
    {"id": "g-004", "white": "Fischer, Robert James", "whiteElo": 2785, "black": "Spassky, Boris", "blackElo": 2660, "event": "Reykjavik WCh", "site": "Reykjavik ISL", "date": "1972.07.23", "result": "1-0", "eco": "E56"},
]

MOCK_TREE = [
    {"san": "d4", "uci": "d2d4", "games": 126_420, "score": 52.8, "white": 37, "draw": 42, "black": 21, "eco": "A45"},
    {"san": "Nf3", "uci": "g1f3", "games": 84_210, "score": 51.2, "white": 35, "draw": 44, "black": 21, "eco": "A06"},
    {"san": "c4", "uci": "c2c4", "games": 61_190, "score": 50.4, "white": 34, "draw": 43, "black": 23, "eco": "A10"},
    {"san": "e4", "uci": "e2e4", "games": 23_880, "score": 49.7, "white": 33, "draw": 40, "black": 27, "eco": "B00"},
]

DEFAULT_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"


# ---------------------------------------------------------------------------
# Request models
# ---------------------------------------------------------------------------

class CreateDatabaseRequest(BaseModel):
    name: str
    format: str = "PGN"
    games: int = 0
    readOnly: bool = False


class SearchRequest(BaseModel):
    databaseId: str | None = "masters"
    type: str = "advanced"
    query: dict[str, Any] = Field(default_factory=dict)


class TreeQueryRequest(BaseModel):
    moves: list[dict[str, str]] = Field(default_factory=list)
    source: str | None = None
    fen: str | None = None


class AnalysisStartRequest(BaseModel):
    fen: str | None = DEFAULT_FEN
    multiPv: int = 3
    depth: int = 20
    engineId: str = "stockfish"
    movetimeMs: int | None = None


class ConvertRequest(BaseModel):
    targetFormat: str = "SCI"


class ExportRequest(BaseModel):
    format: str = "PGN"
    gameIds: list[str] | None = None


# ---- Wave 3: player center, repertoire, prep ------------------------------

class PlayerPrepRequest(BaseModel):
    playerId: str
    databaseId: str | None = None
    color: str | None = None


class OpeningPrepRequest(BaseModel):
    repertoireId: str
    databaseId: str | None = None


# ---- Wave 4: maintenance, crosstables -------------------------------------

class MaintenanceRequest(BaseModel):
    databaseId: str
    operation: str


class CrosstableQueryRequest(BaseModel):
    event: str | None = None
    site: str | None = None
    players: list[str] | None = None


# ---- Wave 5: game viewer / editor -----------------------------------------

class GameUpdateRequest(BaseModel):
    headers: dict[str, str] | None = None
    comment: dict[str, Any] | None = None


class VariationRequest(BaseModel):
    parentMoveId: str
    moves: list[dict[str, str]] = Field(default_factory=list)
    comment: dict[str, Any] | None = None


class MoveCommentRequest(BaseModel):
    comment: dict[str, Any]


# ---- Wave 6: explorer / opening-info --------------------------------------

class ExplorerRequest(BaseModel):
    moves: list[dict[str, str]] = Field(default_factory=list)
    source: str | None = None
    speed: str | None = None
    ratings: list[int] | None = None
    fen: str | None = None


class OpeningInfoRequest(BaseModel):
    moves: list[dict[str, str]] = Field(default_factory=list)
    fen: str | None = None


# ---------------------------------------------------------------------------
# Search helpers
# ---------------------------------------------------------------------------

def _normalize_result(r: str) -> str:
    return r.replace("½", "1/2").replace("–", "-").replace("—", "-").replace("−", "-").replace(" ", "")


def _matches_advanced(game: dict, q: dict) -> bool:
    if q.get("white") and q["white"].lower() not in game["white"].lower():
        return False
    if q.get("black") and q["black"].lower() not in game["black"].lower():
        return False
    if q.get("event") and q["event"].lower() not in game["event"].lower():
        return False
    if q.get("site") and q["site"].lower() not in game["site"].lower():
        return False
    if q.get("ecoFrom") and game["eco"] < q["ecoFrom"]:
        return False
    if q.get("ecoTo") and game["eco"] > q["ecoTo"]:
        return False
    if q.get("result") and q["result"] != "any" and _normalize_result(game["result"]) != _normalize_result(q["result"]):
        return False
    if q.get("yearFrom") and int(game["date"][:4]) < int(q["yearFrom"]):
        return False
    if q.get("yearTo") and int(game["date"][:4]) > int(q["yearTo"]):
        return False
    return True


def _matches_material(game: dict, q: dict) -> bool:
    profiles = {
        "g-001": {"wq": 1, "bq": 1, "wr": 2, "br": 2, "wb": 2, "bb": 1, "wn": 2, "bn": 2, "wp": 8, "bp": 7},
        "g-002": {"wq": 1, "bq": 0, "wr": 2, "br": 1, "wb": 2, "bb": 2, "wn": 2, "bn": 2, "wp": 7, "bp": 6},
        "g-003": {"wq": 1, "bq": 1, "wr": 2, "br": 2, "wb": 1, "bb": 2, "wn": 2, "bn": 1, "wp": 8, "bp": 8},
        "g-004": {"wq": 0, "bq": 0, "wr": 2, "br": 2, "wb": 2, "bb": 2, "wn": 2, "bn": 2, "wp": 6, "bp": 6},
    }
    p = profiles.get(game["id"])
    if not p:
        return False
    for key, field_name in [("whiteQ", "wq"), ("whiteR", "wr"), ("whiteB", "wb"), ("whiteN", "wn"), ("whiteP", "wp"),
                             ("blackQ", "bq"), ("blackR", "br"), ("blackB", "bb"), ("blackN", "bn"), ("blackP", "bp")]:
        val = q.get(key)
        if val is not None and p[field_name] != int(val):
            return False
    imbalance = q.get("imbalance")
    if imbalance:
        wv = p["wq"] * 9 + p["wr"] * 5 + (p["wb"] + p["wn"]) * 3 + p["wp"]
        bv = p["bq"] * 9 + p["br"] * 5 + (p["bb"] + p["bn"]) * 3 + p["bp"]
        if imbalance == "up" and wv <= bv:
            return False
        if imbalance == "down" and wv >= bv:
            return False
        if imbalance == "equal" and wv != bv:
            return False
    return True


def _matches_rating(game: dict, q: dict) -> bool:
    avg = (game["whiteElo"] + game["blackElo"]) // 2
    if q.get("whiteEloMin") and game["whiteElo"] < int(q["whiteEloMin"]):
        return False
    if q.get("whiteEloMax") and game["whiteElo"] > int(q["whiteEloMax"]):
        return False
    if q.get("blackEloMin") and game["blackElo"] < int(q["blackEloMin"]):
        return False
    if q.get("blackEloMax") and game["blackElo"] > int(q["blackEloMax"]):
        return False
    if q.get("averageEloMin") and avg < int(q["averageEloMin"]):
        return False
    if q.get("averageEloMax") and avg > int(q["averageEloMax"]):
        return False
    return True


def _matches_cql(game: dict, q: dict) -> bool:
    text = (q.get("cql") or "").lower()
    if not text:
        return True
    haystack = f"{game['white']} {game['black']} {game['event']} {game['site']} {game['eco']} {game['result']}".lower()
    return any(term in haystack for term in text.split())


# ---------------------------------------------------------------------------
# Tcl bridge (optional)
# ---------------------------------------------------------------------------
#
# When ``TCL_BRIDGE_PATH`` is set (path to a Tcl script or executable that
# emits JSON), database/game/search/tree/analysis endpoints are routed through
# the bridge. If the bridge is unavailable or returns an error, each endpoint
# falls back to the in-memory mock data so tests and development still work.

from tcl_bridge import TclBridge

_tcl_bridge = TclBridge()

# ---------------------------------------------------------------------------
# Health check (legacy + Phase 2 live/ready split)
# ---------------------------------------------------------------------------

@app.get("/api/health")
async def health():
    """Legacy combined health endpoint (preserved for backward compatibility)."""
    checks = await _ready_checks()
    ok = all(v in ("ok", "active", "disabled", "mock") for v in checks.values())
    return JSONResponse(
        {
            "status": "ok" if ok else "degraded",
            "version": "0.1.0",
            "redis": "connected" if checks.get("redis") == "ok" else "disabled",
            "storage": "s3" if checks.get("s3") == "ok" else "local",
            "tclBridge": checks.get("tclBridge", "disabled"),
        },
        status_code=200 if ok else 503,
    )


@app.get("/api/health/live")
async def health_live():
    """Liveness probe: the process is up and the event loop responds."""
    return {"status": "ok", "version": "0.1.0"}


async def _ready_checks() -> dict[str, str]:
    """Return a map of dependency name -> 'ok' / 'error' / 'disabled'."""
    checks: dict[str, str] = {}

    # PostgreSQL / store layer
    try:
        await asyncio.wait_for(store.list_jobs(), timeout=2.0)
        checks["store"] = "ok"
    except Exception:
        checks["store"] = "error"

    # Redis
    r = _get_redis()
    if r is None:
        checks["redis"] = "disabled"
    else:
        try:
            pong = await r.ping()
            checks["redis"] = "ok" if pong else "error"
        except Exception:
            checks["redis"] = "error"

    # S3 / object storage
    if S3_BUCKET:
        try:
            s3 = _get_s3()
            if s3 is None:
                raise RuntimeError("s3 client unavailable")
            await asyncio.to_thread(s3.head_bucket, Bucket=S3_BUCKET)
            checks["s3"] = "ok"
        except Exception:
            checks["s3"] = "error"
    else:
        checks["s3"] = "disabled"

    # Informational components (do not affect readiness).
    checks["tclBridge"] = "active" if _tcl_bridge.is_available() else "disabled"
    checks["engine"] = "available" if STOCKFISH_PATH else "mock"

    return checks


@app.get("/api/health/ready")
async def health_ready():
    """Readiness probe: backing services (store/Redis, S3) are reachable.

    Returns 200 when all *critical* components are healthy, 503 otherwise.
    The Tcl bridge and engine binary are informational only.
    """
    checks = await _ready_checks()
    ok = all(v in ("ok", "active", "disabled", "mock") for v in checks.values())
    return JSONResponse(
        {"status": "ready" if ok else "degraded", "components": checks},
        status_code=200 if ok else 503,
    )


@app.get("/metrics", include_in_schema=False)
async def prometheus_metrics():
    """Prometheus scrape endpoint (501 when prometheus-client is absent)."""
    return await metrics_endpoint()


# ---------------------------------------------------------------------------
# Auth — OIDC / JWT verification
# ---------------------------------------------------------------------------
#
# When OIDC_ISSUER and OIDC_JWKS_URI are set, tokens are verified using
# PyJWT with RS256 against the provider's JWKS (with key caching). An
# optional introspection fallback (OIDC_INTROSPECTION_URI) can validate
# opaque tokens.
#
# The permissive dummy-JWT fallback is available ONLY when BOTH:
#   1. SCIDB_ENV is not production, and
#   2. SCIDB_ALLOW_INSECURE_DEV_AUTH=1 is set explicitly.
# In production the adapter refuses to start without OIDC (see
# security.validate_security_config, invoked from the FastAPI lifespan).
#
# The module-level names below are kept stable: tests monkeypatch
# ``OIDC_JWKS_URI`` / ``_verify_jwt_rs256`` / ``_jwks_client`` here, and the
# wrappers resolve them at call time.

OIDC_ISSUER = config.OIDC_ISSUER
OIDC_AUDIENCE = config.OIDC_AUDIENCE
OIDC_JWKS_URI = config.OIDC_JWKS_URI
OIDC_INTROSPECTION_URI = config.OIDC_INTROSPECTION_URI
_SCIDB_JWT_SECRET = os.environ.get("SCIDB_JWT_SECRET", "scidb-beta-dev-secret")

# Lazy-loaded JWKS client (PyJWT), with key caching enabled.
_jwks_client: Any = None
_signing_keys: list = []  # cached JWKS keys


def _get_jwks_client():
    """Return a cached PyJWT PyJWKClient, or None if OIDC is not configured.

    When OIDC_JWKS_URI IS configured but PyJWT is missing, this returns None
    and verification fails CLOSED (tokens are rejected) — never falls back
    to the dummy decoder.
    """
    global _jwks_client
    if not OIDC_JWKS_URI:
        return None
    if _jwks_client is None:
        _jwks_client = security.create_jwks_client(OIDC_JWKS_URI)
    return _jwks_client


def _verify_jwt_rs256(token: str) -> dict[str, Any] | None:
    """Verify an RS256 JWT using the OIDC provider's JWKS.

    Returns the decoded payload on success, None on failure.
    """
    jwks = _get_jwks_client()
    if not jwks:
        return None  # OIDC not configured, or verification unavailable
    return security.verify_rs256(
        token,
        jwks,
        issuer=OIDC_ISSUER or None,
        audience=OIDC_AUDIENCE or None,
    )


async def _introspect_token(token: str) -> dict[str, Any] | None:
    """Introspect an opaque/access token via the OIDC introspection endpoint.

    Returns the introspection response if active, None otherwise.
    """
    if not OIDC_INTROSPECTION_URI:
        return None
    try:
        client = get_http_client()
        resp = await client.post(
            OIDC_INTROSPECTION_URI,
            data={"token": token},
            headers={"Accept": "application/json"},
            timeout=10,
        )
        if resp.status_code != 200:
            return None
        data = resp.json()
        if not isinstance(data, dict) or not data.get("active", False):
            return None
        return data
    except Exception:
        return None


def _decode_dummy_jwt(token: str) -> dict[str, Any] | None:
    """Permissive dummy JWT decode for local development and tests.

    Only reachable when config.allow_insecure_dev_auth() is True (never in
    production). Accepts any JWT whose payload contains a 'sub' claim.
    """
    return security.decode_dummy_jwt(token)


def _get_auth_payload_sync(authorization: str | None) -> dict[str, Any] | None:
    """Extract and validate the Bearer token (synchronous path).

    Tries RS256 JWT verification first when OIDC is configured (fail closed:
    no dummy fallback in that case). Without OIDC, the dummy decoder is used
    only when insecure dev auth is explicitly allowed. Introspection is
    handled separately in the async path.
    """
    if not authorization:
        return None
    if not authorization.startswith("Bearer "):
        return None
    token = authorization[7:].strip()
    if not token:
        return None

    # If OIDC is configured, require real JWT verification — never fall back
    # to the dummy decoder, even in development.
    if OIDC_JWKS_URI:
        return _verify_jwt_rs256(token)

    # Development fallback, gated behind SCIDB_ENV != production AND
    # SCIDB_ALLOW_INSECURE_DEV_AUTH=1.
    if not config.allow_insecure_dev_auth():
        return None
    return _decode_dummy_jwt(token)


@app.get("/api/auth/me")
async def auth_me(authorization: str | None = Header(default=None)):
    """Return the decoded user from the Bearer token, or 401 if unauthenticated."""
    # Try sync JWT verification first (handles RS256 + dummy fallback)
    payload = _get_auth_payload_sync(authorization)

    # If sync path failed and introspection is configured, try async introspection
    if not payload and OIDC_INTROSPECTION_URI and authorization:
        token = authorization[7:].strip() if authorization.startswith("Bearer ") else ""
        if token:
            payload = await _introspect_token(token)

    if not payload:
        return JSONResponse({"error": "unauthorized"}, status_code=401)
    return {
        "id": payload.get("sub"),
        "name": payload.get("name", payload.get("sub", "")),
        "email": payload.get("email", ""),
        "profile": payload,
    }


@app.get("/api/auth/login")
async def auth_login(redirect: str | None = None):
    """No-op redirect for OIDC flow compatibility.

    In a real deployment, this would redirect to the OIDC provider's
    authorization endpoint. For local development it simply redirects to
    the callback URI so the frontend can test the flow end-to-end.
    """
    _audit_log("auth.login")
    callback = redirect or "/auth/callback"
    return RedirectResponse(url=callback, status_code=302)


@app.get("/api/auth/logout")
async def auth_logout(redirect: str | None = None):
    """No-op redirect for OIDC sign-out compatibility."""
    _audit_log("auth.logout")
    target = redirect or "/"
    return RedirectResponse(url=target, status_code=302)


# ---------------------------------------------------------------------------
# Lichess proxy endpoints (preserved from proxy_server.py)
# ---------------------------------------------------------------------------

@app.get("/api/explorer/{explorer_type}")
async def proxy_explorer(explorer_type: str, request: Request):
    """Proxy to Lichess Opening Explorer API."""
    if explorer_type not in ("masters", "lichess"):
        return JSONResponse({"error": "Unknown explorer type"}, status_code=400)
    # Forward the query string from the incoming request to Lichess
    query_string = str(request.url.query) if request.url.query else ""
    return _explorer_proxy(explorer_type, query_string=query_string)


# Cache TTLs for the Lichess proxies. Masters data changes slowly; the
# lichess pool explorer changes faster; exported game PGNs are immutable.
_EXPLORER_CACHE_TTL = {"masters": 3600.0, "lichess": 300.0}
_GAME_PGN_CACHE_TTL = 86400.0
_OPENING_CACHE_TTL = 3600.0


async def _explorer_proxy(explorer_type: str, *, query_string: str = ""):
    url = f"{LICHESS_EXPLORER_BASE}/{explorer_type}?{query_string}"
    cache = get_cache()
    key = cache_key("explorer", explorer_type, hash_payload(query_string))
    cached = await cache.get(key)
    if cached is not None:
        return JSONResponse(cached["body"], status_code=cached["status"])
    client = get_http_client()
    try:
        resp = await client.get(url, headers={"Accept": "application/json"})
    except httpx.HTTPError as exc:
        return JSONResponse({"error": str(exc)}, status_code=502)
    try:
        body = resp.json()
    except ValueError:
        return JSONResponse({"error": "invalid upstream response"}, status_code=502)
    if resp.status_code == 200:
        await cache.set(
            key,
            {"status": resp.status_code, "body": body},
            ttl=_EXPLORER_CACHE_TTL.get(explorer_type, 300.0),
        )
    return JSONResponse(body, status_code=resp.status_code)


@app.get("/api/game/{game_id}")
async def proxy_game(game_id: str):
    """Proxy Lichess game PGN export."""
    cache = get_cache()
    key = cache_key("lichess-game", game_id)
    cached = await cache.get(key)
    if cached is not None:
        return PlainTextResponse(cached, media_type="application/x-chess-pgn")
    url = f"{LICHESS_GAME_BASE}/game/export/{game_id}"
    client = get_http_client()
    try:
        resp = await client.get(url, headers={"Accept": "application/x-chess-pgn"})
    except httpx.HTTPError:
        return PlainTextResponse("", status_code=502)
    if resp.status_code != 200:
        return PlainTextResponse("", status_code=resp.status_code)
    await cache.set(key, resp.text, ttl=_GAME_PGN_CACHE_TTL)
    return PlainTextResponse(resp.text, media_type="application/x-chess-pgn")


@app.get("/api/opening")
async def proxy_opening(play: str = ""):
    """Proxy opening info via Lichess master explorer."""
    cache = get_cache()
    key = cache_key("opening", hash_payload(play))
    cached = await cache.get(key)
    if cached is not None:
        return JSONResponse(cached["body"], status_code=cached["status"])
    url = f"{LICHESS_EXPLORER_BASE}/masters?play={play}&topGames=0&moves=0"
    client = get_http_client()
    try:
        resp = await client.get(url, headers={"Accept": "application/json"})
    except httpx.HTTPError as exc:
        return JSONResponse({"error": str(exc)}, status_code=502)
    try:
        body = resp.json()
    except ValueError:
        return JSONResponse({"error": "invalid upstream response"}, status_code=502)
    if resp.status_code == 200:
        await cache.set(key, {"status": resp.status_code, "body": body}, ttl=_OPENING_CACHE_TTL)
    return JSONResponse(body, status_code=resp.status_code)


# ---------------------------------------------------------------------------
# Database endpoints
# ---------------------------------------------------------------------------

# Cache TTLs for idempotent GET endpoints.
_DATABASES_CACHE_TTL = 60.0
_GAMES_CACHE_TTL = 60.0
_GAME_DETAIL_CACHE_TTL = 300.0
_TREE_CACHE_TTL = 300.0


@app.get("/api/databases")
async def list_databases():
    cache = get_cache()
    key = cache_key("databases", "list")
    cached = await cache.get(key)
    if cached is not None:
        return cached
    if _tcl_bridge.is_available():
        data = await _tcl_bridge.list_databases()
        if data is not None:
            await cache.set(key, data, ttl=_DATABASES_CACHE_TTL)
            return data
    await cache.set(key, MOCK_DATABASES, ttl=_DATABASES_CACHE_TTL)
    return MOCK_DATABASES


@app.post("/api/databases")
async def create_database(req: CreateDatabaseRequest):
    db = {
        "id": f"db-{uuid.uuid4().hex[:8]}",
        "name": req.name,
        "format": req.format,
        "games": req.games,
        "readOnly": req.readOnly,
    }
    try:
        created = await store.create_database(db)
    except Exception:
        MOCK_DATABASES.append(db)
        created = db
    # Invalidate the cached database list so the new database shows up.
    await get_cache().clear_prefix(cache_key("databases"))
    await get_cache().clear_prefix(cache_key("indexes"))
    await get_cache().clear_prefix(cache_key("eco"))
    return created


@app.get("/api/databases/{database_id}/games")
async def list_games(database_id: str):
    cache = get_cache()
    key = cache_key("games", database_id, "list")
    cached = await cache.get(key)
    if cached is not None:
        return cached
    if _tcl_bridge.is_available():
        data = await _tcl_bridge.list_games(database_id)
        if data is not None:
            await cache.set(key, data, ttl=_GAMES_CACHE_TTL)
            return data
    await cache.set(key, MOCK_GAMES, ttl=_GAMES_CACHE_TTL)
    return MOCK_GAMES


@app.get("/api/games/{game_id}")
async def get_game(game_id: str):
    """Return full game detail (headers, moves, pgn) for a single game."""
    cache = get_cache()
    key = cache_key("game", game_id)
    cached = await cache.get(key)
    if cached is not None:
        return cached
    if _tcl_bridge.is_available():
        data = await _tcl_bridge.get_game(game_id)
        if data is not None:
            await cache.set(key, data, ttl=_GAME_DETAIL_CACHE_TTL)
            return data
    game = next((g for g in MOCK_GAMES if g["id"] == game_id), None)
    if not game:
        return JSONResponse({"error": "not found"}, status_code=404)
    detail = _build_game_detail(game)
    await cache.set(key, detail, ttl=_GAME_DETAIL_CACHE_TTL)
    return detail


def _build_game_detail(game: dict) -> dict:
    """Build a GameDetail dict from a GameSummary entry."""
    pgn = _game_pgn(game)
    return {
        "id": game["id"],
        "headers": {
            "Event": game.get("event", ""),
            "Site": game.get("site", ""),
            "Date": game.get("date", ""),
            "White": game.get("white", ""),
            "Black": game.get("black", ""),
            "WhiteElo": str(game.get("whiteElo", "")),
            "BlackElo": str(game.get("blackElo", "")),
            "Result": game.get("result", ""),
            "ECO": game.get("eco", ""),
        },
        "moves": _parse_moves_from_pgn(pgn),
        "pgn": pgn,
    }


def _game_pgn(game: dict) -> str:
    """Return a minimal PGN string for a mock game."""
    return (
        f'[Event "{game.get("event", "?")}"]\n'
        f'[Site "{game.get("site", "?")}"]\n'
        f'[Date "{game.get("date", "?")}"]\n'
        f'[White "{game.get("white", "?")}"]\n'
        f'[Black "{game.get("black", "?")}"]\n'
        f'[WhiteElo "{game.get("whiteElo", "")}"]\n'
        f'[BlackElo "{game.get("blackElo", "")}"]\n'
        f'[Result "{game.get("result", "*")}"]\n'
        f'1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 *\n'
    )


def _parse_moves_from_pgn(pgn: str) -> list[dict]:
    """Parse a PGN movetext into a flat list of move dicts (mock)."""
    movetext_lines = [l for l in pgn.split("\n") if not l.startswith("[")]
    movetext = " ".join(movetext_lines).strip()
    tokens = [
        t for t in movetext.split()
        if t and not t[0].isdigit() and t not in ("1-0", "0-1", "1/2-1/2", "*")
    ]
    moves: list[dict] = []
    ply = 0
    for san in tokens:
        if san.endswith("."):
            continue
        ply += 1
        moves.append({
            "id": f"m-{ply}",
            "san": san,
            "uci": "",
            "fen": "",
            "color": "w" if ply % 2 == 1 else "b",
            "ply": ply,
            "nags": [],
            "annotations": [],
            "variations": [],
        })
    return moves


# ---------------------------------------------------------------------------
# Import / Convert endpoints (streaming multipart + object storage)
# ---------------------------------------------------------------------------

# Chunk size for streaming upload reads, and the slack allowed on the
# declared Content-Length to account for multipart framing (boundaries and
# part headers) before an early 413 is issued.
_UPLOAD_CHUNK_SIZE = 1024 * 1024  # 1 MiB
_MULTIPART_FRAMING_SLACK = 64 * 1024  # 64 KiB


@app.post("/api/databases/{database_id}/import")
async def import_database(database_id: str, request: Request, file: UploadFile = File(...)):
    """Import a PGN or database file via streaming multipart upload.

    The file is stored in object storage (S3/R2) or local disk under
    ``uploads/{database_id}/{filename}``. A job is created to track progress.

    Hardening:
      - ``database_id`` and the uploaded filename are validated/sanitized
        before they are embedded in a storage key (path-traversal guard).
      - The declared Content-Length is checked up front for an early 413.
      - The body is read in chunks with the size cap enforced DURING the
        read, so oversized bodies are rejected without buffering more than
        the cap plus one chunk.
    """
    client_ip = _client_ip(request)
    if not await _check_rate_limit(client_ip, "/api/databases/{database_id}/import"):
        _audit_log("import.rate_limited", ip=client_ip, database=database_id)
        return JSONResponse({"error": "Rate limit exceeded. Try again in a minute."}, status_code=429)

    # Validate the database id before it is embedded in a storage key.
    if not security.is_safe_key_component(database_id):
        _audit_log("import.invalid_database_id", ip=client_ip, database=database_id)
        return JSONResponse({"error": "Invalid database id"}, status_code=400)

    # Early 413 from the declared Content-Length (includes multipart framing,
    # hence the slack). The streaming cap below is the authoritative check.
    declared = request.headers.get("content-length")
    if declared is not None:
        try:
            declared_len = int(declared)
        except ValueError:
            declared_len = -1
        if declared_len > MAX_UPLOAD_SIZE + _MULTIPART_FRAMING_SLACK:
            _audit_log("import.too_large", ip=client_ip, database=database_id,
                       declared_size=declared_len, limit=MAX_UPLOAD_SIZE)
            return JSONResponse(
                {"error": f"File exceeds maximum size of {MAX_UPLOAD_SIZE // (1024 * 1024)} MB"},
                status_code=413,
            )

    # Sanitize the uploaded filename (path-traversal guard) before use.
    try:
        safe_filename = security.sanitize_filename(file.filename)
    except ValueError as exc:
        _audit_log("import.bad_filename", ip=client_ip, database=database_id, filename=file.filename)
        return JSONResponse({"error": f"Invalid filename: {exc}"}, status_code=400)

    # Stream the body in chunks, enforcing the size cap during the read.
    contents = bytearray()
    while True:
        chunk = await file.read(_UPLOAD_CHUNK_SIZE)
        if not chunk:
            break
        contents.extend(chunk)
        if len(contents) > MAX_UPLOAD_SIZE:
            _audit_log("import.too_large", ip=client_ip, database=database_id,
                       size=len(contents), limit=MAX_UPLOAD_SIZE)
            return JSONResponse(
                {"error": f"File exceeds maximum size of {MAX_UPLOAD_SIZE // (1024 * 1024)} MB"},
                status_code=413,
            )

    # Validate PGN if the file looks like PGN
    file_text = bytes(contents).decode("utf-8", errors="replace")
    if not _validate_pgn(file_text):
        _audit_log("import.invalid_pgn", ip=client_ip, database=database_id, filename=safe_filename)
        return JSONResponse({"error": "Invalid PGN: malformed headers or movetext"}, status_code=400)

    storage_key = f"uploads/{database_id}/{safe_filename}"
    await _store_file(storage_key, bytes(contents))

    job_id = f"import-{uuid.uuid4().hex[:8]}"
    job_data = {
        "jobId": job_id,
        "type": "import",
        "status": "complete",
        "progress": 100,
        "total": 1,
        "databaseId": database_id,
        "filename": safe_filename,
        "storageKey": storage_key,
        "fileSize": len(contents),
    }
    await store.set_job(job_id, job_data)
    _JOBS[job_id] = job_data  # backward compat

    # Simulate progress events for the job (quick burst for mock)
    asyncio.create_task(_simulate_job_progress(job_id, "import", 10))

    _audit_log("import.success", ip=client_ip, database=database_id, filename=safe_filename, size=len(contents), jobId=job_id)

    # Invalidate cached game lists and database stats for this database.
    await get_cache().clear_prefix(cache_key("games", database_id))
    await get_cache().clear_prefix(cache_key("databases"))
    await get_cache().clear_prefix(cache_key("indexes"))
    await get_cache().clear_prefix(cache_key("eco"))

    return {"jobId": job_id, "status": "complete", "filename": safe_filename, "size": len(contents)}


@app.post("/api/databases/{database_id}/convert")
async def convert_database(database_id: str, req: ConvertRequest):
    """Convert a database to a target format (SCI, SI3, PGN, etc.).

    Creates a conversion job and publishes progress events. The actual
    conversion is delegated to the scidb runtime (not yet implemented); this
    endpoint creates the job and returns immediately.
    """
    job_id = f"convert-{uuid.uuid4().hex[:8]}"
    job_data = {
        "jobId": job_id,
        "type": "convert",
        "status": "running",
        "progress": 0,
        "total": 100,
        "databaseId": database_id,
        "targetFormat": req.targetFormat,
    }
    await store.set_job(job_id, job_data)
    _JOBS[job_id] = job_data  # backward compat

    # Simulate progress
    asyncio.create_task(_simulate_job_progress(job_id, "convert", 20))

    _audit_log("convert.start", database=database_id, targetFormat=req.targetFormat, jobId=job_id)

    return {"jobId": job_id, "status": "running", "targetFormat": req.targetFormat}


# ---------------------------------------------------------------------------
# Search endpoints
# ---------------------------------------------------------------------------

@app.post("/api/searches")
async def create_search(request: Request, req: SearchRequest):
    client_ip = _client_ip(request)
    if not await _check_rate_limit(client_ip, "/api/searches"):
        _audit_log("search.rate_limited", ip=client_ip, type=req.type)
        return JSONResponse({"error": "Rate limit exceeded. Try again in a minute."}, status_code=429)

    # Validate CQL queries server-side
    if req.type == "cql":
        cql_text = req.query.get("cql", "")
        if cql_text and not _validate_cql(cql_text):
            _audit_log("search.invalid_cql", ip=client_ip, type="cql")
            return JSONResponse({"error": "Invalid CQL: unbalanced parentheses or forbidden content"}, status_code=400)

    matchers = {
        "advanced": lambda g: _matches_advanced(g, req.query),
        "material": lambda g: _matches_material(g, req.query),
        "rating": lambda g: _matches_rating(g, req.query),
        "cql": lambda g: _matches_cql(g, req.query),
    }
    matcher = matchers.get(req.type, matchers["advanced"])
    # Use mock games when the store doesn't support list_games (e.g. no DB configured).
    try:
        games = await store.list_games(req.databaseId or "masters")
        if not games:
            games = MOCK_GAMES
    except Exception:
        games = MOCK_GAMES
    filtered = [g for g in games if matcher(g)]

    if _tcl_bridge.is_available():
        bridge_result = await _tcl_bridge.search(req.model_dump())
        if bridge_result is not None:
            job_id = bridge_result.get("jobId", f"search-{uuid.uuid4().hex[:8]}")
            # Store full results (including games) since the Tcl bridge is
            # stateless across subprocess calls and cannot serve results later.
            full_result = {
                "jobId": job_id,
                "status": "complete",
                "total": len(filtered),
                "games": filtered,
                "query": req.model_dump(),
            }
            bridge_job = {
                "jobId": job_id,
                "type": "search",
                "status": "complete",
                "progress": 100,
                "total": len(filtered),
                "result": full_result,
            }
            await store.set_job(job_id, bridge_job)
            _JOBS[job_id] = bridge_job
            return {"jobId": job_id, "status": "complete", "total": len(filtered)}

    job_id = f"search-{uuid.uuid4().hex[:8]}"
    job_data = {
        "jobId": job_id,
        "type": "search",
        "status": "complete",
        "progress": 100,
        "total": len(filtered),
        "result": {"jobId": job_id, "status": "complete", "total": len(filtered), "games": filtered, "query": req.model_dump()},
    }
    await store.set_job(job_id, job_data)
    _JOBS[job_id] = job_data  # backward compat

    return {"jobId": job_id, "status": "complete", "total": len(filtered)}


# ---------------------------------------------------------------------------
# Import PGN JSON variant
# ---------------------------------------------------------------------------

@app.post("/api/databases/{database_id}/import-pgn")
async def import_pgn_json(database_id: str, request: Request):
    """Import a PGN from a JSON body (programmatic / editor use-case)."""
    client_ip = _client_ip(request)
    if not await _check_rate_limit(client_ip, "/api/databases/{database_id}/import"):
        _audit_log("import.rate_limited", ip=client_ip, database=database_id)
        return JSONResponse({"error": "Rate limit exceeded. Try again in a minute."}, status_code=429)
    if not security.is_safe_key_component(database_id):
        return JSONResponse({"error": "Invalid database id"}, status_code=400)
    body = await request.json()
    file_text = str(body.get("pgn", ""))
    filename = security.sanitize_filename(str(body.get("filename", "import.pgn")))
    text_bytes = file_text.encode("utf-8")
    if len(text_bytes) > MAX_UPLOAD_SIZE:
        return JSONResponse({"error": f"PGN exceeds maximum size of {MAX_UPLOAD_SIZE // (1024 * 1024)} MB"}, status_code=413)
    if not _validate_pgn(file_text):
        return JSONResponse({"error": "Invalid PGN: malformed headers or movetext"}, status_code=400)
    storage_key = f"uploads/{database_id}/{filename}"
    await _store_file(storage_key, text_bytes)
    job_id = f"import-{uuid.uuid4().hex[:8]}"
    job_data = {"jobId": job_id, "type": "import", "status": "complete", "progress": 100, "total": 1, "databaseId": database_id, "filename": filename, "storageKey": storage_key, "fileSize": len(text_bytes)}
    await store.set_job(job_id, job_data)
    _JOBS[job_id] = job_data
    asyncio.create_task(_simulate_job_progress(job_id, "import", 10))
    await get_cache().clear_prefix(cache_key("games", database_id))
    await get_cache().clear_prefix(cache_key("databases"))
    await get_cache().clear_prefix(cache_key("indexes"))
    await get_cache().clear_prefix(cache_key("eco"))
    _audit_log("import.success", ip=client_ip, database=database_id, filename=filename, jobId=job_id)
    return {"jobId": job_id, "status": "complete", "filename": filename, "size": len(text_bytes)}


# ---------------------------------------------------------------------------
# Player center + repertoire + prep endpoints (Wave 3)
# ---------------------------------------------------------------------------

@app.get("/api/players")
async def list_players(q: str | None = None, limit: int = 20):
    return await store.search_players(query=q, limit=limit)


@app.get("/api/players/{player_id}/card")
async def get_player_card(player_id: str):
    card = await store.get_player_card(player_id)
    if not card:
        return JSONResponse({"error": "not found"}, status_code=404)
    return card


@app.post("/api/players/{player_id}/prep")
async def create_player_prep(player_id: str, req: PlayerPrepRequest):
    job_id = f"prep-{uuid.uuid4().hex[:8]}"
    job_data = {"jobId": job_id, "type": "report", "status": "running", "progress": 0, "total": 100, "databaseId": req.databaseId, "subject": player_id, "subjectType": "opponent", "color": req.color}
    await store.set_job(job_id, job_data)
    _JOBS[job_id] = job_data
    asyncio.create_task(_simulate_job_progress(job_id, "report", 15))
    return {"jobId": job_id, "status": "running", "type": "opponent"}


@app.get("/api/repertoires")
async def list_repertoires():
    return await store.list_repertoires()


@app.post("/api/prep/reports")
async def create_opening_prep(req: OpeningPrepRequest):
    repertoire = next((r for r in await store.list_repertoires() if r["id"] == req.repertoireId), None)
    job_id = f"prep-{uuid.uuid4().hex[:8]}"
    job_data = {"jobId": job_id, "type": "report", "status": "running", "progress": 0, "total": 100, "databaseId": req.databaseId, "subject": req.repertoireId, "subjectType": "opening", "repertoireName": repertoire["name"] if repertoire else req.repertoireId}
    await store.set_job(job_id, job_data)
    _JOBS[job_id] = job_data
    asyncio.create_task(_simulate_job_progress(job_id, "report", 15))
    return {"jobId": job_id, "status": "running", "type": "opening"}


# ---------------------------------------------------------------------------
# Maintenance + crosstable endpoints (Wave 4)
# ---------------------------------------------------------------------------

@app.post("/api/maintenance/jobs")
async def start_maintenance(req: MaintenanceRequest):
    job_id = f"maintenance-{uuid.uuid4().hex[:8]}"
    job_data = {"jobId": job_id, "type": "maintenance", "status": "running", "progress": 0, "total": 100, "databaseId": req.databaseId, "operation": req.operation}
    await store.set_job(job_id, job_data)
    _JOBS[job_id] = job_data
    asyncio.create_task(_simulate_job_progress(job_id, "maintenance", 20))
    return {"jobId": job_id, "status": "running", "operation": req.operation}


@app.get("/api/maintenance/reports/{report_id}")
async def get_maintenance_report(report_id: str):
    job = await store.get_job(report_id)
    if not job:
        return JSONResponse({"error": "not found"}, status_code=404)
    return {"jobId": report_id, "operation": job.get("operation", "unknown"), "databaseId": job.get("databaseId"), "status": job.get("status", "unknown"), "message": f"Maintenance '{job.get('operation')}' completed"}


@app.post("/api/crosstables/query")
async def query_crosstable(req: CrosstableQueryRequest):
    result = await store.query_crosstable(req.model_dump(exclude_unset=True))
    if not result:
        return JSONResponse({"error": "not found"}, status_code=404)
    return result


# ---------------------------------------------------------------------------
# Game viewer + editor endpoints (Wave 5)
# ---------------------------------------------------------------------------

SCIDB_DATABASE_READONLY = os.environ.get("SCIDB_DATABASE_READONLY", "1").strip() in {"1", "true", "yes"}


def _writable_backend_available() -> bool:
    return _tcl_bridge.is_available() and not SCIDB_DATABASE_READONLY


@app.get("/api/games/{game_id}/pgn")
async def get_game_pgn(game_id: str):
    if _tcl_bridge.is_available():
        data = await _tcl_bridge.get_game_pgn(game_id)
        if data is not None:
            return PlainTextResponse(data, media_type="application/x-chess-pgn")
    pgn = await store.get_game_pgn(game_id)
    if pgn is None:
        return JSONResponse({"error": "not found"}, status_code=404)
    return PlainTextResponse(pgn, media_type="application/x-chess-pgn")


@app.patch("/api/games/{game_id}")
async def update_game(game_id: str, req: GameUpdateRequest):
    if not _writable_backend_available():
        return JSONResponse({"error": "Writable chess database backend is unavailable."}, status_code=503)
    if _tcl_bridge.is_available():
        data = await _tcl_bridge.patch_game(game_id, req.model_dump(exclude_unset=True))
        if data is not None:
            await get_cache().clear_prefix(cache_key("game", game_id))
            await get_cache().clear_prefix(cache_key("games"))
            return data
    updated = await store.patch_game(game_id, req.model_dump(exclude_unset=True))
    if not updated:
        return JSONResponse({"error": "not found"}, status_code=404)
    await get_cache().clear_prefix(cache_key("game", game_id))
    await get_cache().clear_prefix(cache_key("games"))
    return updated


@app.post("/api/games/{game_id}/variations")
async def add_variation(game_id: str, req: VariationRequest):
    if not _writable_backend_available():
        return JSONResponse({"error": "Writable chess database backend is unavailable."}, status_code=503)
    if _tcl_bridge.is_available():
        data = await _tcl_bridge.add_game_variation(game_id, req.parentMoveId, req.model_dump(exclude_unset=True))
        if data is not None:
            await get_cache().clear_prefix(cache_key("game", game_id))
            return data
    updated = await store.add_game_variation(game_id, req.parentMoveId, req.model_dump(exclude_unset=True))
    if not updated:
        return JSONResponse({"error": "not found"}, status_code=404)
    await get_cache().clear_prefix(cache_key("game", game_id))
    return updated


@app.post("/api/games/{game_id}/moves/{move_id}/comments")
async def add_move_comment(game_id: str, move_id: str, req: MoveCommentRequest):
    if not _writable_backend_available():
        return JSONResponse({"error": "Writable chess database backend is unavailable."}, status_code=503)
    if _tcl_bridge.is_available():
        data = await _tcl_bridge.add_game_comment(game_id, move_id, req.model_dump(exclude_unset=True))
        if data is not None:
            await get_cache().clear_prefix(cache_key("game", game_id))
            return data
    updated = await store.add_game_comment(game_id, move_id, req.model_dump(exclude_unset=True))
    if not updated:
        return JSONResponse({"error": "not found"}, status_code=404)
    await get_cache().clear_prefix(cache_key("game", game_id))
    return updated


# ---------------------------------------------------------------------------
# Paginated games list (Wave 7)
# ---------------------------------------------------------------------------

@app.get("/api/databases/{database_id}/games")
async def list_games(database_id: str, page: int = 1, limit: int = 25, sort: str = "date", order: str = "desc", query: str | None = None):
    cache = get_cache()
    key = cache_key("games", database_id, "page", page, "limit", limit, "sort", sort, "order", order, "query", query or "")
    cached = await cache.get(key)
    if cached is not None:
        return cached
    if _tcl_bridge.is_available():
        data = await _tcl_bridge.paginate_games(database_id, page=page, limit=limit, sort=sort, order=order, query=query)
        if data is not None:
            await cache.set(key, data, ttl=_GAMES_CACHE_TTL)
            return data
    result = await store.paginate_games(database_id, page=page, limit=limit, sort=sort, order=order, query=query)
    await cache.set(key, result, ttl=_GAMES_CACHE_TTL)
    return result


# ---------------------------------------------------------------------------
# Explorer + opening-info proxy endpoints (Wave 6)
# ---------------------------------------------------------------------------

_EXPLORER_CACHE_TTL = 60.0


def _moves_to_play(moves: list[dict[str, str]]) -> str:
    return ",".join(m.get("uci", "") for m in moves if m.get("uci"))


@app.post("/api/explorer")
async def post_explorer(req: ExplorerRequest):
    play = _moves_to_play(req.moves)
    cache = get_cache()
    key = cache_key("explorer", play or "start", req.source, req.speed, ",".join(str(r) for r in (req.ratings or [])))
    cached = await cache.get(key)
    if cached is not None:
        return cached
    query = {"play": play, "speeds": req.speed or "blitz,rapid,classical", "topGames": 0}
    if req.ratings:
        query["ratings"] = ",".join(str(r) for r in req.ratings)
    data = await _explorer_proxy("lichess", query_string=_encode_query(query))
    if data is not None:
        reshaped = _reshape_lichess_explorer(data, req.moves)
        await cache.set(key, reshaped, ttl=_EXPLORER_CACHE_TTL)
        return reshaped
    await cache.set(key, MOCK_EXPLORER, ttl=_EXPLORER_CACHE_TTL)
    return MOCK_EXPLORER


@app.post("/api/explorer/elo")
async def post_explorer_elo(req: ExplorerRequest):
    play = _moves_to_play(req.moves)
    cache = get_cache()
    ratings_key = ",".join(str(r) for r in (req.ratings or []))
    key = cache_key("explorer-elo", play or "start", req.speed, ratings_key)
    cached = await cache.get(key)
    if cached is not None:
        return cached
    segments: list[dict[str, Any]] = []
    for band in ([[1200, 1500], [1500, 1900], [1900, 2200], [2200, 2500]] if not req.ratings else _bands_from_ratings(req.ratings)):
        query = {"play": play, "ratings": f"{band[0]}-{band[1]}", "topGames": 0}
        band_data = await _explorer_proxy("lichess", query_string=_encode_query(query))
        segments.append({"range": {"label": f"{band[0]}-{band[1]}", "min": band[0], "max": band[1]}, "data": _reshape_lichess_explorer(band_data or {}, req.moves)})
    await cache.set(key, segments, ttl=_EXPLORER_CACHE_TTL)
    return segments


@app.post("/api/explorer/historical")
async def post_explorer_historical(req: ExplorerRequest):
    play = _moves_to_play(req.moves)
    cache = get_cache()
    key = cache_key("explorer-hist", play or "start", req.speed, ",".join(str(r) for r in (req.ratings or [])))
    cached = await cache.get(key)
    if cached is not None:
        return cached
    data = await _explorer_proxy("lichess", query_string=_encode_query({"play": play, "topGames": 0}))
    reshaped: dict[str, Any] = {"yearlyData": [], "topGames": [], "totalGames": 0}
    if isinstance(data, dict):
        for m in data.get("moves", []):
            reshaped["totalGames"] += m.get("white", 0) + m.get("draws", 0) + m.get("black", 0)
        if reshaped["totalGames"]:
            for year in range(2014, 2025):
                reshaped["yearlyData"].append({"year": year, "count": max(1, reshaped["totalGames"] // 11)})
    await cache.set(key, reshaped, ttl=_EXPLORER_CACHE_TTL)
    return reshaped


@app.post("/api/opening-info")
async def post_opening_info(req: ExplorerRequest):
    play = _moves_to_play(req.moves)
    eco = await _lookup_eco(play)
    if eco:
        return eco
    data = await _explorer_proxy("lichess", query_string=_encode_query({"play": play, "topGames": 0}))
    opening = data.get("opening") if isinstance(data, dict) else None
    return opening or {"eco": "A00", "name": "Irregular Opening"}


async def _lookup_eco(play: str) -> dict[str, str] | None:
    if not play:
        return {"eco": "A00", "name": "Irregular Openings"}
    moves = play.split(",")
    if moves[0] == "d2d4":
        return {"eco": "A45", "name": "Indian Game"}
    if moves[0] == "e2e4":
        if len(moves) > 1 and moves[1] == "c7c5":
            return {"eco": "B90", "name": "Sicilian, Najdorf"}
        return {"eco": "B00", "name": "King's Pawn Opening"}
    if moves[0] == "g1f3":
        return {"eco": "A06", "name": "Reti Opening"}
    return None


def _encode_query(params: dict[str, Any]) -> str:
    parts = []
    for k, v in params.items():
        if v is None:
            continue
        if isinstance(v, list):
            for item in v:
                parts.append(f"{k}={item}")
        else:
            parts.append(f"{k}={v}")
    return "&".join(parts)


def _bands_from_ratings(ratings: list[int]) -> list[list[int]]:
    if len(ratings) >= 2:
        return [ratings[i:i + 2] for i in range(0, len(ratings) - 1, 2)]
    return [[1200, 1500], [1500, 1900], [1900, 2200], [2200, 2500]]


MOCK_EXPLORER: dict[str, Any] = {
    "white": 0,
    "draws": 0,
    "black": 0,
    "moves": [],
    "turn": "w",
    "topGames": [],
    "fen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
}


def _reshape_lichess_explorer(data: dict[str, Any], moves: list[dict[str, str]]) -> dict[str, Any]:
    fen = data.get("fen") or _moves_to_fen(moves)
    return {
        "white": data.get("white", 0),
        "draws": data.get("draws", 0),
        "black": data.get("black", 0),
        "moves": [{"uci": m.get("uci", ""), "san": m.get("san", ""), "white": m.get("white", 0), "draws": m.get("draws", 0), "black": m.get("black", 0), "averageRating": m.get("averageRating")} for m in data.get("moves", [])],
        "turn": "w" if len(moves) % 2 == 0 else "b",
        "topGames": [],
        "fen": fen,
        "opening": data.get("opening"),
    }


def _moves_to_fen(moves: list[dict[str, str]]) -> str:
    from chess import Board
    board = Board()
    for m in moves:
        uci = m.get("uci", "")
        if uci:
            try:
                board.push_uci(uci)
            except Exception:
                break
    return board.fen()



@app.get("/api/searches/{job_id}/results")
async def get_search_results(job_id: str):
    job = await store.get_job(job_id)
    if not job:
        if _tcl_bridge.is_available():
            data = await _tcl_bridge.get_search_results(job_id)
            if data is not None:
                return data
        return JSONResponse({"jobId": job_id, "status": "pending", "total": 0, "games": []}, status_code=404)
    return job["result"]


# ---------------------------------------------------------------------------
# Opening tree endpoint
# ---------------------------------------------------------------------------

@app.post("/api/tree/query")
async def tree_query(req: TreeQueryRequest):
    cache = get_cache()
    key = cache_key("tree", hash_payload(req.model_dump()))
    cached = await cache.get(key)
    if cached is not None:
        return cached
    if _tcl_bridge.is_available():
        data = await _tcl_bridge.tree_query(req.model_dump())
        if data is not None:
            await cache.set(key, data, ttl=_TREE_CACHE_TTL)
            return data
    await cache.set(key, MOCK_TREE, ttl=_TREE_CACHE_TTL)
    return MOCK_TREE


# ---------------------------------------------------------------------------
# Index browser + ECO endpoints
# ---------------------------------------------------------------------------

_INDEXES_CACHE_TTL = 300.0
_ECO_CACHE_TTL = 300.0
_VALID_INDEX_TYPES = {"players", "events", "sites", "annotators"}


@app.get("/api/indexes/{index_type}")
async def list_indexes(index_type: str):
    """Return namebase entries for the given index type."""
    if index_type not in _VALID_INDEX_TYPES:
        return JSONResponse(
            {"error": f"Invalid index type '{index_type}'. Valid types: {sorted(_VALID_INDEX_TYPES)}"},
            status_code=400,
        )
    cache = get_cache()
    key = cache_key("indexes", index_type)
    cached = await cache.get(key)
    if cached is not None:
        return cached
    data = await store.list_namebase(index_type)
    await cache.set(key, data, ttl=_INDEXES_CACHE_TTL)
    return data


@app.get("/api/eco")
async def list_eco():
    """Return the ECO classification table."""
    cache = get_cache()
    key = cache_key("eco", "table")
    cached = await cache.get(key)
    if cached is not None:
        return cached
    data = await store.list_eco()
    await cache.set(key, data, ttl=_ECO_CACHE_TTL)
    return data


# ---------------------------------------------------------------------------
# Engines endpoint
# ---------------------------------------------------------------------------

@app.get("/api/engines")
async def list_engines():
    """List available UCI engines."""
    return _available_engines()


# ---------------------------------------------------------------------------
# Analysis endpoints
# ---------------------------------------------------------------------------

@app.post("/api/analysis/start")
async def start_analysis(request: Request, req: AnalysisStartRequest, authorization: str | None = Header(default=None)):
    client_ip = _client_ip(request)
    if not await _check_rate_limit(client_ip, "/api/analysis/start"):
        _audit_log("analysis.rate_limited", ip=client_ip)
        return JSONResponse({"error": "Rate limit exceeded. Try again in a minute."}, status_code=429)

    # Rated-game engine lock (docs/ONLINE_PLAY_PLAN.md §5.2, Phase 7): refuse to
    # start an engine for a user with an active rated match. Guests can never
    # be in a rated match (play_routes rejects rated seeks from guests), so
    # only an authenticated subject needs checking here.
    auth_payload = _get_auth_payload_sync(authorization)
    if auth_payload:
        sub = auth_payload.get("sub") or auth_payload.get("id")
        if sub and play_service.is_user_in_rated_match(sub):
            _audit_log("analysis.engine_locked", ip=client_ip, user=sub)
            return JSONResponse({"error": "Engine disabled during a rated game", "code": "rated_engine_lock"}, status_code=403)

    # Validate FEN server-side (accept "start" as alias for the initial position)
    fen = req.fen or DEFAULT_FEN
    if fen == "start":
        fen = DEFAULT_FEN
    if not _validate_fen(fen):
        _audit_log("analysis.invalid_fen", ip=client_ip, fen=fen[:100])
        return JSONResponse({"error": "Invalid FEN"}, status_code=400)

    job_id = f"analysis-{uuid.uuid4().hex[:8]}"
    analysis_data = {
        "jobId": job_id,
        "status": "running",
        "fen": fen,
        "depth": 0,
        "multiPv": req.multiPv,
        "lines": [],
        "nodes": 0,
        "nps": 0,
        "engineId": req.engineId,
    }
    await store.set_analysis(job_id, analysis_data)
    _ANALYSIS[job_id] = analysis_data  # backward compat

    engine_path = _resolve_engine_path(req.engineId)

    if engine_path and os.path.isfile(engine_path):
        # Acquire an engine-pool slot; respond 429 if all slots are busy.
        pool = get_engine_pool()
        if not await pool.try_acquire():
            _audit_log(
                "analysis.engine_busy",
                ip=client_ip,
                jobId=job_id,
                engine=req.engineId,
            )
            return JSONResponse(
                {"error": "Engine busy", "engine": pool.stats()},
                status_code=429,
            )

        # Real UCI engine analysis
        time_limit = max(req.depth * 2.0, 10.0)  # generous timeout
        task = asyncio.create_task(
            _run_real_analysis(
                job_id,
                engine_path,
                fen,
                req.depth,
                req.multiPv,
                time_limit_s=time_limit,
            )
        )

        # Ensure the pool slot is released when the worker finishes, even if
        # _run_real_analysis returns early or crashes.
        def _release_pool_slot(future):
            try:
                future.result()
            except Exception:
                pass
            try:
                pool.release()
            except RuntimeError:
                pass

        task.add_done_callback(_release_pool_slot)
    else:
        # Fallback: mock simulation
        asyncio.create_task(_simulate_analysis(job_id, req.depth, req.multiPv))
    return {"jobId": job_id, "status": "running"}


@app.get("/api/analysis/{job_id}")
async def get_analysis(job_id: str):
    job = await store.get_analysis(job_id)
    if not job:
        return JSONResponse({"jobId": job_id, "status": "unknown"}, status_code=404)
    return {k: v for k, v in job.items()}


@app.post("/api/analysis/{job_id}/stop")
async def stop_analysis(job_id: str):
    job = await store.get_analysis(job_id)
    if job:
        job["status"] = "stopped"
        await store.set_analysis(job_id, job)
    return {"jobId": job_id, "status": job["status"] if job else "unknown"}


# ---------------------------------------------------------------------------
# Workspace endpoint
# ---------------------------------------------------------------------------

@app.get("/api/workspace")
async def get_workspace():
    if _tcl_bridge.is_available():
        data = await _tcl_bridge.workspace()
        if data is not None:
            return data
    return {"activeDatabaseId": "masters", "currentFen": "start"}


# ---------------------------------------------------------------------------
# Jobs endpoint
# ---------------------------------------------------------------------------

@app.get("/api/jobs/{job_id}")
async def get_job(job_id: str):
    job = await store.get_job(job_id) or await store.get_analysis(job_id)
    if not job:
        return JSONResponse({"jobId": job_id, "status": "unknown"}, status_code=404)
    return {k: v for k, v in job.items() if k != "result"}


@app.delete("/api/jobs/{job_id}")
async def delete_job(job_id: str):
    """Delete a job from the store.

    For analysis jobs, also delete the analysis record.
    Returns 204 on success, 404 if the job does not exist.
    """
    job = await store.get_job(job_id)
    if not job:
        analysis = await store.get_analysis(job_id)
        if not analysis:
            return JSONResponse({"error": "not found"}, status_code=404)
        await store.delete_analysis(job_id)
        _ANALYSIS.pop(job_id, None)
        return JSONResponse({"jobId": job_id, "status": "deleted"}, status_code=200)
    await store.delete_job(job_id)
    _JOBS.pop(job_id, None)
    # Also clean up analysis if this was an analysis job
    analysis = await store.get_analysis(job_id)
    if analysis:
        await store.delete_analysis(job_id)
        _ANALYSIS.pop(job_id, None)
    return JSONResponse({"jobId": job_id, "status": "deleted"}, status_code=200)


@app.post("/api/jobs/{job_id}/cancel")
async def cancel_job(job_id: str):
    """Cancel a running job.

    Sets job status to "cancelled" and publishes a job.cancelled event.
    For analysis jobs, also delegates to the stop-analysis logic.
    Returns 404 if the job does not exist.
    """
    job = await store.get_job(job_id)
    if not job:
        analysis = await store.get_analysis(job_id)
        if not analysis:
            return JSONResponse({"error": "not found"}, status_code=404)
        # Analysis job cancel → stop
        analysis["status"] = "cancelled"
        await store.set_analysis(job_id, analysis)
        _ANALYSIS[job_id] = analysis
        await _publish_analysis(job_id, {**analysis, "type": "analysis.cancelled"})
        return {"jobId": job_id, "status": "cancelled"}
    job["status"] = "cancelled"
    await store.set_job(job_id, job)
    _JOBS[job_id] = job
    await _publish_event({
        "type": "job.cancelled",
        "jobId": job_id,
        "jobType": job.get("type", "unknown"),
        "timestamp": time.time(),
    })
    return {"jobId": job_id, "status": "cancelled"}


# ---------------------------------------------------------------------------
# Search cancel endpoint
# ---------------------------------------------------------------------------

@app.delete("/api/searches/{job_id}")
async def delete_search(job_id: str):
    """Cancel and delete a search job.

    Marks the search as cancelled, publishes a search.cancelled event,
    then deletes it from the store.
    Returns 204 on success, 404 if the search does not exist.
    """
    job = await store.get_job(job_id)
    if not job:
        return JSONResponse({"error": "not found"}, status_code=404)
    job["status"] = "cancelled"
    await store.set_job(job_id, job)
    await _publish_event({
        "type": "search.cancelled",
        "jobId": job_id,
        "timestamp": time.time(),
    })
    await store.delete_job(job_id)
    _JOBS.pop(job_id, None)
    return JSONResponse({"jobId": job_id, "status": "deleted"}, status_code=200)


# ---------------------------------------------------------------------------
# Export endpoint
# ---------------------------------------------------------------------------

@app.post("/api/databases/{database_id}/export")
async def export_database(database_id: str, req: ExportRequest):
    """Create an export job for a database.

    Request body: { format: str, gameIds?: list[str] }
    Returns a JobProgress object with status "running".
    The actual export is deferred to Phase 4 (Tcl ::scidb::view::export);
    for now the job stays "running" and will be completed by future work.
    """
    job_id = f"export-{uuid.uuid4().hex[:8]}"
    job_data = {
        "jobId": job_id,
        "type": "export",
        "status": "running",
        "progress": 0,
        "total": 100,
        "databaseId": database_id,
        "format": req.format,
        "gameIds": req.gameIds,
    }
    await store.set_job(job_id, job_data)
    _JOBS[job_id] = job_data  # backward compat

    _audit_log("export.start", database=database_id, format=req.format, jobId=job_id)

    return {"jobId": job_id, "status": "running", "format": req.format}


# ---------------------------------------------------------------------------
# WebSocket endpoints
# ---------------------------------------------------------------------------

@app.websocket("/api/ws/events")
async def ws_events(websocket: WebSocket):
    """Stream job progress events for imports, searches, reports, maintenance.

    When Redis is configured, subscribes to the ``scidb:events`` pub/sub
    channel. Otherwise uses the in-memory queue.
    """
    await websocket.accept()
    websocket_opened("events")
    try:
        redis = _get_redis()

        if redis:
            pubsub = redis.pubsub()
            await pubsub.subscribe(_EVENT_BUS_CHANNEL)
            try:
                async for message in pubsub.listen():
                    if message["type"] == "message":
                        await websocket.send_text(message["data"])
            except WebSocketDisconnect:
                pass
            finally:
                await pubsub.unsubscribe(_EVENT_BUS_CHANNEL)
        else:
            queue: asyncio.Queue = asyncio.Queue()
            _GLOBAL_EVENT_SUBSCRIBERS.append(queue)
            try:
                while True:
                    get_task = asyncio.create_task(queue.get())
                    recv_task = asyncio.create_task(_ws_receive_or_disconnect(websocket))
                    done, pending = await asyncio.wait(
                        [get_task, recv_task],
                        return_when=asyncio.FIRST_COMPLETED,
                    )
                    for task in pending:
                        task.cancel()
                    if recv_task in done:
                        # Client disconnected (or sent unexpected data)
                        raise WebSocketDisconnect()
                    if get_task in done:
                        event = get_task.result()
                        await websocket.send_json(event)
            except WebSocketDisconnect:
                pass
            finally:
                if queue in _GLOBAL_EVENT_SUBSCRIBERS:
                    _GLOBAL_EVENT_SUBSCRIBERS.remove(queue)
    finally:
        websocket_closed("events")


@app.websocket("/api/ws/analysis/{job_id}")
async def ws_analysis(websocket: WebSocket, job_id: str):
    """Stream engine analysis updates for a specific job.

    When Redis is configured, subscribes to ``scidb:analysis:{job_id}``.
    Otherwise uses the in-memory queue.
    """
    await websocket.accept()
    websocket_opened("analysis")
    try:
        redis = _get_redis()
        channel = f"{_ANALYSIS_BUS_CHANNEL}:{job_id}"

        if redis:
            pubsub = redis.pubsub()
            await pubsub.subscribe(channel)
            try:
                async for message in pubsub.listen():
                    if message["type"] == "message":
                        await websocket.send_text(message["data"])
            except WebSocketDisconnect:
                pass
            finally:
                await pubsub.unsubscribe(channel)
        else:
            queue: asyncio.Queue = asyncio.Queue()
            _ANALYSIS_SUBSCRIBERS.setdefault(job_id, []).append(queue)
            try:
                while True:
                    get_task = asyncio.create_task(queue.get())
                    recv_task = asyncio.create_task(_ws_receive_or_disconnect(websocket))
                    done, pending = await asyncio.wait(
                        [get_task, recv_task],
                        return_when=asyncio.FIRST_COMPLETED,
                    )
                    for task in pending:
                        task.cancel()
                    if recv_task in done:
                        raise WebSocketDisconnect()
                    if get_task in done:
                        data = get_task.result()
                        await websocket.send_json(data)
            except WebSocketDisconnect:
                pass
            finally:
                subs = _ANALYSIS_SUBSCRIBERS.get(job_id, [])
                if queue in subs:
                    subs.remove(queue)
    finally:
        websocket_closed("analysis")


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    # Fail closed on unsafe configuration (the uvicorn lifespan also runs
    # this check; validating here too covers embedding use-cases).
    security.validate_security_config()
    uvicorn.run(app, host="0.0.0.0", port=5001)
