#!/usr/bin/env python3
"""Decide the type-4/5 square coordinate convention with structure.

Hypothesis A (current doc): a1 = 0 ... h8 = 63, 64 = sentinel.
Hypothesis B (new diff):    a1 = 1 ... h8 = 64, 0 = sentinel.

Oracle 1: chained type-5 arrows (same style, to[i] == from[i+1]) form a
piece path; consecutive hops must respect chess geometry for SOME piece.
For each chain we test knight consistency (strongest signal) and
diagonal/file/rank continuation.

Oracle 2: for position-specific clips whose directory/file name carries a
FEN board (ranks separated by 'z'), arrows/markers drawn within the first
seconds should reference plausible squares; more importantly the cumulative
distribution over all coordinates should expose which edge value is real.
"""

import collections
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from analyze_annotations import parse_export, FIXTURES  # noqa: E402


def geometry(frm, to):
    """Return ('knight'|'diag'|'line'|None, offset) for two square values."""
    df = (to & 7) - (frm & 7)
    dr = (to >> 3) - (frm >> 3)
    adf, adr = abs(df), abs(dr)
    if {adf, adr} == {1, 2}:
        return "knight", (df, dr)
    if adf == adr and adf > 0:
        return "diag", (df // adf, dr // adr)
    if df == 0 and dr != 0:
        return "line", (0, dr // adr)
    if dr == 0 and df != 0:
        return "line", (df // adf, 0)
    return None, (df, dr)


def delta_type5(payload):
    out = []
    if len(payload) < 10 or struct.unpack_from("<I", payload, 0)[0] != 6:
        return out
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
            out.append([(value[i], value[i + 1], value[i + 2])
                        for i in range(0, len(value), 3)])
        offset += 2 + length
    return out


def chains(records, one_based):
    shift = 1 if one_based else 0
    result = []
    for arrows in records:
        pairs = [(f - shift, t - shift, s) for s, f, t in arrows]
        for i in range(len(pairs) - 1):
            sf, st, ss = pairs[i]
            nf, nt, ns = pairs[i + 1]
            if ss != ns or st != nf:
                continue
            if not (0 <= sf < 64 and 0 <= nf < 64 and 0 <= nt < 64):
                continue
            kind, offset = geometry(sf, st)
            if kind is None:
                continue
            kind2, offset2 = geometry(nf, nt)
            same = kind2 == kind and offset2 == offset and offset2 not in ((0, 0),)
            result.append((kind, same))
    return result


def main():
    outcome = {False: collections.Counter(), True: collections.Counter()}
    for path in sorted(FIXTURES.rglob("*.txt")):
        for _ts, payload in parse_export(path):
            records = delta_type5(payload)
            for one_based in (False, True):
                for kind, same in chains(records, one_based):
                    outcome[one_based][f"{kind}_{'same' if same else 'diff'}"] += 1
    for one_based in (False, True):
        counts = outcome[one_based]
        total = sum(counts.values())
        print(f"{'1-based' if one_based else '0-based'}: total={total} "
              + " ".join(f"{key}={count}" for key, count in sorted(counts.items())))


if __name__ == "__main__":
    main()