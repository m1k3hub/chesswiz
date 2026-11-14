#!/usr/bin/env bash
# Offline build of the pinned, separately licensed Dutch pairing helper.
# bash scripts/build-bbp-pairings.sh [native|x86_64-windows-gnu|x86_64-macos|aarch64-macos] [output]
set -euo pipefail
export SOURCE_DATE_EPOCH=1767225600
root="$(cd "$(dirname "$0")/.." && pwd)"
target="${1:-native}"
out="${2:-$root/build/bbp-$target}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
compiler=(g++)
name=bbpPairings
if [[ "$target" != native ]]; then
    compiler=(zig c++ -target "$target")
fi
if [[ "$target" == *windows* ]]; then name+=.exe; fi
mapfile -t sources < <(find "$root/engines/bbpPairings/src" -name '*.cpp' -print | sort)
"${compiler[@]}" -std=c++20 -Wno-date-time -O2 -DNDEBUG '-DVERSION_INFO="v6.0.0"' \
    -I"$root/engines/bbpPairings/src" "${sources[@]}" -o "$out/$name"
cp "$root/engines/bbpPairings/"{LICENSE.txt,Apache-2.0.txt,README.txt} "$out/"
printf '%s\n' 'bbpPairings v6.0.0: 16a000f9811de322b0e835d5643198226165b5a9' > "$out/SOURCE.txt"
if [[ "$target" != native ]]; then
    ziglib=$(zig env | python3 -c 'import json,sys; print(json.load(sys.stdin)["lib_dir"])')
    mkdir -p "$out/runtime-notices"
    cp "$ziglib/libcxx/LICENSE.TXT" "$out/runtime-notices/libcxx.txt"
    cp "$ziglib/libcxxabi/LICENSE.TXT" "$out/runtime-notices/libcxxabi.txt"
    cp "$ziglib/libunwind/LICENSE.TXT" "$out/runtime-notices/libunwind.txt"
    if [[ "$target" == *windows* ]]; then cp "$ziglib/libc/mingw/COPYING" "$out/runtime-notices/mingw.txt"; fi
fi
echo "Built $out/$name"
