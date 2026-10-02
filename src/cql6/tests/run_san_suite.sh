#!/bin/bash
# scidb: run the Task 3 sanitizer suites sequentially, one log per step.
cd "$(dirname "$0")/.." || exit 9
export ASAN_OPTIONS=halt_on_error=1:abort_on_error=0:detect_leaks=1
export UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1
export TSAN_OPTIONS=halt_on_error=1:second_deadlock_stack=1

run() {
  local tag=$1; shift
  echo "### $tag : $*" >> /tmp/san_suite.status
  "$@" > /tmp/san_${tag}.log 2>&1
  echo "### $tag EXIT=$?" >> /tmp/san_suite.status
}

: > /tmp/san_suite.status
echo "=== ASAN core ===" >> /tmp/san_suite.status
run asan_pgn_driver        ./build/asan/pgn_driver
run asan_robustness        ./build/asan/robustness 4
run asan_filelock          ./build/asan/filelock normal /tmp/cql_test/mega_3000.pgn /tmp/cql_asan_scratch
run asan_stdout_race       ./build/asan/stdout_race /tmp/cql_test/mega_3000.pgn
run asan_stress            ./build/asan/stress /tmp/cql_test/mega_3000.pgn 1 16 20000

echo "=== TSAN core ===" >> /tmp/san_suite.status
run tsan_pgn_driver        ./build/tsan/pgn_driver
run tsan_robustness        ./build/tsan/robustness 4
run tsan_filelock          ./build/tsan/filelock normal /tmp/cql_test/mega_3000.pgn /tmp/cql_tsan_scratch
run tsan_stdout_race       ./build/tsan/stdout_race /tmp/cql_test/mega_3000.pgn
run tsan_stress            ./build/tsan/stress /tmp/cql_test/mega_3000.pgn 1 16 20000

echo "=== ASAN oracle rates (extra coverage) ===" >> /tmp/san_suite.status
run asan_oracle_rates      ./build/asan/oracle20k rates /tmp/cql_test/mega_20000.pgn
echo "ALL_DONE" >> /tmp/san_suite.status
