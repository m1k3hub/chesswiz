#!/usr/bin/env python3
"""cms_records.py - ChessBase Media (.cms) Index File Parser and Selector Decoder.

Parses ChessBase Media .cms index files, discriminating records by kind:
  kind 1: Drill / position chapter boundaries and terminal position
  kind 2: Base video segments
  kind 3: Alternative hotspot clips (f3 = 2)
  kind 4: Primary hotspot clips (f3 = 0)

Decodes hotspot selector keys:
  x: from-square (file-major 0-based: file * 8 + rank)
  y: to-square (file-major 0-based: file * 8 + rank)
  v, u: UI priority / view tier constants

Verifies move legality and computes SAN / UCI using python-chess against chapter FEN.
"""

import argparse
import json
import os
import re
import struct
import sys
from typing import Any, Dict, List, Optional, Tuple

import chess


def fm_to_chess_sq(val: int) -> chess.Square:
    """Convert file-major 0-based square (file * 8 + rank) to chess.Square."""
    file_idx = val // 8
    rank_idx = val % 8
    return chess.square(file_idx, rank_idx)


def square_to_algebraic(val: int) -> str:
    """Convert file-major 0-based square to algebraic name (e.g. 'e4')."""
    if val < 0 or val >= 64:
        return f"#{val}"
    return chess.square_name(fm_to_chess_sq(val))


def parse_clip_selectors(clip_name: str, chapter_fen: Optional[str] = None) -> Dict[str, Any]:
    """Extract and decode x/y/v/u selectors from a clip filename."""
    m = re.search(r"x(\d+)y(\d+)v(\d+)u(\d+)", clip_name)
    if not m:
        return {
            "has_selectors": False,
            "x": None,
            "y": None,
            "v": None,
            "u": None,
            "from_sq": None,
            "to_sq": None,
            "uci": None,
            "san": None,
            "is_legal": None,
        }

    x, y, v, u = int(m.group(1)), int(m.group(2)), int(m.group(3)), int(m.group(4))
    res: Dict[str, Any] = {
        "has_selectors": True,
        "x": x,
        "y": y,
        "v": v,
        "u": u,
        "from_sq": square_to_algebraic(x) if 0 <= x < 64 else None,
        "to_sq": square_to_algebraic(y) if 0 <= y < 64 else None,
        "uci": None,
        "san": None,
        "is_legal": None,
    }

    if chapter_fen and 0 <= x < 64 and 0 <= y < 64 and x != y:
        try:
            b = chess.Board(chapter_fen)
            from_sq = fm_to_chess_sq(x)
            to_sq = fm_to_chess_sq(y)
            piece = b.piece_at(from_sq)
            move = chess.Move(from_sq, to_sq)
            if piece and piece.piece_type == chess.PAWN:
                if (piece.color == chess.WHITE and chess.square_rank(to_sq) == 7) or \
                   (piece.color == chess.BLACK and chess.square_rank(to_sq) == 0):
                    move = chess.Move(from_sq, to_sq, promotion=chess.QUEEN)

            res["uci"] = move.uci()
            res["is_legal"] = move in b.legal_moves
            if res["is_legal"]:
                res["san"] = b.san(move)
            else:
                res["san"] = move.uci()
        except Exception:
            pass

    return res


def parse_cms(data_or_path: Any) -> Dict[str, Any]:
    """Parse a .cms file or raw binary buffer into structured records and chapters."""
    if isinstance(data_or_path, (str, bytes, os.PathLike)) and os.path.exists(str(data_or_path)):
        with open(data_or_path, "rb") as f:
            data = f.read()
        file_path = str(data_or_path)
    elif isinstance(data_or_path, (bytes, bytearray)):
        data = bytes(data_or_path)
        file_path = None
    else:
        raise TypeError("Expected file path or bytes buffer")

    if len(data) < 16:
        raise ValueError(f"File too small for .cms header ({len(data)} bytes)")

    body_len = struct.unpack_from(">I", data, 0)[0]
    record_count = struct.unpack_from("<I", data, 4)[0]
    base_name_len = struct.unpack_from("<I", data, 8)[0]
    base_name = data[12 : 12 + base_name_len].decode("latin1")
    off = 12 + base_name_len

    records: List[Dict[str, Any]] = []
    current_fen: Optional[str] = None

    for i in range(record_count):
        if off + 16 > len(data):
            raise ValueError(f"Unexpected EOF at record {i} (offset {off}, total {len(data)})")

        kind = struct.unpack_from("<I", data, off)[0]
        f1 = struct.unpack_from("<I", data, off + 4)[0]
        dur = struct.unpack_from("<I", data, off + 8)[0]
        f3 = struct.unpack_from("<I", data, off + 12)[0]

        rec: Dict[str, Any] = {
            "record_index": i,
            "kind": kind,
            "f1": f1,
            "duration_sec": dur,
            "f3": f3,
            "f4": 0,
            "clip": None,
            "fen": None,
        }

        if kind == 1:
            cur = off + 16
            nlen1 = struct.unpack_from("<I", data, cur)[0]
            fen = data[cur + 4 : cur + 4 + nlen1].decode("latin1")
            cur += 4 + nlen1
            clip = None
            if cur + 4 <= len(data):
                nlen2 = struct.unpack_from("<I", data, cur)[0]
                if nlen2 > 4 and cur + 4 + nlen2 <= len(data):
                    clip = data[cur + 4 : cur + 4 + nlen2].decode("latin1")
                    cur += 4 + nlen2
            rec["fen"] = fen
            rec["clip"] = clip
            current_fen = fen
            off = cur

        elif kind == 2:
            f4 = struct.unpack_from("<I", data, off + 16)[0]
            cur = off + 20
            clip = None
            if cur + 4 <= len(data):
                cand_len = struct.unpack_from("<I", data, cur)[0]
                if cand_len > 4 and cur + 4 + cand_len <= len(data):
                    cand_str = data[cur + 4 : cur + 4 + cand_len]
                    if all(32 <= b < 127 for b in cand_str):
                        clip = cand_str.decode("latin1")
                        cur += 4 + cand_len
            rec["f4"] = f4
            rec["clip"] = clip if clip else base_name
            off = cur

        elif kind in (3, 4):
            f4 = struct.unpack_from("<I", data, off + 16)[0]
            cur = off + 20
            nlen = struct.unpack_from("<I", data, cur)[0]
            clip = data[cur + 4 : cur + 4 + nlen].decode("latin1")
            cur += 4 + nlen
            rec["f4"] = f4
            rec["clip"] = clip
            rec["fen"] = current_fen
            off = cur
        else:
            raise ValueError(f"Unknown .cms record kind {kind} at record {i}, offset {off}")

        # Decode selectors if clip name is present
        if rec["clip"]:
            rec["selectors"] = parse_clip_selectors(rec["clip"], current_fen)
        else:
            rec["selectors"] = parse_clip_selectors("", current_fen)

        records.append(rec)

    # Group into logical chapters
    chapters = []
    current_chapter = None
    for r in records:
        if r["kind"] == 1:
            if current_chapter is not None:
                chapters.append(current_chapter)
            current_chapter = {
                "chapter_index": len(chapters),
                "fen": r["fen"],
                "duration_sec": r["duration_sec"],
                "base_clip": r["clip"],
                "hotspots": [],
            }
        elif r["kind"] in (3, 4) and current_chapter is not None:
            current_chapter["hotspots"].append(r)

    if current_chapter is not None:
        chapters.append(current_chapter)

    return {
        "file": file_path,
        "base_name": base_name,
        "body_len": body_len,
        "record_count": record_count,
        "chapter_count": len(chapters),
        "records": records,
        "chapters": chapters,
    }


def main():
    parser = argparse.ArgumentParser(description="Parse ChessBase .cms index file.")
    parser.add_argument("cms_file", help="Path to .cms index file")
    parser.add_argument("--json", action="store_true", help="Output full parse as JSON")
    parser.add_argument("--summary", action="store_true", help="Print human-readable summary")
    parser.add_argument("--out", metavar="FILE", help="Write JSON output to file")
    args = parser.parse_args()

    cms_data = parse_cms(args.cms_file)

    if args.summary or (not args.json and not args.out):
        print(f"=== .cms Index Summary: {os.path.basename(args.cms_file)} ===")
        print(f"Base Name:     {cms_data['base_name']}")
        print(f"Total Records: {cms_data['record_count']}")
        print(f"Chapters:      {cms_data['chapter_count']}")
        print("\nChapters & Clips:")
        for ch in cms_data["chapters"]:
            print(f"\n[Chapter {ch['chapter_index']}] Duration: {ch['duration_sec']}s")
            print(f"  FEN: {ch['fen']}")
            if ch["base_clip"]:
                print(f"  Prompt/Base: {ch['base_clip']}")
            print(f"  Hotspots ({len(ch['hotspots'])}):")
            for h in ch["hotspots"]:
                kind_str = "Primary (kind 4)" if h["kind"] == 4 else "Alternative (kind 3)"
                sel = h["selectors"]
                move_str = f"{sel['san']} ({sel['uci']})" if sel["san"] else "none"
                legal_str = "legal" if sel["is_legal"] else "illegal/unknown"
                print(f"    - {kind_str:22s} | {h['duration_sec']:3d}s | Move: {move_str:10s} [{legal_str}] | {h['clip']}")

    if args.json or args.out:
        json_str = json.dumps(cms_data, indent=2)
        if args.out:
            with open(args.out, "w") as f:
                f.write(json_str)
            print(f"Wrote CMS data to {args.out}")
        else:
            print(json_str)


if __name__ == "__main__":
    main()
