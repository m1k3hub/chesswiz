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
#     lib/json lib/sha1     tcllib modules (from the sysroot; sha1 ships sha256)
#     lib/tls*              loadable TLS extension (static OpenSSL)
#     cacert.pem            Mozilla CA roots for TLS verification
#     data/ hyphen/ lang/ pieces/ themes/ ...   share files (share dir = exe dir)
#     fonts/              registered privately at startup (spec D8)
#
#     engines/            engines.dat, plus build/engines-win/*-chesswiz.exe if built
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$(cd "${1:-$ROOT/build/wt-win}" && pwd)"
DIST="${2:-$ROOT/build/dist/Chesswiz}"
# absolute: the install targets below run make -C in other directories
case "$DIST" in /*) ;; *) DIST="$PWD/$DIST" ;; esac
SYSROOT="$ROOT/build/x86_64-windows-gnu"

die() { echo "make-windows-dist: $*" >&2; exit 1; }

[ -f "$BUILD/src/tkchesswiz.exe" ] || die "no $BUILD/src/tkchesswiz.exe; build first"
[ -f "$BUILD/tcl/chesswiz.exe" ]   || die "no script bundle $BUILD/tcl/chesswiz.exe; run make -C tcl"
[ -d "$SYSROOT/lib/tcl8.6" ]       || die "no sysroot at $SYSROOT; run scripts/build-sysroot.sh"
TLS_PACKAGES=("$SYSROOT"/lib/tls*)
[ -d "${TLS_PACKAGES[0]}" ]        || die "no TLS package; run scripts/build-sysroot.sh x86_64-windows-gnu --tls-only"
[ -f "$SYSROOT/cacert.pem" ]      || die "no CA bundle; run scripts/build-sysroot.sh x86_64-windows-gnu --tls-only"

[ -f "$SYSROOT/cacert.pem" ] || die "no CA bundle; run scripts/build-sysroot.sh x86_64-windows-gnu --tls-only"
compgen -G "$SYSROOT/lib/tls*/pkgIndex.tcl" >/dev/null || die "no TLS package; run scripts/build-sysroot.sh x86_64-windows-gnu --tls-only"

rm -rf "$DIST"
mkdir -p "$DIST/lib"

# Share files, through the regular install targets (fonts excluded: they
# run Linux font tools).
make -s -C "$BUILD/tcl" \
	install-scripts install-pieces install-cursors install-flags install-localizations \
	install-textures install-themes install-ttk-themes install-text-scripts \
	install-images install-help install-config install-photos install-sample \
	SHAREDIR="$DIST" DATADIR="$DIST" BINDIR="$DIST"
# install-scripts: plain.eXt, which every TeXt script (tournament tables,
# player cards) inputs first
make -s -C "$BUILD/src" install-data install-hyphen install-scripts SHAREDIR="$DIST"

# The generated registry pack ships with the selected source tree. A cross
# build cannot run install-knowledge's target executable on the build host.
mkdir -p "$DIST/knowledge"
cp "$BUILD"/share/knowledge/* "$DIST/knowledge/"

# install-scripts puts the bundle under the program's name; Windows would
# take a file named .exe for a program.
rm -f "$DIST/chesswiz.exe"
cp "$BUILD/tcl/chesswiz.exe" "$DIST/chesswiz.tcl"
cp "$BUILD/src/tkchesswiz.exe" "$DIST/"

# Registered privately by tkchesswiz.exe at startup.
mkdir -p "$DIST/fonts"
cp "$ROOT"/tcl/fonts/*.ttf "$DIST/fonts/"

# Engines from scripts/build-windows-engines.sh, when built.
if [ -d "$ROOT/build/engines-win" ]; then
	mkdir -p "$DIST/engines"
	cp "$ROOT"/build/engines-win/*-chesswiz.exe "$DIST/engines/"
	# Each engine's licence beside it (GPL-3, GPL-2, AGPL-3).
	cp "$ROOT/engines/stockfish/Copying.txt" "$DIST/engines/Stockfish-Copying.txt"
	[ ! -f "$DIST/engines/sjeng-chesswiz.exe" ] || cp "$ROOT/engines/Sjeng/COPYING" "$DIST/engines/Sjeng-Copying.txt"
	[ ! -f "$DIST/engines/reckless-chesswiz.exe" ] || cp "$ROOT/engines/reckless/LICENSE" "$DIST/engines/Reckless-License.txt"
fi

# Bundled Dutch Swiss pairing helper (bbpPairings v6.0.0) when built.
for cand in "$BUILD/build/bbp-x86_64-windows-gnu/bbpPairings.exe" "$ROOT/build/bbp-x86_64-windows-gnu/bbpPairings.exe"; do
	if [ -f "$cand" ]; then
		cp "$cand" "$DIST/bbpPairings.exe"
		mkdir -p "$DIST/engines"
		cp "$ROOT/engines/bbpPairings/LICENSE.txt" "$DIST/engines/bbpPairings-LICENSE.txt"
		cp "$ROOT/engines/bbpPairings/Apache-2.0.txt" "$DIST/engines/bbpPairings-Apache-2.0.txt"
		break
	fi
done

for d in tcl8.6 tk8.6 tcl8 json sha1; do
	cp -R "$SYSROOT/lib/$d" "$DIST/lib/"
done

# The TLS builder installs the complete package, including pkgIndex.tcl.
for d in "${TLS_PACKAGES[@]}"; do
	cp -R "$d" "$DIST/lib/"
done
cp "$SYSROOT/cacert.pem" "$DIST/"

echo "make-windows-dist: $DIST ($(du -sh "$DIST" | cut -f1))"
