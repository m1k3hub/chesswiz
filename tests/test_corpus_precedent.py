#!/usr/bin/env python3
"""Regression test for scripts/corpus_precedent.py.

Covers the score-orientation bug: `query --moves` must report the score from the
side-to-move's point of view, including Black-to-move positions.
"""

import json
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SCRIPT = os.path.join(ROOT, "scripts", "corpus_precedent.py")

PGN = """[Event "t1"]
[Result "1-0"]

1. e4 e5 2. Nf3 Nc6 1-0

[Event "t2"]
[Result "0-1"]

1. e4 e5 2. Nf3 Nc6 0-1

[Event "t3"]
[Result "1-0"]

1. e4 c5 2. Nf3 d6 1-0
"""

failures = 0


def check(name, cond, detail=""):
    global failures
    if cond:
        print(f"PASS: {name}")
    else:
        failures += 1
        print(f"FAIL: {name} {detail}")


def run(args):
    out = subprocess.check_output([sys.executable, SCRIPT, *args])
    return json.loads(out)


def score_of(res, move):
    for m in res["moves"]:
        if m["move"] == move:
            return m["scorePct"]
    return None


def main():
    with tempfile.TemporaryDirectory() as d:
        pgn = os.path.join(d, "mini.pgn")
        db = os.path.join(d, "mini.sqlite")
        with open(pgn, "w") as fh:
            fh.write(PGN)
        run(["build", "--pgn", pgn, "--db", db, "--max-games", "10"])

        # Black to move after 1.e4: e5 = (1-0,0-1) -> 50% ; c5 = (1-0) -> 100% White
        by_moves = run(["query", "--db", db, "--moves", "e4"])
        check("sideToMove is black for --moves e4", by_moves["sideToMove"] == "black")
        check("Black-to-move e5 scores 50%", score_of(by_moves, "e7e5") == 50.0,
              score_of(by_moves, "e7e5"))
        check("Black-to-move c5 scores 0%", score_of(by_moves, "c7c5") == 0.0,
              score_of(by_moves, "c7c5"))

        # same position via --fen must agree (this is the regression)
        fen = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"
        by_fen = run(["query", "--db", db, "--fen", fen])
        check("--fen and --moves agree",
              [m["scorePct"] for m in by_moves["moves"]] ==
              [m["scorePct"] for m in by_fen["moves"]])

        # White to move after 1.e4 e5: Nf3 = (1-0,0-1) -> 50% for White (no flip)
        white = run(["query", "--db", db, "--moves", "e4 e5"])
        check("sideToMove is white for --moves e4 e5", white["sideToMove"] == "white")
        check("White-to-move Nf3 scores 50%", score_of(white, "g1f3") == 50.0,
              score_of(white, "g1f3"))

    if failures:
        print(f"\n{failures} corpus-precedent check(s) failed")
        return 1
    print("\nall corpus-precedent checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
