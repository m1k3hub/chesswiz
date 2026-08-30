#!/usr/bin/env python3
"""Extract the synchronization timeline of a ChessBase media script stream.

Reads the ASF script stream (stream 3) of a base `.wmv` Chess Media file
via ffprobe and writes a JSON sidecar describing the full lesson event
timeline. Squares are decoded to algebraic names (c8, e6, ...) using the
verified file-major conventions:

  node squares   — file-major zero-based (a1 = 0): checkpoint edge stream
  opcode-04      — file-major zero-based
  opcode-06 4/5  — file-major one-based (0 = none)

  nodes        — per-node media timestamps (type-37 ms) recovered from
                 the prefix checkpoint's searchable delta stream
  transitions  — opcode-03 id checkpoints (media time -> cursor id)
  board        — opcode-04 transient board actions (class + squares)
  deltas       — opcode-06 annotation records (marks/arrows/comments)
  checkpoints  — opcode-02 identity headers + per-state positions

The emitted JSON is the input contract for Scidb playback: at media
time t, apply the opcode-06 records and jump the game tree to cursor
id; the prefix node map provides the per-node media time for seeking.

Usage: wmv2timeline.py <base.wmv> [out.json]
"""

import json
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from probe_chessmedia import packets, checkpoint_header  # noqa: E402

FILESS = "abcdefgh"


def fm_square(v, one_based):
    """Decode a script-stream square (file-major) to algebraic form.

    Node-table and opcode-04 squares are zero-based file-major
    (a1 = 0, b1 = 8, a2 = 1); opcode-06 graphics are the same plus one
    (a1 = 1, h8 = 64).
    """
    v = v - (1 if one_based else 0)
    if not (0 <= v < 64):
        return None
    return FILESS[v // 8] + str((v % 8) + 1)


def split_delta(payload):
    """Split one opcode-06 payload into [(type, value_bytes)]."""
    out = []
    count = struct.unpack_from("<H", payload, 8)[0]
    offset = 10
    for _ in range(count):
        if offset + 8 > len(payload):
            break
        length = struct.unpack_from("<H", payload, offset)[0]
        if length < 6 or offset + 2 + length > len(payload):
            break
        rtype = struct.unpack_from(">I", payload, offset + 2)[0]
        out.append((rtype, payload[offset + 8:offset + 2 + length]))
        offset += 2 + length
    return out, offset


def timeline(wmv_path):
    events = []
    nodes = {}
    activation = {}
    for timestamp, packet_size, payload in packets(wmv_path):
        try:
            t = float(timestamp)
        except (TypeError, ValueError):
            continue
        if len(payload) < 6:
            continue
        kind = struct.unpack_from("<I", payload, 0)[0]
        if kind == 2 and len(payload) >= 16:
            state = struct.unpack_from("<I", payload, 8)[0]
            strings, date, end = checkpoint_header(payload)
            # deep annotation times live in the tail; record the header only
            events.append({"t": t, "kind": "checkpoint", "id": state,
                           "len": len(payload)})
            continue
        if kind == 3 and len(payload) >= 6:
            state = struct.unpack_from("<H", payload, 4)[0]
            events.append({"t": t, "kind": "transition", "id": state})
            continue
        if kind == 4 and len(payload) == 12:
            action = struct.unpack_from("<I", payload, 4)[0]
            events.append({"t": t, "kind": "board", "class": action,
                           "squares": [fm_square(payload[8], False),
                                       fm_square(payload[9], False)],
                           "modifier": payload[10]})
            continue
        if kind == 6:
            records, end = split_delta(payload)
            for rtype, value in records:
                if rtype == 37 and len(value) == 4:
                    ms = struct.unpack(">I", value)[0]
                    events.append({"t": t, "kind": "time", "ms": ms})
                elif rtype == 2 and len(value) >= 3:
                    events.append({"t": t, "kind": "comment", "text":
                                   value[2:].decode("cp1252", "replace")})
                elif rtype == 3 and 1 <= len(value) <= 3:
                    events.append({"t": t, "kind": "symbols",
                                   "glyphs": list(value)})
                elif rtype == 4 and len(value) % 2 == 0:
                    items = [(value[i], fm_square(value[i + 1], True))
                             for i in range(0, len(value), 2)]
                    events.append({"t": t, "kind": "marks", "items": items})
                elif rtype == 5 and len(value) % 3 == 0:
                    items = [(value[i], fm_square(value[i + 1], True),
                              fm_square(value[i + 2], True))
                             for i in range(0, len(value), 3)]
                    events.append({"t": t, "kind": "arrows", "items": items})
                else:
                    events.append({"t": t, "kind": f"r{rtype}",
                                   "hex": value.hex()})
            continue
        if kind == 8:
            events.append({"t": t, "kind": "reset"})
            continue
        if kind == 14 and len(payload) == 6:
            counter = struct.unpack_from("<H", payload, 4)[0]
            events.append({"t": t, "kind": "srctime", "n": counter})
    return events


def main():
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    wmv = sys.argv[1]
    events = timeline(wmv)
    summary = {
        "source": wmv,
        "counters": {"events": len(events)},
    }
    out = sys.argv[2] if len(sys.argv) > 2 else None
    text = json.dumps({"summary": summary, "events": events}, indent=1)
    if out:
        Path(out).write_text(text)
        print(f"wrote {out} ({len(events)} events)")
    else:
        print(text)


if __name__ == "__main__":
    main()