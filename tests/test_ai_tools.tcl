# ======================================================================
# test_ai_tools.tcl -- engine-as-tool grounding.
#
#   xvfb-run -a ./src/tkscidb-beta tests/test_ai_tools.tcl
#
# The model side is scripted (deterministic); the chess_engine tool runs the
# real Stockfish.  Set SCIDB_AI_LIVE=1 to drive a real cloud model instead.
# ======================================================================

set failures 0

proc check {name cond} {
	global failures
	if {$cond} { puts "PASS: $name" } else { puts "FAIL: $name"; incr failures }
}

set root [file join [file dirname [file normalize [info script]]] ..]
source [file join $root tcl ai-claims.tcl]
source [file join $root tcl ai-engine.tcl]
source [file join $root tcl ai-provider.tcl]
source [file join $root tcl ai-prompt.tcl]
source [file join $root tcl ai-generate.tcl]

# App-backed: needs the tkscidb shell. Skip cleanly if sourced elsewhere.
if {[llength [info commands ::scidb::ai::facts]] == 0} {
	puts "SKIP: requires the tkscidb shell (::scidb::ai::* unavailable)"
	puts "AI-TOOLS-FAILURES: 0"
	exit 0
}

set start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

# --- the engine tool itself ------------------------------------------
if {[::ai::engine::available]} {
	set out [::ai::generate::runTool chess_engine [dict create fen $start depth 8]]
	check "chess_engine returns an evaluation" [string match {*eval:*} $out]
	check "chess_engine returns a best move"   [string match {*best:*} $out]
	check "chess_engine returns a pv"          [string match {*pv:*} $out]
	::ai::engine::shutdown
} else {
	puts "SKIP: chess_engine tool (no UCI engine)"
}

# --- the tool loop, model side scripted ------------------------------
set call [dict create function [dict create name chess_engine \
	arguments [dict create fen $start depth 8]]]
set msg1 [dict create role assistant content "" tool_calls [list $call]]
set msg2 [dict create role assistant content "STRUCTURE: balanced."]

::ai::provider::configure -name stub -chatResponses [list $msg1 $msg2]
set r [::ai::generate::positionTools $start -depth 8]
check "tool loop calls the tool then finishes" [expr {[dict get $r attempts] == 2}]
check "tool loop returns the final text" \
	[expr {[dict get $r text] eq "STRUCTURE: balanced."}]
::ai::engine::shutdown

# --- optional live cloud model driving the engine --------------------
if {[info exists ::env(SCIDB_AI_LIVE)]} {
	if {[catch {
		::ai::provider::configure -name ollama -model deepseek-v4.1-flash:cloud \
			-timeout 180000 -options {num_predict 400}
		set g [::ai::generate::positionTools $start -depth 10]
	} e]} {
		puts "SKIP: live tool run unavailable ($e)"
	} else {
		check "live model returns text" [expr {[string length [dict get $g text]] > 0}]
		puts "LIVE rounds=[dict get $g attempts] grounded=[dict get $g grounded] flags=[llength [dict get $g claims]]"
		::ai::engine::shutdown
	}
}

puts "AI-TOOLS-FAILURES: $failures"
exit $failures
