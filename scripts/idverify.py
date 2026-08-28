#!/usr/bin/env python3
"""Verify: player ID == TRUE .2lid all-ordinal (over ALL signature slots) + 1.
Tested against .2cbh games whose PGN identity is established by full
move-sequence matching."""
import struct, re, chess, chess.pgn, io
BASE = "/media/michael-g-thomas/sas_mirror/chess/pgn/LumbrasGigaBase_OTB_ELO2400"
pgi = open(BASE + ".pgi", "rb").read()
pgn = open(BASE + ".pgn", "rb").read()
lid = open(BASE + ".2lid", "rb").read()
cbh = open(BASE + ".2cbh", "rb").read()
cbg = open(BASE + ".2cbg", "rb").read()
tbl = open("/tmp/decode_table.bin", "rb").read()

# 1) .2lid: walk ALL signature slots with TRUE ordinals
sig = b"\xff\xff\xff\xff\x08\x00\x00\x00\xff\xff\xff\xff"
true_ord = {}      # "last, first" -> TRUE all-ordinal (first occurrence)
slot_of = {}
pos = 0xb8
ordinal = 0
while ordinal < 12000:
    i = lid.find(sig, pos)
    if i < 0:
        break
    end = i + 12
    lo = max(0xb8, i - 320)
    for start in range(i - 20, lo - 1, -1):
        total = struct.unpack_from("<I", lid, start)[0]
        if start + total == end and 20 < total < 320:
            llen = struct.unpack_from("<I", lid, start + 4)[0]
            if 0 < llen < 80:
                fo = start + 8 + llen
                flen = struct.unpack_from("<I", lid, fo)[0]
                if 0 <= flen < 80 and fo + 4 + flen == end - 20:
                    last = lid[start + 8:fo].decode('latin1')
                    first = lid[fo + 4:fo + 4 + flen].decode('latin1')
                    ok = True
                    for ch in last:
                        if not (32 <= ord(ch) < 127):
                            ok = False
                    if ok and llen > 0:
                        full = last + ", " + first
                        if full not in true_ord:
                            true_ord[full] = ordinal
                            slot_of[full] = start
                    break
    ordinal += 1
    pos = end
print("slots walked:", ordinal, "named:", len(true_ord))

# 2) PGN index: first 20000 games, full SAN sequences
N = 20000
pgn_map = {}
pgn_meta = {}
for k in range(N):
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
print("pgn index:", len(pgn_map))

# 3) .2cbh games: decode the record at @0x08, full-sequence match, verify
def sqn16(s):
    return "abcdefgh"[s >> 3] + str((s & 7) + 1)

tested = 0
good = 0
bad = 0
for k in range(3000):
    if tested >= 40:
        break
    rec = cbh[(256 + k) * 192:(256 + k) * 192 + 192]
    if struct.unpack_from("<Q", rec, 0)[0] != 0x0000000001010001:
        continue
    o8 = struct.unpack_from("<Q", rec, 0x08)[0]
    magic, d, e = struct.unpack_from("<QII", cbg[o8:o8 + 0x10], 0)
    if magic != 0x1122334455667788:
        continue
    typ = struct.unpack_from("<H", cbg, o8 + 0x18)[0]
    if typ != 1:
        continue
    data = struct.unpack_from("<%dH" % (d // 2), cbg, o8 + 0x1a)
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
    if not ok or len(sans) < 20:
        continue
    key = (len(sans), tuple(sans))
    if key not in pgn_map:
        continue
    kk = pgn_map[key]
    tags = pgn_meta[kk]
    w = struct.unpack_from("<Q", rec, 0x18)[0]
    b = struct.unpack_from("<Q", rec, 0x20)[0]
    wn = tags.get('White', '?')
    bn = tags.get('Black', '?')
    wo = true_ord.get(wn, -1)
    bo = true_ord.get(bn, -1)
    dw = w - wo if wo >= 0 else None
    db = b - bo if bo >= 0 else None
    status = "OK" if dw == db and dw is not None else "??"
    print("game %4d: ids (%d,%d) lid_ord (%d,%d) delta (%s,%s) %s | %s vs %s"
          % (k, w, b, wo, bo, dw, db, status, wn, bn))
    if status == "OK" and dw == 1:
        good += 1
    elif status == "OK":
        bad += 1
    tested += 1
print("tested:", tested, "delta==1:", good, "other-constant:", bad)