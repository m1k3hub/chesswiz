# ======================================================================
# test_ai_facts.tcl -- exercise the ::scidb::ai::* grounding commands.
#
# These bind db_chess_facts into the Tcl layer so the language layer can
# request anatomy without knowing anything about chess itself.  Run with:
#   xvfb-run -a ./src/tkchesswiz tests/test_ai_facts.tcl
# ======================================================================

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

# App-backed: needs the tkscidb shell. Skip cleanly if sourced elsewhere.
if {[llength [info commands ::scidb::ai::facts]] == 0} {
	puts "SKIP: requires the tkscidb shell (::scidb::ai::* unavailable)"
	puts "AI-FACTS-FAILURES: 0"
	exit 0
}

set start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

# --- position facts ---------------------------------------------------
set json [::scidb::ai::facts $start]
check "facts command exists and returns JSON" [string match {*"sideToMove":"white"*} $json]
check "facts carries legal move stats"      [string match {*"legalMoves":20*} $json]
check "facts carries motifs"                [string match {*"forks"*} $json]
check "facts carries phase"                 [string match {*"phase":"opening"*} $json]

# --- text rendering ---------------------------------------------------
set txt [::scidb::ai::text $start]
check "text command returns anatomy" [string match {*mobility*} $txt]

# --- move facts -------------------------------------------------------
set move [::scidb::ai::moveFacts Nf3 $start]
check "moveFacts SAN is Latin"    [string match {*"san":"Nf3"*} $move]
check "moveFacts developed flag"  [string match {*"developed":true*} $move]

# --- a tactical move over a real position -----------------------------
set matePos "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4"
set mate [::scidb::ai::moveFacts Qxf7 $matePos]
check "moveFacts detects mate"          [string match {*"mate":true*} $mate]
check "moveFacts material swing"        [string match {*"materialChangeCp":100*} $mate]
check "moveFacts static exchange"       [string match {*"seeCp":100*} $mate]

# --- error handling ---------------------------------------------------
check "invalid FEN raises an error" \
	[catch {::scidb::ai::facts "not a position"} e1]
check "illegal move raises an error" \
	[catch {::scidb::ai::moveFacts e5 $start} e2]

puts "AI-FACTS-FAILURES: $failures"
exit $failures
