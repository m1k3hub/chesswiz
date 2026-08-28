#!/usr/bin/env python3
"""Systematic field correlation: all 192 .2cbh index bytes vs the PGN
Date/ECO/Elo over the verified game pairing."""
import struct, re, chess
from collections import defaultdict
BASE = "/media/michael-g-thomas/sas_mirror/chess/pgn/LumbrasGigaBase_OTB_ELO2400"
pgi = open(BASE + ".pgi", "rb").read()
pgn = open(BASE + ".pgn", "rb").read()
lid = open(BASE + ".2lid", "rb").read()
cbh = open(BASE + ".2cbh", "rb").read()
cbg = open(BASE + ".2cbg", "rb").read()
tbl = open("/tmp/decode_table.bin", "rb").read()
sig = b"\xff\xff\xff\xff\x08\x00\x00\x00\xff\xff\xff\xff"
names = {}
pos = 0xb8; ordinal = 0
while ordinal < 11000:
    i = lid.find(sig, pos)
    if i < 0: break
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
                    last = lid[start+8:fo].decode('latin1')
                    first = lid[fo+4:fo+4+flen].decode('latin1')
                    ok = all(32 <= ord(ch) < 127 for ch in last)
                    if ok and llen > 0 and ordinal not in names:
                        names[ordinal] = (last + ", " + first) if first else last
                    break
    ordinal += 1
    pos = end
print("names:", len(names))
def sqn16(s): return "abcdefgh"[s>>3]+str((s&7)+1)
pgn_map = {}
for k in range(20000):
    off = struct.unpack_from("<Q", pgi, 8+8*k)[0]
    e2 = pgn.find(b"\n\n", off)
    hdr = pgn[off:e2].decode('latin1')
    tags = dict(re.findall(r'\[(\w+) "([^"]*)"\]', hdr))
    mend = pgn.find(b"\n\n", e2+2)
    mt = pgn[e2+2:mend].decode('latin1') if e2 > 0 else ""
    board = chess.Board(); sans = []
    for tok in mt.split():
        if tok in ("1/2-1/2","1-0","0-1","*"): break
        m = re.match(r"^\d+\.(\.\.)?(.*)$", tok)
        tok2 = m.group(2) if m else tok
        if not tok2: continue
        try: board.push_san(tok2)
        except Exception: break
        if len(sans) < 12: sans.append(tok2)
    key = tuple(sans)
    if key not in pgn_map: pgn_map[key] = (k, tags)
print("pgn indexed:", len(pgn_map))
rows = []
for k in range(6000):
    rec = cbh[(256+k)*192:(256+k)*192+192]
    if struct.unpack_from("<Q", rec, 0)[0] != 0x0000000001010001: continue
    o8 = struct.unpack_from("<Q", rec, 0x08)[0]
    magic, d, e = struct.unpack_from("<QII", cbg[o8:o8+0x10], 0)
    if magic != 0x1122334455667788: continue
    typ = struct.unpack_from("<H", cbg, o8+0x18)[0]
    if typ != 1: continue
    data = struct.unpack_from("<%dH" % (d//2), cbg, o8+0x1a)
    board = chess.Board(); sans = []
    for c in data:
        if c == 0xfffc: continue
        if c == 0xffff: break
        if c >= 0xfffb: continue
        w0, w1 = struct.unpack_from("<II", tbl, c*8)
        f, t, p = w0&0x3f, (w0>>8)&0x3f, (w0>>16)&0xff
        u = sqn16(f)+sqn16((w0>>8)&0x3f)
        if w1:
            c0, c1, c2 = w1&0x3f, (w1>>8)&0x3f, (w1>>16)&0xff
            if p in (6,14) and c0 == (w0>>8)&0x3f and c1 == (w0>>8)&0x3f:
                u += {2:"q",3:"n",4:"b",5:"r",10:"q",11:"n",12:"b",13:"r"}.get(c2,"")
        mv = chess.Move.from_uci(u)
        if mv not in board.legal_moves: break
        if len(sans) < 12: sans.append(board.san(mv))
        board.push(mv)
    hit = pgn_map.get(tuple(sans))
    if not hit: continue
    pk, tags = hit
    wn = tags.get('White'); bn = tags.get('Black')
    w = struct.unpack_from("<Q", rec, 0x18)[0]
    b = struct.unpack_from("<Q", rec, 0x20)[0]
    if names.get(w) != wn or names.get(b) != bn: continue
    rows.append((tags, struct.unpack_from("<24Q", rec, 0)))
print("verified rows:", len(rows))
# tests: for each byte 0..0xbf, which PGN value does the byte determine?
tests = [
    ("year", lambda t: t.get('Date','?').split('.')[0]),
    ("month", lambda t: (t.get('Date','?').split('.') + ['?'])[1]),
    ("day", lambda t: (t.get('Date','?').split('.') + ['?','?'])[2]),
    ("eco-letter", lambda t: (t.get('ECO','') or '?')[0]),
    ("whiteElo", lambda t: t.get('WhiteElo','?')),
    ("blackElo", lambda t: t.get('BlackElo','?')),
    ("round", lambda t: t.get('Round','?')),
]
for label, fn in tests:
    hits = []
    for byte in range(0, 0xc0):
        g = defaultdict(set)
        for tags, f in rows:
            v = (f[byte >> 3] >> ((byte & 7) * 8)) & 0xff
            try:
                g[v].add(fn(tags))
            except Exception:
                g[v].add('ERR')
        if all(len(v) == 1 for v in g.values()) and len(g) >= 4:
            sample = [(k, sorted(v)[0]) for k, v in sorted(g.items())[:5]]
            hits.append((hex(byte), len(g), sample))
    print(f"{label}: {hits if hits else 'none'}")
def fbytes(f):
    return b"".join(struct.pack("<Q", v) for v in f)
for off in range(0, 0xc0, 2):
    g = defaultdict(set)
    for tags, f in rows:
        fb = fbytes(f)
        v = struct.unpack_from("<H", fb, off)[0]
        g[v].add(tags.get('WhiteElo','?'))
    if all(len(v) == 1 for v in g.values()) and 4 <= len(g) <= 400:
        print(f"  u16@{off:#04x} -> WhiteElo ({len(g)} values)")
    g = defaultdict(set)
    for tags, f in rows:
        fb = fbytes(f)
        v = struct.unpack_from("<H", fb, off)[0]
        g[v].add(tags.get('BlackElo','?'))
    if all(len(v) == 1 for v in g.values()) and 4 <= len(g) <= 400:
        print(f"  u16@{off:#04x} -> BlackElo ({len(g)} values)")