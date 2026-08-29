#!/usr/bin/env python3
"""Collect movetext for the .2cba sample's PGN twins (single streaming pass)."""
import sys, os, re, json, time

BASE = sys.argv[1] if len(sys.argv) > 1 else "/media/michael-g-thomas/sas_mirror/chess/pgn"
ROOT = "LumbrasGigaBase_OTB_ELO2400"
ROWS = sys.argv[2] if len(sys.argv) > 2 else "/tmp/2cba_alignment_200.json"
OUT  = sys.argv[3] if len(sys.argv) > 3 else "/tmp/twin_movetext.json"

rows = json.load(open(ROWS))
want = set()
for r in rows:
    if r.get("status") == "aligned":
        want.add((r["white"], r["black"], r["date"]))
    elif r.get("status") == "no_twin":
        want.add((r["white"], r["black"], r["date"]))
whites = {w for (w, b, d) in want}
print(f"wanted identities: {len(want)}")

found = {}
tags = {}
started = []
collected = []
in_moves = False
tagRe = re.compile(r'\[(\w+) "(.*)"\]')
t0 = time.time()


def finalize():
    global tags, started, collected, in_moves
    if started:
        w = tags.get("White", "")
        b = tags.get("Black", "")
        d = tags.get("Date", "")
        mt = " ".join(collected).strip()
        for tr in started:
            if tr not in found:
                found[tr] = mt
    started = []
    tags = {}
    collected = []
    in_moves = False


pgn = open(os.path.join(BASE, ROOT + ".pgn"), "rb")
for raw in pgn:
    s = raw.rstrip(b"\r\n").strip()
    if not s:
        if in_moves and started:
            finalize()  # movetext done: a game ends at the first blank line here
        continue
    if s.startswith(b"[") and s.endswith(b"]"):
        m = tagRe.match(s.decode("latin1"))
        if m:
            tags[m.group(1)] = m.group(2)
            if m.group(1) == "Black":
                key = (tags.get("White", ""), m.group(2), tags.get("Date", ""))
                if key in want and key not in found:
                    started.append(key)
        continue
    if started:
        collected.append(s.decode("latin1"))
        in_moves = True
if started:
    finalize()

miss = want - set(found)
print(f"found {len(found)}/{len(want)} twins ({time.time()-t0:.0f}s), missing {len(miss)}")
json.dump({f"{w}|{b}|{d}": mt for (w, b, d), mt in found.items()},
          open(OUT, "w"), ensure_ascii=False)
print("written", OUT)