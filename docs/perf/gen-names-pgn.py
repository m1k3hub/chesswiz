#!/usr/bin/env python3
"""Write two 100k-game PGNs for the name-table import benchmark:
distinct.pgn (every player and event new) and repeated.pgn (500 players, 300 events).
usage: gen-names-pgn.py OUTDIR"""
import random, sys, os
out = sys.argv[1]
random.seed(1)
moves = "1.e4 e5 2.Nf3 Nc6 3.Bb5 a6 4.Ba4 Nf6 5.O-O Be7 1-0"
def game(w, b, i, ev):
    return (f'[Event "{ev}"]\n[Site "Somewhere"]\n[Date "2020.01.01"]\n[Round "{i%9+1}"]\n'
            f'[White "{w}"]\n[Black "{b}"]\n[Result "1-0"]\n\n{moves}\n\n')
with open(os.path.join(out, "distinct.pgn"), "w") as f:
    for i in range(100000):
        f.write(game(f"Zq{random.randrange(10**9):09d}, A", f"Yq{random.randrange(10**9):09d}, B", i,
                     f"Ev{random.randrange(10**9):09d}"))
with open(os.path.join(out, "repeated.pgn"), "w") as f:
    for i in range(100000):
        f.write(game(f"Zq{i%500:09d}, A", f"Yq{i%500:09d}, B", i, f"Ev{i%300:09d}"))
