#!/usr/bin/env python3
"""Derive the ChessBase 17 (2CBH) Move16 code->move mapping empirically.

The .2cbg move data is plaintext 16-bit Move16 codes decoded via the
runtime-built inverse table DAT_141ad7110[code*8] in CBase26.exe. Instead of
dumping that table from Wine, we reconstruct it by correlating the codes
against a PGN edition of the same database (same game order).

For each game:
  - .2cbh index record gives the .2cbg record offset (cbgOffset @ 0x08)
  - .2cbg data = [0xfffc][16-bit move codes...][0xffff]
  - PGN mainline gives (from, to, promo) per ply via a python-chess board walk

We then tabulate code -> (from,to,piece,promo) and check consistency.

Usage: scripts/derive_move16.py [N_GAMES] [START_GAME]
"""
import struct, sys, collections, io
import chess.pgn

BASE = "/media/michael-g-thomas/sas_mirror/chess/pgn/LumbrasGigaBase_OTB_ELO2400"
CBH = BASE + ".2cbh"
CBG = BASE + ".2cbg"
PGN = BASE + ".pgn"
MAGIC = 0x1122334455667788

N_GAMES = int(sys.argv[1]) if len(sys.argv) > 1 else 2000
START = int(sys.argv[2]) if len(sys.argv) > 2 else 0

# ---- 1) read .2cbh index: game records start at record 256, 192 bytes each
cbh = open(CBH, "rb")
recsize = struct.unpack("<H", cbh.read(192)[0x0A:0x0C])[0]
assert recsize == 192, recsize

def game_offset(i):  # i = 0-based game number
    cbh.seek((256 + i) * 192)
    rec = cbh.read(192)
    marker = struct.unpack("<Q", rec[0x00:0x08])[0]
    if marker != 0x0000000001010001:
        return None
    return struct.unpack("<Q", rec[0x08:0x10])[0]

# ---- 2) read .2cbg record at a given offset -> list of uint16 codes
cbg = open(CBG, "rb")

def read_codes(off):
    cbg.seek(off)
    hdr = cbg.read(0x1A)
    magic, dsize, esize = struct.unpack("<QII", hdr[:16])
    if magic != MAGIC:
        return None
    cbg.seek(off + 0x1A)
    data = cbg.read(dsize)
    codes = list(struct.unpack("<%dH" % (dsize // 2), data))
    return codes

# ---- 3) PGN reader
pgn = open(PGN, "r", errors="replace")

def pgn_games(start):
    # skip `start` games
    for i in range(start):
        while True:
            line = pgn.readline()
            if not line:
                return
            if line.strip() == "" :
                # end of a game is a blank line after movetext; a blank line
                # before the tags also counts as a separator
                pass
            if line.startswith("[Event "):
                break
    while True:
        tags = {}
        movetext = []
        in_tags = True
        while True:
            line = pgn.readline()
            if not line:
                return
            if in_tags:
                if line.startswith("["):
                    m = line.split(" ", 1)
                    tags[m[0][1:]] = m[1].strip().rstrip('"]') if len(m) > 1 else ""
                elif line.strip() == "":
                    if tags:
                        in_tags = False
                else:
                    in_tags = False
                    movetext.append(line)
            else:
                if line.strip() == "":
                    break
                movetext.append(line)
        yield tags, "".join(movetext)

# ---- 4) correlate
code2move = {}          # code -> (from, to, promo, flags)
move2code = collections.defaultdict(set)
collisions = collections.Counter()
n_used = n_len_mismatch = n_no_offset = 0
ply_count = 0
special = collections.Counter()   # codes on castling / promo / ep plies
promo_codes = collections.defaultdict(set)
examples = {}

stream = pgn_games(START)
for i in range(N_GAMES):
    try:
        tags, movetext = next(stream)
    except StopIteration:
        break
    off = game_offset(START + i)
    if off is None:
        n_no_offset += 1
        continue
    codes = read_codes(off)
    if not codes:
        n_no_offset += 1
        continue
    # strip structural tokens
    body = [c for c in codes if c < 0xFFFB]
    # mainline SAN
    game = chess.pgn.read_game(io.StringIO(
        "".join("[%s \"%s\"]\n\n" % (k, v) for k, v in tags.items()) + movetext + "\n"))
    if game is None:
        continue
    board = game.board()
    plies = []
    for mv in game.mainline_moves():
        plies.append((board.piece_at(mv.from_square), mv.from_square, mv.to_square,
                      mv.promotion, board.is_castling(mv), board.is_capture(mv)))
        board.push(mv)
    if len(plies) != len(body):
        n_len_mismatch += 1
        continue
    ok = True
    for code, (piece, frm, to, promo, castle, cap) in zip(body, plies):
        prev = code2move.get(code)
        tup = (frm, to, piece.piece_type if piece else 0, promo or 0)
        if prev is None:
            code2move[code] = tup
            move2code[tup].add(code)
        elif prev != tup:
            ok = False
            collisions[code] += 1
        if castle:
            special[code] += 1
            if prev is None:
                examples_castle = (code, frm, to)
        if promo:
            promo_codes[(frm, to)].add(code)
        if piece and piece.piece_type == chess.PAWN and abs(to - frm) == 16 and \
           abs((frm & 7) - (to & 7)) == 1:
            special[code] += 1  # en passant
        if ok:
            examples = None
    if ok:
        ply_count = len(body)
        n_ply_total = 0
    n_used += 1

print(f"games correlated cleanly: {n_used}, length mismatches: {n_len_mismatch}, "
      f"no cbg offset: {n_no_offset}, code collisions: {len(collisions)}")
print(f"distinct codes seen: {len(code2move)}  max code: {max(code2move) if code2move else 0:#06x}")
print("distinct moves sharing a code (should be 0):",
      sum(1 for c, k in collisions.items()))
# how many distinct codes per (from,to) pair?
pair2codes = collections.defaultdict(set)
for code, (frm, to, pt, promo) in code2move.items():
    pair2codes[(frm, to)].add(code)
multi = {k: v for k, v in pair2codes.items() if len(v) > 1}
print(f"(from,to) pairs mapping to >1 code: {len(multi)} / {len(pair2codes)}")
# promo pairs
print("promotion (from,to) pairs and their codes:",
      {k: sorted(v) for k, v in list(promo_codes.items())[:6]})
# castling codes
print("castling-related codes:", dict(list(special.items())[:10]))

import json, pickle
with open("/tmp/move16_map.pkl", "wb") as f:
    pickle.dump(code2move, f)
print("saved /tmp/move16_map.pkl")