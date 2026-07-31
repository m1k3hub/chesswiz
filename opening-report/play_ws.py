"""play_ws — WebSocket handler for /api/ws/play (Phase 4: live moves + clocks).

One multiplexed channel per session. Auth: the access token is passed as a
`?token=` query param (browsers can't set WS headers) and validated via the
adapter's _get_auth_payload_sync; absent token → ephemeral guest identity
(re-presentable via `?guest=` so reconnect reclaims the match).

Server is the source of truth: incoming moves are validated by play_service
(via play_rules), clocks are server-authoritative, and a background asyncio
task flags timeouts. Events (seek.created, match.paired, match.move,
match.finish) are fanned out to the relevant sockets. On (re)connect the server
sends a resync: open seeks + any active match for the user with its move list.
"""

from __future__ import annotations

import asyncio
import uuid
from typing import Any

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from play_service import play_service

router = APIRouter()

# matchId -> set of connected sockets; userId -> set of sockets (for seeks).
_match_sockets: dict[str, set[WebSocket]] = {}
_user_sockets: dict[str, set[WebSocket]] = {}

_clock_task: asyncio.Task | None = None


def _adapter():
    import runtime_adapter as ra

    return ra._get_auth_payload_sync


def _resolve_user(token: str | None, guest: str | None) -> dict[str, Any]:
    get_payload = _adapter()
    payload = get_payload(f"Bearer {token}" if token else None) if token else None
    if payload:
        sub = payload.get("sub") or "user-" + uuid.uuid4().hex[:8]
        name = payload.get("name") or sub
        return {"id": sub, "name": name, "rating": 1500}
    gid = guest if (guest and guest.startswith("guest-") and len(guest) <= 64) else "guest-" + uuid.uuid4().hex[:8]
    return {"id": gid, "name": "Guest-" + gid[-4:].upper(), "rating": 1500}


async def _send(ws: WebSocket, data: dict[str, Any]) -> None:
    try:
        await ws.send_json(data)
    except Exception:
        pass


def _fanout(sockets: set[WebSocket], event: dict[str, Any]) -> None:
    for ws in list(sockets):
        asyncio.create_task(_send(ws, event))


async def _on_event(event: dict[str, Any]) -> None:
    etype = event.get("type")
    if etype == "seek.created" or etype == "seek.cancelled":
        # broadcast to all connected sockets (lobby)
        for sockets in list(_user_sockets.values()):
            _fanout(sockets, event)
    elif etype == "match.paired":
        match = event["match"]
        for uid in (match["white"]["id"], match["black"]["id"]):
            _fanout(_user_sockets.get(uid, set()), event)
    elif etype == "match.move":
        mid = event["matchId"]
        _fanout(_match_sockets.get(mid, set()), event)
    elif etype == "match.finish":
        mid = event["matchId"]
        _fanout(_match_sockets.get(mid, set()), event)
    elif etype in ("match.offer", "match.offer.response", "match.chat"):
        mid = event["matchId"]
        _fanout(_match_sockets.get(mid, set()), event)


def _ensure_clock_loop() -> None:
    global _clock_task
    if _clock_task is None or _clock_task.done():

        async def loop():
            while True:
                try:
                    play_service.check_timeouts()
                except Exception:
                    pass
                await asyncio.sleep(0.2)

        _clock_task = asyncio.create_task(loop())


@router.websocket("/api/ws/play")
async def ws_play(websocket: WebSocket, token: str | None = None, guest: str | None = None):
    await websocket.accept()
    user = _resolve_user(token, guest)
    uid = user["id"]
    _ensure_clock_loop()

    # Register the socket for seek broadcasts.
    _user_sockets.setdefault(uid, set()).add(websocket)
    active: dict[str, Any] = {"id": None}
    # If the user already has an active match, register for it (reconnect/resync).
    for mid, rec in play_service._records.items():  # noqa: SLF001
        m = rec["match"]
        if m["status"] == "playing" and uid in (m["white"]["id"], m["black"]["id"]):
            active["id"] = mid
            _match_sockets.setdefault(mid, set()).add(websocket)
            break

    # Subscribe to play_service events and forward relevant ones to this socket.
    def forward(event: dict[str, Any]) -> None:
        etype = event.get("type")
        if etype in ("seek.created", "seek.cancelled"):
            asyncio.create_task(_send(websocket, event))
        elif etype == "match.paired":
            m = event["match"]
            if uid in (m["white"]["id"], m["black"]["id"]):
                active["id"] = m["id"]
                _match_sockets.setdefault(m["id"], set()).add(websocket)
                asyncio.create_task(_send(websocket, event))
        elif etype in ("match.move", "match.finish", "match.offer", "match.offer.response", "match.chat") and event.get("matchId") == active["id"]:
            asyncio.create_task(_send(websocket, event))

    unsub = play_service.subscribe(forward)

    # Resync: send current seeks and the active match (if any).
    await _send(websocket, {"type": "seek.list", "seeks": play_service.list_seeks(uid)})
    if active["id"]:
        match = play_service.get_match(active["id"])
        moves = play_service.get_match_moves(active["id"])
        if match:
            await _send(websocket, {"type": "match.resync", "match": match, "moves": moves})

    try:
        while True:
            msg = await websocket.receive_json()
            mtype = msg.get("type")
            if mtype == "ping":
                await _send(websocket, {"type": "pong"})
            elif mtype == "move":
                try:
                    res = play_service.submit_move(user, msg["matchId"], msg["uci"])
                except Exception as exc:
                    await _send(websocket, {"type": "match.error", "code": _err_code(exc), "message": str(exc)})
                    continue
                # The event subscriber forwards match.move to both sockets.
            elif mtype == "resign":
                try:
                    play_service.resign(user, msg["matchId"])
                except Exception as exc:
                    await _send(websocket, {"type": "match.error", "code": _err_code(exc), "message": str(exc)})
            elif mtype == "offer":
                try:
                    play_service.offer(user, msg["matchId"], msg["kind"])
                except Exception as exc:
                    await _send(websocket, {"type": "match.error", "code": _err_code(exc), "message": str(exc)})
            elif mtype == "offer.respond":
                try:
                    play_service.respond_offer(user, msg["matchId"], bool(msg.get("accept")))
                except Exception as exc:
                    await _send(websocket, {"type": "match.error", "code": _err_code(exc), "message": str(exc)})
            elif mtype == "abort":
                try:
                    play_service.abort(user, msg["matchId"])
                except Exception as exc:
                    await _send(websocket, {"type": "match.error", "code": _err_code(exc), "message": str(exc)})
            elif mtype == "chat":
                try:
                    play_service.chat(user, msg["matchId"], msg.get("text", ""))
                except Exception as exc:
                    await _send(websocket, {"type": "match.error", "code": _err_code(exc), "message": str(exc)})
            elif mtype == "blur":
                # Anti-cheat v1 signal (Phase 7): client reports focus-out
                # during the opponent's turn. Best-effort, no error reply.
                mid = msg.get("matchId") or active["id"]
                if mid:
                    try:
                        play_service.record_blur(user, mid)
                    except Exception:
                        pass
    except WebSocketDisconnect:
        pass
    finally:
        unsub()
        _user_sockets.get(uid, set()).discard(websocket)
        if not _user_sockets.get(uid):
            _user_sockets.pop(uid, None)
        if active["id"]:
            _match_sockets.get(active["id"], set()).discard(websocket)
            if not _match_sockets.get(active["id"]):
                _match_sockets.pop(active["id"], None)


def _err_code(exc: Exception) -> str:
    msg = str(exc)
    if "not your turn" in msg:
        return "not_your_turn"
    if "illegal" in msg:
        return "illegal_move"
    if "not a participant" in msg or "not your seek" in msg:
        return "not_participant"
    if "finished" in msg:
        return "match_finished"
    return "error"


