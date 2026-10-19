#!/bin/bash
# Run every assistant action in its own process. Usage:
# bash tests/run_actions_isolated.sh stub|real [output-directory]
set -uo pipefail
mode=${1:-stub}
case "$mode" in stub|real) ;; *) echo 'expected stub or real' >&2; exit 2 ;; esac
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"
out=${2:-"$root/tests/tmp-app/partc/isolated-$mode"}
mkdir -p "$out"
out=$(cd "$out" && pwd)
# Metadata enumeration only: app-assistant has no top-level Tk calls. The
# actual tests below always load Tk through the existing application binary.
tclsh > "$out/actions.txt" <<'TCL'
package provide Tk 8.6
source tcl/actions.tcl
source tcl/app-assistant.tcl
source tcl/app-assistant-jobs.tcl
puts [join [::action::list] \n]
TCL
run_action() {
    local action=$1 test_home pattern rc test_file

    test_home=$(mktemp -d "$out/home-$action.XXXXXX")
    pattern="action-handler-$action"
    test_file=test_app_actions_all.tcl
    if [ "$mode" = real ]; then
        pattern="real-action-$action"
        test_file=test_app_actions_real_ui.tcl
    fi
    HOME="$test_home" \
        SCIDB_AI_HANDOFF_CMD="" \
        timeout 30 xvfb-run -a -s '-screen 0 1920x1080x24' \
        "$root/../../src/tkchesswiz" tests/run_app_tests.tcl \
        -file "$test_file" -match "$pattern" -verbose \
        > "$out/$action.log" 2>&1
    rc=$?
    rm -rf -- "$test_home"
    if [ "$rc" -eq 0 ] && rg -q "^ACTION-SKIP $action:" "$out/$action.log"; then
        rc=SKIP
    elif [ "$rc" -eq 0 ] && ! rg -q '^Total Passed: 1$' "$out/$action.log"; then
        rc=1
    fi
    printf '%s\t%s\n' "$action" "$rc" > "$out/$action.result"
}
# Optional bounded concurrency; every action still owns a fresh HOME, Xvfb,
# application process and timeout. Default remains serial for reproduction.
parallel=${SCIDB_ACTION_JOBS:-1}
if ! [[ "$parallel" =~ ^[1-9][0-9]*$ ]]; then echo 'invalid SCIDB_ACTION_JOBS' >&2; exit 2; fi
pids=()
while IFS= read -r action; do
    run_action "$action" &
    pids+=("$!")
    if [ "${#pids[@]}" -ge "$parallel" ]; then
        for pid in "${pids[@]}"; do wait "$pid"; done
        pids=()
    fi
done < "$out/actions.txt"
for pid in "${pids[@]}"; do wait "$pid"; done
status=0
: > "$out/results.tsv"
while IFS= read -r action; do
    cat "$out/$action.result" >> "$out/results.tsv"
    rc=$(cut -f2 "$out/$action.result")
    if [ "$rc" != 0 ] && [ "$rc" != SKIP ]; then status=1; fi
done < "$out/actions.txt"
cat "$out/results.tsv"
exit "$status"
