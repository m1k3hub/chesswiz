#!/bin/bash
# usage: bench-run.sh <tcl-file-to-source> [setup-tcl]   (app on :77, scratch HOME)
D=/tmp/claude-1000/-media-michael-g-thomas-sas-mirror-src-chess-scidb-code-codex/b004314a-e474-44e6-b425-aa1a8d7ec8d9/scratchpad/drive
export DISPLAY=${BDISPLAY:-:77}
(HOME=$D/hx PULSE_SINK=cwtests CHESSWIZ_NO_SETUP_SCAN=1 nohup ${BIN:-src/tkchesswiz} -encoding utf-8 tcl/chesswiz --single-process >$D/b.log 2>&1 &)
for i in $(seq 80); do $D/cw 'winfo ismapped .application' 2>/dev/null | grep -q 1 && break; sleep 0.5; done; sleep 4
T=900 $D/cw "$2; source [pwd]/$1"
$D/cw 'after 10 exit' >/dev/null; sleep 2
