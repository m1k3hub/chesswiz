#!/usr/bin/env bash
# scripts/build-sysroot.sh <triple>
#
# Build the third-party C dependencies (spec D2, docs/PORT_WINDOWS_MAC_SPEC.md)
# from source with `zig cc -target <triple>` into a per-target sysroot:
#
#   build/<triple>/{include,lib,bin}   install prefix ("sysroot")
#   build/src/                         downloaded tarballs (sha256-pinned)
#   build/<triple>/build/<pkg>/        out-of-tree build dirs
#   build/<triple>/logs/               per-package configure/make logs
#   build/bin/zcc, zcxx, zar, zranlib, zrc
#                                       zig wrappers (configure chokes on
#                                       multiword "zig cc -target ...")
#
# Packages: Tcl 8.6.17, Tk 8.6.17 (win|unix|macosx configure by target),
#           zlib 1.3.1, Expat 2.6.4, tcllib json, OpenSSL and TclTLS.
#           Sources and Mozilla CA roots are checksum-verified with sha256 pinned
#           below; downloads are cached in build/src/.
#
# Validated: x86_64-windows-gnu; aarch64-macos and x86_64-macos core compilation.
# macOS installs Tcl/Tk headers only plus static zlib/Expat, not a runnable Tk.
# Stubbed (TODO): x86_64-linux-gnu
#
# With x86_64-windows-gnu the sysroot ends up with (among the rest):
#   include/tcl.h  include/tclInt.h  include/tk.h  include/zlib.h
#   include/tkInt.h include/tkPort.h include/tkWinInt.h include/tkWinPort.h
#   include/X11/Xlib.h              (Tk's Windows xlib emulation, tk/xlib/X11)
#   include/tk-private/{generic,win}/*.h
#   include/tcl-private/{generic,win,compat,libtommath}/*.h
#   lib/libz.a  lib/libtcl86s.a  lib/libtk86s.a  lib/libtclstub86.a
#   bin/        (empty; tclsh86.exe/wish86.exe stay in build/<triple>/build/*-obj/)
#
# Nothing under src/ is touched; nothing is committed.

set -euo pipefail

# --------------------------------------------------------------------------
# config

TCL_VER=8.6.17
TK_VER=8.6.17
ZLIB_VER=1.3.1
EXPAT_VER=2.6.4
TCLLIB_VER=2.0
OPENSSL_VER=3.5.9
TCLTLS_VER=1.7.22

TCL_TARBALL=tcl${TCL_VER}-src.tar.gz
TK_TARBALL=tk${TK_VER}-src.tar.gz
ZLIB_TARBALL=zlib-${ZLIB_VER}.tar.gz
EXPAT_TARBALL=expat-${EXPAT_VER}.tar.xz
TCLLIB_TARBALL=tcllib-${TCLLIB_VER}.tar.gz
OPENSSL_TARBALL=openssl-${OPENSSL_VER}.tar.gz
TCLTLS_TARBALL=tcltls-${TCLTLS_VER}.tar.gz
CACERT_FILE=cacert.pem

TCL_URL=https://prdownloads.sourceforge.net/tcl/${TCL_TARBALL}
TK_URL=https://prdownloads.sourceforge.net/tcl/${TK_TARBALL}
ZLIB_URL=https://zlib.net/fossils/${ZLIB_TARBALL}
EXPAT_URL=https://github.com/libexpat/libexpat/releases/download/R_2_6_4/${EXPAT_TARBALL}
TCLLIB_URL=https://core.tcl-lang.org/tcllib/uv/${TCLLIB_TARBALL}
OPENSSL_URL=https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VER}/${OPENSSL_TARBALL}
TCLTLS_URL=https://core.tcl-lang.org/tcltls/uv/${TCLTLS_TARBALL}
CACERT_URL=https://curl.se/ca/cacert.pem

TCL_SHA256=a3903371efcce8a405c5c245d029e9f6850258a60fa3761c4d58995610949b31
TK_SHA256=e4982df6f969c08bf9dd858a6891059b4a3f50dc6c87c10abadbbe2fc4838946
ZLIB_SHA256=9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23
EXPAT_SHA256=a695629dae047055b37d50a0ff4776d1d45d0a4c842cf4ccee158441f55ff7ee
TCLLIB_SHA256=590263de0832ac801255501d003441a85fb180b8ba96265d50c4a9f92fde2534

OPENSSL_SHA256=603f5602e2eef00d77fbd429d34dcd5822bb301757a1bc9cdb24c670f1eb859a
TCLTLS_SHA256=e84e2b7a275ec82c4aaa9d1b1f9786dbe4358c815e917539ffe7f667ff4bc3b4
CACERT_SHA256=a41b5d356aea97a529fe27e0f7316d2f9d946d75927476cf9cf1b90637d00505

# Repo root = parent of scripts/; the script may be invoked from anywhere.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ZIG_GLOBAL_CACHE_DIR="${ZIG_GLOBAL_CACHE_DIR:-$ROOT/build/zig-cache}"
SRC_DIR="$ROOT/build/src"
WRAPPER_DIR="$ROOT/build/bin"

JOBS="$(nproc 2>/dev/null || echo 4)"

usage() {
    echo "usage: $0 <triple> [--tls-only]" >&2
    echo "  e.g. $0 x86_64-windows-gnu" >&2
    echo "  macOS (headers-only Tcl/Tk): aarch64-macos, x86_64-macos"
    echo "  planned: x86_64-linux-gnu" >&2
    exit 2
}

die() { echo "build-sysroot: error: $*" >&2; exit 1; }

log() { echo "build-sysroot: $*"; }

need_tool() {
    command -v "$1" >/dev/null 2>&1 || die "required tool '$1' not found in PATH"
}

# --------------------------------------------------------------------------
# targets

TARGET="${1:-}"
[ -n "$TARGET" ] || usage
TLS_ONLY="${2:-}"
[ "$#" -le 2 ] && { [ -z "$TLS_ONLY" ] || [ "$TLS_ONLY" = --tls-only ]; } || usage

# Tcl/Tk configure flavor + zig flags per target.
FLAVOR=""
ZIG_TARGET="$TARGET"
EXTRA_CFLAGS=""
EXTRA_LDFLAGS=""

case "$TARGET" in
    x86_64-windows-gnu|aarch64-windows-gnu|i686-windows-gnu)
        FLAVOR=win
        need_tool llvm-rc         # resource script compiler for tclsh/wish .rc files
        # The win/ configure is a 2008-era autoconf script that predates
        # ac_cv_func_*/ac_cv_type_* checks; cross detection comes only from
        # --host/--build, and those triples feed ${host}-windres lookups that
        # don't exist here (we substitute via RC=zrc), so they are harmless.
        HOST_TRIPLE="$TARGET"
        ;;
    x86_64-linux-gnu|x86_64-linux-gnu.*|aarch64-linux-gnu|aarch64-linux-gnu.*)
        die "target '$TARGET' is planned (spec D2) but not implemented yet in this script; only *-windows-gnu is wired up"
        ;;
    aarch64-macos-none|x86_64-macos-none|aarch64-macos|x86_64-macos)
        FLAVOR=macosx
        HOST_TRIPLE="${TARGET%%-*}-apple-darwin"
        ;;
    *)
        die "unknown target '$TARGET'"
        ;;
esac

PREFIX="$ROOT/build/$TARGET"
BUILD_ROOT="$PREFIX/build"
LOG_DIR="$PREFIX/logs"

# --------------------------------------------------------------------------
# zig wrappers (multiword CC breaks several configure scripts)

install_wrappers() {
    mkdir -p "$WRAPPER_DIR"
    cat > "$WRAPPER_DIR/zcc" <<EOF
#!/bin/sh
# zig cc wrapper for $TARGET (generated by scripts/build-sysroot.sh)
exec zig cc -target $ZIG_TARGET $EXTRA_CFLAGS "\$@"
EOF
    cat > "$WRAPPER_DIR/zcxx" <<EOF
#!/bin/sh
# zig c++ wrapper for $TARGET (generated by scripts/build-sysroot.sh)
exec zig c++ -target $ZIG_TARGET $EXTRA_CFLAGS "\$@"
EOF
    cat > "$WRAPPER_DIR/zar" <<'EOF'
#!/bin/sh
# zig ar wrapper (generated by scripts/build-sysroot.sh)
exec zig ar "$@"
EOF
    cat > "$WRAPPER_DIR/zranlib" <<'EOF'
#!/bin/sh
# zig ranlib wrapper (generated by scripts/build-sysroot.sh)
exec zig ranlib "$@"
EOF
    cat > "$WRAPPER_DIR/zrc" <<'EOF'
#!/bin/sh
# `zig rc` (resinator) needs MSVC-style /flags, but the Tcl/Tk win makefiles
# emit GNU windres flags (-o out, --define X, --include dir, input.rc last).
# Translate between the two.  Generated by scripts/build-sysroot.sh.
out="" defs="" incs="" input=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o)        out="$2";   shift 2 ;;
        --define)  defs="$defs /d$2"; shift 2 ;;
        --include) incs="$incs /i$2"; shift 2 ;;
        *)         input="$1"; shift ;;
    esac
done
[ -n "$input" ] || { echo "zrc: no input file" >&2; exit 1; }
[ -n "$out" ]   || { echo "zrc: no output file" >&2; exit 1; }
# shellcheck disable=SC2086
exec zig rc $defs $incs -- "$input" "$out"
EOF
    chmod +x "$WRAPPER_DIR"/zcc "$WRAPPER_DIR"/zcxx "$WRAPPER_DIR"/zar \
             "$WRAPPER_DIR"/zranlib "$WRAPPER_DIR"/zrc
    log "tool wrappers: $WRAPPER_DIR/{zcc,zcxx,zar,zranlib,zrc} (-target $ZIG_TARGET)"
    PATH="$WRAPPER_DIR:$PATH"
}

# --------------------------------------------------------------------------
# download + verify

fetch() {
    # fetch <tarball> <url> <sha256>
    local tb="$1" url="$2" sha="$3"
    local dest="$SRC_DIR/$tb"
    if [ -f "$dest" ] && echo "$sha  $dest" | sha256sum -c - >/dev/null 2>&1; then
        log "cached: $tb (sha256 ok)"
        return 0
    fi
    log "downloading: $url"
    curl -fL --retry 3 --connect-timeout 30 -o "$dest.tmp" "$url"
    mv "$dest.tmp" "$dest"
    echo "$sha  $dest" | sha256sum -c - >/dev/null \
        || die "sha256 mismatch for $tb (expected $sha)"
}

fetch_all() {
    [ "$FLAVOR" != win ] || need_tool curl
    need_tool sha256sum
    need_tool curl
    need_tool tar
    fetch "$TCL_TARBALL"  "$TCL_URL"  "$TCL_SHA256"
    fetch "$TK_TARBALL"   "$TK_URL"   "$TK_SHA256"
    fetch "$ZLIB_TARBALL" "$ZLIB_URL" "$ZLIB_SHA256"
    fetch "$EXPAT_TARBALL" "$EXPAT_URL" "$EXPAT_SHA256"
    fetch "$TCLLIB_TARBALL" "$TCLLIB_URL" "$TCLLIB_SHA256"
}

# --------------------------------------------------------------------------
# unpack (fresh copy per package per target)

unpacked() {
    # unpacked <tarball> <builddir> -> echoes the top-level source dir
    local tb="$1" dest="$2"
    rm -rf "$dest"
    mkdir -p "$dest"
    tar -xf "$SRC_DIR/$tb" -C "$dest"
    find "$dest" -mindepth 1 -maxdepth 1 -type d | head -1
}

# --------------------------------------------------------------------------
# package builders

build_zlib() {
    if [ -f "$PREFIX/include/zlib.h" ] && [ -f "$PREFIX/lib/libz.a" ]; then log "zlib already installed; skipping"; return; fi
    local srcdir objdir
    srcdir="$(unpacked "$ZLIB_TARBALL" "$BUILD_ROOT/zlib")"
    log "zlib $ZLIB_VER -> $PREFIX (static, in-source build)"
    (
        cd "$srcdir"
        CC=zcc AR=zar RANLIB=zranlib \
            ./configure --prefix="$PREFIX" --static \
            > "$LOG_DIR/zlib-configure.log" 2>&1
        make -j"$JOBS" > "$LOG_DIR/zlib-make.log" 2>&1
        make install   > "$LOG_DIR/zlib-install.log" 2>&1
    )
    [ -f "$PREFIX/include/zlib.h" ] || die "zlib: include/zlib.h missing after install"
    [ -f "$PREFIX/lib/libz.a" ]     || die "zlib: lib/libz.a missing after install"
    log "zlib $ZLIB_VER installed (include/zlib.h, lib/libz.a)"
}

build_tcl() {
    if [ -f "$PREFIX/include/tclInt.h" ] && [ -f "$PREFIX/lib/libtcl86.a" ] && [ -f "$PREFIX/lib/tcl8.6/init.tcl" ]; then log "Tcl already installed; skipping"; return; fi
    local srcdir objdir
    srcdir="$(unpacked "$TCL_TARBALL" "$BUILD_ROOT/tcl")"
    objdir="$BUILD_ROOT/tcl-obj"
    rm -rf "$objdir"; mkdir -p "$objdir"
    log "Tcl $TCL_VER ($FLAVOR configure) -> $PREFIX"
    (
        cd "$objdir"
        # Cross-compile overrides: configure can't run test programs for a
        # different OS, and its EXEEXT/winsock checks rely on running them.
        # Static build: zig links PE executables against .dll only via import
        # libs; shipping the libtcl86.a static archive is simpler and matches
        # the "no prebuilt system libraries" spirit of D2.
        CC=zcc AS=zcc AR=zar RANLIB=zranlib RC=zrc \
        ac_cv_exeext=.exe ac_cv_func_connect=no \
        "$srcdir/$FLAVOR/configure" \
            --prefix="$PREFIX" \
            --build=x86_64-pc-linux-gnu \
            --host="$HOST_TRIPLE" \
            --enable-threads \
            --disable-shared \
            > "$LOG_DIR/tcl-configure.log" 2>&1
        make -j"$JOBS" binaries > "$LOG_DIR/tcl-make.log" 2>&1
        make install-binaries > "$LOG_DIR/tcl-install-binaries.log" 2>&1
        # install-libraries has prerequisites `install-tzdata install-msgs`
        # (which run the cross-compiled tclsh .exe, impossible on this Linux
        # host) BEFORE its recipe body, so `make install-libraries` always
        # dies before copying the public headers.  Copy them directly (this is
        # exactly the install-libraries recipe) and the script library, then
        # install-private-headers for the internal headers Tk/private code uses.
        cp -f "$srcdir/generic/tcl.h" "$srcdir/generic/tclDecls.h" \
              "$srcdir/generic/tclOO.h" "$srcdir/generic/tclOODecls.h" \
              "$srcdir/generic/tclPlatDecls.h" \
              "$srcdir/generic/tclTomMath.h" "$srcdir/generic/tclTomMathDecls.h" \
              "$PREFIX/include/"
        # Tcl script library (needed at runtime by anything embedding Tcl). The
        # Makefile installs it at lib/tcl$(VERSION) where VERSION=8.6 (not the
        # full patch level), i.e. lib/tcl8.6.
        local tclver="${TCL_VER%.*}"   # 8.6
        rm -rf "$PREFIX/lib/tcl$tclver"
        mkdir -p "$PREFIX/lib/tcl$tclver"
        cp -R "$srcdir/library/"*.tcl "$srcdir/library/tclIndex" "$PREFIX/lib/tcl$tclver/" 2>/dev/null || true
        for d in http1.0 opt0.4 encoding msgs tzdata; do mkdir -p "$PREFIX/lib/tcl$tclver/$d"; cp -R "$srcdir/library/$d/"* "$PREFIX/lib/tcl$tclver/$d/" 2>/dev/null || true; done
        # Tcl Modules (msgcat, http, tcltest, platform): the install-libraries
        # recipe copies them to lib/tcl8/<ver>/<name>-<version>.tm. Take the
        # copy lines from the Makefile, so the versions always match.
        sed -n 's|.*\$(COPY) \$(ROOT_DIR)/\(library/[^ ]*\) "\$(MODULE_INSTALL_DIR)/\([^"]*\)";.*|\1 \2|p' \
            "$srcdir/win/Makefile.in" | while read -r src dst; do
            mkdir -p "$(dirname "$PREFIX/lib/tcl8/$dst")"
            cp -f "$srcdir/$src" "$PREFIX/lib/tcl8/$dst"
        done
        [ -n "$(ls "$PREFIX"/lib/tcl8/8.5/msgcat-*.tm 2>/dev/null)" ] || die "Tcl: msgcat module missing after install"
        # install-private-headers installs tclInt.h/... to include/tcl-private
        # (plain copy, no tclsh execution, so it succeeds).
        make install-private-headers > "$LOG_DIR/tcl-install-private.log" 2>&1 || true
    )
    [ -f "$PREFIX/include/tcl.h" ] || die "Tcl: include/tcl.h missing after install"
    # Tcl's install-private-headers flattens generic+win private headers into
    # <prefix>/include/tcl-private; our C++ includes Tcl private headers as
    # plain "tclInt.h", so flatten them into the include root as well.
    if [ -d "$PREFIX/include/tcl-private" ]; then
        cp -f "$PREFIX/include/tcl-private/"*.h "$PREFIX/include/" 2>/dev/null || true
    fi
    [ -f "$PREFIX/include/tclInt.h" ] || die "Tcl: include/tclInt.h missing after install"
    log "Tcl $TCL_VER installed (include/tcl.h, include/tclInt.h, lib/libtcl86*)"
}

build_tk() {
    if [ -f "$PREFIX/include/tkWinInt.h" ] && [ -f "$PREFIX/lib/libtk86.a" ] && [ -f "$PREFIX/lib/tk8.6/tk.tcl" ]; then log "Tk already installed; skipping"; return; fi
    local srcdir objdir
    srcdir="$(unpacked "$TK_TARBALL" "$BUILD_ROOT/tk")"
    objdir="$BUILD_ROOT/tk-obj"
    rm -rf "$objdir"; mkdir -p "$objdir"
    log "Tk $TK_VER ($FLAVOR configure) -> $PREFIX"
    (
        cd "$objdir"
        CC=zcc AS=zcc AR=zar RANLIB=zranlib RC=zrc \
        ac_cv_exeext=.exe ac_cv_func_connect=no \
        "$srcdir/$FLAVOR/configure" \
            --prefix="$PREFIX" \
            --with-tcl="$PREFIX/lib" \
            --build=x86_64-pc-linux-gnu \
            --host="$HOST_TRIPLE" \
            --enable-threads \
            --disable-shared \
            > "$LOG_DIR/tk-configure.log" 2>&1
        make -j"$JOBS" binaries > "$LOG_DIR/tk-make.log" 2>&1
        make install-binaries > "$LOG_DIR/tk-install.log" 2>&1
        # The Tk win Makefile has no install-headers; tk.h/tkDecls.h/... and
        # the xlib emulation headers (xlib/X11/*.h) are copied by
        # install-libraries (a plain copy; no wish execution), and the Tk
        # internals (tkInt.h, tkWinInt.h, tkPort.h, tkWinPort.h, ...) by
        # install-private-headers.  install-libraries also installs the Tk
        # script library (lib/tk8.6).  install-demos/install-doc are skipped.
        make install-libraries >> "$LOG_DIR/tk-install.log" 2>&1 || true
        make install-private-headers >> "$LOG_DIR/tk-install.log" 2>&1 || true
    )
    [ -f "$PREFIX/include/tk.h" ] || die "Tk: include/tk.h missing after install"
    # install-private-headers puts tkInt.h/tkWinInt.h/... at the include ROOT
    # (PRIVATE_INCLUDE_INSTALL_DIR = includedir), exactly where our C++ wants
    # them; install-libraries puts xlib/X11/*.h at include/X11/.  Keep
    # namespaced copies under include/tk-private/ for clarity and mirror the
    # Tcl private layout.
    mkdir -p "$PREFIX/include/tk-private"
    cp -f "$srcdir/generic/"*.h "$PREFIX/include/tk-private/" 2>/dev/null || true
    cp -f "$srcdir/$FLAVOR/"*.h "$PREFIX/include/tk-private/" 2>/dev/null || true

    local want_hdrs="tkInt.h tkPort.h"
    [ "$FLAVOR" = win ] && want_hdrs="tkInt.h tkPort.h tkWinInt.h tkWinPort.h X11/Xlib.h"
    for h in $want_hdrs; do
        [ -f "$PREFIX/include/$h" ] || die "Tk: include/$h missing after install"
    done
    # A static Tk needs its resources (buttons bitmap, cursors, dialogs)
    # linked into the executable; FindResourceW() fails at startup otherwise.
    # The application's own .rc includes tk_base.rc from lib/tk-rc (so it can
    # replace Tk's icon); check here that it compiles.
    if [ "$FLAVOR" = win ]; then
        rm -rf "$PREFIX/lib/tk-rc"
        cp -R "$srcdir/win/rc" "$PREFIX/lib/tk-rc"
        zig rc /:auto-includes gnu /i "$PREFIX/lib/tk-rc" \
            -- "$PREFIX/lib/tk-rc/tk_base.rc" "$LOG_DIR/tk_base.res" \
            > "$LOG_DIR/tk-rc.log" 2>&1 || die "Tk: zig rc tk_base.rc failed"
    fi
    log "Tk $TK_VER installed (include/tk.h, tk private headers, X11 emulation headers)"
}

build_expat() {
    if [ -f "$PREFIX/include/expat.h" ] && [ -f "$PREFIX/lib/libexpat.a" ]; then
        log "Expat already installed; skipping"
        return
    fi
    local srcdir objdir
    srcdir="$(unpacked "$EXPAT_TARBALL" "$BUILD_ROOT/expat")"
    objdir="$BUILD_ROOT/expat-obj"
    mkdir -p "$objdir"
    log "Expat $EXPAT_VER -> $PREFIX (static)"
    (
        cd "$objdir"
        CC=zcc CXX=zcxx AR=zar RANLIB=zranlib "$srcdir/configure" \
            --prefix="$PREFIX" --build=x86_64-pc-linux-gnu \
            --host="$HOST_TRIPLE" --disable-shared --enable-static \
            --without-xmlwf --without-examples --without-tests --without-docbook \
            > "$LOG_DIR/expat-configure.log" 2>&1
        make -j"$JOBS" > "$LOG_DIR/expat-make.log" 2>&1
        make install > "$LOG_DIR/expat-install.log" 2>&1
    )
    [ -f "$PREFIX/lib/libexpat.a" ] || die "Expat: library missing after install"
}

build_openssl() {
    if [ -f "$PREFIX/include/openssl/ssl.h" ] && [ -f "$PREFIX/lib/libssl.a" ] && [ -f "$PREFIX/lib/libcrypto.a" ] && [ "$(cat "$PREFIX/lib/openssl-build-version" 2>/dev/null)" = "$OPENSSL_VER" ]; then log "OpenSSL already installed; skipping"; return; fi
    [ "$TARGET" = x86_64-windows-gnu ] || die "OpenSSL: only mingw64 (x86_64-windows-gnu) is implemented"
    need_tool perl
    local srcdir
    srcdir="$(unpacked "$OPENSSL_TARBALL" "$BUILD_ROOT/openssl")"
    log "OpenSSL $OPENSSL_VER -> $PREFIX (static, mingw64)"
    (
        cd "$srcdir"
        CC=zcc AR=zar RANLIB=zranlib RC=zrc \
            perl ./Configure mingw64 no-shared no-tests no-docs \
                --prefix="$PREFIX" --libdir=lib \
                > "$LOG_DIR/openssl-configure.log" 2>&1 || exit 1
        make -j"$JOBS" > "$LOG_DIR/openssl-make.log" 2>&1 || exit 1
        make install_dev > "$LOG_DIR/openssl-install.log" 2>&1 || exit 1
    ) || die "OpenSSL: build failed; see $LOG_DIR/openssl-*.log"
    [ -f "$PREFIX/lib/libssl.a" ] && [ -f "$PREFIX/lib/libcrypto.a" ] || die "OpenSSL: static libraries missing after install"
    echo "$OPENSSL_VER" > "$PREFIX/lib/openssl-build-version"
}

build_tcltls() {
    local pkgdir="$PREFIX/lib/tls$TCLTLS_VER" dll="tls${TCLTLS_VER//./}.dll"
    if [ -f "$pkgdir/$dll" ] && [ -f "$pkgdir/tls.tcl" ] && [ -f "$pkgdir/pkgIndex.tcl" ] && [ "$(cat "$pkgdir/openssl-build-version" 2>/dev/null)" = "$OPENSSL_VER" ]; then log "TclTLS already installed; skipping"; return; fi
    [ -f "$PREFIX/lib/libtclstub86.a" ] || die "TclTLS: Tcl stub library missing; build the full sysroot first"
    local srcdir objdir
    srcdir="$(unpacked "$TCLTLS_TARBALL" "$BUILD_ROOT/tcltls")"
    patch -d "$srcdir" -p1 < "$ROOT/scripts/patches/tcltls-1.7.22-hostname.patch" \
        > "$LOG_DIR/tcltls-patch.log" 2>&1 || die "TclTLS: hostname patch failed"
    objdir="$BUILD_ROOT/tcltls-obj"
    rm -rf "$objdir"; mkdir -p "$objdir"
    log "TclTLS $TCLTLS_VER -> $pkgdir (loadable DLL, Tcl stubs, static OpenSSL)"
    (
        cd "$objdir"
        # Absolute OpenSSL archives force static linking without the old
        # configure script's -Bdynamic flags (which break Zig Tcl stub lookup).
        CC=zcc AR=zar RANLIB=zranlib \
        CPPFLAGS="-I$PREFIX/include" \
        TCLTLS_SSL_LIBS="$PREFIX/lib/libssl.a $PREFIX/lib/libcrypto.a -lws2_32 -lcrypt32 -ladvapi32 -lbcrypt" \
        TCLTLS_SSL_CFLAGS="-I$PREFIX/include" TCLTLS_SSL_CPPFLAGS="-I$PREFIX/include" \
            "$srcdir/configure" --prefix="$PREFIX" --with-tcl="$PREFIX/lib" \
                --build=x86_64-pc-linux-gnu --host=x86_64-w64-mingw32 \
                --enable-shared --enable-stubs --enable-deterministic \
                > "$LOG_DIR/tcltls-configure.log" 2>&1 || exit 1
        # The extension configure keeps Tcl flags (including thread support),
        # filters out STATIC_BUILD, and enables USE_TCL_STUBS.
        # Zig's PE linker accepts -shared, but not GNU ld's --dll or
        # ELF version scripts. Keep the initialization exports intact.
        printf 'EXPORTS\nTls_Init\nTls_SafeInit\n' > tls.def
        make -j"$JOBS" LDFLAGS="-shared $objdir/tls.def" \
            > "$LOG_DIR/tcltls-make.log" 2>&1 || exit 1
        mkdir -p "$pkgdir"
        cp tcltls.dll "$pkgdir/$dll" || exit 1
        sed "s/tcltls.dll/$dll/g" pkgIndex.tcl > "$pkgdir/pkgIndex.tcl" || exit 1
        cp "$srcdir/tls.tcl" "$pkgdir/" || exit 1
        echo "$OPENSSL_VER" > "$pkgdir/openssl-build-version"
    ) || die "TclTLS: build failed; see $LOG_DIR/tcltls-*.log"
    [ -f "$pkgdir/$dll" ] && [ -f "$pkgdir/pkgIndex.tcl" ] || die "TclTLS: package missing after install"
}

install_cacert() {
    if [ -f "$PREFIX/$CACERT_FILE" ] && echo "$CACERT_SHA256  $PREFIX/$CACERT_FILE" | sha256sum -c - >/dev/null 2>&1; then log "CA bundle already installed; skipping"; return; fi
    cp "$SRC_DIR/$CACERT_FILE" "$PREFIX/$CACERT_FILE" \
        > "$LOG_DIR/cacert-install.log" 2>&1 || die "CA bundle: install failed"
    log "Mozilla CA bundle installed (sha256:$CACERT_SHA256)"
}

# --------------------------------------------------------------------------
# manifest

write_manifest() {
    local mf="$PREFIX/SYSROOT_MANIFEST.txt"
    {
        echo "Chesswiz sysroot for $TARGET"
        echo "built:  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
        echo "host:   $(uname -srm)"
        echo "zig:    $(zig version 2>/dev/null || echo unknown)"
        echo
        echo "toolchain wrappers: build/bin/{zcc,zcxx,zar,zranlib,zrc} (-target $ZIG_TARGET)"
        echo
        echo "packages:"
        echo "  tcl   $TCL_VER  sha256:$TCL_SHA256  ($TCL_URL)"
        echo "  tk    $TK_VER  sha256:$TK_SHA256  ($TK_URL)"
        echo "  zlib  $ZLIB_VER   sha256:$ZLIB_SHA256  ($ZLIB_URL)"
        echo "  expat $EXPAT_VER sha256:$EXPAT_SHA256 ($EXPAT_URL)"
        echo
        echo "  tcllib $TCLLIB_VER sha256:$TCLLIB_SHA256 ($TCLLIB_URL)"
        echo "  openssl $OPENSSL_VER sha256:$OPENSSL_SHA256 ($OPENSSL_URL)"
        echo "  tcltls $TCLTLS_VER sha256:$TCLTLS_SHA256 ($TCLTLS_URL)"
        echo "  cacert 2026-09-25 sha256:$CACERT_SHA256 ($CACERT_URL)"
        echo
        echo "layout:"
        echo "  include/        public headers (tcl.h, tk.h, zlib.h, X11/*) + flattened private headers"
        echo "  include/tcl-private/  Tcl private headers (generic, $FLAVOR, compat, libtommath)"
        echo "  include/tk-private/   Tk private headers (generic, $FLAVOR)"
        echo "  lib/            static libraries (libtcl86.a, libtk86.a, libz.a) + tclConfig.sh/tkConfig.sh"
        echo "  bin/            (nothing installed; tclsh/wish live in build/<triple>/build/*-obj/)"
        echo "  logs/           per-package configure/make logs"
    } > "$mf"
    log "manifest: $mf"
}

# Pure-Tcl tcllib modules the program uses (Linux gets them from the system
# tcllib). Installed as lib/<module>: Tcl searches the subdirectories of the
# directory above its library.
TCLLIB_MODULES="json"

install_tcllib() {
    local srcdir m
    srcdir="$(unpacked "$TCLLIB_TARBALL" "$BUILD_ROOT/tcllib")"
    for m in $TCLLIB_MODULES; do
        rm -rf "$PREFIX/lib/$m"
        mkdir -p "$PREFIX/lib/$m"
        cp "$srcdir/modules/$m/"*.tcl "$PREFIX/lib/$m/"
        [ -f "$PREFIX/lib/$m/pkgIndex.tcl" ] || die "tcllib: no pkgIndex.tcl for $m"
    done
    log "tcllib $TCLLIB_VER modules installed: $TCLLIB_MODULES"
}

# --------------------------------------------------------------------------

install_macos_headers() {
    local tclsrc tksrc
    tclsrc="$(unpacked "$TCL_TARBALL" "$BUILD_ROOT/tcl")"
    tksrc="$(unpacked "$TK_TARBALL" "$BUILD_ROOT/tk")"
    mkdir -p "$PREFIX/include/tcl-private" "$PREFIX/include/tk-private"
    cp "$tclsrc/generic/"*.h "$PREFIX/include/"
    cp "$tclsrc/unix/"*.h "$PREFIX/include/"
    cp "$tksrc/generic/"*.h "$PREFIX/include/"
    cp "$tksrc/macosx/"*.h "$PREFIX/include/"
    local dir
    for dir in generic unix compat libtommath; do
        mkdir -p "$PREFIX/include/tcl-private/$dir"
        cp "$tclsrc/$dir/"*.h "$PREFIX/include/tcl-private/$dir/"
    done
    for dir in generic macosx; do
        mkdir -p "$PREFIX/include/tk-private/$dir"
        cp "$tksrc/$dir/"*.h "$PREFIX/include/tk-private/$dir/"
    done
    mkdir -p "$PREFIX/include/X11"
    cp "$tksrc/xlib/X11/"*.h "$PREFIX/include/X11/"
}

main() {
    need_tool zig
    log "root:   $ROOT"
    log "target: $TARGET (flavor: $FLAVOR)"
    log "prefix: $PREFIX"
    mkdir -p "$SRC_DIR" "$BUILD_ROOT" "$LOG_DIR"
    install_wrappers
    need_tool curl
    need_tool sha256sum
    need_tool tar
    need_tool make
    need_tool patch
    if [ "$FLAVOR" = macosx ]; then
        [ -z "$TLS_ONLY" ] || die "macOS headers-only sysroot does not support --tls-only"
        fetch "$TCL_TARBALL" "$TCL_URL" "$TCL_SHA256"
        fetch "$TK_TARBALL" "$TK_URL" "$TK_SHA256"
        fetch "$ZLIB_TARBALL" "$ZLIB_URL" "$ZLIB_SHA256"
        fetch "$EXPAT_TARBALL" "$EXPAT_URL" "$EXPAT_SHA256"
        install_macos_headers
        build_zlib
        build_expat
        {
            echo "Chesswiz compile sysroot for $TARGET"
            echo "zig: $(zig version)"
            echo "Tcl $TCL_VER headers only; sha256:$TCL_SHA256"
            echo "Tk $TK_VER headers only; sha256:$TK_SHA256"
            echo "zlib $ZLIB_VER static; sha256:$ZLIB_SHA256"
            echo "Expat $EXPAT_VER static; sha256:$EXPAT_SHA256"
            echo "No Tcl/Tk libraries or Apple frameworks. Link on a Mac with an SDK."
        } > "$PREFIX/SYSROOT_MANIFEST.txt"
        log "macOS compile sysroot ready (Tcl/Tk headers only; linking requires a Mac SDK)"
        return
    fi
    if [ -z "$TLS_ONLY" ]; then
        fetch_all
        build_zlib
        build_tcl
        build_tk
        build_expat
        install_tcllib
    fi
    fetch "$OPENSSL_TARBALL" "$OPENSSL_URL" "$OPENSSL_SHA256"
    fetch "$TCLTLS_TARBALL" "$TCLTLS_URL" "$TCLTLS_SHA256"
    fetch "$CACERT_FILE" "$CACERT_URL" "$CACERT_SHA256"
    build_openssl
    build_tcltls
    install_cacert
    # Tk extensions need platform widget defaults, not installed by Tk's
    # install-private-headers target.
    if [ "$FLAVOR" = win ]; then
        local tk_source
        tk_source="$(find "$BUILD_ROOT/tk" -name tkWinDefault.h -print -quit)"
        [ -z "$tk_source" ] || cp -f "$tk_source" "$PREFIX/include/"
    fi
    write_manifest
    log "done: $PREFIX"
}

main
