#!/usr/bin/env bash
# Build both native Stockfish slices in scratch copies; embed vendored NNUE.
# Usage: build-macos-engines.sh [OUT_DIR]; SF_ARCHS=x86_64 for Intel only.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/engines-macos}"
export MACOSX_DEPLOYMENT_TARGET=11.0
grep -q '^#define EvalFileDefaultName "nn-1a298aa575a0.nnue"' "$ROOT/engines/stockfish/src/evaluate.h" || {
    echo 'Stockfish network changed: update the pinned network before building.' >&2; exit 1;
}
# Never let upstream's net target fetch an unpinned replacement.
echo "1a298aa575a085434d29027978dc36867fe9c5bcea9376654b7a8eba1e52dfc2  $ROOT/engines/stockfish/src/nn-1a298aa575a0.nnue" | shasum -a 256 -c -
mkdir -p "$OUT"
SLICES=()
for cpu in ${SF_ARCHS:-x86_64 arm64}; do
    case "$cpu" in x86_64) arch=x86-64;; arm64) arch=armv8;; *) exit 2;; esac
    WORK="$ROOT/build/sf-macos-$cpu"
    rm -rf "$WORK"
    mkdir -p "$WORK"
    cp -R "$ROOT/engines/stockfish/src" "$ROOT/engines/stockfish/scripts" "$WORK/"
    make -s -C "$WORK/src" clean > /dev/null
    make -C "$WORK/src" -j"${JOBS:-$(sysctl -n hw.ncpu)}" build ARCH="$arch" COMP=clang \
        CXX=clang++ mac_target_flags="-arch $cpu -mmacosx-version-min=11.0" \
        > "$WORK/build.log" 2>&1 || { tail -30 "$WORK/build.log"; exit 1; }
    cp "$WORK/src/stockfish" "$OUT/stockfish-$cpu"
    SLICES+=("$OUT/stockfish-$cpu")
done
lipo -create "${SLICES[@]}" -output "$OUT/stockfish-chesswiz"
chmod +x "$OUT/stockfish-chesswiz"
lipo -info "$OUT/stockfish-chesswiz"

# Sjeng 11.2 (C) with the vendored gdbm, one slice per CPU, then lipo.
SJ="$ROOT/build/sjeng-macos"
rm -rf "$SJ"; mkdir -p "$SJ/gdbm"
cp "$ROOT"/engines/Sjeng/*.[ch] "$SJ/"
cp "$ROOT"/src/util/gdbm/*.[ch] "$SJ/gdbm/"
SJ_SLICES=()
for cpu in ${SF_ARCHS:-x86_64 arm64}; do
    CC_SJ="clang -arch $cpu -mmacosx-version-min=11.0 -O2 -w"
    rm -f "$SJ"/gdbm/*.o
    for f in "$SJ"/gdbm/*.c; do $CC_SJ -c "$f" -o "${f%.c}.o"; done
    ( cd "$SJ" && $CC_SJ -std=gnu11 -fcommon -DSCIDB_VERSION=1 -Igdbm \
        attacks.c crazy.c epd.c learn.c partner.c seval.c ttable.c book.c \
        ecache.c eval.c moves.c search.c sjeng.c utils.c newbook.c proof.c \
        neval.c rcfile.c leval.c draw.c see.c probe.c segtb.c gdbm/*.o \
        -o "$OUT/sjeng-$cpu" )
    SJ_SLICES+=("$OUT/sjeng-$cpu")
done
lipo -create "${SJ_SLICES[@]}" -output "$OUT/sjeng-chesswiz"
lipo -info "$OUT/sjeng-chesswiz"

# Reckless 0.9.0 (Rust). With cargo and the Apple targets it is built here;
# otherwise the slices cross-built on Linux by build-macos-reckless.sh
# (copied into OUT_DIR as reckless-x86_64 / reckless-arm64) are combined.
RK_SLICES=()
if command -v cargo >/dev/null; then
    RK="$ROOT/build/reckless-macos"
    mkdir -p "$RK"
    rsync -a --delete --exclude target --exclude reckless-chesswiz --exclude reckless-scidb \
        "$ROOT/engines/reckless/" "$RK/src/"
    for cpu in ${SF_ARCHS:-x86_64 arm64}; do
        case "$cpu" in x86_64) t=x86_64-apple-darwin; c=x86-64-v2;; arm64) t=aarch64-apple-darwin; c=apple-m1;; esac
        ( cd "$RK/src" && GIT_DIR=/nonexistent MACOSX_DEPLOYMENT_TARGET=11.0 RUSTFLAGS="-C target-cpu=$c" \
            cargo build --release --quiet --target "$t" ) > "$RK/build-$cpu.log" 2>&1 \
            || { echo "build-macos-engines: WARNING: Reckless $cpu failed (see $RK/build-$cpu.log)" >&2; RK_SLICES=(); break; }
        cp "$RK/src/target/$t/release/reckless" "$OUT/reckless-$cpu"
        RK_SLICES+=("$OUT/reckless-$cpu")
    done
else
    for cpu in ${SF_ARCHS:-x86_64 arm64}; do
        [ -f "$OUT/reckless-$cpu" ] && RK_SLICES+=("$OUT/reckless-$cpu")
    done
    [ ${#RK_SLICES[@]} -gt 0 ] || echo "build-macos-engines: WARNING: no cargo and no cross-built slices (scripts/build-macos-reckless.sh); Reckless not built" >&2
fi
if [ ${#RK_SLICES[@]} -gt 0 ]; then
    lipo -create "${RK_SLICES[@]}" -output "$OUT/reckless-chesswiz"
    chmod +x "$OUT/reckless-chesswiz"
    lipo -info "$OUT/reckless-chesswiz"
fi
