#!/usr/bin/env python3
"""Enumerate MISSING H0 states at the current table (dry run, no writes).

For each PGN-matched Grenke Chess960 game, walk the real .cbg raw stream with
the PROVEN count-cipher math (derive counts from bytes, ground-truth lc from the
PGN via scidb's encoder). At every ply where H0[count_prev, lc_prev, lc, ply] is
ABSENT, record it as a fillable target. Also flag AMBIGUITY: keys where the SAME
state yields DIFFERENT count values across games (model gap, not fillable by a
single table entry).

Model:
  count_0 = g(lc0);  count_p = H0(count_{p-1}, lc_{p-1}, lc_p, p)
  raw_p   = InvLUT[lc_p] + count_p (mod 256)

Usage: enumerate_missing_h0.py [cbv]
Prereq: build src/list_cbv_headers and src/probe_cbh_chess960.
"""
import json, re, subprocess, sys, chess, chess.pgn
from pathlib import Path
from collections import defaultdict

REPO = Path('/media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex')
CBV = sys.argv[1] if len(sys.argv) > 1 else REPO/'opening-report/tests/fixtures/twic1639_grenke_freestyle_open.cbv'
CBH = REPO/'opening-report/tests/fixtures/twic1639.cbh'
PGN = REPO/'opening-report/tests/fixtures/grenke_freestyle_2026.pgn'

src = (REPO/'src/db/cbh/cbh_decoder.cpp').read_text()
m = re.search(r'MoveNumberLookup\[256\] =\s*\{(.*?)\};', src, re.S)
LUT = [int(x, 16) for x in re.findall(r'0x[0-9a-f]{2}', m.group(1))]
INV = [0]*256
for i, v in enumerate(LUT):
    INV[v] = i

u = json.load(open(REPO/'src/count_cipher_universal.json'))
H0 = u['H0']; g = u['g_count0']

# --- CBV headers (cbv-index -> lastname white/black/round) ---
hdr = subprocess.run([str(REPO/'src/list_cbv_headers'), str(CBV), '1'],
                     capture_output=True, text=True).stdout
cbv = {}
for line in hdr.splitlines():
    if line.startswith('database='): continue
    p = line.strip().split('\t')
    if len(p) < 7: continue
    try: idx = int(p[0])
    except ValueError: continue
    cbv[idx] = (p[1].split(',')[0].strip(), p[2].split(',')[0].strip(), p[6])

# --- PGN games ---
pgn = []
with open(PGN, encoding='utf-8') as fh:
    while True:
        gm = chess.pgn.read_game(fh)
        if gm is None: break
        w = gm.headers.get('White','').split(',')[0].strip()
        b = gm.headers.get('Black','').split(',')[0].strip()
        r = gm.headers.get('Round','')
        fen = gm.headers.get('FEN','')
        if not fen: continue
        brd = chess.Board(fen, chess960=True)
        ucis = []
        for mv in gm.mainline_moves():
            ucis.append(mv.uci()); brd.push(mv)
        pgn.append((w, b, r, fen, ucis))

matches = []
for w,b,r,fen,ucis in pgn:
    for idx,(cw,cb,cr) in cbv.items():
        if (w,b,r) == (cw,cb,cr):
            matches.append((idx, fen, ucis)); break
print(f"pgn games: {len(pgn)}, matched to cbv: {len(matches)}", file=sys.stderr)

# --- raw move bytes per cbv index (via the .cbh mirror) ---
res = subprocess.run([str(REPO/'src/probe_cbh_chess960'), str(CBH), '--dump-moves'],
                     capture_output=True, text=True)
raws = {}
cur = None
for line in res.stdout.splitlines():
    mm = re.match(r'game=(\d+) ', line)
    if mm: cur = int(mm.group(1)); continue
    mm = re.match(r'\s+moves=([0-9a-f ]+)$', line)
    if mm and cur is not None:
        raws[cur] = bytes.fromhex(mm.group(1).replace(' ',''))

# --- lc per move via scidb encoder (probe_encode960 takes SAN) ---
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

missing = defaultdict(set)   # key -> set of derived counts (ambiguity detection)
n_aligned = 0
n_misaligned = 0
games_seen = 0
for idx, fen, ucis in matches:
    raw = raws.get(idx)
    if raw is None: continue
    lcs = lcs_of(fen, ucis)
    if not lcs: continue
    games_seen += 1

    count = None; lc_prev = None; pos = 0; ok = True
    for ply, (lc, nb) in enumerate(lcs):
        if pos >= len(raw): ok = False; break
        rp = raw[pos]; cnt = (rp - INV[lc]) & 0xff
        if ply == 0:
            if str(lc) in g and g[str(lc)] != cnt:
                ok = False; break
            count = cnt
        else:
            key = f"{count},{lc_prev},{lc},{ply}"
            known = H0.get(key)
            if known is not None:
                if known != cnt:
                    ok = False; break   # misalignment -> skip whole game
            else:
                missing[key].add(cnt)   # fillable target (or ambiguous)
        lc_prev = lc; count = cnt; pos += nb
    if ok: n_aligned += 1
    else: n_misaligned += 1

print(f"games walked: {games_seen}, aligned: {n_aligned}, misaligned/skipped: {n_misaligned}")
print(f"missing H0 keys reached by aligned games: {len(missing)}")
fillable = {k for k,v in missing.items() if len(v) == 1}
ambig    = {k:v for k,v in missing.items() if len(v) > 1}
print(f"  -> fillable (unique count): {len(fillable)}")
print(f"  -> ambiguous (multi-count): {len(ambig)}")

# ply distribution
from collections import Counter
plydist = Counter(int(k.split(',')[3]) for k in missing)
print("\nmissing-key ply distribution:")
for ply in sorted(plydist):
    print(f"  ply {ply:2d}: {plydist[ply]}")
    if ply > 40: break

# ambiguous examples
if ambig:
    print(f"\nambiguous states (model gap, {len(ambig)}):")
    for k, v in list(ambig.items())[:15]:
        print(f"  {k} -> counts {sorted(v)}")

# write fillable target list
out = Path('/tmp/missing_h0_fillable.tsv')
with open(out, 'w') as fh:
    for k in sorted(fillable, key=lambda s: tuple(int(x) for x in s.split(','))):
        v = missing[k].pop()
        fh.write(f"{k}\t{v}\n")
print(f"\nwrote {len(fillable)} fillable targets to {out}")
