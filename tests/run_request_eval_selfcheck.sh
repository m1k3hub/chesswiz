#!/bin/sh
# run_mode.sh MODE TAG [MATCH] -- corpus self-check without a model (gold/null)
cd "$(dirname "$0")/.." || exit 1
W=$PWD/tests/tmp-app/eval-w3/$2; rm -rf "$W"; mkdir -p "$W/home"
HOME=$W/home SCIDB_EVAL_WORK=$W SCIDB_AI_PROVIDER=stub timeout ${TMO:-1500} \
  xvfb-run -a -s '-screen 0 1920x1080x24' src/tkchesswiz tests/run_request_eval.tcl -mode "$1" -match "${3:-*}" > "$W/out.log" 2>&1
echo "rc=$?" >> "$W/out.log"
