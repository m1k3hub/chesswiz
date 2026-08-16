#!/usr/bin/env python3
"""Harvest H0 entries from ChessBase-encoded CLEAN games (the oracle).

The oracle database is /tmp/oracle.cbh (534 clean Grenke games, no variations,
mainline only). Because they are clean, the raw .cbg bytes align trivially with
the mainline lc sequence. We derive lc per move via scidb's probe_encode960 and
walk the raw bytes with the proven model:

  count_0 = g(lc0)
  count_p = H0(count_{p-1}, lc_{p-1}, lc_p, p)
  raw_p   = InvLUT[lc_p] + count_p

Add-only harvest with conflict detection. Also cross-checks against the existing
table: keys already present must AGREE (else lc/alignment is wrong).

Usage: harvest_oracle.py [--apply]
"""
import json, re, subprocess, sys, chess, chess.pgn
from pathlib import Path
from collections import Counter

REPO = Path('/media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex')
CBH = '/tmp/oracle.cbh'
PGN = '/tmp/grenke_clean_20.pgn'
UPATH = REPO/'src/count_cipher_universal.json'
APPLY = '--apply' in sys.argv

src = (REPO/'src/db/cbh/cbh_decoder.cpp').read_text()
m = re.search(r'MoveNumberLookup\[256\] =\s*\{(.*?)\};', src, re.S)
LUT = [int(x, 16) for x in re.findall(r'0x[0-9a-f]{2}', m.group(1))]
INV = [0]*256
for i, v in enumerate(LUT):
    INV[v] = i

u = json.load(open(UPATH))
H0 = u['H0']; g = u['g_count0']

# --- raw move bytes per game from the oracle classic CBH ---
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
print(f"raw games loaded: {len(raws)}", file=sys.stderr)

# --- clean PGN moves ---
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
print(f"clean pgn games: {len(pgames)}", file=sys.stderr)

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

new_h = 0; conf_h = 0; dup_h = 0; new_g = 0
n_ok = 0; n_fail = 0
conf_examples = []
for idx in range(len(pgames)):
    if idx not in raws: continue
    fen, ucis = pgames[idx]
    raw = raws[idx]
    lcs = lcs_of(fen, ucis)
    if not lcs: n_fail += 1; continue

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
                    conf_h += 1
                    if len(conf_examples) < 10:
                        conf_examples.append((idx, key, known, cnt))
                    ok = False; break
            else:
                H0[key] = cnt; new_h += 1
        lc_prev = lc; count = cnt; pos += nb
    if ok: n_ok += 1
    else: n_fail += 1

print(f"games aligned ok: {n_ok}, failed/skipped: {n_fail}")
print(f"H0 NEW entries from oracle: {new_h}")
print(f"conflicts (disagree with existing table): {conf_h}")
for e in conf_examples:
    print("  conflict:", e)

if APPLY:
    u['H0_entries'] = len(H0)
    json.dump(u, open(UPATH,'w'), indent=1)
    print(f"APPLIED: H0 now {len(H0)} -> {UPATH}")
else:
    print("(dry run; pass --apply to write)")
