#!/usr/bin/env bash
# VAL-KNOW-003 evidence: the capability lookup answers the development
# corpus from the installed knowledge pack with no network access.
#
# Runs one app test (`knowledge-dev-corpus`) inside a network namespace.
# `unshare -n` is not permitted on every host, so bubblewrap is preferred.
#
# Usage: scripts/knowledge-offline-check.sh
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
home=$root/tests/tmp-app/know-eval/offline-home

if command -v bwrap >/dev/null 2>&1 && bwrap --unshare-net --dev-bind / / true 2>/dev/null; then
	isolation=(bwrap --unshare-net --dev-bind / / --)
elif unshare -n true 2>/dev/null; then
	isolation=(unshare -n)
else
	echo "SKIP: neither bwrap nor unshare can create a network namespace here" >&2
	exit 2
fi

rm -rf "$home"
mkdir -p "$home"

echo "VAL-KNOW-003 running offline under: ${isolation[*]}"
HOME=$home "${isolation[@]}" env HOME="$home" \
	xvfb-run -a -s '-screen 0 1920x1080x24' \
	"$root/src/tkchesswiz" "$root/tests/run_app_tests.tcl" \
	-file test_app_knowledge.tcl -match 'knowledge-dev-corpus'
