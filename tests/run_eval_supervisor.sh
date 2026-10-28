#!/bin/sh
# ======================================================================
# Restartable evaluation supervisor (VAL-KNOW-008, VAL-AI-012).
#
# The assistant's provider request is asynchronous, but a stalled DNS/TLS
# connect can leave the whole Tcl interpreter waiting, so no timer inside
# the harness can end that item. This wrapper watches the item logs and,
# when an item has produced nothing for STALL seconds, kills that attempt
# and starts the harness again with -skip-done. Completed items are read
# back from their logs, so a request is never sent to the model twice.
#
#   tests/run_eval_supervisor.sh request|bounds WORKDIR PROVIDER MODEL [MATCH]
#
# Environment: STALL (seconds without a new item log, default 180),
#              MAX_RUNS (default 12). The harness work directory must be
#              the same on every run; the report is rewritten each time
#              and counts the completed items.
# ======================================================================
set -u

kind=$1
work=$2
provider=$3
model=$4
match=${5:-*}

root=$(cd "$(dirname "$0")/.." && pwd)
stall=${STALL:-180}
maxruns=${MAX_RUNS:-12}
app=${SCIDB_EVAL_APP:-$root/src/tkchesswiz}
log=$work/supervisor.log

case $kind in
	request) script=tests/run_request_eval.tcl ;;
	bounds)  script=tests/run_bounds_eval.tcl ;;
	*) echo "usage: $0 request|bounds WORKDIR PROVIDER MODEL [MATCH]" >&2; exit 2 ;;
esac

mkdir -p "$work/items" "$work/home"
# The app opens the database by path; a relative work directory confuses the
# later lookups (db::get codec), so every path passed down is absolute.
work=$(cd "$work" && pwd)
log=$work/supervisor.log
: > "$log"

run=1
while [ "$run" -le "$maxruns" ]; do
	echo "[$(date +%H:%M:%S)] attempt $run: $kind $provider/$model match=$match" >>"$log"
	HOME=$work/home SCIDB_EVAL_WORK=$work \
	SCIDB_AI_PROVIDER=$provider SCIDB_AI_MODEL=$model \
	SCIDB_AI_CLASSIFIER=typesafe SCIDB_AI_ROUTE=auto \
	xvfb-run -a -s '-screen 0 1920x1080x24' "$app" \
		"$script" -match "$match" -skip-done ${EVAL_ARGS:-} >>"$log" 2>&1 &
	pid=$!

	# Watch the newest item log. A finished run exits by itself.
	start=$(date +%s)
	stalled=0
	while kill -0 "$pid" 2>/dev/null; do
		sleep 5
		now=$(date +%s)
		newest=$(ls -t "$work"/items/*.txt 2>/dev/null | head -1)
		if [ -n "$newest" ]; then
			age=$(( now - $(stat -c %Y "$newest") ))
			# the skip-done pass may run for a while before the first new item
			if [ $(( now - start )) -ge "$stall" ] && [ "$age" -ge "$stall" ]; then
				stalled=1; break
			fi
		fi
	done

	if [ "$stalled" -eq 1 ]; then
		echo "[$(date +%H:%M:%S)] stall: no item for ${stall}s; stopping attempt $run" >>"$log"
		for child in $(pgrep -P "$pid" 2>/dev/null); do kill "$child" 2>/dev/null; done
		kill "$pid" 2>/dev/null
		sleep 2
		# a frozen app may be a grandchild of xvfb-run
		for child in $(pgrep -P "$pid" 2>/dev/null); do kill -9 "$child" 2>/dev/null; done
		kill -9 "$pid" 2>/dev/null
	else
		wait "$pid"
		echo "[$(date +%H:%M:%S)] attempt $run exited $?" >>"$log"
	fi

	if grep -q '^TOTAL ' "$work/report.txt" 2>/dev/null; then
		echo "[$(date +%H:%M:%S)] complete" >>"$log"
		grep '^TOTAL ' "$work/report.txt" >>"$log"
		exit 0
	fi
	run=$((run + 1))
done

echo "[$(date +%H:%M:%S)] gave up after $maxruns attempts" >>"$log"
exit 1
