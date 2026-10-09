# ======================================================================
# test_ai_journal.tcl -- the decision / override journal (tcl/ai-journal.tcl).
#
#   xvfb-run -a ./src/tkchesswiz tests/test_ai_journal.tcl
#
# Deterministic and file-only: recording, escaping, the forwarding sink,
# the reader, and the disabled default.
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
source [file join $root tcl ai-journal.tcl]

set file [file join [file dirname [file normalize [info script]]] tmp-app journal-[pid].txt]
catch { file delete $file }

# off by default: nothing is written
::ai::journal::configure -file ""
check "disabled by default" [expr {![::ai::journal::enabled]}]
::ai::journal::decision comment_kind "text" {ok 1 label tactics confidence 0.9 source classifier}
check "disabled: no file" [expr {![file exists $file]}]
check "read: a missing file is empty" [expr {[llength [::ai::journal::read $file]] == 0}]

# on: a decision and an override round-trip
::ai::journal::configure -file $file
::ai::journal::decision comment_kind "The knight forks the rook." \
	{ok 1 label tactics confidence 0.9 source classifier}
::ai::journal::override comment_kind "The knight forks the rook." opening tactics
set records [::ai::journal::read]
check "two records" [expr {[llength $records] == 2}]
set d [lindex $records 0]
check "decision fields" [expr {
	[dict get $d type] eq "decision" && [dict get $d feature] eq "comment_kind" \
	&& [dict get $d label] eq "tactics" && [dict get $d confidence] eq "0.9" \
	&& [dict get $d source] eq "classifier"
}]
set o [lindex $records 1]
check "override fields" [expr {
	[dict get $o type] eq "override" && [dict get $o proposed] eq "opening" \
	&& [dict get $o corrected] eq "tactics"
}]

# tabs and newlines in the state survive the round-trip
::ai::journal::decision event_type "a\tb\nc" {ok 1 label blitz confidence 0.5 source classifier}
set last [lindex [::ai::journal::read] end]
check "escaping round-trip" [expr {[dict get $last state] eq "a\tb\nc"}]

# the sink forwards the decision unchanged
set ::got {}
set script {apply {{d} {set ::got $d}}}
::ai::journal::logged feature "state" $script {ok 1 label L confidence 0.7 source classifier}
check "sink forwards" [expr {[dict get $::got label] eq "L"}]
check "sink records too" [expr {[llength [::ai::journal::read]] == 4}]

catch { file delete $file }
puts "AI-JOURNAL-FAILURES: $failures"
exit $failures
