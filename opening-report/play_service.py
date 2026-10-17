"""play_service — in-process online-play state (Phase 3 seeks + Phase 4 moves).

Server-side counterpart of the Phase 2 mock backend. Holds seeks and matches
in memory (single-process v1; horizontal scale is Phase 7+ via Redis). Move
validation uses play_rules (pure-Python standard-chess engine), which is the
documented fallback for the scidb C++ `position/legal` bridge command when the
bridge is unavailable (decision 1).

Clocks are server-authoritative: the clock snapshot is updated on each move
and the clock loop (driven by play_ws) flags timeouts. Events (match.move,
match.finish) are emitted to sync subscribers that play_ws fans out to sockets.

Identity model (docs/ONLINE_PLAY_PLAN.md §5.3): authenticated user (OIDC subject)
or ephemeral guest. Rated games require authentication (enforced in play_routes).
"""

from __future__ import annotations

import threading
import time
import uuid
from typing import Any, Callable

import play_rules
import rating
import metrics

START_FEN = play_rules.START_FEN

# Anti-cheat v1 heuristics (docs/ONLINE_PLAY_PLAN.md Phase 7). Thresholds are not
# calibrated against a play-test dataset yet (plan §"Open questions") — these
# are conservative placeholders that flag for review, never auto-ban.
_INSTANT_MOVE_MS = 200
_INSTANT_MOVE_FLAG_COUNT = 3
_BLUR_FLAG_COUNT = 3


def _now_ms() -> int:
    return int(time.time() * 1000)


def _gen_id(prefix: str) -> str:
    return f"{prefix}-{uuid.uuid4().hex[:8]}"


class PlayService:
    """Thread-safe in-memory store for seeks, matches, and move state."""

    def __init__(self) -> None:
        self._seeks: dict[str, dict[str, Any]] = {}
        self._records: dict[str, dict[str, Any]] = {}  # matchId -> record
        self._my_games: dict[str, list[dict[str, Any]]] = {}  # userId -> finished
        self._lock = threading.Lock()
        self._subscribers: list[Callable[[dict[str, Any]], None]] = []
        self._review_queue: list[dict[str, Any]] = []  # anti-cheat flags, no auto-ban

    # ---- event subscription (for play_ws) ----

    def subscribe(self, cb: Callable[[dict[str, Any]], None]) -> Callable[[], None]:
        with self._lock:
            self._subscribers.append(cb)
        def unsub() -> None:
            with self._lock:
                if cb in self._subscribers:
                    self._subscribers.remove(cb)
        return unsub

    def _emit(self, event: dict[str, Any]) -> None:
        with self._lock:
            subs = list(self._subscribers)
        for cb in subs:
            try:
                cb(event)
            except Exception:
                pass

    # ---- seeks ----

    def list_seeks(self, exclude_user_id: str) -> list[dict[str, Any]]:
        with self._lock:
            return [
                dict(s)
                for s in self._seeks.values()
                if s["owner"]["id"] != exclude_user_id and not s.get("accepted")
            ]

    def list_my_seeks(self, user_id: str) -> list[dict[str, Any]]:
        with self._lock:
            return [
                dict(s)
                for s in self._seeks.values()
                if s["owner"]["id"] == user_id and not s.get("accepted")
            ]

    def create_seek(self, user: dict[str, Any], payload: dict[str, Any]) -> dict[str, Any]:
        tc = payload.get("timeControl") or {}
        seek = {
            "id": _gen_id("seek"),
            "owner": user,
            "timeControl": {
                "kind": tc.get("kind", "blitz"),
                "baseSeconds": int(tc.get("baseSeconds", 180)),
                "incrementSeconds": int(tc.get("incrementSeconds", 0)),
            },
            "variant": payload.get("variant", "standard"),
            "rated": bool(payload.get("rated", False)),
            "color": payload.get("color", "random"),
            "ratingRange": payload.get("ratingRange"),
            "startFen": payload.get("startFen") or START_FEN,
            "createdAt": _now_ms(),
            "accepted": False,
        }
        with self._lock:
            self._seeks[seek["id"]] = seek
        public = dict(seek)
        public.pop("accepted", None)
        metrics.play_seek_opened()
        self._emit({"type": "seek.created", "seek": public})
        return public

    def cancel_seek(self, user_id: str, seek_id: str) -> None:
        with self._lock:
            s = self._seeks.get(seek_id)
            if s is None:
                raise KeyError("seek not found")
            if s["owner"]["id"] != user_id:
                raise PermissionError("not your seek")
            del self._seeks[seek_id]
        metrics.play_seek_closed()
        self._emit({"type": "seek.cancelled", "seekId": seek_id})

    # ---- pairing ----

    def accept_seek(self, user: dict[str, Any], seek_id: str) -> dict[str, Any]:
        import random

        with self._lock:
            s = self._seeks.get(seek_id)
            if s is None:
                raise KeyError("seek not found")
            if s["owner"]["id"] == user["id"]:
                raise ValueError("cannot accept own seek")
            if s.get("accepted"):
                raise ValueError("seek already accepted")
            owner = s["owner"]
            if s["color"] == "b":
                white, black = user, owner
            elif s["color"] == "w":
                white, black = owner, user
            else:
                if random.random() < 0.5:
                    white, black = user, owner
                else:
                    white, black = owner, user
            base_ms = s["timeControl"]["baseSeconds"] * 1000
            match = {
                "id": _gen_id("match"),
                "variant": s["variant"],
                "timeControl": s["timeControl"],
                "rated": s["rated"],
                "white": white,
                "black": black,
                "startFen": s["startFen"],
                "ply": 0,
                "status": "playing",
                "result": None,
                "clocks": {"whiteMs": base_ms, "blackMs": base_ms},
                "clockUpdatedAt": _now_ms(),
                "drawOfferSide": None,
                "rematchOfferSide": None,
                "arbiterId": white["id"],
            }
            self._records[match["id"]] = {
                "match": match,
                "fen": s["startFen"],
                "moves": [],
                "pos_keys": [],
                "anticheat": {"w": {"times": [], "instant": 0}, "b": {"times": [], "instant": 0}, "blur": {"w": 0, "b": 0}},
            }
            s["accepted"] = True
            del self._seeks[seek_id]
            match_copy = dict(match)
        metrics.play_seek_closed()
        metrics.play_match_started()
        self._emit({"type": "seek.cancelled", "seekId": seek_id})
        self._emit({"type": "match.paired", "match": match_copy})
        return match_copy

    # ---- matches ----

    def get_match(self, match_id: str) -> dict[str, Any] | None:
        with self._lock:
            rec = self._records.get(match_id)
            return dict(rec["match"]) if rec else None

    def get_match_moves(self, match_id: str) -> list[dict[str, Any]]:
        with self._lock:
            rec = self._records.get(match_id)
            return list(rec["moves"]) if rec else []

    def _user_color(self, match: dict[str, Any], user_id: str) -> str | None:
        if match["white"]["id"] == user_id:
            return "w"
        if match["black"]["id"] == user_id:
            return "b"
        return None

    def submit_move(self, user: dict[str, Any], match_id: str, uci: str) -> dict[str, Any]:
        with self._lock:
            rec = self._records.get(match_id)
            if rec is None:
                raise KeyError("match not found")
            match = rec["match"]
            if match["status"] != "playing":
                raise ValueError("match finished")
            color = self._user_color(match, user["id"])
            if color is None:
                raise PermissionError("not a participant")
            side = "w" if (rec["fen"].split()[1] == "w") else "b"
            if color != side:
                raise ValueError("not your turn")
            fen = rec["fen"]

        result = play_rules.make_move(fen, uci)
        if not result.legal:
            raise ValueError("illegal move")

        with self._lock:
            rec = self._records.get(match_id)
            if rec is None or rec["match"]["status"] != "playing":
                raise ValueError("match no longer active")
            match = rec["match"]
            # Server-authoritative clock update.
            now = _now_ms()
            elapsed = now - match["clockUpdatedAt"]
            if side == "w":
                match["clocks"]["whiteMs"] = max(0, match["clocks"]["whiteMs"] - elapsed + match["timeControl"]["incrementSeconds"] * 1000)
            else:
                match["clocks"]["blackMs"] = max(0, match["clocks"]["blackMs"] - elapsed + match["timeControl"]["incrementSeconds"] * 1000)
            match["clockUpdatedAt"] = now
            move = {
                "ply": len(rec["moves"]) + 1,
                "san": result.san,
                "uci": uci,
                "fen": result.fen,
                "clockMsAfter": match["clocks"]["whiteMs"] if side == "w" else match["clocks"]["blackMs"],
                "latencyMs": elapsed,
            }
            rec["moves"].append(move)
            rec["fen"] = result.fen
            match["ply"] = len(rec["moves"])
            flag_reason = self._track_anticheat(rec, side, elapsed)
            finish = None
            if result.checkmate:
                finish = {"kind": "mate", "winner": side}
            elif result.stalemate:
                finish = {"kind": "draw", "reason": "stalemate"}
            elif result.draw:
                finish = {"kind": "draw", "reason": result.draw}
            if finish:
                match["status"] = "finished"
                match["result"] = finish
                self._record_my_game(match)
                self._apply_rating(match, finish)
            match_copy = dict(match)
            move_copy = dict(move)
            clocks_copy = dict(match["clocks"])
            finish_copy = dict(finish) if finish else None

        metrics.play_move_latency(elapsed / 1000.0)
        if flag_reason:
            self._flag_match(match_id, user["id"], flag_reason)
        if finish_copy:
            metrics.play_match_finished()
        self._emit({
            "type": "match.move",
            "matchId": match_id,
            "move": move_copy,
            "clocks": clocks_copy,
            "clockUpdatedAt": now,
        })
        if finish_copy:
            self._emit({
                "type": "match.finish",
                "matchId": match_id,
                "result": finish_copy,
                "clocks": clocks_copy,
            })
        return {"move": move_copy, "match": match_copy, "result": finish_copy}

    def resign(self, user: dict[str, Any], match_id: str) -> dict[str, Any]:
        with self._lock:
            rec = self._records.get(match_id)
            if rec is None:
                raise KeyError("match not found")
            match = rec["match"]
            if match["status"] != "playing":
                raise ValueError("match finished")
            color = self._user_color(match, user["id"])
            if color is None:
                raise PermissionError("not a participant")
            result = {"kind": "resign", "winner": "b" if color == "w" else "w"}
            match["status"] = "finished"
            match["result"] = result
            self._record_my_game(match)
            self._apply_rating(match, result)
            clocks_copy = dict(match["clocks"])
            result_copy = dict(result)
        metrics.play_match_finished()
        self._emit({"type": "match.finish", "matchId": match_id, "result": result_copy, "clocks": clocks_copy})
        return result_copy

    def list_my_games(self, user_id: str) -> list[dict[str, Any]]:
        with self._lock:
            return list(self._my_games.get(user_id, []))

    def get_my_rating(self, user_id: str) -> list[dict[str, Any]]:
        return rating.rating_store.get(user_id)

    # ---- clock arbiter (driven by play_ws loop) ----

    def check_timeouts(self) -> None:
        """Flag any active match whose side-to-move clock has run out."""
        with self._lock:
            now = _now_ms()
            to_finish: list[tuple[str, dict, dict]] = []
            for rec in self._records.values():
                match = rec["match"]
                if match["status"] != "playing" or match["timeControl"]["baseSeconds"] == 0:
                    continue
                side = "w" if rec["fen"].split()[1] == "w" else "b"
                remaining = (match["clocks"]["whiteMs"] if side == "w" else match["clocks"]["blackMs"]) - (now - match["clockUpdatedAt"])
                if remaining <= 0:
                    result = {"kind": "timeout", "winner": "b" if side == "w" else "w"}
                    match["status"] = "finished"
                    match["result"] = result
                    if side == "w":
                        match["clocks"]["whiteMs"] = 0
                    else:
                        match["clocks"]["blackMs"] = 0
                    match["clockUpdatedAt"] = now
                    self._record_my_game(match)
                    self._apply_rating(match, result)
                    to_finish.append((match["id"], dict(result), dict(match["clocks"])))
        for match_id, result, clocks in to_finish:
            metrics.play_match_finished()
            metrics.play_timeout()
            self._emit({"type": "match.finish", "matchId": match_id, "result": result, "clocks": clocks})

    # ---- helpers ----

    def _record_my_game(self, match: dict[str, Any]) -> None:
        for u in (match["white"]["id"], match["black"]["id"]):
            lst = self._my_games.setdefault(u, [])
            if not any(g["id"] == match["id"] for g in lst):
                lst.insert(0, dict(match))

    def _track_anticheat(self, rec: dict[str, Any], side: str, elapsed_ms: int) -> str | None:
        """Update move-time stats for `side`; return a flag reason, if any.

        Called with `self._lock` held. Heuristic only — never auto-bans, just
        queues the match for human review (docs/ONLINE_PLAY_PLAN.md Phase 7).
        """
        meta = rec["anticheat"][side]
        meta["times"].append(elapsed_ms)
        if len(meta["times"]) > 1 and elapsed_ms < _INSTANT_MOVE_MS:
            meta["instant"] += 1
            if meta["instant"] == _INSTANT_MOVE_FLAG_COUNT:
                return "instant_moves"
        return None

    def record_blur(self, user: dict[str, Any], match_id: str) -> None:
        """Record a focus-out event from `user` while it is not their turn.

        A blur during the opponent's think time is a weak signal (looking up
        moves elsewhere); repeated occurrences queue the match for review.
        """
        flag_reason = None
        with self._lock:
            rec = self._records.get(match_id)
            if rec is None:
                return
            match = rec["match"]
            if match["status"] != "playing":
                return
            color = self._user_color(match, user["id"])
            if color is None:
                return
            side_to_move = "w" if rec["fen"].split()[1] == "w" else "b"
            if color == side_to_move:
                return  # blur while it's your own turn is not suspicious
            blur = rec["anticheat"]["blur"]
            blur[color] += 1
            if blur[color] == _BLUR_FLAG_COUNT:
                flag_reason = "blur_loss"
        if flag_reason:
            self._flag_match(match_id, user["id"], flag_reason)

    def _flag_match(self, match_id: str, user_id: str, reason: str) -> None:
        entry = {"matchId": match_id, "userId": user_id, "reason": reason, "at": _now_ms()}
        with self._lock:
            self._review_queue.append(entry)
        metrics.play_flagged(reason)

    def get_review_queue(self) -> list[dict[str, Any]]:
        with self._lock:
            return list(self._review_queue)

    def is_user_in_rated_match(self, user_id: str) -> bool:
        with self._lock:
            for rec in self._records.values():
                match = rec["match"]
                if match["status"] != "playing" or not match["rated"]:
                    continue
                if user_id in (match["white"]["id"], match["black"]["id"]):
                    return True
        return False

    def _apply_rating(self, match: dict[str, Any], result: dict[str, Any]) -> None:
        if not match.get("rated"):
            return
        wa, wb = match["white"]["id"], match["black"]["id"]
        kind = result.get("kind")
        if kind in ("mate", "resign", "timeout"):
            score = 1.0 if result["winner"] == "w" else 0.0
        elif kind == "draw":
            score = 0.5
        else:  # aborted — no rated effect
            return
        try:
            rating.rating_store.update(wa, wb, score, match["variant"], match["timeControl"]["kind"])
        except Exception:
            pass

    def match_to_pgn(self, match_id: str) -> str | None:
        with self._lock:
            rec = self._records.get(match_id)
            if rec is None:
                return None
            match = rec["match"]
            moves = list(rec["moves"])
        result_str = {"1-0": "1-0", "0-1": "0-1", "1/2-1/2": "1/2-1/2"}.get(self._result_pgn(match), "*")
        tc = match["timeControl"]
        tc_str = f"{tc['baseSeconds']}+{tc['incrementSeconds']}" if tc["baseSeconds"] else "unlimited"
        headers = [
            '[Event "scidb-beta online play"]',
            '[Site "scidb-beta"]',
            f'[Date "{time.strftime("%Y.%m.%d", time.gmtime())}"]',
            f'[White "{match["white"]["name"]}"]',
            f'[Black "{match["black"]["name"]}"]',
            f'[Result "{result_str}"]',
            f'[TimeControl "{tc_str}"]',
            f'[Variant "{match["variant"]}"]',
        ]
        movetext_parts = []
        for i, mv in enumerate(moves):
            if i % 2 == 0:
                movetext_parts.append(f"{i // 2 + 1}.")
            movetext_parts.append(mv["san"])
        movetext = " ".join(movetext_parts)
        body = movetext + f" {result_str}" if movetext else result_str
        return "\n".join(headers) + "\n\n" + body + "\n"

    def _result_pgn(self, match: dict[str, Any]) -> str:
        r = match.get("result")
        if not r:
            return "*"
        if r["kind"] in ("mate", "resign", "timeout"):
            return "1-0" if r["winner"] == "w" else "0-1"
        if r["kind"] == "draw":
            return "1/2-1/2"
        return "*"

    def reset(self) -> None:
        with self._lock:
            self._seeks.clear()
            self._records.clear()
            self._my_games.clear()
            self._subscribers.clear()
            self._review_queue.clear()


# Module singleton used by play_routes + play_ws. Tests call reset() between cases.
play_service = PlayService()

# ---- Phase 5: offers, rematch, abort, chat ----

_ABORT_MAX_PLY = 1  # abort only allowed before the second move (no rated effect)

def _sanitize_chat(text: str) -> str:
    # Strip angle brackets to prevent any markup injection; cap length.
    import html
    return html.escape(text)[:280]


class PlayServiceOffersMixin:
    """Offer / rematch / abort / chat methods (mixed into PlayService)."""


def _new_match_from(self: "PlayService", old: dict[str, Any]) -> dict[str, Any]:
    """Create a rematch match with swapped colours from a finished `old`."""
    base_ms = old["timeControl"]["baseSeconds"] * 1000
    white, black = old["black"], old["white"]  # swap
    match = {
        "id": _gen_id("match"),
        "variant": old["variant"],
        "timeControl": old["timeControl"],
        "rated": old["rated"],
        "white": white,
        "black": black,
        "startFen": old["startFen"],
        "ply": 0,
        "status": "playing",
        "result": None,
        "clocks": {"whiteMs": base_ms, "blackMs": base_ms},
        "clockUpdatedAt": _now_ms(),
        "drawOfferSide": None,
        "rematchOfferSide": None,
        "arbiterId": white["id"],
    }
    with self._lock:
        self._records[match["id"]] = {
            "match": match,
            "fen": old["startFen"],
            "moves": [],
            "pos_keys": [],
            "anticheat": {"w": {"times": [], "instant": 0}, "b": {"times": [], "instant": 0}, "blur": {"w": 0, "b": 0}},
        }
    metrics.play_match_started()
    return match


def offer(self: "PlayService", user: dict[str, Any], match_id: str, kind: str) -> None:
    if kind not in ("draw", "rematch", "takeback"):
        raise ValueError("unknown offer")
    with self._lock:
        rec = self._records.get(match_id)
        if rec is None:
            raise KeyError("match not found")
        match = rec["match"]
        color = self._user_color(match, user["id"])
        if color is None:
            raise PermissionError("not a participant")
        if kind == "rematch":
            if match["status"] != "finished":
                raise ValueError("rematch only after game over")
            match["rematchOfferSide"] = color
        else:
            if match["status"] != "playing":
                raise ValueError("match finished")
            if kind == "draw":
                if match["rated"]:
                    pass  # draws allowed in rated too
                match["drawOfferSide"] = color
            elif kind == "takeback":
                # Takeback requires fen rollback; deferred past Phase 5.
                raise ValueError("takeback not supported in v1")
        match_copy_color = color
    self._emit({"type": "match.offer", "matchId": match_id, "offer": kind, "side": match_copy_color})


def respond_offer(self: "PlayService", user: dict[str, Any], match_id: str, accept: bool) -> None:
    with self._lock:
        rec = self._records.get(match_id)
        if rec is None:
            raise KeyError("match not found")
        match = rec["match"]
        color = self._user_color(match, user["id"])
        if color is None:
            raise PermissionError("not a participant")
        # Determine the pending offer from the opponent's side.
        pending = None
        if match.get("drawOfferSide") and match["drawOfferSide"] != color:
            pending = "draw"
        elif match.get("rematchOfferSide") and match["rematchOfferSide"] != color:
            pending = "rematch"
        if pending is None:
            raise ValueError("no pending offer")
        offer_kind = pending
        side = color
        if not accept:
            if offer_kind == "draw":
                match["drawOfferSide"] = None
            elif offer_kind == "rematch":
                match["rematchOfferSide"] = None
        else:
            if offer_kind == "draw":
                match["status"] = "finished"
                match["result"] = {"kind": "draw", "reason": "agreement"}
                match["drawOfferSide"] = None
                self._record_my_game(match)
                self._apply_rating(match, {"kind": "draw", "reason": "agreement"})
            elif offer_kind == "rematch":
                match["rematchOfferSide"] = None
                old_match = dict(match)
                # Defer rematch creation outside the lock to avoid re-entrancy.
        # Prepare rematch creation outside lock if accepted+rematch.
        do_rematch = accept and offer_kind == "rematch"
        rematch_old = dict(match) if do_rematch else None
        response_event = {"matchId": match_id, "offer": offer_kind, "accepted": accept, "side": side}
    # Emit the response.
    self._emit({"type": "match.offer.response", "matchId": match_id, "offer": offer_kind, "accepted": accept, "side": side})
    if offer_kind == "draw" and accept:
        with self._lock:
            rec = self._records.get(match_id)
            clocks_copy = dict(rec["match"]["clocks"]) if rec else {"whiteMs": 0, "blackMs": 0}
        metrics.play_match_finished()
        self._emit({"type": "match.finish", "matchId": match_id, "result": {"kind": "draw", "reason": "agreement"}, "clocks": clocks_copy})
    if do_rematch and rematch_old is not None:
        new_match = _new_match_from(self, rematch_old)
        self._emit({"type": "match.paired", "match": dict(new_match)})


def abort(self: "PlayService", user: dict[str, Any], match_id: str) -> dict[str, Any]:
    with self._lock:
        rec = self._records.get(match_id)
        if rec is None:
            raise KeyError("match not found")
        match = rec["match"]
        color = self._user_color(match, user["id"])
        if color is None:
            raise PermissionError("not a participant")
        if match["status"] != "playing":
            raise ValueError("match finished")
        if len(rec["moves"]) > _ABORT_MAX_PLY:
            raise ValueError("too many moves to abort")
        result = {"kind": "aborted"}
        match["status"] = "finished"
        match["result"] = result
        # Aborted games have no rated effect; still record for history.
        self._record_my_game(match)
        clocks_copy = dict(match["clocks"])
        result_copy = dict(result)
    metrics.play_match_finished()
    self._emit({"type": "match.finish", "matchId": match_id, "result": result_copy, "clocks": clocks_copy})
    return result_copy


def chat(self: "PlayService", user: dict[str, Any], match_id: str, text: str) -> dict[str, Any]:
    with self._lock:
        rec = self._records.get(match_id)
        if rec is None:
            raise KeyError("match not found")
        match = rec["match"]
        color = self._user_color(match, user["id"])
        if color is None:
            raise PermissionError("not a participant")
    clean = _sanitize_chat(text)
    if not clean.strip():
        raise ValueError("empty message")
    side = color
    self._emit({"type": "match.chat", "matchId": match_id, "side": side, "text": clean})
    return {"side": side, "text": clean}


# Bind mixin-style methods onto PlayService.
PlayService.offer = offer  # type: ignore[attr-defined]
PlayService.respond_offer = respond_offer  # type: ignore[attr-defined]
PlayService.abort = abort  # type: ignore[attr-defined]
PlayService.chat = chat  # type: ignore[attr-defined]
