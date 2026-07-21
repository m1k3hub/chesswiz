"""Abstract storage backend for the scidb-beta runtime adapter.

Three implementations:
  - MemoryStore   — in-memory dicts (default; matches existing behavior)
  - RedisStore    — Redis for jobs, analysis, rate-limit counters, pub/sub events
  - PostgresStore — PostgreSQL for databases, games, users, audit logs,
                    workspaces, and a durable shadow of jobs/analysis

PostgresStore uses the SQLAlchemy **async** engine (``asyncpg`` driver) so
no blocking database call ever runs on the FastAPI event loop. It also
*dual-writes* job and analysis records: the live copy goes to the event
backend (RedisStore when REDIS_URL is set, otherwise an in-process
MemoryStore) and a durable copy is upserted into the ``jobs`` / ``analysis``
tables. Reads prefer the live backend and fall back to PostgreSQL, so job
state survives a Redis flush or restart.

Durability policy: PostgreSQL write failures are logged and swallowed (the
live Redis/memory copy still succeeds); the durable copy is a shadow, not
the primary path. Databases/games/users/audit writes always go straight to
PostgreSQL and propagate failures.
"""

from __future__ import annotations

import asyncio
import json
import os
import time
import uuid
from contextlib import asynccontextmanager
from typing import Any, AsyncIterator

import config

# Re-export for backwards compatibility with modules that import it from here.
normalize_database_url_for_async = config.normalize_database_url_for_async

# ---------------------------------------------------------------------------
# Environment detection
# ---------------------------------------------------------------------------

REDIS_URL = os.environ.get("REDIS_URL", "")
DATABASE_URL = os.environ.get("DATABASE_URL", "")

# TTLs for live (Redis) job/analysis records. The durable PostgreSQL shadow
# has no TTL.
JOB_TTL_SECONDS = int(os.environ.get("SCIDB_JOB_TTL_SECONDS", "86400"))
ANALYSIS_TTL_SECONDS = int(os.environ.get("SCIDB_ANALYSIS_TTL_SECONDS", "86400"))


# ---------------------------------------------------------------------------
# Base interface
# ---------------------------------------------------------------------------


class Store:
    """Abstract storage interface used by runtime_adapter.py."""

    # --- Jobs -----------------------------------------------------------------

    async def get_job(self, job_id: str) -> dict[str, Any] | None:
        raise NotImplementedError

    async def set_job(self, job_id: str, data: dict[str, Any]) -> None:
        raise NotImplementedError

    async def delete_job(self, job_id: str) -> None:
        raise NotImplementedError

    async def list_jobs(self) -> list[dict[str, Any]]:
        raise NotImplementedError

    # --- Analysis -------------------------------------------------------------

    async def get_analysis(self, job_id: str) -> dict[str, Any] | None:
        raise NotImplementedError

    async def set_analysis(self, job_id: str, data: dict[str, Any]) -> None:
        raise NotImplementedError

    async def delete_analysis(self, job_id: str) -> None:
        raise NotImplementedError

    # --- Rate limiting --------------------------------------------------------

    async def check_rate_limit(self, client_ip: str, route_key: str, max_requests: int, window_seconds: float) -> bool:
        """Return True if within limit, False if exceeded."""
        raise NotImplementedError

    # --- Event bus (pub/sub) ---------------------------------------------------

    async def publish_event(self, event: dict[str, Any]) -> None:
        raise NotImplementedError

    async def publish_analysis(self, job_id: str, data: dict[str, Any]) -> None:
        raise NotImplementedError

    async def subscribe_events(self) -> Any:
        """Return an async generator or queue-like object yielding event dicts."""
        raise NotImplementedError

    async def subscribe_analysis(self, job_id: str) -> Any:
        raise NotImplementedError

    async def unsubscribe_events(self, subscription: Any) -> None:
        raise NotImplementedError

    async def unsubscribe_analysis(self, subscription: Any) -> None:
        raise NotImplementedError

    # --- Databases / Games / Users / Audit (PostgresStore overrides) ----------

    async def list_databases(self) -> list[dict[str, Any]]:
        raise NotImplementedError

    async def create_database(self, db: dict[str, Any]) -> dict[str, Any]:
        raise NotImplementedError

    async def list_games(self, database_id: str) -> list[dict[str, Any]]:
        raise NotImplementedError

    async def get_game(self, game_id: str) -> dict[str, Any] | None:
        raise NotImplementedError

    async def create_user(self, user: dict[str, Any]) -> dict[str, Any]:
        raise NotImplementedError

    async def get_user(self, user_id: str) -> dict[str, Any] | None:
        raise NotImplementedError

    async def add_audit_log(self, action: str, **fields: Any) -> None:
        pass  # no-op by default; MemoryStore logs to stdout

    # --- Index browser / ECO --------------------------------------------------

    async def list_namebase(self, index_type: str) -> list[dict[str, Any]]:
        """Return namebase entries for the given index type.

        ``index_type`` is one of ``players``, ``events``, ``sites``,
        ``annotators``.
        """
        raise NotImplementedError

    async def list_eco(self) -> list[dict[str, Any]]:
        """Return ECO classification table rows."""
        raise NotImplementedError

    # --- Player center / repertoire / prep -----------------------------------

    async def search_players(self, query: str | None = None, limit: int = 20) -> list[dict[str, Any]]:
        """Return player summaries matching an optional name prefix."""
        raise NotImplementedError

    async def get_player_card(self, player_id: str) -> dict[str, Any] | None:
        """Return detailed player statistics for the player card modal."""
        raise NotImplementedError

    async def list_repertoires(self) -> list[dict[str, Any]]:
        """Return saved repertoire lines."""
        raise NotImplementedError

    async def query_crosstable(self, query: dict[str, Any]) -> dict[str, Any] | None:
        """Return crosstable result for an event/site/player set."""
        raise NotImplementedError

    # --- Game editor ---------------------------------------------------------

    async def get_game_pgn(self, game_id: str) -> str | None:
        """Return the raw PGN text for a single game."""
        raise NotImplementedError

    async def patch_game(self, game_id: str, patch: dict[str, Any]) -> dict[str, Any] | None:
        """Update game headers and/or top-level comment. Requires writable backend."""
        raise NotImplementedError

    async def add_game_variation(self, game_id: str, move_id: str, variation: dict[str, Any]) -> dict[str, Any] | None:
        """Add a variation to a game. Requires writable backend."""
        raise NotImplementedError

    async def add_game_comment(self, game_id: str, move_id: str, comment: dict[str, Any]) -> dict[str, Any] | None:
        """Add a comment to a game move. Requires writable backend."""
        raise NotImplementedError

    async def paginate_games(
        self,
        database_id: str,
        page: int = 1,
        limit: int = 25,
        sort: str = "date",
        order: str = "desc",
        query: str | None = None,
    ) -> dict[str, Any]:
        """Return a paginated slice of games with total/totalPages metadata."""
        raise NotImplementedError

    # --- Lifecycle ------------------------------------------------------------

    async def close(self) -> None:
        pass


_SEED_REPERTOIRES: list[dict[str, Any]] = [
    {"id": "rep-white", "name": "White Repertoire: Queen's Pawn", "side": "white", "eco": "A45", "moves": [{"san": "d4", "uci": "d2d4", "fen": "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1"}, {"san": "Nf6", "uci": "g8f6", "fen": "rnbqkbnr/pppppppp/5n2/8/3P4/8/PPP1PPPP/RNBQKBNR w KQkq - 1 2"}, {"san": "c4", "uci": "c2c4", "fen": "rnbqkbnr/pppppppp/5n2/8/2PP4/8/PP2PPPP/RNBQKBNR b KQkq - 0 2"}], "updatedAt": "2024-01-15T10:00:00Z"},
    {"id": "rep-black", "name": "Black Repertoire: Sicilian", "side": "black", "eco": "B90", "moves": [{"san": "e4", "uci": "e2e4", "fen": "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"}, {"san": "c5", "uci": "c7c5", "fen": "rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2"}, {"san": "Nf3", "uci": "g1f3", "fen": "rnbqkbnr/pp1ppppp/8/2p5/4P3/5N2/PPPP1PPP/RNBQKBNR b KQkq - 1 2"}], "updatedAt": "2024-02-20T14:30:00Z"},
]

_SEED_CROSSTABLE: dict[str, Any] = {
    "event": "WCh 2021",
    "site": "Dubai UAE",
    "players": [
        {"player": "Carlsen, Magnus", "games": 11, "points": 7.5, "wins": 4, "draws": 7, "losses": 0, "sonnebornBerger": 52.25, "rank": 1},
        {"player": "Nepomniachtchi, Ian", "games": 11, "points": 3.5, "wins": 0, "draws": 7, "losses": 4, "sonnebornBerger": 28.75, "rank": 2},
    ],
    "totalRounds": 11,
}


def _game_pgn(game: dict[str, Any]) -> str:
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


# ---------------------------------------------------------------------------
# MemoryStore (default — in-memory dicts, in-process queues)
# ---------------------------------------------------------------------------

# Seed data so tests and dev work out of the box.

_SEED_DATABASES: list[dict[str, Any]] = [
    {"id": "masters", "name": "Master Games", "format": "SCI", "games": 2_400_000, "readOnly": True},
    {"id": "repertoire", "name": "My Repertoire", "format": "PGN", "games": 1842, "readOnly": False},
]

_SEED_GAMES: list[dict[str, Any]] = [
    {"id": "g-001", "white": "Carlsen, Magnus", "whiteElo": 2855, "black": "Nepomniachtchi, Ian", "blackElo": 2782, "event": "WCh 2021", "site": "Dubai UAE", "date": "2021.12.03", "result": "½–½", "eco": "A45"},
    {"id": "g-002", "white": "Kasparov, Garry", "whiteElo": 2810, "black": "Karpov, Anatoly", "blackElo": 2725, "event": "Linares", "site": "Linares ESP", "date": "1993.03.02", "result": "1-0", "eco": "D37"},
    {"id": "g-003", "white": "Polgar, Judit", "whiteElo": 2735, "black": "Anand, Viswanathan", "blackElo": 2774, "event": "Hoogeveen", "site": "Hoogeveen NED", "date": "2003.10.16", "result": "0-1", "eco": "B90"},
    {"id": "g-004", "white": "Fischer, Robert James", "whiteElo": 2785, "black": "Spassky, Boris", "blackElo": 2660, "event": "Reykjavik WCh", "site": "Reykjavik ISL", "date": "1972.07.23", "result": "1-0", "eco": "E56"},
]

# Seed namebase data — 4-8 entries per type for dev/test.
_SEED_NAMEBASE: dict[str, list[dict[str, Any]]] = {
    "players": [
        {"id": "p-001", "name": "Carlsen, Magnus", "elo": 2839, "title": "GM", "country": "NOR", "games": 2400},
        {"id": "p-002", "name": "Caruana, Fabiano", "elo": 2820, "title": "GM", "country": "USA", "games": 2100},
        {"id": "p-003", "name": "Nepomniachtchi, Ian", "elo": 2792, "title": "GM", "country": "RUS", "games": 1800},
        {"id": "p-004", "name": "Ding, Liren", "elo": 2780, "title": "GM", "country": "CHN", "games": 1600},
        {"id": "p-005", "name": "Anand, Viswanathan", "elo": 2754, "title": "GM", "country": "IND", "games": 3200},
        {"id": "p-006", "name": "Kasparov, Garry", "elo": 2812, "title": "GM", "country": "RUS", "games": 2500},
    ],
    "events": [
        {"id": "e-001", "name": "WCh 2021", "games": 11},
        {"id": "e-002", "name": "Linares", "games": 200},
        {"id": "e-003", "name": "Hoogeveen", "games": 30},
        {"id": "e-004", "name": "Reykjavik WCh", "games": 24},
        {"id": "e-005", "name": "Tata Steel", "games": 800},
    ],
    "sites": [
        {"id": "s-001", "name": "Dubai UAE", "games": 11},
        {"id": "s-002", "name": "Linares ESP", "games": 200},
        {"id": "s-003", "name": "Hoogeveen NED", "games": 30},
        {"id": "s-004", "name": "Reykjavik ISL", "games": 24},
        {"id": "s-005", "name": "Wijk aan Zee NED", "games": 800},
    ],
    "annotators": [
        {"id": "a-001", "name": "Kasparov, Garry", "games": 120},
        {"id": "a-002", "name": "Anand, Viswanathan", "games": 80},
        {"id": "a-003", "name": "Dvoretsky, Mark", "games": 50},
        {"id": "a-004", "name": "Rowson, Jonathan", "games": 30},
    ],
}

# Seed ECO table — representative subset.
_SEED_ECO: list[dict[str, Any]] = [
    {"code": "A00", "name": "Irregular Openings", "games": 120},
    {"code": "A45", "name": "Indian Game", "games": 3400},
    {"code": "A06", "name": "Reti Opening", "games": 2100},
    {"code": "B00", "name": "King's Pawn Opening", "games": 2800},
    {"code": "B90", "name": "Sicilian, Najdorf", "games": 5200},
    {"code": "C00", "name": "French Defence", "games": 4100},
    {"code": "D37", "name": "Queen's Gambit Declined", "games": 3800},
    {"code": "E56", "name": "Nimzo-Indian, Rubinstein", "games": 1900},
]


class MemoryStore(Store):
    """In-memory store — the default backend with no external dependencies."""

    def __init__(self) -> None:
        self._jobs: dict[str, dict[str, Any]] = {}
        self._analysis: dict[str, dict[str, Any]] = {}
        self._rate_buckets: dict[str, dict[str, list[float]]] = {}
        self._global_event_queues: list[asyncio.Queue] = []
        self._analysis_queues: dict[str, list[asyncio.Queue]] = {}
        self._databases: list[dict[str, Any]] = [dict(d) for d in _SEED_DATABASES]
        self._games: list[dict[str, Any]] = [dict(g) for g in _SEED_GAMES]
        self._users: dict[str, dict[str, Any]] = {}
        self._repertoires: list[dict[str, Any]] = [dict(r) for r in _SEED_REPERTOIRES]
        self._game_pgn: dict[str, str] = {}
        self._game_comments: dict[str, dict[str, dict[str, Any]]] = {}
        self._game_variations: dict[str, list[dict[str, Any]]] = {}

    async def get_job(self, job_id: str) -> dict[str, Any] | None:
        return self._jobs.get(job_id)

    async def set_job(self, job_id: str, data: dict[str, Any]) -> None:
        self._jobs[job_id] = data

    async def delete_job(self, job_id: str) -> None:
        self._jobs.pop(job_id, None)

    async def list_jobs(self) -> list[dict[str, Any]]:
        return list(self._jobs.values())

    async def get_analysis(self, job_id: str) -> dict[str, Any] | None:
        return self._analysis.get(job_id)

    async def set_analysis(self, job_id: str, data: dict[str, Any]) -> None:
        self._analysis[job_id] = data

    async def delete_analysis(self, job_id: str) -> None:
        self._analysis.pop(job_id, None)

    async def check_rate_limit(self, client_ip: str, route_key: str, max_requests: int, window_seconds: float) -> bool:
        now = time.monotonic()
        buckets = self._rate_buckets.setdefault(route_key, {})
        timestamps = buckets.get(client_ip, [])
        buckets[client_ip] = [t for t in timestamps if now - t < window_seconds]
        if len(buckets[client_ip]) >= max_requests:
            return False
        buckets[client_ip].append(now)
        return True

    async def publish_event(self, event: dict[str, Any]) -> None:
        for q in self._global_event_queues:
            await q.put(event)

    async def publish_analysis(self, job_id: str, data: dict[str, Any]) -> None:
        for q in self._analysis_queues.get(job_id, []):
            await q.put(data)

    async def subscribe_events(self) -> asyncio.Queue:
        q: asyncio.Queue = asyncio.Queue()
        self._global_event_queues.append(q)
        return q

    async def subscribe_analysis(self, job_id: str) -> asyncio.Queue:
        q: asyncio.Queue = asyncio.Queue()
        self._analysis_queues.setdefault(job_id, []).append(q)
        return q

    async def unsubscribe_events(self, subscription: Any) -> None:
        if isinstance(subscription, asyncio.Queue) and subscription in self._global_event_queues:
            self._global_event_queues.remove(subscription)

    async def unsubscribe_analysis(self, subscription: Any) -> None:
        # The subscription is a queue; remove it from all analysis queue lists.
        if isinstance(subscription, asyncio.Queue):
            for subs in self._analysis_queues.values():
                if subscription in subs:
                    subs.remove(subscription)

    async def list_databases(self) -> list[dict[str, Any]]:
        return list(self._databases)

    async def create_database(self, db: dict[str, Any]) -> dict[str, Any]:
        self._databases.append(db)
        return db

    async def list_games(self, database_id: str) -> list[dict[str, Any]]:
        return list(self._games)

    async def get_game(self, game_id: str) -> dict[str, Any] | None:
        for g in self._games:
            if g["id"] == game_id:
                return dict(g)
        return None

    async def create_user(self, user: dict[str, Any]) -> dict[str, Any]:
        self._users[user["id"]] = user
        return user

    async def get_user(self, user_id: str) -> dict[str, Any] | None:
        return self._users.get(user_id)

    async def add_audit_log(self, action: str, **fields: Any) -> None:
        entry = {"timestamp": time.time(), "action": action, **fields}
        print(json.dumps(entry, default=str, ensure_ascii=False), flush=True)

    async def list_namebase(self, index_type: str) -> list[dict[str, Any]]:
        return [dict(e) for e in _SEED_NAMEBASE.get(index_type, [])]

    async def list_eco(self) -> list[dict[str, Any]]:
        return [dict(e) for e in _SEED_ECO]

    # --- Player center / repertoire / prep -----------------------------------

    async def search_players(self, query: str | None = None, limit: int = 20) -> list[dict[str, Any]]:
        q = (query or "").lower()
        players = _SEED_NAMEBASE.get("players", [])
        if q:
            players = [p for p in players if q in p["name"].lower()]
        return [dict(p) for p in players[:limit]]

    async def get_player_card(self, player_id: str) -> dict[str, Any] | None:
        player = next((p for p in _SEED_NAMEBASE.get("players", []) if p["id"] == player_id), None)
        if not player:
            return None
        recent = [dict(g) for g in _SEED_GAMES if player["name"] in (g["white"], g["black"])][:5]
        return {
            "id": player["id"],
            "name": player["name"],
            "elo": player["elo"],
            "title": player.get("title"),
            "country": player.get("country"),
            "peakElo": player["elo"] + 25,
            "games": player["games"],
            "winRate": 0.48,
            "drawRate": 0.32,
            "lossRate": 0.20,
            "topOpenings": [
                {"eco": "C78", "name": "Ruy Lopez", "games": 120, "score": 0.55},
                {"eco": "D37", "name": "QGD", "games": 90, "score": 0.52},
            ],
            "recentGames": recent,
        }

    async def list_repertoires(self) -> list[dict[str, Any]]:
        return [dict(r) for r in self._repertoires]

    async def query_crosstable(self, query: dict[str, Any]) -> dict[str, Any] | None:
        event = query.get("event") or _SEED_CROSSTABLE["event"]
        site = query.get("site") or _SEED_CROSSTABLE["site"]
        players = query.get("players")
        rows = [dict(r) for r in _SEED_CROSSTABLE["players"]]
        if players:
            rows = [r for r in rows if r["player"] in players]
        return {
            "event": event,
            "site": site,
            "players": rows,
            "totalRounds": _SEED_CROSSTABLE["totalRounds"],
        }

    # --- Game editor ---------------------------------------------------------

    async def get_game_pgn(self, game_id: str) -> str | None:
        game = next((g for g in self._games if g["id"] == game_id), None)
        if not game:
            return None
        return self._game_pgn.get(game_id) or _game_pgn(game)

    async def patch_game(self, game_id: str, patch: dict[str, Any]) -> dict[str, Any] | None:
        game = next((g for g in self._games if g["id"] == game_id), None)
        if not game:
            return None
        if "headers" in patch:
            header_map = {"White": "white", "Black": "black", "Event": "event", "Site": "site", "Date": "date", "Result": "result", "ECO": "eco"}
            for k, v in patch["headers"].items():
                if k in header_map:
                    game[header_map[k]] = v
        return dict(game)

    async def add_game_variation(self, game_id: str, move_id: str, variation: dict[str, Any]) -> dict[str, Any] | None:
        game = next((g for g in self._games if g["id"] == game_id), None)
        if not game:
            return None
        entry = {
            "id": f"v-{len(self._game_variations.get(game_id, [])) + 1}",
            "parentMoveId": move_id,
            "moves": variation.get("moves", []),
            "comment": variation.get("comment"),
        }
        self._game_variations.setdefault(game_id, []).append(entry)
        return dict(game)

    async def add_game_comment(self, game_id: str, move_id: str, comment: dict[str, Any]) -> dict[str, Any] | None:
        game = next((g for g in self._games if g["id"] == game_id), None)
        if not game:
            return None
        self._game_comments.setdefault(game_id, {})[move_id] = comment.get("comment", comment)
        return dict(game)

    async def paginate_games(
        self,
        database_id: str,
        page: int = 1,
        limit: int = 25,
        sort: str = "date",
        order: str = "desc",
        query: str | None = None,
    ) -> dict[str, Any]:
        games = list(self._games)
        if query:
            q = query.lower()
            games = [
                g for g in games
                if q in g["white"].lower()
                or q in g["black"].lower()
                or q in g["event"].lower()
                or q in g.get("eco", "").lower()
            ]
        reverse = order.lower() == "desc"
        sort_key = sort if sort in {"white", "black", "event", "site", "date", "eco", "result"} else "date"
        games.sort(key=lambda g: g.get(sort_key, "") or "", reverse=reverse)
        total = len(games)
        start = (max(1, page) - 1) * limit
        end = start + limit
        return {
            "games": [dict(g) for g in games[start:end]],
            "page": page,
            "limit": limit,
            "total": total,
            "totalPages": max(1, (total + limit - 1) // limit),
        }


# ---------------------------------------------------------------------------
# RedisStore — jobs/analysis/rate-limit in Redis, pub/sub for events
# ---------------------------------------------------------------------------

_EVENT_BUS_CHANNEL = "scidb:events"
_ANALYSIS_BUS_CHANNEL = "scidb:analysis"

# Atomic sliding-window rate limit. Returns 1 when the request is allowed
# (and records it), 0 when the limit is exceeded (and records nothing).
_RATE_LIMIT_LUA = """
local key = KEYS[1]
local now = tonumber(ARGV[1])
local window = tonumber(ARGV[2])
local max_requests = tonumber(ARGV[3])
local member = ARGV[4]
redis.call('ZREMRANGEBYSCORE', key, 0, now - window)
local count = redis.call('ZCARD', key)
if count >= max_requests then
  return 0
end
redis.call('ZADD', key, now, member)
redis.call('EXPIRE', key, math.ceil(window) + 1)
return 1
"""


class RedisStore(Store):
    """Redis-backed store for jobs, analysis, rate limiting, and event pub/sub.

    Does NOT persist databases/games/users — pair with PostgresStore for that.
    When used standalone (without PostgresStore), databases and games fall back
    to the in-memory seed data.

    Job and analysis records are written with a TTL (``job_ttl_seconds`` /
    ``analysis_ttl_seconds``, default 24 h) so Redis does not grow without
    bound; pair with PostgresStore for durable copies with no expiry.
    """

    def __init__(
        self,
        redis_url: str,
        *,
        job_ttl_seconds: int = JOB_TTL_SECONDS,
        analysis_ttl_seconds: int = ANALYSIS_TTL_SECONDS,
    ) -> None:
        self._redis_url = redis_url
        self._job_ttl = job_ttl_seconds
        self._analysis_ttl = analysis_ttl_seconds
        self._redis = None
        # Fallback in-memory data for databases/games when no PostgresStore
        self._databases: list[dict[str, Any]] = [dict(d) for d in _SEED_DATABASES]
        self._games: list[dict[str, Any]] = [dict(g) for g in _SEED_GAMES]
        self._users: dict[str, dict[str, Any]] = {}

    async def _ensure_redis(self):
        if self._redis is None:
            import redis.asyncio as aioredis  # type: ignore
            self._redis = aioredis.from_url(self._redis_url, decode_responses=True)
        return self._redis

    async def get_job(self, job_id: str) -> dict[str, Any] | None:
        r = await self._ensure_redis()
        raw = await r.get(f"job:{job_id}")
        return json.loads(raw) if raw else None

    async def set_job(self, job_id: str, data: dict[str, Any]) -> None:
        r = await self._ensure_redis()
        await r.set(f"job:{job_id}", json.dumps(data, default=str), ex=self._job_ttl or None)

    async def delete_job(self, job_id: str) -> None:
        r = await self._ensure_redis()
        await r.delete(f"job:{job_id}")

    async def list_jobs(self) -> list[dict[str, Any]]:
        r = await self._ensure_redis()
        result: list[dict[str, Any]] = []
        async for key in r.scan_iter("job:*", count=200):
            raw = await r.get(key)
            if raw:
                try:
                    result.append(json.loads(raw))
                except (TypeError, ValueError):
                    continue
        return result

    async def get_analysis(self, job_id: str) -> dict[str, Any] | None:
        r = await self._ensure_redis()
        raw = await r.get(f"analysis:{job_id}")
        return json.loads(raw) if raw else None

    async def set_analysis(self, job_id: str, data: dict[str, Any]) -> None:
        r = await self._ensure_redis()
        await r.set(f"analysis:{job_id}", json.dumps(data, default=str), ex=self._analysis_ttl or None)

    async def delete_analysis(self, job_id: str) -> None:
        r = await self._ensure_redis()
        await r.delete(f"analysis:{job_id}")

    async def check_rate_limit(self, client_ip: str, route_key: str, max_requests: int, window_seconds: float) -> bool:
        r = await self._ensure_redis()
        key = f"rate:{route_key}:{client_ip}"
        now = time.time()
        member = str(uuid.uuid4())
        try:
            allowed = await r.eval(
                _RATE_LIMIT_LUA, 1, key, str(now), str(window_seconds),
                str(max_requests), member,
            )
            return bool(int(allowed))
        except Exception:
            # Fallback for servers/fakes without EVAL: non-atomic pipeline.
            return await self._check_rate_limit_fallback(r, key, now, max_requests, window_seconds, member)

    async def _check_rate_limit_fallback(self, r: Any, key: str, now: float, max_requests: int, window_seconds: float, member: str) -> bool:
        pipe = r.pipeline()
        pipe.zremrangebyscore(key, 0, now - window_seconds)
        pipe.zcard(key)
        pipe.zadd(key, {member: now})
        pipe.expire(key, int(window_seconds) + 1)
        results = await pipe.execute()
        count = results[1]
        if count >= max_requests:
            # We already added — remove the entry we just added
            await r.zremrangebyrank(key, -1, -1)
            return False
        return True

    async def publish_event(self, event: dict[str, Any]) -> None:
        r = await self._ensure_redis()
        await r.publish(_EVENT_BUS_CHANNEL, json.dumps(event, default=str))

    async def publish_analysis(self, job_id: str, data: dict[str, Any]) -> None:
        r = await self._ensure_redis()
        await r.publish(f"{_ANALYSIS_BUS_CHANNEL}:{job_id}", json.dumps(data, default=str))

    async def subscribe_events(self):
        r = await self._ensure_redis()
        pubsub = r.pubsub()
        await pubsub.subscribe(_EVENT_BUS_CHANNEL)
        return pubsub

    async def subscribe_analysis(self, job_id: str):
        r = await self._ensure_redis()
        pubsub = r.pubsub()
        channel = f"{_ANALYSIS_BUS_CHANNEL}:{job_id}"
        await pubsub.subscribe(channel)
        return pubsub

    async def unsubscribe_events(self, subscription: Any) -> None:
        if subscription:
            await subscription.unsubscribe(_EVENT_BUS_CHANNEL)

    async def unsubscribe_analysis(self, subscription: Any) -> None:
        if subscription:
            await subscription.close()

    # Databases / games fall back to in-memory seed data
    async def list_databases(self) -> list[dict[str, Any]]:
        return list(self._databases)

    async def create_database(self, db: dict[str, Any]) -> dict[str, Any]:
        self._databases.append(db)
        return db

    async def list_games(self, database_id: str) -> list[dict[str, Any]]:
        return list(self._games)

    async def get_game(self, game_id: str) -> dict[str, Any] | None:
        for g in self._games:
            if g["id"] == game_id:
                return dict(g)
        return None

    async def create_user(self, user: dict[str, Any]) -> dict[str, Any]:
        self._users[user["id"]] = user
        return user

    async def get_user(self, user_id: str) -> dict[str, Any] | None:
        return self._users.get(user_id)

    async def list_namebase(self, index_type: str) -> list[dict[str, Any]]:
        return [dict(e) for e in _SEED_NAMEBASE.get(index_type, [])]

    async def list_eco(self) -> list[dict[str, Any]]:
        return [dict(e) for e in _SEED_ECO]

    # --- Player center / repertoire / prep (MemoryStore seed fallback) -------

    async def search_players(self, query: str | None = None, limit: int = 20) -> list[dict[str, Any]]:
        q = (query or "").lower()
        players = _SEED_NAMEBASE.get("players", [])
        if q:
            players = [p for p in players if q in p["name"].lower()]
        return [dict(p) for p in players[:limit]]

    async def get_player_card(self, player_id: str) -> dict[str, Any] | None:
        player = next((p for p in _SEED_NAMEBASE.get("players", []) if p["id"] == player_id), None)
        if not player:
            return None
        recent = [dict(g) for g in _SEED_GAMES if player["name"] in (g["white"], g["black"])][:5]
        return {
            "id": player["id"],
            "name": player["name"],
            "elo": player["elo"],
            "title": player.get("title"),
            "country": player.get("country"),
            "peakElo": player["elo"] + 25,
            "games": player["games"],
            "winRate": 0.48,
            "drawRate": 0.32,
            "lossRate": 0.20,
            "topOpenings": [
                {"eco": "C78", "name": "Ruy Lopez", "games": 120, "score": 0.55},
                {"eco": "D37", "name": "QGD", "games": 90, "score": 0.52},
            ],
            "recentGames": recent,
        }

    async def list_repertoires(self) -> list[dict[str, Any]]:
        return [dict(r) for r in _SEED_REPERTOIRES]

    async def query_crosstable(self, query: dict[str, Any]) -> dict[str, Any] | None:
        event = query.get("event") or _SEED_CROSSTABLE["event"]
        site = query.get("site") or _SEED_CROSSTABLE["site"]
        players = query.get("players")
        rows = [dict(r) for r in _SEED_CROSSTABLE["players"]]
        if players:
            rows = [r for r in rows if r["player"] in players]
        return {
            "event": event,
            "site": site,
            "players": rows,
            "totalRounds": _SEED_CROSSTABLE["totalRounds"],
        }

    # --- Game editor (mutations no-op in Redis; use MemoryStore if needed) -----

    async def get_game_pgn(self, game_id: str) -> str | None:
        game = next((g for g in self._games if g["id"] == game_id), None)
        if not game:
            return None
        return _game_pgn(game)

    async def patch_game(self, game_id: str, patch: dict[str, Any]) -> dict[str, Any] | None:
        game = next((g for g in self._games if g["id"] == game_id), None)
        if not game:
            return None
        if "headers" in patch:
            header_map = {"White": "white", "Black": "black", "Event": "event", "Site": "site", "Date": "date", "Result": "result", "ECO": "eco"}
            for k, v in patch["headers"].items():
                if k in header_map:
                    game[header_map[k]] = v
        return dict(game)

    async def add_game_variation(self, game_id: str, move_id: str, variation: dict[str, Any]) -> dict[str, Any] | None:
        game = next((g for g in self._games if g["id"] == game_id), None)
        if not game:
            return None
        return dict(game)

    async def add_game_comment(self, game_id: str, move_id: str, comment: dict[str, Any]) -> dict[str, Any] | None:
        game = next((g for g in self._games if g["id"] == game_id), None)
        if not game:
            return None
        return dict(game)

    async def paginate_games(
        self,
        database_id: str,
        page: int = 1,
        limit: int = 25,
        sort: str = "date",
        order: str = "desc",
        query: str | None = None,
    ) -> dict[str, Any]:
        games = list(self._games)
        if query:
            q = query.lower()
            games = [
                g for g in games
                if q in g["white"].lower()
                or q in g["black"].lower()
                or q in g["event"].lower()
                or q in g.get("eco", "").lower()
            ]
        reverse = order.lower() == "desc"
        sort_key = sort if sort in {"white", "black", "event", "site", "date", "eco", "result"} else "date"
        games.sort(key=lambda g: g.get(sort_key, "") or "", reverse=reverse)
        total = len(games)
        start = (max(1, page) - 1) * limit
        end = start + limit
        return {
            "games": [dict(g) for g in games[start:end]],
            "page": page,
            "limit": limit,
            "total": total,
            "totalPages": max(1, (total + limit - 1) // limit),
        }

    async def close(self) -> None:
        if self._redis is not None:
            # redis-py >= 5.0 renamed close() to aclose(); support both.
            aclose = getattr(self._redis, "aclose", None)
            if aclose is not None:
                await aclose()
            else:
                await self._redis.close()
            self._redis = None


# ---------------------------------------------------------------------------
# PostgresStore — async SQLAlchemy (asyncpg) for all persistent entities
# ---------------------------------------------------------------------------

class PostgresStore(Store):
    """PostgreSQL-backed store using the SQLAlchemy async engine.

    Persists databases, games, users, audit logs, workspaces, and a durable
    shadow of jobs/analysis to PostgreSQL. The constructor performs no I/O;
    the engine is created lazily on first use and the schema is created with
    ``Base.metadata.create_all`` as a development convenience (production
    schemas are owned by Alembic migrations).

    Job/analysis live state is delegated to a RedisStore when ``redis_url``
    is set, otherwise to an in-process MemoryStore; every write is also
    upserted into PostgreSQL (dual-write) and every read falls back to
    PostgreSQL when the live backend has no record.
    """

    def __init__(
        self,
        database_url: str,
        redis_url: str = "",
        *,
        job_ttl_seconds: int = JOB_TTL_SECONDS,
        analysis_ttl_seconds: int = ANALYSIS_TTL_SECONDS,
    ) -> None:
        self._database_url = config.normalize_database_url_for_async(database_url)
        self._engine = None
        self._session_factory = None
        self._schema_lock: asyncio.Lock | None = None
        self._schema_ready = False
        self._redis_store: RedisStore | None = None
        self._memory_fallback: MemoryStore | None = None
        if redis_url:
            self._redis_store = RedisStore(
                redis_url,
                job_ttl_seconds=job_ttl_seconds,
                analysis_ttl_seconds=analysis_ttl_seconds,
            )
        else:
            self._memory_fallback = MemoryStore()

    # --- Engine / session lifecycle -----------------------------------------

    async def _ensure_ready(self) -> None:
        if self._schema_ready:
            return
        if self._schema_lock is None:
            self._schema_lock = asyncio.Lock()
        async with self._schema_lock:
            if self._schema_ready:
                return
            if self._engine is None:
                from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

                self._engine = create_async_engine(self._database_url, pool_pre_ping=True)
                self._session_factory = async_sessionmaker(self._engine, expire_on_commit=False)
            from .models import Base

            async with self._engine.begin() as conn:
                await conn.run_sync(Base.metadata.create_all)
            self._schema_ready = True

    @asynccontextmanager
    async def _session_scope(self) -> AsyncIterator[Any]:
        """Yield an async session, ensuring engine + schema are ready."""
        await self._ensure_ready()
        async with self._session_factory() as session:  # type: ignore[union-attr]
            yield session

    # --- Jobs (live backend + durable PostgreSQL shadow) ---------------------

    @property
    def _event_backend(self) -> Store:
        return self._redis_store if self._redis_store else self._memory_fallback  # type: ignore

    async def get_job(self, job_id: str) -> dict[str, Any] | None:
        live = await self._event_backend.get_job(job_id)
        if live is not None:
            return live
        return await self._load_job_payload(job_id)

    async def set_job(self, job_id: str, data: dict[str, Any]) -> None:
        await self._event_backend.set_job(job_id, data)
        try:
            await self._persist_job(job_id, data)
        except Exception as exc:  # durable shadow must not break the live path
            print(f"WARNING: failed to persist job {job_id} to PostgreSQL: {exc}", flush=True)

    async def delete_job(self, job_id: str) -> None:
        await self._event_backend.delete_job(job_id)
        try:
            from .models import Job as JobModel

            async with self._session_scope() as session:
                row = await session.get(JobModel, job_id)
                if row is not None:
                    await session.delete(row)
                    await session.commit()
        except Exception as exc:
            print(f"WARNING: failed to delete job {job_id} from PostgreSQL: {exc}", flush=True)

    async def list_jobs(self) -> list[dict[str, Any]]:
        merged: dict[str, dict[str, Any]] = {}
        try:
            from sqlalchemy import select

            from .models import Job as JobModel

            async with self._session_scope() as session:
                rows = (await session.execute(select(JobModel))).scalars().all()
                for row in rows:
                    if row.payload:
                        try:
                            merged[row.id] = json.loads(row.payload)
                        except (TypeError, ValueError):
                            continue
        except Exception as exc:
            print(f"WARNING: failed to list jobs from PostgreSQL: {exc}", flush=True)
        for job in await self._event_backend.list_jobs():
            key = job.get("jobId") or job.get("id") or ""
            if key:
                merged[key] = job
        return list(merged.values())

    async def _persist_job(self, job_id: str, data: dict[str, Any]) -> None:
        from .models import Job as JobModel

        async with self._session_scope() as session:
            row = await session.get(JobModel, job_id)
            if row is None:
                row = JobModel(id=job_id, job_type=str(data.get("type", "unknown"))[:32])
                session.add(row)
            row.job_type = str(data.get("type", row.job_type or "unknown"))[:32]
            row.status = str(data.get("status", row.status or "pending"))[:16]
            try:
                row.progress = int(data.get("progress", row.progress or 0))
                row.total = int(data.get("total", row.total or 100))
            except (TypeError, ValueError):
                pass
            row.database_id = data.get("databaseId", row.database_id)
            row.payload = json.dumps(data, default=str)
            if "result" in data:
                row.result = data["result"] if isinstance(data["result"], str) else json.dumps(data["result"], default=str)
            if "error" in data:
                row.error = str(data["error"]) if data["error"] is not None else None
            await session.commit()

    async def _load_job_payload(self, job_id: str) -> dict[str, Any] | None:
        try:
            from .models import Job as JobModel

            async with self._session_scope() as session:
                row = await session.get(JobModel, job_id)
                if row is None or not row.payload:
                    return None
                return json.loads(row.payload)
        except Exception as exc:
            print(f"WARNING: failed to load job {job_id} from PostgreSQL: {exc}", flush=True)
            return None

    # --- Analysis (live backend + durable PostgreSQL shadow) -----------------

    async def get_analysis(self, job_id: str) -> dict[str, Any] | None:
        live = await self._event_backend.get_analysis(job_id)
        if live is not None:
            return live
        try:
            from .models import Analysis as AnalysisModel

            async with self._session_scope() as session:
                row = await session.get(AnalysisModel, job_id)
                if row is None or not row.payload:
                    return None
                return json.loads(row.payload)
        except Exception as exc:
            print(f"WARNING: failed to load analysis {job_id} from PostgreSQL: {exc}", flush=True)
            return None

    async def set_analysis(self, job_id: str, data: dict[str, Any]) -> None:
        await self._event_backend.set_analysis(job_id, data)
        try:
            from .models import Analysis as AnalysisModel

            async with self._session_scope() as session:
                row = await session.get(AnalysisModel, job_id)
                if row is None:
                    row = AnalysisModel(job_id=job_id)
                    session.add(row)
                row.payload = json.dumps(data, default=str)
                await session.commit()
        except Exception as exc:
            print(f"WARNING: failed to persist analysis {job_id} to PostgreSQL: {exc}", flush=True)

    async def delete_analysis(self, job_id: str) -> None:
        await self._event_backend.delete_analysis(job_id)
        try:
            from .models import Analysis as AnalysisModel

            async with self._session_scope() as session:
                row = await session.get(AnalysisModel, job_id)
                if row is not None:
                    await session.delete(row)
                    await session.commit()
        except Exception as exc:
            print(f"WARNING: failed to delete analysis {job_id} from PostgreSQL: {exc}", flush=True)

    # --- Rate limiting / event bus (delegate to live backend) ----------------

    async def check_rate_limit(self, client_ip: str, route_key: str, max_requests: int, window_seconds: float) -> bool:
        return await self._event_backend.check_rate_limit(client_ip, route_key, max_requests, window_seconds)

    async def publish_event(self, event: dict[str, Any]) -> None:
        await self._event_backend.publish_event(event)

    async def publish_analysis(self, job_id: str, data: dict[str, Any]) -> None:
        await self._event_backend.publish_analysis(job_id, data)

    async def subscribe_events(self):
        return await self._event_backend.subscribe_events()

    async def subscribe_analysis(self, job_id: str):
        return await self._event_backend.subscribe_analysis(job_id)

    async def unsubscribe_events(self, subscription: Any) -> None:
        await self._event_backend.unsubscribe_events(subscription)

    async def unsubscribe_analysis(self, subscription: Any) -> None:
        await self._event_backend.unsubscribe_analysis(subscription)

    # --- Databases / Games / Users / Audit (PostgreSQL, authoritative) -------

    async def list_databases(self) -> list[dict[str, Any]]:
        from sqlalchemy import select

        from .models import Database as DBModel

        async with self._session_scope() as session:
            rows = (await session.execute(select(DBModel))).scalars().all()
            return [
                {"id": r.id, "name": r.name, "format": r.format, "games": r.games, "readOnly": r.read_only}
                for r in rows
            ]

    async def create_database(self, db: dict[str, Any]) -> dict[str, Any]:
        from .models import Database as DBModel

        async with self._session_scope() as session:
            record = DBModel(
                id=db["id"],
                name=db["name"],
                format=db["format"],
                games=db["games"],
                read_only=db["readOnly"],
            )
            session.add(record)
            await session.commit()
            return db

    async def list_games(self, database_id: str) -> list[dict[str, Any]]:
        from sqlalchemy import select

        from .models import Game as GameModel

        async with self._session_scope() as session:
            rows = (await session.execute(select(GameModel).where(GameModel.database_id == database_id))).scalars().all()
            return [self._game_to_dict(r) for r in rows]

    async def get_game(self, game_id: str) -> dict[str, Any] | None:
        from .models import Game as GameModel

        async with self._session_scope() as session:
            row = await session.get(GameModel, game_id)
            return self._game_to_dict(row) if row else None

    @staticmethod
    def _game_to_dict(r: Any) -> dict[str, Any]:
        return {
            "id": r.id,
            "white": r.white,
            "whiteElo": r.white_elo,
            "black": r.black,
            "blackElo": r.black_elo,
            "event": r.event,
            "site": r.site,
            "date": r.date,
            "result": r.result,
            "eco": r.eco,
        }

    async def create_user(self, user: dict[str, Any]) -> dict[str, Any]:
        from .models import User as UserModel

        async with self._session_scope() as session:
            record = UserModel(
                id=user["id"],
                name=user.get("name", ""),
                email=user.get("email", ""),
                profile=json.dumps(user.get("profile", {})),
            )
            session.add(record)
            await session.commit()
            return user

    async def get_user(self, user_id: str) -> dict[str, Any] | None:
        from .models import User as UserModel

        async with self._session_scope() as session:
            row = await session.get(UserModel, user_id)
            if not row:
                return None
            return {
                "id": row.id,
                "name": row.name,
                "email": row.email,
                "profile": json.loads(row.profile) if row.profile else {},
            }

    async def add_audit_log(self, action: str, **fields: Any) -> None:
        from .models import AuditLog

        async with self._session_scope() as session:
            record = AuditLog(
                id=str(uuid.uuid4()),
                action=action,
                details=json.dumps(fields, default=str),
                timestamp=time.time(),
                user_id=fields.get("user_id") or fields.get("user"),
                ip=fields.get("ip"),
                route=fields.get("route"),
            )
            session.add(record)
            await session.commit()

    async def list_namebase(self, index_type: str) -> list[dict[str, Any]]:
        # Phase 4 will delegate to ::scidb::db::match; for now return seed data.
        return [dict(e) for e in _SEED_NAMEBASE.get(index_type, [])]

    async def list_eco(self) -> list[dict[str, Any]]:
        # Phase 4 will delegate to ::scidb::db::ecoStats; for now return seed data.
        return [dict(e) for e in _SEED_ECO]

    # --- Player center / repertoire / prep (seed fallback) ------------------

    async def search_players(self, query: str | None = None, limit: int = 20) -> list[dict[str, Any]]:
        q = (query or "").lower()
        players = _SEED_NAMEBASE.get("players", [])
        if q:
            players = [p for p in players if q in p["name"].lower()]
        return [dict(p) for p in players[:limit]]

    async def get_player_card(self, player_id: str) -> dict[str, Any] | None:
        player = next((p for p in _SEED_NAMEBASE.get("players", []) if p["id"] == player_id), None)
        if not player:
            return None
        recent = [dict(g) for g in _SEED_GAMES if player["name"] in (g["white"], g["black"])][:5]
        return {
            "id": player["id"],
            "name": player["name"],
            "elo": player["elo"],
            "title": player.get("title"),
            "country": player.get("country"),
            "peakElo": player["elo"] + 25,
            "games": player["games"],
            "winRate": 0.48,
            "drawRate": 0.32,
            "lossRate": 0.20,
            "topOpenings": [
                {"eco": "C78", "name": "Ruy Lopez", "games": 120, "score": 0.55},
                {"eco": "D37", "name": "QGD", "games": 90, "score": 0.52},
            ],
            "recentGames": recent,
        }

    async def list_repertoires(self) -> list[dict[str, Any]]:
        return [dict(r) for r in _SEED_REPERTOIRES]

    async def query_crosstable(self, query: dict[str, Any]) -> dict[str, Any] | None:
        event = query.get("event") or _SEED_CROSSTABLE["event"]
        site = query.get("site") or _SEED_CROSSTABLE["site"]
        players = query.get("players")
        rows = [dict(r) for r in _SEED_CROSSTABLE["players"]]
        if players:
            rows = [r for r in rows if r["player"] in players]
        return {
            "event": event,
            "site": site,
            "players": rows,
            "totalRounds": _SEED_CROSSTABLE["totalRounds"],
        }

    # --- Game editor (mutations require writable backend; seed fallback) -----

    async def get_game_pgn(self, game_id: str) -> str | None:
        row = await self.get_game(game_id)
        if not row:
            return None
        return _game_pgn(row)

    async def patch_game(self, game_id: str, patch: dict[str, Any]) -> dict[str, Any] | None:
        from .models import Game as GameModel

        async with self._session_scope() as session:
            row = await session.get(GameModel, game_id)
            if row is None:
                return None
            if "headers" in patch:
                header_map = {"White": "white", "Black": "black", "Event": "event", "Site": "site", "Date": "date", "Result": "result", "ECO": "eco"}
                for k, v in patch["headers"].items():
                    if k in header_map:
                        setattr(row, header_map[k], v)
            await session.commit()
            return self._game_to_dict(row)

    async def add_game_variation(self, game_id: str, move_id: str, variation: dict[str, Any]) -> dict[str, Any] | None:
        row = await self.get_game(game_id)
        return row

    async def add_game_comment(self, game_id: str, move_id: str, comment: dict[str, Any]) -> dict[str, Any] | None:
        row = await self.get_game(game_id)
        return row

    async def paginate_games(
        self,
        database_id: str,
        page: int = 1,
        limit: int = 25,
        sort: str = "date",
        order: str = "desc",
        query: str | None = None,
    ) -> dict[str, Any]:
        from sqlalchemy import select
        from .models import Game as GameModel

        async with self._session_scope() as session:
            stmt = select(GameModel).where(GameModel.database_id == database_id)
            if query:
                q = f"%{query}%"
                from sqlalchemy import or_
                stmt = stmt.where(
                    or_(
                        GameModel.white.ilike(q),
                        GameModel.black.ilike(q),
                        GameModel.event.ilike(q),
                        GameModel.eco.ilike(q),
                    )
                )
            reverse = order.lower() == "desc"
            sort_key = sort if sort in {"white", "black", "event", "site", "date", "eco", "result"} else "date"
            order_attr = getattr(GameModel, sort_key if sort_key != "white" else "white", GameModel.date)
            if reverse:
                stmt = stmt.order_by(order_attr.desc())
            else:
                stmt = stmt.order_by(order_attr.asc())
            offset = (max(1, page) - 1) * limit
            total_result = await session.execute(select(func.count()).select_from(stmt.subquery()))
            total = total_result.scalar() or 0
            stmt = stmt.offset(offset).limit(limit)
            rows = (await session.execute(stmt)).scalars().all()
            return {
                "games": [self._game_to_dict(r) for r in rows],
                "page": page,
                "limit": limit,
                "total": total,
                "totalPages": max(1, (total + limit - 1) // limit),
            }

    async def close(self) -> None:
        if self._redis_store:
            await self._redis_store.close()
        if self._engine is not None:
            await self._engine.dispose()
            self._engine = None
            self._session_factory = None
            self._schema_ready = False


# ---------------------------------------------------------------------------
# Factory
# ---------------------------------------------------------------------------

_store_instance: Store | None = None


def get_store() -> Store:
    """Return the appropriate store backend based on environment variables.

    Reads DATABASE_URL and REDIS_URL dynamically so tests can change them.
    """
    global _store_instance
    if _store_instance is not None:
        return _store_instance

    db_url = os.environ.get("DATABASE_URL", "")
    redis_url = os.environ.get("REDIS_URL", "")

    if db_url:
        _store_instance = PostgresStore(db_url, redis_url)
    elif redis_url:
        _store_instance = RedisStore(redis_url)
    else:
        _store_instance = MemoryStore()

    return _store_instance


def reset_store() -> None:
    """Reset the store singleton (used in tests).

    Note: this does not close the previous instance; call ``await
    store.close()`` first when the instance holds real connections.
    """
    global _store_instance
    _store_instance = None
