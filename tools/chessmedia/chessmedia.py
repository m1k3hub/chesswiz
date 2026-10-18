#!/usr/bin/env python3
"""Command-line interface for the ChessMedia 1.1 reference tool.

Subcommands:
  validate <target> [--json]
  pack <src_dir> <out.chessmedia> [--refresh-members] [--json]
  unpack <src.chessmedia> <out_dir> [--json]
  info <target> [--seek-ms <ms>] [--timeline-id <id>] [--json]
  import-legacy <video.wmv|.txt> [<game.pgn>] [-o <out>] [--media-mode {copy,stub}] [--json]
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import List, Optional

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from chessmedia.legacy_import import import_legacy_lesson  # type: ignore
    from chessmedia.package import inspect_package, pack_package, unpack_package  # type: ignore
    from chessmedia.validator import ValidationReport, validate_package  # type: ignore
else:
    from .legacy_import import import_legacy_lesson
    from .package import inspect_package, pack_package, unpack_package
    from .validator import ValidationReport, validate_package


def _print_validation_human(report: ValidationReport) -> None:
    status = "VALID" if report.valid else "INVALID"
    print(f"[{status}] {report.target}")
    print(
        f"  structurally_valid={report.structurally_valid} "
        f"chess_valid={report.chess_valid} "
        f"playable_here={report.playable_here} "
        f"sync_status={report.sync_status}"
    )
    if report.summary:
        s = report.summary
        print(
            f"  id={s.get('id')} games={s.get('games')} assets={s.get('assets')} "
            f"timelines={s.get('timelines')} nodes={s.get('total_nodes')} "
            f"cues={s.get('total_cues')} triggers={s.get('total_triggers')}"
        )
    for w in report.warnings:
        print(f"  WARNING: {w}")
    for err in report.errors:
        loc = f"{err.path}#{err.pointer}" if err.pointer else err.path
        print(f"  ERROR [stage {err.stage}] {err.code} ({loc}): {err.message}")


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog="chessmedia",
        description="ChessMedia 1.1 reference validator, packager, inspector, and legacy importer.",
    )
    sub = parser.add_subparsers(dest="subcommand", required=True)

    # validate
    p_val = sub.add_parser("validate", help="Validate a .chessmedia archive or unpacked directory")
    p_val.add_argument("target", help="Path to .chessmedia file or directory")
    p_val.add_argument("--json", action="store_true", help="Emit machine-readable JSON report")

    # pack
    p_pack = sub.add_parser("pack", help="Pack an unpacked directory into a .chessmedia ZIP archive")
    p_pack.add_argument("src_dir", help="Unpacked package directory")
    p_pack.add_argument("out_zip", help="Output .chessmedia file path")
    p_pack.add_argument(
        "--refresh-members",
        action="store_true",
        help="Recompute manifest.members bytes and SHA-256 digests before packing",
    )
    p_pack.add_argument("--json", action="store_true", help="Emit JSON report")

    # unpack
    p_unpack = sub.add_parser("unpack", help="Unpack a .chessmedia ZIP archive into a directory")
    p_unpack.add_argument("src_zip", help="Source .chessmedia archive")
    p_unpack.add_argument("out_dir", help="Destination directory")
    p_unpack.add_argument("--overwrite", action="store_true", help="Allow overwriting existing regular files in out_dir")
    p_unpack.add_argument("--json", action="store_true", help="Emit JSON report")

    # info
    p_info = sub.add_parser("info", help="Inspect package metadata, sync state, and optional scene at t_ms")
    p_info.add_argument("target", help="Path to .chessmedia file or directory")
    p_info.add_argument("--seek-ms", type=int, default=None, help="Evaluate scene_at(t_ms) at timestamp in ms")
    p_info.add_argument("--timeline-id", default=None, help="Timeline ID for --seek-ms")
    p_info.add_argument("--json", action="store_true", help="Emit JSON output")

    # import-legacy
    p_imp = sub.add_parser(
        "import-legacy",
        help="Convert a legacy .wmv or .txt lesson (and optional .pgn) to ChessMedia 1.1",
    )
    p_imp.add_argument("source", help="Path to legacy .wmv or .txt sidecar")
    p_imp.add_argument("pgn", nargs="?", default=None, help="Optional companion .pgn file")
    p_imp.add_argument("-o", "--out", default=None, help="Output directory or .chessmedia archive path")
    p_imp.add_argument(
        "--media-mode",
        choices=["copy", "stub"],
        default="copy",
        help="Whether to copy source .wmv into assets/ or generate a tiny MP4 placeholder stub",
    )
    p_imp.add_argument("--json", action="store_true", help="Emit JSON output")

    args = parser.parse_args(argv)

    if args.subcommand == "validate":
        report = validate_package(args.target)
        if args.json:
            print(json.dumps(report.to_dict(), indent=2, ensure_ascii=False))
        else:
            _print_validation_human(report)
        return 0 if report.valid else 1

    if args.subcommand == "pack":
        report = pack_package(
            args.src_dir,
            args.out_zip,
            refresh_members=args.refresh_members,
            validate=True,
        )
        if args.json:
            print(json.dumps(report.to_dict(), indent=2, ensure_ascii=False))
        else:
            _print_validation_human(report)
        return 0 if report.valid else 1

    if args.subcommand == "unpack":
        report = unpack_package(args.src_zip, args.out_dir, validate=True, overwrite=args.overwrite)
        if args.json:
            print(json.dumps(report.to_dict(), indent=2, ensure_ascii=False))
        else:
            _print_validation_human(report)
        return 0 if report.valid else 1

    if args.subcommand == "info":
        info = inspect_package(args.target, seek_ms=args.seek_ms, timeline_id=args.timeline_id)
        if args.json:
            print(json.dumps(info, indent=2, ensure_ascii=False))
        else:
            print(f"Package: {info.get('id')} — {info.get('title')}")
            val = info.get("validation", {})
            print(f"Valid: {val.get('valid')} (sync_status={val.get('sync_status')})")
            print(f"Gallery order: {info.get('gallery_order')}")
            for g in info.get("games", []):
                print(
                    f"  Game {g['id']}: start_fen={g['start_fen']!r} setup={g['setup']} "
                    f"nodes={g['node_count']} fingerprint={g.get('fingerprint', {}).get('combined')}"
                )
            for tl in info.get("timelines", []):
                print(
                    f"  Timeline {tl['id']}: clock={tl['clock_asset_id']} "
                    f"duration_ms={tl['duration_ms']} cues={tl['cue_count']} triggers={tl['trigger_count']}"
                )
            if "scene_at" in info:
                sc = info["scene_at"]
                print(f"  Scene at {sc['requested_ms']} ms -> cue {sc['cue_id']} (@{sc['cue_at_ms']} ms):")
                for bid, bstate in sc["boards"].items():
                    print(
                        f"    Board {bid}: node={bstate.get('node_id')} san={bstate.get('san')} "
                        f"fen={bstate.get('fen')} overlays={len(bstate.get('overlays', []))}"
                    )
        return 0 if info.get("validation", {}).get("valid") else 1

    if args.subcommand == "import-legacy":
        out_path = args.out
        if out_path is None:
            src_p = Path(args.source)
            out_path = str(Path.cwd() / f"{src_p.stem}.chessmedia")
        prov, report = import_legacy_lesson(
            args.source,
            pgn_path=args.pgn,
            out_target=out_path,
            media_mode=args.media_mode,
        )
        result_payload = {
            "output": str(out_path),
            "confidence": prov["confidence"],
            "clock_source": prov["clock_source"],
            "inferred_summary": prov["inferred_summary"],
            "validation": report.to_dict(),
        }
        if args.json:
            print(json.dumps(result_payload, indent=2, ensure_ascii=False))
        else:
            print(f"Imported legacy lesson -> {out_path}")
            print(f"  confidence={prov['confidence']} clock_source={prov['clock_source']}")
            print(f"  inferred_summary={json.dumps(prov['inferred_summary'])}")
            _print_validation_human(report)
        return 0 if report.valid else 1

    return 2


if __name__ == "__main__":
    sys.exit(main())
