"""Pack, unpack, and inspect ChessMedia 1.1 packages."""

from __future__ import annotations

import hashlib
import json
import os
import zipfile
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple, Union

from .validator import (
    PackageReader,
    ValidationReport,
    _is_safe_relpath,
    scene_at_package,
    strict_json_loads,
    validate_package,
)

STORED_EXTENSIONS = {
    ".mp4",
    ".webm",
    ".mkv",
    ".wmv",
    ".avi",
    ".mov",
    ".mp3",
    ".ogg",
    ".m4a",
    ".opus",
    ".flac",
    ".png",
    ".jpg",
    ".jpeg",
    ".webp",
    ".gif",
}


def compute_dir_members(src_dir: Union[str, Path]) -> List[Dict[str, Any]]:
    """Compute sorted `members` list (`path`, `bytes`, `sha256`) for a package directory."""
    root_dir = Path(src_dir)
    members: List[Dict[str, Any]] = []
    rel_files: List[str] = []
    for root, dirs, filenames in os.walk(root_dir, followlinks=False):
        dirs.sort()
        filenames.sort()
        for fn in filenames:
            fp = Path(root) / fn
            rel = fp.relative_to(root_dir).as_posix()
            if rel == "manifest.json":
                continue
            rel_files.append(rel)

    for rel in sorted(rel_files):
        fp = root_dir / rel
        h = hashlib.sha256()
        total = 0
        with open(fp, "rb") as f:
            while True:
                chunk = f.read(65536)
                if not chunk:
                    break
                total += len(chunk)
                h.update(chunk)
        members.append(
            {
                "path": rel,
                "bytes": total,
                "sha256": h.hexdigest(),
            }
        )
    return members


def refresh_manifest_members(src_dir: Union[str, Path]) -> Dict[str, Any]:
    """Update `manifest.json` in `src_dir` with fresh `members` digests."""
    root_dir = Path(src_dir)
    manifest_path = root_dir / "manifest.json"
    manifest = strict_json_loads(manifest_path.read_bytes(), "manifest.json")
    manifest["members"] = compute_dir_members(root_dir)
    manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.chmod(manifest_path, 0o644)
    return manifest


def pack_package(
    src_dir: Union[str, Path],
    out_zip: Union[str, Path],
    refresh_members: bool = False,
    validate: bool = True,
) -> ValidationReport:
    """Pack an unpacked ChessMedia directory into a `.chessmedia` ZIP container."""
    src_path = Path(src_dir)
    out_path = Path(out_zip)

    if refresh_members:
        refresh_manifest_members(src_path)

    if validate:
        pre_report = validate_package(src_path)
        if not pre_report.valid:
            return pre_report

    out_path.parent.mkdir(parents=True, exist_ok=True)
    members = compute_dir_members(src_path)
    ordered_paths = ["manifest.json"] + [m["path"] for m in members]

    with zipfile.ZipFile(out_path, "w", allowZip64=True) as zf:
        for rel in ordered_paths:
            fp = src_path / rel
            ext = fp.suffix.lower()
            compress_type = zipfile.ZIP_STORED if ext in STORED_EXTENSIONS else zipfile.ZIP_DEFLATED
            zinfo = zipfile.ZipInfo(filename=rel, date_time=(2026, 1, 1, 0, 0, 0))
            zinfo.compress_type = compress_type
            zinfo.external_attr = (0o100644 & 0xFFFF) << 16
            with open(fp, "rb") as src_f, zf.open(zinfo, "w") as dst_f:
                while True:
                    chunk = src_f.read(65536)
                    if not chunk:
                        break
                    dst_f.write(chunk)

    os.chmod(out_path, 0o644)
    return validate_package(out_path)


def unpack_package(
    src_zip: Union[str, Path],
    out_dir: Union[str, Path],
    validate: bool = True,
) -> ValidationReport:
    """Unpack a `.chessmedia` ZIP container into `out_dir` after safety checks."""
    src_path = Path(src_zip)
    dst_path = Path(out_dir)

    report = validate_package(src_path)
    if validate and not report.valid:
        return report
    # Always block unsafe archive paths even if validate=False
    if any(e.code == "E_ARCHIVE_UNSAFE_PATH" for e in report.errors):
        return report

    dst_path.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(src_path, "r") as zf:
        for info in zf.infolist():
            name = info.filename
            if name.endswith("/"):
                continue
            if not _is_safe_relpath(name):
                raise ValueError(f"Refusing to extract unsafe archive path: {name!r}")
            target_fp = dst_path / name
            target_fp.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(info, "r") as src_f, open(target_fp, "wb") as dst_f:
                while True:
                    chunk = src_f.read(65536)
                    if not chunk:
                        break
                    dst_f.write(chunk)
            os.chmod(target_fp, 0o644)

    return validate_package(dst_path) if validate else report


def inspect_package(
    target: Union[str, Path],
    seek_ms: Optional[int] = None,
    timeline_id: Optional[str] = None,
) -> Dict[str, Any]:
    """Return structured metadata, sync status, and optional `scene_at` evaluation."""
    report = validate_package(target)
    info: Dict[str, Any] = {
        "target": str(target),
        "validation": report.to_dict(),
    }
    with PackageReader(target) as pkg:
        files, _ = pkg.inspect_entries()
        if "manifest.json" not in files:
            return info
        manifest = strict_json_loads(pkg.read_bytes("manifest.json"), "manifest.json")
        info["id"] = manifest.get("id")
        info["title"] = manifest.get("title")
        info["version"] = manifest.get("version")
        info["required_features"] = manifest.get("required_features", [])
        info["gallery_order"] = manifest.get("gallery_order", [])
        info["primary"] = manifest.get("primary", {})
        info["links"] = manifest.get("links", [])
        info["assets"] = manifest.get("assets", [])

        games_summary = []
        for g in manifest.get("games", []):
            gpath = g.get("path")
            if isinstance(gpath, str) and gpath in files:
                gdata = strict_json_loads(pkg.read_bytes(gpath), gpath)
                nodes = gdata.get("nodes", [])
                games_summary.append(
                    {
                        "id": g.get("id"),
                        "path": gpath,
                        "variant": gdata.get("variant"),
                        "start_fen": gdata.get("start_fen"),
                        "setup": gdata.get("setup"),
                        "tags": gdata.get("tags", {}),
                        "fingerprint": gdata.get("fingerprint"),
                        "node_count": len(nodes),
                    }
                )
        info["games"] = games_summary

        timelines_summary = []
        for tl in manifest.get("timelines", []):
            tpath = tl.get("path")
            if isinstance(tpath, str) and tpath in files:
                tdata = strict_json_loads(pkg.read_bytes(tpath), tpath)
                timelines_summary.append(
                    {
                        "id": tl.get("id"),
                        "path": tpath,
                        "clock_asset_id": tdata.get("clock_asset_id"),
                        "clock_track": tdata.get("clock_track", "presentation"),
                        "duration_ms": tdata.get("duration_ms"),
                        "cue_count": len(tdata.get("cues", [])),
                        "chapter_count": len(tdata.get("chapters", [])),
                        "trigger_count": len(tdata.get("interactive_triggers", [])),
                    }
                )
        info["timelines"] = timelines_summary

        prov_ref = manifest.get("provenance")
        if isinstance(prov_ref, dict) and isinstance(prov_ref.get("path"), str) and prov_ref["path"] in files:
            info["provenance"] = strict_json_loads(pkg.read_bytes(prov_ref["path"]), prov_ref["path"])

    if seek_ms is not None and report.valid and info.get("timelines"):
        info["scene_at"] = scene_at_package(target, seek_ms, timeline_id=timeline_id)

    return info
