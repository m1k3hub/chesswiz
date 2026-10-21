#!/usr/bin/env bash
# Build pinned static universal2 Tcl/Tk Aqua for the native application.
# Usage: build-macos-runtime.sh [PREFIX]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/sysroot-pins.sh"
PREFIX="${1:-$HOME/cw/sysroot-universal}"
WORK="$ROOT/build/macos-runtime"
CACHE="$ROOT/build/src"
export MACOSX_DEPLOYMENT_TARGET=11.0
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"
mkdir -p "$WORK" "$CACHE" "$PREFIX"
for pkg in TCL TK; do
    eval 'name=$'"${pkg}_TARBALL"' url=$'"${pkg}_URL"' sha=$'"${pkg}_SHA256"
    [ -f "$CACHE/$name" ] || curl -fL --retry 3 "$url" -o "$CACHE/$name"
    echo "$sha  $CACHE/$name" | shasum -a 256 -c -
    tar xf "$CACHE/$name" -C "$WORK"
done
# Keep [update] finite and grabbed dialogs alive through deferred Aqua focus.
for p in hidden-dirty offview-dirty grab-focus; do
    patch -d "$WORK/tk$TK_VER" -p1 < "$ROOT/scripts/patches/tk-8.6.17-aqua-$p.patch"
done
FLAGS='-arch x86_64 -arch arm64 -mmacosx-version-min=11.0'
rm -rf "$WORK/tcl-obj" "$WORK/tk-obj"
mkdir -p "$WORK/tcl-obj" "$WORK/tk-obj"
(
    cd "$WORK/tcl-obj"
    CC=clang CFLAGS="$FLAGS -O2" LDFLAGS="$FLAGS" \
        "$WORK/tcl$TCL_VER/unix/configure" --prefix="$PREFIX" --disable-shared --enable-threads --enable-64bit
    make -j"$JOBS" binaries
    make install-binaries install-libraries install-headers install-private-headers
) > "$WORK/tcl.log" 2>&1
(
    cd "$WORK/tk-obj"
    CC=clang CFLAGS="$FLAGS -O2" LDFLAGS="$FLAGS" \
        "$WORK/tk$TK_VER/unix/configure" --prefix="$PREFIX" --with-tcl="$PREFIX/lib" \
            --disable-shared --enable-aqua --enable-threads
    make -j"$JOBS" binaries
    make install-binaries install-libraries install-headers install-private-headers
) > "$WORK/tk.log" 2>&1
cp "$PREFIX/include/tcl-private/generic/"*.h "$PREFIX/include/" 2>/dev/null || true
cp "$PREFIX/include/tcl-private/unix/"*.h "$PREFIX/include/" 2>/dev/null || true
for dir in generic macosx; do
    mkdir -p "$PREFIX/include/tk-private/$dir"
    cp "$WORK/tk$TK_VER/$dir/"*.h "$PREFIX/include/tk-private/$dir/"
done
lipo -info "$PREFIX/lib/libtcl8.6.a" "$PREFIX/lib/libtk8.6.a"
