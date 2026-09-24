# ======================================================================
# test_ai_narrate.tcl -- engine-native anatomy from the custom Stockfish.
#
#   xvfb-run -a ./src/tkscidb-beta tests/test_ai_narrate.tcl
#
# Requires the fork binary (engines/stockfish/src/stockfish); skips cleanly
# if it is absent or lacks the `narrate` command.
# ======================================================================

set failures 0

proc check {name cond} {
	global failures
	if {$cond} { puts "PASS: $name" } else { puts "FAIL: $name"; incr failures }
}

set root [file join [file dirname [file normalize [info script]]] ..]
source [file join $root tcl ai-narrate.tcl]
source [file join $root tcl ai-generate.tcl]

# App-backed: needs the tkscidb shell (::scidb::ai::moveFacts).
if {[llength [info commands ::scidb::ai::facts]] == 0} {
	puts "SKIP: requires the tkscidb shell (::scidb::ai::* unavailable)"
	puts "AI-NARRATE-FAILURES: 0"
	exit 0
}

set fork [file join $root engines stockfish src stockfish]
if {![file executable $fork]} {
	puts "SKIP: fork binary not found at $fork"
	puts "AI-NARRATE-FAILURES: 0"
	exit 0
}

::ai::narrate::configure -engine $fork
if {[::ai::narrate::lookup "8/8/8/8/8/8/8/K6k w - - 0 1"] eq ""} {
	puts "SKIP: fork binary has no working 'narrate' command"
	puts "AI-NARRATE-FAILURES: 0"
	exit 0
}

set start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
set iqp   "r1bq1rk1/pp2bppp/2n1pn2/2pp4/3P4/5NP1/PP3PBP/RNBQ1RK1 w - - 0 1"

# --- lookup -----------------------------------------------------------
set d [::ai::narrate::lookup $start]
check "lookup returns a dict" [expr {[llength $d] > 0}]
foreach key {phase legalMoves material pawns pieces kingSafety} {
	check "lookup has $key" [dict exists $d $key]
}
check "startpos legal moves is 20" [expr {[dict get $d legalMoves] == 20}]
check "startpos balance is 0" [expr {[dict get $d material balanceCp] == 0}]

set d [::ai::narrate::lookup $iqp]
check "IQP reports a white isolated pawn" \
	[expr {[dict get $d pawns white isolated] >= 1}]
check "IQP reports material imbalance" [expr {[dict get $d material balanceCp] < 0}]

# --- summary ----------------------------------------------------------
set s [::ai::narrate::summary $iqp]
check "summary non-empty" [string match {*balance*} $s]

# --- move delta -------------------------------------------------------
set delta [::ai::narrate::compare $start "Nf3"]
check "compare returns deltas" [expr {[llength $delta] > 0}]
check "compare has mobility deltas" [dict exists $delta mobility white]
check "Nf3 improves white mobility" [expr {[dict get $delta mobility white] > 0}]

# --- tool dispatch ----------------------------------------------------
check "chess_narrate tool works" \
	[string match {*mobility*} [::ai::generate::runTool chess_narrate [dict create fen $iqp]]]
check "chess_narrate_delta tool works" \
	[string match {*balance*} [::ai::generate::runTool chess_narrate_delta [dict create fen $start move Nf3]]]

puts "AI-NARRATE-FAILURES: $failures"
exit $failures
