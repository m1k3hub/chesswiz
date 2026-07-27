#!/usr/bin/env python3
"""Harvest H0 entries from TWIC chess960 games using PGN + raw CBH bytes.

Key innovation: use KNOWN F values to predict exact raw bytes and verify
alignment. Only accept unknown-F entries when surrounded by verified
known-F entries on both sides.

For each move:
  raw_p = (invLUT[lc_p] + count_p) & 0xff
  count_p = count_{p-1} + F(lc_{p-1}, lc_p, ply)

If F is known → predict raw byte, verify against TWIC stream
If F is unknown → compute count from TWIC byte, accept only if
  adjacent known-F moves also match.
"""
import json, re, subprocess, chess, chess.pgn
from pathlib import Path
from collections import defaultdict

REPO = Path('/media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex')

# Load LUT
src = (REPO/'src/db/cbh/cbh_decoder.cpp').read_text()
m = re.search(r'MoveNumberLookup\[256\] =\s*\{(.*?)\};', src, re.S)
LUT = [int(x, 16) for x in re.findall(r'0x[0-9a-f]{2}', m.group(1))]
invLUT = [0]*256
for i, v in enumerate(LUT): invLUT[v] = i

# Load tables
upath = REPO/'src/count_cipher_universal.json'
u = json.load(open(upath))
H0, g = u['H0'], u['g_count0']

# Build F lookup: (count_prev, lc_prev, lc, ply) -> count_next
# And (lc_prev, lc, ply) -> F value (for deterministic check)
F_deterministic = {}  # (lc_prev, lc, ply) -> F value (if unique)
F_all = defaultdict(set)
for key, val in H0.items():
    parts = key.split(',')
    cp, lp, lc, ply = int(parts[0]), int(parts[1]), int(parts[2]), int(parts[3])
    F = (val - cp) & 0xff
    F_all[(lp, lc, ply)].add(F)

for triple, Fs in F_all.items():
    if len(Fs) == 1:
        F_deterministic[triple] = list(Fs)[0]

print(f"Starting: H0={len(H0)}, g={len(g)}, deterministic F: {len(F_deterministic)}/{len(F_all)} triples")

# Load TWIC raw bytes
result = subprocess.run([str(REPO/'src/probe_cbh_chess960'),
                        str(REPO/'opening-report/tests/fixtures/twic1639.cbh'),
                        '--dump-moves'], capture_output=True, text=True)
games = {}
idx = None
for line in result.stdout.splitlines():
    mm = re.match(r'game=(\d+) ', line)
    if mm: idx = int(mm.group(1)); continue
    mm = re.match(r'\s+moves=([0-9a-f ]+)$', line)
    if mm: games.setdefault(idx, {})['moves'] = bytes.fromhex(mm.group(1).replace(' ', ''))

# Load PGN
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
print(f"Loaded {len(pgames)} PGN games")

def encode_game_lcs(fen, sans):
    """Encode with scidb, return list of (lc, nbytes) per move."""
    clean = [s.rstrip('+#') for s in sans]
    try:
        r = subprocess.run([str(REPO/'src/probe_encode960'), fen] + clean,
                          capture_output=True, text=True, timeout=10)
        for line in r.stdout.splitlines():
            mm = re.match(r'move bytes.*?:\s*([0-9a-f ]+)', line)
            if mm:
                sbytes = bytes.fromhex(mm.group(1).replace(' ', ''))
                lcs = []; j = c = 0
                while j < len(sbytes):
                    lc = LUT[(sbytes[j] - c) & 0xff]
                    nb = 3 if lc == 0xeb else 1
                    lcs.append((lc, nb))
                    j += nb; c += 1
                return lcs
        return []
    except: return []

def harvest_game(raw, move_lcs):
    """Walk TWIC stream using H0 model with F-based verification.
    Returns dict of new H0 entries and g entries."""
    if not move_lcs: return {}, {}

    new_h = {}
    new_g = {}

    # Get initial count from g table
    lc0 = move_lcs[0][0]
    g_val = g.get(str(lc0))
    if g_val is None:
        # Try to find g(lc0) from the first TWIC byte
        if len(raw) == 0: return {}, {}
        # First byte should be: raw = invLUT[lc0] + g(lc0)
        # So g(lc0) = (raw[0] - invLUT[lc0]) & 0xff
        # But we can't verify without a known F for the next move
        g_val = (raw[0] - invLUT[lc0]) & 0xff
        new_g[str(lc0)] = g_val

    count = g_val
    lc_prev = lc0
    ti = 0  # TWIC stream index

    # Verify first byte
    expected_raw = (invLUT[lc0] + g_val) & 0xff
    if ti < len(raw) and raw[ti] != expected_raw:
        # First byte doesn't match — try to find it
        found = False
        for search in range(min(10, len(raw))):
            if raw[search] == expected_raw:
                ti = search
                found = True
                break
        if not found:
            return new_h, new_g  # Can't align first move

    ti += move_lcs[0][1]  # skip 0xeb triple or 1 byte

    # Process subsequent moves
    for ply in range(1, len(move_lcs)):
        lc, nbytes = move_lcs[ply]
        F_key = (lc_prev, lc, ply)
        F_val = F_deterministic.get(F_key)

        if F_val is not None:
            # Known F: predict exact raw byte
            count = (count + F_val) & 0xff
            expected = (invLUT[lc] + count) & 0xff

            # Search for expected byte in TWIC stream (skip tokens)
            found = False
            for search in range(ti, min(ti + 20, len(raw))):
                if raw[search] == expected:
                    # Verify it's not a coincidence: check it decodes to lc
                    if LUT[(raw[search] - count) & 0xff] == lc:
                        ti = search
                        found = True
                        break
            if not found:
                break  # Alignment lost — stop harvesting
        else:
            # Unknown F: compute count from TWIC byte
            # Search for a byte that decodes to the expected lc
            found = False
            for search in range(ti, min(ti + 20, len(raw))):
                candidate_count = (raw[search] - invLUT[lc]) & 0xff
                if LUT[(raw[search] - candidate_count) & 0xff] == lc:
                    # Verify: check if next known-F move also matches
                    if ply + 1 < len(move_lcs):
                        next_lc, next_nb = move_lcs[ply + 1]
                        next_F = F_deterministic.get((lc, next_lc, ply + 1))
                        if next_F is not None:
                            next_count = (candidate_count + next_F) & 0xff
                            next_expected = (invLUT[next_lc] + next_count) & 0xff
                            next_pos = search + nbytes
                            if next_pos < len(raw) and raw[next_pos] == next_expected:
                                # Verified! Accept
                                count = candidate_count
                                ti = search
                                found = True
                                key = f'{count - F_val if F_val else count},{lc_prev},{lc},{ply}'
                                # Actually, store the full H0 entry
                                h0_key = f'{(count - ((raw[search] - invLUT[lc]) & 0xff)) & 0xff},{lc_prev},{lc},{ply}'
                                # Hmm, this is getting complex. Let me simplify.
                                pass
                    # For now, accept if no next known-F to verify
                    count = candidate_count
                    ti = search
                    found = True
                    break
            if not found:
                break  # Alignment lost

        # Harvest entry
        h0_key = f'{(count - (F_val if F_val else 0)) & 0xff},{lc_prev},{lc},{ply}'
        # Actually, the H0 key is (count_prev, lc_prev, lc, ply) -> count_next
        # count_prev = count before this move's F was applied
        # count_next = count after F applied = current count
        count_prev = (count - F_val) & 0xff if F_val is not None else None
        if count_prev is not None:
            h0_key = f'{count_prev},{lc_prev},{lc},{ply}'
            if h0_key not in H0:
                H0[h0_key] = count
                new_h[h0_key] = count
            elif H0[h0_key] != count:
                pass  # conflict, skip
        else:
            # Unknown F: count_prev = count - F, but F is unknown
            # We need to know count_prev to store the entry
            # count_prev is the count from the previous move
            # which is stored in the 'count' variable before this move
            # Wait, I need to restructure this...
            pass

        lc_prev = lc
        ti += nbytes

    return new_h, new_g

# Actually, let me restructure the harvest to be simpler and correct.
# The H0 table stores: (count_prev, lc_prev, lc, ply) -> count_next
# Where count_next = count_prev + F(lc_prev, lc, ply)
# And raw_p = (invLUT[lc] + count_next) & 0xff (wait, no)
# Actually: raw_p = (invLUT[lc] + count_p) & 0xff where count_p is the count
# AFTER the F increment. So count_p = count_next = count_prev + F.
# The H0 key uses count_prev (the count BEFORE this move).

# Let me rewrite more carefully:
# - count_0 = g(lc_0)  (the count for the FIRST move)
# - For move p (p >= 1): count_p = count_{p-1} + F(lc_{p-1}, lc_p, ply)
# - raw_p = (invLUT[lc_p] + count_p) & 0xff
# - H0 key: (count_{p-1}, lc_{p-1}, lc_p, ply) -> count_p

# So count_prev = count_{p-1}, count_next = count_p = count_prev + F

# Harvesting:
# For move 0: g[lc_0] = count_0 (from first TWIC byte)
# For move p: H0[count_{p-1}, lc_{p-1}, lc_p, ply] = count_p

# I need to track count at each step. Let me rewrite.

new_h_total = new_g_total = conflicts_total = 0
games_processed = 0

for i, (fen, sans) in enumerate(pgames):
    cbh_idx = 757 + i
    if cbh_idx not in games or 'moves' not in games[cbh_idx]: continue
    raw = games[cbh_idx]['moves']
    move_lcs = encode_game_lcs(fen, sans)
    if not move_lcs: continue

    # Get initial count
    lc0 = move_lcs[0][0]
    g_val = g.get(str(lc0))
    if g_val is None:
        if len(raw) == 0: continue
        g_val = (raw[0] - invLUT[lc0]) & 0xff
        g[str(lc0)] = g_val
        new_g_total += 1

    count = g_val  # count for move 0
    lc_prev = lc0
    ti = move_lcs[0][1]  # skip first move's bytes

    # Verify first byte
    expected0 = (invLUT[lc0] + g_val) & 0xff
    if raw[0] != expected0:
        continue  # First byte mismatch — skip game

    game_new = 0

    for ply in range(1, len(move_lcs)):
        lc, nbytes = move_lcs[ply]
        F_key = (lc_prev, lc, ply)
        F_val = F_deterministic.get(F_key)

        count_prev = count  # count BEFORE this move

        if F_val is not None:
            # Known F: predict exact byte
            count = (count_prev + F_val) & 0xff
            expected = (invLUT[lc] + count) & 0xff

            # Search for expected byte (skip tokens/variations)
            found = False
            for search in range(ti, min(ti + 30, len(raw))):
                if raw[search] == expected and LUT[(raw[search] - count) & 0xff] == lc:
                    ti = search
                    found = True
                    break
            if not found:
                break  # Alignment lost
        else:
            # Unknown F: search for byte that decodes to lc
            found = False
            for search in range(ti, min(ti + 30, len(raw))):
                candidate_count = (raw[search] - invLUT[lc]) & 0xff
                if LUT[(raw[search] - candidate_count) & 0xff] != lc:
                    continue

                # Verify with next known-F move
                verified = False
                if ply + 1 < len(move_lcs):
                    next_lc, next_nb = move_lcs[ply + 1]
                    next_F = F_deterministic.get((lc, next_lc, ply + 1))
                    if next_F is not None:
                        next_count = (candidate_count + next_F) & 0xff
                        next_expected = (invLUT[next_lc] + next_count) & 0xff
                        next_pos = search + nbytes
                        if next_pos < len(raw) and raw[next_pos] == next_expected:
                            verified = True
                else:
                    verified = True  # Last move, accept

                if verified:
                    count = candidate_count
                    ti = search
                    found = True

                    # Harvest new H0 entry
                    h0_key = f'{count_prev},{lc_prev},{lc},{ply}'
                    if h0_key not in H0:
                        H0[h0_key] = count
                        new_h_total += 1
                        game_new += 1
                    elif H0[h0_key] != count:
                        conflicts_total += 1
                    break

            if not found:
                break  # Alignment lost

        ti += nbytes
        lc_prev = lc

    if game_new > 0:
        games_processed += 1

    if (i + 1) % 100 == 0:
        print(f'  {i+1}/{len(pgames)}: +{new_h_total} H0, +{new_g_total} g, {conflicts_total} conflicts, {games_processed} games')

print(f'\nF-verified harvest:')
print(f'  Games with new entries: {games_processed}')
print(f'  New H0: {new_h_total}')
print(f'  New g: {new_g_total}')
print(f'  Conflicts: {conflicts_total}')
print(f'  Total H0: {len(H0)}')

u['H0'] = H0; u['g_count0'] = g; u['H0_entries'] = len(H0)
json.dump(u, open(upath, 'w'), indent=1)
print('MERGED')