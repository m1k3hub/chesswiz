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
lipo -create "${SLICES[@]}" -output "$OUT/stockfish-scidb"
chmod +x "$OUT/stockfish-scidb"
lipo -info "$OUT/stockfish-scidb"
