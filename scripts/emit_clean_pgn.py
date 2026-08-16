#!/usr/bin/env python3
"""Emit clean (mainline-only) Chess960 PGN for the Grenke games, up to a
given ply depth, with FEN + Chess960 headers preserved. Clean games have NO
variations, so raw .cbg bytes align trivially with the mainline for the oracle
harvest (the whole point vs. the variation-laden source fixture).
"""
import sys, chess, chess.pgn
from pathlib import Path

REPO = Path('/media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex')
SRC = REPO/'opening-report/tests/fixtures/grenke_freestyle_2026.pgn'
MAX_PLY = int(sys.argv[1]) if len(sys.argv) > 1 else 40
OUT = sys.argv[2] if len(sys.argv) > 2 else '/tmp/grenke_clean.pgn'

games = []
with open(SRC, encoding='utf-8') as fh:
    while True:
        gm = chess.pgn.read_game(fh)
        if gm is None: break
        fen = gm.headers.get('FEN','')
        if not fen: continue
        games.append(gm)

out = []
for gi, gm in enumerate(games):
    fen = gm.headers.get('FEN')
    board = chess.Board(fen, chess960=True)
    g = chess.pgn.Game()
    g.headers['Event'] = gm.headers.get('Event','Grenke')
    g.headers['Site'] = gm.headers.get('Site','?')
    g.headers['Date'] = gm.headers.get('Date','????.??.??')
    g.headers['Round'] = gm.headers.get('Round','?')
    g.headers['White'] = gm.headers.get('White','?')
    g.headers['Black'] = gm.headers.get('Black','?')
    g.headers['Result'] = gm.headers.get('Result','*')
    g.headers['Variant'] = 'Chess960'
    g.headers['FEN'] = fen
    g.headers['SetUp'] = '1'
    node = g
    plies = 0
    for mv in gm.mainline_moves():
        if plies >= MAX_PLY: break
        node = node.add_variation(mv)
        plies += 1
    out.append(g)

with open(OUT, 'w', encoding='utf-8') as fh:
    for g in out:
        fh.write(str(g))
        fh.write('\n\n')
print(f"wrote {len(out)} clean games (<= {MAX_PLY} plies) to {OUT}")
