#!/bin/sh
# Run after building src/ (make); the test uses the actual shipped startup files.
set -eu
cd "$(dirname "$0")/.."
cache_test_binary=$(mktemp /tmp/chesswiz-player-cache-io-test.XXXXXX)
trap 'rm -f "$cache_test_binary"' EXIT HUP INT TERM
${CXX:-c++} -std=c++17 ${OPTIMIZE--O2} -DBROKEN_LINKER_HACK=1 \
    -Isrc -Isrc/db -Isrc/mstl -Isrc/util -Isrc/sys -I/usr/include/tcl8.6 \
    tests/test_player_cache_io.cpp -o "$cache_test_binary" \
    -Wl,--start-group src/db/libdb.a src/mstl/libmstl.a src/util/libutil.a \
    src/sys/libsys.a src/util/libTeXt/libTeXt.a src/util/libharu/libharu.a \
    src/util/libhyphenate/libhyphenate.a src/util/universalchardet/libchardet.a \
    -Wl,--end-group -Lsrc/util/minizip -lminizip -ltcl8.6 -lzzip -lz \
    -lexpat -lpthread -lfontconfig -lpng -lm
"$cache_test_binary" src/data "$@"
