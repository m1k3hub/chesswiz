# ======================================================================
# test_ai_calibrate.tcl -- the calibration math and the threshold file.
#
#   xvfb-run -a ./src/tkscidb-beta tests/test_ai_calibrate.tcl
#
# Pure and deterministic: sweep/recommend over synthetic scored data, and
# the TSV write/load round-trip that feeds ::ai::systemone::threshold. The
# live measurement is `scripts/calibrate-systemone.tcl`; the transport it
# uses is covered by tests/test_ai_batch.tcl.
# ======================================================================

package require Tcl 8.5

set failures 0

proc check {name cond} {
	global failures
	if {$cond} {
		puts "PASS: $name"
	} else {
		puts "FAIL: $name"
		incr failures
	}
}

set root [file join [file dirname [file normalize [info script]]] ..]
source [file join $root tcl ai-provider.tcl]
source [file join $root tcl ai-systemone.tcl]
source [file join $root tcl ai-calibrate.tcl]

# gold choice confidence: first two right, last two wrong
set scored {{a a 0.90} {b b 0.80} {a b 0.40} {b a 0.20}}

# --- sweep -------------------------------------------------------------
set sweep [::ai::calibrate::sweep $scored]
proc rowAt {sweep t} {
	foreach row $sweep { if {abs([lindex $row 0] - $t) < 1e-9} { return $row } }
	return {}
}
check "sweep: everything answered at 0.0" \
	[expr {[lindex [rowAt $sweep 0.0] 1] == 1.0}]
check "sweep: half answered at 0.45" \
	[expr {abs([lindex [rowAt $sweep 0.45] 1] - 0.5) < 1e-9}]
check "sweep: perfect above the wrong answers" \
	[expr {abs([lindex [rowAt $sweep 0.45] 2] - 1.0) < 1e-9}]
check "sweep: one answered at 0.85" \
	[expr {abs([lindex [rowAt $sweep 0.85] 1] - 0.25) < 1e-9}]

# --- recommend ---------------------------------------------------------
set rec [::ai::calibrate::recommend $sweep 0.9]
check "recommend: lowest threshold meeting the target" \
	[expr {abs([lindex $rec 0] - 0.45) < 1e-9}]
check "recommend: keeps the most coverage" \
	[expr {abs([lindex $rec 1] - 0.5) < 1e-9}]

# nothing meets the target: fall back to the best accuracy, not to acting
set hopeless [::ai::calibrate::recommend [::ai::calibrate::sweep {{a b 0.9} {b a 0.8}}] 1.0]
check "recommend: a hopeless battery reports 0 accuracy" \
	[expr {[lindex $hopeless 2] == 0.0}]

# --- write / load round-trip ------------------------------------------
set file [file join [file dirname [file normalize [info script]]] tmp-app calibrate-[pid].tsv]
catch { file delete $file }
::ai::calibrate::write $file comment_kind plumb 0.85
::ai::calibrate::write $file event_type   plumb 0.60
::ai::calibrate::write $file comment_kind plumb 0.90
set chan [open $file r]
set text [read $chan]
close $chan
set lines {}
foreach line [split [string trim $text] "\n"] { if {$line ne ""} { lappend lines $line } }
check "write: one line per pair" [expr {[llength $lines] == 2}]
check "write: a repeat replaces, not duplicates" \
	[expr {[llength [lsearch -all -inline -glob $lines "comment_kind\tplumb\t0.9*"]] == 1}]

# load merges into Thresholds, and threshold reads it by backend
set savedThresholds $::ai::systemone::Thresholds
set savedBackend $::ai::systemone::Config(backend)
unset -nocomplain ::env(SCIDB_AI_COMMENT_KIND_MIN_CONFIDENCE)
set ::ai::systemone::Config(backend) plumb
set loaded [::ai::systemone::loadThresholds $file]
check "load: two entries read" [expr {$loaded == 2}]
check "load: the calibrated value is used" \
	[expr {[::ai::systemone::threshold comment_kind 0.6] == 0.9}]
set ::ai::systemone::Config(backend) other
set otherValue [::ai::systemone::threshold comment_kind 0.6]
check "load: an uncalibrated backend falls back" [expr {$otherValue == 0.6}]
# drop removes one pair, leaving the other
::ai::calibrate::drop $file comment_kind plumb
set chan [open $file r]
set text [::read $chan]
close $chan
check "drop: the failed pair is gone" [expr {[string first "comment_kind" $text] < 0}]
check "drop: the other pair stays" [expr {[string first "event_type" $text] >= 0}]

set ::ai::systemone::Thresholds $savedThresholds
set ::ai::systemone::Config(backend) $savedBackend
catch { file delete $file }

puts "AI-CALIBRATE-FAILURES: $failures"
exit $failures
