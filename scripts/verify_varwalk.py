#!/usr/bin/env python3
"""Validate the variation-walk reconstruction against PGN twins.

For sampled .2cb* games that have variation blocks and a twin:
  reconstruct the flattened walk from .2cbg (markers + blocks),
  resolve every .2cba item's X to a walk position,
  and compare against the twin's norst comment positions (text-matched).
"""
import sys, os, re, json
from collections import Counter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pgn_ground_truth import parse_items_at
from varwalk import parseCBG, reconstruct, decodePosition

movetext_lines = []
collected = []

BASE = "/media/michael-g-thomas/sas_mirror/chess/pgn"
ROOT = "LumbrasGigaBase_OTB_ELO2400"
CBH = open(os.path.join(BASE, ROOT + ".2cbh"), "rb").read()
CBG = open(os.path.join(BASE, ROOT + ".2cbg"), "rb").read()
CBA = open(os.path.join(BASE, ROOT + ".2cba"), "rb").read()
LID = open(os.path.join(BASE, ROOT + ".2lid"), "rb").read()
recordSize = int.from_bytes(CBH[0x0a:0x0c], "little")
N = len(CBH) // recordSize - 256

twins = json.load(open("/tmp/twin_movetext.json"))


def loadNames(want):
    """signature walk; return names for the wanted ordinals"""
    sig = bytes.fromhex("ffffffff08000000ffffffff")
    names = {}
    ordinal = 0
    pos = 0xb8
    want = set(want)
    while pos + 12 <= len(LID) and ordinal < (1 << 21) and want:
        i = LID.find(sig, pos)
        if i < 0:
            break
        end = i + 12
        lo = max(0, i + 8 - 320)
        start = i + 4
        while start > lo:
            start -= 1
            total = int.from_bytes(LID[start:start + 4], "little")
            if start + total != end or total <= 20 or total >= 320:
                continue
            llen = int.from_bytes(LID[start + 4:start + 6], "little")
            if llen == 0 or llen >= 80 or start + 8 + llen + 4 > len(LID):
                continue
            fo = start + 8 + llen
            flen = int.from_bytes(LID[fo:fo + 2], "little")
            if flen >= 80 or fo + 4 + flen != end - 20:
                continue
            last = LID[start + 8:start + 8 + llen]
            if ordinal in want and all(32 <= c < 127 for c in last):
                first = LID[fo + 4:fo + 4 + flen]
                names[ordinal] = last.decode("latin1") + \
                    (", " + first.decode("latin1") if flen else "")
                want.discard(ordinal)
            break
        ordinal += 1
        pos = end
    return names


def normText(t):
    return re.sub(r"\s+", " ", t.replace("(", "").replace(")", "")
                  .replace("[", "").replace("]", "")).strip().lower()


def norstComments(mt):
    out = []
    cur = 0
    i, ln = 0, len(mt)
    SAN_RE = re.compile(r"^(?:O-O(?:-O)?|0-0(?:-0)?|[KQRBN][a-h1-8]?x?[a-h][1-8](?:=?[QRBN])?|"
                        r"[a-h]x[a-h][1-8](?:=?[QRBN])?|[a-h][1-8](?:=?[QRBN])?)[+#!?]*$")
    while i < ln:
        c = mt[i]
        if c.isspace():
            i += 1
            continue
        if c == "{":
            j = mt.find("}", i + 1)
            out.append((mt[i+1:j].strip(), cur))
            i = j + 1
            continue
        if c == "(" or c == ")":
            i += 1
            continue
        j = i
        while j < ln and not mt[j].isspace() and mt[j] not in "{}()":
            j += 1
        tok = mt[i:j]
        i = j
        if tok.startswith("$"):
            continue
        if tok[0].isdigit() and "." in tok:
            continue
        if SAN_RE.match(tok):
            cur += 1
    return out


# build id->name map only for sampled games' players (two passes keep mem low)
sample = []
for k in range(0, N, 197):
    cbaOff = int.from_bytes(CBH[(256 + k) * recordSize + 0x10:
                                (256 + k) * recordSize + 0x14], "little")
    ds = int.from_bytes(CBA[cbaOff + 8:cbaOff + 12], "little")
    if ds <= 8:
        continue
    off = int.from_bytes(CBH[(256 + k) * recordSize + 0x08:
                             (256 + k) * recordSize + 0x0c], "little")
    try:
        mainline, markers, blocks = parseCBG(CBG, off)
    except Exception:
        continue
    if not markers or not blocks:
        continue
    sample.append((k, cbaOff, ds))
want = set()
for k, cbaOff, ds in sample:
    r = CBH[(256 + k) * recordSize:(256 + k) * recordSize + recordSize]
    want.add(int.from_bytes(r[0x18:0x1c], "little") & 0xffffff)
    want.add(int.from_bytes(r[0x20:0x24], "little") & 0xffffff)
names = loadNames(want)
print(f"var-games sampled: {len(sample)}, names: {len(names)}", flush=True)

# --- build twin identity set for the variation games ---
wantKeys = set()
gameMeta = {}
for k, cbaOff, ds in sample:
    r = CBH[(256 + k) * recordSize:(256 + k) * recordSize + recordSize]
    wId = int.from_bytes(r[0x18:0x1c], "little") & 0xffffff
    bId = int.from_bytes(r[0x20:0x24], "little") & 0xffffff
    d24 = r[0xBC] | (r[0xBD] << 8) | (r[0xBE] << 16)
    dday, dmon, dyr = d24 & 0x1f, (d24 >> 5) & 0xf, (d24 >> 9) & 0xfff
    wName = (names.get(wId) or "").strip()
    bName = (names.get(bId) or "").strip()
    if not wName or not bName:
        continue
    key = f"{wName}|{bName}|{dyr:04d}.{dmon:02d}.{dday:02d}"
    gameMeta[k] = (wName, bName, key)
    wantKeys.add(key)

# stream the PGN once: collect movetext for wanted keys
want = {tuple(k.split("|", 2)[0:2]) for k in ()}  # unused
tmpCache = {}
if os.path.exists("/tmp/varwalk_twin_cache.json"):
    tmpCache = json.load(open("/tmp/varwalk_twin_cache.json"))
need = {k for k in wantKeys if k not in tmpCache}
if need:
    print(f"streaming PGN for {len(need)} wanted twins...", flush=True)
    pgn = open(os.path.join(BASE, ROOT + ".pgn"), "rb")
    tags = {}
    tagRe = re.compile(r'\[(\w+) "(.*)"\]$')
    movetext_lines = []
    tagKeys = []
    started = []
    movetext = []
    tagRe = re.compile(r'^\[(\w+) "(.*)"\]$')

    def flush():
        mt = " ".join(movetext_lines).strip()
        if mt and curkey:
            tmpCache[curkey] = mt
        movetext_lines.clear()

    # simpler per-line state machine with explicit identity
    collected = []
    collecting = False
    curkey = None
    for raw in pgn:
        s = raw.rstrip(b"\r\n").strip()
        if s.startswith(b"[") and s.endswith(b"]"):
            m = tagRe.match(s.decode("latin1"))
            if m:
                tags[m.group(1)] = m.group(2)
                if m.group(1) == "Black":
                    curkey = tags.get("White", "") + "|" + m.group(2) + "|" + tags.get("Date", "")
                    if curkey in need and curkey not in tmpCache:
                        movetext_lines.clear()
                        collecting = True
            continue
        if s:
            if collecting:
                movetext_lines.append(s.decode("latin1"))
        else:
            if collecting and movetext_lines:
                flush()  # movetext done: blank line ends the game
                collecting = False
                need.discard(curkey)
                if not need:
                    break
    # done streaming
    json.dump({str(k): v for k, v in tmpCache.items()}, open("/tmp/varwalk_twin_cache.json", "w"))
    print("COLLECTED", len(tmpCache), "need-remaining:", len(need))
    print("tmpCache sample:", sorted(tmpCache)[:2])
    print("wantKeys sample:", sorted(wantKeys)[:2])
    print("main-loop key sample:", list(gameMeta.values())[0][2] if gameMeta else None)
    missingInCache = [k for k in wantKeys if k not in tmpCache]
    print(f"{len(missingInCache)} wanted keys missing from tmpCache; first 5:")
    for kk in sorted(missingInCache)[:5]:
        print("   MISSING:", repr(kk))
print(f"twin cache size: {len(twins) + len(tmpCache)} (+tmp {len(tmpCache)})")

stats = Counter()
fails = []
for k, cbaOff, ds in sample:
    r = CBH[(256 + k) * recordSize:(256 + k) * recordSize + recordSize]
    wId = int.from_bytes(r[0x18:0x1c], "little") & 0xffffff
    bId = int.from_bytes(r[0x20:0x24], "little") & 0xffffff
    d24 = r[0xBC] | (r[0xBD] << 8) | (r[0xBE] << 16)
    dday, dmon, dyr = d24 & 0x1f, (d24 >> 5) & 0xf, (d24 >> 9) & 0xfff
    wName = (names.get(wId) or "").strip()
    bName = (names.get(bId) or "").strip()
    if not wName or not bName:
        stats["no_names"] += 1
        continue
    key = f"{wName}|{bName}|{dyr:04d}.{dmon:02d}.{dday:02d}"
    twinMt = tmpCache.get(key) or twins.get(key)
    if twinMt is None:
        stats["no_twin"] += 1
        continue

    off = int.from_bytes(CBH[(256 + k) * recordSize + 0x08:
                             (256 + k) * recordSize + 0x0c], "little")
    mainline, markers, blocks = parseCBG(CBG, off)
    res = reconstruct(mainline, markers, blocks)
    if res is None:
        stats["reconstruct_failed"] += 1
        fails.append((k, key, "reconstruct"))
        continue
    plyPos, varPos, ml, varTotal = res
    items, complete = parse_items_at(CBA, cbaOff, ds)
    if not complete or not items:
        stats["no_items"] += 1
        continue

    pgnComments = norstComments(twinMt)
    # align .2cba items (doc order) to twin comments (doc order) by text
    pi = 0
    for it in items:
        if not it["text"]:
            continue
        text = normText(it["text"])
        j = pi
        while j < len(pgnComments) and normText(pgnComments[j][0]) != text:
            j += 1
        if j >= len(pgnComments):
            stats["twin_text_absent"] += 1
            fails.append((k, key[:30], it["X"], text[:35], "absent"))
            continue
        twinPos = pgnComments[j][1]
        pi = j + 1
        pos = decodePosition(it["X"], plyPos, varPos, ml + varTotal)
        # decodePosition returns the walk position itself in pos[1]
        modelPos = None if pos is None else pos[1]
        if modelPos is None or modelPos != twinPos:
            stats["mismatch"] += 1
            fails.append((k, key[:30], it["X"], "model", modelPos,
                          "twin", twinPos, text[:30]))
        else:
            stats["match"] += 1

print(dict(stats))
print(f"{len(fails)} failures (first 12):")
for f in fails[:12]:
    print("  ", f)