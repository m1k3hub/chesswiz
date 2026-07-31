"""Tests for play_rules (pure-Python standard-chess engine, Phase 4 fallback).

Pins standard-chess outcomes with known positions: fool's mate, scholar's
mate, castling, en passant, promotion, stalemate, insufficient material, and
the fifty-move rule. These are deterministic expected results (no JS engine
dependency).
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from play_rules import make_move, START_FEN, parse_fen, legal_moves


def test_fools_mate():
    f = START_FEN
    for uci in ["f2f3", "e7e5", "g2g4"]:
        r = make_move(f, uci)
        assert r.legal and r.fen
        f = r.fen
    r = make_move(f, "d8h4")
    assert r.legal
    assert r.checkmate
    assert r.san == "Qh4#"


def test_scholars_mate():
    f = START_FEN
    for uci in ["e2e4", "e7e5", "f1c4", "b8c6", "d1h5", "g8f6"]:
        f = make_move(f, uci).fen
    r = make_move(f, "h5f7")
    assert r.legal and r.checkmate and r.san == "Qxf7#"


def test_illegal_move_rejected():
    assert make_move(START_FEN, "e2e5").legal is False  # pawn can't jump 3
    assert make_move(START_FEN, "e2e3").legal is True
    assert make_move(START_FEN, "e1e2").legal is False  # king can't move 2


def test_castling_san():
    fen = "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"
    assert make_move(fen, "e1g1").san == "O-O"
    assert make_move(fen, "e1c1").san == "O-O-O"
    # can't castle through check
    attacked = "r3k2r/8/8/8/8/8/5q2/R3K2R w KQkq - 0 1"  # black queen f2 attacks f1? actually attacks g1? -> use a rook on f-file
    # queen on f3 attacks f1 -> kingside through f1 illegal
    blocked = "r3k2r/8/8/8/8/5q2/8/R3K2R w KQkq - 0 1"
    assert make_move(blocked, "e1g1").legal is False


def test_en_passant():
    ep = "rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 3"
    r = make_move(ep, "e5d6")
    assert r.legal and r.san == "exd6"


def test_promotion():
    r = make_move("8/P7/8/8/8/8/8/4k2K w - - 0 1", "a7a8q")
    assert r.legal and r.san == "a8=Q"
    r = make_move("8/P7/8/8/8/8/8/4k2K w - - 0 1", "a7a8r")
    assert r.legal and r.san == "a8=R"


def test_stalemate():
    assert len(legal_moves(parse_fen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"))) == 0
    r = make_move("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1", "h8h7")
    # stalemate means no legal move; the only "move" is illegal
    assert r.legal is False


def test_insufficient_material():
    r = make_move("8/8/8/4k3/8/8/8/4K3 w - - 0 1", "e1e2")
    assert r.draw == "insufficient"


def test_fifty_move_rule():
    # halfmove clock at 99; a knight move (no pawn/capture) -> 100 -> fifty-move draw
    fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 99 50"
    r = make_move(fen, "g1f3")
    assert r.draw == "fifty"


def test_auto_queen_when_no_promo_specified():
    r = make_move("8/P7/8/8/8/8/8/4k2K w - - 0 1", "a7a8")
    assert r.legal and r.san.startswith("a8=Q")