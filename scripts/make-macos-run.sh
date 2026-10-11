#!/usr/bin/env bash
# Assemble a minimal, unsigned Aqua .app from a configured native build.
# Usage: make-macos-run.sh [BUILD_DIR] [APP_DIR] [TCL_TK_SYSROOT]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$(cd "${1:-$ROOT}" && pwd)"
APP="${2:-$BUILD/build/dist/Chesswiz.app}"
SYSROOT="${3:-$HOME/cw/sysroot}"
[ -x "$BUILD/src/tkchesswiz" ] || { echo 'Build tkchesswiz first.' >&2; exit 1; }
[ -d "$SYSROOT/lib/tk8.6" ] || { echo 'Tcl/Tk script libraries missing.' >&2; exit 1; }
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/lib"
APP="$(cd "$APP" && pwd)"
RES="$APP/Contents/Resources"
export LC_ALL=C
make -C "$BUILD/tcl" install-scripts install-pieces install-cursors install-flags \
    install-localizations install-textures install-themes install-ttk-themes \
    install-text-scripts install-images install-help install-config install-photos \
    BINDIR="$RES" SHAREDIR="$RES" DATADIR="$RES"
make -C "$BUILD/src" install-data install-hyphen SHAREDIR="$RES"
mv "$RES/chesswiz" "$RES/chesswiz.tcl"
cp "$BUILD/src/tkchesswiz" "$APP/Contents/MacOS/"
for library in tcl8.6 tk8.6 tcl8; do
    if [ -d "$SYSROOT/lib/$library" ]; then
        mkdir -p "$RES/lib/$library"
        cp -R "$SYSROOT/lib/$library/." "$RES/lib/$library/"
    fi
done
# Tk Aqua redirects stdout/stderr to /dev/null for a null character-device stdin.
# A regular empty file keeps startup diagnostics attached to our log files.
: > "$RES/empty-stdin"
mkdir -p "$RES/fonts"
cp "$ROOT"/tcl/fonts/*.ttf "$RES/fonts/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>chesswiz</string>
<key>CFBundleIdentifier</key><string>org.chesswiz.Chesswiz</string>
<key>CFBundleName</key><string>Chesswiz</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
cat > "$APP/Contents/MacOS/chesswiz" <<'LAUNCHER'
#!/bin/bash
CONTENTS="$(cd "$(dirname "$0")/.." && pwd)"
export TCL_LIBRARY="$CONTENTS/Resources/lib/tcl8.6"
export TK_LIBRARY="$CONTENTS/Resources/lib/tk8.6"
export SCIDB_SHAREDIR="$CONTENTS/Resources"
LOGDIR="${CW_LOGDIR:-$HOME/Library/Logs/Chesswiz}"
mkdir -p "$LOGDIR"
SCRIPT="$CONTENTS/Resources/chesswiz.tcl"
if [ -n "${CW_STARTUP_HARNESS:-}" ]; then
    set -- "$SCRIPT" "$@"
    SCRIPT="$CW_STARTUP_HARNESS"
fi
exec "$CONTENTS/MacOS/tkchesswiz" -encoding utf-8 "$SCRIPT" "$@" \
    <"$CONTENTS/Resources/empty-stdin" >>"$LOGDIR/stdout.log" 2>>"$LOGDIR/stderr.log"
LAUNCHER
chmod +x "$APP/Contents/MacOS/chesswiz"
echo "$APP"
