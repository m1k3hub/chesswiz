#!/usr/bin/env bash
# scripts/make-windows-dist.sh [BUILD_DIR] [DIST_DIR]
#
# Assembles a self-contained Chesswiz folder for Windows from a finished
# cross build (default build/wt-win) and the sysroot it was built against:
#
#   Chesswiz/
#     tkchesswiz.exe       the program (Tcl/Tk linked in statically)
#     chesswiz.tcl         the script bundle; main() starts it when present
#     lib/tcl8.6 tk8.6 tcl8   Tcl/Tk script libraries ([info library] finds them)
#     data/ hyphen/ lang/ pieces/ themes/ ...   share files (share dir = exe dir)
#
# Fonts are not installed yet (Windows needs private registration at
# startup, spec D8), nor engines; the installer comes later.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$(cd "${1:-$ROOT/build/wt-win}" && pwd)"
DIST="${2:-$ROOT/build/dist/Chesswiz}"
SYSROOT="$ROOT/build/x86_64-windows-gnu"

die() { echo "make-windows-dist: $*" >&2; exit 1; }

[ -f "$BUILD/src/tkchesswiz.exe" ] || die "no $BUILD/src/tkchesswiz.exe; build first"
[ -f "$BUILD/tcl/chesswiz.exe" ]   || die "no script bundle $BUILD/tcl/chesswiz.exe; run make -C tcl"
[ -d "$SYSROOT/lib/tcl8.6" ]       || die "no sysroot at $SYSROOT; run scripts/build-sysroot.sh"

rm -rf "$DIST"
mkdir -p "$DIST/lib"

# Share files, through the regular install targets (fonts excluded: they
# run Linux font tools).
make -s -C "$BUILD/tcl" \
	install-scripts install-pieces install-cursors install-flags install-localizations \
	install-textures install-themes install-ttk-themes install-text-scripts \
	install-images install-help install-config install-photos \
	SHAREDIR="$DIST" DATADIR="$DIST" BINDIR="$DIST"
make -s -C "$BUILD/src" install-data install-hyphen SHAREDIR="$DIST"

# install-scripts puts the bundle under the program's name; Windows would
# take a file named .exe for a program.
rm -f "$DIST/chesswiz.exe"
cp "$BUILD/tcl/chesswiz.exe" "$DIST/chesswiz.tcl"
cp "$BUILD/src/tkchesswiz.exe" "$DIST/"

for d in tcl8.6 tk8.6 tcl8; do
	cp -R "$SYSROOT/lib/$d" "$DIST/lib/"
done

echo "make-windows-dist: $DIST ($(du -sh "$DIST" | cut -f1))"
