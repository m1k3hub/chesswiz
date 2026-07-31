"""play_routes — FastAPI router for /api/play/* (Phase 3: seeks + pairing).

Mounted by runtime_adapter via `app.include_router(play_router, prefix="/api")`.
The auth/rate-limit helpers live in runtime_adapter; they are imported lazily
inside the route handlers so this module can be imported before the adapter
finishes initializing (no import-time circularity).

Identity: authenticated users come from the Bearer token (OIDC subject); guests
get an ephemeral id returned via the `X-Play-Guest-Id` response header and
re-presented by the client on subsequent requests. Rated seeks from guests are
rejected with 403 `rated_requires_auth`.
"""

from __future__ import annotations

import uuid
from typing import Any

from fastapi import APIRouter, Header, HTTPException, Request, Response
from pydantic import BaseModel

from play_service import play_service

router = APIRouter(prefix="/play", tags=["play"])

# Rate-limit bucket for all /api/play routes.
_PLAY_RATE_KEY = "/api/play"


class SeekPayload(BaseModel):
    timeControl: dict[str, Any]
    variant: str = "standard"
    rated: bool = False
    color: str = "random"
    ratingRange: list[int] | None = None
    startFen: str | None = None


def _adapter():
    """Lazy import of runtime_adapter helpers (avoids circular import)."""
    import runtime_adapter as ra

    return ra._get_auth_payload_sync, ra._check_rate_limit, ra._client_ip


def _play_user(request: Request, authorization: str | None) -> tuple[dict[str, Any], bool]:
    """Return (user, is_guest). Authenticated when a valid token is present."""
    get_payload, _, _ = _adapter()
    payload = get_payload(authorization)
    if payload:
        sub = payload.get("sub") or payload.get("id") or "user-" + uuid.uuid4().hex[:8]
        name = payload.get("name") or payload.get("preferred_username") or sub
        return {"id": sub, "name": name, "rating": 1500, "title": payload.get("title")}, False

    guest_id = request.headers.get("x-play-guest-id")
    if not guest_id or not guest_id.startswith("guest-") or len(guest_id) > 64:
        guest_id = "guest-" + uuid.uuid4().hex[:8]
    name = "Guest-" + guest_id[-4:].upper()
    return {"id": guest_id, "name": name, "rating": 1500}, True


def _set_guest_header(response: Response, user: dict[str, Any], is_guest: bool) -> None:
    if is_guest:
        response.headers["X-Play-Guest-Id"] = user["id"]


async def _rate_limit(request: Request) -> None:
    _, check, client_ip = _adapter()
    ip = client_ip(request)
    if not await check(ip, _PLAY_RATE_KEY):
        raise HTTPException(status_code=429, detail="rate limit exceeded")


@router.post("/seek")
async def create_seek(
    body: SeekPayload,
    request: Request,
    response: Response,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    await _rate_limit(request)
    user, is_guest = _play_user(request, authorization)
    if body.rated and is_guest:
        raise HTTPException(
            status_code=403,
            detail={"code": "rated_requires_auth", "message": "Rated games require sign-in"},
        )
    _set_guest_header(response, user, is_guest)
    return play_service.create_seek(user, body.model_dump())


@router.get("/seeks")
async def list_seeks(
    request: Request,
    response: Response,
    authorization: str | None = Header(default=None),
) -> list[dict[str, Any]]:
    user, is_guest = _play_user(request, authorization)
    _set_guest_header(response, user, is_guest)
    return play_service.list_seeks(user["id"])


@router.get("/seeks/mine")
async def list_my_seeks(
    request: Request,
    response: Response,
    authorization: str | None = Header(default=None),
) -> list[dict[str, Any]]:
    user, is_guest = _play_user(request, authorization)
    _set_guest_header(response, user, is_guest)
    return play_service.list_my_seeks(user["id"])


@router.delete("/seek/{seek_id}")
async def cancel_seek(
    seek_id: str,
    request: Request,
    response: Response,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    await _rate_limit(request)
    user, is_guest = _play_user(request, authorization)
    _set_guest_header(response, user, is_guest)
    try:
        play_service.cancel_seek(user["id"], seek_id)
    except KeyError:
        raise HTTPException(status_code=404, detail="seek not found")
    except PermissionError:
        raise HTTPException(status_code=403, detail="not your seek")
    return {"ok": True}


@router.post("/seek/{seek_id}/accept")
async def accept_seek(
    seek_id: str,
    request: Request,
    response: Response,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    await _rate_limit(request)
    user, is_guest = _play_user(request, authorization)
    _set_guest_header(response, user, is_guest)
    try:
        return play_service.accept_seek(user, seek_id)
    except KeyError:
        raise HTTPException(status_code=404, detail="seek not found")
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.get("/match/{match_id}")
async def get_match(match_id: str) -> dict[str, Any] | None:
    m = play_service.get_match(match_id)
    if m is None:
        raise HTTPException(status_code=404, detail="match not found")
    return m


@router.get("/me/rating")
async def my_rating(
    request: Request,
    response: Response,
    authorization: str | None = Header(default=None),
) -> list[dict[str, Any]]:
    user, _ = _play_user(request, authorization)
    return play_service.get_my_rating(user["id"])

class MovePayload(BaseModel):
    uci: str


def _participant_or_403(user: dict[str, Any], match: dict[str, Any]) -> None:
    if user["id"] not in (match["white"]["id"], match["black"]["id"]):
        raise HTTPException(status_code=403, detail="not a participant")


@router.post("/match/{match_id}/move")
async def submit_move(
    match_id: str,
    body: MovePayload,
    request: Request,
    response: Response,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    await _rate_limit(request)
    user, is_guest = _play_user(request, authorization)
    _set_guest_header(response, user, is_guest)
    try:
        return play_service.submit_move(user, match_id, body.uci)
    except KeyError:
        raise HTTPException(status_code=404, detail="match not found")
    except PermissionError:
        raise HTTPException(status_code=403, detail="not a participant")
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.post("/match/{match_id}/resign")
async def resign_match(
    match_id: str,
    request: Request,
    response: Response,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    await _rate_limit(request)
    user, is_guest = _play_user(request, authorization)
    _set_guest_header(response, user, is_guest)
    try:
        return play_service.resign(user, match_id)
    except KeyError:
        raise HTTPException(status_code=404, detail="match not found")
    except PermissionError:
        raise HTTPException(status_code=403, detail="not a participant")
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.get("/match/{match_id}/moves")
async def match_moves(match_id: str) -> list[dict[str, Any]]:
    return play_service.get_match_moves(match_id)


@router.get("/me/games")
async def my_games(
    request: Request,
    response: Response,
    authorization: str | None = Header(default=None),
) -> list[dict[str, Any]]:
    user, is_guest = _play_user(request, authorization)
    _set_guest_header(response, user, is_guest)
    return play_service.list_my_games(user["id"])


class OfferPayload(BaseModel):
    kind: str  # 'draw' | 'rematch' | 'takeback'


class OfferResponsePayload(BaseModel):
    accept: bool


class ChatPayload(BaseModel):
    text: str


@router.post("/match/{match_id}/offer")
async def offer(
    match_id: str,
    body: OfferPayload,
    request: Request,
    response: Response,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    await _rate_limit(request)
    user, is_guest = _play_user(request, authorization)
    _set_guest_header(response, user, is_guest)
    try:
        play_service.offer(user, match_id, body.kind)
    except KeyError:
        raise HTTPException(status_code=404, detail="match not found")
    except PermissionError:
        raise HTTPException(status_code=403, detail="not a participant")
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return {"ok": True}


@router.post("/match/{match_id}/offer/respond")
async def respond_offer(
    match_id: str,
    body: OfferResponsePayload,
    request: Request,
    response: Response,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    await _rate_limit(request)
    user, is_guest = _play_user(request, authorization)
    _set_guest_header(response, user, is_guest)
    try:
        play_service.respond_offer(user, match_id, body.accept)
    except KeyError:
        raise HTTPException(status_code=404, detail="match not found")
    except PermissionError:
        raise HTTPException(status_code=403, detail="not a participant")
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    return {"ok": True}


@router.post("/match/{match_id}/abort")
async def abort_match(
    match_id: str,
    request: Request,
    response: Response,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    await _rate_limit(request)
    user, is_guest = _play_user(request, authorization)
    _set_guest_header(response, user, is_guest)
    try:
        return play_service.abort(user, match_id)
    except KeyError:
        raise HTTPException(status_code=404, detail="match not found")
    except PermissionError:
        raise HTTPException(status_code=403, detail="not a participant")
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.post("/match/{match_id}/chat")
async def match_chat(
    match_id: str,
    body: ChatPayload,
    request: Request,
    response: Response,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    await _rate_limit(request)
    user, is_guest = _play_user(request, authorization)
    _set_guest_header(response, user, is_guest)
    try:
        return play_service.chat(user, match_id, body.text)
    except KeyError:
        raise HTTPException(status_code=404, detail="match not found")
    except PermissionError:
        raise HTTPException(status_code=403, detail="not a participant")
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


class ArchivePayload(BaseModel):
    databaseId: str


@router.post("/match/{match_id}/archive")
async def archive_match(
    match_id: str,
    body: ArchivePayload,
    request: Request,
    response: Response,
    authorization: str | None = Header(default=None),
) -> dict[str, Any]:
    await _rate_limit(request)
    user, is_guest = _play_user(request, authorization)
    _set_guest_header(response, user, is_guest)
    match = play_service.get_match(match_id)
    if match is None:
        raise HTTPException(status_code=404, detail="match not found")
    if user["id"] not in (match["white"]["id"], match["black"]["id"]):
        raise HTTPException(status_code=403, detail="not a participant")
    if match["status"] != "finished":
        raise HTTPException(status_code=400, detail="match not finished")
    pgn = play_service.match_to_pgn(match_id)
    if not pgn:
        raise HTTPException(status_code=500, detail="could not generate PGN")

    # Reuse the adapter's import/job pipeline (lazy import avoids circularity).
    import runtime_adapter as ra  # noqa: WPS433
    import security as _security
    import asyncio as _asyncio

    database_id = body.databaseId
    if not _security.is_safe_key_component(database_id):
        raise HTTPException(status_code=400, detail="invalid database id")
    filename = f"{match_id}.pgn"
    storage_key = f"uploads/{database_id}/{filename}"
    await ra._store_file(storage_key, pgn.encode("utf-8"))
    job_id = f"import-{__import__('uuid').uuid4().hex[:8]}"
    job_data = {
        "jobId": job_id,
        "type": "import",
        "status": "running",
        "progress": 0,
        "total": 10,
        "databaseId": database_id,
        "filename": filename,
        "storageKey": storage_key,
        "fileSize": len(pgn.encode("utf-8")),
        "source": "play-archive",
    }
    await ra.store.set_job(job_id, job_data)
    ra._JOBS[job_id] = job_data  # backward-compat sync view
    _asyncio.create_task(ra._simulate_job_progress(job_id, "import", 10))
    return {"jobId": job_id}
