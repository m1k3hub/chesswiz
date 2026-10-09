# ======================================================================
# test_ai_precedent.tcl -- master-practice evidence in the narration prompt.
#
#   xvfb-run -a ./src/tkchesswiz tests/test_ai_precedent.tcl
#
# Builds a tiny corpus index from a generated PGN, then checks that
# ::ai::precedent::lookup reads it and that the prompt carries the evidence.
# ======================================================================

set failures 0

proc check {name cond} {
	global failures
	if {$cond} { puts "PASS: $name" } else { puts "FAIL: $name"; incr failures }
}

set root [file join [file dirname [file normalize [info script]]] ..]
source [file join $root tcl ai-precedent.tcl]
source [file join $root tcl ai-prompt.tcl]
source [file join $root tcl ai-claims.tcl]

# App-backed: needs the tkscidb shell (::scidb::ai::facts, json).
if {[llength [info commands ::scidb::ai::facts]] == 0} {
	puts "SKIP: requires the tkscidb shell (::scidb::ai::* unavailable)"
	puts "AI-PRECEDENT-FAILURES: 0"
	exit 0
}

set script [file join $root scripts corpus_precedent.py]
set tmp [file join $root tests tmp-precedent]
file mkdir $tmp
set pgn [file join $tmp mini.pgn]
set db  [file join $tmp mini.sqlite]
file delete -force $db

set fh [open $pgn w]
puts $fh {[Event "t1"]
[Result "1-0"]

1. d4 Nf6 2. c4 e6 3. Nc3 Bb4 4. e3 1-0

[Event "t2"]
[Result "0-1"]

1. d4 Nf6 2. c4 e6 3. Nc3 Bb4 4. e3 0-1

[Event "t3"]
[Result "1/2-1/2"]

1. d4 Nf6 2. c4 e6 3. Nc3 Bb4 4. Qc2 1/2-1/2}
close $fh

exec python3 $script build --pgn $pgn --db $db --max-games 10

# FEN after 1.d4 Nf6 2.c4 e6 3.Nc3 Bb4 -- White to move
set fen "rnbqk2r/pppp1ppp/4pn2/8/1bPP4/2N5/PP2PPPP/R1BQKBNR w KQkq - 0 4"

::ai::precedent::configure -index $db -script $script

set d [::ai::precedent::lookup $fen]
check "lookup finds the position" [expr {[llength $d] > 0}]
check "lookup reports three games" [expr {[dict get $d games] == 3}]
check "lookup is side-to-move aware" [expr {[dict get $d sideToMove] eq "white"}]

set e3 {}
foreach m [dict get $d moves] {
	if {[dict get $m move] eq "e2e3"} { set e3 $m }
}
check "4.e3 is 66.7% of games" [expr {[dict get $e3 share] == 66.7}]
check "4.e3 scores 50% for White" [expr {[dict get $e3 scorePct] == 50.0}]

set summary [::ai::precedent::summary $fen]
check "summary mentions games" [string match {*3 games*} $summary]

set prompt [::ai::prompt::position $fen -engine 0]
check "prompt carries MASTER PRACTICE" [string match {*MASTER PRACTICE:*} $prompt]

# an unconfigured index yields no precedent rather than an error
::ai::precedent::configure -index [file join $tmp missing.sqlite]
check "missing index yields no summary" [expr {[::ai::precedent::summary $fen] eq ""}]
set prompt [::ai::prompt::position $fen -engine 0]
check "prompt omits MASTER PRACTICE when unknown" \
	[expr {![string match {*MASTER PRACTICE:*} $prompt]}]

file delete -force $tmp

puts "AI-PRECEDENT-FAILURES: $failures"
exit $failures
