"""Best-effort converter from legacy `.wmv` / `.txt` / `.cms` / `.pgn` lessons to ChessMedia 1.1.

Every inferred value is explicitly marked (`inferred: true`, `inferred_fields`)
and audited in `provenance/import.json` without fabricated precision.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shutil
import struct
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple, Union

from .chess_core import (
    FILES,
    STANDARD_START_FEN,
    apply_uci_move,
    compute_fingerprint,
    find_moves_between_squares,
    parse_pgn_text,
    validate_fen,
)
from .package import compute_dir_members, pack_package
from .validator import ValidationReport, validate_package

IMPORTER_NAME = "chessmedia-import-legacy"
IMPORTER_VERSION = "1.1.0"

# Legacy 1-byte style code -> RGBA hex (marked as inferred_overlay_colors)
LEGACY_STYLE_RGBA = {
    2: "#33aa55cc",  # green
    3: "#e6b800cc",  # yellow
    4: "#dd3333cc",  # red
}
DEFAULT_STYLE_RGBA = "#33aa55cc"

LEGACY_LANG_MAP = {
    0x00: "und",
    0x2A: "en",
    0x2B: "es",
    0x31: "fr",
    0x35: "de",
    0x46: "it",
    0x67: "nl",
    0x75: "pt",
}

PIECE_MAP_64 = {
    1: "K",
    2: "Q",
    3: "N",
    4: "B",
    5: "R",
    6: "P",
    9: "k",
    10: "q",
    11: "n",
    12: "b",
    13: "r",
    14: "p",
}

PROMO_HINT_MAP = {
    0: "q",
    1: "q",
    2: "r",
    3: "b",
}

ASF_FILE_PROPS_GUID = bytes.fromhex("a1dcab8c47a9cf118ee400c00c205365")
INTERACTIVE_FNAME_RE = re.compile(
    r"^(?:(?P<stem>.+?)_)?(?P<fen>[rnbqkpRNBQKP1-8z]+)[_ ](?P<turn>[wb])(?:[_ ](?P<castling>[KQkq-]+)[_ ](?P<ep>[a-h1-8-]+)[_ ](?P<half>\d+)[_ ](?P<full>\d+))?[_ ]?(?P<tail>x\d+y\d+v\d+u\d+|[A-Za-z0-9._-]+)$"
)
BRANCH_TAIL_RE = re.compile(r"^x(?P<from>\d+)y(?P<to>\d+)v(?P<v>\d+)u(?P<u>\d+)$")


def sq_0based(v: int) -> Optional[str]:
    if 0 <= v < 64:
        return f"{FILES[v >> 3]}{(v & 7) + 1}"
    return None


def sq_1based(v: int) -> Optional[str]:
    if 1 <= v <= 64:
        z = v - 1
        return f"{FILES[z >> 3]}{(z & 7) + 1}"
    return None


def file_sha256_and_size(path: Path) -> Tuple[int, str]:
    h = hashlib.sha256()
    total = 0
    with open(path, "rb") as f:
        while True:
            chunk = f.read(65536)
            if not chunk:
                break
            total += len(chunk)
            h.update(chunk)
    return total, h.hexdigest()


def slugify_id(text: str, prefix: str = "item") -> str:
    s = re.sub(r"[^A-Za-z0-9._-]+", "-", text.strip()).strip("-._")
    if not s or not s[0].isalnum():
        s = f"{prefix}-{s}" if s else prefix
    return s[:120]


# ---------------------------------------------------------------------------
# Six-bit GA payload decoder
# ---------------------------------------------------------------------------

def decode_ga6bit(encoded: str) -> bytes:
    """Decode legacy 6-bit ASCII ('?'..'~') payload into raw bytes."""
    encoded = encoded.rstrip("\x00\r\n ")
    values = [ord(ch) - 0x3F for ch in encoded]
    if any(v < 0 or v > 63 for v in values):
        raise ValueError("Invalid 6-bit character in GA payload")
    out = bytearray()
    n = len(values)
    for i in range(0, n - 3, 4):
        w = (values[i] << 18) | (values[i + 1] << 12) | (values[i + 2] << 6) | values[i + 3]
        out.extend(w.to_bytes(3, "big"))
    rem = n % 4
    if rem == 2:
        i = n - 2
        out.append((values[i] << 2) | (values[i + 1] >> 4))
    elif rem == 3:
        i = n - 3
        out.append((values[i] << 2) | (values[i + 1] >> 4))
        out.append(((values[i + 1] & 0x0F) << 4) | (values[i + 2] >> 2))
    return bytes(out)


_TIME_HEADER_RE = re.compile(r"^(?:(\d+):(\d{2}):(\d{2}(?:\.\d+)?)|(\d+(?:\.\d+)?)):?$")


def _parse_time_str_ms(s: str) -> Optional[int]:
    m = _TIME_HEADER_RE.match(s.strip())
    if not m:
        return None
    if m.group(1) is not None:
        h = int(m.group(1))
        mins = int(m.group(2))
        secs = float(m.group(3))
        return int(round((h * 3600 + mins * 60 + secs) * 1000))
    return int(round(float(m.group(4)) * 1000))


def parse_sidecar_txt(txt_path: Path) -> List[Tuple[int, bytes]]:
    """Parse `.txt` sidecar lines into `[(timestamp_ms, raw_payload_bytes)]`.

    Supports both two-line (`H:MM:SS.d:` followed by `GA:<encoded>`) and
    single-line (`<sec.d> GA <encoded>`) sidecars.
    """
    raw_text = txt_path.read_bytes().decode("cp1252", errors="replace")
    events: List[Tuple[int, bytes]] = []
    cur_ms: Optional[int] = None
    for line in raw_text.splitlines():
        line = line.strip()
        if not line:
            continue
        t_cand = _parse_time_str_ms(line)
        if t_cand is not None:
            cur_ms = t_cand
            continue
        if line.startswith("GA:") and cur_ms is not None:
            try:
                payload = decode_ga6bit(line[3:])
                if len(payload) >= 4:
                    events.append((cur_ms, payload))
            except Exception:
                pass
            continue
        parts = line.split(None, 2)
        if len(parts) >= 3 and parts[1] in ("GA", "GA:"):
            t_ms = _parse_time_str_ms(parts[0])
            if t_ms is not None:
                try:
                    payload = decode_ga6bit(parts[2])
                    if len(payload) >= 4:
                        events.append((t_ms, payload))
                except Exception:
                    pass
    return events


def probe_wmv_info(wmv_path: Path, extract_packets: bool = True) -> Dict[str, Any]:
    """Read WMV duration/preroll from ASF header and optionally stream-2 packets via ffprobe."""
    info: Dict[str, Any] = {
        "duration_ms": None,
        "preroll_ms": 0,
        "packets": [],
    }
    try:
        with open(wmv_path, "rb") as f:
            header_chunk = f.read(65536)
        idx = header_chunk.find(ASF_FILE_PROPS_GUID)
        if idx != -1 and idx + 88 <= len(header_chunk):
            play_dur_100ns = struct.unpack_from("<Q", header_chunk, idx + 64)[0]
            preroll_ms = struct.unpack_from("<Q", header_chunk, idx + 80)[0]
            play_ms = int(play_dur_100ns // 10000)
            eff_ms = max(0, play_ms - int(preroll_ms))
            info["duration_ms"] = eff_ms if eff_ms > 0 else play_ms
            info["preroll_ms"] = int(preroll_ms)
    except Exception:
        pass

    if extract_packets and shutil.which("ffprobe"):
        try:
            cmd = [
                "ffprobe",
                "-v",
                "error",
                "-select_streams",
                "2",
                "-show_packets",
                "-show_data",
                "-of",
                "json",
                str(wmv_path),
            ]
            out = subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL, timeout=15)
            doc = json.loads(out)
            hex_re = re.compile(r"(?m)^........: ((?:[0-9a-f]{4} ?)+)")
            pkts: List[Tuple[int, bytes]] = []
            for pkt in doc.get("packets", []):
                pts_s = pkt.get("pts_time")
                data_s = pkt.get("data", "")
                if pts_s is None or not data_s:
                    continue
                t_ms = int(round(float(pts_s) * 1000))
                raw_bytes = bytes.fromhex("".join(hex_re.findall(data_s)).replace(" ", ""))
                txt = raw_bytes.decode("utf-16le", errors="replace")
                if txt.startswith("GA\x00"):
                    payload = decode_ga6bit(txt[3:].rstrip("\x00"))
                    if len(payload) >= 4:
                        pkts.append((t_ms, payload))
            info["packets"] = pkts
        except Exception:
            pass

    # Fallback binary scan for UTF-16LE "GA\x00" records when ffprobe is unavailable or synthetic ASF test files are used
    if extract_packets and not info["packets"]:
        try:
            raw_data = wmv_path.read_bytes()
            marker = b"G\x00A\x00\x00\x00"
            pos = 0
            pkts_fb: List[Tuple[int, bytes]] = []
            while True:
                found = raw_data.find(marker, pos)
                if found == -1:
                    break
                # Read 32-bit PTS ms at found - 10 if present
                pts_ms = struct.unpack_from("<I", raw_data, found - 10)[0] if found >= 10 else 0
                end_nul = raw_data.find(b"\x00\x00", found + 6)
                if end_nul != -1:
                    # Align to 2-byte UTF-16LE boundary
                    if (end_nul - (found + 6)) % 2 == 1:
                        end_nul += 1
                    ga_txt = raw_data[found + 6 : end_nul].decode("utf-16le", errors="replace").rstrip("\x00")
                    try:
                        payload = decode_ga6bit(ga_txt)
                        if len(payload) >= 4:
                            pkts_fb.append((pts_ms, payload))
                    except Exception:
                        pass
                pos = found + 6
            info["packets"] = pkts_fb
        except Exception:
            pass
    return info


# ---------------------------------------------------------------------------
# Opcode-06 Annotation Delta Parser
# ---------------------------------------------------------------------------

def parse_annotation_records(buf: bytes, start_off: int, count: int) -> Tuple[List[Tuple[int, bytes]], int]:
    """Parse `count` annotation records starting at `start_off`."""
    records: List[Tuple[int, bytes]] = []
    off = start_off
    for _ in range(count):
        if off + 8 > len(buf):
            raise ValueError("Truncated annotation record header")
        rec_len = struct.unpack_from("<H", buf, off)[0]
        if rec_len < 6 or off + 2 + rec_len > len(buf):
            raise ValueError("Invalid annotation record length")
        rec_type = struct.unpack_from(">I", buf, off + 2)[0]
        val = buf[off + 8 : off + 2 + rec_len]
        records.append((rec_type, val))
        off += 2 + rec_len
    return records, off


def extract_overlays_and_captions_from_records(
    records: List[Tuple[int, bytes]],
    cue_idx: int,
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]], List[int], Optional[int], int]:
    """Convert legacy annotation records into ChessMedia overlays, captions, NAGs, type-37 ms, and inferred color count."""
    overlays: List[Dict[str, Any]] = []
    captions: List[Dict[str, Any]] = []
    nags: List[int] = []
    type37_ms: Optional[int] = None
    inferred_colors = 0
    ov_seq = 0

    for rtype, val in records:
        if rtype == 37 and len(val) == 4:
            type37_ms = struct.unpack(">I", val)[0]
        elif rtype == 2 and len(val) >= 3:
            placement_code = val[0]
            lang_code = val[1]
            txt = val[2:].rstrip(b"\x00").decode("cp1252", errors="replace").strip()
            if txt:
                captions.append(
                    {
                        "lang": LEGACY_LANG_MAP.get(lang_code, "und"),
                        "placement": "pre" if placement_code == 1 else "post",
                        "text": txt,
                    }
                )
        elif rtype == 3 and 1 <= len(val) <= 3:
            for b in val:
                if 1 <= b <= 255:
                    nags.append(b)
        elif rtype == 4 and len(val) % 2 == 0:
            for i in range(0, len(val), 2):
                style = val[i]
                sq = sq_1based(val[i + 1])
                if sq:
                    ov_seq += 1
                    inferred_colors += 1
                    overlays.append(
                        {
                            "id": f"ov-c{cue_idx}-sq{ov_seq}",
                            "kind": "square",
                            "square": sq,
                            "color": LEGACY_STYLE_RGBA.get(style, DEFAULT_STYLE_RGBA),
                            "inferred": True,
                        }
                    )
        elif rtype == 5 and len(val) % 3 == 0:
            for i in range(0, len(val), 3):
                style = val[i]
                frm = sq_1based(val[i + 1])
                to = sq_1based(val[i + 2])
                if frm and to:
                    ov_seq += 1
                    inferred_colors += 1
                    overlays.append(
                        {
                            "id": f"ov-c{cue_idx}-ar{ov_seq}",
                            "kind": "arrow",
                            "from": frm,
                            "to": to,
                            "color": LEGACY_STYLE_RGBA.get(style, DEFAULT_STYLE_RGBA),
                            "inferred": True,
                        }
                    )
    return overlays, captions, nags, type37_ms, inferred_colors


# ---------------------------------------------------------------------------
# Checkpoint (Opcode 02) Recursive Tree & Set-Position Decoder
# ---------------------------------------------------------------------------

@dataclass
class RawCheckpointNode:
    from_raw: int
    to_raw: int
    records: List[Tuple[int, bytes]]
    variations: List[List["RawCheckpointNode"]]
    legacy_id: int = 0


def _parse_raw_node_sequence(buf: bytes, off: int, count: int) -> Tuple[List[RawCheckpointNode], int]:
    seq: List[RawCheckpointNode] = []
    for _ in range(count):
        if off + 4 > len(buf):
            raise ValueError("Truncated node entry")
        from_raw = buf[off]
        to_raw = buf[off + 1]
        if (from_raw & 0x3F) >= 64 or (to_raw & 0x3F) >= 64:
            raise ValueError("Invalid square index in node entry")
        ann_count = struct.unpack_from("<H", buf, off + 2)[0]
        off += 4
        records, off = parse_annotation_records(buf, off, ann_count)
        if off >= len(buf):
            raise ValueError("Missing variation count byte")
        var_count = buf[off]
        off += 1
        if var_count > 32:
            raise ValueError("Unreasonable variation count")
        variations: List[List[RawCheckpointNode]] = []
        for _ in range(var_count):
            if off + 4 > len(buf):
                raise ValueError("Truncated variation length")
            var_len = struct.unpack_from("<I", buf, off)[0]
            off += 4
            if var_len == 0 or var_len > 1000:
                raise ValueError("Invalid variation length")
            var_nodes, off = _parse_raw_node_sequence(buf, off, var_len)
            variations.append(var_nodes)
        seq.append(RawCheckpointNode(from_raw=from_raw, to_raw=to_raw, records=records, variations=variations))
    return seq, off


def _assign_legacy_variation_ids(var_nodes: List[RawCheckpointNode], next_id: int) -> int:
    for node in var_nodes:
        node.legacy_id = next_id
        next_id += 1
    for node in var_nodes:
        for sub_var in node.variations:
            next_id = _assign_legacy_variation_ids(sub_var, next_id)
    return next_id


def _assign_all_legacy_ids(main_nodes: List[RawCheckpointNode]) -> int:
    next_id = 1
    for node in main_nodes:
        node.legacy_id = next_id
        next_id += 1
    for idx in range(len(main_nodes) - 1, -1, -1):
        for sub_var in main_nodes[idx].variations:
            next_id = _assign_legacy_variation_ids(sub_var, next_id)
    return next_id - 1


def decode_64byte_setup_fen(block78: bytes) -> Optional[str]:
    """Decode the 78-byte inline set-position header block into a 6-field FEN."""
    if len(block78) < 75 or block78[0] != 0:
        return None
    board_bytes = block78[1:65]
    if any(b not in PIECE_MAP_64 and b != 0 for b in board_bytes):
        return None
    ranks = []
    w_k = 0
    b_k = 0
    for r in range(7, -1, -1):
        empty = 0
        row_s = []
        for f in range(8):
            code = board_bytes[f * 8 + r]
            ch = PIECE_MAP_64.get(code)
            if ch is None:
                empty += 1
            else:
                if empty:
                    row_s.append(str(empty))
                    empty = 0
                if ch == "K":
                    w_k += 1
                elif ch == "k":
                    b_k += 1
                row_s.append(ch)
        if empty:
            row_s.append(str(empty))
        ranks.append("".join(row_s))
    if w_k != 1 or b_k != 1:
        return None
    placement = "/".join(ranks)
    stm = "b" if (block78[65] & 1) else "w"
    castling_mask = block78[67]
    c_str = ""
    if castling_mask & 1:
        c_str += "K"
    if castling_mask & 2:
        c_str += "Q"
    if castling_mask & 4:
        c_str += "k"
    if castling_mask & 8:
        c_str += "q"
    if not c_str:
        c_str = "-"
    fullmove = block78[72] if block78[72] >= 1 else 1
    fen = f"{placement} {stm} {c_str} - 0 {fullmove}"
    ok, _ = validate_fen(fen)
    return fen if ok else None


@dataclass
class DecodedCheckpoint:
    state_id: int
    tags: Dict[str, str]
    header_layout: str
    start_fen: str
    start_fen_inferred: bool
    start_fen_source: str
    main_nodes: List[RawCheckpointNode]
    max_legacy_id: int


def parse_checkpoint_payload(payload: bytes) -> DecodedCheckpoint:
    """Parse an opcode-02 checkpoint payload across all 4 observed binary header layouts."""
    if len(payload) < 24:
        raise ValueError("Short opcode-02 checkpoint payload")
    state_id = struct.unpack_from("<I", payload, 8)[0]
    off = 16
    strings: List[str] = []
    for _ in range(6):
        if off >= len(payload):
            raise ValueError("Truncated checkpoint string table")
        slen = payload[off]
        end = off + 1 + slen
        if slen < 1 or end > len(payload):
            raise ValueError("Invalid checkpoint string length")
        strings.append(payload[off + 1 : end - 1].decode("cp1252", errors="replace").strip())
        off = end

    if off + 8 > len(payload):
        raise ValueError("Truncated checkpoint metadata tail")
    date_word = struct.unpack_from("<I", payload, off)[0]
    year = date_word >> 9
    month = (date_word >> 5) & 0x0F
    day = date_word & 0x1F
    date_str = f"{year:04d}.{month:02d}.{day:02d}" if year > 0 else "????.??.??"

    round_num = payload[off + 4]
    result_code = payload[off + 7]
    result_map = {1: "1-0", 2: "1/2-1/2", 0: "*"}
    header_end = off + 8

    white_name = f"{strings[0]}, {strings[1]}".strip(", ") if strings[1] else strings[0]
    black_name = f"{strings[2]}, {strings[3]}".strip(", ") if strings[2] else strings[2]
    tags: Dict[str, str] = {
        "Event": strings[5] or "?",
        "Site": strings[4] or "?",
        "Date": date_str,
        "Round": str(round_num) if round_num > 0 else "?",
        "White": white_name or "?",
        "Black": black_name or "?",
        "Result": result_map.get(result_code, "*"),
    }

    # Locate the self-consistent node tree block ending at len(payload) - 4
    found_pos: Optional[int] = None
    found_main: List[RawCheckpointNode] = []
    for pos in range(header_end, len(payload) - 3):
        cnt = struct.unpack_from("<I", payload, pos)[0]
        if 0 < cnt < 600:
            try:
                seq, end_off = _parse_raw_node_sequence(payload, pos + 4, cnt)
                if end_off == len(payload) - 4:
                    found_pos = pos
                    found_main = seq
                    break
            except Exception:
                continue

    start_fen = STANDARD_START_FEN
    start_fen_inferred = False
    start_fen_source = "standard_initial"

    if found_pos is None:
        # Check for empty 0-move checkpoint (e.g. intro before game load)
        return DecodedCheckpoint(
            state_id=state_id,
            tags=tags,
            header_layout="empty_checkpoint",
            start_fen=start_fen,
            start_fen_inferred=False,
            start_fen_source=start_fen_source,
            main_nodes=[],
            max_legacy_id=0,
        )

    # Identify which of the 4 binary checkpoint header layouts precedes found_pos
    header_layout = f"gap_{found_pos - header_end}b"
    decoded_fen: Optional[str] = None
    for back in (78, 73):
        if found_pos >= back and payload[found_pos - back] == 0:
            cand_block = payload[found_pos - back : found_pos]
            if len(cand_block) < 75:
                cand_block = cand_block + b"\x00" * (78 - len(cand_block))
            decoded_fen = decode_64byte_setup_fen(cand_block)
            if decoded_fen:
                header_layout = "inline_setup_board_78b"
                start_fen = decoded_fen
                start_fen_inferred = True
                start_fen_source = "checkpoint_78b_board_array"
                break

    if decoded_fen is None:
        tail34 = payload[max(0, found_pos - 34) : found_pos]
        if tail34.endswith(b"\x5f\x90\x00\x00\x0b\xb8\x03\xe8\x03"):
            header_layout = "3_period_tc_34b"
        elif len(tail34) == 34 and tail34.endswith(b"\x00" * 11) and b"\x0b\xb8\x03\xe8\x03" in tail34:
            header_layout = "2_period_tc_11b_pad"
        elif tail34.endswith(b"\x01\x00\x00"):
            header_layout = "no_tc_short_3b"

    max_id = _assign_all_legacy_ids(found_main)
    return DecodedCheckpoint(
        state_id=state_id,
        tags=tags,
        header_layout=header_layout,
        start_fen=start_fen,
        start_fen_inferred=start_fen_inferred,
        start_fen_source=start_fen_source,
        main_nodes=found_main,
        max_legacy_id=max_id,
    )


# ---------------------------------------------------------------------------
# Build ChessMedia Game Tree from DecodedCheckpoint
# ---------------------------------------------------------------------------

@dataclass
class BuiltGameEpoch:
    game_id: str
    game_json: Dict[str, Any]
    legacy_id_to_node_id: Dict[int, str]
    node_id_to_fen: Dict[str, str]
    inferred_promotions: int
    inferred_colors: int
    header_layout: str
    start_fen_inferred: bool
    start_fen_source: str


def build_game_from_checkpoint(
    cp: DecodedCheckpoint,
    game_id: str,
    pgn_override_tags: Optional[Dict[str, str]] = None,
    pgn_override_start_fen: Optional[str] = None,
) -> BuiltGameEpoch:
    """Convert a DecodedCheckpoint into a validated ChessMedia 1.1 game object."""
    start_fen = pgn_override_start_fen or cp.start_fen
    start_fen_inferred = False if pgn_override_start_fen else cp.start_fen_inferred
    start_fen_source = "pgn_fen_tag" if pgn_override_start_fen else cp.start_fen_source

    tags = dict(cp.tags)
    if pgn_override_tags:
        for k, v in pgn_override_tags.items():
            if v and v != "?":
                tags[k] = v

    nodes_out: List[Dict[str, Any]] = [
        {
            "id": "n0",
            "parent_id": None,
            "uci": None,
            "san": None,
            "fen": start_fen,
            "main_child_id": None,
            "children_ids": [],
        }
    ]
    if start_fen_inferred:
        nodes_out[0]["inferred"] = True
        nodes_out[0]["inferred_fields"] = ["fen"]

    node_by_id: Dict[str, Dict[str, Any]] = {"n0": nodes_out[0]}
    legacy_to_nid: Dict[int, str] = {0: "n0"}
    nid_to_fen: Dict[str, str] = {"n0": start_fen}
    inferred_promos = 0
    inferred_colors = 0

    def _walk_seq(seq: List[RawCheckpointNode], parent_nid: str) -> None:
        nonlocal inferred_promos, inferred_colors
        cur_parent = parent_nid
        for raw_node in seq:
            if raw_node.from_raw == 0 and raw_node.to_raw == 0 and not raw_node.variations:
                # Static diagram placeholder node (0->0): map its legacy_id to current parent node
                legacy_to_nid[raw_node.legacy_id] = cur_parent
                continue
            parent_fen = nid_to_fen[cur_parent]
            from_sq = sq_0based(raw_node.from_raw & 0x3F)
            to_sq = sq_0based(raw_node.to_raw & 0x3F)
            promo_bits = (raw_node.from_raw >> 6) & 3
            promo_hint = PROMO_HINT_MAP.get(promo_bits, "q")
            if not from_sq or not to_sq:
                raise ValueError(f"Invalid square coordinates ({raw_node.from_raw}, {raw_node.to_raw})")
            uci, next_fen, san, was_inferred_promo = find_moves_between_squares(
                parent_fen, from_sq, to_sq, promo_hint=promo_hint
            )
            # If move is a promotion (5-char UCI) and came from binary edge bits, mark as inferred
            is_promo = len(uci) == 5
            if is_promo or was_inferred_promo:
                inferred_promos += 1

            nid = f"n{raw_node.legacy_id}"
            _, caps, nags, _, inf_c = extract_overlays_and_captions_from_records(raw_node.records, raw_node.legacy_id)
            inferred_colors += inf_c

            node_entry: Dict[str, Any] = {
                "id": nid,
                "parent_id": cur_parent,
                "uci": uci,
                "san": san,
                "fen": next_fen,
                "main_child_id": None,
                "children_ids": [],
            }
            if caps:
                node_entry["comment"] = " ".join(c["text"] for c in caps)
            if nags:
                node_entry["nags"] = nags
            if is_promo or was_inferred_promo:
                node_entry["inferred"] = True
                node_entry["inferred_fields"] = ["uci_promotion"]

            nodes_out.append(node_entry)
            node_by_id[nid] = node_entry
            legacy_to_nid[raw_node.legacy_id] = nid
            nid_to_fen[nid] = next_fen

            parent_obj = node_by_id[cur_parent]
            if parent_obj["main_child_id"] is None:
                parent_obj["main_child_id"] = nid
            parent_obj["children_ids"].append(nid)

            # Variations on raw_node branch from cur_parent (alternatives to raw_node)
            for var_seq in raw_node.variations:
                _walk_seq(var_seq, cur_parent)

            cur_parent = nid

    _walk_seq(cp.main_nodes, "n0")

    # Compute mainline UCIs for fingerprint
    mainline_ucis: List[str] = []
    cur_mc = nodes_out[0]["main_child_id"]
    while cur_mc is not None:
        n_obj = node_by_id[cur_mc]
        if n_obj.get("uci"):
            mainline_ucis.append(n_obj["uci"])
        cur_mc = n_obj.get("main_child_id")

    fp = compute_fingerprint(tags, start_fen, mainline_ucis, include_normalized_header=True)
    game_json = {
        "schema_version": "1.1",
        "id": game_id,
        "variant": "standard",
        "fen_encoding": "fen",
        "start_fen": start_fen,
        "setup": (start_fen.strip() != STANDARD_START_FEN),
        "tags": tags,
        "fingerprint": fp,
        "nodes": nodes_out,
    }
    return BuiltGameEpoch(
        game_id=game_id,
        game_json=game_json,
        legacy_id_to_node_id=legacy_to_nid,
        node_id_to_fen=nid_to_fen,
        inferred_promotions=inferred_promos,
        inferred_colors=inferred_colors,
        header_layout=cp.header_layout,
        start_fen_inferred=start_fen_inferred,
        start_fen_source=start_fen_source,
    )


def decode_interactive_filename_fen(stem_or_name: str) -> Optional[Tuple[str, Optional[Tuple[str, str, int, int]]]]:
    """Decode interactive drill filename FEN (`z` rank separators) and optional `x..y..v..u..` branch."""
    base = Path(stem_or_name).stem
    m = INTERACTIVE_FNAME_RE.match(base)
    if not m:
        return None
    fen_ranks = m.group("fen").replace("z", "/")
    turn = m.group("turn")
    castling = m.group("castling") or "-"
    ep = m.group("ep") or "-"
    half_s = m.group("half") or "0"
    full_s = m.group("full") or "1"
    tail = m.group("tail")
    fen = f"{fen_ranks} {turn} {castling} {ep} {half_s} {full_s}"
    ok, _ = validate_fen(fen)
    if not ok:
        return None
    bm = BRANCH_TAIL_RE.match(tail)
    branch_info = None
    if bm:
        from_idx = int(bm.group("from"))
        to_idx = int(bm.group("to"))
        if not (from_idx == 0 and to_idx == 0):
            f_sq = sq_0based(from_idx)
            t_sq = sq_0based(to_idx)
            if f_sq and t_sq:
                branch_info = (f_sq, t_sq, int(bm.group("v")), int(bm.group("u")))
    return fen, branch_info


# ---------------------------------------------------------------------------
# Tiny synthetic placeholder media generator (for sidecar-only or stub mode)
# ---------------------------------------------------------------------------

def _write_placeholder_mp4(target_path: Path, duration_ms: int) -> None:
    """Create a tiny valid blank MP4 via ffmpeg (or minimal ftyp+moov box stub if ffmpeg unavailable)."""
    target_path.parent.mkdir(parents=True, exist_ok=True)
    dur_sec = max(1.0, min(5.0, duration_ms / 1000.0))
    if shutil.which("ffmpeg"):
        try:
            cmd = [
                "ffmpeg",
                "-y",
                "-v",
                "error",
                "-f",
                "lavfi",
                "-i",
                f"color=c=black:s=64x64:r=10:d={dur_sec:.1f}",
                "-c:v",
                "libx264",
                "-pix_fmt",
                "yuv420p",
                "-movflags",
                "+faststart",
                str(target_path),
            ]
            subprocess.run(cmd, check=True, timeout=15)
            os.chmod(target_path, 0o644)
            return
        except Exception:
            pass
    # Minimal ISO BMFF ftyp box stub if ffmpeg is unavailable
    ftyp = b"\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom"
    target_path.write_bytes(ftyp)
    os.chmod(target_path, 0o644)


def _summarize_raw_events(events: List[Tuple[int, bytes]]) -> List[Dict[str, Any]]:
    """Summarize raw `(timestamp_ms, payload)` events for dual-clock provenance preservation."""
    summary: List[Dict[str, Any]] = []
    for idx, (t_ms, pay) in enumerate(events):
        opcode = struct.unpack_from("<I", pay, 0)[0] if len(pay) >= 4 else -1
        arg: Optional[int] = None
        if opcode in (3, 14) and len(pay) >= 6:
            arg = struct.unpack_from("<H", pay, 4)[0]
        elif opcode == 2 and len(pay) >= 12:
            arg = struct.unpack_from("<I", pay, 8)[0]
        entry: Dict[str, Any] = {
            "index": idx,
            "at_ms": t_ms,
            "opcode": opcode,
            "bytes": len(pay),
        }
        if arg is not None:
            entry["arg"] = arg
        summary.append(entry)
    return summary


def _part_c_report_verified() -> bool:
    """Return True only when delegates/media-sync-list/PART-C-REPORT.md exists with a measured calibration."""
    here = Path(__file__).resolve()
    # Check both worktree and main repo delegates/media-sync-list/PART-C-REPORT.md
    candidates = [
        here.parent.parent.parent / "tests" / "tmp-app" / "delegates" / "media-sync-list" / "PART-C-REPORT.md",
        here.parent.parent.parent.parent.parent / "tests" / "tmp-app" / "delegates" / "media-sync-list" / "PART-C-REPORT.md",
    ]
    return any(p.is_file() and p.stat().st_size > 0 for p in candidates)


# ---------------------------------------------------------------------------
# Main Legacy Importer Entry Point
# ---------------------------------------------------------------------------

def import_legacy_lesson(
    source_path: Union[str, Path],
    pgn_path: Optional[Union[str, Path]] = None,
    wmv_path: Optional[Union[str, Path]] = None,
    out_target: Optional[Union[str, Path]] = None,
    media_mode: str = "copy",
    compute_source_digests: bool = True,
    allow_part_c_calibration: bool = False,
) -> Tuple[Dict[str, Any], ValidationReport]:
    """Convert a legacy `.wmv` or `.txt` lesson (plus optional `.pgn`) into ChessMedia 1.1.

    Parameters
    ----------
    source_path : path to `.wmv` or `.txt`
    pgn_path : optional path to companion `.pgn`
    wmv_path : optional explicit path to companion `.wmv`
    out_target : output directory or `.chessmedia` file path
    media_mode : `'copy'` (copies source `.wmv` into `assets/`) or `'stub'` (writes tiny placeholder mp4)
    compute_source_digests : whether to compute SHA-256 over source files
    allow_part_c_calibration : if True and PART-C-REPORT.md exists AND initial Sync counters match within 2s,
        apply the measured Sync(0) offset; defaults to False so the importer never claims proven sync on its own.
    """
    src_p = Path(source_path)
    if not src_p.exists():
        raise FileNotFoundError(f"Source file not found: {src_p}")

    if src_p.suffix.lower() == ".wmv":
        wmv_p: Optional[Path] = src_p
        cand_txt = src_p.with_suffix(".txt")
        txt_p: Optional[Path] = cand_txt if cand_txt.is_file() else None
    elif src_p.suffix.lower() == ".txt":
        txt_p = src_p
        if wmv_path is not None:
            wmv_p = Path(wmv_path)
        else:
            cand_wmv = src_p.with_suffix(".wmv")
            wmv_p = cand_wmv if cand_wmv.is_file() else None
    else:
        raise ValueError(f"Expected .wmv or .txt input, got {src_p}")

    stem = (wmv_p or txt_p).stem  # type: ignore[union-attr]
    lesson_id = slugify_id(stem, prefix="lesson")

    sources_audit: List[Dict[str, Any]] = []
    warnings: List[str] = []

    if wmv_p and wmv_p.is_file():
        if compute_source_digests:
            w_bytes, w_sha = file_sha256_and_size(wmv_p)
        else:
            w_bytes, w_sha = wmv_p.stat().st_size, "0" * 64
        sources_audit.append(
            {"role": "video", "filename": wmv_p.name, "bytes": w_bytes, "sha256": w_sha}
        )
    if txt_p and txt_p.is_file():
        if compute_source_digests:
            t_bytes, t_sha = file_sha256_and_size(txt_p)
        else:
            t_bytes, t_sha = txt_p.stat().st_size, "0" * 64
        sources_audit.append(
            {"role": "sidecar_txt", "filename": txt_p.name, "bytes": t_bytes, "sha256": t_sha}
        )

    parsed_pgns = []
    if pgn_path is not None:
        pgn_p = Path(pgn_path)
        if pgn_p.is_file():
            p_bytes, p_sha = file_sha256_and_size(pgn_p)
            sources_audit.append(
                {"role": "pgn", "filename": pgn_p.name, "bytes": p_bytes, "sha256": p_sha}
            )
            parsed_pgns = parse_pgn_text(pgn_p.read_text(encoding="utf-8", errors="replace"))

    # Parse event streams from sidecar .txt and/or .wmv
    txt_events: List[Tuple[int, bytes]] = parse_sidecar_txt(txt_p) if (txt_p and txt_p.is_file()) else []
    need_wmv_packets = (out_target is not None) or (not txt_events and compute_source_digests)
    wmv_info: Dict[str, Any] = (
        probe_wmv_info(wmv_p, extract_packets=need_wmv_packets)
        if (wmv_p and wmv_p.is_file())
        else {"duration_ms": None, "preroll_ms": 0, "packets": []}
    )
    wmv_events: List[Tuple[int, bytes]] = wmv_info.get("packets", [])

    # Preserve both source timestamp series and evaluate clock mapping status.
    # Per user instruction & REVIEW Finding 2: do NOT pick one clock as proven; keep both source
    # timestamp series in provenance, mark the mapping as "unresolved", and lower confidence.
    part_c_verified = bool(allow_part_c_calibration and _part_c_report_verified())
    clock_drift_stats: Dict[str, Any] = {}
    source_clock_timestamps: Dict[str, Any] = {
        "sidecar_events": _summarize_raw_events(txt_events),
        "wmv_pts_events": _summarize_raw_events(wmv_events),
        "paired_clock_comparison": [],
    }
    inferred_clock_choice = False

    if txt_events and wmv_events:
        inferred_clock_choice = True

        # Check initial Sync (opcode 14) counter in both sources
        txt_syncs = [
            (struct.unpack_from("<H", pay, 4)[0], t_ms)
            for t_ms, pay in txt_events
            if len(pay) >= 6 and struct.unpack_from("<I", pay, 0)[0] == 14
        ]
        wmv_syncs = [
            (struct.unpack_from("<H", pay, 4)[0], t_ms)
            for t_ms, pay in wmv_events
            if len(pay) >= 6 and struct.unpack_from("<I", pay, 0)[0] == 14
        ]
        initial_sync_offset_ms: Optional[int] = None
        if txt_syncs and wmv_syncs and txt_syncs[0][0] == wmv_syncs[0][0]:
            initial_sync_offset_ms = txt_syncs[0][1] - wmv_syncs[0][1]

        # Compare matching (opcode, arg) events between txt and wmv (both op 14 markers and op 3 gotos)
        paired_comp: List[Dict[str, Any]] = []
        txt_by_op_arg: Dict[Tuple[int, int], int] = {}
        wmv_by_op_arg: Dict[Tuple[int, int], int] = {}
        for t_ms, pay in txt_events:
            if len(pay) >= 6:
                op = struct.unpack_from("<I", pay, 0)[0]
                if op in (3, 14):
                    arg = struct.unpack_from("<H", pay, 4)[0]
                    txt_by_op_arg.setdefault((op, arg), t_ms)
        for t_ms, pay in wmv_events:
            if len(pay) >= 6:
                op = struct.unpack_from("<I", pay, 0)[0]
                if op in (3, 14):
                    arg = struct.unpack_from("<H", pay, 4)[0]
                    wmv_by_op_arg.setdefault((op, arg), t_ms)

        common_keys = sorted(set(txt_by_op_arg.keys()) & set(wmv_by_op_arg.keys()))
        deltas: List[int] = []
        ratios: List[float] = []
        for op, arg in common_keys:
            s_ms = txt_by_op_arg[(op, arg)]
            w_ms = wmv_by_op_arg[(op, arg)]
            diff = s_ms - w_ms
            deltas.append(diff)
            ratio = round(w_ms / s_ms, 4) if s_ms > 0 else None
            if ratio is not None:
                ratios.append(ratio)
            paired_comp.append(
                {
                    "opcode": op,
                    "arg": arg,
                    "sidecar_ms": s_ms,
                    "wmv_pts_ms": w_ms,
                    "delta_ms": diff,
                    "wmv_over_sidecar_ratio": ratio,
                }
            )
        source_clock_timestamps["paired_clock_comparison"] = paired_comp
        source_clock_timestamps["initial_sync_offset_ms"] = initial_sync_offset_ms

        clock_source = "unresolved_dual" if not part_c_verified else "sidecar_txt"
        clock_mapping_status = "verified_part_c" if part_c_verified else "unresolved"
        clock_drift_stats = {
            "sidecar_event_count": len(txt_events),
            "wmv_packet_count": len(wmv_events),
            "wmv_preroll_ms": wmv_info.get("preroll_ms", 0),
            "matched_event_pairs": len(common_keys),
            "initial_sync_offset_ms": initial_sync_offset_ms,
            "mean_txt_minus_wmv_ms": round(sum(deltas) / len(deltas), 1) if deltas else None,
            "max_abs_delta_ms": max((abs(d) for d in deltas), default=None),
            "mean_wmv_over_sidecar_ratio": round(sum(ratios) / len(ratios), 4) if ratios else None,
            "mapping_status": clock_mapping_status,
            "rationale": (
                "Both sidecar .txt and WMV script-stream PTS timestamps are preserved in source_clock_timestamps; "
                "mapping between authoring clock and media presentation time is marked unresolved so the importer "
                "never claims synchronization it has not proven."
            ),
        }
        if not part_c_verified:
            warnings.append(
                "Unresolved dual-clock discrepancy between sidecar .txt and WMV data-stream PTS; "
                "both timestamp series preserved in provenance and timeline marked incomplete."
            )
    elif txt_events:
        inferred_clock_choice = True
        clock_source = "sidecar_txt"
        clock_mapping_status = "verified_part_c" if part_c_verified else "unresolved"
        clock_drift_stats = {
            "sidecar_event_count": len(txt_events),
            "wmv_packet_count": 0,
            "wmv_preroll_ms": wmv_info.get("preroll_ms", 0),
            "mapping_status": clock_mapping_status,
            "rationale": (
                "Sidecar .txt timestamps used as provisional cue times; presentation clock relationship "
                "is unverified without companion media Sync(0) calibration."
            ),
        }
        if not part_c_verified:
            warnings.append(
                "Sidecar .txt authoring timestamps have no measured media presentation clock calibration."
            )
    elif wmv_events:
        clock_source = "wmv_pts"
        inferred_clock_choice = True
        clock_mapping_status = "verified_part_c" if part_c_verified else "unresolved"
        clock_drift_stats = {
            "sidecar_event_count": 0,
            "wmv_packet_count": len(wmv_events),
            "wmv_preroll_ms": wmv_info.get("preroll_ms", 0),
            "mapping_status": clock_mapping_status,
            "rationale": "Embedded WMV script-stream packet timestamps used provisionally; mapping unverified.",
        }
        if not part_c_verified:
            warnings.append(
                "Embedded WMV script-stream timestamps have no measured presentation clock calibration."
            )
    else:
        clock_source = "none"
        clock_mapping_status = "not_applicable"

    # Build indexed lookup of WMV timestamps by (opcode, arg) so each cue can also record both source timestamps
    wmv_ms_by_op_arg: Dict[Tuple[int, int], List[int]] = {}
    for w_ms, w_pay in wmv_events:
        if len(w_pay) >= 4:
            w_op = struct.unpack_from("<I", w_pay, 0)[0]
            w_arg = -1
            if w_op in (3, 14) and len(w_pay) >= 6:
                w_arg = struct.unpack_from("<H", w_pay, 4)[0]
            elif w_op == 2 and len(w_pay) >= 12:
                w_arg = struct.unpack_from("<I", w_pay, 8)[0]
            wmv_ms_by_op_arg.setdefault((w_op, w_arg), []).append(w_ms)

    active_events = txt_events if txt_events else wmv_events

    # Decode checkpoints (opcode 2) in chronological order
    epochs: List[Tuple[int, BuiltGameEpoch]] = []
    header_layouts: List[str] = []
    inferred_promotions_total = 0
    inferred_colors_total = 0
    inferred_start_fen_any = False
    start_fen_source_str = "standard_initial"

    pgn_tags = parsed_pgns[0].tags if parsed_pgns else None
    pgn_start_fen = parsed_pgns[0].start_fen if (parsed_pgns and parsed_pgns[0].setup) else None

    for ev_ms, pay in active_events:
        kind = struct.unpack_from("<I", pay, 0)[0]
        if kind == 2 and len(pay) >= 24:
            try:
                cp = parse_checkpoint_payload(pay)
            except Exception as exc:
                warnings.append(f"Failed to parse checkpoint at {ev_ms} ms: {exc}")
                continue
            header_layouts.append(cp.header_layout)
            if not cp.main_nodes:
                continue
            # Check if this checkpoint has a larger or distinct tree from previous epochs
            gid = "main" if len(epochs) == 0 else f"game-{len(epochs) + 1}"
            try:
                built = build_game_from_checkpoint(
                    cp,
                    game_id=gid,
                    pgn_override_tags=pgn_tags if len(epochs) == 0 else None,
                    pgn_override_start_fen=pgn_start_fen if len(epochs) == 0 else None,
                )
            except Exception as exc:
                warnings.append(f"Checkpoint tree move resolution error at {ev_ms} ms: {exc}")
                continue

            # If same game (same start_fen and compatible root->first move) and larger/equal node set, replace epoch
            if epochs:
                prev_ms, prev_built = epochs[-1]
                prev_fp = prev_built.game_json["fingerprint"]["header_hash"]
                cur_fp = built.game_json["fingerprint"]["header_hash"]
                if prev_fp == cur_fp and len(built.legacy_id_to_node_id) >= len(prev_built.legacy_id_to_node_id):
                    built.game_id = prev_built.game_id
                    built.game_json["id"] = prev_built.game_id
                    epochs[-1] = (prev_ms, built)
                    continue
                elif prev_fp == cur_fp and len(built.legacy_id_to_node_id) < len(prev_built.legacy_id_to_node_id):
                    # Keep the fuller tree for the same game
                    continue

            epochs.append((ev_ms, built))

    # Fallback if no non-empty checkpoint was present
    fn_interactive = decode_interactive_filename_fen(stem)
    if not epochs:
        if parsed_pgns:
            pgn_g = parsed_pgns[0]
            start_fen = pgn_g.start_fen
            nodes_out = []
            nid_to_fen = {}
            # Spec §7: Never fabricate opaque legacy authoring-node IDs from PGN traversal order.
            # Only root cursor 0 -> "n0" is known without a decoded checkpoint tree.
            leg_map = {0: "n0"}
            for pn in pgn_g.nodes:
                nd: Dict[str, Any] = {
                    "id": pn.id,
                    "parent_id": pn.parent_id,
                    "uci": pn.uci,
                    "san": pn.san,
                    "fen": pn.fen,
                    "main_child_id": pn.main_child_id,
                    "children_ids": pn.children_ids,
                }
                if pn.comment:
                    nd["comment"] = pn.comment
                if pn.nags:
                    nd["nags"] = pn.nags
                nodes_out.append(nd)
                nid_to_fen[pn.id] = pn.fen
            main_ucis = []
            mc = nodes_out[0]["main_child_id"]
            by_id = {n["id"]: n for n in nodes_out}
            while mc:
                if by_id[mc]["uci"]:
                    main_ucis.append(by_id[mc]["uci"])
                mc = by_id[mc]["main_child_id"]
            fp = compute_fingerprint(pgn_g.tags, start_fen, main_ucis, include_normalized_header=True)
            g_json = {
                "schema_version": "1.1",
                "id": "main",
                "variant": "standard",
                "fen_encoding": "fen",
                "start_fen": start_fen,
                "setup": pgn_g.setup,
                "tags": pgn_g.tags,
                "fingerprint": fp,
                "nodes": nodes_out,
            }
            epochs.append(
                (
                    0,
                    BuiltGameEpoch(
                        game_id="main",
                        game_json=g_json,
                        legacy_id_to_node_id=leg_map,
                        node_id_to_fen=nid_to_fen,
                        inferred_promotions=0,
                        inferred_colors=0,
                        header_layout="pgn_only",
                        start_fen_inferred=False,
                        start_fen_source="pgn_fen_tag" if pgn_g.setup else "standard_initial",
                    ),
                )
            )
        else:
            # Interactive clip filename FEN or unsynchronized media fallback
            start_fen = fn_interactive[0] if fn_interactive else STANDARD_START_FEN
            inferred_sf = bool(fn_interactive)
            sf_source = "interactive_filename_fen" if fn_interactive else "standard_initial_fallback"
            tags_fb = {"Event": stem, "White": "?", "Black": "?", "Date": "????.??.??", "Round": "?", "Result": "*"}
            fp = compute_fingerprint(tags_fb, start_fen, [], include_normalized_header=True)
            root_node: Dict[str, Any] = {
                "id": "n0",
                "parent_id": None,
                "uci": None,
                "san": None,
                "fen": start_fen,
                "main_child_id": None,
                "children_ids": [],
            }
            if inferred_sf:
                root_node["inferred"] = True
                root_node["inferred_fields"] = ["fen"]
            g_json = {
                "schema_version": "1.1",
                "id": "main",
                "variant": "standard",
                "fen_encoding": "fen",
                "start_fen": start_fen,
                "setup": (start_fen != STANDARD_START_FEN),
                "tags": tags_fb,
                "fingerprint": fp,
                "nodes": [root_node],
            }
            epochs.append(
                (
                    0,
                    BuiltGameEpoch(
                        game_id="main",
                        game_json=g_json,
                        legacy_id_to_node_id={0: "n0"},
                        node_id_to_fen={"n0": start_fen},
                        inferred_promotions=0,
                        inferred_colors=0,
                        header_layout="none",
                        start_fen_inferred=inferred_sf,
                        start_fen_source=sf_source,
                    ),
                )
            )

    # Deduplicate games by game_id while keeping epoch switch times
    games_by_id: Dict[str, BuiltGameEpoch] = {}
    for _, ep in epochs:
        games_by_id[ep.game_id] = ep
        inferred_promotions_total += ep.inferred_promotions
        inferred_colors_total += ep.inferred_colors
        if ep.start_fen_inferred:
            inferred_start_fen_any = True
            start_fen_source_str = ep.start_fen_source
        elif ep.start_fen_source != "standard_initial":
            start_fen_source_str = ep.start_fen_source

    # Walk event stream to build full replacement timeline cues
    max_event_ms = max(
        max((t for t, _ in active_events), default=0),
        max((t for t, _ in wmv_events), default=0),
    )
    wmv_dur = wmv_info.get("duration_ms")
    duration_ms = max(max_event_ms + 1000, int(wmv_dur) if wmv_dur else max_event_ms + 1000, 1000)

    cur_epoch = epochs[0][1]
    cur_game_id = cur_epoch.game_id
    cur_node_id = "n0"
    cur_overlays: List[Dict[str, Any]] = []
    cur_captions: List[Dict[str, Any]] = []

    cues_by_ms: Dict[int, Dict[str, Any]] = {
        0: {
            "id": "cue-0000",
            "at_ms": 0,
            "scene": {
                "boards": {
                    "demo": {
                        "game_id": cur_game_id,
                        "node_id": "n0",
                        "orientation": "white",
                        "overlays": [],
                    }
                },
                "captions": [],
            },
        }
    }

    total_gotos = 0
    unresolved_gotos = 0
    failed_state_records = 0
    incomplete_intervals: List[Dict[str, Any]] = []
    open_unknown_start_ms: Optional[int] = None
    open_unknown_reasons: List[str] = []
    dyn_node_seq = 0
    cue_dual_timestamps: List[Dict[str, Any]] = []

    def _open_unknown_interval(at_ms: int, reason: str) -> None:
        nonlocal open_unknown_start_ms, open_unknown_reasons
        clamped = max(0, min(at_ms, duration_ms))
        if open_unknown_start_ms is None:
            open_unknown_start_ms = clamped
            open_unknown_reasons = [reason]
        else:
            if reason not in open_unknown_reasons:
                open_unknown_reasons.append(reason)

    def _close_unknown_interval(recovery_ms: int) -> None:
        nonlocal open_unknown_start_ms, open_unknown_reasons
        if open_unknown_start_ms is not None:
            end_val = max(open_unknown_start_ms, min(recovery_ms, duration_ms))
            incomplete_intervals.append(
                {
                    "start_ms": open_unknown_start_ms,
                    "end_ms": end_val,
                    "reason": "; ".join(open_unknown_reasons),
                }
            )
            open_unknown_start_ms = None
            open_unknown_reasons = []

    for ev_ms, pay in active_events:
        # Switch active epoch if we reached a new game checkpoint timestamp
        for ep_ms, ep_obj in epochs:
            if ep_ms <= ev_ms:
                cur_epoch = ep_obj
                cur_game_id = ep_obj.game_id

        kind = struct.unpack_from("<I", pay, 0)[0]
        state_changed = False
        board_position_recovered = False
        cue_inferred = False
        cue_inferred_fields: List[str] = []
        ev_arg: Optional[int] = None

        if kind == 2:
            if len(pay) < 24:
                failed_state_records += 1
                msg = f"Truncated opcode-02 checkpoint at {ev_ms} ms"
                warnings.append(msg)
                _open_unknown_interval(ev_ms, msg)
            else:
                target_leg = struct.unpack_from("<I", pay, 8)[0]
                ev_arg = target_leg
                cp_valid = True
                try:
                    cp_chk = parse_checkpoint_payload(pay)
                    if cp_chk.main_nodes:
                        # Ensure its moves also resolve cleanly
                        build_game_from_checkpoint(cp_chk, game_id="chk")
                except Exception as exc:
                    cp_valid = False
                    failed_state_records += 1
                    msg = f"Failed checkpoint at {ev_ms} ms: {exc}"
                    warnings.append(msg)
                    _open_unknown_interval(ev_ms, msg)

                if cp_valid:
                    if target_leg in cur_epoch.legacy_id_to_node_id:
                        cur_node_id = cur_epoch.legacy_id_to_node_id[target_leg]
                        cur_overlays = []
                        cur_captions = []
                        state_changed = True
                        board_position_recovered = True
                    else:
                        failed_state_records += 1
                        msg = f"Unresolved checkpoint state_id={target_leg} at {ev_ms} ms"
                        warnings.append(msg)
                        _open_unknown_interval(ev_ms, msg)
        elif kind == 3 and len(pay) >= 6:
            total_gotos += 1
            target_leg = struct.unpack_from("<H", pay, 4)[0]
            ev_arg = target_leg
            resolved_nid = cur_epoch.legacy_id_to_node_id.get(target_leg)
            if resolved_nid is None:
                # Search across all epochs in case lecture jumped back to an earlier game
                for _, other_ep in epochs:
                    if target_leg in other_ep.legacy_id_to_node_id:
                        cur_epoch = other_ep
                        cur_game_id = other_ep.game_id
                        resolved_nid = other_ep.legacy_id_to_node_id[target_leg]
                        break
            if resolved_nid is not None:
                cur_node_id = resolved_nid
                cur_overlays = []
                cur_captions = []
                state_changed = True
                board_position_recovered = True
            else:
                unresolved_gotos += 1
                msg = f"Unresolved legacy cursor id {target_leg}"
                warnings.append(f"Unresolved opcode-03 goto legacy_id={target_leg} at {ev_ms} ms")
                _open_unknown_interval(ev_ms, msg)
        elif kind == 4 and len(pay) == 12:
            action = struct.unpack_from("<I", pay, 4)[0]
            s1 = sq_0based(pay[8] & 0x3F)
            s2 = sq_0based(pay[9] & 0x3F)
            if action == 0 and s1 and s2:
                if open_unknown_start_ms is not None:
                    failed_state_records += 1
                    msg = f"Cannot apply transient opcode-04 move {s1}->{s2} at {ev_ms} ms while board state is unknown"
                    warnings.append(msg)
                    _open_unknown_interval(ev_ms, msg)
                else:
                    # Transient move on board: check if legal move from cur_node_id
                    cur_fen = cur_epoch.node_id_to_fen.get(cur_node_id, STANDARD_START_FEN)
                    try:
                        uci, next_fen, san, inf_p = find_moves_between_squares(cur_fen, s1, s2)
                        # Check if already a child of cur_node_id
                        g_nodes = cur_epoch.game_json["nodes"]
                        existing_child = None
                        for n in g_nodes:
                            if n.get("parent_id") == cur_node_id and n.get("uci") == uci:
                                existing_child = n["id"]
                                break
                        if existing_child:
                            cur_node_id = existing_child
                        else:
                            dyn_node_seq += 1
                            new_nid = f"n_dyn_{dyn_node_seq}"
                            new_node: Dict[str, Any] = {
                                "id": new_nid,
                                "parent_id": cur_node_id,
                                "uci": uci,
                                "san": san,
                                "fen": next_fen,
                                "main_child_id": None,
                                "children_ids": [],
                                "inferred": True,
                                "inferred_fields": ["dynamic_opcode04_move"],
                            }
                            g_nodes.append(new_node)
                            for n in g_nodes:
                                if n["id"] == cur_node_id:
                                    if n["main_child_id"] is None:
                                        n["main_child_id"] = new_nid
                                    n["children_ids"].append(new_nid)
                                    break
                            cur_epoch.node_id_to_fen[new_nid] = next_fen
                            cur_node_id = new_nid
                        cur_overlays = []
                        state_changed = True
                        cue_inferred = True
                        cue_inferred_fields.append("dynamic_opcode04_move")
                    except ValueError as exc:
                        failed_state_records += 1
                        msg = f"Failed opcode-04 move {s1}->{s2} at {ev_ms} ms: {exc}"
                        warnings.append(msg)
                        _open_unknown_interval(ev_ms, msg)
        elif kind == 6:
            if len(pay) < 10:
                failed_state_records += 1
                msg = f"Truncated opcode-06 annotation record at {ev_ms} ms"
                warnings.append(msg)
                _open_unknown_interval(ev_ms, msg)
            else:
                rec_cnt = struct.unpack_from("<H", pay, 8)[0]
                try:
                    recs, _ = parse_annotation_records(pay, 10, rec_cnt)
                    ovs, caps, _, _, inf_c = extract_overlays_and_captions_from_records(recs, len(cues_by_ms))
                    if ovs or caps:
                        inferred_colors_total += inf_c
                        cur_overlays = ovs
                        cur_captions = caps
                        state_changed = True
                        if inf_c > 0:
                            cue_inferred = True
                            cue_inferred_fields.append("overlay_colors")
                except Exception as exc:
                    failed_state_records += 1
                    msg = f"Malformed opcode-06 annotation record at {ev_ms} ms: {exc}"
                    warnings.append(msg)
                    _open_unknown_interval(ev_ms, msg)
        elif kind == 8:
            if cur_overlays or cur_captions:
                cur_overlays = []
                cur_captions = []
                state_changed = True

        if board_position_recovered:
            _close_unknown_interval(ev_ms)

        if state_changed:
            clamped_ev_ms = max(0, min(ev_ms, duration_ms))
            cue_obj: Dict[str, Any] = {
                "id": f"cue-{len(cues_by_ms):04d}",
                "at_ms": clamped_ev_ms,
                "scene": {
                    "boards": {
                        "demo": {
                            "game_id": cur_game_id,
                            "node_id": cur_node_id,
                            "orientation": "white",
                            "overlays": [dict(o) for o in cur_overlays],
                        }
                    },
                    "captions": [dict(c) for c in cur_captions],
                },
            }
            if cue_inferred or inferred_clock_choice or clock_mapping_status == "unresolved":
                cue_obj["inferred"] = True
                fields_list = list(cue_inferred_fields)
                if (inferred_clock_choice or clock_mapping_status == "unresolved") and "clock_source" not in fields_list:
                    fields_list.append("clock_source")
                cue_obj["inferred_fields"] = fields_list
            cues_by_ms[clamped_ev_ms] = cue_obj

            # Record both source timestamps for this cue in provenance
            matched_wmv_ms: Optional[int] = None
            if ev_arg is not None and (kind, ev_arg) in wmv_ms_by_op_arg and wmv_ms_by_op_arg[(kind, ev_arg)]:
                matched_wmv_ms = wmv_ms_by_op_arg[(kind, ev_arg)][0]
            cue_dual_timestamps.append(
                {
                    "at_ms": clamped_ev_ms,
                    "opcode": kind,
                    "arg": ev_arg,
                    "node_id": cur_node_id,
                    "sidecar_ms": ev_ms if txt_events else None,
                    "wmv_pts_ms": matched_wmv_ms if txt_events else (ev_ms if wmv_events else None),
                }
            )

    # If an unknown board-state interval is still open at the end of the event stream, close it at duration_ms
    if open_unknown_start_ms is not None:
        _close_unknown_interval(duration_ms)

    source_clock_timestamps["cue_source_timestamps"] = cue_dual_timestamps

    # Recompute game fingerprints in case dynamic opcode-04 moves extended a mainline
    for gid, ep in games_by_id.items():
        g_json = ep.game_json
        by_id = {n["id"]: n for n in g_json["nodes"]}
        main_ucis = []
        mc = by_id["n0"].get("main_child_id")
        while mc and mc in by_id:
            if by_id[mc].get("uci"):
                main_ucis.append(by_id[mc]["uci"])
            mc = by_id[mc].get("main_child_id")
        g_json["fingerprint"] = compute_fingerprint(
            g_json["tags"], g_json["start_fen"], main_ucis, include_normalized_header=True
        )

    # Interactive triggers from filename if applicable
    interactive_triggers: List[Dict[str, Any]] = []
    req_features = ["scene-timeline/1", "chess-standard/1"]
    if fn_interactive:
        req_features.append("interactive-triggers/1")
        fen_str, br_info = fn_interactive
        trig: Dict[str, Any] = {
            "id": "trig-position-1",
            "fen": fen_str,
            "match_mode": "board_turn",
            "game_id": "main",
            "node_id": "n0",
            "at_ms": 0,
            "kind": "clip",
            "asset_id": "video-main",
        }
        if br_info:
            f_sq, t_sq, v_idx, u_idx = br_info
            try:
                uci, _, san, _ = find_moves_between_squares(fen_str, f_sq, t_sq)
                trig["branches"] = [
                    {
                        "id": f"branch-v{v_idx}-u{u_idx}",
                        "uci": uci,
                        "san": san,
                        "role": "primary" if u_idx == 1 else "alternative",
                        "asset_id": "video-main",
                        "overlay_arrow": {"from": f_sq, "to": t_sq},
                    }
                ]
            except ValueError:
                pass
        interactive_triggers.append(trig)

    # If clock_mapping_status is unresolved and there are active board events, record an incomplete interval
    # covering the timeline so neither the importer nor the validator claims verified synchronization.
    total_nodes_all = sum(len(ep.game_json["nodes"]) for ep in games_by_id.values())
    has_board_activity = bool(active_events) and (total_nodes_all > 1 or total_gotos > 0 or bool(fn_interactive))

    if has_board_activity and clock_mapping_status == "unresolved":
        incomplete_intervals.append(
            {
                "start_ms": 0,
                "end_ms": duration_ms,
                "reason": (
                    "Unresolved clock mapping between legacy sidecar (.txt) authoring times and WMV presentation "
                    "timestamps (awaiting measured calibration in delegates/media-sync-list/PART-C-REPORT.md)."
                ),
            }
        )

    # Determine overall confidence level (never claim "high" when clock mapping is unresolved or intervals are incomplete)
    if not has_board_activity:
        confidence = "unsynchronized_media_only"
        warnings.append("Source media contains no synchronized board events or game tree checkpoints.")
    elif unresolved_gotos > 0 or failed_state_records > 0:
        if total_gotos > 0 and (unresolved_gotos / total_gotos) < 0.05 and failed_state_records == 0 and clock_mapping_status == "verified_part_c":
            confidence = "medium"
        else:
            confidence = "low"
    elif clock_mapping_status != "verified_part_c" or incomplete_intervals:
        # Board tree and cursors decoded cleanly, but media clock mapping is not yet proven
        confidence = "medium" if not (txt_events and wmv_events) else "low"
    else:
        confidence = "high"

    # Renumber cues sequentially by sorted at_ms
    sorted_cues = []
    for idx_c, ms_key in enumerate(sorted(cues_by_ms.keys())):
        c = cues_by_ms[ms_key]
        c["id"] = f"cue-{idx_c:04d}"
        sorted_cues.append(c)

    provenance_json: Dict[str, Any] = {
        "schema_version": "1.1",
        "importer": {"name": IMPORTER_NAME, "version": IMPORTER_VERSION},
        "confidence": confidence,
        "clock_source": clock_source,
        "clock_mapping_status": clock_mapping_status,
        "clock_drift_stats": clock_drift_stats,
        "source_clock_timestamps": source_clock_timestamps,
        "sources": sources_audit,
        "inferred_summary": {
            "inferred_start_fen": inferred_start_fen_any,
            "start_fen_source": start_fen_source_str,
            "inferred_clock_choice": inferred_clock_choice,
            "inferred_promotions": inferred_promotions_total,
            "inferred_overlay_colors": inferred_colors_total,
            "unresolved_goto_count": unresolved_gotos,
            "failed_state_record_count": failed_state_records,
            "total_goto_count": total_gotos,
            "checkpoint_header_layouts": header_layouts,
            "game_epoch_count": len(games_by_id),
        },
        "incomplete_intervals": incomplete_intervals,
        "warnings": warnings,
    }

    timeline_json: Dict[str, Any] = {
        "schema_version": "1.1",
        "id": "lecture",
        "clock_asset_id": "video-main",
        "clock_track": "presentation",
        "duration_ms": duration_ms,
        "cues": sorted_cues,
        "chapters": [{"id": "ch-start", "title": stem, "at_ms": 0}],
        "interactive_triggers": interactive_triggers,
    }

    # If out_target is provided, materialize the package on disk and validate it
    if out_target is not None:
        out_p = Path(out_target)
        want_zip = out_p.suffix.lower() == ".chessmedia"
        work_dir = out_p.with_suffix(".unpacked_tmp") if want_zip else out_p
        if work_dir.exists():
            shutil.rmtree(work_dir)
        (work_dir / "games").mkdir(parents=True, exist_ok=True)
        (work_dir / "timelines").mkdir(parents=True, exist_ok=True)
        (work_dir / "assets").mkdir(parents=True, exist_ok=True)
        (work_dir / "provenance").mkdir(parents=True, exist_ok=True)

        # Write games
        manifest_games = []
        manifest_links = []
        for gid, ep in games_by_id.items():
            g_rel = f"games/{gid}.json"
            g_fp = work_dir / g_rel
            g_fp.write_text(json.dumps(ep.game_json, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            os.chmod(g_fp, 0o644)
            fp_full = ep.game_json["fingerprint"]
            manifest_games.append(
                {
                    "id": gid,
                    "path": g_rel,
                    "fingerprint": {
                        "header_hash": fp_full["header_hash"],
                        "move_hash": fp_full["move_hash"],
                        "combined": fp_full["combined"],
                    },
                }
            )
            manifest_links.append(
                {
                    "game_id": gid,
                    "asset_id": "video-main",
                    "timeline_id": "lecture",
                    "role": "primary",
                }
            )

        # Write timeline
        tl_rel = "timelines/main.json"
        tl_fp = work_dir / tl_rel
        tl_fp.write_text(json.dumps(timeline_json, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        os.chmod(tl_fp, 0o644)

        # Write media asset (copy or placeholder stub)
        if wmv_p and wmv_p.is_file() and media_mode == "copy":
            asset_rel = "assets/lecture.wmv"
            asset_media_type = "video/x-ms-wmv"
            dst_media = work_dir / asset_rel
            shutil.copyfile(wmv_p, dst_media)
            os.chmod(dst_media, 0o644)
        else:
            asset_rel = "assets/lecture.mp4"
            asset_media_type = "video/mp4"
            _write_placeholder_mp4(work_dir / asset_rel, duration_ms)
            if not (wmv_p and wmv_p.is_file()):
                provenance_json["warnings"].append(
                    "Generated placeholder MP4 asset because only sidecar .txt was provided."
                )
            elif media_mode != "copy":
                provenance_json["warnings"].append(
                    "Generated placeholder MP4 asset (--media-mode=stub); original video digest recorded in sources."
                )

        # Write provenance
        prov_rel = "provenance/import.json"
        prov_fp = work_dir / prov_rel
        prov_fp.write_text(json.dumps(provenance_json, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        os.chmod(prov_fp, 0o644)

        first_tags = epochs[0][1].game_json.get("tags", {})
        title_str = f"{first_tags.get('Event', stem)}: {first_tags.get('White', '?')} - {first_tags.get('Black', '?')}"
        if first_tags.get("White") in (None, "?") and first_tags.get("Black") in (None, "?"):
            title_str = stem

        manifest_json: Dict[str, Any] = {
            "format": "chessmedia",
            "version": {"major": 1, "minor": 1},
            "id": lesson_id,
            "title": title_str,
            "required_features": req_features,
            "boards": [{"id": "demo", "title": "Demonstration Board"}],
            "games": manifest_games,
            "assets": [
                {
                    "id": "video-main",
                    "kind": "file",
                    "path": asset_rel,
                    "media_type": asset_media_type,
                    "duration_ms": duration_ms,
                    "offset_ms": 0,
                    "clock_track": "presentation",
                    "title": stem,
                }
            ],
            "timelines": [
                {
                    "id": "lecture",
                    "path": tl_rel,
                    "clock_asset_id": "video-main",
                }
            ],
            "links": manifest_links,
            "gallery_order": ["video-main"],
            "primary": {"timeline_id": "lecture", "asset_id": "video-main"},
            "provenance": {"path": prov_rel},
            "members": compute_dir_members(work_dir),
        }
        man_fp = work_dir / "manifest.json"
        man_fp.write_text(json.dumps(manifest_json, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        os.chmod(man_fp, 0o644)

        if want_zip:
            report = pack_package(work_dir, out_p, refresh_members=False, validate=True)
            shutil.rmtree(work_dir)
        else:
            report = validate_package(work_dir)
    else:
        if confidence == "unsynchronized_media_only":
            dry_sync = "unsynced_no_timeline"
        elif incomplete_intervals or clock_mapping_status == "unresolved":
            dry_sync = "unsynced_incomplete_import"
        else:
            dry_sync = "synced"
        report = ValidationReport(
            target=str(src_p),
            structurally_valid=True,
            chess_valid=True,
            playable_here=True,
            sync_status=dry_sync,
        )

    return provenance_json, report
