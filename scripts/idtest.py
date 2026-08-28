#!/usr/bin/env python3
"""Definitive ID-formula test: match FULL move sequences between .2cbg
records and PGN games (unique matches only), then compute
   base = player_ID - .2lid_ordinal
for white and black of every matched game.  A constant base solves the
name mapping."""
import struct, re, chess
BASE = "/media/michael-g-thomas/sas_mirror/chess/pgn/LumbrasGigaBase_OTB_ELO2400"
pgi = open(BASE + ".pgi", "rb").read()
pgn = open(BASE + ".pgn", "rb").read()
lid = open(BASE + ".2lid", "rb").read()
cbh = open(BASE + ".2cbh", "rb").read()
cbg = open(BASE + ".2cbg", "rb").read()
tbl = open("/tmp/decode_table.bin", "rb").read()

# 1) .2lid walk (all signature records; true ordinals over non-empty)
sig = b"\xff\xff\xff\xff\x08\x00\x00\x00\xff\xff\xff\xff"
lid_all = []      # (offset, last, first) or None for empty/unparseable
pos = 0xb8
while len(lid_all) < 12000:
    i = lid.find(sig, pos)
    if i < 0:
        break
    end = i + 12
    lo = max(0xb8, i - 320)
    rec = None
    for start in range(i - 20, lo - 1, -1):
        total = struct.unpack_from("<I", lid, start)[0]
        if start + total == end and 20 < total < 320:
            llen = struct.unpack_from("<I", lid, start + 4)[0]
            if 0 < llen < 80:
                fo = start + 8 + llen
                flen = struct.unpack_from("<I", lid, fo)[0]
                if 0 <= flen < 80 and fo + 4 + flen == end - 20:
                    last = lid[start + 8:fo]
                    first = lid[fo + 4:fo + 4 + flen]
                    if all(32 <= c < 127 for c in last):
                        rec = (start, last.decode('latin1'),
                               first.decode('latin1'))
                    break
    lid_all.append(rec)
    pos = end
n_valid = sum(1 for r in lid_all if r)
print("lid slots:", len(lid_all), "valid:", n_valid)
ordinal_of = {}     # surname -> first ordinal (non-empty)
ordinal_all = {}    # surname -> first true ordinal (incl. empties)
for n, r in enumerate(lid_all):
    if r:
        ordinal_of.setdefault(r[1], n)
        ordinal_all.setdefault(r[1] + ", " + r[2], n)

# 2) PGN: full SAN sequence -> (ordinal, White, Black) for 20000 games
N_PGN = 20000
pgn_map = {}
pgn_meta = {}
for k in range(N_PGN):
    off = struct.unpack_from("<Q", pgi, 8 + 8 * k)[0]
    e2 = pgn.find(b"\n\n", off)
    hdr = pgn[off:e2].decode('latin1')
    tags = dict(re.findall(r'\[(\w+) "([^"]*)"\]', hdr))
    mend = pgn.find(b"\n\n", e2 + 2)
    movetext = pgn[e2 + 2:mend].decode('latin1') if e2 > 0 else ""
    board = chess.Board()
    sans = []
    for tok in movetext.split():
        if tok in ("1/2-1/2", "1-0", "0-1", "*"):
            break
        m = re.match(r"^\d+\.(\.\.)?(.*)$", tok)
        tok2 = m.group(2) if m else tok
        if not tok2:
            continue
        try:
            board.push_san(tok2)
        except Exception:
            break
        sans.append(tok2)
    key = (len(sans), tuple(sans))
    if key not in pgn_map:
        pgn_map[key] = k
    pgn_meta[k] = tags
print("pgn full-seq index:", len(pgn_map))

# 3) .2cbg sequential: full decode, unique-match, compute base
def sqn16(s):
    return "abcdefgh"[s >> 3] + str((s & 7) + 1)

bases = {}
off = 12
nm = 0
for r in range(3000):
    if nm >= 60:
        break
    magic, d, e = struct.unpack_from("<QII", cbg[off:off + 0x10], 0)
    typ = struct.unpack_from("<H", cbg, off + 0x18)[0]
    if typ == 1:
        data = struct.unpack_from("<%dH" % (d // 2), cbg, off + 0x1a)
        board = chess.Board()
        sans = []
        ok = True
        for c in data:
            if c == 0xfffc:
                continue
            if c == 0xffff:
                break
            if c >= 0xfffb:
                continue
            w0, w1 = struct.unpack_from("<II", tbl, c * 8)
            f, t, p = w0 & 0x3f, (w0 >> 8) & 0x3f, (w0 >> 16) & 0xff
            u = sqn16(f) + sqn16((w0 >> 8) & 0x3f)
            if w1:
                c0, c1, c2 = w1 & 0x3f, (w1 >> 8) & 0x3f, (w1 >> 16) & 0xff
                if p in (6, 14) and c0 == (w0 >> 8) & 0x3f and c1 == (w0 >> 8) & 0x3f:
                    u += {2: "q", 3: "n", 4: "b", 5: "r", 10: "q",
                          11: "n", 12: "b", 13: "r"}.get(c2, "")
            mv = chess.Move.from_uci(u)
            if mv not in board.legal_moves:
                ok = False
                break
            sans.append(board.san(mv))
            board.push(mv)
        if ok and len(sans) >= 20:
            key = (len(sans), tuple(sans))
            if key in pgn_map and pgn_map[key] not in pgn_meta:
                off += 16 + d + e + 18
                continue
            if key in pgn_map:
                k = pgn_map[key]
                tags = pgn_meta[k]
                rec = cbh[(256 + r) * 192:(256 + r) * 192 + 192]
                w = struct.unpack_from("<Q", rec, 0x18)[0]
                b = struct.unpack_from("<Q", rec, 0x20)[0]
                wn = tags.get('White', '?')
                bn = tags.get('Black', '?')
                ws = wn.split(",")[0].strip()
                bs = bn.split(",")[0].strip()
                wo = ordinal_of.get(ws, -1)
                bo = ordinal_of.get(bs, -1)
                bw = w - wo if wo >= 0 else None
                bb = b - bo if bo >= 0 else None
                bases.setdefault((bw, bb), []).append((r, k, wn, bn))
                nm += 1
    off += 16 + d + e + 18

print("\nbase candidates (white_base, black_base) -> count:")
for kk, v in sorted(bases.items(), key=lambda x: -len(x[1])):
    print(f"  {kk}: {len(v)} games  e.g. rec {v[0][0]} = pgn {v[0][1]} ({v[0][2]} vs {v[0][3]})")