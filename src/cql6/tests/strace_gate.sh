#!/bin/sh
# scidb: Task 3 §A strace gate — prove that NO file is opened/created/renamed/
# deleted while embedded searches run.
# usage: strace_gate.sh <filelock-bin> <pgn> <workdir>
set -e
BIN=$1; PGN=$2; WORK=$3
rm -rf "$WORK"; mkdir -p "$WORK/scratch"
strace -f -tt -e trace=openat,open,creat,unlink,unlinkat,rename,renameat,renameat2,mkdir,mkdirat \
    -o "$WORK/strace.log" "$BIN" strace "$PGN" "$WORK/scratch" > "$WORK/run.log" 2>&1 || { cat "$WORK/run.log"; exit 1; }
cat "$WORK/run.log"
awk '
 /marker_start/ {inwin=1; next}
 /marker_end/   {inwin=0; next}
 inwin && $0 !~ /\+\+\+/ && $0 !~ /\/proc\/sys\/vm\/overcommit_memory/ {print}
' "$WORK/strace.log" > "$WORK/window.log"
if [ -s "$WORK/window.log" ]; then
  echo "[FAIL] A-strace: filesystem syscalls during the search phase:"
  cat "$WORK/window.log"
  exit 1
fi
echo "[PASS] A-strace: no openat/open/creat/unlink/rename/mkdir during searches"
