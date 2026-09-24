#!/usr/bin/env python3
"""Regression test for the chess anatomy fact extractor (src/probe_chess_facts).

The whole point of the fact layer is that the language model never reasons
about the board -- so the facts themselves must be right.  Each case below
uses a position whose answer is known by chess reasoning, not by the code.
"""

import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROBE = os.path.join(HERE, os.pardir, "src", "probe_chess_facts")

CASES = [
    (
        "startpos mobility / structure",
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        lambda d: (
            d["pieces"]["white"]["mobility"] == 20,
            d["pieces"]["white"]["badBishops"] == 0,
            d["pawns"]["white"]["islands"] == 1,
            d["pawns"]["white"]["doubled"] == 0,
            d["pieces"]["white"]["developedMinors"] == 0,
            d["phase"] == "opening",
        ),
    ),
    (
        "isolated queen's pawn",
        "r1bq1rk1/pp2bppp/2n1pn2/2pp4/3P4/5NP1/PP3PBP/RNBQ1RK1 w - - 0 1",
        lambda d: (
            d["pawns"]["white"]["isolatedQueenPawn"] is True,
            d["pawns"]["white"]["isolated"] == 1,
            set(d["files"]["semiOpenForWhite"]) == {"c", "e"},
            d["pawns"]["white"]["islands"] == 3,
        ),
    ),
    (
        "opposite-coloured bishops",
        "8/5pk1/6p1/8/1b6/8/5PPP/3B2K1 w - - 0 1",
        lambda d: (
            d["material"]["oppositeColouredBishops"] is True,
            d["phase"] == "endgame",
        ),
    ),
    (
        "pin against the king",
        "rnbqk2r/pppp1ppp/5n2/8/1b6/8/PPPNPPPP/R1BQKBNR w KQkq - 0 1",
        lambda d: (d["tactics"]["whitePinned"] == ["d2"],),
    ),
    (
        "check and checker square",
        "rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3",
        lambda d: (
            d["inCheck"] is True,
            d["tactics"]["checkers"] == ["h4"],
        ),
    ),
    (
        "undefended piece",
        "4k3/8/8/8/8/8/1b6/R3K3 w Q - 0 1",
        lambda d: (d["tactics"]["whiteUndefended"] == ["a1"],),
    ),
    (
        "knight outpost",
        "4k3/8/8/4N3/3P4/8/8/4K3 w - - 0 1",
        lambda d: (d["pieces"]["white"]["knightsOutposted"] == 1,),
    ),
    (
        "passed pawn with enemy pawn behind on an adjacent file",
        "8/8/8/4P3/3p4/8/5K2/7k w - - 0 1",
        lambda d: (
            d["pawns"]["white"]["passed"] == 1,
            d["pawns"]["white"]["isolated"] == 1,
        ),
    ),
    (
        "doubled and backward pawns",
        "4k3/8/8/8/3p4/3p4/3P4/4K3 w - - 0 1",
        lambda d: (
            d["pawns"]["black"]["doubled"] == 1,
            d["pawns"]["black"]["isolated"] == 2,
        ),
    ),
    (
        "material balance and bishop pair",
        "4k3/8/8/8/8/8/8/2B1KB2 w - - 0 1",
        lambda d: (
            d["material"]["white"]["bishopPair"] is True,
            d["material"]["balanceCp"] > 600,
        ),
    ),
    (
        "legal move count",
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        lambda d: (
            d["moveStats"]["legalMoves"] == 20,
            d["moveStats"]["captures"] == 0,
            d["moveStats"]["checks"] == 0,
        ),
    ),
    (
        "knight fork",
        "4k3/3r4/2n5/4N3/8/8/8/4K3 w - - 0 1",
        lambda d: (d["motifs"]["forks"]["white"] == [{"from": "e5", "targets": ["c6", "d7"]}],),
    ),
    (
        "skewer",
        "7r/6k1/8/8/8/8/1B6/6K1 w - - 0 1",
        lambda d: (
            d["motifs"]["skewers"]["white"] == [{"by": "b2", "through": "g7", "wins": "h8"}],
            d["tactics"]["blackPinned"] == [],
        ),
    ),
    (
        "back-rank weakness",
        "6k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1",
        lambda d: (d["motifs"]["backRankWeak"] == {"white": False, "black": True},),
    ),
]


def run(fen):
    out = subprocess.check_output([PROBE, fen])
    return json.loads(out.decode("utf-8"))


MOVE_CASES = [
    (
        "knight is developed",
        "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
        "Nf3",
        lambda d: (
            d["san"] == "Nf3",          # Latin-1, not figurine
            d["uci"] == "g1f3",
            d["developed"] is True,
            d["capture"] is False,
        ),
    ),
    (
        "capture, check and mate + material swing",
        "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4",
        "Qxf7",
        lambda d: (
            d["san"] == "Qxf7",
            d["capture"] is True,
            d["captured"] == "P",
            d["check"] is True,
            d["mate"] is True,
            d["materialChangeCp"] == 100,
            d["materialBalanceWhiteCp"] == 100,
        ),
    ),
    (
        "castling uci is king destination",
        "r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4",
        "O-O",
        lambda d: (d["castling"] is True, d["uci"] == "e1g1"),
    ),
    (
        "promotion",
        "4k3/P7/8/8/8/8/8/4K3 w - - 0 1",
        "a8=Q",
        lambda d: (
            d["promotion"] == "Q",
            d["materialChangeCp"] == 800,   # +Q -P
        ),
    ),
    (
        "en passant capture",
        "rnbqkbnr/1ppppppp/p7/3Pp3/8/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 3",
        "dxe6",
        lambda d: (
            d["enPassant"] is True,
            d["captured"] == "P",
            d["materialChangeCp"] == 100,
        ),
    ),
    (
        "newly undefended piece",
        "r3k3/8/8/8/8/8/1B6/R3K3 w - - 0 1",
        "Bc1",
        lambda d: (d["newUndefended"]["white"] == ["a1"],),
    ),
    (
        "doubled pawns created by a capture",
        "4k3/8/8/8/8/1n6/PP6/4K3 w - - 0 1",
        "axb3",
        lambda d: (d["structureDelta"]["white"]["doubled"] == 1,),
    ),
    (
        "discovered attack",
        "3k4/8/8/5q2/4N3/3B4/8/3K4 w - - 0 1",
        "Nc5",
        lambda d: (d["discoveredAttacks"] == [{"by": "d3", "targets": ["f5"], "check": False}],),
    ),
    (
        "static exchange: winning capture",
        "4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1",
        "exd5",
        lambda d: (d["seeCp"] == 100, d["losesMaterial"] is False),
    ),
    (
        "static exchange: losing capture",
        "4k3/8/2p5/3p4/8/8/8/3QK3 w - - 0 1",
        "Qxd5",
        lambda d: (d["seeCp"] < 0, d["losesMaterial"] is True),
    ),
    (
        "mating capture is not flagged as material loss",
        "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4",
        "Qxf7",
        lambda d: (d["mate"] is True, d["losesMaterial"] is False),
    ),
    (
        "newly en prise",
        "4k3/8/8/8/4p1p1/8/8/4K1N1 w - - 0 1",
        "Nf3",
        lambda d: (d["newEnPrise"]["white"] == ["f3"],),
    ),
    (
        "removal of the defender",
        "6k1/3n4/8/4r3/8/6B1/8/3R2K1 w - - 0 1",
        "Rxd7",
        lambda d: (d["removesDefender"] == ["e5"],),
    ),
    (
        "discovered check",
        "8/6k1/8/8/3N4/8/1B6/6K1 w - - 0 1",
        "Nf3",
        lambda d: (
            d["check"] is True,
            d["discoveredAttacks"] == [{"by": "b2", "targets": ["g7"], "check": True}],
        ),
    ),
]


def run_move(fen, move):
    out = subprocess.check_output([PROBE, "--move", move, fen])
    return json.loads(out.decode("utf-8"))


def main():
    if not os.path.exists(PROBE):
        print(f"probe not built: {PROBE}\nrun: make -C src probe_chess_facts")
        return 2

    failures = 0

    for name, fen, check in CASES:
        try:
            data = run(fen)
            results = check(data)
            if all(results):
                print(f"PASS: {name}")
            else:
                failures += 1
                print(f"FAIL: {name}")
                print(f"      fen: {fen}")
                print(f"      results: {results}")
        except Exception as exc:  # noqa: BLE001
            failures += 1
            print(f"FAIL: {name} ({exc})")

    # determinism: identical input must yield byte-identical facts
    fen = "r1bq1rk1/pp2bppp/2n1pn2/2pp4/3P4/5NP1/PP3PBP/RNBQ1RK1 w - - 0 1"
    a = subprocess.check_output([PROBE, fen])
    b = subprocess.check_output([PROBE, fen])
    if a == b:
        print("PASS: determinism")
    else:
        failures += 1
        print("FAIL: determinism")

    for name, fen, move, check in MOVE_CASES:
        try:
            data = run_move(fen, move)
            results = check(data)
            if all(results):
                print(f"PASS: move -- {name}")
            else:
                failures += 1
                print(f"FAIL: move -- {name}")
                print(f"      fen={fen} move={move}")
                print(f"      results: {results}")
        except Exception as exc:  # noqa: BLE001
            failures += 1
            print(f"FAIL: move -- {name} ({exc})")

    if failures:
        print(f"\n{failures} chess-facts case(s) failed")
        return 1

    print(f"\nall {len(CASES) + len(MOVE_CASES) + 1} chess-facts checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
