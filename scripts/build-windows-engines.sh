#!/usr/bin/env bash
# scripts/build-windows-engines.sh [OUT_DIR]
#
# Cross-compiles the bundled engines for Windows with zig into OUT_DIR
# (default build/engines-win) under the names engines.dat expects (Windows
# adds .exe): stockfish-chesswiz.exe, sjeng-chesswiz.exe (with the vendored
# gdbm from src/util/gdbm) and reckless-chesswiz.exe (cargo; needs
# `rustup target add x86_64-pc-windows-gnu`; skipped with a warning when
# cargo or the target is missing, or when ENGINES does not list it).
# ENGINES selects a subset, e.g. ENGINES="stockfish sjeng".
#
# Built in a scratch copy, so the Linux engine build is untouched. Link
# time optimisation is switched off there: with -flto=full, lld can't
# resolve the MinGW libm/wchar symbols from zig's libc++.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/engines-win}"
WORK="$ROOT/build/sf-win"
ARCH="${SF_ARCH:-x86-64-avx2}"

ENGINES="${ENGINES:-stockfish sjeng reckless}"
mkdir -p "$OUT"

want() { case " $ENGINES " in *" $1 "*) return 0;; esac; return 1; }

if want stockfish; then
rm -rf "$WORK"
mkdir -p "$WORK"
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

cp "$WORK/src/stockfish.exe" "$OUT/stockfish-chesswiz.exe"
echo "build-windows-engines: $OUT/stockfish-chesswiz.exe ($ARCH)"
fi

# Sjeng 11.2 (C). Its utils.c already has a Windows branch; gdbm is vendored.
if want sjeng; then
	SJ="$ROOT/build/sjeng-win"
	rm -rf "$SJ"
	mkdir -p "$SJ/gdbm"
	cp "$ROOT"/engines/Sjeng/*.[ch] "$SJ/"
	cp "$ROOT"/src/util/gdbm/*.[ch] "$SJ/gdbm/"
	ZCC="zig cc -target x86_64-windows-gnu -O2 -w"
	for f in "$SJ"/gdbm/*.c; do $ZCC -c "$f" -o "${f%.c}.o"; done
	zig ar rcs "$SJ/libgdbm.a" "$SJ"/gdbm/*.o
	( cd "$SJ" && $ZCC -std=gnu11 -fcommon -DSCIDB_VERSION=1 -Igdbm \
		attacks.c crazy.c epd.c learn.c partner.c seval.c ttable.c book.c \
		ecache.c eval.c moves.c search.c sjeng.c utils.c newbook.c proof.c \
		neval.c rcfile.c leval.c draw.c see.c probe.c segtb.c \
		libgdbm.a -o sjeng-chesswiz.exe )
	cp "$SJ/sjeng-chesswiz.exe" "$OUT/"
	echo "build-windows-engines: $OUT/sjeng-chesswiz.exe"
fi

# Reckless 0.9.0 (Rust). build.rs hard-codes "clang" for Fathom, so a shim
# named clang on PATH redirects it to zig; the link goes through zig c++
# (for libunwind) minus the GNU-toolchain libraries zig supplies itself.
if want reckless; then
	RK="$ROOT/build/reckless-win"
	RK_CPU="${RK_CPU:-x86-64-v3}"
	if ! command -v cargo >/dev/null || ! rustup target list --installed 2>/dev/null | grep -qx x86_64-pc-windows-gnu; then
		echo "build-windows-engines: WARNING: cargo or the x86_64-pc-windows-gnu target is missing; Reckless not built" >&2
	else
		mkdir -p "$RK/shim"
		rsync -a --delete --exclude target --exclude reckless-chesswiz --exclude reckless-scidb \
			"$ROOT/engines/reckless/" "$RK/src/"
		cat > "$RK/shim/clang" <<'EOF'
#!/bin/sh
for a in "$@"; do case "$a" in --target=*|-m64) ;; *) set -- "$@" "$a";; esac; shift; done
exec zig cc -target x86_64-windows-gnu "$@"
EOF
		cat > "$RK/shim/zigcc-link" <<'EOF'
#!/bin/sh
for a in "$@"; do
	case "$a" in
	-lgcc_eh|-lgcc_s|-lgcc|-lmsvcrt|-lmingwex|-lmingw32|-l:libpthread.a|-m64|-fno-use-linker-plugin|-Wl,-O1|-Wl,--disable-auto-image-base|-Wl,--dynamicbase|-Wl,--high-entropy-va|-Wl,--nxcompat) ;;
	*) set -- "$@" "$a";;
	esac
	shift
done
exec zig c++ -target x86_64-windows-gnu "$@"
EOF
		printf '#!/bin/sh\nexec zig ar "$@"\n' > "$RK/shim/ar"
		chmod +x "$RK"/shim/*
		( cd "$RK/src" && PATH="$RK/shim:$PATH" GIT_DIR=/nonexistent \
			CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER="$RK/shim/zigcc-link" \
			AR_x86_64_pc_windows_gnu="$RK/shim/ar" \
			RUSTFLAGS="-C target-cpu=$RK_CPU" \
			cargo build --release --quiet --target x86_64-pc-windows-gnu ) \
			> "$RK/build.log" 2>&1 || { tail -30 "$RK/build.log"; exit 1; }
		cp "$RK/src/target/x86_64-pc-windows-gnu/release/reckless.exe" "$OUT/reckless-chesswiz.exe"
		echo "build-windows-engines: $OUT/reckless-chesswiz.exe ($RK_CPU)"
	fi
fi
