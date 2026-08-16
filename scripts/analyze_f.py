#!/usr/bin/env python3
"""Test whether F(lc_prev, lc, ply) is a DETERMINISTIC 3-input function using
ONLY clean oracle data (guaranteed-correct alignment).

count_0 = g(lc0)
count_p = H0[count_prev, lc_prev, lc, ply]   (4-input, sparse)
If F = (count_p - count_prev) & 0xff is a PURE function of (lc_prev, lc, ply)
across all clean games, then count_p = count_prev + F(lc_prev,lc,ply) and the
whole 4-input sparse table collapses to a compact 3-input F function -- which
would make the ChessBase F algorithm directly recoverable (and the decoder
complete) without per-state table coverage.

Reads the ChessBase-encoded clean games (/tmp/oracle.cbh + /tmp/grenke_clean_20.pgn).
"""
import json, re, subprocess, chess, chess.pgn
from pathlib import Path
from collections import defaultdict, Counter

REPO = Path('/media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex')
CBH = '/tmp/oracle.cbh'
PGN = '/tmp/grenke_clean_20.pgn'

src = (REPO/'src/db/cbh/cbh_decoder.cpp').read_text()
m = re.search(r'MoveNumberLookup\[256\] =\s*\{(.*?)\};', src, re.S)
LUT = [int(x, 16) for x in re.findall(r'0x[0-9a-f]{2}', m.group(1))]
INV = [0]*256
for i, v in enumerate(LUT):
    INV[v] = i

# raw bytes per game
res = subprocess.run([str(REPO/'src/probe_cbh_chess960'), CBH, '--dump-moves'],
                     capture_output=True, text=True)
raws = {}
cur = None
for line in res.stdout.splitlines():
    mm = re.match(r'game=(\d+) ', line)
    if mm: cur = int(mm.group(1)); continue
    mm = re.match(r'\s+moves=([0-9a-f ]+)$', line)
    if mm and cur is not None:
        raws[cur] = bytes.fromhex(mm.group(1).replace(' ',''))

pgames = []
with open(PGN, encoding='utf-8') as fh:
    while True:
        gm = chess.pgn.read_game(fh)
        if gm is None: break
        fen = gm.headers.get('FEN','')
        if not fen: continue
        brd = chess.Board(fen, chess960=True); ucis = []
        for mv in gm.mainline_moves():
            ucis.append(mv.uci()); brd.push(mv)
        pgames.append((fen, ucis))

def lcs_of(fen, ucis):
    try:
        b = chess.Board(fen, chess960=True); sans = []
        for uc in ucis:
            mv = chess.Move.from_uci(uc); sans.append(b.san(mv)); b.push(mv)
        clean = [s.rstrip('+#') for s in sans]
        r = subprocess.run([str(REPO/'src/probe_encode960'), fen] + clean,
                           capture_output=True, text=True, timeout=10)
        for line in r.stdout.splitlines():
            mm = re.search(r'move bytes.*?:\s*([0-9a-f ]+)', line)
            if mm:
                sb = bytes.fromhex(mm.group(1).replace(' ',''))
                out = []; j = c = 0
                while j < len(sb):
                    lc = LUT[(sb[j]-c) & 0xff]
                    nb = 3 if lc == 0xeb else 1
                    out.append((lc, nb)); j += nb; c += 1
                return out
        return []
    except Exception:
        return []

# collect F: (lc_prev, lc, ply) -> set of F values, and count states
F_vals = defaultdict(set)
n_games = 0
n_states = 0
for idx in range(len(pgames)):
    if idx not in raws: continue
    fen, ucis = pgames[idx]
    raw = raws[idx]
    lcs = lcs_of(fen, ucis)
    if not lcs: continue
    n_games += 1
    # derive counts from raw
    count = None
    lc_prev = None
    for ply, (lc, nb) in enumerate(lcs):
        pos = sum(nb for _, nb in lcs[:ply])  # byte offset = sum of nbytes before
        if pos + nb > len(raw): break
        rp = raw[pos]
        cnt = (rp - INV[lc]) & 0xff
        if ply >= 1:
            F = (cnt - count) & 0xff
            F_vals[(lc_prev, lc, ply)].add(F)
            n_states += 1
        count = cnt
        lc_prev = lc

total = len(F_vals)
det = {k for k,v in F_vals.items() if len(v) == 1}
amb = {k:v for k,v in F_vals.items() if len(v) > 1}
print(f"games: {n_games}, (lc_prev,lc,ply) states observed: {n_states}, unique triples: {total}")
print(f"deterministic F: {len(det)}  ({100.0*len(det)/max(total,1):.2f}%)")
print(f"AMBIGUOUS F (needs a 4th input): {len(amb)}  ({100.0*len(amb)/max(total,1):.2f}%)")
if amb:
    print("\nambiguous triples (sample):")
    for k, v in list(amb.items())[:25]:
        print(f"  (lc_prev={k[0]}, lc={k[1]}, ply={k[2]}) -> F in {sorted(v)}")
