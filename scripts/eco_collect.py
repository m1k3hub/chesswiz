#!/usr/bin/env python3
"""Correlate the .2cbh index @0x80 u16 with the twin PGN's [ECO] tags.

1. .2lid walk (full pass) -> names by ordinal id
2. .2cbh scan for a sample of games -> (white, black, date, eco16)
3. single PGN pass -> ECO tag per matching identity
4. fit: eco16 -> ECO string; report consistency + coverage
"""
import sys, os, re, json, time
from collections import defaultdict, Counter

BASE = sys.argv[1] if len(sys.argv) > 1 else "/media/michael-g-thomas/sas_mirror/chess/pgn"
ROOT = "LumbrasGigaBase_OTB_ELO2400"
NSAMP = int(sys.argv[2]) if len(sys.argv) > 2 else 65536
OUT = sys.argv[3] if len(sys.argv) > 3 else "/tmp/eco_corr.json"

t0 = time.time()
CBH = open(os.path.join(BASE, ROOT + ".2cbh"), "rb").read()
LID = open(os.path.join(BASE, ROOT + ".2lid"), "rb").read()
recordSize = int.from_bytes(CBH[0x0a:0x0c], "little")
N = len(CBH) // recordSize - 256

step = max(1, N // NSAMP)
sampleIdx = list(range(0, N, step))[:NSAMP]

idsNeeded = set()
meta = {}
for k in sampleIdx:
    r = CBH[(256 + k) * recordSize: (256 + k) * recordSize + recordSize]
    w = int.from_bytes(r[0x18:0x1c], "little") & 0xffffff
    b = int.from_bytes(r[0x20:0x24], "little") & 0xffffff
    idsNeeded.add(w)
    idsNeeded.add(b)
    d24 = r[0xBC] | (r[0xBD] << 8) | (r[0xBE] << 16)
    dday, dmon, dyr = d24 & 0x1f, (d24 >> 5) & 0xf, (d24 >> 9) & 0xfff
    meta[k] = (w, b, f"{dyr:04d}.{dmon:02d}.{dday:02d}",
               int.from_bytes(r[0x80:0x82], "little"))
print(f"player ids needed: {len(idsNeeded)}", flush=True)

sig = bytes.fromhex("ffffffff08000000ffffffff")
names = {}
ordinal = 0
pos = 0xb8
lastOff = len(LID)
while pos + 12 <= lastOff and ordinal < (1 << 21) and idsNeeded:
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
        if llen == 0 or llen >= 80 or start + 8 + llen + 4 > lastOff:
            continue
        fo = start + 8 + llen
        flen = int.from_bytes(LID[fo:fo + 2], "little")
        if flen >= 80 or fo + 4 + flen != end - 20:
            continue
        last = LID[start + 8:start + 8 + llen]
        if ordinal in idsNeeded and all(32 <= c < 127 for c in last):
            first = LID[fo + 4:fo + 4 + flen]
            names[ordinal] = last.decode("latin1") + (", " + first.decode("latin1") if flen else "")
            idsNeeded.discard(ordinal)
        break
    ordinal += 1
    pos = end
idsNeeded = None
print(f"names resolved: {len(names)} ({time.time()-t0:.0f}s)", flush=True)

sample = {}
for k in sampleIdx:
    w, b, date, eco16 = meta[k]
    wname = names.get(w)
    bname = names.get(b)
    if not wname or not bname:
        continue
    sample[k] = (wname, bname, date, eco16)
meta = None
keymap = defaultdict(list)
for k, (w, b, date, eco16) in sample.items():
    keymap[(w, b, date)].append((k, eco16))
pgnKeys = {kk for kk in keymap if len(keymap[kk]) == 1}  # unique identities only
print(f"usable identities: {len(pgnKeys)} ({time.time()-t0:.0f}s)", flush=True)

found = defaultdict(lambda: defaultdict(int))  # key -> ecoTag -> count
tags = {}
tagRe = re.compile(r'\[(\w+) "(.*)"\]$')
pgn = open(os.path.join(BASE, ROOT + ".pgn"), "rb")
for raw in pgn:
    s = raw.rstrip(b"\r\n").strip()
    if not s:
        continue
    if s.startswith(b"[") and s.endswith(b"]"):
        m = tagRe.match(s.decode("latin1"))
        if m:
            tags[m.group(1)] = m.group(2)
            if m.group(1) == "ECO":
                w = tags.get("White")
                b = tags.get("Black")
                d = tags.get("Date")
                if w and b and d:
                    key = (w, b, d)
                    if key in pgnKeys:
                        found[key][m.group(2)] += 1
        continue
    # movetext line: tags of this game complete
    if tags.get("ECO"):
        tags = {}
print(f"pgn pass done ({time.time()-t0:.0f}s)", flush=True)

# correlation
pairs = []
for key, counter in found.items():
    if len(counter) != 1:
        continue  # ambiguous identity (multiple twin games with same names+date)
    (k, eco16), = keymap[key]
    ecoTag, = counter.keys()
    pairs.append((k, eco16, ecoTag))

# build map eco16 -> ECO (must be a function)
m = defaultdict(Counter)
for k, eco16, ecoTag in pairs:
    m[eco16][ecoTag] += 1
cons = 0
incons = 0
mapping = {}
for eco16, counter in sorted(m.items()):
    tag, cnt = counter.most_common(1)[0]
    if len(counter) == 1:
        cons += 1
        mapping[eco16] = tag
    else:
        incons += 1
        mapping[eco16] = f"{tag}(+{len(counter)-1} other)"
print(f"pair games: {len(pairs)}  distinct eco16 keys with twins: {len(m)}")
print(f"  consistent keys: {cons}  inconsistent: {incons}")

# stride/structure analysis: sorted keys vs ECO baseline letter*100+num
def ecoNum(tag):
    mm = re.match(r"([A-E])(\d\d)([a-z]?)$", tag)
    if not mm:
        return None
    letter, num, sub = mm.group(1), int(mm.group(2)), mm.group(3)
    base = "ABCDE".index(letter) * 100 + num
    subv = (ord(sub) - 96) if sub else 0
    return base, subv

rows = []
for eco16, tag in sorted(mapping.items()):
    rows.append((eco16, tag))
print("first 30 (eco16 -> ECO):")
for eco16, tag in rows[:30]:
    print(f"  {eco16:5d} 0x{eco16:04x}  {tag}")

json.dump({str(k): v for k, v in mapping.items()}, open(OUT, "w"), indent=0)
json.dump(pairs, open(OUT + "_pairs", "w"))
print("written", OUT)