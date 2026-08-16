#!/usr/bin/env python3
"""Measure move-exactness: decode a scidb .sci/.cbv database and compare every
Chess960 game's decoded SAN mainline against the Grenke PGN ground truth.

Usage: measure_move_exactness.py <database> <pgn>
(probe_dump_moves must be built; uses src/probe_dump_moves <db>)
"""
import re, subprocess, sys, chess, chess.pgn
from pathlib import Path

REPO = Path('/media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex')
DB = sys.argv[1] if len(sys.argv) > 1 else '/tmp/twic1639_base.sci'
PGN = sys.argv[2] if len(sys.argv) > 2 else REPO/'opening-report/tests/fixtures/grenke_freestyle_2026.pgn'

# --- decoded games from scidb ---
res = subprocess.run([str(REPO/'src/probe_dump_moves'), DB],
                     capture_output=True, text=True)
decoded = {}   # game -> (white, black, fen, sans_list)
for line in res.stdout.splitlines():
    m = re.match(r'^(\d+)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$', line)
    if not m:
        continue
    g, w, b, result, fen, roundno, sans = m.groups()
    decoded[int(g)] = (w, b, fen, sans.split())

# --- PGN ground truth ---
pgn_games = []
with open(PGN, encoding='utf-8') as fh:
    while True:
        gm = chess.pgn.read_game(fh)
        if gm is None: break
        fen = gm.headers.get('FEN','')
        if not fen: continue
        w = gm.headers.get('White','').strip()
        b = gm.headers.get('Black','').strip()
        r = gm.headers.get('Round','').strip()
        brd = chess.Board(fen, chess960=True)
        sans = []
        for mv in gm.mainline_moves():
            sans.append(brd.san(mv)); brd.push(mv)
        pgn_games.append((w, b, r, fen, sans))

# match by FEN board-layout (scidb normalizes castling rights) + player lastnames
def layout(fen):
    return fen.split()[0]

def last(n):
    n = n.strip()
    return n.split(',')[0].strip().lower()

pgn_by_layout = {}
for w,b,r,fen,sans in pgn_games:
    pgn_by_layout.setdefault(layout(fen), []).append((w,b,r,sans))

n_matched = 0; n_exact = 0; n_chess960 = 0
exact_games = []; wrong_games = []
for g, (w,b,fen,sans) in decoded.items():
    if 'pppppppp' not in fen or '/' not in fen:
        continue
    n_chess960 += 1
    candidates = pgn_by_layout.get(layout(fen), [])
    match = None
    for pw,pb,pr,psans in candidates:
        if last(w)==last(pw) and last(b)==last(pb):
            match = (pw,pb,pr,psans); break
    if match is None:
        continue
    n_matched += 1
    psans = match[3]
    if sans == psans:
        n_exact += 1
        exact_games.append(g)
    else:
        wrong_games.append((g, w, b, len(sans), len(psans)))

print(f"chess960 games in db: {n_chess960}")
print(f"matched to PGN: {n_matched}")
print(f"EXACT move match: {n_exact}  ({100.0*n_exact/max(n_matched,1):.1f}%)")
print(f"wrong moves: {n_matched - n_exact}")
if wrong_games:
    print("\nsample wrong games (game, white, black, decoded#/pgn#):")
    for g,w,b,nd,np_ in wrong_games[:20]:
        print(f"  {g}: {w} vs {b}: {nd}/{np_} moves")
