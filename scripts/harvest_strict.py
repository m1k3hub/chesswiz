#!/usr/bin/env python3
"""STRICT CBV-aligned H0 harvest.

Only harvest games whose ENTIRE derived count chain is verified against the
existing (proven 440K) table: g-match at ply 0, and at every ply the derived
count must either (a) equal an existing H0 entry, or (b) be bracketed by
verified neighbors. This excludes games with variations/drift entirely.

Harvest semantic: for a move at (countPrev,lcPrev,lc,ply), if the key is
absent, write H0[key] = countNext derived from the NEXT byte's verified count.
"""
import json, re, subprocess, chess, chess.pgn
from pathlib import Path
from collections import defaultdict

REPO = Path('/media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex')

src = (REPO/'src/db/cbh/cbh_decoder.cpp').read_text()
m = re.search(r'MoveNumberLookup\[256\] =\s*\{(.*?)\};', src, re.S)
LUT = [int(x, 16) for x in re.findall(r'0x[0-9a-f]{2}', m.group(1))]
INV = [0]*256
for i, v in enumerate(LUT): INV[v] = i

upath = REPO/'src/count_cipher_universal.json'
u = json.load(open(upath))
H0 = u['H0']; g = u['g_count0']
h0_before = len(H0); g_before = len(g)

# --- raw bytes ---
res = subprocess.run([str(REPO/'src/probe_cbh_chess960'),
                      str(REPO/'opening-report/tests/fixtures/twic1639.cbh'),
                      '--dump-moves'], capture_output=True, text=True)
raws = {}
cur = None
for line in res.stdout.splitlines():
    mm = re.match(r'game=(\d+) ', line)
    if mm: cur = int(mm.group(1)); continue
    mm = re.match(r'\s+moves=([0-9a-f ]+)$', line)
    if mm and cur is not None:
        raws[cur] = bytes.fromhex(mm.group(1).replace(' ',''))

# --- CBV headers ---
cbv = {}
for line in open('/tmp/cbv_headers.tsv'):
    if line.startswith('database='): continue
    p = line.strip().split('\t')
    if len(p) < 7: continue
    cbv[int(p[0])] = (p[1].split(',')[0].strip(), p[2].split(',')[0].strip(), p[6])

# --- PGN ---
pg = []
with open(REPO/'opening-report/tests/fixtures/grenke_freestyle_2026.pgn', encoding='utf-8') as fh:
    while True:
        gm = chess.pgn.read_game(fh)
        if gm is None: break
        fen = gm.headers.get('FEN','')
        if not fen: continue
        b = chess.Board(fen, chess960=True); ucis = []
        for mv in gm.mainline_moves():
            ucis.append(mv.uci()); b.push(mv)
        pg.append((gm.headers.get('White','').split(',')[0].strip(),
                   gm.headers.get('Black','').split(',')[0].strip(),
                   gm.headers.get('Round',''), fen, ucis))

def lcs_of(fen, ucis):
    try:
        b = chess.Board(fen, chess960=True); sans = []
        for u in ucis:
            mv = chess.Move.from_uci(u); sans.append(b.san(mv)); b.push(mv)
        r = subprocess.run([str(REPO/'src/probe_encode960'), fen] +
                           [s.rstrip('+#') for s in sans],
                           capture_output=True, text=True, timeout=10)
        for line in r.stdout.splitlines():
            mm = re.search(r'move bytes.*?:\s*([0-9a-f ]+)', line)
            if mm:
                sb = bytes.fromhex(mm.group(1).replace(' ',''))
                out = []; j = c = 0
                while j < len(sb):
                    lc = LUT[(sb[j]-c) & 0xff]; nb = 3 if lc == 0xeb else 1
                    out.append((lc, nb)); j += nb; c += 1
                return out
        return []
    except Exception:
        return []

new_h = 0; conf_h = 0; dup_h = 0; new_g = 0; ok = 0; bad = 0
for w,b,r,fen,ucis in pg:
    idx = next((i for i,(cw,cb,cr) in cbv.items() if (w,b,r)==(cw,cb,cr)), None)
    if idx is None: continue
    raw = raws.get(idx)
    if raw is None: continue
    lcs = lcs_of(fen, ucis)
    if not lcs: continue

    # --- strict verified walk ---
    # returns list of (countPrev, lcPrev, lc, ply, countNext) ONLY for unverified
    # gaps that are enclosed by verified plies, or None if any drift found.
    chain = []   # (ply, lc, count, verified:bool)
    count = None; lc_prev = None; pos = 0
    drift = False
    for ply, (lc, nb) in enumerate(lcs):
        if pos >= len(raw): drift = True; break
        cnt = (raw[pos] - INV[lc]) & 0xff
        if ply == 0:
            if str(lc) in g:
                if g[str(lc)] != cnt: drift = True; break
                chain.append((ply, lc, cnt, True))
            else:
                # no seed known: can't verify first move -> skip game
                drift = True; break
        else:
            key = f"{count},{lc_prev},{lc},{ply}"
            hv = H0.get(key)
            verified = (hv is not None and hv == cnt)
            if hv is not None and hv != cnt:
                drift = True; break   # explicit disagreement -> misalign
            chain.append((ply, lc, cnt, verified))
            if not verified:
                # gap: only harvestable if next ply verifies
                pass
        lc_prev = lc; count = cnt; pos += nb
    if drift:
        bad += 1; continue

    # harvest gaps bracketed by verified plies; skip if trailing unverified tail
    new_entries = []
    ok_flag = True
    for i, (ply, lc, cnt, verified) in enumerate(chain):
        if verified: continue
        # find the NEXT verified ply after i
        j = i + 1
        while j < len(chain) and not chain[j][3]:
            j += 1
        if j >= len(chain):
            ok_flag = False; break   # unverified tail -> skip this game entirely
        # write H0[chain[i] as next-transition]: key=(countPrev,lcPrev,lc,ply)
        # countPrev = chain[i-1].count
        if i == 0: ok_flag = False; break   # ply0 gap not allowed (already checked)
        cp = chain[i-1][2]; lp = chain[i-1][1]; lc1 = chain[i][1]; ply1 = chain[i][0]
        key = f"{cp},{lp},{lc1},{ply1}"
        if key not in H0:
            new_entries.append((key, chain[i][2]))
        elif H0[key] != chain[i][2]:
            ok_flag = False; break
    if not ok_flag:
        bad += 1; continue

    ok += 1
    for key, val in new_entries:
        H0[key] = val; new_h += 1
    # g-seed
    if chain and not chain[0][3] and str(chain[0][1]) not in g:
        g[str(chain[0][1])] = chain[0][2]; new_g += 1

print(f"games fully-verified & harvested: {ok}, skipped (drift/unverifiable): {bad}")
print(f"H0: {h0_before} -> {len(H0)} (+{new_h})")
print(f"g : {g_before} -> {len(g)} (+{new_g})")

u['H0_entries'] = len(H0)
u['source'] = u['source'].rstrip() + f" +strict-cbv-aligned harvest {new_h} entries 2026-08-05 (verified-only)"
json.dump(u, open(upath,'w'), indent=1)
print(f"SAVED {upath}")
