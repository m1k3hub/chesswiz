#!/usr/bin/env python3
"""Corpus statistics for the opcode-06 ChessBase media record grammar.

Tests the CBA-annotation hypothesis (CHESSBASE_FORMAT_REFERENCES 4.4):
  type  2  = text after move  (0x02), leading u16be language code
  type  3  = symbols (move comment, position evaluation, prefix)
  type 34  = medal (0x22), u32be bitfield
  type 130 = text before move (0x82), leading u16be language code
  types 4/5/7 = graphics/objects with board squares

Also measures the square coordinate convention (a1=0 vs a1=1 with 0
sentinel) by correlating squares with textual board references.
"""

import collections
import re
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).with_name("probe_chessmedia.py").parent))
import probe_chessmedia as probe  # noqa: E402

FIXTURES = Path("/media/michael-g-thomas/sas_mirror/fixt/cbm168")
SQUARE_MENTION = re.compile(r"(?<![a-zA-Z0-9])([a-h][1-8])(?![a-zA-Z0-9])")


def value_of_square(name, one_based):
    file = ord(name[0]) - ord("a")
    rank = int(name[1]) - 1
    return file + 8 * rank + (1 if one_based else 0)


def parse_export(path):
    """Yield (timestamp, payload) for each GA command in a text export."""
    lines = path.read_text("cp1252", "replace").splitlines()
    timestamp = None
    for line in lines:
        if line.startswith("GA:"):
            payload = decode_command(line[3:])
            if payload is not None:
                yield timestamp, payload
        else:
            timestamp = line.rstrip(":")


def decode_command(encoded):
    values = [ord(ch) - 0x3F for ch in encoded]
    if any(v < 0 or v > 63 for v in values):
        return None
    result = bytearray()
    for offset in range(0, len(values) - 3, 4):
        packed = ((values[offset] << 18) | (values[offset + 1] << 12)
                  | (values[offset + 2] << 6) | values[offset + 3])
        result.extend(packed.to_bytes(3, "big"))
    remainder = len(values) % 4
    if remainder == 1:
        return None
    if remainder >= 2:
        offset = len(values) - remainder
        result.append((values[offset] << 2) | (values[offset + 1] >> 4))
    if remainder == 3:
        result.append(((values[offset + 1] & 0x0F) << 4) | (values[offset + 2] >> 2))
    if len(result) < 4:
        return bytes(result)
    kind = struct.unpack_from("<I", result, 0)[0]
    fixed = {3: 6, 4: 12, 8: 6, 14: 6}
    logical = fixed.get(kind)
    if kind == 2:
        logical = len(result)
    elif kind == 6 and len(result) >= 10:
        count = struct.unpack_from("<H", result, 8)[0]
        logical = 10
        for _ in range(count):
            if logical + 2 > len(result):
                return None
            logical += 2 + struct.unpack_from("<H", result, logical)[0]
    if logical is None or logical > len(result):
        return bytes(result)
    if any(result[logical:]):
        return None
    return bytes(result[:logical])


def delta_records(payload):
    """[(timestamp, record_type, value_bytes)] of one opcode-06 payload."""
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
        record_type = struct.unpack_from(">I", payload, offset + 2)[0]
        out.append(record_type)
        yield_type = record_type
        value = payload[offset + 8:offset + 2 + length]
        offsets = {"type": yield_type, "value": value}
        out[-1] = offsets
        offset += 2 + length
    return out


def main():
    exports = sorted(FIXTURES.rglob("*.txt"))
    stats = {
        "languages": collections.Counter(),
        "languages_130": collections.Counter(),
        "language_samples": collections.defaultdict(list),
        "type3_bytes": collections.defaultdict(collections.Counter),
        "type3_lengths": collections.Counter(),
        "type34": collections.Counter(),
        "styles4": collections.Counter(),
        "styles5": collections.Counter(),
        "coord_edges": collections.Counter(),
        "type7_meta": collections.Counter(),
        "mentions": {"total": 0,
                     "match0": collections.Counter(),
                     "match1": collections.Counter()},
    }
    c7_text_records = []
    for path in exports:
        for timestamp, payload in parse_export(path):
            if len(payload) < 10 or struct.unpack_from("<I", payload, 0)[0] != 6:
                continue
            records = delta_records(payload)
            squares = []
            texts = []
            for record in records:
                rtype, value = record["type"], record["value"]
                if rtype in (2, 130):
                    country = struct.unpack_from(">H", value)[0]
                    key = "languages" if rtype == 2 else "languages_130"
                    stats[key][country] += 1
                    text = value[2:].decode("cp1252", "replace")
                    if 4 <= len(text) <= 120:
                        bucket = stats["language_samples"]
                        bucket[(rtype, country)].append(text)
                    texts.append(text)
                elif rtype == 3:
                    stats["type3_lengths"][len(value)] += 1
                    for index, item in enumerate(value):
                        stats["type3_bytes"][index][item] += 1
                elif rtype == 34:
                    stats["type34"][struct.unpack(">I", value)[0]] += 1
                elif rtype == 4:
                    for i in range(0, len(value) - 1, 2):
                        stats["styles4"][value[i]] += 1
                        stats["coord_edges"][value[i + 1]] += 1
                        squares.append(value[i + 1])
                elif rtype == 5:
                    for i in range(0, len(value) - 2, 3):
                        stats["styles5"][value[i]] += 1
                        stats["coord_edges"][value[i + 1]] += 1
                        stats["coord_edges"][value[i + 2]] += 1
                        squares.extend(value[i + 1:i + 3])
                elif rtype == 7:
                    stats["type7_meta"][(value[0], value[1], value[3])] += 1
                    if len(value) >= 3 and value[2] < 64:
                        squares.append(value[2])
            # text-vs-square correlation inside the same delta
            joined = " ".join(texts)
            mentions = SQUARE_MENTION.findall(joined)
            stats["mentions"]["total"] += len(mentions)
            for name in mentions:
                for square in squares:
                    if square == value_of_square(name, False):
                        stats["mentions"]["match0"][name] += 1
                    if 0 < square == value_of_square(name, True):
                        stats["mentions"]["match1"][name] += 1
                    if square == 0:
                        stats["mentions"]["match1"]["<sentinel0>"] += 1
            if any("c7" == mention for block in texts
                   for mention in SQUARE_MENTION.findall(block)):
                c7_text_records.append((path.name, timestamp, records))

    print("== type 2 (post-text) language codes ==")
    for country, count in sorted(stats["languages"].items()):
        print(f"  0x{country:04x}: {count}")
    print("== type 130 (pre-text) language codes ==")
    for country, count in sorted(stats["languages_130"].items()):
        print(f"  0x{country:04x}: {count}")
    print("== type 3 symbol byte distribution by index ==")
    for index in sorted(stats["type3_bytes"]):
        counts = stats["type3_bytes"][index]
        print(f"  index {index}: " + ", ".join(
            f"0x{value:02x}x{count}" for value, count in counts.most_common(12)))
    print(f"  lengths: {dict(stats['type3_lengths'])}")
    print("== type 34 (medal?) values ==")
    for value, count in stats["type34"].most_common(10):
        print(f"  {value}: {count}")
    print(f"== type 4 styles: {dict(stats['styles4'])}")
    print(f"== type 5 styles: {dict(stats['styles5'])}")
    edges = stats["coord_edges"]
    print(f"== coordinates: 0 appears {edges.get(0, 0)}x, 64 appears "
          f"{edges.get(64, 0)}x, max={max(edges)}")
    print(f"== type 7 (lead, index, tail) top: {stats['type7_meta'].most_common(5)}")
    print(f"== text-square mentions: total={stats['mentions']['total']}")
    print(f"  a1=0 hits: {sum(stats['mentions']['match0'].values())} "
          f"{stats['mentions']['match0'].most_common(8)}")
    print(f"  a1=1 hits: {sum(stats['mentions']['match1'].values())} "
          f"{stats['mentions']['match1'].most_common(8)}")
    print("== 'knight into c7' records ==")
    for name, timestamp, records in c7_text_records[:8]:
        shapes = [(record["type"], record["value"].hex()[:40], len(record["value"]))
                  for record in records]
        print(f"  {name} @{timestamp}: {shapes}")


if __name__ == "__main__":
    main()