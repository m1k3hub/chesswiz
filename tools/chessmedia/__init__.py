"""ChessMedia 1.1 reference validator, packager, scene evaluator, and legacy importer."""

from .chess_core import (
    HAS_PYTHON_CHESS,
    STANDARD_START_FEN,
    apply_uci_move,
    compute_fingerprint,
    parse_pgn_text,
    san_to_uci,
    validate_fen,
)
from .legacy_import import import_legacy_lesson, parse_checkpoint_payload, parse_sidecar_txt
from .package import (
    compute_dir_members,
    inspect_package,
    pack_package,
    refresh_manifest_members,
    unpack_package,
)
from .validator import (
    ValidationErrorItem,
    ValidationReport,
    evaluate_timeline_scene_at,
    scene_at_package,
    validate_package,
)

__all__ = [
    "HAS_PYTHON_CHESS",
    "STANDARD_START_FEN",
    "ValidationErrorItem",
    "ValidationReport",
    "apply_uci_move",
    "compute_dir_members",
    "compute_fingerprint",
    "evaluate_timeline_scene_at",
    "import_legacy_lesson",
    "inspect_package",
    "pack_package",
    "parse_checkpoint_payload",
    "parse_pgn_text",
    "parse_sidecar_txt",
    "refresh_manifest_members",
    "san_to_uci",
    "scene_at_package",
    "unpack_package",
    "validate_fen",
    "validate_package",
]
