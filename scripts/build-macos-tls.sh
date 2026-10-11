#!/usr/bin/env bash
# Native macOS loadable TclTLS, with static OpenSSL; shared Windows pins.
# Usage: build-macos-tls.sh [SYSROOT] [ARCH]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/sysroot-pins.sh"
PREFIX="${1:-$HOME/cw/sysroot}"
ARCH="${2:-x86_64}"
export MACOSX_DEPLOYMENT_TARGET=11.0
WORK="$ROOT/build/macos-tls-$ARCH"
CACHE="$ROOT/build/src"
JOBS="${JOBS:-$(sysctl -n hw.ncpu)}"
mkdir -p "$WORK" "$CACHE" "$PREFIX/lib"
fetch() {
    local name="$1" url="$2" sha="$3"
    if [ ! -f "$CACHE/$name" ]; then curl -fL --retry 3 "$url" -o "$CACHE/$name"; fi
    echo "$sha  $CACHE/$name" | shasum -a 256 -c -
}
fetch "$OPENSSL_TARBALL" "$OPENSSL_URL" "$OPENSSL_SHA256"
fetch "$TCLTLS_TARBALL" "$TCLTLS_URL" "$TCLTLS_SHA256"
fetch "$TCLLIB_TARBALL" "$TCLLIB_URL" "$TCLLIB_SHA256"
fetch "$CACERT_FILE" "$CACERT_URL" "$CACERT_SHA256"
# Fresh sources ensure patches and architecture changes are repeatable.
rm -rf "$WORK/openssl-$OPENSSL_VER" "$WORK/tcltls-$TCLTLS_VER" "$WORK/tls-obj" "$WORK/tcllib-$TCLLIB_VER"
tar xf "$CACHE/$OPENSSL_TARBALL" -C "$WORK"
case "$ARCH" in x86_64) TARGET=darwin64-x86_64-cc;; arm64) TARGET=darwin64-arm64-cc;; *) exit 2;; esac
(
    cd "$WORK/openssl-$OPENSSL_VER"
    ./Configure "$TARGET" no-shared no-tests no-docs --prefix="$PREFIX" --libdir=lib -mmacosx-version-min=11.0
    make -j"$JOBS" build_libs
    make install_dev
) > "$WORK/openssl.log" 2>&1
tar xf "$CACHE/$TCLTLS_TARBALL" -C "$WORK"
patch -d "$WORK/tcltls-$TCLTLS_VER" -p1 < "$ROOT/scripts/patches/tcltls-1.7.22-hostname.patch"
mkdir -p "$WORK/tls-obj"
CROSS=()
if [ "$ARCH" = arm64 ] && [ "$(uname -m)" != arm64 ]; then
    CROSS=(--build=x86_64-apple-darwin --host=aarch64-apple-darwin)
fi
(
    cd "$WORK/tls-obj"
    CC="clang -arch $ARCH" CPPFLAGS="-I$PREFIX/include" \
    TCLTLS_SSL_LIBS="$PREFIX/lib/libssl.a $PREFIX/lib/libcrypto.a" \
    TCLTLS_SSL_CFLAGS="-I$PREFIX/include" TCLTLS_SSL_CPPFLAGS="-I$PREFIX/include" \
        "$WORK/tcltls-$TCLTLS_VER/configure" --prefix="$PREFIX" --with-tcl="$PREFIX/lib" \
            --enable-shared --enable-stubs --enable-deterministic "${CROSS[@]}"
    make -j"$JOBS"
    make install
) > "$WORK/tcltls.log" 2>&1
rm -rf "$PREFIX/lib/tls$TCLTLS_VER"
mv "$PREFIX/lib/tcltls$TCLTLS_VER" "$PREFIX/lib/tls$TCLTLS_VER"
tar xf "$CACHE/$TCLLIB_TARBALL" -C "$WORK"
mkdir -p "$PREFIX/lib/json"
cp "$WORK/tcllib-$TCLLIB_VER/modules/json/"*.tcl "$PREFIX/lib/json/"
cp "$CACHE/$CACERT_FILE" "$PREFIX/"
printf '%s\n' "$OPENSSL_VER" > "$PREFIX/lib/openssl-build-version"
echo "TLS, json, CA roots installed: $PREFIX ($ARCH)"
