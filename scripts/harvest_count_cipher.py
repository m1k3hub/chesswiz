#!/usr/bin/env python3
"""Harvest (count,lc_prev,lc)->count H0 samples from an aligned CBV+PGN pair.

Pipeline: probe_cbh_chess960 --dump-moves (raw cbg bytes) + list_cbv_headers
(names) + PGN (python-chess) + probe_encode_many (scidb encoding of the same
moves, count=index) -> derive ChessBase counts, harvest H0/g, iterative
majority-clean, merge into count_cipher_universal.json.
"""
import json, re, subprocess, sys, collections
from pathlib import Path

REPO = Path('/media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex')
S = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('.')
TAG = sys.argv[2] if len(sys.argv) > 2 else 'twic1654'

# --- MoveNumberLookup from source -----------------------------------------
src = (REPO/'src/db/cbh/cbh_decoder.cpp').read_text()
m = re.search(r'MoveNumberLookup\[256\] =\s*\{(.*?)\};', src, re.S)
LUT = [int(x, 16) for x in re.findall(r'0x[0-9a-f]{2}', m.group(1))]
assert len(LUT) == 256

# --- cbg move dump ---------------------------------------------------------
games = {}  # idx -> {'pos': bytes36, 'moves': bytes}
idx = None
for line in (S/f'{TAG}_moves.txt').read_text().splitlines():
    mm = re.match(r'game=(\d+) ', line)
    if mm: idx = int(mm.group(1)); continue
    mm = re.match(r'\s+pos=([0-9a-f ]+)$', line)
    if mm: games.setdefault(idx, {})['pos'] = bytes.fromhex(mm.group(1).replace(' ', '')); continue
    mm = re.match(r'\s+moves=([0-9a-f ]+)$', line)
    if mm: games.setdefault(idx, {})['moves'] = bytes.fromhex(mm.group(1).replace(' ', ''))
games = {i: g for i, g in games.items() if 'moves' in g and 'pos' in g}
print(f'cbg: {len(games)} chess960 games dumped')

# --- headers ---------------------------------------------------------------
hdr = {}  # idx -> (white, black, round)
for line in (S/f'{TAG}_headers.txt').read_text().splitlines():
    f = line.split('\t')
    if len(f) >= 7 and f[0].isdigit():
        hdr[int(f[0])] = (f[1].strip(), f[2].strip(), f[6].strip())

# --- PGN -------------------------------------------------------------------
import chess, chess.pgn, io
pgn_path = next(S.glob(f'{TAG}*.pgn'))
pgames = []  # (white, black, round, fen, [san])
with open(pgn_path, encoding='latin-1') as fh:
    while True:
        g = chess.pgn.read_game(fh)
        if g is None: break
        if g.headers.get('Variant', '') != 'Chess960': continue
        fen = g.headers.get('FEN')
        if not fen: continue
        board = g.board()
        sans = []
        for mv in g.mainline_moves():
            sans.append(board.san(mv)); board.push(mv)
        pgames.append((g.headers.get('White','').strip(), g.headers.get('Black','').strip(),
                       g.headers.get('Round','').strip(), fen, sans))
print(f'pgn: {len(pgames)} chess960 games')

# --- align by (white, black, round), whitespace-normalized ------------------
def norm(s): return re.sub(r'\s+', '', s).lower()
by_key = {}
for i in games:
    if i in hdr:
        w, b, r = hdr[i]
        by_key.setdefault((norm(w), norm(b), r), []).append(i)
pairs = []
for w, b, r, fen, sans in pgames:
    ids = by_key.get((norm(w), norm(b), r), [])
    if len(ids) == 1:
        pairs.append((ids[0], fen, sans))
print(f'aligned by exact (white,black,round): {len(pairs)}')

# --- scidb encoding of PGN moves -------------------------------------------
inp = '\n'.join(f'{fen}\t{" ".join(sans)}' for _, fen, sans in pairs) + '\n'
out = subprocess.run([str(REPO/'src/probe_encode_many')], input=inp,
                     capture_output=True, text=True).stdout.splitlines()
assert len(out) == len(pairs), (len(out), len(pairs))

def walk(stream):
    """Yield (byte_offset, scidb_count) per move given scidb semantics."""
    j = c = 0
    res = []
    while j < len(stream):
        lc = LUT[(stream[j] - c) & 0xff]
        res.append((j, c, lc))
        j += 3 if lc == 0xeb else 1
        c += 1
    return res

# --- derive counts, harvest per game ---------------------------------------
game_samples = []  # (game_id, seed(lc0,count0), [ (key,(...)->count) ])
skipped_pos = skipped_empty = 0
for (gid, fen, sans), line in zip(pairs, out):
    mm = re.match(r'POS=([0-9a-f]+) \| ([0-9a-f ]*)$', line.strip())
    if not mm: skipped_empty += 1; continue
    pos28 = bytes.fromhex(mm.group(1))
    sbytes = bytes.fromhex(mm.group(2).replace(' ', ''))
    if len(sbytes) == 0: skipped_empty += 1; continue
    raw = games[gid]['moves']
    # byte 0 of the on-disk block carries a flag (0x01) absent from the
    # probe's rendering; compare bytes 1..27
    if games[gid]['pos'][1:28] != pos28[1:28]:
        skipped_pos += 1; continue
    smoves = walk(sbytes)
    # cbv stream must be at least as long as the scidb-parsed prefix
    n = len(smoves)
    if len(raw) < (smoves[-1][0] + (3 if smoves[-1][2] == 0xeb else 1)):
        n = 0
        for k, (off, c, lc) in enumerate(smoves):
            if off + (3 if lc == 0xeb else 1) <= len(raw): n = k + 1
    if n < 2: skipped_empty += 1; continue
    counts, lcs = [], []
    for off, c, lc in smoves[:n]:
        counts.append((raw[off] - sbytes[off] + c) & 0xff)
        lcs.append(lc)
    samples = [((counts[p-1], lcs[p-1], lcs[p]), counts[p]) for p in range(1, n)]
    game_samples.append((gid, (lcs[0], counts[0]), samples))
print(f'harvested {len(game_samples)} games ({skipped_pos} pos-mismatch, {skipped_empty} empty/short)')

# --- divergence trimming ----------------------------------------------------
# A misaligned tail (cbv stream contains variations/other moves) yields
# internally-unique garbage triples that majority voting cannot catch.
# Trim each game at its first conflict with the trusted table (existing
# H0 from the previous fixture), then iterate sample-level majority
# trimming among the games themselves until stable.
upath = REPO/'src/count_cipher_universal.json'
u = json.load(open(upath))
H0, g = u['H0'], u['g_count0']
trusted = {tuple(int(x) for x in k.split(',')): v for k, v in H0.items()}

trimmed = []  # [gid, seed, samples-prefix, orig-len]
for gid, seed, samples in game_samples:
    cut = len(samples)
    for p, (k, v) in enumerate(samples):
        if k in trusted and trusted[k] != v:
            cut = p; break
    trimmed.append([gid, seed, samples[:cut], len(samples)])

while True:
    votes = collections.defaultdict(collections.Counter)
    for gid, seed, samples, orig in trimmed:
        for k, v in samples: votes[k][v] += 1
    majority = {k: c.most_common(1)[0] for k, c in votes.items()}
    changed = False
    for entry in trimmed:
        gid, seed, samples, orig = entry
        for p, (k, v) in enumerate(samples):
            mv, mc = majority[k]
            if mv != v and mc >= 2:
                # outvoted by at least two agreeing games: this tail diverged
                entry[2] = samples[:p]; changed = True; break
            if len(votes[k]) > 1 and votes[k][v] == 1 and mc == 1:
                # 1-vs-1 disagreement: cannot attribute the divergence —
                # conservatively trim every participant at the contested key
                entry[2] = samples[:p]; changed = True; break
    if not changed: break

full = sum(1 for _, _, s, o in trimmed if len(s) == o)
frac = sum(1 for _, _, s, o in trimmed if 0 < len(s) < o)
empty = sum(1 for _, _, s, o in trimmed if len(s) == 0 and o > 0)
tot = sum(len(s) for _, _, s, _ in trimmed)
print(f'trimming: {full} full games, {frac} trimmed, {empty} emptied; {tot} samples kept')
game_samples = [(gid, seed, samples) for gid, seed, samples, _ in trimmed]
active = {gid for gid, _, s in game_samples if s}

# --- merge into universal json ----------------------------------------------
new_h = conflicts_h = new_g = conflicts_g = 0
conflict_detail = []
for gid, (lc0, c0), samples in game_samples:
    if gid not in active: continue
    kg = str(lc0)
    if kg in g:
        if g[kg] != c0:
            conflicts_g += 1; conflict_detail.append(('g', kg, g[kg], c0, gid))
    else:
        g[kg] = c0; new_g += 1
    for (cp, lp, lc), cn in samples:
        k = f'{cp},{lp},{lc}'
        if k in H0:
            if H0[k] != cn:
                conflicts_h += 1; conflict_detail.append(('H', k, H0[k], cn, gid))
        else:
            H0[k] = cn; new_h += 1
print(f'H0: +{new_h} new entries (now {len(H0)}), {conflicts_h} conflicts with existing')
print(f'g : +{new_g} new entries (now {len(g)}), {conflicts_g} conflicts with existing')
for c in conflict_detail[:10]: print('  CONFLICT', c)

if conflicts_h == 0 and conflicts_g == 0:
    u['H0_entries'] = len(H0)
    u.setdefault('sources', []).append(
        {'fixture': TAG, 'clean_games': len(active), 'new_H0': new_h, 'new_g': new_g})
    json.dump(u, open(upath, 'w'), indent=1)
    print('MERGED ->', upath)
else:
    print('NOT MERGED (conflicts) — investigate before writing')
