#!/usr/bin/env python3
"""Walk .2lid player records and correlate with the .2cbh index + PGN.

The .2lid records are variable-length and (apparently) NOT in player-ID order.
This script walks them sequentially to (a) confirm the record layout and
(b) find where the player ID lives.
"""
import struct, sys, os

BASE = sys.argv[1] if len(sys.argv) > 1 else "/media/michael-g-thomas/sas_mirror/chess/pgn"
ROOT = "LumbrasGigaBase_OTB_ELO2400"

def u32(b, off): return struct.unpack_from("<I", b, off)[0]

def walk_lid():
    path = os.path.join(BASE, ROOT + ".2lid")
    data = open(path, "rb").read()
    print(f".2lid size = {len(data)}")
    # header is 0xb8 = 184 bytes (BE uint32 at offset 0)
    hdr = struct.unpack_from(">I", data, 0)[0]
    print(f"header field[0] (BE) = {hdr:#x} = {hdr}")
    off = hdr  # first record offset
    recs = []
    for i in range(30):
        if off + 4 > len(data):
            break
        length = u32(data, off)
        if length == 0 or length > 1000:
            print(f"  [record {i}] BAD length {length} at offset {off:#x}")
            break
        lastNameLen = u32(data, off + 4)
        lastName = data[off+8 : off+8+lastNameLen].decode("latin1", "replace")
        p = off + 8 + lastNameLen
        firstNameLen = u32(data, p)
        firstName = data[p+4 : p+4+firstNameLen].decode("latin1", "replace")
        # after name, find the sentinel + trailing fields
        q = p + 4 + firstNameLen
        # align q to 8
        q = (q + 7) & ~7
        sentinel = u32(data, q)
        idfield = u32(data, q + 4)
        recs.append((off, length, lastName, firstName, sentinel, idfield))
        off += length
    return recs

def main():
    recs = walk_lid()
    print(f"\nwalked {len(recs)} records")
    for off, length, ln, fn, sent, idf in recs:
        print(f"  off={off:#x} len={length} sent={sent:#x} id={idf}  {ln}, {fn}")

if __name__ == "__main__":
    main()
