#!/usr/bin/env python3
"""Ground-truth pipeline for .2cba ply alignment.

Phase 1: parse .2cbh index, .2lid namebase, .2cba records (proper item
         walker), and the .2cbg mainline (via move16_py) for a sample of
         annotated games.
Phase 2: scan the PGN twin for line needles playing the game role correctly
         locating each comment's ply context with a real PGN movetext
         tokenizer (RAV-aware), and identify the twin by White/Black/Date.
Phase 3: align items with PGN comments and dump the (X, ch) vs ground-truth
         ply matrix as JSON for mapping analysis.
"""
import struct, sys, os, re, json

BASE = sys.argv[1] if len(sys.argv) > 1 else "/media/michael-g-thomas/sas_mirror/chess/pgn"
ROOT = "LumbrasGigaBase_OTB_ELO2400"
OUT  = sys.argv[2] if len(sys.argv) > 2 else "/tmp/2cba_ground_truth.json"

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from move16_py import cbg_uci, replay

# ----------------------------------------------------------------------
# loading
# ----------------------------------------------------------------------
def load(prefix, ext):
    with open(os.path.join(BASE, ROOT + ext), "rb") as f:
        return f.read()

print("loading .2cbh...", flush=True)
CBH = load(None, ".2cbh")
print("loading .2cba...", flush=True)
CBA = load(None, ".2cba")
print("loading .2cbg...", flush=True)
CBG = load(None, ".2cbg")
print("loading .2lid...", flush=True)
LID = load(None, ".2lid")
print("done loading", flush=True)

recordSize = int.from_bytes(CBH[0x0a:0x0c], "little")
N = len(CBH) // recordSize - 256

def index_rec(k):
    o = (256 + k) * recordSize
    r = CBH[o:o + recordSize]
    cbaOff = int.from_bytes(r[0x10:0x14], "little")
    date = (r[0xBC] | (r[0xBD] << 8) | (r[0xBE] << 16))
    dday, dmon, dyr = date & 0x1f, (date >> 5) & 0xf, (date >> 9) & 0xfff
    res = ("0-1", "1/2-1/2", "1-0", "*")[r[0x58] & 3]
    return dict(
        cbgOff=int.from_bytes(r[0x08:0x0c], "little"),
        cbaOff=cbaOff,
        wId=int.from_bytes(r[0x18:0x1c], "little") & 0xffffff,
        bId=int.from_bytes(r[0x20:0x24], "little") & 0xffffff,
        wElo=int.from_bytes(r[0x60:0x62], "little"),
        bElo=int.from_bytes(r[0x70:0x72], "little"),
        result=res,
        date=(dyr, dmon, dday))

# ----------------------------------------------------------------------
# .2lid names (signature walk; ordinal == player id)
# ----------------------------------------------------------------------
lidSig = bytes.fromhex("ffffffff08000000ffffffff")

def load_names():
    syspath = os.path.join(BASE, ROOT + ".2lid")
    names = {}
    ordinal = 0
    pos = 0xb8
    size = len(LID)
    while pos + 12 <= size and ordinal < (1 << 21):
        i = LID.find(lidSig, pos)
        if i < 0:
            break
        end = i + 12
        lo = max(0, i + 8 - 320)
        start = i + 4
        found = False
        while start > lo:
            start -= 1
            total = int.from_bytes(LID[start:start + 4], "little")
            if start + total != end or total <= 20 or total >= 320:
                continue
            llen = int.from_bytes(LID[start + 4:start + 6], "little")
            if llen == 0 or llen >= 80 or start + 8 + llen + 4 > size:
                continue
            fo = start + 8 + llen
            flen = int.from_bytes(LID[fo:fo + 2], "little")
            if flen >= 80 or fo + 4 + flen != end - 20:
                continue
            last = LID[start + 8:start + 8 + llen]
            first = LID[fo + 4:fo + 4 + flen]
            try:
                if not all(32 <= c < 127 for c in last):
                    start = 0
                    break
                name = (first.decode("latin1") + ", " if flen else "") + last.decode("latin1")
                names[ordinal] = name
            except Exception:
                pass
            found = True
            break
        ordinal += 1
        pos = end
    return names

print("walking .2lid...", flush=True)
NAMES = load_names()
print(f"{len(NAMES)} names", flush=True)

# ----------------------------------------------------------------------
# .2cba item parse: [u32 X][u32 2][u16 3][u16 ch][u8 0][u32 2][u16 type][u32 len][payload]
# terminated by ff ff ff 7f (scan for it; remainder = row tail)
# ----------------------------------------------------------------------
def parse_items(rec_off):
    dataSize = int.from_bytes(CBA[rec_off + 8:rec_off + 12], "little")
    extraSize = int.from_bytes(CBA[rec_off + 12:rec_off + 16], "little")
    typ = int.from_bytes(CBA[rec_off + 0x18:rec_off + 0x1a], "little")
    dataOff = rec_off + 0x1a
    dataEnd = dataOff + dataSize
    p = dataOff
    items = []
    while p + 23 <= dataEnd:
        if CBA[p:p + 4] == b"\xff\xff\xff\x7f" or CBA[p:p + 2] == b"\xff\xff":
            break
        X, mid2, ver, ch = struct.unpack_from("<IIHH", CBA, p)
        z = CBA[p + 12]
        mid3 = int.from_bytes(CBA[p + 13:p + 17], "little")
        itype, ln = struct.unpack_from("<HI", CBA, p + 15)
        if mid2 != 2 or ver != 3 or z != 0 or mid3 != 2 or itype != 7 or p + 23 + ln > dataEnd:
            items.append({"kind": "?", "at": p - dataOff})
            break
        payload = CBA[p + 23:p + 23 + ln]
        try:
            text = payload.decode("utf-8")
        except UnicodeDecodeError:
            text = None
        items.append({"kind": "text", "X": X, "ch": ch, "type": itype,
                      "len": ln, "text": text, "at": p - dataOff})
        p += 23 + ln
    return dict(dataSize=dataSize, extraSize=extraSize, recType=typ,
                items=items, tail=CBA[p:dataEnd].hex(),
                extra=CBA[dataEnd:dataEnd + extraSize].hex())

# ----------------------------------------------------------------------
# sample selection: annotated games with real content
# ----------------------------------------------------------------------
print("index scan...", flush=True)
sample = []
for k in range(N):
    recOff = index_rec(k)["cbaOff"]
    dataSize = int.from_bytes(CBA[recOff + 8:recOff + 12], "little")
    if dataSize > 8:
        sample.append(k)
NSAMP = int(os.environ.get("NSAMP", "150"))
if len(sample) > NSAMP:
    step = len(sample) / NSAMP
    sample = [sample[int(i * step)] for i in range(NSAMP)]
print(f"annotated-with-content: {sample and len(sample)} (sampled {len(sample)})", flush=True)

sampled = []
for k in sample:
    ix = index_rec(k)
    wName = NAMES.get(ix["wId"], f"?{ix['wId']}")
    bName = NAMES.get(ix["bId"], f"?{ix['bId']}")
    rec = parse_items(ix["cbaOff"])
    uci, moves, term, ok = cbg_uci(CBG, ix["cbgOff"])
    board, n_ok = replay(uci) if ok else (None, -1)
    sampled.append(dict(k=k, **ix, white=wName, black=bName,
                        cbgMoves=moves, cba=rec,
                        uci=uci if n_ok >= 0 else None,
                        replayOk=n_ok == moves))
print("sample parsed:", len(sampled), "replayOk:", sum(1 for g in sampled if g["replayOk"]), flush=True)

# ----------------------------------------------------------------------
# PGN scan
# ----------------------------------------------------------------------
needleRe = None
needles = sorted({it["text"] for g in sampled for it in g["cba"]["items"]
                  if it["kind"] == "text" and it["text"]}) , 
alt = "|".join(re.escape(n) for n in needles)
needleRe = re.compile(alt.encode("utf-8"))
print(f"{len(needles)} needles, scanning PGN...", flush=True)

movetextRe = re.compile(rb"\{[^{}]*\}")
pgnName = os.path.join(BASE, ROOT + ".pgn")
CHUNK = 1 << 22

def read_game_tags(fh, line_off):
    """Read the tag block immediately above byte offset line_off."""
    fh.seek(max(0, line_off - 4096))
    blk = fh.read(4096).split(b"\n")
    end = None
    # find the line whose start offset <= line_off; we approximate by rebuilding
    # from the block: recompute offsets
    base = max(0, line_off - 4096)
    acc = 0
    tags = {}
    for ln in blk:
        acc += len(ln) + 1
        if acc >= (line_off - base):
            break
        m = re.match(rb"\[(\w+) \"(.*)\"\]\s*$", ln)
        if m:
            tags[m.group(1).decode()] = m.group(2).decode()
    return tags

def tokenize_comment_plies(movetext: bytes):
    """RAV-aware PGN movetext tokenizer.

    Returns a list of (text, ply_before, depth) for every {} comment,
    where ply_before = number of SAN moves played in the current context
    before the comment, and depth = 0 for mainline.
    """
    out = []
    stack = []
    cur = 0
    i = 0
    n = len(movetext)
    token_re = re.compile(r"\s*(\{[^{}]*\}|\(|\)|\$\d+|B?O-O(?:-O)?[+#]?|0-0(?:-0)?[+#]?|"
                          r"[KQRBN]?[a-h]?[1-8]?x?[a-h][1-8](?:=[QRBN])?[+#]?|--|"
                          r"[1-9]\d*(?:\.\.\.)?\.+|1-0|0-1|\*|<=|e\.p\.?)")
    while i < n:
        if movetext[i:i + 1].isspace():
            i += 1
            continue
        m = token_re.match(movetext.decode("latin1"), i)
        if not m:
            i += 1
            continue
        tok = m.group(1)
        j = m.end()
        if tok == "(":
            stack.append(cur)
枸杞        elif tok == ")":
            cur = stack.pop() if stack else 0
        elif tok.startswith("{"):
            out.append((tok[1:-1], cur, len(stack)))
        elif tok.startswith("$"):
            pass
        elif re.match(r"^[0-9]+\.+$", tok):
            pass
        elif re.match(r"^1-0$", tok) or re.match(r"^0-1$", tok) or tok == "*":
            pass
        else:
            cur += 1
        i = j
    return out

pgnHits = {}   # (white,black,date) -> list of dict
with open(pgnName, "rb") as fh:
    buf = b""
    base = 0
    while True:
        chunk = fh.read(CHUNK)
        if not chunk:
            break
        buf += chunk
        if needleRe.search(buf):
            # resolve hits in buf
            for m in needleRe.finditer(buf):
                # find enclosing movetext line
                line_start = buf.rfind(b"\n", 0, m.start()) + 1
                line_end = buf.find(b"\n", m.start())
                if line_end < 0:
                    break  # line truncated at chunk edge; skip (rare)
                line = buf[line_start:line_end]
                off_line = base + line_start
                tags = read_game_tags(fh, base + off_line).  # broken call? fix: we resync below
                ...
        # fast path: emit game boundaries
    # end