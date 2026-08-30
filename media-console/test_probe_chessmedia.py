import importlib.util
import struct
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).with_name("probe_chessmedia.py")
SPEC = importlib.util.spec_from_file_location("probe_chessmedia", MODULE_PATH)
PROBE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PROBE)


def packet_data(encoded):
    raw = ("GA\0" + encoded).encode("utf-16le")
    value = raw.hex()
    return "00000000: " + " ".join(value[i:i + 4] for i in range(0, len(value), 4))


def encode_six_bit(payload):
    bits = int.from_bytes(payload, "big")
    count = (len(payload) * 8 + 5) // 6
    padding = count * 6 - len(payload) * 8
    bits <<= padding
    return "".join(chr(0x3F + ((bits >> (6 * i)) & 0x3F)) for i in range(count - 1, -1, -1))


class PacketBytesTest(unittest.TestCase):
    def test_discards_zero_padding_after_fixed_record(self):
        self.assertEqual(
            PROBE.packet_bytes(packet_data("B_????w????")),
            bytes.fromhex("0e0000000e00"),
        )

    def test_restores_unpadded_delta_tail_from_declared_lengths(self):
        def record(record_type, payload):
            length = 6 + len(payload)
            return struct.pack("<H", length) + struct.pack(">IH", record_type, length) + payload

        payload = struct.pack("<IIH", 6, 0, 2)
        payload += record(5, bytes.fromhex("021a19020419"))
        payload += record(4, bytes.fromhex("0204"))
        encoded = encode_six_bit(payload)
        self.assertEqual(len(encoded) % 4, 2)
        self.assertEqual(PROBE.packet_bytes(packet_data(encoded)), payload)
        description = PROBE.describe(payload)
        self.assertIn(
            "type=5 len=12 arrows=[green:d2-d1,green:a4-d1]", description)
        self.assertIn("type=4 len=8 marks=[green:a4]", description)

    def test_decodes_type_two_text_as_windows_1252(self):
        text = b"\x00\x35wei\xdffeldriger L\xe4ufer"
        length = 6 + len(text)
        payload = struct.pack("<IIHH", 6, 0, 1, length)
        payload += struct.pack(">IH", 2, length) + text
        self.assertIn("comment=post:de:'weißfeldriger Läufer'",
                      PROBE.describe(payload))

    def test_decodes_checkpoint_identity_header(self):
        values = ["Navara", "David", "Adams", "Michael", "Biel", "48th Biel Festival 2015"]
        payload = struct.pack("<IIII", 2, 0, 24, 0)
        for value in values:
            encoded = value.encode("cp1252") + b"\x00"
            payload += bytes([len(encoded)]) + encoded
        payload += struct.pack("<I", (2015 << 9) | (7 << 5) | 25)
        strings, date, offset = PROBE.checkpoint_header(payload)
        self.assertEqual(strings, values)
        self.assertEqual(date, (2015, 7, 25))
        self.assertEqual(offset, len(payload))


if __name__ == "__main__":
    unittest.main()
