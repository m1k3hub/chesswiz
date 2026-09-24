#!/usr/bin/env python3
"""Validate a corpus precedent index before trusting it.

Checks that the full Lumbras index is representative (not opening-biased),
internally consistent, and matches known master practice.

    python3 validate_index.py --db /path/lumbras_index.sqlite
"""

import argparse
import json
import os
import sqlite3
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROBE = os.path.join(HERE, "corpus_precedent.py")

START = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

results = []


def check(name, cond, detail=""):
    results.append((name, bool(cond), detail))


def query(db, moves=None, fen=None, limit=10):
    args = [sys.executable, PROBE, "query", "--db", db, "--limit", str(limit)]
    args += ["--moves", moves] if moves else ["--fen", fen]
    return json.loads(subprocess.check_output(args))


def share(res, move):
    for m in res["moves"]:
        if m["move"] == move:
            return m["share"], m["scorePct"]
    return 0.0, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", required=True)
    ap.add_argument("--min-games", type=int, default=800_000)
    ap.add_argument("--min-rows", type=int, default=15_000_000)
    args = ap.parse_args()

    con = sqlite3.connect(args.db)
    rows = con.execute("SELECT COUNT(*) FROM moves").fetchone()[0]
    con.close()

    start = query(args.db, fen=START, limit=6)
    games = start["games"]

    check("index has enough games", games >= args.min_games, f"{games:,}")
    check("index has enough rows", rows >= args.min_rows, f"{rows:,}")
    check("sideToMove is white at start", start["sideToMove"] == "white")

    # First-move spread must not be degenerate (the bug we hit with a prefix sample).
    d4 = share(start, "d2d4")[0]
    e4 = share(start, "e2e4")[0]
    c4 = share(start, "c2c4")[0]
    nf3 = share(start, "g1f3")[0]

    check("1.d4 plausible (20-50%)", 20 <= d4 <= 50, f"{d4}%")
    check("1.e4 plausible (20-50%)", 20 <= e4 <= 50, f"{e4}%")
    check("1.c4 plausible (5-20%)", 5 <= c4 <= 20, f"{c4}%")
    check("1.Nf3 present (>2%)", nf3 > 2, f"{nf3}%")
    check("d4+e4+c4+Nf3 covers most games",
          d4 + e4 + c4 + nf3 >= 85, f"{round(d4+e4+c4+nf3,1)}%")

    # Black's answer to 1.e4: both 1...e5 and 1...c5 must be substantial.
    e4r = query(args.db, moves="e4", limit=6)
    c5 = share(e4r, "c7c5")[0]
    e5 = share(e4r, "e7e5")[0]
    check("1...e5 substantial (15-40%)", 15 <= e5 <= 40, f"{e5}%")
    check("1...c5 substantial (25-50%)", 25 <= c5 <= 50, f"{c5}%")
    check("1...c5 is the top reply to 1.e4", c5 > e5, f"c5 {c5}% vs e5 {e5}%")
    check("1...c5 side-to-move is black", e4r["sideToMove"] == "black")

    # Known lines should be dominant and correctly oriented.
    nimzo = query(args.db, moves="d4 Nf6 c4 e6 Nc3 Bb4", limit=6)
    e3, e3score = share(nimzo, "e2e3")
    qc2, _ = share(nimzo, "d1c2")
    check("Nimzo 4.e3 is the top move (>30%)", e3 > 30, f"{e3}%")
    check("Nimzo 4.e3 + 4.Qc2 dominate (>60%)", e3 + qc2 > 60, f"{round(e3+qc2,1)}%")
    check("Nimzo 4.e3 scores ~52% for White",
          e3score is not None and 48 <= e3score <= 56, f"{e3score}%")

    qgd = query(args.db, moves="d4 d5 c4 e6", limit=4)
    nc3, _ = share(qgd, "b1c3")
    check("QGD 3.Nc3 common (>45%)", nc3 > 45, f"{nc3}%")

    # A rarer line should still have data in the full index.
    rare = query(args.db, moves="e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6", limit=4)
    check("Najdorf has games", rare["games"] > 1000, f"{rare['games']:,}")

    print(f"index: {args.db}")
    print(f"games: {games:,}   rows: {rows:,}\n")
    failed = 0
    for name, ok, detail in results:
        tag = "PASS" if ok else "FAIL"
        if not ok:
            failed += 1
        print(f"{tag}: {name}" + (f"  [{detail}]" if detail else ""))

    print(f"\n{len(results)-failed}/{len(results)} checks passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
