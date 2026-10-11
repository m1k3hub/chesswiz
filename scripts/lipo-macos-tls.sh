#!/usr/bin/env bash
# Usage: lipo-macos-tls.sh X86_SYSROOT ARM_SYSROOT [OUTPUT_SYSROOT]
# Output defaults to ARM_SYSROOT, preserving its universal Tcl/Tk runtime.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/sysroot-pins.sh"
INTEL="$(cd "$1" && pwd)"
ARM="$(cd "$2" && pwd)"
OUT="${3:-$ARM}"
for prefix in "$INTEL" "$ARM"; do
    [ "$(cat "$prefix/lib/openssl-build-version")" = "$OPENSSL_VER" ]
done
mkdir -p "$OUT/lib/tls$TCLTLS_VER"
WORK="$(mktemp -d "$OUT/lib/cw-tls-lipo.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
thin() {
    if [ "$(lipo -archs "$1")" = "$2" ]; then cp "$1" "$3"
    else lipo "$1" -thin "$2" -output "$3"; fi
}
for lib in libssl.a libcrypto.a "tls$TCLTLS_VER/tcltls.dylib"; do
    thin "$INTEL/lib/$lib" x86_64 "$WORK/intel"
    thin "$ARM/lib/$lib" arm64 "$WORK/arm"
    lipo -create "$WORK/intel" "$WORK/arm" -output "$OUT/lib/$lib.universal"
    mv "$OUT/lib/$lib.universal" "$OUT/lib/$lib"
    lipo "$OUT/lib/$lib" -verify_arch x86_64 arm64
done
if [ "$OUT" != "$ARM" ]; then
    cp "$ARM/lib/tls$TCLTLS_VER/"*.tcl "$OUT/lib/tls$TCLTLS_VER/"
    cp -R "$ARM/lib/json" "$OUT/lib/"
    cp "$ARM/cacert.pem" "$OUT/"
fi
install_name_tool -id @rpath/tcltls.dylib "$OUT/lib/tls$TCLTLS_VER/tcltls.dylib"
echo "Universal static OpenSSL and loadable TclTLS: $OUT"
