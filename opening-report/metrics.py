"""Prometheus metrics endpoint + ASGI middleware (Phase 2 observability).

Exposes ``GET /metrics`` in the Prometheus text exposition format and records
per-request counters/histograms, open WebSocket connections, cache results,
and active analysis jobs.

When ``prometheus-client`` is not installed the module degrades gracefully:
the middleware becomes a pass-through and the endpoint returns HTTP 501.

Path normalisation replaces id-like URL segments with ``{id}`` to bound label
cardinality (job ids, game ids, Lichess game ids, uuid fragments).
"""

from __future__ import annotations

import re
import time
from typing import Any

try:
    from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest
    _HAVE_PROM = True
except ImportError:  # pragma: no cover - exercised when dependency missing
    _HAVE_PROM = False

if _HAVE_PROM:
    HTTP_REQUESTS = Counter(
        "scidb_http_requests_total",
        "HTTP requests handled by the runtime adapter",
        ["method", "path", "status"],
    )
    HTTP_DURATION = Histogram(
        "scidb_http_request_duration_seconds",
        "HTTP request latency in seconds",
        ["method", "path"],
        buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0),
    )
    WS_CONNECTIONS = Gauge(
        "scidb_websocket_connections",
        "Currently open WebSocket connections",
        ["endpoint"],
    )
    ANALYSIS_ACTIVE = Gauge(
        "scidb_analysis_jobs_active",
        "Currently running engine analysis jobs",
    )
    CACHE_RESULTS = Counter(
        "scidb_cache_results_total",
        "Cache lookups by backend and result",
        ["backend", "result"],
    )
    PLAY_MATCHES_ACTIVE = Gauge(
        "scidb_play_matches_active",
        "Currently active (playing) online-play matches",
    )
    PLAY_SEEKS_OPEN = Gauge(
        "scidb_play_seeks_open",
        "Currently open (unmatched) online-play seeks",
    )
    PLAY_MOVE_LATENCY = Histogram(
        "scidb_play_move_latency_seconds",
        "Wall-clock time between consecutive moves in a match",
        buckets=(0.1, 0.25, 0.5, 1.0, 2.0, 5.0, 10.0, 30.0, 60.0),
    )
    PLAY_TIMEOUTS = Counter(
        "scidb_play_timeouts_total",
        "Matches finished by clock timeout",
    )
    PLAY_FLAGGED_GAMES = Counter(
        "scidb_play_flagged_games_total",
        "Matches flagged by anti-cheat heuristics",
        ["reason"],
    )


_ID_PREFIX_RE = re.compile(r"^(analysis|import|search|convert|job|db|g|m)-", re.IGNORECASE)
_HEX_RE = re.compile(r"^[0-9a-f]{8,}(-[0-9a-f]{4,}){0,4}$", re.IGNORECASE)
_LICHESS_ID_RE = re.compile(r"^[A-Za-z0-9]{8,12}$")


def _looks_like_id(segment: str) -> bool:
    if segment.isdigit():
        return True
    if _ID_PREFIX_RE.match(segment):
        return True
    if _HEX_RE.match(segment):
        return True
    # Lichess-style game ids: mixed alnum, 8-12 chars, contains both letters
    # and digits but no separators (plain words like "masters" are kept).
    if _LICHESS_ID_RE.match(segment) and any(c.isdigit() for c in segment) and any(c.isalpha() for c in segment):
        return True
    return False


def normalize_path(path: str) -> str:
    """Replace id-like path segments with ``{id}`` to bound cardinality."""
    if not path or path == "/":
        return path or "/"
    return "/".join(
        "{id}" if (seg and _looks_like_id(seg)) else seg for seg in path.split("/")
    )


def record_cache_result(hit: bool, backend: str) -> None:
    """Record a cache hit/miss (no-op without prometheus-client)."""
    if _HAVE_PROM:
        CACHE_RESULTS.labels(backend=backend, result="hit" if hit else "miss").inc()


def websocket_opened(endpoint: str) -> None:
    if _HAVE_PROM:
        WS_CONNECTIONS.labels(endpoint=endpoint).inc()


def websocket_closed(endpoint: str) -> None:
    if _HAVE_PROM:
        WS_CONNECTIONS.labels(endpoint=endpoint).dec()


def analysis_started() -> None:
    if _HAVE_PROM:
        ANALYSIS_ACTIVE.inc()


def analysis_finished() -> None:
    if _HAVE_PROM:
        ANALYSIS_ACTIVE.dec()


def play_match_started() -> None:
    if _HAVE_PROM:
        PLAY_MATCHES_ACTIVE.inc()


def play_match_finished() -> None:
    if _HAVE_PROM:
        PLAY_MATCHES_ACTIVE.dec()


def play_seek_opened() -> None:
    if _HAVE_PROM:
        PLAY_SEEKS_OPEN.inc()


def play_seek_closed() -> None:
    if _HAVE_PROM:
        PLAY_SEEKS_OPEN.dec()


def play_move_latency(seconds: float) -> None:
    if _HAVE_PROM:
        PLAY_MOVE_LATENCY.observe(seconds)


def play_timeout() -> None:
    if _HAVE_PROM:
        PLAY_TIMEOUTS.inc()


def play_flagged(reason: str) -> None:
    if _HAVE_PROM:
        PLAY_FLAGGED_GAMES.labels(reason=reason).inc()


_EXCLUDED_PATHS = frozenset({"/metrics", "/api/health/live", "/api/health/ready"})


class MetricsMiddleware:
    """Pure-ASGI middleware recording request count and latency.

    No-ops (pass-through) when prometheus-client is unavailable. The metrics
    endpoint itself and the k8s-style health probes are excluded to avoid
    self-referential noise.
    """

    def __init__(self, app: Any) -> None:
        self.app = app

    async def __call__(self, scope: dict, receive: Any, send: Any) -> None:
        if scope.get("type") != "http" or not _HAVE_PROM:
            await self.app(scope, receive, send)
            return
        path = scope.get("path", "")
        if path in _EXCLUDED_PATHS:
            await self.app(scope, receive, send)
            return

        method = scope.get("method", "?")
        start = time.perf_counter()
        status = "500"

        async def send_wrapped(message: dict) -> None:
            nonlocal status
            if message.get("type") == "http.response.start":
                status = str(message.get("status", 500))
            await send(message)

        try:
            await self.app(scope, receive, send_wrapped)
        finally:
            elapsed = time.perf_counter() - start
            norm = normalize_path(path)
            HTTP_REQUESTS.labels(method=method, path=norm, status=status).inc()
            HTTP_DURATION.labels(method=method, path=norm).observe(elapsed)


async def metrics_endpoint() -> Any:
    """Serve the Prometheus text exposition format (or 501 when unavailable)."""
    from fastapi import Response
    from fastapi.responses import JSONResponse

    if not _HAVE_PROM:
        return JSONResponse(
            {"error": "prometheus-client is not installed"},
            status_code=501,
        )
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)
