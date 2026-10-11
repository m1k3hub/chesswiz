#!/usr/bin/env bash
# Usage: build-macos-app-binary.sh BUILD_DIR SYSROOT ["x86_64 arm64"]
# Use a scratch copy; this removes all compiled objects (no header tracking).
set -euo pipefail
BUILD="$(cd "$1" && pwd)"
SYSROOT="$(cd "$2" && pwd)"
ARCHS="${3:-x86_64 arm64}"
[ "$(uname -s)" = Darwin ] || { echo 'Run this builder on macOS.' >&2; exit 1; }
export MACOSX_DEPLOYMENT_TARGET=11.0
FLAGS='-mmacosx-version-min=11.0'
for cpu in $ARCHS; do
    case "$cpu" in x86_64|arm64) FLAGS="$FLAGS -arch $cpu";; *) exit 2;; esac
done
cd "$BUILD"
mkdir -p build/bin
printf '#!/bin/sh\nexec clang %s "$@"\n' "$FLAGS" > build/bin/maccc
printf '#!/bin/sh\nexec clang++ %s "$@"\n' "$FLAGS" > build/bin/maccxx
chmod +x build/bin/maccc build/bin/maccxx
find src -type f \( -name '*.o' -o -name '*.a' \) -delete
rm -f src/tkchesswiz src/tclchesswiz src/cbh2si4 src/cdb2sci
PATH="$SYSROOT/bin:$PATH" ./configure --prefix="$BUILD/build/install" \
    --exec-prefix="$BUILD/build/install" --gcc-version=clang \
    --tcl-includes="$SYSROOT/include" --tcl-libraries="$SYSROOT/lib" \
    --tk-includes="$SYSROOT/include" --tk-libraries="$SYSROOT/lib" \
    CC="$BUILD/build/bin/maccc" CXX="$BUILD/build/bin/maccxx" MEDIA_BACKEND=avf
make -C src -j"${JOBS:-$(sysctl -n hw.ncpu)}" MEDIA_BACKEND=avf
# Recombine explicitly, retaining just the requested architectures.
SLICES=()
for cpu in $ARCHS; do
    if [[ "$ARCHS" = *' '* ]]; then
        lipo src/tkchesswiz -thin "$cpu" -output "src/tkchesswiz-$cpu"
    else
        cp src/tkchesswiz "src/tkchesswiz-$cpu"
    fi
    SLICES+=("src/tkchesswiz-$cpu")
done
if [ "${#SLICES[@]}" -gt 1 ]; then
    lipo -create "${SLICES[@]}" -output src/tkchesswiz
fi
lipo -info src/tkchesswiz
