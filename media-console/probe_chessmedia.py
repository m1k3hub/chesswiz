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
    if kind == 6 and len(payload) >= 8:
        fields = []
        offset = 8
        while offset + 4 <= len(payload):
            tag, length = struct.unpack_from("<HH", payload, offset)
            offset += 4
            if offset + length > len(payload):
                fields.append(f"tag={tag} truncated={length}")
                break
            value = payload[offset:offset + length]
            text = value.decode("utf-8", "replace")
            if text.isprintable() and text:
                fields.append(f"tag={tag} len={length} text={text!r}")
            else:
                fields.append(f"tag={tag} len={length} hex={value.hex()}")
            offset += length
        return f"container kind=6 decoded={len(payload)} fields=[{'; '.join(fields)}]"
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
