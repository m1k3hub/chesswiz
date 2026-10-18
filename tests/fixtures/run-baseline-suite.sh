#!/bin/bash
# Run the full app test suite twice under Xvfb and compute flaky set
# Usage: bash tests/fixtures/run-baseline-suite.sh

set -e
SRCDIR="$(cd "$(dirname "$0")/../.." && pwd)"
OUTDIR="$SRCDIR/tests/tmp-app/menu-baseline"

run_suite() {
    local run=$1
    local homedir="$SRCDIR/tests/tmp-app/app-home-baseline-run${run}"
    local logfile="$OUTDIR/suite-run${run}.log"
    mkdir -p "$homedir"
    echo "=== Starting run $run ==="
    HOME="$homedir" xvfb-run -a -s '-screen 0 1920x1080x24' \
        "$SRCDIR/src/tkchesswiz" "$SRCDIR/tests/run_app_tests.tcl" \
        > "$logfile" 2>&1 || true
    echo "Run $run complete: $logfile"
}

# Extract pass/fail per test from a log file
extract_results() {
    local logfile=$1
    grep -E '^test_.*\.tcl:\s+Total' "$logfile" | sed 's/.*\(test_.*\.tcl\):.*Total\s*\([0-9]*\).*Passed\s*\([0-9]*\).*Failed\s*\([0-9]*\).*/\1 total=\2 passed=\3 failed=\4/'
}

run_suite 1
run_suite 2

# Compare runs to find flaky tests
echo "" > "$OUTDIR/flaky-tests.txt"
echo "# Flaky tests (different results between run 1 and run 2)" >> "$OUTDIR/flaky-tests.txt"

extract_results "$OUTDIR/suite-run1.log" | sort > "$OUTDIR/results-run1.txt"
extract_results "$OUTDIR/suite-run2.log" | sort > "$OUTDIR/results-run2.txt"

# Find differences
diff "$OUTDIR/results-run1.txt" "$OUTDIR/results-run2.txt" >> "$OUTDIR/flaky-tests.txt" 2>&1 || true

echo "Results written to $OUTDIR/"
