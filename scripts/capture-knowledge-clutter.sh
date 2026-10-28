#!/usr/bin/env bash
# VAL-KNOW-007 evidence: capture a fresh start (and the default board layout)
# and compare the pixels with the G3-b snapshot taken before this work.
#
# Usage: scripts/capture-knowledge-clutter.sh [output-directory]
# Default output: tests/tmp-app/know-eval/after
#
# Requires Xvfb and ImageMagick (`compare`, `import`), as the rest of the
# app test suite does.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
out=${1:-$root/tests/tmp-app/know-eval/after}
snap=$root/tests/tmp-app/know-eval/g3b-snapshot
home=$root/tests/tmp-app/know-eval/capture-home

mkdir -p "$out"
rm -rf "$home"
mkdir -p "$home"

driver=$(mktemp "$out/capture-XXXXXX.tcl")
trap 'rm -f "$driver"' EXIT

cat >"$driver" <<'TCL'
set argvCopy $argv
set argv {--single-process}
set ::env(SCIDB_AI_TRIAGE) 0
set ::env(SCIDB_AI_CLASSIFIER) off
source -encoding utf-8 [file join [pwd] tcl chesswiz]
# A fresh HOME is a first run: skip the language chooser, as the runner does.
set ::scidb::dir::setup 0
set out [lindex $argvCopy 0]

set deadline [expr {[clock milliseconds] + 20000}]
while {![info exists ::application::Vars(ready)] || !$::application::Vars(ready)} {
	update
	if {[clock milliseconds] > $deadline} { break }
	after 20
}
update
update idletasks
exec import -window root [file join $out fresh-start.png]
set fh [open [file join $out fresh-start-toplevels.txt] w]
foreach w [wm stackorder .] {
	puts $fh "$w mapped=[winfo ismapped $w] class=[winfo class $w] title=[wm title $w]"
}
close $fh

catch { ::application::switchTab board }
if {[llength [info commands ::application::openPane]]} { catch { ::application::openPane board } }
update
after 300
update
exec import -window root [file join $out default-layout.png]
set fh [open [file join $out default-layout-toplevels.txt] w]
foreach w [wm stackorder .] {
	puts $fh "$w mapped=[winfo ismapped $w] class=[winfo class $w] title=[wm title $w]"
}
close $fh
puts "captured $out"
exit 0
TCL

HOME=$home xvfb-run -a -s '-screen 0 1920x1080x24' \
	"$root/src/tkchesswiz" "$driver" "$out"

status=0
for pair in "fresh-start fresh-start" "default-layout default-layout"; do
	set -- $pair
	shot=$1
	base=$2
	if [ ! -f "$snap/$base.png" ]; then
		echo "missing baseline: $snap/$base.png"
		status=1
		continue
	fi
	metric=$(compare -metric RMSE "$snap/$base.png" "$out/$shot.png" null: 2>&1 || true)
	echo "VAL-KNOW-007 $shot RMSE vs G3-b: $metric"
	case "$metric" in
	0*) echo "  PASS: $shot is pixel-identical to G3-b" ;;
	*) echo "  DIFFERS: inspect $out/$shot.png against $snap/$base.png"; status=1 ;;
	esac
done

for pair in "toplevels fresh-start-toplevels" "default-layout-toplevels default-layout-toplevels"; do
	set -- $pair
	base=$1
	shot=$2
	if [ ! -f "$snap/$base.txt" ]; then continue; fi
	if diff -u "$snap/$base.txt" "$out/$shot.txt" >/dev/null 2>&1; then
		echo "VAL-KNOW-007 $shot: PASS"
	else
		echo "VAL-KNOW-007 $shot: DIFFER"
		diff -u "$snap/$base.txt" "$out/$shot.txt" || true
		status=1
	fi
done

exit $status
