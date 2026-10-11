#!/usr/bin/env bash
# Usage: make-macos-app.sh [BUILD_DIR] [APP_DIR] [SYSROOT] [ENGINE_DIR]
# CHESSWIZ_SIGN_ID defaults to ad-hoc '-'; CHESSWIZ_VERSION defaults to 1.0.1493.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$(cd "${1:-$ROOT}" && pwd)"
APP="${2:-$BUILD/build/dist/Chesswiz.app}"
SYSROOT="${3:-$HOME/cw/sysroot}"
ENGINE_DIR="${4:-$BUILD/build/engines-macos}"
case "$APP" in *.app) ;; *) echo 'APP_DIR must end in .app' >&2; exit 2;; esac
SIGN_ID="${CHESSWIZ_SIGN_ID:--}"
VERSION="${CHESSWIZ_VERSION:-1.0.1493}"
[ -f "$SYSROOT/cacert.pem" ] && [ -f "$SYSROOT/lib/json/pkgIndex.tcl" ]
[ -x "$ENGINE_DIR/stockfish-scidb" ]
TLS=("$SYSROOT"/lib/tls*)
[ -f "${TLS[0]}/pkgIndex.tcl" ]
mkdir -p "$(dirname "$APP")"
STAGE="$(mktemp -d "$(dirname "$APP")/cw-package.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
"$ROOT/scripts/make-macos-run.sh" "$BUILD" "$STAGE/Chesswiz.app" "$SYSROOT"
RES="$STAGE/Chesswiz.app/Contents/Resources"
cp -R "$SYSROOT/lib/json" "${TLS[@]}" "$RES/lib/"
cp "$SYSROOT/cacert.pem" "$RES/"
mkdir -p "$RES/engines"
cp "$ENGINE_DIR/stockfish-scidb" "$RES/engines/"
# Include distribution notices and engine source licensing beside the executable.
for f in COPYING LICENSE README; do
    [ ! -f "$ROOT/$f" ] || cp "$ROOT/$f" "$RES/"
done
cp "$ROOT/engines/stockfish/Copying.txt" "$RES/engines/Stockfish-Copying.txt"
ICONSET="$STAGE/Chesswiz.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ROOT/icons/chesswiz-512.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$ROOT/icons/chesswiz-512.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$RES/Chesswiz.icns"
python3 - "$STAGE/Chesswiz.app/Contents/Info.plist" "$VERSION" <<'PY'
import plistlib, sys
p, version = sys.argv[1:]
with open(p, 'rb') as f: info = plistlib.load(f)
info.update(CFBundleShortVersionString=version, CFBundleVersion=version,
            CFBundleIconFile='Chesswiz.icns', LSMinimumSystemVersion='11.0',
            NSPrincipalClass='NSApplication',
            CFBundleDocumentTypes=[dict(CFBundleTypeName='Portable Game Notation',
                CFBundleTypeExtensions=['pgn'], CFBundleTypeRole='Editor',
                LSHandlerRank='Alternate', LSItemContentTypes=['org.chesswiz.pgn'])],
            UTExportedTypeDeclarations=[dict(UTTypeIdentifier='org.chesswiz.pgn',
                UTTypeDescription='Portable Game Notation', UTTypeConformsTo=['public.plain-text'],
                UTTypeTagSpecification={'public.filename-extension': ['pgn']})])
with open(p, 'wb') as f: plistlib.dump(info, f)
PY
# Sign every Mach-O leaf first (TLS and engine included), then the app envelope.
SIGN_ARGS=(--force --deep -s "$SIGN_ID")
if [ "$SIGN_ID" != - ]; then SIGN_ARGS+=(--timestamp --options runtime); fi
# The finder goes to a file first: macOS's bash 3.2 can't parse a heredoc
# inside a process substitution.
cat > "$STAGE/find-macho.py" <<'PYCODE'
import os, sys
magic = {bytes.fromhex(h) for h in (
    'feedface', 'cefaedfe', 'feedfacf', 'cffaedfe',
    'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca')}
for root, _, files in os.walk(sys.argv[1]):
    for name in files:
        path = os.path.join(root, name)
        if os.path.islink(path):
            continue
        with open(path, 'rb') as f:
            if f.read(4) in magic:
                sys.stdout.buffer.write(os.fsencode(path) + b'\0')
PYCODE
while IFS= read -r -d '' f; do
    codesign "${SIGN_ARGS[@]}" "$f"
done < <(python3 "$STAGE/find-macho.py" "$STAGE/Chesswiz.app")
codesign "${SIGN_ARGS[@]}" "$STAGE/Chesswiz.app"
codesign --verify --deep --strict "$STAGE/Chesswiz.app"
rm -rf "$APP"
ditto "$STAGE/Chesswiz.app" "$APP"
mkdir -p "$STAGE/dmg"
ditto "$APP" "$STAGE/dmg/Chesswiz.app"
ln -s /Applications "$STAGE/dmg/Applications"
DMG="${CHESSWIZ_DMG:-$(dirname "$APP")/Chesswiz.dmg}"
hdiutil create -ov -format UDZO -volname Chesswiz -srcfolder "$STAGE/dmg" "$DMG"
if [ "$SIGN_ID" != - ]; then codesign --force -s "$SIGN_ID" --timestamp "$DMG"; fi
echo "App: $APP"
echo "DMG: $DMG"
