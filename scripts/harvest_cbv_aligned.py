#!/usr/bin/env python3
"""Match Grenke Freestyle 2026 PGN to CBV, harvest H0 from aligned games."""
import json, re, subprocess, chess, chess.pgn, struct
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
H0_orig = len(u['H0'])
g_orig = len(u['g_count0'])
print(f"Starting: H0={H0_orig}, g={g_orig}")

# Load CBV headers
cbv_games = {}
with open('/tmp/cbv_headers.tsv') as f:
    for line in f:
        if line.startswith('database='): continue
        parts = line.strip().split('\t')
        if len(parts) < 7: continue
        idx = int(parts[0])
        white = parts[1].split(',')[0].strip()  # Lastname
        black = parts[2].split(',')[0].strip()
        round_val = parts[6]
        cbv_games[idx] = {'white': white, 'black': black, 'round': round_val}

print(f"Loaded {len(cbv_games)} CBV game headers")

# Load PGN games
pgn_games = []
with open(REPO/'opening-report/tests/fixtures/grenke_freestyle_2026.pgn', encoding='utf-8') as fh:
    while True:
        game = chess.pgn.read_game(fh)
        if game is None: break
        white = game.headers.get('White', '').split(',')[0].strip()
        black = game.headers.get('Black', '').split(',')[0].strip()
        round_val = game.headers.get('Round', '')
        fen = game.headers.get('FEN')
        if not fen: continue
        board = game.board()
        moves_uci = []
        for mv in game.mainline_moves():
            moves_uci.append(mv.uci())
            board.push(mv)
        pgn_games.append({
            'white': white, 'black': black, 'round': round_val,
            'fen': fen, 'uci': moves_uci
        })

print(f"Loaded {len(pgn_games)} PGN games")

# Match PGN to CBV by (white, black, round)
matches = []
for pg in pgn_games:
    for cbv_idx, cg in cbv_games.items():
        if (pg['white'] == cg['white'] and
            pg['black'] == cg['black'] and
            pg['round'] == cg['round']):
            matches.append((cbv_idx, pg))
            break

print(f"Matched {len(matches)} PGN→CBV games")

# Read raw move bytes from base CBH
def read_cbg_moves(game_idx):
    """Read raw move bytes from twic1639.cbg for game game_idx."""
    result = subprocess.run([
        str(REPO/'src/probe_cbh_chess960'),
        str(REPO/'opening-report/tests/fixtures/twic1639.cbh'),
        '--dump-moves'
    ], capture_output=True, text=True)
    
    in_game = False
    for line in result.stdout.splitlines():
        mm = re.match(r'game=(\d+) ', line)
        if mm and int(mm.group(1)) == game_idx:
            in_game = True
            continue
        if in_game:
            mm = re.match(r'\s+moves=([0-9a-f ]+)$', line)
            if mm:
                return bytes.fromhex(mm.group(1).replace(' ', ''))
            if re.match(r'game=', line):  # Next game started
                break
    return None

# Encode PGN with scidb to get lc values
def encode_game_lcs(fen, uci_moves):
    """Encode with probe_encode960, extract lc values from raw bytes."""
    try:
        cmd = [str(REPO/'src/probe_encode960'), fen] + uci_moves
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        for line in r.stdout.splitlines():
            mm = re.search(r'move bytes.*?:\s*([0-9a-f ]+)', line)
            if mm:
                sbytes = bytes.fromhex(mm.group(1).replace(' ', ''))
                # Extract lc from scidb-encoded bytes
                # Scidb format: raw[i] = (LUT[lc] + move_index) & 0xff
                # So: lc = invLUT[(raw[i] - move_index) & 0xff]
                lcs = []
                move_idx = 0
                j = 0
                while j < len(sbytes):
                    lc = invLUT[(sbytes[j] - move_idx) & 0xff]
                    lcs.append(lc)
                    nb = 3 if lc == 0xeb else 1
                    j += nb
                    move_idx += 1
                return lcs
        return []
    except Exception as e:
        print(f"  Encode error: {e}")
        return []

# Harvest H0 from matched games
harvested = 0
H0 = u['H0']
g = u['g_count0']

for cbv_idx, pg in matches:  # All matched games
    raw = read_cbg_moves(cbv_idx)
    if raw is None:
        print(f"Game {cbv_idx}: no raw bytes")
        continue
    
    lcs = encode_game_lcs(pg['fen'], pg['uci'])
    if not lcs:
        print(f"Game {cbv_idx}: encoding failed")
        continue
    
    if len(raw) < len(lcs):
        print(f"Game {cbv_idx}: raw={len(raw)} < lcs={len(lcs)}, skip")
        continue
    
    # Harvest using the verified method from harvest_h0_fverified.py
    count = g
    lc_prev = 0
    for ply, lc in enumerate(lcs):
        ply1 = ply + 1
        raw_byte = raw[ply]
        
        # H0_count = (raw_byte - LUT_inv[lc] + ply) & 0xff
        h0_count = (raw_byte - invLUT[lc] + ply) & 0xff
        
        # Add H0 entry
        key = f"{count},{lc_prev},{lc},{ply1}"
        if key not in H0:
            harvested += 1
        H0[key] = h0_count
        
        # Update count for next ply
        count = h0_count
        lc_prev = lc
    
    print(f"Game {cbv_idx}: harvested from {len(lcs)} moves")

print(f"\nHarvested {harvested} new H0 entries")
print(f"H0: {H0_orig} → {len(H0)} (+{len(H0)-H0_orig})")

# Save updated tables
u['H0'] = H0
json.dump(u, open(upath, 'w'), indent=2, sort_keys=True)
print(f"Saved to {upath}")
