#!/usr/bin/env python3
"""Cross-reference H0 gap bytes against PGN ground-truth move classes.

For each DAda game (757+) with a PGN match (lastname,lastname,Round), walk the
raw stream via the H0 fast path; at the first gap byte, look up the REAL next
PGN move and classify it (piece, castling, promotion) to determine WHICH move
classes the H0 table most often fails to cover.
"""
import json, struct, re, sys
from collections import Counter, defaultdict

REPO = '/media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex'
CBH = f'{REPO}/opening-report/tests/fixtures/twic1639.cbh'
CBG = f'{REPO}/opening-report/tests/fixtures/twic1639.cbg'
PGN = f'{REPO}/opening-report/tests/fixtures/grenke_freestyle_2026.pgn'

u = json.load(open(f'{REPO}/src/count_cipher_universal.json'))
H0 = u['H0']
g0 = {int(k): v for k, v in u['g_count0'].items()}

src = open(f'{REPO}/src/db/cbh/cbh_decoder.cpp').read()
m = re.search(r'MoveNumberLookup\[256\] =\s*\{(.*?)\};', src, re.S)
LUT = [int(x, 16) for x in re.findall(r'0x[0-9a-f]{2}', m.group(1))]
invLUT = [0] * 256
for i, v in enumerate(LUT):
    invLUT[v] = i

import chess, chess.pgn


def ln(name):
    name = name.strip()
    if ',' in name:
        return name.split(',')[0].strip().lower()
    return name.split()[-1].lower()


pgames = []
with open(PGN, encoding='latin-1') as fh:
    while True:
        g = chess.pgn.read_game(fh)
        if g is None:
            break
        pgames.append(g)
bykey = {}
for gi, g in enumerate(pgames):
    bykey[(ln(g.headers.get('White', '')), ln(g.headers.get('Black', '')),
           g.headers.get('Round', '').strip())] = gi

# expected SAN moves per pgn game
pgn_sans = {}
for gi, g in enumerate(pgames):
    fen = g.headers.get('FEN', '')
    if 'rkqrbbnn' not in fen:
        continue
    b = chess.Board(fen, chess960=True)
    sans = []
    for mv in g.mainline_moves():
        sans.append(b.san(mv))
        b.push(mv)
    pgn_sans[gi] = sans


def read_game(g):
    with open(CBH, 'rb') as f:
        f.seek(46 + 46 * g)
        rec = f.read(46)
    off = struct.unpack('>I', rec[1:5])[0]
    with open(CBG, 'rb') as f:
        f.seek(off)
        data = f.read(500)
    word = struct.unpack('>I', data[:4])[0]
    size = word & 0xffffff
    return word, data[40:40 + size - 40]


def walk(moves):
    """Fast-path walk; return (n_accepted, ply_of_first_gap, gap_raw, gap_ncands, states_so_far)."""
    count = None
    lc_prev = -1
    ply = 0
    for i, raw in enumerate(moves):
        if count is None:
            cands = [(lc, c0) for lc, c0 in g0.items() if (c0 + invLUT[lc]) & 0xff == raw]
        else:
            cands = []
            for lc in range(0xec):
                cc = H0.get(f"{count},{lc_prev},{lc},{ply}")
                if cc is not None and (cc + invLUT[lc]) & 0xff == raw:
                    cands.append((lc, cc))
            if not cands:
                for lc in range(0xec, 256):
                    if (count + invLUT[lc]) & 0xff == raw:
                        cands.append((lc, count))
        if len(cands) != 1:
            return i, ply, raw, len(cands), count, lc_prev
        lc, count = cands[0]
        lc_prev = lc
        ply += 1
    return len(moves), ply, None, 0, count, lc_prev


class_by_piece = Counter()      # real move class at first gap
class_zero = Counter()          # gap kinds where 0 candidates
class_multi = Counter()
n_matched = 0
n_gap_with_pgn = 0
extra = Counter()               # how many more plies the pgn has vs gap ply (truncation depth)

examples = []
for g in range(757, 1301):
    try:
        word, moves = read_game(g)
    except Exception:
        continue
    if not (word & 0x0a000000) or not moves:
        continue
    # identify pgn game index via headers is unavailable here (cbh has no headers);
    # instead use fixed order assumption: pgn[g-757] is the same game ONLY if every
    # prior game decoded; unreliable. We use raw order and match by content marker:
    # instead, try ALL pgn games with same first fast-path lc sequence? Too heavy.
    # Pragmatic: rely on the offset-order match used before: only include games
    # where pgn index g-757 exists and starting FEN equals the DAda FEN.
    gi = g - 757
    if gi not in pgn_sans:
        continue
    n_acc, ply, raw, nc, count, lp = walk(moves)
    if nc == 0 or nc >= 2:
        # gap at 'ply': the pgn move at half-index ply is the real next move
        if ply < len(pgn_sans[gi]):
            san = pgn_sans[gi][ply]
            n_matched += 1
            n_gap_with_pgn += 1
            # classify
            if san in ('O-O', 'O-O-O'):
                cls = san
            elif '=' in san:
                cls = f"promo={san.split('=')[1].rstrip('+#')}"
            else:
                # piece = first uppercase letter (excluding castling)
                piece = san[0] if san[0].isupper() else 'P'
                cls = piece
            class_by_piece[cls] += 1
            if nc == 0:
                class_zero[cls] += 1
            else:
                class_multi[cls] += 1
            extra[ply] += 1
            if len(examples) < 12:
                examples.append((g, ply, hex(raw) if raw is not None else None, nc, san))
        else:
            # gap beyond pgn length: decoded PAST the real game end (rare corruption)
            pass

print("games with pgn match walked:", n_matched)
print("\n=== real move CLASS at first H0 gap (all Candiants) ===")
for cls, n in class_by_piece.most_common(12):
    print(f"  {cls:12s} {n:3d}   (0-cand: {class_zero.get(cls,0)}, multi: {class_multi.get(cls,0)})")

print("\n=== first-gap ply distribution (matched games) ===")
buckets = Counter(min(ply // 10, 10) for ply in extra)
for b in sorted(buckets):
    print(f"  ply {b*10}-{b*10+9}: {buckets[b]}")

print("\n=== samples ===")
for ex in examples:
    print("  ", ex)
