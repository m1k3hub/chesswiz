#!/usr/bin/env python3
"""Structural analysis of opcode-02 checkpoint bodies.

Diffs consecutive checkpoints of one text export to isolate:
  - the single byte at offset 8 (cursor/ply state, high bytes of the u32
    never change),
  - inline [u16 count][records...] opcode-06-style collections inserted
    into the per-node table,
  - the fixed 5-byte node entries [pair][00 00 00],
  - the fixed metadata region after the identity strings.

Usage: analyze_checkpoints.py [name-substring]
       (default: 'Biel 2015 round 06 Navara-Adams')
"""

import struct
import sys

from analyze_annotations import parse_export, FIXTURES


def checkpoints(substring):
    paths = [p for p in sorted(FIXTURES.rglob("*.txt")) if substring in p.name]
    for path in paths:
        for ts, payload in parse_export(path):
            if struct.unpack_from("<I", payload, 0)[0] == 2:
                yield ts, payload


def show_diffs(substring):
    prev = None
    for ts, payload in checkpoints(substring):
        state = struct.unpack_from("<I", payload, 8)[0]
        if prev:
            prev_ts, prev_payload = prev
            i = 0
            n = min(len(prev_payload), len(payload))
            while i < n and prev_payload[i] == payload[i]:
                i += 1
            j = 0
            while j < n - i and prev_payload[len(prev_payload) - 1 - j] == payload[len(payload) - 1 - j]:
                j += 1
            if len(payload) == len(prev_payload) and i + j >= len(payload):
                print(f"{ts} state=0x{state:x}: identical")
            else:
                print(f"{ts} state=0x{state:x} len={len(payload)}: insert at {i}, "
                      f"new bytes: {payload[i:len(payload) - j].hex()}")
        prev = (ts, payload)


def dump_tail(substring):
    best = None
    for ts, payload in checkpoints(substring):
        if not best or len(payload) > len(best[1]):
            best = (ts, payload)
    if best is None:
        return
    ts, payload = best
    state = struct.unpack_from("<I", payload, 8)[0]
    print(f"largest {ts} state=0x{state:x} len={len(payload)}")
    offset = 16
    for _ in range(6):
        offset += 1 + payload[offset]
    print(f"identity strings end at {offset}; "
          f"date=0x{struct.unpack_from('<I', payload, offset)[0]:x}")
    hexes = payload[offset + 4:].hex()
    for row in range(0, len(hexes), 64):
        print(f"{row // 2:04x}: {hexes[row:row + 64]}")


if __name__ == "__main__":
    substring = sys.argv[1] if len(sys.argv) > 1 else "Biel 2015 round 06 Navara-Adams"
    show_diffs(substring)
    dump_tail(substring)