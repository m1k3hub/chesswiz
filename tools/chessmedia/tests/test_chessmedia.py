"""Comprehensive unit and integration tests for ChessMedia 1.1 reference tools.

Covers:
  - Branching variation trees & pack/unpack round-trip
  - Set-position start (`start_fen` & `setup: true`)
  - O(log N) seek-to-scene (`scene_at`) and overlay/caption expiry
  - Position-keyed interactive triggers (`clip`, `range`, `branch_prompt`)
  - First-class stream assets (`https://.../*.m3u8`) and `gallery_order`
  - Pure-Python chess fallback (`CHESSMEDIA_PURE_PYTHON=1`)
  - Hand-crafted legacy `.txt` + `.pgn` import with `provenance/import.json`
  - Exact validator error codes (`E_*`) across all 5 validation stages
"""

from __future__ import annotations

import copy
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from typing import Any, Dict, List

TOOLS_DIR = Path(__file__).resolve().parent.parent.parent
if str(TOOLS_DIR) not in sys.path:
    sys.path.insert(0, str(TOOLS_DIR))

from chessmedia.chess_core import (  # noqa: E402
    STANDARD_START_FEN,
    apply_uci_move,
    compute_fingerprint,
    parse_pgn_text,
    san_to_uci,
    validate_fen,
)
from chessmedia.chessmedia import main as cli_main  # noqa: E402
from chessmedia.legacy_import import import_legacy_lesson  # noqa: E402
from chessmedia.package import (  # noqa: E402
    compute_dir_members,
    inspect_package,
    pack_package,
    unpack_package,
)
from chessmedia.validator import scene_at_package, validate_package  # noqa: E402


def _encode_ga6bit(raw: bytes) -> str:
    """Encode raw bytes into legacy 6-bit ASCII ('?'..'~') for synthetic test fixtures."""
    out: List[str] = []
    n = len(raw)
    i = 0
    while i + 3 <= n:
        w = (raw[i] << 16) | (raw[i + 1] << 8) | raw[i + 2]
        out.append(chr(((w >> 18) & 0x3F) + 0x3F))
        out.append(chr(((w >> 12) & 0x3F) + 0x3F))
        out.append(chr(((w >> 6) & 0x3F) + 0x3F))
        out.append(chr((w & 0x3F) + 0x3F))
        i += 3
    rem = n - i
    if rem == 1:
        b0 = raw[i]
        out.append(chr(((b0 >> 2) & 0x3F) + 0x3F))
        out.append(chr(((b0 & 0x03) << 4) + 0x3F))
    elif rem == 2:
        b0, b1 = raw[i], raw[i + 1]
        out.append(chr(((b0 >> 2) & 0x3F) + 0x3F))
        out.append(chr((((b0 & 0x03) << 4) | ((b1 >> 4) & 0x0F)) + 0x3F))
        out.append(chr(((b1 & 0x0F) << 2) + 0x3F))
    return "".join(out)


def _generate_tiny_media(path: Path, fmt: str = "mp4") -> None:
    """Generate a tiny synthetic 0.5s 64x64 video via ffmpeg (or minimal stub)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if shutil.which("ffmpeg"):
        try:
            if fmt == "webm":
                cmd = [
                    "ffmpeg",
                    "-y",
                    "-v",
                    "error",
                    "-f",
                    "lavfi",
                    "-i",
                    "color=c=darkgreen:s=64x64:r=10:d=0.5",
                    "-c:v",
                    "libvpx",
                    "-b:v",
                    "32k",
                    str(path),
                ]
            else:
                cmd = [
                    "ffmpeg",
                    "-y",
                    "-v",
                    "error",
                    "-f",
                    "lavfi",
                    "-i",
                    "color=c=navy:s=64x64:r=10:d=0.5",
                    "-c:v",
                    "libx264",
                    "-pix_fmt",
                    "yuv420p",
                    str(path),
                ]
            subprocess.run(cmd, check=True, timeout=15)
            os.chmod(path, 0o644)
            return
        except Exception:
            pass
    path.write_bytes(b"\x00\x00\x00\x18ftypmp42\x00\x00\x00\x00mp42isom")
    os.chmod(path, 0o644)


class ChessMediaTestSuite(unittest.TestCase):
    tmpdir: Path
    sample_mp4: Path
    sample_webm: Path

    @classmethod
    def setUpClass(cls) -> None:
        cls.tmpdir = Path(tempfile.mkdtemp(prefix="chessmedia_test_"))
        cls.sample_mp4 = cls.tmpdir / "shared_tiny.mp4"
        cls.sample_webm = cls.tmpdir / "shared_tiny.webm"
        _generate_tiny_media(cls.sample_mp4, "mp4")
        _generate_tiny_media(cls.sample_webm, "webm")

    @classmethod
    def tearDownClass(cls) -> None:
        if cls.tmpdir.exists():
            shutil.rmtree(cls.tmpdir)

    def _build_base_package_dict(self) -> Dict[str, Any]:
        """Return a complete, valid multi-file ChessMedia 1.1 package dictionary."""
        tags = {
            "Event": "Test Variation Lesson",
            "Site": "Local",
            "Date": "2026.10.18",
            "Round": "1",
            "White": "Learner, Alice",
            "Black": "Instructor, Bob",
            "Result": "1-0",
        }
        start_fen = STANDARD_START_FEN
        f1, _, s1 = apply_uci_move(start_fen, "e2e4")
        f2_main, _, s2_main = apply_uci_move(f1, "e7e5")
        f3_main, _, s3_main = apply_uci_move(f2_main, "g1f3")
        f2_var, _, s2_var = apply_uci_move(f1, "c7c5")
        f3_var, _, s3_var = apply_uci_move(f2_var, "g1f3")

        fp = compute_fingerprint(tags, start_fen, ["e2e4", "e7e5", "g1f3"], include_normalized_header=True)

        game_json = {
            "schema_version": "1.1",
            "id": "main",
            "variant": "standard",
            "fen_encoding": "fen",
            "start_fen": start_fen,
            "setup": False,
            "tags": tags,
            "fingerprint": fp,
            "nodes": [
                {
                    "id": "n0",
                    "parent_id": None,
                    "uci": None,
                    "san": None,
                    "fen": start_fen,
                    "main_child_id": "n1",
                    "children_ids": ["n1"],
                },
                {
                    "id": "n1",
                    "parent_id": "n0",
                    "uci": "e2e4",
                    "san": s1,
                    "fen": f1,
                    "main_child_id": "n2",
                    "children_ids": ["n2", "n2_sicilian"],
                },
                {
                    "id": "n2",
                    "parent_id": "n1",
                    "uci": "e7e5",
                    "san": s2_main,
                    "fen": f2_main,
                    "main_child_id": "n3",
                    "children_ids": ["n3"],
                },
                {
                    "id": "n3",
                    "parent_id": "n2",
                    "uci": "g1f3",
                    "san": s3_main,
                    "fen": f3_main,
                    "main_child_id": None,
                    "children_ids": [],
                },
                {
                    "id": "n2_sicilian",
                    "parent_id": "n1",
                    "uci": "c7c5",
                    "san": s2_var,
                    "fen": f2_var,
                    "main_child_id": "n3_sicilian",
                    "children_ids": ["n3_sicilian"],
                    "comment": "The Sicilian response.",
                },
                {
                    "id": "n3_sicilian",
                    "parent_id": "n2_sicilian",
                    "uci": "g1f3",
                    "san": s3_var,
                    "fen": f3_var,
                    "main_child_id": None,
                    "children_ids": [],
                },
            ],
        }

        timeline_json = {
            "schema_version": "1.1",
            "id": "lecture",
            "clock_asset_id": "video-main",
            "clock_track": "presentation",
            "duration_ms": 30000,
            "cues": [
                {
                    "id": "cue-0000",
                    "at_ms": 0,
                    "scene": {
                        "boards": {
                            "demo": {
                                "game_id": "main",
                                "node_id": "n0",
                                "orientation": "white",
                                "overlays": [],
                            }
                        },
                        "captions": [{"lang": "en", "placement": "pre", "text": "Starting position."}],
                    },
                },
                {
                    "id": "cue-0001",
                    "at_ms": 5000,
                    "scene": {
                        "boards": {
                            "demo": {
                                "game_id": "main",
                                "node_id": "n1",
                                "orientation": "white",
                                "overlays": [
                                    {
                                        "id": "ov-arrow-e4",
                                        "kind": "arrow",
                                        "from": "e2",
                                        "to": "e4",
                                        "color": "#33aa55ff",
                                        "end_ms": 8000,
                                    },
                                    {
                                        "id": "ov-sq-e4",
                                        "kind": "square",
                                        "square": "e4",
                                        "color": "#33aa5580",
                                    },
                                ],
                            }
                        },
                        "captions": [
                            {
                                "lang": "en",
                                "placement": "post",
                                "text": "1.e4 controls d5 and f5.",
                                "end_ms": 9000,
                            }
                        ],
                    },
                },
                {
                    "id": "cue-0002",
                    "at_ms": 12000,
                    "scene": {
                        "boards": {
                            "demo": {
                                "game_id": "main",
                                "node_id": "n2_sicilian",
                                "orientation": "black",
                                "overlays": [
                                    {
                                        "id": "ov-lbl-c5",
                                        "kind": "label",
                                        "square": "c5",
                                        "text": "!",
                                        "color": "#e6b800ff",
                                    }
                                ],
                            }
                        },
                        "captions": [{"lang": "en", "placement": "post", "text": "Exploring 1...c5 sideline."}],
                    },
                },
                {
                    "id": "cue-0003",
                    "at_ms": 20000,
                    "scene": {
                        "boards": {
                            "demo": {
                                "game_id": "main",
                                "node_id": "n3",
                                "orientation": "white",
                                "overlays": [],
                            }
                        },
                        "captions": [],
                    },
                },
            ],
            "chapters": [
                {"id": "ch-intro", "title": "Introduction", "at_ms": 0},
                {"id": "ch-sideline", "title": "Sicilian Sideline", "at_ms": 12000},
            ],
            "interactive_triggers": [
                {
                    "id": "trig-after-e4",
                    "fen": f1,
                    "match_mode": "board_turn",
                    "game_id": "main",
                    "node_id": "n1",
                    "at_ms": 5000,
                    "kind": "branch_prompt",
                    "asset_id": "clip-reply",
                    "prompt": "Choose Black's response to 1.e4",
                    "branches": [
                        {
                            "id": "br-e5",
                            "uci": "e7e5",
                            "san": "e5",
                            "role": "primary",
                            "asset_id": "video-main",
                            "overlay_arrow": {"from": "e7", "to": "e5"},
                        },
                        {
                            "id": "br-c5",
                            "uci": "c7c5",
                            "san": "c5",
                            "role": "alternative",
                            "asset_id": "clip-reply",
                            "overlay_arrow": {"from": "c7", "to": "c5"},
                        },
                    ],
                }
            ],
        }

        manifest_json = {
            "format": "chessmedia",
            "version": {"major": 1, "minor": 1},
            "id": "test-lesson-1",
            "title": "Test Lesson 1: Variations, Triggers, and Streams",
            "language": "en",
            "required_features": [
                "scene-timeline/1",
                "chess-standard/1",
                "interactive-triggers/1",
                "stream-assets/1",
            ],
            "boards": [{"id": "demo", "title": "Main Demo Board"}],
            "games": [
                {
                    "id": "main",
                    "path": "games/main.json",
                    "fingerprint": {
                        "header_hash": fp["header_hash"],
                        "move_hash": fp["move_hash"],
                        "combined": fp["combined"],
                    },
                }
            ],
            "assets": [
                {
                    "id": "video-main",
                    "kind": "file",
                    "path": "assets/lecture.mp4",
                    "media_type": "video/mp4",
                    "duration_ms": 30000,
                    "offset_ms": 0,
                    "clock_track": "presentation",
                    "title": "Main Lecture MP4",
                },
                {
                    "id": "clip-reply",
                    "kind": "file",
                    "path": "assets/clip.webm",
                    "media_type": "video/webm",
                    "duration_ms": 5000,
                    "offset_ms": 0,
                    "clock_track": "presentation",
                    "title": "Sideline Drill Clip",
                },
                {
                    "id": "stream-hls",
                    "kind": "stream",
                    "uri": "https://stream.example.org/chessmedia/lesson1/master.m3u8",
                    "fallback_path": "assets/lecture.mp4",
                    "media_type": "application/vnd.apple.mpegurl",
                    "duration_ms": 30000,
                    "offset_ms": 0,
                    "clock_track": "presentation",
                    "live": False,
                    "title": "HLS Adaptive Stream",
                },
            ],
            "timelines": [
                {
                    "id": "lecture",
                    "path": "timelines/main.json",
                    "clock_asset_id": "video-main",
                }
            ],
            "links": [
                {
                    "game_id": "main",
                    "asset_id": "video-main",
                    "timeline_id": "lecture",
                    "role": "primary",
                },
                {
                    "game_id": "main",
                    "asset_id": "clip-reply",
                    "timeline_id": "lecture",
                    "role": "interactive-clip",
                },
                {
                    "game_id": "main",
                    "asset_id": "stream-hls",
                    "timeline_id": "lecture",
                    "role": "alternate-stream",
                },
            ],
            "gallery_order": ["video-main", "clip-reply", "stream-hls"],
            "primary": {"timeline_id": "lecture", "asset_id": "video-main"},
            "members": [],
        }

        return {
            "manifest": manifest_json,
            "games/main.json": game_json,
            "timelines/main.json": timeline_json,
        }

    def _materialize_pkg(self, name: str, pkg_dict: Dict[str, Any], refresh_members: bool = True) -> Path:
        pkg_dir = self.tmpdir / name
        if pkg_dir.exists():
            shutil.rmtree(pkg_dir)
        (pkg_dir / "games").mkdir(parents=True)
        (pkg_dir / "timelines").mkdir(parents=True)
        (pkg_dir / "assets").mkdir(parents=True)
        shutil.copyfile(self.sample_mp4, pkg_dir / "assets" / "lecture.mp4")
        shutil.copyfile(self.sample_webm, pkg_dir / "assets" / "clip.webm")

        for rel, obj in pkg_dict.items():
            if rel == "manifest":
                continue
            fp = pkg_dir / rel
            fp.parent.mkdir(parents=True, exist_ok=True)
            fp.write_text(json.dumps(obj, indent=2) + "\n", encoding="utf-8")

        manifest = copy.deepcopy(pkg_dict["manifest"])
        if refresh_members:
            manifest["members"] = compute_dir_members(pkg_dir)
        (pkg_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
        return pkg_dir

    def test_01_variations_tree_and_pack_unpack_roundtrip(self) -> None:
        pkg_dir = self._materialize_pkg("valid_variations", self._build_base_package_dict())
        report = validate_package(pkg_dir)
        self.assertTrue(report.valid, f"Expected valid package, got errors: {report.errors}")
        self.assertEqual(report.sync_status, "synced")
        self.assertEqual(report.summary["total_nodes"], 6)

        zip_path = self.tmpdir / "valid_variations.chessmedia"
        pack_rep = pack_package(pkg_dir, zip_path)
        self.assertTrue(pack_rep.valid)

        # Verify media files use ZIP_STORED and JSON files use ZIP_DEFLATED
        with zipfile.ZipFile(zip_path, "r") as zf:
            self.assertEqual(zf.getinfo("assets/lecture.mp4").compress_type, zipfile.ZIP_STORED)
            self.assertEqual(zf.getinfo("assets/clip.webm").compress_type, zipfile.ZIP_STORED)
            self.assertEqual(zf.getinfo("manifest.json").compress_type, zipfile.ZIP_DEFLATED)

        unpacked_dir = self.tmpdir / "unpacked_variations"
        unpack_rep = unpack_package(zip_path, unpacked_dir)
        self.assertTrue(unpack_rep.valid)

        # Test CLI validate & info
        import io
        import contextlib
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            self.assertEqual(cli_main(["validate", str(zip_path), "--json"]), 0)
            self.assertEqual(cli_main(["info", str(zip_path), "--seek-ms", "12500", "--json"]), 0)

    def test_02_set_position_start_fen(self) -> None:
        pkg_dict = self._build_base_package_dict()
        setup_fen = "8/8/4k3/8/4P3/4K3/8/8 w - - 0 1"
        f1, _, s1 = apply_uci_move(setup_fen, "e3d4")
        f2, _, s2 = apply_uci_move(f1, "e6d6")
        tags = pkg_dict["games/main.json"]["tags"]
        fp = compute_fingerprint(tags, setup_fen, ["e3d4", "e6d6"], include_normalized_header=True)
        pkg_dict["games/main.json"] = {
            "schema_version": "1.1",
            "id": "main",
            "variant": "standard",
            "fen_encoding": "fen",
            "start_fen": setup_fen,
            "setup": True,
            "tags": tags,
            "fingerprint": fp,
            "nodes": [
                {
                    "id": "n0",
                    "parent_id": None,
                    "uci": None,
                    "san": None,
                    "fen": setup_fen,
                    "main_child_id": "n1",
                    "children_ids": ["n1"],
                },
                {
                    "id": "n1",
                    "parent_id": "n0",
                    "uci": "e3d4",
                    "san": s1,
                    "fen": f1,
                    "main_child_id": "n2",
                    "children_ids": ["n2"],
                },
                {
                    "id": "n2",
                    "parent_id": "n1",
                    "uci": "e6d6",
                    "san": s2,
                    "fen": f2,
                    "main_child_id": None,
                    "children_ids": [],
                },
            ],
        }
        pkg_dict["manifest"]["games"][0]["fingerprint"] = {
            "header_hash": fp["header_hash"],
            "move_hash": fp["move_hash"],
            "combined": fp["combined"],
        }
        # Update timeline cues and triggers to reference valid nodes in this endgame tree
        pkg_dict["timelines/main.json"]["cues"] = pkg_dict["timelines/main.json"]["cues"][:2]
        pkg_dict["timelines/main.json"]["interactive_triggers"] = []

        pkg_dir = self._materialize_pkg("valid_setup_pos", pkg_dict)
        rep = validate_package(pkg_dir)
        self.assertTrue(rep.valid, f"Set-position package failed validation: {rep.errors}")
        sc0 = scene_at_package(pkg_dir, 0)
        self.assertEqual(sc0["boards"]["demo"]["fen"], setup_fen)
        sc1 = scene_at_package(pkg_dir, 6000)
        self.assertEqual(sc1["boards"]["demo"]["fen"], f1)

    def test_03_seek_to_scene_and_overlay_expiry(self) -> None:
        pkg_dir = self._materialize_pkg("seek_test", self._build_base_package_dict())

        # Seek forward to 6000 ms (inside cue-0001 at 5000 ms; arrow expires at 8000 ms, caption at 9000 ms)
        s_6000 = scene_at_package(pkg_dir, 6000)
        self.assertEqual(s_6000["cue_id"], "cue-0001")
        self.assertEqual(s_6000["boards"]["demo"]["node_id"], "n1")
        self.assertEqual(len(s_6000["boards"]["demo"]["overlays"]), 2)
        self.assertEqual(len(s_6000["captions"]), 1)
        self.assertIn("trig-after-e4", s_6000["matched_triggers"])

        # Seek to 8500 ms: arrow (end_ms=8000) expired, square (no end_ms) still active, caption (end_ms=9000) still active
        s_8500 = scene_at_package(pkg_dir, 8500)
        self.assertEqual(s_8500["cue_id"], "cue-0001")
        ov_ids = [o["id"] for o in s_8500["boards"]["demo"]["overlays"]]
        self.assertEqual(ov_ids, ["ov-sq-e4"])
        self.assertEqual(len(s_8500["captions"]), 1)

        # Seek to 9500 ms: caption (end_ms=9000) also expired
        s_9500 = scene_at_package(pkg_dir, 9500)
        self.assertEqual(len(s_9500["captions"]), 0)

        # Seek to 15000 ms: inside cue-0002 (Sicilian sideline, black orientation, label overlay)
        s_15000 = scene_at_package(pkg_dir, 15000)
        self.assertEqual(s_15000["cue_id"], "cue-0002")
        self.assertEqual(s_15000["boards"]["demo"]["node_id"], "n2_sicilian")
        self.assertEqual(s_15000["boards"]["demo"]["orientation"], "black")
        self.assertEqual(s_15000["boards"]["demo"]["overlays"][0]["kind"], "label")

        # Rewind back to 0 ms: clean initial state, no leftover overlays
        s_0 = scene_at_package(pkg_dir, 0)
        self.assertEqual(s_0["cue_id"], "cue-0000")
        self.assertEqual(s_0["boards"]["demo"]["node_id"], "n0")
        self.assertEqual(s_0["boards"]["demo"]["overlays"], [])

    def test_04_pure_python_chess_fallback(self) -> None:
        old_env = os.environ.get("CHESSMEDIA_PURE_PYTHON")
        try:
            os.environ["CHESSMEDIA_PURE_PYTHON"] = "1"
            pkg_dir = self._materialize_pkg("pure_py_pkg", self._build_base_package_dict())
            rep = validate_package(pkg_dir)
            self.assertTrue(rep.valid, f"Pure-Python validation failed: {rep.errors}")

            # Test castling, en-passant, promotion, checkmate, and PGN parsing in pure-Python mode
            pgn = """[Event "Mini Test"]
[White "A"]
[Black "B"]
[Result "1-0"]

1. e4 e5 2. Bc4 Nc6 (2... Nf6 3. d3) 3. Qh5 Nf6 4. Qxf7# 1-0
"""
            games = parse_pgn_text(pgn)
            self.assertEqual(len(games), 1)
            self.assertEqual(games[0].nodes[-1].san, "Qxf7#")

            # En-passant + promotion test
            ep_fen = "rnbqkbnr/ppp1pppp/8/3pP3/8/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2"
            ok, err = validate_fen(ep_fen)
            self.assertTrue(ok, err)
            next_f, _, san_ep = apply_uci_move(ep_fen, "e5d6")
            self.assertEqual(san_ep, "exd6")

            promo_fen = "8/P7/8/8/8/8/7k/4K3 w - - 0 1"
            _, _, san_pr = apply_uci_move(promo_fen, "a7a8n")
            self.assertEqual(san_pr, "a8=N")
        finally:
            if old_env is None:
                os.environ.pop("CHESSMEDIA_PURE_PYTHON", None)
            else:
                os.environ["CHESSMEDIA_PURE_PYTHON"] = old_env

    def test_05_legacy_import_synthetic_sidecar_and_pgn(self) -> None:
        # Build a synthetic opcode-02 checkpoint + opcode-03 transitions + opcode-06 annotations
        strings = [b"PlayerW\x00", b"Alice\x00", b"PlayerB\x00", b"Bob\x00", b"Biel\x00", b"Match\x00"]
        str_block = b"".join(bytes([len(s)]) + s for s in strings)
        date_word = (2025 << 9) | (7 << 5) | 20
        meta_tail = struct.pack("<IBBBB", date_word, 1, 0, 0, 1)
        # 3-byte no-TC gap: 01 00 00, then 2 mainline plies: e2e4 (from=33, to=35) and e7e5 (from=38, to=36)
        # Wait: file-major 0-based: e2 is file 4 * 8 + rank 1 = 33; e4 is 4 * 8 + 3 = 35
        # e7 is file 4 * 8 + rank 6 = 38; e5 is 4 * 8 + 4 = 36
        node1 = struct.pack("<BBHB", 33, 35, 0, 0)
        node2 = struct.pack("<BBHB", 38, 36, 0, 0)
        cp_payload = (
            struct.pack("<IIII", 2, 0, 0, 0)
            + str_block
            + meta_tail
            + b"\x01\x00\x00"
            + struct.pack("<I", 2)
            + node1
            + node2
            + b"\x00\x00\x00\x00"
        )
        op3_n1 = struct.pack("<IH", 3, 1)
        op3_n2 = struct.pack("<IH", 3, 2)
        # Opcode 6 square mark on e4 (1-based file-major: 35 + 1 = 36, green=2)
        val_mark = bytes([2, 36])
        rec_mark = struct.pack("<H", 6 + len(val_mark)) + struct.pack(">IH", 4, len(val_mark)) + val_mark
        op6_mark = struct.pack("<IIH", 6, 0, 1) + rec_mark
        op8_reset = struct.pack("<IH", 8, 0)

        txt_lines = [
            f"0.5 GA {_encode_ga6bit(cp_payload)}",
            f"2.0 GA {_encode_ga6bit(op3_n1)}",
            f"2.5 GA {_encode_ga6bit(op6_mark)}",
            f"5.0 GA {_encode_ga6bit(op8_reset)}",
            f"5.5 GA {_encode_ga6bit(op3_n2)}",
        ]
        txt_file = self.tmpdir / "synth_lesson.txt"
        txt_file.write_text("\n".join(txt_lines) + "\n", encoding="utf-8")

        pgn_file = self.tmpdir / "synth_lesson.pgn"
        pgn_file.write_text(
            '[Event "Match"]\n[Site "Biel"]\n[Date "2025.07.20"]\n[Round "1"]\n'
            '[White "PlayerW, Alice"]\n[Black "PlayerB, Bob"]\n[Result "1-0"]\n\n1. e4 e5 1-0\n',
            encoding="utf-8",
        )

        out_pkg = self.tmpdir / "synth_imported.chessmedia"
        prov, rep = import_legacy_lesson(txt_file, pgn_path=pgn_file, out_target=out_pkg, media_mode="stub")
        self.assertTrue(rep.valid, f"Imported package invalid: {rep.errors}")
        self.assertEqual(prov["confidence"], "high")
        self.assertEqual(prov["inferred_summary"]["unresolved_goto_count"], 0)
        self.assertEqual(prov["inferred_summary"]["total_goto_count"], 2)
        self.assertGreater(prov["inferred_summary"]["inferred_overlay_colors"], 0)

        info = inspect_package(out_pkg, seek_ms=3000)
        self.assertEqual(info["scene_at"]["boards"]["demo"]["node_id"], "n1")
        self.assertEqual(info["scene_at"]["boards"]["demo"]["san"], "e4")
        self.assertEqual(len(info["scene_at"]["boards"]["demo"]["overlays"]), 1)

    def test_06_exact_validator_error_codes(self) -> None:
        # 1. E_MANIFEST_MISSING
        empty_dir = self.tmpdir / "err_no_manifest"
        empty_dir.mkdir(exist_ok=True)
        rep = validate_package(empty_dir)
        self.assertIn("E_MANIFEST_MISSING", [e.code for e in rep.errors])

        # 2. E_ARCHIVE_UNSAFE_PATH
        unsafe_zip = self.tmpdir / "err_unsafe.chessmedia"
        with zipfile.ZipFile(unsafe_zip, "w") as zf:
            zf.writestr("../escape.json", "{}")
            zf.writestr("manifest.json", "{}")
        rep = validate_package(unsafe_zip)
        self.assertIn("E_ARCHIVE_UNSAFE_PATH", [e.code for e in rep.errors])

        # 3. E_MEMBER_HASH_MISMATCH & E_MEMBER_UNLISTED & E_MEMBER_MISSING
        pkg_dir = self._materialize_pkg("err_members", self._build_base_package_dict())
        (pkg_dir / "games" / "main.json").write_text(
            (pkg_dir / "games" / "main.json").read_text(encoding="utf-8") + "\n",
            encoding="utf-8",
        )
        (pkg_dir / "extra_unlisted.txt").write_text("unlisted", encoding="utf-8")
        rep = validate_package(pkg_dir)
        codes = {e.code for e in rep.errors}
        self.assertIn("E_MEMBER_HASH_MISMATCH", codes)
        self.assertIn("E_MEMBER_UNLISTED", codes)

        pkg_missing = self._materialize_pkg("err_missing_member", self._build_base_package_dict())
        (pkg_missing / "assets" / "clip.webm").unlink()
        rep = validate_package(pkg_missing)
        self.assertIn("E_MEMBER_MISSING", {e.code for e in rep.errors})

        # 4. E_JSON_SYNTAX (duplicate key)
        pkg_dup_key = self._materialize_pkg("err_dup_key", self._build_base_package_dict())
        (pkg_dup_key / "manifest.json").write_text('{"format": "chessmedia", "format": "chessmedia"}', encoding="utf-8")
        rep = validate_package(pkg_dup_key)
        self.assertIn("E_JSON_SYNTAX", {e.code for e in rep.errors})

        # 5. E_UNSUPPORTED_VERSION & E_UNSUPPORTED_FEATURE & E_SCHEMA_VIOLATION
        d = self._build_base_package_dict()
        d["manifest"]["version"] = {"major": 2, "minor": 0}
        d["manifest"]["required_features"].append("quantum-chess/99")
        d["manifest"]["unknown_top_field"] = 123
        rep = validate_package(self._materialize_pkg("err_ver_feat", d))
        codes = {e.code for e in rep.errors}
        self.assertIn("E_UNSUPPORTED_VERSION", codes)
        self.assertIn("E_UNSUPPORTED_FEATURE", codes)
        self.assertIn("E_SCHEMA_VIOLATION", codes)

        # 6. E_DUPLICATE_ID, E_REF_UNKNOWN, E_GALLERY_INVALID, E_STREAM_URI_INVALID
        d = self._build_base_package_dict()
        d["manifest"]["boards"].append({"id": "demo"})
        d["manifest"]["links"].append({"game_id": "nonexistent-game", "asset_id": "video-main"})
        d["manifest"]["gallery_order"] = ["unknown-asset"]
        d["manifest"]["assets"][2]["uri"] = "ftp://bad.example.org/stream.m3u8"
        rep = validate_package(self._materialize_pkg("err_refs", d))
        codes = {e.code for e in rep.errors}
        self.assertIn("E_DUPLICATE_ID", codes)
        self.assertIn("E_REF_UNKNOWN", codes)
        self.assertIn("E_GALLERY_INVALID", codes)
        self.assertIn("E_STREAM_URI_INVALID", codes)

        # 7. E_START_FEN_INVALID
        d = self._build_base_package_dict()
        d["games/main.json"]["start_fen"] = "8/8/8/8/8/8/8/8 w - - 0 1"  # No kings
        rep = validate_package(self._materialize_pkg("err_start_fen", d))
        self.assertIn("E_START_FEN_INVALID", {e.code for e in rep.errors})

        # 8. E_TREE_STRUCTURE (dangling parent_id)
        d = self._build_base_package_dict()
        d["games/main.json"]["nodes"][-1]["parent_id"] = "n_nonexistent"
        rep = validate_package(self._materialize_pkg("err_tree", d))
        self.assertIn("E_TREE_STRUCTURE", {e.code for e in rep.errors})

        # 9. E_ILLEGAL_MOVE
        d = self._build_base_package_dict()
        d["games/main.json"]["nodes"][1]["uci"] = "e2e5"  # Illegal pawn jump
        rep = validate_package(self._materialize_pkg("err_illegal_move", d))
        self.assertIn("E_ILLEGAL_MOVE", {e.code for e in rep.errors})

        # 10. E_FEN_MISMATCH, E_SAN_MISMATCH, E_FINGERPRINT_MISMATCH
        d = self._build_base_package_dict()
        d["games/main.json"]["nodes"][1]["fen"] = STANDARD_START_FEN
        d["games/main.json"]["nodes"][1]["san"] = "Nf3"
        d["games/main.json"]["fingerprint"]["move_hash"] = "0000000000000000"
        rep = validate_package(self._materialize_pkg("err_fen_san_fp", d))
        codes = {e.code for e in rep.errors}
        self.assertIn("E_FEN_MISMATCH", codes)
        self.assertIn("E_SAN_MISMATCH", codes)
        self.assertIn("E_FINGERPRINT_MISMATCH", codes)

        # 11. E_CUE_ZERO_MISSING, E_CUE_ORDER, E_CUE_PAST_DURATION, E_SCENE_INCOMPLETE, E_OVERLAY_INVALID, E_TRIGGER_INVALID
        d = self._build_base_package_dict()
        d["timelines/main.json"]["cues"][0]["at_ms"] = 100
        d["timelines/main.json"]["cues"][1]["at_ms"] = 50  # out of order
        d["timelines/main.json"]["cues"][3]["at_ms"] = 99999  # past duration_ms=30000
        d["timelines/main.json"]["cues"][2]["scene"]["boards"] = {}  # missing 'demo' board
        d["timelines/main.json"]["cues"][1]["scene"]["boards"]["demo"]["overlays"][0]["end_ms"] = 10  # end_ms <= at_ms
        d["timelines/main.json"]["interactive_triggers"][0]["branches"][0]["uci"] = "e7e4"  # illegal branch move
        rep = validate_package(self._materialize_pkg("err_timeline", d))
        codes = {e.code for e in rep.errors}
        self.assertIn("E_CUE_ZERO_MISSING", codes)
        self.assertIn("E_CUE_ORDER", codes)
        self.assertIn("E_CUE_PAST_DURATION", codes)
        self.assertIn("E_SCENE_INCOMPLETE", codes)
        self.assertIn("E_OVERLAY_INVALID", codes)
        self.assertIn("E_TRIGGER_INVALID", codes)

    def test_07_on_disk_handmade_fixtures(self) -> None:
        fixtures_root = Path(__file__).resolve().parent / "fixtures"
        valid_fixt = fixtures_root / "valid-stream-and-setpos"
        rep_valid = validate_package(valid_fixt)
        self.assertTrue(rep_valid.valid, f"Expected valid fixture, got: {rep_valid.errors}")
        sc = scene_at_package(valid_fixt, 2000)
        self.assertEqual(sc["boards"]["demo"]["fen"], "8/8/4k3/8/4P3/4K3/8/8 w - - 0 1")
        self.assertEqual(len(sc["boards"]["demo"]["overlays"]), 1)
        self.assertIn("trig-start-drill", sc["matched_triggers"])

        # At 4500 ms the square overlay (end_ms=4000) has expired
        sc_4500 = scene_at_package(valid_fixt, 4500)
        self.assertEqual(len(sc_4500["boards"]["demo"]["overlays"]), 0)

        bad_fixt = fixtures_root / "bad-illegal-move"
        rep_bad = validate_package(bad_fixt)
        self.assertFalse(rep_bad.valid)
        self.assertIn("E_ILLEGAL_MOVE", [e.code for e in rep_bad.errors])


if __name__ == "__main__":
    unittest.main()
