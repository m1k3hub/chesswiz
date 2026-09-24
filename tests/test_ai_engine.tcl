# ======================================================================
# test_ai_engine.tcl -- engine facts (eval + move classification).
#
#   xvfb-run -a ./src/tkscidb-beta tests/test_ai_engine.tcl
#
# Requires a UCI engine on PATH (stockfish); skips cleanly if absent.
# ======================================================================

set failures 0

proc check {name cond} {
	global failures
	if {$cond} { puts "PASS: $name" } else { puts "FAIL: $name"; incr failures }
}

set root [file join [file dirname [file normalize [info script]]] ..]
source [file join $root tcl ai-engine.tcl]

# App-backed: needs the tkscidb shell for ::scidb::ai::moveFacts.
if {[llength [info commands ::scidb::ai::moveFacts]] == 0} {
	puts "SKIP: requires the tkscidb shell (::scidb::ai::moveFacts unavailable)"
	puts "AI-ENGINE-FAILURES: 0"
	exit 0
}

if {![::ai::engine::available]} {
	puts "SKIP: no UCI engine found (set ::ai::engine::configure -engine /path/to/stockfish)"
	puts "AI-ENGINE-FAILURES: 0"
	exit 0
}

::ai::engine::configure -depth 10

set start   "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
set mateIn1 "6k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1"
set blunder "r1bqkbnr/pppp1ppp/2n5/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR b KQkq - 4 4"
# --- evaluate ---------------------------------------------------------
set e [::ai::engine::evaluate $start]
check "evaluate returns a UCI best move" \
	[regexp {^[a-h][1-8][a-h][1-8][qrbn]?$} [dict get $e bestMove]]
check "evaluate returns cp or mate" [expr {[dict get $e kind] in {cp mate}}]
check "evaluate returns a pv"       [expr {[llength [dict get $e pv]] > 0}]

set e2 [::ai::engine::evaluate $start]
check "evaluate is deterministic at fixed depth" \
	[expr {[dict get $e bestMove] eq [dict get $e2 bestMove]}]

set e2m [::ai::engine::evaluate $start -multipv 2]
check "evaluate exposes the only-move gap" \
	[expr {[dict exists $e2m gapCp] && [dict get $e2m gapCp] >= 0}]
check "startpos is not an only-move" [expr {[dict get $e2m gapCp] < 150}]

set m [::ai::engine::evaluate $mateIn1]
check "evaluate detects mate" [expr {[dict get $m kind] eq "mate" && [dict get $m value] == 1}]

# --- classify ---------------------------------------------------------
set good [::ai::engine::classify $start "e4"]
check "classify(e4) is strong" \
	[expr {[dict get $good classification] in {Best Excellent}}]
check "classify(e4) loses little" [expr {[dict get $good cpLoss] < 30}]

set bad [::ai::engine::classify $blunder "Nf6"]
check "classify(Nf6??) is a blunder" [expr {[dict get $bad classification] eq "Blunder"}]
check "classify(Nf6??) loses material-scale eval" [expr {[dict get $bad cpLoss] > 200}]
check "classify reports uci + best" \
	[expr {[dict get $bad uci] eq "g8f6" && [regexp {^[a-h][1-8][a-h][1-8]} [dict get $bad bestMove]]}]
check "blunder position is not an only move" [expr {[dict get $bad onlyMove] == 0}]

set only [::ai::engine::classify $mateIn1 "Re8"]
check "classify(Re8#) is best" [expr {[dict get $only classification] eq "Best"}]
check "classify flags an only move" [expr {[dict get $only onlyMove] == 1}]

::ai::engine::shutdown

puts "AI-ENGINE-FAILURES: $failures"
exit $failures
