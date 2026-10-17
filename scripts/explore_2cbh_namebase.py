#!/usr/bin/env python3
"""Explore the 2CBH namebase files (.2lid/.2lcd/.2lgd) against the PGN ground truth.

Goal: reverse-engineer how the .2cbh index's whitePlayerId/blackPlayerId/eventId
(uint64) map to player/event names, so scidb can implement index-only 2CBH
browsing (docs/formats/2CBH_FORMAT_DESIGN.md §7).

Usage:
    python3 scripts/explore_2cbh_namebase.py [base_dir]

where base_dir contains LumbrasGigaBase_OTB_ELO2400.{2cbh,2lid,2lcd,2lgd,pgn}.
"""
import struct, sys, os

BASE = sys.argv[1] if len(sys.argv) > 1 else "/media/michael-g-thomas/sas_mirror/chess/pgn"
ROOT = "LumbrasGigaBase_OTB_ELO2400"

def u32le(b, off): return struct.unpack_from("<I", b, off)[0]
def u64le(b, off): return struct.unpack_from("<Q", b, off)[0]
def u32be(b, off): return struct.unpack_from(">I", b, off)[0]

def read_index():
    """Read .2cbh game records (records 256+). Returns list of dicts."""
    path = os.path.join(BASE, ROOT + ".2cbh")
    with open(path, "rb") as f:
        f.seek(256 * 192)  # skip header (rec 0) + metadata (recs 1-255)
        games = []
        while True:
            rec = f.read(192)
            if len(rec) < 192:
                break
            marker = u64le(rec, 0x00)
            if marker != 0x0000000001010001:
                break
            games.append({
                "cbg": u64le(rec, 0x08),
                "cba": u64le(rec, 0x10),
                "wp": u64le(rec, 0x18),
                "bp": u64le(rec, 0x20),
                "ev": u64le(rec, 0x28),
                "flags": u64le(rec, 0x58),
                "eco": u64le(rec, 0x60),
                "date": u64le(rec, 0x88),
            })
    return games

def read_pgn_headers(n):
    """Read first n games' headers from the PGN."""
    import re
    path = os.path.join(BASE, ROOT + ".pgn")
    out = []
    tags = {}
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.rstrip("\n")
            m = re.match(r'\[(\w+) "([^"]*)"\]', line)
            if m:
                tags[m.group(1)] = m.group(2)
            elif line == "" and tags:
                out.append(tags)
                tags = {}
                if len(out) >= n:
                    break
    return out

def main():
    games = read_index()
    print(f"index: {len(games)} games")
    pgn = read_pgn_headers(10)
    print(f"pgn: {len(pgn)} games\n")

    for i in range(min(5, len(games), len(pgn))):
        g, p = games[i], pgn[i]
        print(f"game {i+1}: wp={g['wp']} bp={g['bp']} ev={g['ev']} "
              f"date={g['date']:#x} eco={g['eco']:#x} flags={g['flags']:#x}")
        print(f"   PGN: {p.get('White')} vs {p.get('Black')} | {p.get('Event')} "
              f"| {p.get('Date')} | {p.get('ECO')} | {p.get('Result')} | R{p.get('Round')}")

    # Dump .2lid header (first 256 bytes) as both endiannesses
    print("\n=== .2lid header ===")
    with open(os.path.join(BASE, ROOT + ".2lid"), "rb") as f:
        h = f.read(256)
    for off in range(0, 64, 4):
        print(f"  {off:#04x}: LE={u32le(h,off):#010x}  BE={u32be(h,off):#010x}")

    print("\n=== .2lcd header ===")
    with open(os.path.join(BASE, ROOT + ".2lcd"), "rb") as f:
        h = f.read(64)
    for off in range(0, 64, 4):
        print(f"  {off:#04x}: LE={u32le(h,off):#010x}  BE={u32be(h,off):#010x}")

    print("\n=== .2lgd header ===")
    with open(os.path.join(BASE, ROOT + ".2lgd"), "rb") as f:
        h = f.read(64)
    for off in range(0, 64, 4):
        print(f"  {off:#04x}: LE={u32le(h,off):#010x}  BE={u32be(h,off):#010x}")

if __name__ == "__main__":
    main()
