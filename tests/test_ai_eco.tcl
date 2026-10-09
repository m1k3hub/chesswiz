# ======================================================================
# test_ai_eco.tcl -- ECO opening identification via ::scidb::ai::eco.
#
#   xvfb-run -a ./src/tkchesswiz tests/test_ai_eco.tcl
#
# Loads the repo's ECO table explicitly (the running app loads it at startup).
# ======================================================================

set failures 0

proc check {name cond} {
	global failures
	if {$cond} { puts "PASS: $name" } else { puts "FAIL: $name"; incr failures }
}

set root [file join [file dirname [file normalize [info script]]] ..]

# App-backed: needs the tkscidb shell. Skip cleanly if sourced elsewhere.
if {[llength [info commands ::scidb::ai::eco]] == 0} {
	puts "SKIP: requires the tkscidb shell (::scidb::ai::eco unavailable)"
	puts "AI-ECO-FAILURES: 0"
	exit 0
}

# the command must refuse to guess before the table exists
check "errors before the ECO table is loaded" \
	[catch {::scidb::ai::eco {e4 e5}} e0]

::scidb::app::load eco [file join $root src data eco.bin]

proc ecoOf {moves} { ::scidb::ai::eco $moves }

set r [ecoOf {e4}]
check "1.e4 is B00" [expr {[dict get $r code] eq "B00"}]

set r [ecoOf {e4 e5 Nf3 Nc6 Bb5}]
check "Ruy Lopez is C60" [expr {[dict get $r code] eq "C60"}]
check "Ruy Lopez name mentions Spanish" \
	[string match -nocase {*spanish*} [dict get $r name]]

set r [ecoOf {e4 c5 Nf3 d6 d4 cxd4 Nxd4 Nf6 Nc3 a6}]
check "Najdorf is B90" [expr {[dict get $r code] eq "B90"}]
check "Najdorf name mentions Najdorf" \
	[string match -nocase {*najdorf*} [dict get $r name]]

set r [ecoOf {d4 d5 c4 e6 Nc3 Nf6}]
check "QGD is D35" [expr {[dict get $r code] eq "D35"}]

set r [ecoOf {e4 c5}]
check "code format is letter + two digits" [regexp {^[A-E][0-9][0-9]$} [dict get $r code]]

check "illegal move errors" [catch {::scidb::ai::eco {e4 e5 Zz9}} e1]

puts "AI-ECO-FAILURES: $failures"
exit $failures
