#!/usr/bin/env bash
# scripts/build-macos-reckless.sh [OUT_DIR]
#
# Cross-compiles Reckless 0.9.0 (engines/reckless) for macOS on Linux, with
# zig as C compiler, archiver and linker, so the Mac build machine needs no
# Rust toolchain. Writes OUT_DIR/reckless-x86_64 and reckless-arm64 (default
# build/engines-macos); copy them into the Mac's build/engines-macos and
# build-macos-engines.sh combines and make-macos-app.sh signs them.
# Needs: rustup target add x86_64-apple-darwin aarch64-apple-darwin
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/engines-macos}"
RK="$ROOT/build/reckless-macos-cross"
mkdir -p "$OUT" "$RK"
rsync -a --delete --exclude target --exclude reckless-chesswiz --exclude reckless-scidb \
	"$ROOT/engines/reckless/" "$RK/src/"
printf '#!/bin/sh\nexec zig ar --format=darwin "$@"\n' > "$RK/ar"
chmod +x "$RK/ar"

for cpu in x86_64 arm64; do
	case "$cpu" in
	x86_64) z=x86_64;  t=x86_64-apple-darwin;  c=x86-64-v2;;
	arm64)  z=aarch64; t=aarch64-apple-darwin; c=apple-m1;;
	esac
	shim="$RK/shim-$cpu"
	mkdir -p "$shim"
	# build.rs hard-codes "clang" for Fathom: a shim on PATH sends it to zig.
	cat > "$shim/clang" <<SH
#!/bin/sh
for a in "\$@"; do case "\$a" in --target=*|-m64|-arch|x86_64|arm64) ;; *) set -- "\$@" "\$a";; esac; shift; done
exec zig cc -target $z-macos.11.0 "\$@"
SH
	cat > "$shim/zigcc-link" <<SH
#!/bin/sh
for a in "\$@"; do case "\$a" in -arch|x86_64|arm64|-mmacosx-version-min=*|-nodefaultlibs) ;; *) set -- "\$@" "\$a";; esac; shift; done
exec zig cc -target $z-macos.11.0 "\$@"
SH
	chmod +x "$shim"/*
	T_UP="$(echo "$t" | tr 'a-z-' 'A-Z_')"
	( cd "$RK/src" && env PATH="$shim:$PATH" GIT_DIR=/nonexistent \
		"AR_$t=$RK/ar" "CARGO_TARGET_${T_UP}_LINKER=$shim/zigcc-link" \
		RUSTFLAGS="-C target-cpu=$c" \
		cargo build --release --quiet --target "$t" ) > "$RK/build-$cpu.log" 2>&1 \
		|| { tail -30 "$RK/build-$cpu.log"; exit 1; }
	cp "$RK/src/target/$t/release/reckless" "$OUT/reckless-$cpu"
	echo "build-macos-reckless: $OUT/reckless-$cpu ($c)"
done
