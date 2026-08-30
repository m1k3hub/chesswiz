#!/usr/bin/env python3
"""Test whether coordinate value 64 behaves as h8 (1-based) or sentinel (0-based)."""

import collections
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from analyze_annotations import parse_export, FIXTURES  # noqa: E402

FILES = "abcdefgh"


def name(square, shift):
    value = square - shift
    if not (0 <= value < 64):
        return f"#{square}"
    return FILES[value & 7] + str(1 + (value >> 3))


def main():
    boundary_style = collections.Counter()
    shapes = collections.Counter()
    markers = collections.Counter()
    by_file = collections.Counter()
    for path in sorted(FIXTURES.rglob("*.txt")):
        for _ts, payload in parse_export(path):
            if len(payload) < 10 or struct.unpack_from("<I", payload, 0)[0] != 6:
                continue
            count = struct.unpack_from("<H", payload, 8)[0]
            offset = 10
            for _ in range(count):
                if offset + 8 > len(payload):
                    break
                length = struct.unpack_from("<H", payload, offset)[0]
                if length < 6 or offset + 2 + length > len(payload):
                    break
                rtype = struct.unpack_from(">I", payload, offset + 2)[0]
                value = payload[offset + 8:offset + 2 + length]
                if rtype == 5 and len(value) % 3 == 0:
                    for i in range(0, len(value), 3):
                        boundary_style[value[i]] += (
                            value[i + 1] in (0, 64)) + (value[i + 2] in (0, 64))
                        if 64 in (value[i + 1], value[i + 2]):
                            by_file[path.name.rsplit(".", 2)[0]] += 1
                            frm, to = value[i + 1] - 1, value[i + 2] - 1
                            df = (to & 7) - (frm & 7)
                            dr = (to >> 3) - (frm >> 3)
                            shapes[(abs(df), abs(dr), "to64" if to + 1 == 64 else "from64")] += 1
                elif rtype == 4 and len(value) % 2 == 0:
                    for i in range(0, len(value), 2):
                        boundary_style[value[i]] += value[i + 1] in (0, 64)
                        if value[i + 1] == 64:
                            markers[value[i]] += 1
                offset += 2 + length
    print("segments touching 0/64, by style:", dict(boundary_style))
    print("segment shapes (|df|,|dr|,end):", shapes.most_common(20))
    print("style-4 markers at 64 by style:", dict(markers))
    print("files with a 64 coordinate:", dict(by_file.most_common(12)))


if __name__ == "__main__":
    main()