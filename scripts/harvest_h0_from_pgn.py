#!/usr/bin/env python3
"""Harvest H0 table entries from TWIC chess960 games by comparing
the raw CBH bytes with scidb-encoded (move_index) bytes.

For each move:
  scidb: raw_s = InvLUT[lc] + move_index
  TWIC:  raw_t = InvLUT[lc] + H0_count
  => H0_count = (raw_t - raw_s + move_index) & 0xff

Then: count_p = H0_count, and the H0 table entry is:
  key = "count_prev,lc_prev,lc,ply" -> count_next
  where count_next = H0_count (the count AFTER applying F)

For the first move: g[lc] = H0_count
For subsequent: H0[count_prev, lc_prev, lc, ply] = count_next
  where F = (count_next - count_prev) & 0xff
"""
import json, re, subprocess, sys, collections
from pathlib import Path

REPO = Path('/media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex')

# --- MoveNumberLookup from source -----------------------------------------
src = (REPO/'src/db/cbh/cbh_decoder.cpp').read_text()
m = re.search(r'MoveNumberLookup\[256\] =\s*\{(.*?)\};', src, re.S)
LUT = [int(x, 16) for x in re.findall(r'0x[0-9a-f]{2}', m.group(1))]
assert len(LUT) == 256
invLUT = [0]*256
for i, v in enumerate(LUT):
    invLUT[v] = i

# --- Load existing tables --------------------------------------------------
upath = REPO/'src/count_cipher_universal.json'
u = json.load(open(upath))
H0, g = u['H0'], u['g_count0']

# --- Load TWIC raw bytes ---------------------------------------------------
games = {}  # idx -> {'pos': bytes, 'moves': bytes}
for line in (REPO/'src/probe_cbh_chess960').__class__([
        subprocess.run([str(REPO/'src/probe_cbh_chess960'),
                       str(REPO/'opening-report/tests/fixtures/twic1639.cbh'),
                       '--dump-moves'],
                      capture_output=True, text=True).stdout]).read_text().splitlines() if False else []:
    pass

# Actually, dump moves properly
result = subprocess.run([str(REPO/'src/probe_cbh_chess960'),
                        str(REPO/'opening-report/tests/fixtures/twic1639.cbh'),
                        '--dump-moves'],
                       capture_output=True, text=True)
idx = None
for line in result.stdout.splitlines():
    mm = re.match(r'game=(\d+) ', line)
    if mm: idx = int(mm.group(1)); continue
    mm = re.match(r'\s+pos=([0-9a-f ]+)$', line)
    if mm: games.setdefault(idx, {})['pos'] = bytes.fromhex(mm.group(1).replace(' ', '')); continue
    mm = re.match(r'\s+moves=([0-9a-f ]+)$', line)
    if mm: games.setdefault(idx, {})['moves'] = bytes.fromhex(mm.group(1).replace(' ', ''))

games = {i: g for i, g in games.items() if 'moves' in g and 'pos' in g}
print(f'Loaded {len(games)} games with move data')

# --- Load PGN --------------------------------------------------------------
import chess, chess.pgn, io
pgn_path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('/tmp/chess960_all.pgn')
if not pgn_path.exists():
    print(f'PGN file not found: {pgn_path}')
    sys.exit(1)

pgames = []  # (game_idx_in_cbh, fen, sans)
with open(pgn_path, encoding='latin-1') as fh:
    while True:
        game = chess.pgn.read_game(fh)
        if game is None: break
        if game.headers.get('Variant', '') not in ('Chess960', 'chess960', 'CHESS960'): continue
        fen = game.headers.get('FEN')
        if not fen: continue
        board = game.board()
        sans = []
        for mv in game.mainline_moves():
            sans.append(board.san(mv)); board.push(mv)
        pgames.append((fen, sans))

print(f'Loaded {len(pgames)} chess960 PGN games')

# --- Encode each game with scidb (move_index) ------------------------------
def encode_game(fen, sans):
    """Encode moves with scidb's probe_encode960, return move bytes."""
    # Remove check/mate annotations
    clean_sans = [s.rstrip('+#') for s in sans]
    try:
        result = subprocess.run(
            [str(REPO/'src/probe_encode960'), fen] + clean_sans,
            capture_output=True, text=True, timeout=10)
        # Parse output: "move bytes (offset 32+): XX XX XX ..."
        for line in result.stdout.splitlines():
            mm = re.match(r'move bytes.*?:\s*([0-9a-f ]+)', line)
            if mm:
                return bytes.fromhex(mm.group(1).replace(' ', ''))
        return b''  # no move bytes found
    except Exception as e:
        return b''

# --- Harvest H0 entries ----------------------------------------------------
new_h = new_g = conflicts = 0
total_harvested = 0

for i, (fen, sans) in enumerate(pgames):
    # Find matching game in the CBH dump (by position bytes)
    # For now, use game index (PGN order should match CBH order)
    # The PGN games are in the same order as the CBH database
    # We need to map PGN game index to CBH game index
    # The PGN starts from game 758 (1-indexed) = game 757 (0-indexed)
    cbh_idx = 757 + i  # first chess960 game is at index 757

    if cbh_idx not in games:
        continue

    raw = games[cbh_idx]['moves']
    sbytes = encode_game(fen, sans)

    if len(sbytes) == 0:
        continue

    # Walk both streams in parallel
    # scidb: one byte per move (move_index encoding)
    # TWIC: one byte per move (H0 encoding), but with possible tokens

    h0_count = None
    lc_prev = None
    si = 0  # scidb stream index
    ti = 0  # TWIC stream index
    ply = 0

    while si < len(sbytes) and ti < len(raw):
        s_raw = sbytes[si]
        t_raw = raw[ti]
        mi_count = si  # move_index = position in scidb stream

        # Get lc from scidb encoding
        lc = LUT[(s_raw - mi_count) & 0xff]

        # Check for tokens
        if lc >= 0xec:
            # Token (Push/Pop/Skip) — both streams should have the same token
            # but with different counts. Skip alignment.
            si += 1
            ti += 1
            ply += 1
            # Tokens don't update the H0 chain (count stays the same)
            continue

        # Compute H0_count from difference
        diff = (t_raw - s_raw) & 0xff
        h0_computed = (diff + mi_count) & 0xff

        # Verify: LUT[(t_raw - h0_computed) & 0xff] should also give lc
        lc_check = LUT[(t_raw - h0_computed) & 0xff]
        if lc_check != lc:
            # Misaligned — skip this byte
            ti += 1
            continue

        # Harvest entry
        if ply == 0 or h0_count is None:
            # First move: g entry
            key = str(lc)
            if key not in g:
                g[key] = h0_computed
                new_g += 1
            elif g[key] != h0_computed:
                conflicts += 1
            h0_count = h0_computed
        else:
            # H0 entry
            key = f'{h0_count},{lc_prev},{lc},{ply}'
            if key not in H0:
                H0[key] = h0_computed
                new_h += 1
            elif H0[key] != h0_computed:
                conflicts += 1
            h0_count = h0_computed

        lc_prev = lc
        si += 1
        ti += 1
        ply += 1
        total_harvested += 1

    if (i + 1) % 50 == 0:
        print(f'  Processed {i+1}/{len(pgames)} games, +{new_h} H0, +{new_g} g, {conflicts} conflicts')

print(f'\nHarvest complete:')
print(f'  Games processed: {len(pgames)}')
print(f'  Moves harvested: {total_harvested}')
print(f'  New H0 entries: {new_h}')
print(f'  New g entries: {new_g}')
print(f'  Conflicts: {conflicts}')
print(f'  Total H0 entries: {len(H0)}')
print(f'  Total g entries: {len(g)}')

if conflicts == 0:
    u['H0'] = H0
    u['g_count0'] = g
    u['H0_entries'] = len(H0)
    json.dump(u, open(upath, 'w'), indent=1)
    print(f'MERGED -> {upath}')
else:
    print(f'NOT MERGED ({conflicts} conflicts)')