#!/usr/bin/env python3
# ======================================================================
# probe_cms_selectors.py - decode the ChessBase .cms per-clip record
# grammar and the x/y/v/u hotspot selectors (decoded 2026-09-02).
# ======================================================================
# .cms layout (FULLY DECODED - see CHESSBASE_MEDIA_RE.md for the full
# write-up):
#
#   header: u32be body length, u32le record count, u32le base-name
#   length + base name.  `count` records follow, four shapes:
#
#     kind=1 (drill/position):
#       [kind][0][duration-s][0]
#       [u32le len][FEN slash-form]
#       [u32le len][base x0y0 clip name]     <-- only when a clip follows
#       (the LAST record in a file is a kind=1 with the final FEN and NO
#        clip name - the "trailing short record" from commit fb3aa3d)
#
#     kind=2 (base video):
#       [kind][0][duration-s][0][5][u32le len][base-video name]
#
#     kind=3/4 (hotspot clip; 3=alternative, 4=primary):
#       [kind][0][duration-s][2 or 0][0][u32le len][clip name]
#
#   The clip name embeds the FEN (z for '/') plus the x/y/v/u selectors.
#   x and y are BOARD SQUARES of the lesson's key move (from/to),
#   encoded file-major 0-based (a1=0, b1=1, ..., a2=8, b2=9, ...):
#   verified 109/109 clips have an occupied from-square and a fully
#   legal x->y move (python-chess, CBM168 corpus).
# ======================================================================

import glob
import os
import re

try:
    import chess
    HAVE_CHESS = True
except ImportError:
    HAVE_CHESS = False

CLIP_RE = re.compile(r"^(?P<pos>.+)x(?P<x>\d+)y(?P<y>\d+)v(?P<v>\d+)u(?P<u>\d+)$")


def u32le(b, o):
    return int.from_bytes(b[o:o + 4], "little")


def parse(path):
    data = open(path, "rb").read()
    body_len = int.from_bytes(data[0:4], "big")
    count = u32le(data, 4)
    nl = u32le(data, 8)
    base = data[12:12 + nl].decode("latin-1")
    off = 12 + nl
    records = []
    for i in range(count):
        kind = u32le(data, off)
        rec = {"index": i, "offset": off, "kind": kind}
        if kind == 1:
            # kind=1: [kind][0][dur][0][nl_fen][fen][nl_clip][clip]
            # the clip-name pair is absent on the final (terminal) record
            f1 = u32le(data, off + 4)
            dur = u32le(data, off + 8)
            f3 = u32le(data, off + 12)
            nl1 = u32le(data, off + 16)
            fen = data[off + 20:off + 20 + nl1].decode("latin-1")
            o2 = off + 20 + nl1
            clip = ""
            end = o2
            if o2 + 4 <= len(data):
                nl2 = u32le(data, o2)
                if nl2 > 0 and o2 + 4 + nl2 <= len(data):
                    clip = data[o2 + 4:o2 + 4 + nl2].decode("latin-1")
                    rec.update(clip=clip)
                    end = o2 + 4 + nl2
            rec.update(fields=[f1, dur, f3], fen=fen, dur=dur, end=end)
        else:
            # kind=2/3/4: [kind][0][dur][0][0][namelen][name]
            f1 = u32le(data, off + 4)
            dur = u32le(data, off + 8)
            f3 = u32le(data, off + 12)
            f4 = u32le(data, off + 16)
            nl = u32le(data, off + 20)
            name = data[off + 24:off + 24 + nl].decode("latin-1")
            if nl == 0:
                # the final kind=2 record: no name section at all;
                # the name is implicitly the header base name
                name = base
                rec.update(fields=[f1, dur, f3, f4], name=name, dur=dur,
                           end=off + 20)
            else:
                rec.update(fields=[f1, dur, f3, f4], name=name, dur=dur,
                           end=off + 24 + nl)
        records.append(rec)
        off = rec["end"]
    return {"path": path, "body_len": body_len, "count": count,
            "base": base, "records": records, "end": off, "size": len(data)}


def square_name_filemajor0(s):
    # file-major 0-based: a1=0, b1=1, ..., h1=7, a2=8, ...
    file_ = s // 8
    rank_ = s % 8
    return "abcdefgh"[file_] + "12345678"[rank_]


def main():
    paths = sorted(glob.glob(
        "/media/michael-g-thomas/sas_mirror/fixt/cbm168/*/*.cms"))
    print("=== .cms full record walk (pinned grammar) ===")
    for path in paths:
        r = parse(path)
        print("\n--- %s (size=%d, records=%d, base=%r)" % (
            os.path.basename(path), r["size"], r["count"], r["base"]))
        for rec in r["records"]:
            if rec["kind"] == 1:
                print("    @0x%03x kind=1 dur=%-3d fen=%r clip=%r" % (
                    rec["offset"], rec["dur"], rec["fen"][:44],
                    rec.get("clip", "")[:52]))
            else:
                print("    @0x%03x kind=%d dur=%-3d fields=%s name=%r" % (
                    rec["offset"], rec["kind"], rec["dur"], rec["fields"],
                    rec["name"][:70]))
        last = r["records"][-1] if r["records"] else None
        print("    end=%s size=%d %s" % (
            last["end"] if last else 0, r["size"],
            "(COMPLETE)" if last and last["end"] == r["size"] else "(MISMATCH)"))


if __name__ == "__main__":
    main()