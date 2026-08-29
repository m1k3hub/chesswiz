#!/usr/bin/env python3
"""Align .2cba items with PGN twin comments; derive the ply mapping.

For each sampled annotated game:
  - items come from the strict 2-header walker (A: 23B ch-form, B: 18B plain)
  - the PGN twin is identified by (white, black, date) among hits of the
    game's own items' texts
  - items and comments are aligned in DOCUMENT ORDER (both are ply-ordered);
    a text is only accepted when it is unique within the twin

Outputs:
  /tmp/2cba_alignment.json  -- per-item rows
  stdout summary            -- delta distributions by channel
"""
import sys, os, re, json, struct, time
from collections import Counter, defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from pgn_ground_truth import parse_items_at

BASE = sys.argv[1] if len(sys.argv) > 1 else "/media/michael-g-thomas/sas_mirror/chess/pgn"
ROOT = "LumbrasGigaBase_OTB_ELO2400"
HITS = sys.argv[2] if len(sys.argv) > 2 else "/tmp/pgn_needle_hits.json"
ROWS = sys.argv[3] if len(sys.argv) > 3 else "/tmp/2cba_alignment.json"
NSAMP = int(os.environ.get("NSAMP", "600"))

t0 = time.time()
print("loading binaries...", flush=True)
CBH = open(os.path.join(BASE, ROOT + ".2cbh"), "rb").read()
CBA = open(os.path.join(BASE, ROOT + ".2cba"), "rb").read()
CBG = open(os.path.join(BASE, ROOT + ".2cbg"), "rb").read()
LID = open(os.path.join(BASE, ROOT + ".2lid"), "rb").read()
recordSize = int.from_bytes(CBH[0x0a:0x0c], "little")
N = len(CBH) // recordSize - 256
print(f"  {len(CBA)//(1<<20)} MiB cba, {N} games  ({time.time()-t0:.0f}s)", flush=True)


def index_rec(k):
    o = (256 + k) * recordSize
    r = CBH[o:o + recordSize]
    d24 = r[0xBC] | (r[0xBD] << 8) | (r[0xBE] << 16)
    dday, dmon, dyr = d24 & 0x1f, (d24 >> 5) & 0xf, (d24 >> 9) & 0xfff
    return dict(
        cbaOff=int.from_bytes(r[0x10:0x14], "little"),
        cbgOff=int.from_bytes(r[0x08:0x0c], "little"),
        wId=int.from_bytes(r[0x18:0x1c], "little") & 0xffffff,
        bId=int.from_bytes(r[0x20:0x24], "little") & 0xffffff,
        date=f"{dyr:04d}.{dmon:02d}.{dday:02d}",
        result=("0-1", "1/2-1/2", "1-0", "*")[r[0x58] & 3])


# names: walk to needed ordinals lazily (sorted scan once, keep requested ids)
def load_names_for(ids_needed):
    names = {}
    lidSig = bytes.fromhex("ffffffff08000000ffffffff")
    ordinal = 0
    pos = 0xb8
    size = len(LID)
    while pos + 12 <= size and ordinal < (1 << 21) and ids_needed:
        i = LID.find(lidSig, pos)
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
            if llen == 0 or llen >= 80 or start + 8 + llen + 4 > size:
                continue
            fo = start + 8 + llen
            flen = int.from_bytes(LID[fo:fo + 2], "little")
            if flen >= 80 or fo + 4 + flen != end - 20:
                continue
            last = LID[start + 8:start + 8 + llen]
            if all(32 <= c < 127 for c in last):
                first = LID[fo + 4:fo + 4 + flen]
                name = last.decode("latin1") + (", " + first.decode("latin1") if flen else "")
                names[ordinal] = name
            break
        ordinal += 1
        pos = end
    return names


# sample selection
annot = []
for k in range(N):
    cbaOff = int.from_bytes(CBH[(256 + k) * recordSize + 0x10:
                                (256 + k) * recordSize + 0x14], "little")
    ds = int.from_bytes(CBA[cbaOff + 8:cbaOff + 12], "little")
    if ds > 8:
        annot.append(k)
step = max(1, len(annot) // NSAMP)
sample = annot[::step][:NSAMP]
print(f"annotated={len(annot)} sampled={len(sample)}", flush=True)

# pass 1: parse all sampled .2cba records
games = []
all_names = set()
parsed = []
for k in sample:
    ix = index_rec(k)
    items, complete = parse_items_at(CBA, ix["cbaOff"],
                                     int.from_bytes(CBA[ix["cbaOff"] + 8:
                                                        ix["cbaOff"] + 12], "little"))
    parsed.append((k, ix, complete, items))
print(f"parsed .2cba records ({time.time()-t0:.0f}s)", flush=True)

# collect PGN identities needed
for k, ix, complete, items in parsed:
    all_names.update((ix["wId"], ix["bId"]))
NAMES = load_names_for(all_names)
print(f"names resolved: {len(NAMES)} ({time.time()-t0:.0f}s)", flush=True)

hits = json.load(open(HITS))
print(f"pgn hits for {len(hits)} texts", flush=True)

rows = []
n_twin = n_notwin = n_ambig = n_incomplete = 0
for k, ix, complete, items in parsed:
    if not complete or not items:
        n_incomplete += 1
        continue
    w = NAMES.get(ix["wId"], "")
    b = NAMES.get(ix["bId"], "")
    date = ix["date"]
    # twin candidates keyed by (w,b,date,mainline)
    cand = {}
    for it in items:
        if not it["text"] or it["text"] not in hits:
            continue
        for h2 in hits[it["text"]]:
            if h2["white"] == w and h2["black"] == b and h2["date"] == date:
                cand[(w, b, date, h2["mainline"])] = h2
    if not cand:
        n_notwin += 1
        rows.append(dict(k=k, status="no_twin", white=w, black=b, date=date,
                         cbgOff=ix["cbgOff"], items=items))
        continue
    if len(cand) > 1:
        n_ambig += 1
        rows.append(dict(k=k, status="ambiguous_twin",
                         candidates=[list(c) for c in cand], items=items))
        continue
    h = next(iter(cand.values()))
    # per-text comment plies from the twin (only comments recorded in hits)
    byText = defaultdict(list)
    for it in items:
        if it["text"] in hits:
            for h2 in hits[it["text"]]:
                if h2["white"] == w and h2["black"] == b and h2["date"] == date \
                        and h2["mainline"] == h["mainline"]:
                    byText[it["text"]].append(h2)
    rows.append(dict(k=k, status="aligned", white=w, black=b, date=date,
                     mainline=h["mainline"], items=items,
                     textPlies=[dict(text=it["text"],
                                     ply=[hh["ply"] for hh in byText.get(it["text"], [])],
                                     depth=[hh["depth"] for hh in byText.get(it["text"], [])])
                                for it in items if it["text"]]))
    n_twin += 1

print(f"aligned={n_twin} ambiguous={n_ambig} no_twin={n_notwin} "
      f"incomplete={n_incomplete} ({time.time()-t0:.0f}s)", flush=True)
json.dump(rows, open(ROWS, "w"), ensure_ascii=False)
print("rows written to", ROWS)