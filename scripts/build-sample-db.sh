#!/usr/bin/env bash
# Rebuild from the bundled, unmodified TWIC PGN selection; no network needed.
# Usage: bash scripts/build-sample-db.sh [source.pgn.gz] [output.sci] [tkchesswiz]
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_pgn="${1:-$repo_root/share/sample/twic1667.pgn.gz}"
out_sci="${2:-$repo_root/share/sample/Sample games.sci}"
program="${3:-$repo_root/src/tkchesswiz}"
mkdir -p "$repo_root/tests/tmp-app"
work="$(mktemp -d "$repo_root/tests/tmp-app/sample-build.XXXXXX")"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/home" "$(dirname "$out_sci")"
python3 - "$source_pgn" "$work/source.pgn" <<'PY'
import gzip
import pathlib
import sys
source = pathlib.Path(sys.argv[1])
data = gzip.decompress(source.read_bytes()) if source.suffix == '.gz' else source.read_bytes()
count = data.count(b'[Event ')
if not 2000 <= count <= 5000:
    raise SystemExit(f'Expected 2000-5000 TWIC games, got {count}')
pathlib.Path(sys.argv[2]).write_bytes(data)
PY
# Always use a private profile and virtual display, even on a desktop machine.
HOME="$work/home" SCIDB_USERDIR="$work/home/profile" xvfb-run -a "$program" \
    "$repo_root/scripts/import-sample-db.tcl" "$work/source.pgn" "$work/Sample games.sci" \
    "${SCIDB_SHAREDIR:-/usr/local/share/chesswiz}/data/eco.bin"
python3 - "$work" "$out_sci" <<'PY'
import pathlib
import shutil
import sys
work, target = map(pathlib.Path, sys.argv[1:])
parts = [work / ('Sample games' + ext) for ext in ('.sci', '.scg', '.scn')]
if sum(p.stat().st_size for p in parts) >= 5_000_000:
    raise SystemExit('Sample exceeds 5 MB')
for p in parts:
    shutil.copyfile(p, target.with_suffix(p.suffix))
print('Built sample:', target)
PY
