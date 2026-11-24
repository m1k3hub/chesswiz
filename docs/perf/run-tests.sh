#!/bin/bash
# Run app test files serially on Xvfb with a fresh HOME each; print totals/failures.
for t in "$@"; do
	H=$(mktemp -d)
	HOME=$H SCIDB_USERDIR=$H/.chesswiz PULSE_SINK=cwtests SCIDB_AI_UNCALIBRATED=1 timeout 1500 \
		xvfb-run -a -s '-screen 0 1920x1080x24' bash -c 'openbox & sleep 1; exec "$@"' _ \
		src/tkchesswiz tests/run_app_tests.tcl -file "$t" 2>&1 | grep -E "^test_.*Total|FAILED" | head -6
done
