#!/usr/bin/env python3
"""Decode the ASF ChessBase script stream used by WMV Chess Media files.

This is an analysis tool, not a playback implementation.  ChessBase stores
the stream-3 script payload as UTF-16LE-shaped characters from '?' through '~'.
Each character represents one six-bit value; four values produce three bytes.
"""

import argparse
import json
import re
import struct
import subprocess
import sys


HEX_LINE = re.compile(r"(?m)^........: ((?:[0-9a-f]{4} ?)+)")


def square_name(value):
    if value == 64:
        return "*"
    if value < 64:
        return f"{'abcdefgh'[value & 7]}{1 + (value >> 3)}"
    return f"#{value}"


def packet_bytes(data):
    raw = bytes.fromhex("".join(HEX_LINE.findall(data)).replace(" ", ""))
    text = raw.decode("utf-16le", "replace")
    if not text.startswith("GA\x00"):
        raise ValueError("missing GA transport prefix")
    encoded = text[3:].rstrip("\x00")
    values = [ord(char) - 0x3F for char in encoded]
    if any(value < 0 or value > 63 for value in values):
        raise ValueError("invalid six-bit character")

    result = bytearray()
    for offset in range(0, len(values) - 3, 4):
        value = (
            (values[offset] << 18)
            | (values[offset + 1] << 12)
            | (values[offset + 2] << 6)
            | values[offset + 3]
        )
        result.extend(value.to_bytes(3, "big"))
    complete_length = len(result)
    remainder = len(values) % 4
    if remainder == 1:
        raise ValueError("invalid one-character six-bit tail")
    if remainder >= 2:
        offset = len(values) - remainder
        result.append((values[offset] << 2) | (values[offset + 1] >> 4))
    if remainder == 3:
        result.append(((values[offset + 1] & 0x0F) << 4) | (values[offset + 2] >> 2))

    if complete_length < 4:
        return bytes(result)
    kind = struct.unpack_from("<I", result, 0)[0]
    fixed_lengths = {3: 6, 4: 12, 8: 6, 14: 6}
    logical_length = fixed_lengths.get(kind)
    if kind == 2:
        logical_length = complete_length
    elif kind == 6 and len(result) >= 10:
        count = struct.unpack_from("<H", result, 8)[0]
        logical_length = 10
        for _ in range(count):
            if logical_length + 2 > len(result):
                raise ValueError("truncated delta record length")
            length = struct.unpack_from("<H", result, logical_length)[0]
            logical_length += 2 + length
    if logical_length is not None:
        if logical_length > len(result):
            raise ValueError("truncated logical payload")
        if any(result[logical_length:]):
            raise ValueError("nonzero six-bit transport padding")
        del result[logical_length:]
    return bytes(result)


def packets(path):
    command = [
        "ffprobe", "-v", "error", "-select_streams", "2",
        "-show_packets", "-show_data", "-of", "json", path,
    ]
    document = json.loads(subprocess.check_output(command, text=True))
    for packet in document.get("packets", []):
        try:
            payload = packet_bytes(packet["data"])
        except (KeyError, ValueError, UnicodeError) as error:
            print(f"{packet.get('pts_time', '?')} decode-error: {error}", file=sys.stderr)
            continue
        yield packet.get("pts_time", "?"), int(packet.get("size", 0)), payload


def describe(payload):
    if len(payload) < 4:
        return "short=" + payload.hex()
    kind = struct.unpack_from("<I", payload, 0)[0]
    if kind == 2 and len(payload) >= 12:
        state = struct.unpack_from("<I", payload, 8)[0]
        strings = re.findall(rb"[ -~]{4,}", payload)
        names = ", ".join(item.decode("ascii", "replace") for item in strings[:8])
        return f"state kind=2 id=0x{state:x} decoded={len(payload)} strings=[{names}]"
    if kind == 3 and len(payload) >= 6:
        state = struct.unpack_from("<H", payload, 4)[0]
        return f"transition kind=3 id=0x{state:x} decoded={len(payload)}"
    if kind == 4 and len(payload) == 12 and payload[8] < 64 and payload[9] < 64:
        action = struct.unpack_from("<I", payload, 4)[0]
        first, second, modifier = struct.unpack_from("<BBH", payload, 8)
        return (
            f"board-action kind=4 class=0x{action:x} "
            f"squares={square_name(first)},{square_name(second)} "
            f"modifier=0x{modifier:x} decoded=12"
        )
    if kind == 6 and len(payload) >= 8:
        fields = []
        count = struct.unpack_from("<H", payload, 8)[0]
        offset = 10
        for _ in range(count):
            if offset + 8 > len(payload):
                fields.append("truncated-header")
                break
            length = struct.unpack_from("<H", payload, offset)[0]
            record_type = struct.unpack_from(">I", payload, offset + 2)[0]
            echoed_length = struct.unpack_from(">H", payload, offset + 6)[0]
            end = offset + 2 + length
            if length < 6 or end > len(payload):
                fields.append(f"type={record_type} truncated={length}")
                break
            value = payload[offset + 8:end]
            if record_type == 4 and len(value) % 2 == 0:
                items = [
                    f"{value[i]}:{square_name(value[i + 1])}"
                    for i in range(0, len(value), 2)
                ]
                rendered = f"squares=[{','.join(items)}]"
            elif record_type == 5 and len(value) % 3 == 0:
                items = [
                    f"{value[i]}:{square_name(value[i + 1])}-{square_name(value[i + 2])}"
                    for i in range(0, len(value), 3)
                ]
                rendered = f"arrows=[{','.join(items)}]"
            elif record_type == 130 and value.startswith(b"\x00\x00"):
                rendered = f"question={value[2:].decode('ascii', 'replace')!r}"
            elif record_type == 2 and value.startswith(b"\x00"):
                text = value[1:].lstrip(b"\x00").decode("cp1252")
                rendered = f"text={text!r}"
            elif record_type == 37 and len(value) == 4:
                rendered = f"time_ms={struct.unpack('>I', value)[0]}"
            elif record_type == 7 and len(value) == 4 and value[0] == value[3] == 0:
                rendered = f"index={value[1]} square={square_name(value[2])}"
            elif record_type == 34 and len(value) == 4:
                rendered = f"u32be={struct.unpack('>I', value)[0]}"
            elif record_type == 3 and len(value) in (1, 2):
                rendered = f"u{len(value) * 8}be={int.from_bytes(value, 'big')}"
            else:
                strings = re.findall(rb"[ -~]{4,}", value)
                if strings:
                    rendered = "text=" + repr(
                        " | ".join(item.decode("utf-8", "replace") for item in strings)
                    )
                else:
                    rendered = f"hex={value.hex()}"
            echo = "" if echoed_length == length else f" echoed={echoed_length}"
            fields.append(f"type={record_type} len={length}{echo} {rendered}")
            offset = end
        trailing = "" if offset == len(payload) else f" trailing={len(payload) - offset}"
        return (
            f"delta kind=6 count={count} decoded={len(payload)}{trailing} "
            f"fields=[{'; '.join(fields)}]"
        )
    if kind == 8 and payload == b"\x08\x00\x00\x00\x00\x00":
        return "reset-candidate kind=8 decoded=6"
    if kind == 14 and len(payload) == 6:
        counter = struct.unpack_from("<H", payload, 4)[0]
        return f"source-time kind=14 counter={counter} decoded=6"
    return f"kind={kind} decoded={len(payload)} head={payload[:16].hex()}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("wmv", help="ChessBase .wmv file")
    args = parser.parse_args()
    for timestamp, packet_size, payload in packets(args.wmv):
        print(f"{timestamp}\tpacket={packet_size}\t{describe(payload)}")


if __name__ == "__main__":
    main()
