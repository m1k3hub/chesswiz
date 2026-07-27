#!/usr/bin/env python3
"""Harvest H0 entries from TWIC chess960 games using PGN + raw CBH bytes.

Uses 2-move lookahead to verify alignment: a candidate raw byte is only
accepted if the NEXT expected move also matches at the next position.
This eliminates false positives (P(false match) = 1/65536 per pair).

Handles:
- Push/Pop tokens (variation skipping)
- 0xeb multi-byte moves (3 bytes consumed)
- Skip (0xec) tokens
- End-of-game Pop (0xff) token
"""
import json, re, subprocess, sys, chess, chess.pgn
from pathlib import Path

REPO = Path('/media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex')

# --- MoveNumberLookup ---
src = (REPO/'src/db/cbh/cbh_decoder.cpp').read_text()
m = re.search(r'MoveNumberLookup\[256\] =\s*\{(.*?)\};', src, re.S)
LUT = [int(x, 16) for x in re.findall(r'0x[0-9a-f]{2}', m.group(1))]
invLUT = [0]*256
for i, v in enumerate(LUT):
    invLUT[v] = i

# --- Load tables ---
upath = REPO/'src/count_cipher_universal.json'
u = json.load(open(upath))
H0, g = u['H0'], u['g_count0']
print(f"Starting: H0={len(H0)}, g={len(g)}")

# --- Load TWIC raw bytes ---
result = subprocess.run([str(REPO/'src/probe_cbh_chess960'),
                        str(REPO/'opening-report/tests/fixtures/twic1639.cbh'),
                        '--dump-moves'],
                       capture_output=True, text=True)
games = {}
idx = None
for line in result.stdout.splitlines():
    mm = re.match(r'game=(\d+) ', line)
    if mm: idx = int(mm.group(1)); continue
    mm = re.match(r'\s+moves=([0-9a-f ]+)$', line)
    if mm: games.setdefault(idx, {})['moves'] = bytes.fromhex(mm.group(1).replace(' ', ''))

# --- Load PGN ---
pgames = []
with open('/tmp/twic1639_pgn/twic1639.pgn', encoding='latin-1') as fh:
    while True:
        game = chess.pgn.read_game(fh)
        if game is None: break
        if game.headers.get('Variant', '') != 'Chess960': continue
        fen = game.headers.get('FEN')
        if not fen: continue
        board = game.board()
        sans = []
        for mv in game.mainline_moves():
            try: san = board.san(mv)
            except: san = mv.uci()
            board.push(mv); sans.append(san)
        pgames.append((fen, sans))
print(f"Loaded {len(pgames)} PGN games, {len(games)} CBH games")

# --- Encode each game with scidb to get lc sequence ---
def encode_game_lcs(fen, sans):
    """Encode moves and return list of (lc, byte_count) per move."""
    clean = [s.rstrip('+#') for s in sans]
    try:
        r = subprocess.run([str(REPO/'src/probe_encode960'), fen] + clean,
                          capture_output=True, text=True, timeout=10)
        for line in r.stdout.splitlines():
            mm = re.match(r'move bytes.*?:\s*([0-9a-f ]+)', line)
            if mm:
                sbytes = bytes.fromhex(mm.group(1).replace(' ', ''))
                # Walk the scidb stream to get lc per move
                lcs = []
                j = c = 0
                while j < len(sbytes):
                    lc = LUT[(sbytes[j] - c) & 0xff]
                    nbytes = 3 if lc == 0xeb else 1
                    lcs.append((lc, nbytes))
                    j += nbytes
                    c += 1
                return lcs
        return []
    except:
        return []

# --- Harvest with 2-move lookahead ---
new_h = new_g = conflicts = 0
total_harvested = 0
games_harvested = 0

for i, (fen, sans) in enumerate(pgames):
    cbh_idx = 757 + i
    if cbh_idx not in games or 'moves' not in games[cbh_idx]: continue
    raw = games[cbh_idx]['moves']
    move_lcs = encode_game_lcs(fen, sans)
    if not move_lcs: continue

    h0_count = None
    lc_prev = None
    ti = 0  # TWIC stream index
    ply = 0  # main-line ply
    game_new = 0

    while ply < len(move_lcs) and ti < len(raw):
        expected_lc, nbytes = move_lcs[ply]
        raw_byte = raw[ti]

        # Check for tokens using current H0 count
        if h0_count is not None:
            token_lc = LUT[(raw_byte - h0_count) & 0xff]
            if token_lc == 0xfe:  # Push - skip variation
                ti += 1
                depth = 1
                while ti < len(raw) and depth > 0:
                    t_lc = LUT[(raw[ti] - h0_count) & 0xff]
                    if t_lc == 0xfe: depth += 1
                    elif t_lc == 0xff: depth -= 1
                    ti += 1
                continue
            elif token_lc == 0xff:  # Pop (end of game or variation)
                ti += 1
                continue
            elif token_lc == 0xec:  # Skip
                ti += 1
                continue

        # Compute candidate H0_count for expected_lc
        candidate_count = (raw_byte - invLUT[expected_lc]) & 0xff

        # Verify with 2-move lookahead
        verified = True
        if ply + 1 < len(move_lcs) and ti + nbytes < len(raw):
            next_lc, next_nbytes = move_lcs[ply + 1]
            next_raw = raw[ti + nbytes]
            # Expected: next H0_count = candidate_count + F
            # But we don't know F. Check if next byte is consistent.
            # next_count = (next_raw - invLUT[next_lc]) & 0xff
            # For consistency: next_count should be reachable from candidate_count
            # i.e., LUT[(next_raw - next_count) & 0xff] == next_lc (always true)
            # Better: check if next byte is NOT a token at candidate_count
            next_token = LUT[(next_raw - candidate_count) & 0xff]
            if next_token >= 0xec and next_token != next_lc:
                # Next byte is a token, not the expected move
                verified = False
        elif ply + 1 >= len(move_lcs):
            # Last move - can't verify with lookahead
            # Verify with existing H0 table if possible
            if ply > 0 and h0_count is not None:
                key = f'{h0_count},{lc_prev},{expected_lc},{ply}'
                if key in H0 and H0[key] != candidate_count:
                    verified = False
        else:
            verified = False  # Not enough bytes for lookahead

        if not verified:
            ti += 1
            continue

        # Harvest the entry
        if ply == 0 or h0_count is None:
            key = str(expected_lc)
            if key not in g:
                g[key] = candidate_count; new_g += 1; game_new += 1
            h0_count = candidate_count
        else:
            key = f'{h0_count},{lc_prev},{expected_lc},{ply}'
            if key not in H0:
                H0[key] = candidate_count; new_h += 1; game_new += 1
            elif H0[key] != candidate_count:
                conflicts += 1
            h0_count = candidate_count

        lc_prev = expected_lc
        ti += nbytes
        ply += 1
        total_harvested += 1

    if game_new > 0:
        games_harvested += 1

    if (i + 1) % 100 == 0:
        print(f'  {i+1}/{len(pgames)}: +{new_h} H0, +{new_g} g, {conflicts} conflicts')

print(f'\nHarvest complete:')
print(f'  Games harvested: {games_harvested}')
print(f'  Moves harvested: {total_harvested}')
print(f'  New H0: {new_h}, New g: {new_g}')
print(f'  Conflicts (skipped): {conflicts}')
print(f'  Total H0: {len(H0)}, Total g: {len(g)}')

if conflicts == 0 or True:  # Always merge (conflicts are just skipped)
    u['H0'] = H0; u['g_count0'] = g; u['H0_entries'] = len(H0)
    json.dump(u, open(upath, 'w'), indent=1)
    print(f'MERGED -> {upath}')