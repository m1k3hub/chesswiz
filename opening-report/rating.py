"""rating — Glicko-2 ratings for online play (Phase 6).

Per (variant, timeControl.kind) ratings. In-memory store (single-process v1;
persistence + multi-instance via Redis is Phase 7+). New players start
provisional (r=1500, rd=350, vol=0.06) and the rating deviation shrinks as they
play. Floors: rating floor (100) and rd floor (30) applied after each update.

Reference: Glickman, "Example of the Glicko-2 system" (2013). Each rated game is
treated as one rating period with a single opponent (m=1); both players are
updated against each other.
"""

from __future__ import annotations

import math
import threading
from typing import Any

_SCALE = 173.7178
_TAU = 0.5  # system constant (constrains volatility change)
_RATING_FLOOR = 100.0
_RD_FLOOR = 30.0
_DEFAULT = {"r": 1500.0, "rd": 350.0, "vol": 0.06}


def _g(phi: float) -> float:
    return 1.0 / math.sqrt(1.0 + 3.0 * phi * phi / (math.pi * math.pi))


def _e(mu: float, mu_j: float, phi_j: float) -> float:
    return 1.0 / (1.0 + math.exp(-_g(phi_j) * (mu - mu_j)))


def _new_volatility(sigma: float, phi: float, v: float, delta: float) -> float:
    a = math.log(sigma * sigma)
    tau = _TAU

    def f(x: float) -> float:
        ex = math.exp(x)
        num = ex * (delta * delta - phi * phi - v - ex)
        den = 2.0 * (phi * phi + v + ex) ** 2
        return num / den - (x - a) / (tau * tau)

    # Initial iteration bounds (A = a, B per Glickman's procedure).
    A = a
    if delta * delta > phi * phi + v:
        B = math.log(delta * delta - phi * phi - v)
    else:
        k = 1
        while f(a - k * tau) < 0:
            k += 1
        B = a - k * tau
    fa, fb = f(A), f(B)
    # Iterate to convergence.
    for _ in range(100):
        if abs(B - A) < 1e-10:
            break
        C = A + (A - B) * fa / (fb - fa)
        fc = f(C)
        if fc * fb <= 0:
            A, fa = B, fb
        else:
            fa /= 2.0
        B, fb = C, fc
    return math.exp(A / 2.0)


def _update_one(r: float, rd: float, vol: float, r_j: float, rd_j: float, score: float) -> tuple[float, float, float]:
    mu = (r - 1500.0) / _SCALE
    phi = rd / _SCALE
    mu_j = (r_j - 1500.0) / _SCALE
    phi_j = rd_j / _SCALE

    g_j = _g(phi_j)
    e = _e(mu, mu_j, phi_j)
    v = 1.0 / (g_j * g_j * e * (1.0 - e))
    delta = v * g_j * (score - e)

    new_vol = _new_volatility(vol, phi, v, delta)
    phi_star = math.sqrt(phi * phi + new_vol * new_vol)
    phi_new = 1.0 / math.sqrt(1.0 / (phi_star * phi_star) + 1.0 / v)
    mu_new = mu + phi_new * phi_new * g_j * (score - e)

    r_new = _SCALE * mu_new + 1500.0
    rd_new = _SCALE * phi_new
    # Floors.
    r_new = max(_RATING_FLOOR, r_new)
    rd_new = max(_RD_FLOOR, min(rd_new, 350.0))
    return r_new, rd_new, new_vol


class RatingStore:
    def __init__(self) -> None:
        self._ratings: dict[tuple[str, str], dict[str, float]] = {}  # (userId, key) -> {r, rd, vol}
        self._lock = threading.Lock()

    def _get_or_default(self, user_id: str, key: str) -> dict[str, float]:
        rec = self._ratings.get((user_id, key))
        return dict(rec) if rec else dict(_DEFAULT)

    def get(self, user_id: str) -> list[dict[str, Any]]:
        """Return all known ratings for a user (provisional default if none)."""
        with self._lock:
            keys = {k for (u, k) in self._ratings if u == user_id}
            out = []
            for k in sorted(keys):
                rec = self._ratings[(user_id, k)]
                parts = k.split(":", 1)
                out.append({
                    "variant": parts[0] if parts else "standard",
                    "timeControl": parts[1] if len(parts) > 1 else "blitz",
                    "rating": round(rec["r"], 1),
                    "rd": round(rec["rd"], 1),
                    "vol": round(rec["vol"], 4),
                })
            if not out:
                out.append({"variant": "standard", "timeControl": "blitz", "rating": 1500.0, "rd": 350.0, "vol": 0.06})
            return out

    def update(self, user_a: str, user_b: str, score_a: float, variant: str, time_control_kind: str) -> None:
        """Apply a single-game Glicko-2 update for both players."""
        key = f"{variant}:{time_control_kind}"
        with self._lock:
            a = self._get_or_default(user_a, key)
            b = self._get_or_default(user_b, key)
        ra, rda, vola = a["r"], a["rd"], a["vol"]
        rb, rdb, volb = b["r"], b["rd"], b["vol"]
        na = _update_one(ra, rda, vola, rb, rdb, score_a)
        nb = _update_one(rb, rdb, volb, ra, rda, 1.0 - score_a)
        with self._lock:
            self._ratings[(user_a, key)] = {"r": na[0], "rd": na[1], "vol": na[2]}
            self._ratings[(user_b, key)] = {"r": nb[0], "rd": nb[1], "vol": nb[2]}

    def reset(self) -> None:
        with self._lock:
            self._ratings.clear()


# Module singleton.
rating_store = RatingStore()