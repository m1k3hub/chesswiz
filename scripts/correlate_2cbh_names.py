#!/usr/bin/env python3
"""Correlate player IDs (from .2cbh) with names (from PGN) and .2lid offsets,
to reverse-engineer the .2lgd mapping. Prints a table to reveal the structure.
"""
import struct, sys, os, re

BASE = sys.argv[1] if len(sys.argv) > 1 else "/media/michael-g-thomas/sas_mirror/chess/pgn"
ROOT = "LumbrasGigaBase_OTB_ELO2400"

def u64le(b, off): return struct.unpack_from("<Q", b, off)[0]

def read_games(n):
    """Read first n games: (wp, bp, ev) from .2cbh."""
    with open(os.path.join(BASE, ROOT + ".2cbh"), "rb") as f:
        f.seek(256 * 192)
        out = []
        for _ in range(n):
            rec = f.read(192)
            if len(rec) < 192: break
            out.append((u64le(rec, 0x18), u64le(rec, 0x20), u64le(rec, 0x28)))
    return out

def read_pgn(n):
    """Read first n games' White/Black/Event."""
    out = []
    tags = {}
    with open(os.path.join(BASE, ROOT + ".pgn"), "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            m = re.match(r'\[(\w+) "([^"]*)"\]', line)
            if m: tags[m.group(1)] = m.group(2)
            elif line == "" and tags:
                out.append((tags.get("White",""), tags.get("Black",""), tags.get("Event","")))
                tags = {}
                if len(out) >= n: break
    return out

def main():
    lid = open(os.path.join(BASE, ROOT + ".2lid"), "rb").read()
    lgd = open(os.path.join(BASE, ROOT + ".2lgd"), "rb").read()
    games = read_games(15)
    pgn = read_pgn(15)

    print(f"{'pid':>6} {'name':<24} {'lid_off':>10}  {'lgd positions (pid as u32le)'}")
    seen = set()
    for (wp, bp, ev), (w, b, e) in zip(games, pgn):
        for pid, name in [(wp, w), (bp, b)]:
            if pid in seen: continue
            seen.add(pid)
            # find name in .2lid (first occurrence = record)
            off = lid.find(name.encode("latin1"))
            # find pid in .2lgd
            pat = struct.pack("<I", pid)
            pos = []
            s = 0
            while True:
                i = lgd.find(pat, s)
                if i < 0: break
                pos.append(i)
                s = i + 1
                if len(pos) >= 4: break
            print(f"{pid:>6} {name:<24} {off:#x}  {[hex(p) for p in pos]}")

if __name__ == "__main__":
    main()
