#!/bin/bash
# scidb: Task 3 §B ASan/UBSan suite (leak detection on), one log per test.
cd "$(dirname "$0")/.." || exit 9
export ASAN_OPTIONS=halt_on_error=1:abort_on_error=0:detect_leaks=1
export UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1
: > /tmp/asan_suite.status
run() {
  local tag=$1; shift
  "$@" > /tmp/asan_${tag}.log 2>&1
  local rc=$?
  echo "$tag EXIT=$rc" >> /tmp/asan_suite.status
}
rm -rf /tmp/cql_asan_scratch_final
run robustness ./build/asan/robustness 4
run filelock   ./build/asan/filelock normal /tmp/cql_test/mega_3000.pgn /tmp/cql_asan_scratch_final
run stdout_race ./build/asan/stdout_race /tmp/cql_test/mega_3000.pgn
run stress     ./build/asan/stress /tmp/cql_test/mega_3000.pgn 1 16 20000
run pgn_driver ./build/asan/pgn_driver
echo ASAN_DONE >> /tmp/asan_suite.status
