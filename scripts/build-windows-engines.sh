#!/usr/bin/env bash
# scripts/build-windows-engines.sh [OUT_DIR]
#
# Cross-compiles the bundled Stockfish (engines/stockfish) for Windows with
# zig into OUT_DIR (default build/engines-win) as stockfish-scidb.exe, the
# name engines.dat expects (Windows adds .exe).
#
# Built in a scratch copy, so the Linux engine build is untouched. Link
# time optimisation is switched off there: with -flto=full, lld can't
# resolve the MinGW libm/wchar symbols from zig's libc++.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/engines-win}"
WORK="$ROOT/build/sf-win"
ARCH="${SF_ARCH:-x86-64-avx2}"

rm -rf "$WORK"
mkdir -p "$WORK" "$OUT"
cp -R "$ROOT/engines/stockfish/src" "$ROOT/engines/stockfish/scripts" "$WORK/"
cp "$ROOT"/engines/stockfish/src/*.nnue "$WORK/src/" 2>/dev/null || true

sed -i \
	-e 's/CXXFLAGS += -flto=full/CXXFLAGS +=/' \
	-e 's/CXXFLAGS += -flto -flto-partition=one/CXXFLAGS +=/' \
	-e 's/LDFLAGS += \$(CXXFLAGS) -flto=jobserver/LDFLAGS += $(CXXFLAGS)/' \
	"$WORK/src/Makefile"

make -s -C "$WORK/src" clean >/dev/null 2>&1 || true
make -C "$WORK/src" -j"$(nproc)" build ARCH="$ARCH" COMP=clang \
	CXX="zig c++ -target x86_64-windows-gnu" OS=Windows_NT EXE=stockfish.exe \
	> "$WORK/build.log" 2>&1 || { tail -20 "$WORK/build.log"; exit 1; }

cp "$WORK/src/stockfish.exe" "$OUT/stockfish-scidb.exe"
echo "build-windows-engines: $OUT/stockfish-scidb.exe ($ARCH)"
