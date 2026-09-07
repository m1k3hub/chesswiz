#!/usr/bin/env python3
"""nodes.py - ChessBase Media Base-Tree Decoder and Game-Tree Navigator.

Decodes the serialized game-tree edge stream embedded in ChessBase Media
opcode-02 checkpoint records (from .txt sidecars or .wmv media script streams).
Replays all moves with python-chess, assigns verified node IDs matching
the playback transitions, and extracts per-node FENs and type-37 media timestamps.

File-major square encoding:
  square = file * 8 + rank  (0-based: a1=0, b1=8, c1=16 ... h8=63)
  algebraic: file = chr(ord('a') + (sq // 8)), rank = str((sq % 8) + 1)
"""

import argparse
import json
import os
import re
import struct
import subprocess
import sys
from typing import Any, Dict, List, Optional, Tuple

import chess


def decode_6bit(encoded: str) -> bytes:
    """Decode ChessBase six-bit ASCII-armored string to raw binary payload."""
    values = [ord(c) - 0x3F for c in encoded]
    result = bytearray()
    for offset in range(0, len(values) - 3, 4):
        value = (
            (values[offset] << 18)
            | (values[offset + 1] << 12)
            | (values[offset + 2] << 6)
            | values[offset + 3]
        )
        result.extend(value.to_bytes(3, "big"))
    remainder = len(values) % 4
    if remainder >= 2:
        offset = len(values) - remainder
        result.append((values[offset] << 2) | (values[offset + 1] >> 4))
    if remainder == 3:
        result.append(((values[offset + 1] & 0x0F) << 4) | (values[offset + 2] >> 2))
    return bytes(result)


def fm_to_chess_sq(val: int) -> chess.Square:
    """Convert file-major 0-based square (file * 8 + rank) to chess.Square."""
    file_idx = val // 8
    rank_idx = val % 8
    return chess.square(file_idx, rank_idx)


def chess_sq_to_fm(sq: chess.Square) -> int:
    """Convert chess.Square to file-major 0-based square (file * 8 + rank)."""
    return chess.square_file(sq) * 8 + chess.square_rank(sq)


def square_to_algebraic(val: int) -> str:
    """Convert file-major 0-based square to algebraic name (e.g. 'e4')."""
    return chess.square_name(fm_to_chess_sq(val))


def extract_checkpoint_from_txt(path: str) -> bytes:
    """Extract the final opcode-02 checkpoint payload from a .txt sidecar."""
    last_cp = None
    with open(path, "r", encoding="latin1") as f:
        for line in f:
            line = line.strip()
            if line.startswith("GA:"):
                raw = decode_6bit(line[3:])
                if len(raw) >= 4 and struct.unpack_from("<I", raw, 0)[0] == 2:
                    last_cp = raw
    if last_cp is None:
        raise ValueError(f"No opcode-02 checkpoint record found in {path}")
    return last_cp


def extract_checkpoint_from_wmv(path: str) -> bytes:
    """Extract the final opcode-02 checkpoint payload from a .wmv media file via ffprobe."""
    cmd = [
        "ffprobe", "-v", "error", "-select_streams", "2",
        "-show_packets", "-show_data", "-of", "json", path,
    ]
    try:
        out = subprocess.check_output(cmd, text=True)
    except Exception as e:
        raise RuntimeError(f"Failed to execute ffprobe on {path}: {e}")
    
    doc = json.loads(out)
    hex_re = re.compile(r"(?m)^........: ((?:[0-9a-f]{4} ?)+)")
    last_cp = None
    for pkt in doc.get("packets", []):
        data_str = pkt.get("data", "")
        raw_hex = bytes.fromhex("".join(hex_re.findall(data_str)).replace(" ", ""))
        try:
            text = raw_hex.decode("utf-16le", "replace")
        except Exception:
            continue
        if not text.startswith("GA\x00"):
            continue
        enc = text[3:].rstrip("\x00")
        raw = decode_6bit(enc)
        if len(raw) >= 4 and struct.unpack_from("<I", raw, 0)[0] == 2:
            last_cp = raw
            
    if last_cp is None:
        raise ValueError(f"No opcode-02 checkpoint record found in {path}")
    return last_cp


def extract_checkpoint(path: str) -> bytes:
    """Extract final checkpoint payload from either .txt or .wmv."""
    if path.endswith(".wmv"):
        return extract_checkpoint_from_wmv(path)
    return extract_checkpoint_from_txt(path)


class Node:
    """Represents a single node in the decoded ChessBase game tree."""

    def __init__(self, from_raw: int, to_raw: int, annots: List[Dict[str, Any]], raw_variations: List[List['Node']]):
        self.from_raw = from_raw
        self.to_raw = to_raw
        self.annots = annots
        self.raw_variations = raw_variations

        self.id: int = 0
        self.path: str = ""
        self.parent_id: Optional[int] = None
        self.is_mainline: bool = False
        self.from_sq: str = ""
        self.to_sq: str = ""
        self.uci: str = ""
        self.san: str = ""
        self.fen_before: str = ""
        self.fen: str = ""
        self.ms: Optional[int] = None
        self.variations: List[List['Node']] = []

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "path": self.path,
            "parent_id": self.parent_id,
            "is_mainline": self.is_mainline,
            "from_raw": self.from_raw,
            "to_raw": self.to_raw,
            "from_sq": self.from_sq,
            "to_sq": self.to_sq,
            "uci": self.uci,
            "san": self.san,
            "fen_before": self.fen_before,
            "fen": self.fen,
            "ms": self.ms,
            "time_sec": round(self.ms / 1000.0, 3) if self.ms is not None else None,
            "variation_count": len(self.variations),
            "variations": [[v.id for v in var_line] for var_line in self.variations],
        }


def parse_annotations(data: bytes, off: int, count: int) -> Tuple[List[Dict[str, Any]], int]:
    """Parse inline opcode-06 collections decorating a tree node."""
    annots = []
    for _ in range(count):
        rlen = struct.unpack_from("<H", data, off)[0]
        rtype = struct.unpack_from(">I", data, off + 2)[0]
        echo = struct.unpack_from(">H", data, off + 6)[0]
        payload = data[off + 8 : off + 2 + rlen]
        annots.append({"type": rtype, "echo": echo, "payload": payload})
        off += 2 + rlen
    return annots, off


def parse_node(data: bytes, off: int) -> Tuple[Node, int]:
    """Parse a single node and recursively parse all attached variations."""
    from_sq = data[off]
    to_sq = data[off + 1]
    annot_count = struct.unpack_from("<H", data, off + 2)[0]
    off += 4
    annots, off = parse_annotations(data, off, annot_count)
    var_count = data[off]
    off += 1
    variations = []
    for _ in range(var_count):
        var_len = struct.unpack_from("<I", data, off)[0]
        off += 4
        var_nodes = []
        for _ in range(var_len):
            vnode, off = parse_node(data, off)
            var_nodes.append(vnode)
        variations.append(var_nodes)
    node = Node(from_sq, to_sq, annots, variations)
    return node, off


def count_nodes(node_list: List[Node]) -> int:
    """Recursively count total nodes in a branch/list."""
    return len(node_list) + sum(sum(count_nodes(v) for v in n.raw_variations) for n in node_list)


def assign_variation_block(
    var_line: List[Node],
    start_id: int,
    end_id: int,
    node_dict: Dict[int, Node],
    parent_id: Optional[int],
    path_prefix: str = ""
):
    """Assign node IDs to a variation block adhering to reverse-hierarchical variation allocation."""
    curr_id = start_id
    subvars = []
    prev_id = parent_id
    for idx, node in enumerate(var_line):
        node.id = curr_id
        node.path = f"{path_prefix}/{idx+1}" if path_prefix else f"v/{idx+1}"
        node.parent_id = prev_id
        node.is_mainline = False
        node_dict[node.id] = node
        prev_id = node.id
        curr_id += 1
        for v_idx, subvar in enumerate(node.raw_variations):
            subvars.append((node.id, node.path, v_idx, subvar, count_nodes(subvar)))

    top_id = end_id
    for pid, pfx, v_idx, subvar, sz in subvars:
        assign_variation_block(
            subvar,
            top_id - sz + 1,
            top_id,
            node_dict,
            parent_id=pid,
            path_prefix=f"{pfx}.v{v_idx+1}"
        )
        top_id -= sz
    assert top_id == curr_id - 1, f"Variation block sizing mismatch: top_id={top_id}, curr_id-1={curr_id - 1}"


def decode_tree(cp_bytes: bytes) -> Dict[str, Any]:
    """Decode the complete game tree from an opcode-02 checkpoint payload."""
    if len(cp_bytes) < 231:
        raise ValueError(f"Checkpoint payload too short ({len(cp_bytes)} bytes)")

    main_ply_count = struct.unpack_from("<I", cp_bytes, 227)[0]
    offset = 231

    main_nodes: List[Node] = []
    for _ in range(main_ply_count):
        node, offset = parse_node(cp_bytes, offset)
        main_nodes.append(node)

    node_dict: Dict[int, Node] = {}

    prev_id = None
    for idx, node in enumerate(main_nodes):
        node.id = idx + 1
        node.path = f"main/{idx+1}"
        node.parent_id = prev_id
        node.is_mainline = True
        node_dict[node.id] = node
        prev_id = node.id

    current_var_start = main_ply_count + 1
    var_groups = []
    for idx in range(len(main_nodes) - 1, -1, -1):
        n = main_nodes[idx]
        if n.raw_variations:
            total_sz = sum(count_nodes(v) for v in n.raw_variations)
            var_groups.append((n.id, idx + 1, n.raw_variations, total_sz))

    for node_id, ply, v_list, total_sz in var_groups:
        block_start = current_var_start
        current_var_start += total_sz
        v_start = block_start
        var_parent_id = node_id - 1 if node_id > 1 else None
        for v_idx, v in enumerate(v_list):
            sz = count_nodes(v)
            assign_variation_block(
                v,
                v_start,
                v_start + sz - 1,
                node_dict,
                parent_id=var_parent_id,
                path_prefix=f"main/{ply}.v{v_idx+1}"
            )
            v_start += sz

    def replay_line(nodes: List[Node], board: chess.Board):
        b = board.copy()
        for n in nodes:
            from_sq = fm_to_chess_sq(n.from_raw)
            to_sq = fm_to_chess_sq(n.to_raw)
            piece = b.piece_at(from_sq)
            move = chess.Move(from_sq, to_sq)
            if piece and piece.piece_type == chess.PAWN:
                if (piece.color == chess.WHITE and chess.square_rank(to_sq) == 7) or \
                   (piece.color == chess.BLACK and chess.square_rank(to_sq) == 0):
                    move = chess.Move(from_sq, to_sq, promotion=chess.QUEEN)

            n.from_sq = chess.square_name(from_sq)
            n.to_sq = chess.square_name(to_sq)
            n.fen_before = b.fen()
            n.uci = move.uci()
            try:
                n.san = b.san(move)
            except Exception:
                n.san = move.uci()

            before_board = b.copy()
            b.push(move)
            n.fen = b.fen()

            for a in n.annots:
                if a["type"] == 37 and len(a["payload"]) >= 4:
                    n.ms = struct.unpack(">I", a["payload"][:4])[0]

            n.variations = n.raw_variations
            for v in n.variations:
                replay_line(v, before_board)

    start_board = chess.Board()
    replay_line(main_nodes, start_board)

    return {
        "main_ply_count": main_ply_count,
        "total_nodes": len(node_dict),
        "main_nodes": main_nodes,
        "node_dict": node_dict,
    }


def find_fen_in_tree(tree_data: Dict[str, Any], target_fen: str) -> List[Dict[str, Any]]:
    """Search for matching positions in the game tree (matching both board and FEN)."""
    clean_target = target_fen.strip()
    target_board_fen = clean_target.split(" ")[0]
    matches = []
    for nid, node in tree_data["node_dict"].items():
        node_board_fen = node.fen.split(" ")[0]
        if clean_target == node.fen:
            matches.append({"match_type": "exact", "node": node.to_dict()})
        elif target_board_fen == node_board_fen:
            matches.append({"match_type": "board_only", "node": node.to_dict()})
    return matches


def main():
    parser = argparse.ArgumentParser(description="Decode ChessBase game tree and node timeline.")
    parser.add_argument("input", help="Path to base .txt sidecar or .wmv media file")
    parser.add_argument("--json", action="store_true", help="Output complete tree nodes as JSON")
    parser.add_argument("--summary", action="store_true", help="Print summary statistics")
    parser.add_argument("--find-fen", metavar="FEN", help="Search for a specific FEN in the decoded tree")
    parser.add_argument("--out", metavar="FILE", help="Write JSON output to file")
    args = parser.parse_args()

    cp_bytes = extract_checkpoint(args.input)
    tree_data = decode_tree(cp_bytes)

    if args.find_fen:
        matches = find_fen_in_tree(tree_data, args.find_fen)
        print(f"Found {len(matches)} matches for FEN: {args.find_fen}")
        for m in matches:
            n = m["node"]
            print(f"  [{m['match_type'].upper()}] ID={n['id']} Path={n['path']} Move={n['san']} ({n['uci']}) Time={n['time_sec']}s")
            print(f"    FEN: {n['fen']}")
        return

    if args.summary or (not args.json and not args.out):
        print(f"=== ChessBase Game Tree Summary: {os.path.basename(args.input)} ===")
        print(f"Mainline plies: {tree_data['main_ply_count']}")
        print(f"Total nodes:    {tree_data['total_nodes']} ({tree_data['total_nodes'] - tree_data['main_ply_count']} variation nodes)")
        nodes_with_time = [n for n in tree_data["node_dict"].values() if n.ms is not None]
        print(f"Nodes with media timestamp: {len(nodes_with_time)}")
        if nodes_with_time:
            first_t = min(n.ms for n in nodes_with_time) / 1000.0
            last_t = max(n.ms for n in nodes_with_time) / 1000.0
            print(f"Timestamp range: {first_t:.1f}s to {last_t:.1f}s")
        print("\nSample Timeline Nodes (first 10 with media timestamps):")
        for n in sorted(nodes_with_time, key=lambda x: x.ms)[:10]:
            print(f"  ID {n.id:3d} | {n.path:16s} | {n.ms/1000:6.1f}s | {n.san:6s} | {n.fen[:45]}...")

    if args.json or args.out:
        out_dict = {
            "source": args.input,
            "main_ply_count": tree_data["main_ply_count"],
            "total_nodes": tree_data["total_nodes"],
            "nodes": {str(nid): node.to_dict() for nid, node in sorted(tree_data["node_dict"].items())},
        }
        json_str = json.dumps(out_dict, indent=2)
        if args.out:
            with open(args.out, "w") as f:
                f.write(json_str)
            print(f"Wrote {len(out_dict['nodes'])} nodes to {args.out}")
        else:
            print(json_str)


if __name__ == "__main__":
    main()
