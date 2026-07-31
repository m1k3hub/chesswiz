"""Tests for Glicko-2 ratings (Phase 6)."""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import pytest

from rating import rating_store, _update_one


@pytest.fixture(autouse=True)
def _reset_ratings():
    rating_store.reset()
    yield
    rating_store.reset()


def test_new_player_is_provisional():
    r = rating_store.get("newbie")
    assert len(r) == 1
    assert r[0]["rating"] == 1500.0
    assert r[0]["rd"] == 350.0
    assert r[0]["vol"] == 0.06


def test_win_increases_winner_rating():
    rating_store.update("alice", "bob", 1.0, "standard", "blitz")  # alice beats bob
    a = next(x for x in rating_store.get("alice") if x["variant"] == "standard")
    b = next(x for x in rating_store.get("bob") if x["variant"] == "standard")
    assert a["rating"] > 1500.0
    assert b["rating"] < 1500.0


def test_loss_decreases_loser_and_rd_shrinks():
    rating_store.update("alice", "bob", 0.0, "standard", "blitz")  # alice loses
    a = next(x for x in rating_store.get("alice") if x["variant"] == "standard")
    assert a["rating"] < 1500.0
    assert a["rd"] < 350.0  # uncertainty reduced after a game


def test_draw_keeps_both_near_1500():
    rating_store.update("alice", "bob", 0.5, "standard", "blitz")
    a = next(x for x in rating_store.get("alice") if x["variant"] == "standard")
    b = next(x for x in rating_store.get("bob") if x["variant"] == "standard")
    assert abs(a["rating"] - 1500.0) < 1.0
    assert abs(b["rating"] - 1500.0) < 1.0


def test_ratings_are_per_variant_timecontrol():
    rating_store.update("alice", "bob", 1.0, "standard", "blitz")
    # No rating under rapid yet for alice → provisional default.
    rapid = [x for x in rating_store.get("alice") if x["timeControl"] == "rapid"]
    assert not rapid


def test_rating_floor_enforced():
    # Drive one player's rating down heavily by repeated losses vs a strong
    # opponent; the floor prevents going below 100.
    for _ in range(200):
        rating_store.update("weak", "strong", 0.0, "standard", "blitz")
    w = next(x for x in rating_store.get("weak") if x["variant"] == "standard")
    assert w["rating"] >= 100.0


def test_update_one_matches_known_example_shape():
    # Sanity: a win with equal ratings should move rating up but not explode.
    r, rd, vol = _update_one(1500.0, 200.0, 0.06, 1400.0, 30.0, 1.0)
    assert 1500.0 < r < 1600.0
    assert rd < 200.0
    assert 0 < vol < 0.1