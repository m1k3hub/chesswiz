#!/usr/bin/env bash
# Run all loopback suites serially, then scan raw artifacts for one synthetic
# credential. Never reads the developer's HOME/token or enables the live test.
set -euo pipefail
shopt -s nullglob
cd "$(dirname "$0")/.."

scan() {
    local allowed=$1 root matches path rc leaked=0
    shift
    for root in "$@"; do
        if [[ ! -e $root ]]; then
            printf 'Missing scan root: %s\n' "$root" >&2
            return 2
        fi
        rc=0
        matches=$(grep -ralF -f <(printf '%s\n' "$CHESSWIZ_LICHESS_TEST_TOKEN") -- "$root") || rc=$?
        if (( rc > 1 )); then return "$rc"; fi
        while IFS= read -r path; do
            [[ -z $path || $path == "$allowed" ]] && continue
            printf 'LEAK: %s\n' "$path"
            leaked=1
        done <<< "$matches"
        printf 'grep -ralF [synthetic credential] %s: %s\n' "$root" "$([[ $leaked == 0 ]] && echo clean || echo LEAK)"
    done
    return "$leaked"
}

# Scanner can be exercised independently, including intentional leak canaries.
if [[ ${1:-} == --scan-only ]]; then
    shift
    : "${CHESSWIZ_LICHESS_TEST_TOKEN:?synthetic credential required}"
    [[ $CHESSWIZ_LICHESS_TEST_TOKEN =~ ^lip_[[:alnum:]]{20}$ ]] || exit 2
    scan "$@"
    exit
fi

out=${1:-tests/tmp-app/lichess-hardening/F-reg-sec}
if (( $# )); then shift; fi
mkdir -p "$out"
out=$(realpath "$out")
export CHESSWIZ_LICHESS_TEST_TOKEN="lip_$(od -An -N10 -tx1 /dev/urandom | tr -d ' \n')"
export CHESSWIZ_LICHESS_LIVE=0 PULSE_SINK=cwtests CW_TOKEN_EVIDENCE="$out"
# This directory is outside evidence: only config/lichess-token may contain the
# token. The raw HOME trees are checked before removal, never copied to evidence.
homes=$(mktemp -d /tmp/chesswiz-token-homes.XXXXXX)
trap 'rm -rf -- "$homes"' EXIT
status=0
: > "$out/summary.log"
: > "$out/grep.log"
run_suite() {
    local suite=$1 phase=${2:-} log name test_home code=0
    name=${suite%.tcl}${phase:+-$phase}
    test_home="$homes/${suite%.tcl}"
    mkdir -p "$test_home"
    log="$out/$name.log"
    HOME="$test_home" CW_PERSIST_PHASE="${phase:-seed}" timeout 240s \
        xvfb-run -a -s '-screen 0 1920x1080x24' \
        ./src/tkchesswiz tests/run_app_tests.tcl -file "$suite" -verbose > "$log" 2>&1 || code=$?
    printf '%s exit=%s\n' "$name" "$code" | tee -a "$out/summary.log"
    grep -E 'Total (Passed|Failed|Skipped):|STATUS:' "$log" | tee -a "$out/summary.log" || true
    if (( code != 0 )); then status=1; fi
    if [[ $suite == test_app_lichess_live.tcl ]]; then
        # Its only permitted execution here is the explicit disabled-live skip.
        grep -q '^Total Skipped: 1$' "$log" || status=1
        grep -q '^Total Failed: 0$' "$log" || status=1
    else
        grep -q '^STATUS: PASSED$' "$log" || status=1
        grep -q '^Total Skipped: 0$' "$log" || status=1
    fi
    # The app harness sets SCIDB_ERROR_LOG inside tests/tmp-app; the scan below
    # covers it as well as suites which choose their own error-log destination.
    scan "$test_home/.chesswiz/config/lichess-token" "$test_home" >> "$out/grep.log" || status=1
}
for file in tests/test_app_lichess*.tcl tests/test_lichess*.tcl; do
    suite=${file##*/}
    run_suite "$suite"
    if [[ $suite == test_app_lichess_persistence.tcl ]]; then run_suite "$suite" restore; fi
done
# Includes all suite stdout/stderr, screenshots, journals and SCIDB_ERROR_LOG.
# Extra arguments are mission evidence/screencast roots; nonexistent roots fail.
error_logs=(tests/tmp-app/errors-*.log)
scan '' tests/tmp-app/lichess-hardening "$out" "${error_logs[@]}" "$@" >> "$out/grep.log" || status=1
cat "$out/grep.log"
if (( status )); then
    echo 'Lichess regression/token check FAILED (inspect paths above).'
else
    echo 'Lichess regression/token check PASSED.'
fi
exit "$status"
