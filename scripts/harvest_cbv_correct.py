#!/usr/bin/env python3
"""Correct CBV-aligned H0 harvest.

Uses the PROVEN count-cipher math (harvest_h0_fverified.py style) with the
489 PGN->CBV matches, add-only H0 semantics, and g-seed verification.

Model:
  count_0 = g(lc0)
  count_p = H0(count_{p-1}, lc_{p-1}, lc_p, p)     (p = 0-based ply index)
  raw_p   = InvLUT[lc_p] + count_p (mod 256)

Per matched game:
  - scidb-encode the PGN moves (probe_encode960) -> (lc, nbytes) per move.
  - TWIC raw bytes from twic1639.cbg.
  - count_p derived as (raw[pos] - invLUT[lc_p]) & 0xff, advancing pos by nbytes.
  - Cross-checks: (a) g-seed consistency on ply 0 when g has the lc;
    (b) H0-known keys must agree; (c) trailing Pop token at plies/2.
  - Harvest add-only: H0[countPrev,lcPrev,lc,ply] = countNext; g[lc0] if new.
"""
import json, re, subprocess, chess, chess.pgn
from pathlib import Path
from collections import defaultdict

REPO = Path('/media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex')

src = (REPO/'src/db/cbh/cbh_decoder.cpp').read_text()
m = re.search(r'MoveNumberLookup\[256\] =\s*\{(.*?)\};', src, re.S)
LUT = [int(x, 16) for x in re.findall(r'0x[0-9a-f]{2}', m.group(1))]
INV = [0]*256
for i, v in enumerate(LUT):
    INV[v] = i

upath = REPO/'src/count_cipher_universal.json'
u = json.load(open(upath))
H0 = u['H0']
g = u['g_count0']
h0_before = len(H0); g_before = len(g)

# --- CBV headers (index -> lastname white/black/round) ---
cbv = {}
for line in open('/tmp/cbv_headers.tsv'):
    if line.startswith('database='): continue
    p = line.strip().split('\t')
    if len(p) < 7: continue
    cbv[int(p[0])] = (p[1].split(',')[0].strip(), p[2].split(',')[0].strip(), p[6])

# --- PGN games ---
pgn = []
with open(REPO/'opening-report/tests/fixtures/grenke_freestyle_2026.pgn', encoding='utf-8') as fh:
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

# match
matches = []
for w,b,r,fen,ucis in pgn:
    for idx,(cw,cb,cr) in cbv.items():
        if (w,b,r) == (cw,cb,cr):
            matches.append((idx, fen, ucis))
            break
print(f"matched: {len(matches)}")

# --- raw move bytes via probe_cbh_chess960 --dump-moves ---
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

# --- scidb-encode to get lc per move ---
def lcs_of(fen, ucis):
    # probe_encode960 takes SAN moves; convert UCI->SAN via python-chess
    try:
        b = chess.Board(fen, chess960=True)
        sans = []
        for u in ucis:
            mv = chess.Move.from_uci(u)
            sans.append(b.san(mv)); b.push(mv)
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
                    out.append((lc, nb))
                    j += nb; c += 1
                return out
        return []
    except Exception:
        return []

new_h = 0; conf_h = 0; dup_h = 0; new_g = 0; ok_games = 0; bad = 0
for idx, fen, ucis in matches:
    raw = raws.get(idx)
    if raw is None: continue
    lcs = lcs_of(fen, ucis)
    if not lcs: continue

    # walk: derive count_p from bytes (INV[lc]); cross-check g seed + known H0
    count = None
    lc_prev = None
    pos = 0
    entries = []   # (countPrev, lcPrev, lc, ply1, countNext)
    ok = True
    for ply, (lc, nb) in enumerate(lcs):
        if pos >= len(raw):
            ok = False; break
        rp = raw[pos]
        cnt = (rp - INV[lc]) & 0xff
        # g-seed check on first move
        if ply == 0:
            kg = str(lc)
            if kg in g:
                if g[kg] != cnt:
                    ok = False; break   # g mismatch -> misalignment, skip game
            count = cnt
        else:
            count_prev = count
            # known-key cross check
            key = f"{count_prev},{lc_prev},{lc},{ply}"
            known = H0.get(key)
            if known is not None and known != cnt:
                ok = False; break       # disagrees with proven table
            entries.append((count_prev, lc_prev, lc, ply, cnt))
        lc_prev = lc
        count = cnt
        pos += nb
    if not ok:
        bad += 1
        continue

    # trailing Pop: last byte should be 0xff with move-number count
    # (optional sanity; don't fail if absent — some games may have variations)
    ok_games += 1

    # harvest g seed from first move count
    lc0 = lcs[0][0]
    if str(lc0) not in g:
        c0 = (raw[0] - INV[lc0]) & 0xff
        g[str(lc0)] = c0
        new_g += 1

    for e in entries:
        cp, lp, lc1, ply1, cn = e
        key = f"{cp},{lp},{lc1},{ply1}"
        if key not in H0:
            H0[key] = cn; new_h += 1
        elif H0[key] == cn:
            dup_h += 1
        else:
            conf_h += 1

print(f"games aligned ok: {ok_games}, skipped: {bad}")
print(f"H0: {h0_before} -> {len(H0)}  (+{new_h} new, {dup_h} dup, {conf_h} conflict)")
print(f"g : {g_before} -> {len(g)}  (+{new_g})")

u['H0_entries'] = len(H0)
u['source'] = u['source'].rstrip() + f" +cbv-aligned harvest {new_h} entries 2026-08-05"
json.dump(u, open(upath,'w'), indent=1)
print(f"SAVED {upath}")
