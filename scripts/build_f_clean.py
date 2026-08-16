#!/usr/bin/env python3
"""Build F(lc_prev,lc,ply) from CLEAN oracle games with majority-vote denoising.

For each clean game: count_p = (raw_p - invLUT[lc_p]) & 0xff using scidb's lc
(~95% right). F(lc_prev,lc,ply) = (count_p - count_prev) & 0xff. Because F is a
deterministic 3-input function, the ~5% wrong-lc samples are noise that a
per-triple majority vote removes.

Report determinism + coverage, and write the merged F table (from clean games,
then merged with the table-derived F). Then SIMULATE: does F-consistency recover
lc (and hence count) for the full clean-game trajectories, and how many states do
the clean games cover?
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
u = json.load(open(REPO/'src/count_cipher_universal.json'))
g = u['g_count0']

res = subprocess.run([str(REPO/'src/probe_cbh_chess960'), CBH, '--dump-moves'],
                     capture_output=True, text=True)
raws = {}; cur = None
for line in res.stdout.splitlines():
    mm = re.match(r'game=(\d+) ', line)
    if mm: cur = int(mm.group(1)); continue
    mm = re.match(r'\s+moves=([0-9a-f ]+)$', line)
    if mm and cur is not None: raws[cur] = bytes.fromhex(mm.group(1).replace(' ',''))

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

# F samples per triple from clean games (scidb lc)
Fcnt = defaultdict(Counter)
for idx in range(len(pgames)):
    if idx not in raws: continue
    fen, ucis = pgames[idx]
    raw = raws[idx]
    lcs = lcs_of(fen, ucis)
    if not lcs: continue
    lc0 = lcs[0][0]
    c0 = (raw[0] - INV[lc0]) & 0xff
    if str(lc0) not in g or g[str(lc0)] != c0: continue
    count = c0; lp = lc0
    for ply in range(1, len(lcs)):
        lc, nb = lcs[ply]
        off = sum(nb for _, nb in lcs[:ply])
        if off >= len(raw): break
        cnt = (raw[off] - INV[lc]) & 0xff
        Fcnt[(lp, lc, ply)][(cnt - count) & 0xff] += 1
        count = cnt; lp = lc

# denoise: majority F per triple
F = {}
for t, cnt in Fcnt.items():
    f, v = cnt.most_common(1)[0]
    # only keep if the majority has >50% (clean)
    if v * 2 > sum(cnt.values()):
        F[t] = f

print(f"clean-game (lc_prev,lc,ply) triples reached: {len(Fcnt)}")
print(f"  -> clean (majority>50%) F triples: {len(F)}")
noisy = sum(1 for t,c in Fcnt.items() if c.most_common(1)[0][1]*2 <= sum(c.values()))
print(f"  -> noisy triples (discarded): {noisy}")
print(f"  -> F triples with ply<=5: {sum(1 for (a,b,p) in F if p<=5)}")
print(f"  -> F triples with ply<=10: {sum(1 for (a,b,p) in F if p<=10)}")
print(f"  -> F triples with ply<=20: {sum(1 for (a,b,p) in F if p<=20)}")

# merge with table-derived F
tabF = json.load(open(REPO/'src/f_table.json'))['F']
tabF = {tuple(int(x) for x in k.split(',')): v for k,v in tabF.items()}
merged = dict(tabF); merged.update(F)   # clean overrides
print(f"\nmerged F table size: {len(merged)}")

# write merged F table for the decoder
json.dump({"F": {f"{a},{b},{p}": v for (a,b,p),v in merged.items()},
           "F_entries": len(merged),
           "source": "merged: table majority-vote + clean-oracle"},
          open(REPO/'src/f_table.json','w'), indent=1)
print(f"wrote merged F -> {REPO/'src/f_table.json'}")

# simulate: can F-consistency recover lc for clean-game moves?
# for moves where F(lc_prev, lc, ply) is known, verify raw matches; count recovered lc errors
n_moves = 0; n_fknown = 0; n_match = 0; n_lc_err = 0
for idx in range(len(pgames)):
    if idx not in raws: continue
    fen, ucis = pgames[idx]
    raw = raws[idx]
    lcs = lcs_of(fen, ucis)
    if not lcs: continue
    lc0 = lcs[0][0]; c0 = (raw[0] - INV[lc0]) & 0xff
    if str(lc0) not in g or g[str(lc0)] != c0: continue
    count = c0; lp = lc0
    for ply in range(1, len(lcs)):
        lc, nb = lcs[ply]
        off = sum(nb for _, nb in lcs[:ply])
        if off >= len(raw): break
        n_moves += 1
        f = merged.get((lp, lc, ply))
        if f is None: continue
        n_fknown += 1
        cnt = (count + f) & 0xff
        if (INV[lc] + cnt) & 0xff == raw[off]:
            n_match += 1
            count = cnt; lp = lc
        else:
            n_lc_err += 1  # scidb lc disagrees with F-consistent count
print(f"\nsimulation (clean games, F-consistent): moves={n_moves}, F-known={n_fknown}")
print(f"  F-consistent matches: {n_match} ({100.0*n_match/max(n_fknown,1):.2f}%)")
print(f"  scidb-lc mismatches (would need lc recovery): {n_lc_err}")
