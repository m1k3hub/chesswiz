# ======================================================================
# test_ai_generate.tcl -- grounded generation loop.
#
#   xvfb-run -a ./src/tkscidb-beta tests/test_ai_generate.tcl
#
# Uses the deterministic `stub` provider by default.  Set SCIDB_AI_LIVE=1 to
# also exercise a real local Ollama model (slower, non-deterministic).
# ======================================================================

set failures 0

proc check {name cond} {
	global failures
	if {$cond} { puts "PASS: $name" } else { puts "FAIL: $name"; incr failures }
}

set root [file join [file dirname [file normalize [info script]]] ..]
source [file join $root tcl ai-claims.tcl]
source [file join $root tcl ai-provider.tcl]
source [file join $root tcl ai-prompt.tcl]
source [file join $root tcl ai-generate.tcl]

# App-backed: needs the tkscidb shell. Skip cleanly if sourced elsewhere.
if {[llength [info commands ::scidb::ai::facts]] == 0} {
	puts "SKIP: requires the tkscidb shell (::scidb::ai::* unavailable)"
	puts "AI-GENERATE-FAILURES: 0"
	exit 0
}

set start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
set iqp   "r1bq1rk1/pp2bppp/2n1pn2/2pp4/3P4/5NP1/PP3PBP/RNBQ1RK1 w - - 0 1"

# --- prompt construction ---------------------------------------------
set p [::ai::prompt::position $start -engine 0]
check "prompt embeds the fact pack"      [string match {*"legalMoves":20*} $p]
check "prompt asks only for the sections" [string match {*ONLY the three sections*} $p]
check "prompt forbids preamble"          [string match {*Do not repeat or restate*} $p]
check "prompt asks for sections"         [string match {*STRUCTURE:*} $p]
check "rules are a separate system message" \
	[string match {*Follow these rules exactly*} [::ai::prompt::rules]]
check "rules state the grounding rule" \
	[string match {*ONLY state facts*} [::ai::prompt::rules]]

# --- grounded response, one attempt ----------------------------------
::ai::provider::configure -name stub -responses {"The position is balanced."}
set g [::ai::generate::position $start -engine 0]
check "grounded response passes"          [expr {[dict get $g grounded] == 1}]
check "grounded response takes one try"   [expr {[dict get $g attempts] == 1}]
check "grounded response has no claims"   [expr {[llength [dict get $g claims]] == 0}]

# --- ungrounded first, grounded second -> retry ----------------------
::ai::provider::configure -name stub -responses {
	"White has an isolated pawn."
	"Both sides have the bishop pair."
}
set g [::ai::generate::position $start -engine 0 -retries 1]
check "ungrounded claim triggers a retry" [expr {[dict get $g attempts] == 2}]
check "retry recovers to grounded"        [expr {[dict get $g grounded] == 1}]

# --- no retries -> the ungrounded claim is reported ------------------
::ai::provider::configure -name stub -responses {"White has an isolated pawn."}
set g [::ai::generate::position $start -engine 0 -retries 0]
check "ungrounded claim is reported" [expr {[dict get $g grounded] == 0}]
check "reported claim names the problem" \
	[string match {*isolated*} [lindex [dict get $g claims] 0]]

# --- a genuinely grounded structural claim ---------------------------
::ai::provider::configure -name stub -responses {"White has an isolated queen's pawn."}
set g [::ai::generate::position $iqp -engine 0]
check "grounded IQP claim passes" [expr {[dict get $g grounded] == 1}]

# --- optional live local model ---------------------------------------
if {[info exists ::env(SCIDB_AI_LIVE)]} {
	if {[catch {
		::ai::provider::configure -name ollama -model qwen3.8:4b \
			-timeout 300000 -options {num_predict 160}
		set g [::ai::generate::position $start -engine 0 -retries 0]
		set text [dict get $g text]
	} e]} {
		puts "SKIP: live model unavailable ($e)"
	} else {
		check "live model returns text" [expr {[string length $text] > 0}]
		puts "LIVE grounded=[dict get $g grounded] claims=[llength [dict get $g claims]]"
	}
}

puts "AI-GENERATE-FAILURES: $failures"
exit $failures
