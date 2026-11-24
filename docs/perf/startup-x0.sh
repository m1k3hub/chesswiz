#!/bin/bash
# Time-to-mapped + wrap.tcl slow calls on a display. usage: startup-x0.sh HOME DISPLAY OUT
H=$1; export DISPLAY=$2; OUT=$3
t0=$(date +%s%3N); (HOME=$H CHESSWIZ_LOG=debug PULSE_SINK=cwtests PROFOUT=$OUT nohup src/tkchesswiz -encoding utf-8 /media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/docs/perf/wrap.tcl >/dev/null 2>&1 &)
timeout 60 wish /media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/docs/perf/poll.tcl $t0; sleep 5
wish <<<"wm withdraw .; send Chesswiz profdump; catch {send Chesswiz {after 10 exit}}; exit"; sleep 2
