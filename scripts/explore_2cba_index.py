#!/usr/bin/env python3
"""Scan the .2cbh index @0x10 (cbaOffset field) and confirm its semantics.

Reports:
  - the field value distribution (u32 vs u64, the 'none' marker)
  - how many games are annotated
  - whether the framed .2cba records at those offsets carry the record magic
"""
import struct, sys, os

BASE = sys.argv[1] if len(sys.argv) > 1 else "/media/michael-g-thomas/sas_mirror/chess/pgn"
ROOT = "LumbrasGigaBase_OTB_ELO2400"

cbh = open(os.path.join(BASE, ROOT + ".2cbh"), "rb").read()
recordSize = struct.unpack_from("<H", cbh, 0x0a)[0]
nGames = len(cbh) // recordSize - 256
print(f"recordSize={recordSize} nGames={nGames}")

MAGIC_NONE32 = 0x7fffffff

noneCount = 0
offs = []
hi_vals = set()
for k in range(nGames):
    rec = cbh[(256 + k) * recordSize : (256 + k) * recordSize + recordSize]
    off64 = struct.unpack_from("<Q", rec, 0x10)[0]
    hi_vals.add(off64 >> 32)
    lo = off64 & 0xFFFFFFFF
    if lo == MAGIC_NONE32:
        noneCount += 1
    else:
        offs.append((k, lo))

print(f"none-marker count = {noneCount}, annotated = {len(offs)}, hi64 values = {sorted(hi_vals)[:8]}")
cba = open(os.path.join(BASE, ROOT + ".2cba"), "rb").read()
print(f".2cba size = {len(cba)}")

if offs:
    print("first 10 annotated games (index, cbaOffset):", [(k, hex(o)) for k, o in offs[:10]])
    mono = all(offs[i][1] <= offs[i+1][1] for i in range(min(2000, len(offs)-1)))
    print(f"first-2000 offsets monotonically non-decreasing: {mono}")
    maxoff = max(o for _, o in offs)
    print(f"max cbaOffset = {maxoff:#x} ({maxoff}) vs .2cba size {len(cba)}  margin={len(cba)-maxoff}")

def framing(off):
    if off + 0x1a > len(cba):
        return None
    magic = struct.unpack_from("<Q", cba, off)[0]
    dataSize, extraSize = struct.unpack_from("<II", cba, off + 8)
    typ = struct.unpack_from("<H", cba, off + 0x18)[0]
    return magic, dataSize, extraSize, typ

ok = bad = 0
for k, off in offs[:50]:
    f = framing(off)
    if f and f[0] == 0x1122334455667788:
        ok += 1
    else:
        bad += 1
        if bad <= 3:
            print(f"  BAD magic game {k} off {off:#x}: {f}")
print(f"framing check over 50 annotated games: {ok} ok, {bad} bad")

spans = {}
for k, off in offs:
    f = framing(off)
    if f:
        spans[off] = 16 + f[1] + f[2] + 18
print("span/partition check (record span, tail bytes, next offset):")
soffs = sorted(spans)
for i in [0, 1, 2, len(soffs)//2, len(soffs)-2, len(soffs)-1]:
    off = soffs[i]
    end = off + spans[off]
    tail = cba[end-4:end] if end <= len(cba) else b""
    nxt = soffs[i+1] if i + 1 < len(soffs) else len(cba)
    print(f"  rec@{off:#x} span={spans[off]:>7} end={end:#010x} next={nxt:#010x} tail={tail.hex()}")