"""Staged validator and O(log N) scene evaluator for ChessMedia 1.1 packages.

Implements all 5 validation stages and all machine-readable error codes (`E_*`)
defined in `docs/CHESSMEDIA_FORMAT.md`, plus dependency-free validation against
the JSON Schemas in `docs/chessmedia/schema/*.json`.
"""

from __future__ import annotations

import bisect
import hashlib
import json
import os
import re
import stat
import unicodedata
import zipfile
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple, Union

from .chess_core import (
    STANDARD_START_FEN,
    apply_uci_move,
    compute_fingerprint,
    fen_board_turn_key,
    fens_equivalent,
    validate_fen,
)

MAX_ARCHIVE_MEMBERS = 10000
MAX_JSON_BYTES = 64 * 1024 * 1024

KNOWN_FEATURES = {
    "scene-timeline/1",
    "chess-standard/1",
    "chess-960/1",
    "interactive-triggers/1",
    "stream-assets/1",
}

ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$")
RELPATH_RE = re.compile(r"^(?!/)(?!.*//)(?!.*(^|/)\.\.?($|/))[A-Za-z0-9._ /+-]+$")
SQUARE_RE = re.compile(r"^[a-h][1-8]$")
RGBA_RE = re.compile(r"^#[0-9a-fA-F]{8}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
URI_RE = re.compile(r"^https?://\S+$")


@dataclass
class ValidationErrorItem:
    stage: int
    code: str
    path: str
    pointer: str
    message: str

    def to_dict(self) -> Dict[str, Any]:
        return {
            "stage": self.stage,
            "code": self.code,
            "path": self.path,
            "pointer": self.pointer,
            "message": self.message,
        }


@dataclass
class ValidationReport:
    target: str
    structurally_valid: bool
    chess_valid: bool
    playable_here: bool
    sync_status: str
    errors: List[ValidationErrorItem] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    summary: Dict[str, Any] = field(default_factory=dict)

    @property
    def valid(self) -> bool:
        return self.structurally_valid and self.chess_valid and len(self.errors) == 0

    def to_dict(self) -> Dict[str, Any]:
        return {
            "target": self.target,
            "valid": self.valid,
            "structurally_valid": self.structurally_valid,
            "chess_valid": self.chess_valid,
            "playable_here": self.playable_here,
            "sync_status": self.sync_status,
            "errors": [e.to_dict() for e in self.errors],
            "warnings": self.warnings,
            "summary": self.summary,
        }


class _DuplicateKeyError(ValueError):
    pass


def _reject_duplicate_keys(pairs: List[Tuple[str, Any]]) -> Dict[str, Any]:
    obj: Dict[str, Any] = {}
    for k, v in pairs:
        if k in obj:
            raise _DuplicateKeyError(f"Duplicate JSON object key: {k!r}")
        obj[k] = v
    return obj


def _reject_nonfinite_constant(val: str) -> Any:
    raise ValueError(f"Non-finite JSON number constant not permitted: {val}")


def strict_json_loads(raw_bytes: bytes, file_path: str) -> Any:
    """Parse UTF-8 JSON without BOM, rejecting duplicate keys and NaN/Infinity."""
    if len(raw_bytes) > MAX_JSON_BYTES:
        raise ValueError(f"JSON file {file_path} exceeds 64 MiB limit ({len(raw_bytes)} bytes)")
    if raw_bytes.startswith(b"\xef\xbb\xbf"):
        raise ValueError(f"UTF-8 BOM is not permitted in {file_path}")
    try:
        text = raw_bytes.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise ValueError(f"Invalid UTF-8 encoding in {file_path}: {exc}") from exc
    return json.loads(
        text,
        object_pairs_hook=_reject_duplicate_keys,
        parse_constant=_reject_nonfinite_constant,
    )


def _is_int_not_bool(v: Any) -> bool:
    return isinstance(v, int) and not isinstance(v, bool)


def _is_safe_relpath(p: str) -> bool:
    if not isinstance(p, str) or not p:
        return False
    if "\\" in p or p.startswith("/") or ":" in p:
        return False
    parts = p.split("/")
    for seg in parts:
        if seg in ("", ".", ".."):
            return False
    return bool(RELPATH_RE.match(p))


# ---------------------------------------------------------------------------
# Built-in JSON Schema Draft 2020-12 Evaluator (dependency-free)
# ---------------------------------------------------------------------------

_SCHEMA_CACHE: Dict[str, Dict[str, Any]] = {}


def _load_builtin_schema(name: str) -> Optional[Dict[str, Any]]:
    if name in _SCHEMA_CACHE:
        return _SCHEMA_CACHE[name]
    here = Path(__file__).resolve().parent
    schema_path = here.parent.parent / "docs" / "chessmedia" / "schema" / f"{name}.schema.json"
    if schema_path.is_file():
        with open(schema_path, "rb") as f:
            data = json.loads(f.read().decode("utf-8"))
            _SCHEMA_CACHE[name] = data
            return data
    return None


def _validate_against_json_schema(
    instance: Any,
    schema: Dict[str, Any],
    root_schema: Dict[str, Any],
    pointer: str,
) -> List[str]:
    """Dependency-free evaluator for our JSON Schema 2020-12 files."""
    if "$ref" in schema:
        ref = schema["$ref"]
        if ref.startswith("#/"):
            target: Any = root_schema
            for part in ref[2:].split("/"):
                target = target[part]
            return _validate_against_json_schema(instance, target, root_schema, pointer)

    if "oneOf" in schema:
        matches = 0
        sub_errs: List[str] = []
        for sub in schema["oneOf"]:
            errs = _validate_against_json_schema(instance, sub, root_schema, pointer)
            if not errs:
                matches += 1
            else:
                sub_errs.extend(errs)
        if matches != 1:
            # If instance is a dict with a discriminator like "kind" or "live", prefer errors from the matching branch
            if isinstance(instance, dict):
                for sub in schema["oneOf"]:
                    props = sub.get("properties", {}) if isinstance(sub, dict) else {}
                    kind_prop = props.get("kind", {})
                    if isinstance(kind_prop, dict) and "const" in kind_prop and instance.get("kind") == kind_prop["const"]:
                        live_prop = props.get("live", {})
                        if isinstance(live_prop, dict) and "const" in live_prop and "live" in instance:
                            if instance.get("live") != live_prop["const"]:
                                continue
                        branch_errs = _validate_against_json_schema(instance, sub, root_schema, pointer)
                        if branch_errs:
                            return branch_errs
            return [f"{pointer}: failed oneOf constraint"]
        return []

    errs: List[str] = []
    if "const" in schema:
        if instance != schema["const"]:
            errs.append(f"{pointer}: expected const {schema['const']!r}, got {instance!r}")
            return errs

    if "enum" in schema:
        if instance not in schema["enum"]:
            errs.append(f"{pointer}: value {instance!r} not in enum {schema['enum']!r}")
            return errs

    expected_type = schema.get("type")
    if expected_type == "object":
        if not isinstance(instance, dict):
            return [f"{pointer}: expected object, got {type(instance).__name__}"]
        req = schema.get("required", [])
        for k in req:
            if k not in instance:
                errs.append(f"{pointer}: missing required property {k!r}")
        min_props = schema.get("minProperties")
        if min_props is not None and len(instance) < min_props:
            errs.append(f"{pointer}: expected at least {min_props} properties")
        props = schema.get("properties", {})
        addl = schema.get("additionalProperties", True)
        for k, v in instance.items():
            sub_ptr = f"{pointer}/{k}"
            if k in props:
                errs.extend(_validate_against_json_schema(v, props[k], root_schema, sub_ptr))
            elif addl is False:
                errs.append(f"{pointer}: unexpected additional property {k!r}")
            elif isinstance(addl, dict):
                errs.extend(_validate_against_json_schema(v, addl, root_schema, sub_ptr))
    elif expected_type == "array":
        if not isinstance(instance, list):
            return [f"{pointer}: expected array, got {type(instance).__name__}"]
        min_items = schema.get("minItems")
        if min_items is not None and len(instance) < min_items:
            errs.append(f"{pointer}: array requires at least {min_items} items")
        if schema.get("uniqueItems"):
            seen = []
            for item in instance:
                if item in seen:
                    errs.append(f"{pointer}: array items must be unique")
                    break
                seen.append(item)
        item_schema = schema.get("items")
        if isinstance(item_schema, dict):
            for idx, item in enumerate(instance):
                errs.extend(
                    _validate_against_json_schema(item, item_schema, root_schema, f"{pointer}/{idx}")
                )
    elif expected_type == "string":
        if not isinstance(instance, str):
            return [f"{pointer}: expected string, got {type(instance).__name__}"]
        min_len = schema.get("minLength")
        max_len = schema.get("maxLength")
        if min_len is not None and len(instance) < min_len:
            errs.append(f"{pointer}: string shorter than minLength {min_len}")
        if max_len is not None and len(instance) > max_len:
            errs.append(f"{pointer}: string longer than maxLength {max_len}")
        pat = schema.get("pattern")
        if pat is not None and not re.search(pat, instance):
            errs.append(f"{pointer}: string {instance!r} does not match pattern {pat!r}")
    elif expected_type == "integer":
        if not _is_int_not_bool(instance):
            return [f"{pointer}: expected integer, got {type(instance).__name__}"]
        minimum = schema.get("minimum")
        maximum = schema.get("maximum")
        if minimum is not None and instance < minimum:
            errs.append(f"{pointer}: integer {instance} < minimum {minimum}")
        if maximum is not None and instance > maximum:
            errs.append(f"{pointer}: integer {instance} > maximum {maximum}")
    elif expected_type == "boolean":
        if not isinstance(instance, bool):
            return [f"{pointer}: expected boolean, got {type(instance).__name__}"]
    elif expected_type == "null":
        if instance is not None:
            return [f"{pointer}: expected null, got {type(instance).__name__}"]

    return errs


# ---------------------------------------------------------------------------
# Package Abstraction (Directory or ZIP)
# ---------------------------------------------------------------------------

class PackageReader:
    """Unified reader for an unpacked directory or `.chessmedia` ZIP container."""

    def __init__(self, target: Union[str, Path]) -> None:
        self.target = Path(target)
        self.is_zip = False
        self._zf: Optional[zipfile.ZipFile] = None
        if self.target.is_file():
            self.is_zip = True

    def __enter__(self) -> "PackageReader":
        if self.is_zip:
            self._zf = zipfile.ZipFile(self.target, "r")
        return self

    def __exit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> None:
        if self._zf is not None:
            self._zf.close()
            self._zf = None

    def inspect_entries(self) -> Tuple[List[str], List[ValidationErrorItem]]:
        """Return list of relative file paths and any Stage 1 archive safety errors."""
        errors: List[ValidationErrorItem] = []
        files: List[str] = []
        norm_seen: Dict[str, str] = {}

        if self.is_zip:
            assert self._zf is not None
            infos = self._zf.infolist()
            if len(infos) > MAX_ARCHIVE_MEMBERS:
                errors.append(
                    ValidationErrorItem(
                        1,
                        "E_ARCHIVE_UNSAFE_PATH",
                        str(self.target),
                        "",
                        f"Archive contains {len(infos)} members (max {MAX_ARCHIVE_MEMBERS})",
                    )
                )
                return files, errors
            raw_seen: Set[str] = set()
            for info in infos:
                name = info.filename
                if name.endswith("/"):
                    continue
                # Check Unix symlink mode in external_attr
                mode = (info.external_attr >> 16) & 0xFFFF
                if mode and stat.S_ISLNK(mode):
                    errors.append(
                        ValidationErrorItem(
                            1,
                            "E_ARCHIVE_UNSAFE_PATH",
                            name,
                            "",
                            f"Symbolic link entry not permitted in archive: {name!r}",
                        )
                    )
                    continue
                if not _is_safe_relpath(name):
                    errors.append(
                        ValidationErrorItem(
                            1,
                            "E_ARCHIVE_UNSAFE_PATH",
                            name,
                            "",
                            f"Unsafe archive member path: {name!r}",
                        )
                    )
                    continue
                if name in raw_seen:
                    errors.append(
                        ValidationErrorItem(
                            1,
                            "E_ARCHIVE_UNSAFE_PATH",
                            name,
                            "",
                            f"Duplicate archive member path: {name!r}",
                        )
                    )
                    continue
                raw_seen.add(name)
                norm_key = unicodedata.normalize("NFC", name).lower()
                if norm_key in norm_seen:
                    errors.append(
                        ValidationErrorItem(
                            1,
                            "E_ARCHIVE_UNSAFE_PATH",
                            name,
                            "",
                            f"Case/Unicode collision between {name!r} and {norm_seen[norm_key]!r}",
                        )
                    )
                    continue
                norm_seen[norm_key] = name
                files.append(name)
        else:
            if not self.target.is_dir():
                errors.append(
                    ValidationErrorItem(
                        1,
                        "E_MANIFEST_MISSING",
                        str(self.target),
                        "",
                        f"Package path does not exist: {self.target}",
                    )
                )
                return files, errors
            count = 0
            for root, dirs, filenames in os.walk(self.target, followlinks=False):
                dirs.sort()
                filenames.sort()
                root_p = Path(root)
                for d in dirs:
                    dp = root_p / d
                    if dp.is_symlink():
                        rel_d = dp.relative_to(self.target).as_posix()
                        errors.append(
                            ValidationErrorItem(
                                1,
                                "E_ARCHIVE_UNSAFE_PATH",
                                rel_d,
                                "",
                                f"Symbolic link directory not permitted: {rel_d!r}",
                            )
                        )
                for fn in filenames:
                    count += 1
                    if count > MAX_ARCHIVE_MEMBERS:
                        errors.append(
                            ValidationErrorItem(
                                1,
                                "E_ARCHIVE_UNSAFE_PATH",
                                str(self.target),
                                "",
                                f"Directory exceeds {MAX_ARCHIVE_MEMBERS} files",
                            )
                        )
                        return files, errors
                    fp = root_p / fn
                    rel = fp.relative_to(self.target).as_posix()
                    st = os.lstat(fp)
                    if stat.S_ISLNK(st.st_mode) or not stat.S_ISREG(st.st_mode):
                        errors.append(
                            ValidationErrorItem(
                                1,
                                "E_ARCHIVE_UNSAFE_PATH",
                                rel,
                                "",
                                f"Non-regular or symlink file not permitted: {rel!r}",
                            )
                        )
                        continue
                    if not _is_safe_relpath(rel):
                        errors.append(
                            ValidationErrorItem(
                                1,
                                "E_ARCHIVE_UNSAFE_PATH",
                                rel,
                                "",
                                f"Unsafe relative file path: {rel!r}",
                            )
                        )
                        continue
                    norm_key = unicodedata.normalize("NFC", rel).lower()
                    if norm_key in norm_seen:
                        errors.append(
                            ValidationErrorItem(
                                1,
                                "E_ARCHIVE_UNSAFE_PATH",
                                rel,
                                "",
                                f"Case/Unicode collision between {rel!r} and {norm_seen[norm_key]!r}",
                            )
                        )
                        continue
                    norm_seen[norm_key] = rel
                    files.append(rel)
        return sorted(files), errors

    def read_bytes(self, relpath: str) -> bytes:
        if self.is_zip:
            assert self._zf is not None
            return self._zf.read(relpath)
        return (self.target / relpath).read_bytes()

    def size_and_sha256(self, relpath: str) -> Tuple[int, str]:
        h = hashlib.sha256()
        total = 0
        if self.is_zip:
            assert self._zf is not None
            with self._zf.open(relpath, "r") as f:
                while True:
                    chunk = f.read(65536)
                    if not chunk:
                        break
                    total += len(chunk)
                    h.update(chunk)
        else:
            with open(self.target / relpath, "rb") as f:
                while True:
                    chunk = f.read(65536)
                    if not chunk:
                        break
                    total += len(chunk)
                    h.update(chunk)
        return total, h.hexdigest()


# ---------------------------------------------------------------------------
# Full 5-Stage Package Validator
# ---------------------------------------------------------------------------

def validate_package(target: Union[str, Path]) -> ValidationReport:
    """Validate a `.chessmedia` archive or directory across all 5 stages."""
    target_path = Path(target)
    errors: List[ValidationErrorItem] = []
    warnings: List[str] = []

    def add_err(stage: int, code: str, path: str, pointer: str, msg: str) -> None:
        errors.append(ValidationErrorItem(stage, code, path, pointer, msg))

    if target_path.is_file() and not zipfile.is_zipfile(target_path):
        add_err(1, "E_MANIFEST_MISSING", str(target_path), "", "File is not a valid ZIP archive")
        return ValidationReport(
            target=str(target_path),
            structurally_valid=False,
            chess_valid=False,
            playable_here=False,
            sync_status="error_validation_failed",
            errors=errors,
        )

    with PackageReader(target_path) as pkg:
        files, stage1_errs = pkg.inspect_entries()
        errors.extend(stage1_errs)
        file_set = set(files)

        if "manifest.json" not in file_set:
            add_err(1, "E_MANIFEST_MISSING", "manifest.json", "", "manifest.json is missing at package root")
            return ValidationReport(
                target=str(target_path),
                structurally_valid=False,
                chess_valid=False,
                playable_here=False,
                sync_status="error_validation_failed",
                errors=errors,
            )

        # Parse manifest.json
        try:
            manifest_raw = pkg.read_bytes("manifest.json")
        except Exception as exc:
            add_err(1, "E_MANIFEST_MISSING", "manifest.json", "", f"Cannot read manifest.json: {exc}")
            return ValidationReport(
                target=str(target_path),
                structurally_valid=False,
                chess_valid=False,
                playable_here=False,
                sync_status="error_validation_failed",
                errors=errors,
            )

        try:
            manifest = strict_json_loads(manifest_raw, "manifest.json")
        except Exception as exc:
            add_err(2, "E_JSON_SYNTAX", "manifest.json", "", str(exc))
            return ValidationReport(
                target=str(target_path),
                structurally_valid=False,
                chess_valid=False,
                playable_here=False,
                sync_status="error_validation_failed",
                errors=errors,
            )

        if not isinstance(manifest, dict):
            add_err(2, "E_SCHEMA_VIOLATION", "manifest.json", "", "Manifest root must be a JSON object")
            return ValidationReport(
                target=str(target_path),
                structurally_valid=False,
                chess_valid=False,
                playable_here=False,
                sync_status="error_validation_failed",
                errors=errors,
            )

        # Version and format check before full schema check
        fmt = manifest.get("format")
        ver = manifest.get("version")
        if fmt != "chessmedia" or not isinstance(ver, dict) or ver.get("major") != 1 or not _is_int_not_bool(ver.get("minor")) or ver.get("minor", 0) < 1:
            add_err(
                2,
                "E_UNSUPPORTED_VERSION",
                "manifest.json",
                "/version",
                f"Unsupported format={fmt!r} or version={ver!r}; expected chessmedia 1.1+",
            )

        req_features = manifest.get("required_features")
        if isinstance(req_features, list):
            for idx, feat in enumerate(req_features):
                if not isinstance(feat, str) or feat not in KNOWN_FEATURES:
                    add_err(
                        2,
                        "E_UNSUPPORTED_FEATURE",
                        "manifest.json",
                        f"/required_features/{idx}",
                        f"Unsupported required_feature: {feat!r}",
                    )

        # Stage 2: JSON Schema check on manifest.json
        manifest_schema = _load_builtin_schema("manifest")
        if manifest_schema is not None:
            for s_err in _validate_against_json_schema(manifest, manifest_schema, manifest_schema, ""):
                # Don't duplicate version error if already added
                if "/version" in s_err or "/format" in s_err:
                    if any(e.code == "E_UNSUPPORTED_VERSION" for e in errors):
                        continue
                ptr_part = s_err.split(":")[0]
                if "pattern '^https?://" in s_err or (
                    ptr_part.startswith("/assets/") and ("'uri'" in s_err or "'duration_ms'" in s_err)
                ):
                    add_err(3, "E_STREAM_URI_INVALID", "manifest.json", ptr_part, s_err)
                elif "/gallery_order" in s_err and ("unique" in s_err or "at least 1" in s_err):
                    add_err(3, "E_GALLERY_INVALID", "manifest.json", "/gallery_order", s_err)
                elif "/interactive_triggers" in ptr_part:
                    add_err(5, "E_TRIGGER_INVALID", "manifest.json", ptr_part, s_err)
                else:
                    add_err(2, "E_SCHEMA_VIOLATION", "manifest.json", ptr_part, s_err)

        # Stage 1: Check manifest.members against package files
        members_list = manifest.get("members")
        declared_members: Dict[str, Dict[str, Any]] = {}
        if isinstance(members_list, list):
            for idx, m_entry in enumerate(members_list):
                if not isinstance(m_entry, dict):
                    continue
                m_path = m_entry.get("path")
                m_bytes = m_entry.get("bytes")
                m_sha = m_entry.get("sha256")
                ptr = f"/members/{idx}"
                if not isinstance(m_path, str) or not _is_safe_relpath(m_path):
                    add_err(1, "E_ARCHIVE_UNSAFE_PATH", "manifest.json", f"{ptr}/path", f"Unsafe member path {m_path!r}")
                    continue
                if m_path in declared_members:
                    add_err(3, "E_DUPLICATE_ID", "manifest.json", f"{ptr}/path", f"Duplicate member path {m_path!r}")
                    continue
                declared_members[m_path] = m_entry
                if m_path not in file_set:
                    add_err(1, "E_MEMBER_MISSING", m_path, ptr, f"Member listed in manifest is missing: {m_path}")
                else:
                    actual_bytes, actual_sha = pkg.size_and_sha256(m_path)
                    if m_bytes != actual_bytes or m_sha != actual_sha:
                        add_err(
                            1,
                            "E_MEMBER_HASH_MISMATCH",
                            m_path,
                            ptr,
                            f"Digest/size mismatch for {m_path}: expected ({m_bytes}, {m_sha}), got ({actual_bytes}, {actual_sha})",
                        )

        for pkg_file in files:
            if pkg_file == "manifest.json":
                continue
            if pkg_file not in declared_members:
                add_err(
                    1,
                    "E_MEMBER_UNLISTED",
                    pkg_file,
                    "/members",
                    f"Package file {pkg_file!r} is not listed in manifest.members",
                )

        # Stage 3: Collect and check IDs in manifest
        board_ids: Set[str] = set()
        for idx, b in enumerate(manifest.get("boards", []) if isinstance(manifest.get("boards"), list) else []):
            if isinstance(b, dict) and isinstance(b.get("id"), str):
                bid = b["id"]
                if bid in board_ids:
                    add_err(3, "E_DUPLICATE_ID", "manifest.json", f"/boards/{idx}/id", f"Duplicate board id {bid!r}")
                board_ids.add(bid)

        game_entries: Dict[str, Dict[str, Any]] = {}
        game_manifest_idx: Dict[str, int] = {}
        for idx, g in enumerate(manifest.get("games", []) if isinstance(manifest.get("games"), list) else []):
            if isinstance(g, dict) and isinstance(g.get("id"), str):
                gid = g["id"]
                if gid in game_entries:
                    add_err(3, "E_DUPLICATE_ID", "manifest.json", f"/games/{idx}/id", f"Duplicate game id {gid!r}")
                game_entries[gid] = g
                game_manifest_idx[gid] = idx
                gpath = g.get("path")
                if isinstance(gpath, str):
                    if not _is_safe_relpath(gpath):
                        add_err(1, "E_ARCHIVE_UNSAFE_PATH", "manifest.json", f"/games/{idx}/path", f"Unsafe path {gpath!r}")
                    elif gpath not in file_set:
                        add_err(1, "E_MEMBER_MISSING", gpath, f"/games/{idx}/path", f"Referenced game file missing: {gpath}")

        asset_entries: Dict[str, Dict[str, Any]] = {}
        for idx, a in enumerate(manifest.get("assets", []) if isinstance(manifest.get("assets"), list) else []):
            if not isinstance(a, dict):
                continue
            aid = a.get("id")
            ptr = f"/assets/{idx}"
            if isinstance(aid, str):
                if aid in asset_entries:
                    add_err(3, "E_DUPLICATE_ID", "manifest.json", f"{ptr}/id", f"Duplicate asset id {aid!r}")
                asset_entries[aid] = a
            kind = a.get("kind")
            if kind == "file":
                apath = a.get("path")
                if not isinstance(apath, str) or not apath:
                    if not any(e.path == "manifest.json" and e.pointer.startswith(ptr) for e in errors):
                        add_err(2, "E_SCHEMA_VIOLATION", "manifest.json", f"{ptr}/path", "File asset requires 'path'")
                elif not _is_safe_relpath(apath):
                    add_err(1, "E_ARCHIVE_UNSAFE_PATH", "manifest.json", f"{ptr}/path", f"Unsafe asset path {apath!r}")
                elif apath not in file_set:
                    add_err(1, "E_MEMBER_MISSING", apath, f"{ptr}/path", f"Referenced asset file missing: {apath}")
            elif kind == "stream":
                uri = a.get("uri")
                if not isinstance(uri, str) or not URI_RE.match(uri):
                    if not any(e.code == "E_STREAM_URI_INVALID" and e.pointer.startswith(ptr) for e in errors):
                        add_err(
                            3,
                            "E_STREAM_URI_INVALID",
                            "manifest.json",
                            f"{ptr}/uri",
                            f"Stream asset requires valid http(s) URI, got {uri!r}",
                        )
                if a.get("live") is False and not _is_int_not_bool(a.get("duration_ms")):
                    if not any(e.code == "E_STREAM_URI_INVALID" and e.pointer.startswith(ptr) for e in errors):
                        add_err(
                            3,
                            "E_STREAM_URI_INVALID",
                            "manifest.json",
                            f"{ptr}/duration_ms",
                            "Non-live VOD stream asset requires integer duration_ms",
                        )
                fb = a.get("fallback_path")
                if fb is not None:
                    if not isinstance(fb, str) or not _is_safe_relpath(fb):
                        add_err(1, "E_ARCHIVE_UNSAFE_PATH", "manifest.json", f"{ptr}/fallback_path", f"Unsafe fallback_path {fb!r}")
                    elif fb not in file_set:
                        add_err(1, "E_MEMBER_MISSING", fb, f"{ptr}/fallback_path", f"Missing fallback_path file: {fb}")

        timeline_entries: Dict[str, Dict[str, Any]] = {}
        for idx, tl in enumerate(manifest.get("timelines", []) if isinstance(manifest.get("timelines"), list) else []):
            if not isinstance(tl, dict):
                continue
            tid = tl.get("id")
            ptr = f"/timelines/{idx}"
            if isinstance(tid, str):
                if tid in timeline_entries:
                    add_err(3, "E_DUPLICATE_ID", "manifest.json", f"{ptr}/id", f"Duplicate timeline id {tid!r}")
                timeline_entries[tid] = tl
            tpath = tl.get("path")
            if isinstance(tpath, str):
                if not _is_safe_relpath(tpath):
                    add_err(1, "E_ARCHIVE_UNSAFE_PATH", "manifest.json", f"{ptr}/path", f"Unsafe timeline path {tpath!r}")
                elif tpath not in file_set:
                    add_err(1, "E_MEMBER_MISSING", tpath, f"{ptr}/path", f"Referenced timeline file missing: {tpath}")
            clock_aid = tl.get("clock_asset_id")
            if isinstance(clock_aid, str) and clock_aid not in asset_entries:
                add_err(3, "E_REF_UNKNOWN", "manifest.json", f"{ptr}/clock_asset_id", f"Unknown clock_asset_id {clock_aid!r}")

        # Links validation
        for idx, lk in enumerate(manifest.get("links", []) if isinstance(manifest.get("links"), list) else []):
            if not isinstance(lk, dict):
                continue
            ptr = f"/links/{idx}"
            gid = lk.get("game_id")
            aid = lk.get("asset_id")
            tid = lk.get("timeline_id")
            if isinstance(gid, str) and gid not in game_entries:
                add_err(3, "E_REF_UNKNOWN", "manifest.json", f"{ptr}/game_id", f"Link references unknown game_id {gid!r}")
            if isinstance(aid, str) and aid not in asset_entries:
                add_err(3, "E_REF_UNKNOWN", "manifest.json", f"{ptr}/asset_id", f"Link references unknown asset_id {aid!r}")
            if isinstance(tid, str) and tid not in timeline_entries:
                add_err(3, "E_REF_UNKNOWN", "manifest.json", f"{ptr}/timeline_id", f"Link references unknown timeline_id {tid!r}")

        # Gallery order validation
        gallery = manifest.get("gallery_order")
        if isinstance(gallery, list):
            if not gallery:
                if not any(e.code == "E_GALLERY_INVALID" for e in errors):
                    add_err(3, "E_GALLERY_INVALID", "manifest.json", "/gallery_order", "gallery_order cannot be empty")
            seen_gal: Set[str] = set()
            for idx, aid in enumerate(gallery):
                if not isinstance(aid, str) or aid not in asset_entries:
                    add_err(3, "E_GALLERY_INVALID", "manifest.json", f"/gallery_order/{idx}", f"gallery_order references unknown asset_id {aid!r}")
                elif aid in seen_gal:
                    add_err(3, "E_GALLERY_INVALID", "manifest.json", f"/gallery_order/{idx}", f"Duplicate asset_id {aid!r} in gallery_order")
                else:
                    seen_gal.add(aid)

        # Primary validation
        primary = manifest.get("primary")
        if isinstance(primary, dict):
            paid = primary.get("asset_id")
            ptid = primary.get("timeline_id")
            if isinstance(paid, str) and paid not in asset_entries:
                add_err(3, "E_REF_UNKNOWN", "manifest.json", "/primary/asset_id", f"primary.asset_id {paid!r} is unknown")
            if isinstance(ptid, str) and ptid not in timeline_entries:
                add_err(3, "E_REF_UNKNOWN", "manifest.json", "/primary/timeline_id", f"primary.timeline_id {ptid!r} is unknown")

        # Provenance validation (if present)
        prov_obj = None
        prov_ref = manifest.get("provenance")
        if isinstance(prov_ref, dict):
            ppath = prov_ref.get("path")
            if isinstance(ppath, str):
                if not _is_safe_relpath(ppath):
                    add_err(1, "E_ARCHIVE_UNSAFE_PATH", "manifest.json", "/provenance/path", f"Unsafe provenance path {ppath!r}")
                elif ppath not in file_set:
                    add_err(1, "E_MEMBER_MISSING", ppath, "/provenance/path", f"Missing provenance file: {ppath}")
                else:
                    try:
                        prov_obj = strict_json_loads(pkg.read_bytes(ppath), ppath)
                        prov_schema = _load_builtin_schema("provenance")
                        if prov_schema is not None:
                            for s_err in _validate_against_json_schema(prov_obj, prov_schema, prov_schema, ""):
                                add_err(2, "E_SCHEMA_VIOLATION", ppath, s_err.split(":")[0], s_err)
                    except Exception as exc:
                        add_err(2, "E_JSON_SYNTAX", ppath, "", str(exc))

        # Stage 4: Validate each game file
        parsed_games: Dict[str, Dict[str, Any]] = {}
        game_node_maps: Dict[str, Dict[str, Dict[str, Any]]] = {}
        game_schema = _load_builtin_schema("game")

        for gid, g_entry in game_entries.items():
            gpath = g_entry.get("path")
            if not isinstance(gpath, str) or gpath not in file_set:
                continue
            try:
                gdata = strict_json_loads(pkg.read_bytes(gpath), gpath)
            except Exception as exc:
                add_err(2, "E_JSON_SYNTAX", gpath, "", str(exc))
                continue
            if not isinstance(gdata, dict):
                add_err(2, "E_SCHEMA_VIOLATION", gpath, "", "Game file root must be an object")
                continue
            if gdata.get("schema_version") != "1.1":
                add_err(2, "E_UNSUPPORTED_VERSION", gpath, "/schema_version", f"Unsupported game schema_version {gdata.get('schema_version')!r}")
            if game_schema is not None:
                for s_err in _validate_against_json_schema(gdata, game_schema, game_schema, ""):
                    if "/schema_version" in s_err:
                        continue
                    add_err(2, "E_SCHEMA_VIOLATION", gpath, s_err.split(":")[0], s_err)
            if gdata.get("id") != gid:
                add_err(3, "E_REF_UNKNOWN", gpath, "/id", f"Game id {gdata.get('id')!r} does not match manifest game id {gid!r}")

            variant = gdata.get("variant", "standard")
            if not isinstance(variant, str) or variant not in ("standard", "chess960"):
                variant = "standard"
            fen_enc = gdata.get("fen_encoding", "fen")
            if not isinstance(fen_enc, str) or fen_enc not in ("fen", "shredder-fen", "xfen"):
                fen_enc = "fen"
            start_fen = gdata.get("start_fen")
            setup_flag = gdata.get("setup")

            if not isinstance(start_fen, str):
                add_err(4, "E_START_FEN_INVALID", gpath, "/start_fen", "Missing start_fen")
                continue
            fen_ok, fen_reason = validate_fen(start_fen, variant=variant)
            if not fen_ok:
                add_err(4, "E_START_FEN_INVALID", gpath, "/start_fen", f"Invalid start_fen: {fen_reason}")
                continue
            if variant == "standard":
                expected_setup = (start_fen.strip() != STANDARD_START_FEN)
                if isinstance(setup_flag, bool) and setup_flag != expected_setup:
                    add_err(
                        4,
                        "E_START_FEN_INVALID",
                        gpath,
                        "/setup",
                        f"setup={setup_flag} inconsistent with start_fen (expected {expected_setup})",
                    )

            nodes = gdata.get("nodes")
            if not isinstance(nodes, list) or not nodes:
                add_err(4, "E_TREE_STRUCTURE", gpath, "/nodes", "Game must have at least one node")
                continue

            node_by_id: Dict[str, Dict[str, Any]] = {}
            node_idx_by_id: Dict[str, int] = {}
            roots: List[str] = []
            for idx, n in enumerate(nodes):
                if not isinstance(n, dict):
                    continue
                nid = n.get("id")
                if not isinstance(nid, str):
                    continue
                if nid in node_by_id:
                    add_err(3, "E_DUPLICATE_ID", gpath, f"/nodes/{idx}/id", f"Duplicate node id {nid!r}")
                    continue
                node_by_id[nid] = n
                node_idx_by_id[nid] = idx
                if n.get("parent_id") is None:
                    roots.append(nid)

            if len(roots) != 1:
                add_err(4, "E_TREE_STRUCTURE", gpath, "/nodes", f"Game tree must have exactly 1 root node, found {len(roots)}")
                continue

            root_id = roots[0]
            root_node = node_by_id[root_id]
            root_ptr = f"/nodes/{node_idx_by_id[root_id]}"
            if root_node.get("uci") is not None or root_node.get("san") is not None:
                add_err(4, "E_TREE_STRUCTURE", gpath, root_ptr, "Root node must have uci=null and san=null")
            root_fen_val = root_node.get("fen")
            if not isinstance(root_fen_val, str) or not fens_equivalent(root_fen_val, start_fen, variant=variant, fen_encoding=fen_enc):
                add_err(
                    4,
                    "E_START_FEN_INVALID",
                    gpath,
                    f"{root_ptr}/fen",
                    f"Root node FEN {root_fen_val!r} does not match start_fen {start_fen!r}",
                )

            # Check parent links, children_ids, main_child_id, and tree connectivity (no cycles)
            children_map: Dict[str, List[str]] = {nid: [] for nid in node_by_id}
            structure_ok = True
            for nid, n in node_by_id.items():
                idx = node_idx_by_id[nid]
                ptr = f"/nodes/{idx}"
                pid = n.get("parent_id")
                if pid is not None:
                    if not isinstance(pid, str) or pid not in node_by_id:
                        add_err(4, "E_TREE_STRUCTURE", gpath, f"{ptr}/parent_id", f"Node {nid!r} has unknown parent_id {pid!r}")
                        structure_ok = False
                    elif pid == nid:
                        add_err(4, "E_TREE_STRUCTURE", gpath, f"{ptr}/parent_id", f"Node {nid!r} cannot be its own parent")
                        structure_ok = False
                    else:
                        children_map[pid].append(nid)
                    if not isinstance(n.get("uci"), str):
                        add_err(4, "E_TREE_STRUCTURE", gpath, f"{ptr}/uci", f"Non-root node {nid!r} requires a UCI move string")
                        structure_ok = False

            # Reachability / cycle detection from root_id
            visited: Set[str] = set()
            stack = [root_id]
            while stack:
                cur = stack.pop()
                if cur in visited:
                    add_err(4, "E_TREE_STRUCTURE", gpath, "/nodes", f"Cycle detected involving node {cur!r}")
                    structure_ok = False
                    break
                visited.add(cur)
                for ch_id in children_map.get(cur, []):
                    stack.append(ch_id)

            if len(visited) != len(node_by_id):
                unreachable = sorted(set(node_by_id.keys()) - visited)
                add_err(
                    4,
                    "E_TREE_STRUCTURE",
                    gpath,
                    "/nodes",
                    f"Unreachable/cyclic nodes in game tree: {unreachable[:5]}",
                )
                structure_ok = False

            for nid, n in node_by_id.items():
                idx = node_idx_by_id[nid]
                ptr = f"/nodes/{idx}"
                mc = n.get("main_child_id")
                actual_children = children_map.get(nid, [])
                if mc is not None:
                    if not isinstance(mc, str) or mc not in actual_children:
                        add_err(
                            4,
                            "E_TREE_STRUCTURE",
                            gpath,
                            f"{ptr}/main_child_id",
                            f"main_child_id {mc!r} is not a child of node {nid!r}",
                        )
                        structure_ok = False
                elif actual_children:
                    # If node has children, main_child_id should point to the main continuation
                    add_err(
                        4,
                        "E_TREE_STRUCTURE",
                        gpath,
                        f"{ptr}/main_child_id",
                        f"Node {nid!r} has children {actual_children} but main_child_id is null",
                    )
                    structure_ok = False
                decl_children = n.get("children_ids")
                if isinstance(decl_children, list):
                    if not all(isinstance(c_item, str) for c_item in decl_children):
                        structure_ok = False
                    elif set(decl_children) != set(actual_children) or len(decl_children) != len(actual_children):
                        add_err(
                            4,
                            "E_TREE_STRUCTURE",
                            gpath,
                            f"{ptr}/children_ids",
                            f"Declared children_ids {decl_children} do not match actual children {actual_children}",
                        )
                        structure_ok = False

            # Verify move legality, resulting FEN, and SAN in BFS order from root
            if structure_ok:
                bfs = [root_id]
                while bfs:
                    cur = bfs.pop(0)
                    parent_fen_raw = node_by_id[cur].get("fen")
                    if not isinstance(parent_fen_raw, str):
                        continue
                    parent_fen = parent_fen_raw
                    for ch_id in children_map.get(cur, []):
                        bfs.append(ch_id)
                        ch_node = node_by_id[ch_id]
                        ch_idx = node_idx_by_id[ch_id]
                        ch_ptr = f"/nodes/{ch_idx}"
                        uci_raw = ch_node.get("uci")
                        node_fen_raw = ch_node.get("fen")
                        if not isinstance(uci_raw, str) or not isinstance(node_fen_raw, str):
                            continue
                        uci = uci_raw
                        node_fen = node_fen_raw
                        node_san = ch_node.get("san")
                        try:
                            fen_legal, fen_always, canon_san = apply_uci_move(
                                parent_fen, uci, variant=variant, fen_encoding=fen_enc
                            )
                        except ValueError as exc:
                            add_err(
                                4,
                                "E_ILLEGAL_MOVE",
                                gpath,
                                f"{ch_ptr}/uci",
                                f"Illegal move {uci!r} from node {cur!r}: {exc}",
                            )
                            continue
                        if node_fen.strip() not in (fen_legal, fen_always) and not fens_equivalent(
                            node_fen, fen_legal, variant=variant, fen_encoding=fen_enc
                        ):
                            add_err(
                                4,
                                "E_FEN_MISMATCH",
                                gpath,
                                f"{ch_ptr}/fen",
                                f"FEN mismatch after {uci!r}: expected {fen_legal!r}, got {node_fen!r}",
                            )
                        if node_san is not None and (not isinstance(node_san, str) or node_san != canon_san):
                            add_err(
                                4,
                                "E_SAN_MISMATCH",
                                gpath,
                                f"{ch_ptr}/san",
                                f"SAN mismatch for {uci!r}: expected {canon_san!r}, got {node_san!r}",
                            )

                # Verify game fingerprint
                mainline_ucis: List[str] = []
                cur_mc = root_node.get("main_child_id")
                seen_mc: Set[str] = {root_id}
                while isinstance(cur_mc, str) and cur_mc in node_by_id and cur_mc not in seen_mc:
                    seen_mc.add(cur_mc)
                    u = node_by_id[cur_mc].get("uci")
                    if isinstance(u, str):
                        mainline_ucis.append(u)
                    cur_mc = node_by_id[cur_mc].get("main_child_id")

                raw_tags = gdata.get("tags")
                tags = {str(k): str(v) for k, v in raw_tags.items() if isinstance(k, str) and isinstance(v, str)} if isinstance(raw_tags, dict) else {}
                expected_fp = compute_fingerprint(tags, start_fen, mainline_ucis)
                actual_fp = gdata.get("fingerprint")
                if not isinstance(actual_fp, dict) or (
                    actual_fp.get("header_hash") != expected_fp["header_hash"]
                    or actual_fp.get("move_hash") != expected_fp["move_hash"]
                    or actual_fp.get("combined") != expected_fp["combined"]
                ):
                    add_err(
                        4,
                        "E_FINGERPRINT_MISMATCH",
                        gpath,
                        "/fingerprint",
                        f"Game fingerprint mismatch: expected {expected_fp}, got {actual_fp}",
                    )
                manifest_fp = g_entry.get("fingerprint")
                g_idx = game_manifest_idx[gid]
                if not isinstance(manifest_fp, dict) or (
                    manifest_fp.get("header_hash") != expected_fp["header_hash"]
                    or manifest_fp.get("move_hash") != expected_fp["move_hash"]
                    or manifest_fp.get("combined") != expected_fp["combined"]
                ):
                    add_err(
                        4,
                        "E_FINGERPRINT_MISMATCH",
                        "manifest.json",
                        f"/games/{g_idx}/fingerprint",
                        f"Manifest game fingerprint mismatch for {gid!r}: expected {expected_fp}, got {manifest_fp}",
                    )

            parsed_games[gid] = gdata
            game_node_maps[gid] = node_by_id

        def _validate_triggers_list(
            triggers_list: Any,
            doc_path: str,
            base_ptr: str,
            tl_duration_ms: Optional[int],
            seen_trig_ids: Set[str],
        ) -> None:
            if not isinstance(triggers_list, list):
                return
            for tr_idx, tr in enumerate(triggers_list):
                if not isinstance(tr, dict):
                    continue
                t_ptr = f"{base_ptr}/{tr_idx}"
                tr_id = tr.get("id")
                if isinstance(tr_id, str):
                    if tr_id in seen_trig_ids:
                        add_err(3, "E_DUPLICATE_ID", doc_path, f"{t_ptr}/id", f"Duplicate trigger id {tr_id!r}")
                    seen_trig_ids.add(tr_id)

                tr_at_ms = tr.get("at_ms")
                if tr_at_ms is not None and tl_duration_ms is not None:
                    if not _is_int_not_bool(tr_at_ms) or tr_at_ms < 0 or tr_at_ms > tl_duration_ms:
                        add_err(
                            5,
                            "E_CUE_PAST_DURATION",
                            doc_path,
                            f"{t_ptr}/at_ms",
                            f"Trigger at_ms={tr_at_ms!r} out of timeline duration bounds [0, {tl_duration_ms}]",
                        )

                tr_fen = tr.get("fen")
                if not isinstance(tr_fen, str):
                    add_err(5, "E_TRIGGER_INVALID", doc_path, f"{t_ptr}/fen", "Trigger requires valid 6-field FEN")
                    continue
                tgid = tr.get("game_id")
                tr_variant = "standard"
                if isinstance(tgid, str) and tgid in parsed_games:
                    gv = parsed_games[tgid].get("variant")
                    if gv in ("standard", "chess960"):
                        tr_variant = gv
                fen_ok, fen_err = validate_fen(tr_fen, variant=tr_variant)
                if not fen_ok:
                    add_err(5, "E_TRIGGER_INVALID", doc_path, f"{t_ptr}/fen", f"Invalid trigger FEN: {fen_err}")
                    continue

                match_mode = tr.get("match_mode", "board_turn")
                tnid = tr.get("node_id")
                if tgid is not None:
                    if not isinstance(tgid, str) or tgid not in game_entries:
                        add_err(3, "E_REF_UNKNOWN", doc_path, f"{t_ptr}/game_id", f"Trigger references unknown game_id {tgid!r}")
                    elif tnid is not None:
                        if not isinstance(tnid, str) or (tgid in game_node_maps and tnid not in game_node_maps[tgid]):
                            add_err(3, "E_REF_UNKNOWN", doc_path, f"{t_ptr}/node_id", f"Trigger references unknown node_id {tnid!r}")
                        elif tgid in game_node_maps:
                            node_fen = str(game_node_maps[tgid][tnid].get("fen", ""))
                            if match_mode == "exact":
                                matched = fens_equivalent(node_fen, tr_fen, variant=tr_variant)
                            else:
                                matched = (fen_board_turn_key(node_fen) == fen_board_turn_key(tr_fen))
                            if not matched:
                                add_err(
                                    5,
                                    "E_TRIGGER_INVALID",
                                    doc_path,
                                    f"{t_ptr}/fen",
                                    f"Trigger FEN {tr_fen!r} does not match node ({tgid}, {tnid}) FEN {node_fen!r} under {match_mode!r}",
                                )

                tkind = tr.get("kind")
                taid = tr.get("asset_id")
                ttid = tr.get("timeline_id")
                if taid is not None and (not isinstance(taid, str) or taid not in asset_entries):
                    add_err(3, "E_REF_UNKNOWN", doc_path, f"{t_ptr}/asset_id", f"Trigger references unknown asset_id {taid!r}")
                if ttid is not None and (not isinstance(ttid, str) or ttid not in timeline_entries):
                    add_err(3, "E_REF_UNKNOWN", doc_path, f"{t_ptr}/timeline_id", f"Trigger references unknown timeline_id {ttid!r}")

                if tkind in ("clip", "range") and not isinstance(taid, str):
                    add_err(5, "E_TRIGGER_INVALID", doc_path, f"{t_ptr}/asset_id", f"Trigger kind={tkind!r} requires asset_id")

                if tkind == "range":
                    s_ms = tr.get("start_ms")
                    e_ms = tr.get("end_ms")
                    if not (_is_int_not_bool(s_ms) and _is_int_not_bool(e_ms) and 0 <= s_ms < e_ms):
                        add_err(5, "E_TRIGGER_INVALID", doc_path, t_ptr, f"Range trigger requires 0 <= start_ms < end_ms, got ({s_ms}, {e_ms})")
                    elif isinstance(taid, str) and taid in asset_entries:
                        adur = asset_entries[taid].get("duration_ms")
                        if _is_int_not_bool(adur) and e_ms > adur:
                            add_err(5, "E_TRIGGER_INVALID", doc_path, f"{t_ptr}/end_ms", f"Range trigger end_ms={e_ms} exceeds asset duration_ms={adur}")

                branches = tr.get("branches")
                if tkind == "branch_prompt" and (not isinstance(branches, list) or len(branches) == 0):
                    add_err(5, "E_TRIGGER_INVALID", doc_path, f"{t_ptr}/branches", "branch_prompt trigger requires non-empty branches")
                if isinstance(branches, list):
                    seen_br: Set[str] = set()
                    for b_idx, br in enumerate(branches):
                        if not isinstance(br, dict):
                            continue
                        br_ptr = f"{t_ptr}/branches/{b_idx}"
                        brid = br.get("id")
                        if isinstance(brid, str):
                            if brid in seen_br:
                                add_err(3, "E_DUPLICATE_ID", doc_path, f"{br_ptr}/id", f"Duplicate branch id {brid!r}")
                            seen_br.add(brid)
                        baid = br.get("asset_id")
                        if not isinstance(baid, str) or baid not in asset_entries:
                            add_err(3, "E_REF_UNKNOWN", doc_path, f"{br_ptr}/asset_id", f"Branch references unknown asset_id {baid!r}")
                        btid = br.get("timeline_id")
                        if btid is not None and (not isinstance(btid, str) or btid not in timeline_entries):
                            add_err(3, "E_REF_UNKNOWN", doc_path, f"{br_ptr}/timeline_id", f"Branch references unknown timeline_id {btid!r}")
                        bs_ms = br.get("start_ms")
                        be_ms = br.get("end_ms")
                        if bs_ms is not None or be_ms is not None:
                            if not (_is_int_not_bool(bs_ms) and _is_int_not_bool(be_ms) and 0 <= bs_ms < be_ms):
                                add_err(
                                    5,
                                    "E_TRIGGER_INVALID",
                                    doc_path,
                                    br_ptr,
                                    f"Branch interval requires paired 0 <= start_ms < end_ms, got ({bs_ms}, {be_ms})",
                                )
                            elif isinstance(baid, str) and baid in asset_entries:
                                badur = asset_entries[baid].get("duration_ms")
                                if _is_int_not_bool(badur) and be_ms > badur:
                                    add_err(
                                        5,
                                        "E_TRIGGER_INVALID",
                                        doc_path,
                                        f"{br_ptr}/end_ms",
                                        f"Branch end_ms={be_ms} exceeds target asset duration_ms={badur}",
                                    )
                        buci = br.get("uci")
                        bsan = br.get("san")
                        if not isinstance(buci, str):
                            add_err(5, "E_TRIGGER_INVALID", doc_path, f"{br_ptr}/uci", "Branch requires UCI move")
                        else:
                            try:
                                _, _, canon_san = apply_uci_move(tr_fen, buci, variant=tr_variant)
                                if bsan is not None and (not isinstance(bsan, str) or bsan != canon_san):
                                    add_err(5, "E_TRIGGER_INVALID", doc_path, f"{br_ptr}/san", f"Branch SAN {bsan!r} != canonical {canon_san!r}")
                            except ValueError as exc:
                                add_err(5, "E_TRIGGER_INVALID", doc_path, f"{br_ptr}/uci", f"Illegal branch move {buci!r} in trigger FEN: {exc}")

        # Validate package-wide interactive_triggers in manifest.json (if present)
        global_seen_trig: Set[str] = set()
        if "interactive_triggers" in manifest:
            _validate_triggers_list(
                manifest.get("interactive_triggers"),
                "manifest.json",
                "/interactive_triggers",
                None,
                global_seen_trig,
            )

        # Stage 5: Validate each timeline file
        timeline_schema = _load_builtin_schema("timeline")
        parsed_timelines: Dict[str, Dict[str, Any]] = {}

        for tid, tl_entry in timeline_entries.items():
            tpath = tl_entry.get("path")
            if not isinstance(tpath, str) or tpath not in file_set:
                continue
            try:
                tdata = strict_json_loads(pkg.read_bytes(tpath), tpath)
            except Exception as exc:
                add_err(2, "E_JSON_SYNTAX", tpath, "", str(exc))
                continue
            if not isinstance(tdata, dict):
                add_err(2, "E_SCHEMA_VIOLATION", tpath, "", "Timeline root must be an object")
                continue
            if tdata.get("schema_version") != "1.1":
                add_err(2, "E_UNSUPPORTED_VERSION", tpath, "/schema_version", f"Unsupported timeline schema_version {tdata.get('schema_version')!r}")

            cues = tdata.get("cues")
            if not isinstance(cues, list) or len(cues) == 0:
                add_err(5, "E_CUE_ZERO_MISSING", tpath, "/cues", "Timeline cues must be a non-empty array starting at at_ms=0")
                continue

            if timeline_schema is not None:
                for s_err in _validate_against_json_schema(tdata, timeline_schema, timeline_schema, ""):
                    if "/schema_version" in s_err:
                        continue
                    ptr_part = s_err.split(":")[0]
                    if "/overlays/" in ptr_part:
                        add_err(5, "E_OVERLAY_INVALID", tpath, ptr_part, s_err)
                    elif "/interactive_triggers/" in ptr_part:
                        add_err(5, "E_TRIGGER_INVALID", tpath, ptr_part, s_err)
                    else:
                        add_err(2, "E_SCHEMA_VIOLATION", tpath, ptr_part, s_err)

            if tdata.get("id") != tid:
                add_err(3, "E_REF_UNKNOWN", tpath, "/id", f"Timeline id {tdata.get('id')!r} does not match manifest id {tid!r}")

            clock_aid = tdata.get("clock_asset_id")
            if not isinstance(clock_aid, str) or clock_aid not in asset_entries:
                add_err(3, "E_REF_UNKNOWN", tpath, "/clock_asset_id", f"Timeline references unknown clock_asset_id {clock_aid!r}")
            else:
                if clock_aid != tl_entry.get("clock_asset_id"):
                    add_err(
                        3,
                        "E_REF_UNKNOWN",
                        tpath,
                        "/clock_asset_id",
                        f"Timeline clock_asset_id {clock_aid!r} disagrees with manifest {tl_entry.get('clock_asset_id')!r}",
                    )
                tl_track = tdata.get("clock_track")
                as_track = asset_entries[clock_aid].get("clock_track")
                if isinstance(tl_track, str) and isinstance(as_track, str) and tl_track != as_track:
                    add_err(
                        2,
                        "E_SCHEMA_VIOLATION",
                        tpath,
                        "/clock_track",
                        f"Timeline clock_track {tl_track!r} conflicts with asset {clock_aid!r} clock_track {as_track!r}",
                    )

            duration_ms = tdata.get("duration_ms")
            if not _is_int_not_bool(duration_ms) or duration_ms < 0:
                add_err(2, "E_SCHEMA_VIOLATION", tpath, "/duration_ms", f"Invalid duration_ms: {duration_ms!r}")
                duration_ms = 0

            # Check cues[0].at_ms == 0, strictly increasing order, duration bounds, complete boards, overlays
            first_cue = cues[0] if isinstance(cues[0], dict) else {}
            if first_cue.get("at_ms") != 0:
                add_err(
                    5,
                    "E_CUE_ZERO_MISSING",
                    tpath,
                    "/cues/0/at_ms",
                    f"First cue must start at at_ms=0, got {first_cue.get('at_ms')!r}",
                )

            seen_cue_ids: Set[str] = set()
            prev_ms = -1
            for c_idx, cue in enumerate(cues):
                if not isinstance(cue, dict):
                    continue
                c_ptr = f"/cues/{c_idx}"
                cid = cue.get("id")
                if isinstance(cid, str):
                    if cid in seen_cue_ids:
                        add_err(3, "E_DUPLICATE_ID", tpath, f"{c_ptr}/id", f"Duplicate cue id {cid!r}")
                    seen_cue_ids.add(cid)
                at_ms = cue.get("at_ms")
                if _is_int_not_bool(at_ms):
                    if c_idx > 0 and at_ms <= prev_ms:
                        add_err(
                            5,
                            "E_CUE_ORDER",
                            tpath,
                            f"{c_ptr}/at_ms",
                            f"Cue timestamps must strictly increase: cue {c_idx} at_ms={at_ms} <= previous {prev_ms}",
                        )
                    if at_ms > duration_ms:
                        add_err(
                            5,
                            "E_CUE_PAST_DURATION",
                            tpath,
                            f"{c_ptr}/at_ms",
                            f"Cue at_ms={at_ms} exceeds timeline duration_ms={duration_ms}",
                        )
                    prev_ms = at_ms
                else:
                    at_ms = 0

                scene = cue.get("scene")
                if not isinstance(scene, dict):
                    continue
                boards_obj = scene.get("boards")
                if not isinstance(boards_obj, dict):
                    add_err(5, "E_SCENE_INCOMPLETE", tpath, f"{c_ptr}/scene/boards", "scene.boards must be an object")
                    continue

                if set(boards_obj.keys()) != board_ids:
                    missing_b = sorted(board_ids - set(boards_obj.keys()))
                    extra_b = sorted(set(boards_obj.keys()) - board_ids)
                    add_err(
                        5,
                        "E_SCENE_INCOMPLETE",
                        tpath,
                        f"{c_ptr}/scene/boards",
                        f"scene.boards keys mismatch manifest.boards (missing={missing_b}, extra={extra_b})",
                    )

                for bid, bstate in boards_obj.items():
                    b_ptr = f"{c_ptr}/scene/boards/{bid}"
                    if bid not in board_ids:
                        add_err(3, "E_REF_UNKNOWN", tpath, b_ptr, f"Unknown board id {bid!r}")
                    if not isinstance(bstate, dict):
                        continue
                    if bstate.get("hidden") is True:
                        continue
                    bgid = bstate.get("game_id")
                    bnid = bstate.get("node_id")
                    if not isinstance(bgid, str) or bgid not in game_entries:
                        add_err(3, "E_REF_UNKNOWN", tpath, f"{b_ptr}/game_id", f"Scene references unknown game_id {bgid!r}")
                    elif isinstance(bnid, str) and bgid in game_node_maps and bnid not in game_node_maps[bgid]:
                        add_err(
                            3,
                            "E_REF_UNKNOWN",
                            tpath,
                            f"{b_ptr}/node_id",
                            f"Scene references unknown node_id {bnid!r} in game {bgid!r}",
                        )

                    overlays = bstate.get("overlays")
                    if isinstance(overlays, list):
                        seen_ov_ids: Set[str] = set()
                        for o_idx, ov in enumerate(overlays):
                            if not isinstance(ov, dict):
                                continue
                            o_ptr = f"{b_ptr}/overlays/{o_idx}"
                            oid = ov.get("id")
                            if isinstance(oid, str):
                                if oid in seen_ov_ids:
                                    add_err(3, "E_DUPLICATE_ID", tpath, f"{o_ptr}/id", f"Duplicate overlay id {oid!r}")
                                seen_ov_ids.add(oid)
                            okind = ov.get("kind")
                            ocolor = ov.get("color")
                            if not isinstance(ocolor, str) or not RGBA_RE.match(ocolor):
                                if not any(e.path == tpath and e.pointer.startswith(o_ptr) for e in errors):
                                    add_err(5, "E_OVERLAY_INVALID", tpath, f"{o_ptr}/color", f"Invalid overlay color {ocolor!r}")
                            if okind == "arrow":
                                frm, to = ov.get("from"), ov.get("to")
                                if not (isinstance(frm, str) and SQUARE_RE.match(frm) and isinstance(to, str) and SQUARE_RE.match(to)):
                                    if not any(e.path == tpath and e.pointer.startswith(o_ptr) for e in errors):
                                        add_err(5, "E_OVERLAY_INVALID", tpath, o_ptr, f"Arrow overlay requires valid 'from' and 'to' squares, got {frm!r}->{to!r}")
                            elif okind == "square":
                                sq = ov.get("square")
                                if not (isinstance(sq, str) and SQUARE_RE.match(sq)):
                                    if not any(e.path == tpath and e.pointer.startswith(o_ptr) for e in errors):
                                        add_err(5, "E_OVERLAY_INVALID", tpath, f"{o_ptr}/square", f"Square overlay requires valid 'square', got {sq!r}")
                            elif okind == "label":
                                sq, txt = ov.get("square"), ov.get("text")
                                if not (isinstance(sq, str) and SQUARE_RE.match(sq) and isinstance(txt, str) and 1 <= len(txt) <= 64):
                                    if not any(e.path == tpath and e.pointer.startswith(o_ptr) for e in errors):
                                        add_err(5, "E_OVERLAY_INVALID", tpath, o_ptr, "Label overlay requires valid 'square' and non-empty 'text'")
                            else:
                                if not any(e.path == tpath and e.pointer.startswith(o_ptr) for e in errors):
                                    add_err(5, "E_OVERLAY_INVALID", tpath, f"{o_ptr}/kind", f"Invalid overlay kind {okind!r}")

                            end_ms = ov.get("end_ms")
                            if end_ms is not None:
                                if not _is_int_not_bool(end_ms) or end_ms <= at_ms:
                                    add_err(
                                        5,
                                        "E_OVERLAY_INVALID",
                                        tpath,
                                        f"{o_ptr}/end_ms",
                                        f"Overlay end_ms={end_ms} must be > cue.at_ms={at_ms}",
                                    )
                                elif end_ms > duration_ms:
                                    add_err(
                                        5,
                                        "E_CUE_PAST_DURATION",
                                        tpath,
                                        f"{o_ptr}/end_ms",
                                        f"Overlay end_ms={end_ms} exceeds timeline duration_ms={duration_ms}",
                                    )

                captions = scene.get("captions")
                if isinstance(captions, list):
                    for cap_idx, cap in enumerate(captions):
                        if not isinstance(cap, dict):
                            continue
                        cap_end = cap.get("end_ms")
                        if cap_end is not None:
                            if not _is_int_not_bool(cap_end) or cap_end <= at_ms:
                                add_err(
                                    5,
                                    "E_OVERLAY_INVALID",
                                    tpath,
                                    f"{c_ptr}/scene/captions/{cap_idx}/end_ms",
                                    f"Caption end_ms={cap_end} must be > cue.at_ms={at_ms}",
                                )
                            elif cap_end > duration_ms:
                                add_err(
                                    5,
                                    "E_CUE_PAST_DURATION",
                                    tpath,
                                    f"{c_ptr}/scene/captions/{cap_idx}/end_ms",
                                    f"Caption end_ms={cap_end} exceeds timeline duration_ms={duration_ms}",
                                )

            # Check chapters
            chapters = tdata.get("chapters")
            if isinstance(chapters, list):
                seen_ch: Set[str] = set()
                for ch_idx, ch in enumerate(chapters):
                    if not isinstance(ch, dict):
                        continue
                    chid = ch.get("id")
                    if isinstance(chid, str):
                        if chid in seen_ch:
                            add_err(3, "E_DUPLICATE_ID", tpath, f"/chapters/{ch_idx}/id", f"Duplicate chapter id {chid!r}")
                        seen_ch.add(chid)
                    ch_ms = ch.get("at_ms")
                    if _is_int_not_bool(ch_ms) and ch_ms > duration_ms:
                        add_err(
                            5,
                            "E_CUE_PAST_DURATION",
                            tpath,
                            f"/chapters/{ch_idx}/at_ms",
                            f"Chapter at_ms={ch_ms} exceeds timeline duration_ms={duration_ms}",
                        )

            # Check interactive_triggers on timeline
            _validate_triggers_list(
                tdata.get("interactive_triggers"),
                tpath,
                "/interactive_triggers",
                duration_ms,
                set(global_seen_trig),
            )

            parsed_timelines[tid] = tdata

        # Determine validation flags and player sync status
        stage_1_2_3_5_errs = [e for e in errors if e.stage in (1, 2, 3, 5)]
        stage_4_errs = [e for e in errors if e.stage == 4]
        structurally_valid = len(stage_1_2_3_5_errs) == 0
        chess_valid = structurally_valid and len(stage_4_errs) == 0
        playable_here = chess_valid

        if not chess_valid:
            sync_status = "error_validation_failed"
        elif len(timeline_entries) == 0:
            sync_status = "unsynced_no_timeline"
            warnings.append("Unsynchronized media (no board timeline)")
        elif isinstance(prov_obj, dict) and prov_obj.get("confidence") == "unsynchronized_media_only":
            sync_status = "unsynced_no_timeline"
            warnings.append("Provenance indicates unsynchronized media only (no board events in source)")
        elif isinstance(prov_obj, dict) and (
            prov_obj.get("incomplete_intervals") or prov_obj.get("clock_mapping_status") == "unresolved"
        ):
            sync_status = "unsynced_incomplete_import"
            warnings.append("Provenance contains incomplete import intervals or unresolved clock mapping")
        else:
            sync_status = "synced"

        if isinstance(prov_obj, dict) and isinstance(prov_obj.get("warnings"), list):
            for w in prov_obj.get("warnings", []):
                if isinstance(w, str) and w not in warnings:
                    warnings.append(w)

        total_nodes = sum(len(m) for m in game_node_maps.values())
        total_cues = sum(
            len(tl.get("cues", [])) if isinstance(tl.get("cues"), list) else 0
            for tl in parsed_timelines.values()
        )
        total_triggers = (
            len(manifest.get("interactive_triggers", []))
            if isinstance(manifest.get("interactive_triggers"), list)
            else 0
        ) + sum(
            len(tl.get("interactive_triggers", []))
            if isinstance(tl.get("interactive_triggers"), list)
            else 0
            for tl in parsed_timelines.values()
        )

        summary = {
            "id": manifest.get("id"),
            "title": manifest.get("title"),
            "boards": len(board_ids),
            "games": len(game_entries),
            "assets": len(asset_entries),
            "timelines": len(timeline_entries),
            "total_nodes": total_nodes,
            "total_cues": total_cues,
            "total_triggers": total_triggers,
            "gallery_order": manifest.get("gallery_order", []),
        }

        return ValidationReport(
            target=str(target_path),
            structurally_valid=structurally_valid,
            chess_valid=chess_valid,
            playable_here=playable_here,
            sync_status=sync_status,
            errors=errors,
            warnings=warnings,
            summary=summary,
        )


# ---------------------------------------------------------------------------
# Prepared O(log N) Scene Evaluator (`PreparedTimeline`, `PreparedLesson`, `scene_at`)
# ---------------------------------------------------------------------------

class PreparedTimeline:
    """Pre-indexed timeline and game node lookup tables for true O(log N) scene evaluation.

    Preparation (`__init__`) runs once in O(N + V + T) time (`N` cues, `V` game nodes, `T` triggers).
    Each subsequent `scene_at(t_ms)` call performs:
      - O(log N) binary search (`bisect.bisect_right`) on the cached `cue_times` tuple,
      - O(B) dictionary lookup in `node_maps_by_game[game_id][node_id]` (`B` declared boards),
      - O(K) expiry filter over the overlays and captions attached to that single cue,
      - O(B + M) hash lookup in `triggers_by_exact_fen` and `triggers_by_board_turn`.
    """

    def __init__(
        self,
        timeline_data: Dict[str, Any],
        games_by_id: Dict[str, Dict[str, Any]],
        package_triggers: Optional[List[Dict[str, Any]]] = None,
    ) -> None:
        cues = timeline_data.get("cues", [])
        if not isinstance(cues, list) or not cues:
            raise ValueError("Timeline has no cues")
        self.timeline_id: Optional[str] = timeline_data.get("id")
        self.duration_ms: int = int(timeline_data.get("duration_ms", 0))
        self.cues: Tuple[Dict[str, Any], ...] = tuple(cues)
        self.cue_times: Tuple[int, ...] = tuple(int(c["at_ms"]) for c in self.cues)

        # Build O(1) per-game node_id -> node dict map
        self.node_maps_by_game: Dict[str, Dict[str, Dict[str, Any]]] = {}
        for gid, gdata in games_by_id.items():
            nmap: Dict[str, Dict[str, Any]] = {}
            for n in gdata.get("nodes", []):
                if isinstance(n, dict) and isinstance(n.get("id"), str):
                    nmap[n["id"]] = n
            self.node_maps_by_game[gid] = nmap

        # Build (game_id, node_id) -> sorted list of cue occurrence dicts for board-to-video navigation
        occ_map: Dict[Tuple[str, str], List[Dict[str, Any]]] = {}
        for c_idx, cue in enumerate(self.cues):
            at_ms = self.cue_times[c_idx]
            cid = cue.get("id")
            for bid, bstate in cue.get("scene", {}).get("boards", {}).items():
                if isinstance(bstate, dict) and not bstate.get("hidden"):
                    gid = bstate.get("game_id")
                    nid = bstate.get("node_id")
                    if isinstance(gid, str) and isinstance(nid, str):
                        occ_map.setdefault((gid, nid), []).append(
                            {
                                "cue_id": cid,
                                "cue_index": c_idx,
                                "at_ms": at_ms,
                                "board_id": bid,
                            }
                        )
        self.occurrences_by_game_node: Dict[Tuple[str, str], Tuple[Dict[str, Any], ...]] = {
            k: tuple(v) for k, v in occ_map.items()
        }

        # Build O(1) hash maps for interactive triggers by exact FEN and board_turn key
        self.triggers_by_exact_fen: Dict[str, List[str]] = {}
        self.triggers_by_board_turn: Dict[str, List[str]] = {}
        all_triggers = list(package_triggers or []) + list(timeline_data.get("interactive_triggers", []))
        for tr in all_triggers:
            if not isinstance(tr, dict):
                continue
            tr_id = tr.get("id")
            tr_fen = tr.get("fen")
            if not isinstance(tr_id, str) or not isinstance(tr_fen, str):
                continue
            mode = tr.get("match_mode", "board_turn")
            if mode == "exact":
                self.triggers_by_exact_fen.setdefault(tr_fen.strip(), []).append(tr_id)
            else:
                self.triggers_by_board_turn.setdefault(fen_board_turn_key(tr_fen), []).append(tr_id)

        self.eval_call_count: int = 0

    def scene_at(self, t_ms: int) -> Dict[str, Any]:
        """Evaluate complete scene state at `t_ms` in O(log N) cue lookup + O(B + K + M) board/overlay work."""
        self.eval_call_count += 1
        clamped_ms = max(0, min(int(t_ms), self.duration_ms))

        idx = bisect.bisect_right(self.cue_times, clamped_ms) - 1
        if idx < 0:
            idx = 0
        cue = self.cues[idx]
        cue_at_ms = self.cue_times[idx]
        next_cue_ms = self.cue_times[idx + 1] if (idx + 1) < len(self.cue_times) else self.duration_ms + 1

        boards_out: Dict[str, Any] = {}
        matched_triggers: List[str] = []
        seen_trig: Set[str] = set()

        for bid, bstate in cue.get("scene", {}).get("boards", {}).items():
            if bstate.get("hidden") is True:
                boards_out[bid] = {"hidden": True}
                continue
            gid = bstate["game_id"]
            nid = bstate["node_id"]
            node_obj = self.node_maps_by_game.get(gid, {}).get(nid)

            active_overlays = []
            for ov in bstate.get("overlays", []):
                end_ms = ov.get("end_ms")
                eff_end = min(int(end_ms), next_cue_ms) if end_ms is not None else next_cue_ms
                if clamped_ms < eff_end:
                    active_overlays.append(dict(ov))

            fen_val = node_obj.get("fen") if node_obj else None
            boards_out[bid] = {
                "game_id": gid,
                "node_id": nid,
                "fen": fen_val,
                "uci": node_obj.get("uci") if node_obj else None,
                "san": node_obj.get("san") if node_obj else None,
                "orientation": bstate.get("orientation", "white"),
                "overlays": active_overlays,
            }
            if isinstance(fen_val, str):
                for tid in self.triggers_by_exact_fen.get(fen_val.strip(), ()):
                    if tid not in seen_trig:
                        seen_trig.add(tid)
                        matched_triggers.append(tid)
                for tid in self.triggers_by_board_turn.get(fen_board_turn_key(fen_val), ()):
                    if tid not in seen_trig:
                        seen_trig.add(tid)
                        matched_triggers.append(tid)

        active_captions = []
        for cap in cue.get("scene", {}).get("captions", []):
            end_ms = cap.get("end_ms")
            eff_end = min(int(end_ms), next_cue_ms) if end_ms is not None else next_cue_ms
            if clamped_ms < eff_end:
                active_captions.append(dict(cap))

        return {
            "timeline_id": self.timeline_id,
            "requested_ms": int(t_ms),
            "clamped_ms": clamped_ms,
            "cue_id": cue.get("id"),
            "cue_at_ms": cue_at_ms,
            "boards": boards_out,
            "captions": active_captions,
            "matched_triggers": matched_triggers,
        }

    def occurrences(self, game_id: str, node_id: str, nearest_ms: Optional[int] = None) -> Dict[str, Any]:
        """Return all timeline cue occurrences for `(game_id, node_id)` and optional nearest occurrence."""
        occs = list(self.occurrences_by_game_node.get((game_id, node_id), ()))
        selected = None
        if occs and nearest_ms is not None:
            # Prefer occurrence nearest current media_ms; ties choose earlier occurrence
            selected = min(occs, key=lambda o: (abs(int(o["at_ms"]) - int(nearest_ms)), int(o["at_ms"])))
        elif occs:
            selected = occs[0]
        return {
            "game_id": game_id,
            "node_id": node_id,
            "occurrences": occs,
            "selected": selected,
        }


class PreparedLesson:
    """Loaded and pre-indexed ChessMedia package for repeated O(log N) playback queries."""

    def __init__(self, target: Union[str, Path]) -> None:
        self.target = Path(target)
        with PackageReader(self.target) as pkg:
            self.manifest = strict_json_loads(pkg.read_bytes("manifest.json"), "manifest.json")
            self.games_by_id: Dict[str, Dict[str, Any]] = {}
            for g in self.manifest.get("games", []):
                self.games_by_id[g["id"]] = strict_json_loads(pkg.read_bytes(g["path"]), g["path"])
            pkg_triggers = self.manifest.get("interactive_triggers", [])
            self.timelines: Dict[str, PreparedTimeline] = {}
            for tl in self.manifest.get("timelines", []):
                tdata = strict_json_loads(pkg.read_bytes(tl["path"]), tl["path"])
                self.timelines[tl["id"]] = PreparedTimeline(
                    tdata,
                    self.games_by_id,
                    package_triggers=pkg_triggers if isinstance(pkg_triggers, list) else None,
                )
            prim_tid = self.manifest.get("primary", {}).get("timeline_id")
            if isinstance(prim_tid, str) and prim_tid in self.timelines:
                self.primary_timeline_id: Optional[str] = prim_tid
            elif self.timelines:
                self.primary_timeline_id = next(iter(self.timelines.keys()))
            else:
                self.primary_timeline_id = None

    def get_timeline(self, timeline_id: Optional[str] = None) -> PreparedTimeline:
        if timeline_id is not None:
            if timeline_id not in self.timelines:
                raise ValueError(f"Timeline {timeline_id!r} not found in package")
            return self.timelines[timeline_id]
        if self.primary_timeline_id is None:
            raise ValueError("Package has no timelines")
        return self.timelines[self.primary_timeline_id]

    def scene_at(self, t_ms: int, timeline_id: Optional[str] = None) -> Dict[str, Any]:
        return self.get_timeline(timeline_id).scene_at(t_ms)

    def occurrences(
        self,
        game_id: str,
        node_id: str,
        nearest_ms: Optional[int] = None,
        timeline_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        return self.get_timeline(timeline_id).occurrences(game_id, node_id, nearest_ms=nearest_ms)


def prepare_timeline(
    timeline_data: Dict[str, Any],
    games_by_id: Dict[str, Dict[str, Any]],
    package_triggers: Optional[List[Dict[str, Any]]] = None,
) -> PreparedTimeline:
    """Build and cache a `PreparedTimeline` index on `timeline_data`."""
    cached = timeline_data.get("_prepared_index")
    if isinstance(cached, PreparedTimeline):
        return cached
    prepared = PreparedTimeline(timeline_data, games_by_id, package_triggers=package_triggers)
    timeline_data["_prepared_index"] = prepared
    return prepared


def evaluate_timeline_scene_at(
    timeline_data: Union[PreparedTimeline, Dict[str, Any]],
    games_by_id: Optional[Dict[str, Dict[str, Any]]] = None,
    t_ms: int = 0,
) -> Dict[str, Any]:
    """Evaluate complete scene state at `t_ms` in O(log N) time using a `PreparedTimeline`."""
    if isinstance(timeline_data, PreparedTimeline):
        return timeline_data.scene_at(t_ms)
    prepared = prepare_timeline(timeline_data, games_by_id or {})
    return prepared.scene_at(t_ms)


def scene_at_package(
    target: Union[str, Path, PreparedLesson],
    t_ms: int,
    timeline_id: Optional[str] = None,
) -> Dict[str, Any]:
    """Evaluate `scene_at` at `t_ms` ms on a `PreparedLesson` or one-shot package path."""
    if isinstance(target, PreparedLesson):
        return target.scene_at(t_ms, timeline_id=timeline_id)
    lesson = PreparedLesson(target)
    return lesson.scene_at(t_ms, timeline_id=timeline_id)
