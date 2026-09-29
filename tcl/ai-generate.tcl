# ======================================================================
# ::ai::generate -- grounded generation: prompt -> provider -> verify -> retry.
#
# The model writes; the claim checker verifies; contradictions are fed back and
# the model gets one more try.  The result always carries the claims that could
# not be grounded, so the caller can annotate or reject the text.
#
#   ::ai::generate::position <fen> ?-retries 1? ?-audience club? ...
#       -> dict {text ... claims {...} attempts N grounded 0|1}
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-generate
}

package require Tcl 8.5

namespace eval ai {
namespace eval generate {}
}


proc ::ai::generate::position {fen args} {
	array set opts [list -retries 1 -audience club -perspective neutral -engine 1 -depth 12]
	array set opts $args

	set prompt [::ai::prompt::position $fen \
		-audience $opts(-audience) -perspective $opts(-perspective) \
		-engine $opts(-engine) -depth $opts(-depth)]

	set attempt 0
	set problems {}
	set text ""

	while {1} {
		incr attempt
		set text [::ai::provider::complete $prompt -system [::ai::prompt::rules]]
		set problems [::ai::claims::check $fen $text]

		if {[llength $problems] == 0 || $attempt > $opts(-retries)} {
			break
		}
		append prompt "\n\nYour previous answer made claims the facts contradict: [join $problems {; }]. Rewrite it without those claims."
	}

	return [dict create \
		text $text \
		claims $problems \
		attempts $attempt \
		grounded [expr {[llength $problems] == 0}]]
}


# ----------------------------------------------------------------------
# Asynchronous variant, for the UI: the callback <script> is invoked with a
# single dict {ok 1 text ... claims ... attempts ... grounded ...} or
# {ok 0 error ...}.  The event loop keeps running throughout.
# ----------------------------------------------------------------------

proc ::ai::generate::positionAsync {fen script args} {
	array set opts [list -retries 1 -audience club -perspective neutral -engine 1 -depth 12]
	array set opts $args

	set prompt [::ai::prompt::position $fen \
		-audience $opts(-audience) -perspective $opts(-perspective) \
		-engine $opts(-engine) -depth $opts(-depth)]

	set state [dict create fen $fen prompt $prompt attempt 0 retries $opts(-retries) script $script]
	attemptAsync $state
	return
}


proc ::ai::generate::attemptAsync {state} {
	dict incr state attempt
	::ai::provider::completeAsync [dict get $state prompt] \
		[namespace code [list ::ai::generate::onComplete $state]] \
		-system [::ai::prompt::rules]
	return
}


# Any error in a step (a malformed reply, a failing tool) must still reach
# the caller's callback, or the UI would wait forever.
proc ::ai::generate::onComplete {state result} {
	if {[catch {onCompleteImpl $state $result} err]} {
		uplevel #0 [list {*}[dict get $state script] [dict create ok 0 error $err]]
	}
	return
}


# The rhetoric/coverage check calls this with its own result {ok 1 notices N}
# or {ok 0}; merge the notices into the generation payload and deliver it
# to the original caller. On ok 0 (no classifier, error, low confidence)
# the payload is delivered exactly as it was — today's report, no badge.
proc ::ai::generate::deliver {script payload result} {
	if {[dict get $result ok] && [llength [dict get $result notices]]} {
		dict set payload notices [dict get $result notices]
	}
	uplevel #0 [list {*}$script $payload]
	return
}


proc ::ai::generate::onCompleteImpl {state result} {
	set script [dict get $state script]

	if {![dict get $result ok]} {
		uplevel #0 [list {*}$script [dict create ok 0 error [dict get $result error]]]
		return
	}

	set text [dict get $result text]
	set problems [::ai::claims::check [dict get $state fen] $text]

	if {[llength $problems] == 0 || [dict get $state attempt] > [dict get $state retries]} {
		# The claim checker (deterministic, C++/regex) has passed or we've
		# run out of retries. Before handing the result to the caller, ask
		# the System One classifier for an advisory second opinion on the
		# *language* (rhetoric, answer-coverage) — questions the claim
		# checker cannot see. The notices are fixed, application-owned
		# strings; the classifier only picks a label. On any abstention the
		# result reaches the caller unchanged (today's behaviour).
		set context [expr {[dict exists $state context] ? [dict get $state context] : ""}]
		set task [expr {[string length $context] ? $context : "Explain the chess position."}]
		set payload [dict create \
			ok 1 text $text claims $problems attempts [dict get $state attempt] \
			grounded [expr {[llength $problems] == 0}] \
			evidence [evidenceFromText [dict get $state prompt]]]
		if {[llength [info commands ::ai::rhetoric::check]]} {
			::ai::rhetoric::check $task $text \
				[namespace code [list ::ai::generate::deliver $script $payload]]
		} else {
			uplevel #0 [list {*}$script $payload]
		}
		return
	}

	dict set state prompt "[dict get $state prompt]\n\nYour previous answer made claims the facts contradict: [join $problems {; }]. Rewrite it without those claims."
	attemptAsync $state
	return
}


# ----------------------------------------------------------------------
# Tool-grounded generation: the model can call a strong engine (Stockfish)
# and the ECO table while it writes.  Facts come from the tool, so the model
# reasons over real evaluations instead of recalled ones.
# ----------------------------------------------------------------------

namespace eval ai {
namespace eval generate {

variable Tools {[{"type":"function","function":{"name":"chess_engine","description":"Evaluate a chess position with Stockfish. Returns the evaluation, best move, principal variation and the second-best gap.","parameters":{"type":"object","properties":{"fen":{"type":"string","description":"FEN of the position to evaluate"},"depth":{"type":"integer","description":"search depth, default 12"}},"required":["fen"]}}},{"type":"function","function":{"name":"chess_eco","description":"Identify the ECO opening (code and name) for a line of moves from the initial position.","parameters":{"type":"object","properties":{"moves":{"type":"string","description":"space-separated SAN moves from the start position"}},"required":["moves"]}}},{"type":"function","function":{"name":"chess_narrate","description":"Engine-native position anatomy (material, pawn structure, mobility, king safety) from the custom Stockfish narrate command.","parameters":{"type":"object","properties":{"fen":{"type":"string","description":"FEN of the position"}},"required":["fen"]}}},{"type":"function","function":{"name":"chess_narrate_delta","description":"How a move changes the engine's own anatomy: material balance, mobility, isolated and passed pawn counts before vs after.","parameters":{"type":"object","properties":{"fen":{"type":"string","description":"FEN before the move"},"move":{"type":"string","description":"the move in SAN or UCI"}},"required":["fen","move"]}}}]}

} ;# namespace generate
} ;# namespace ai


proc ::ai::generate::runTool {name cargs} {
	switch -- $name {
		chess_engine {
			set fen [dict get $cargs fen]
			set depth [expr {[dict exists $cargs depth] ? [dict get $cargs depth] : 12}]

			if {[catch {::ai::engine::evaluate $fen -depth $depth -multipv 2} e]} {
				return "engine error: $e"
			}

			set out "eval: [dict get $e kind] [dict get $e value]; best: [dict get $e bestMove]; pv: [join [dict get $e pv] { }]"
			if {[dict exists $e gapCp]} { append out "; second-best gap: [dict get $e gapCp] cp" }
			return $out
		}
		chess_eco {
			set moves [dict get $cargs moves]

			if {[catch {::scidb::ai::eco $moves} r]} { return "eco error: $r" }
			return "ECO [dict get $r code]: [dict get $r name]"
		}
		chess_narrate {
			if {[llength [info commands ::ai::narrate::summary]] == 0} { return "narrate unavailable" }
			set summary [::ai::narrate::summary [dict get $cargs fen]]
			return [expr {$summary ne "" ? $summary : "narrate unavailable for this position"}]
		}
		chess_narrate_delta {
			if {[llength [info commands ::ai::narrate::compare]] == 0} { return "narrate unavailable" }
			set d [::ai::narrate::compare [dict get $cargs fen] [dict get $cargs move]]
			if {[llength $d] == 0} { return "delta unavailable" }
			return "balance [dict get $d balanceCp]cp; white mobility [dict get $d mobility white]; black mobility [dict get $d mobility black]"
		}
		default {
			return "unknown tool: $name"
		}
	}
}


proc ::ai::generate::buildMessages {fen audience perspective depth {context ""}} {
	set user [::ai::prompt::position $fen \
		-audience $audience -perspective $perspective -engine 0 -depth $depth]

	# A caller-supplied context (a selected move, a game, a comment) is the
	# task; the fact pack above still grounds it.
	if {$context ne ""} { append user "\n$context\n" }

	append user "\nYou may call chess_engine with the FEN to obtain an evaluation, best move and principal variation,"
	append user " and chess_eco to identify an opening. State an evaluation only if you obtained it from chess_engine.\n"

	return [list \
		[dict create role system content [::ai::prompt::rules]] \
		[dict create role user content $user]]
}


proc ::ai::generate::positionTools {fen args} {
	array set opts [list -audience club -perspective neutral -depth 12 -maxRounds 4]
	array set opts $args

	set messages [buildMessages $fen $opts(-audience) $opts(-perspective) $opts(-depth)]
	set rounds 0
	set text ""

	while {$rounds < $opts(-maxRounds)} {
		incr rounds
		# the last round offers no tools, so the model has to answer in prose
		set tools [expr {$rounds < $opts(-maxRounds) ? $::ai::generate::Tools : ""}]
		set msg [::ai::provider::chat $messages $tools]

		if {$tools ne "" && [dict exists $msg tool_calls] && [llength [dict get $msg tool_calls]]} {
			lappend messages $msg
			foreach call [dict get $msg tool_calls] {
				set fn [dict get $call function]
				set name [dict get $fn name]
				set cargs [expr {[dict exists $fn arguments] ? [dict get $fn arguments] : {}}]
				lappend messages [dict create role tool content [runTool $name $cargs] tool_name $name]
			}
			continue
		}

		set text [expr {[dict exists $msg content] ? [dict get $msg content] : ""}]
		break
	}

	set problems [noAnswer $text [::ai::claims::check $fen $text]]
	return [dict create text $text claims $problems attempts $rounds grounded [expr {[llength $problems] == 0}]]
}


# An empty reply verifies trivially; it must not be reported as grounded.
proc ::ai::generate::noAnswer {text problems} {
	if {[string trim $text] eq ""} { lappend problems "model returned no assessment" }
	return $problems
}


# The evidence lines (engine, master practice, annotated examples) carried in the
# prompt, for display alongside the narrative in the report pane.
proc ::ai::generate::evidenceFromText {text} {
	set lines {}
	foreach line [split $text "\n"] {
		foreach prefix {ENGINE: MASTER PRACTICE: ANNOTATED EXAMPLES:} {
			if {[string match "$prefix*" $line]} {
				lappend lines [string trim $line]
				break
			}
		}
	}
	return $lines
}


proc ::ai::generate::positionToolsAsync {fen script args} {
	array set opts [list -audience club -perspective neutral -depth 12 -maxRounds 4 -retries 1 -context "" -line ""]
	array set opts $args

	set state [dict create \
		fen      $fen \
		line     $opts(-line) \
		messages [buildMessages $fen $opts(-audience) $opts(-perspective) $opts(-depth) $opts(-context)] \
		rounds   0 \
		maxRounds $opts(-maxRounds) \
		attempt  0 \
		retries  $opts(-retries) \
		script   $script]

	toolsStep $state
	return
}


proc ::ai::generate::toolsStep {state} {
	# the last round offers no tools, so the model has to answer in prose
	set tools [expr {[dict get $state rounds] + 1 < [dict get $state maxRounds]
		? $::ai::generate::Tools : ""}]
	::ai::provider::chatAsync [dict get $state messages] $tools \
		[namespace code [list ::ai::generate::onToolStep $state]]
	return
}


# Any error in a step (a malformed reply, a failing tool) must still reach
# the caller's callback, or the UI would wait forever.
proc ::ai::generate::onToolStep {state result} {
	if {[catch {onToolStepImpl $state $result} err]} {
		uplevel #0 [list {*}[dict get $state script] [dict create ok 0 error $err]]
	}
	return
}


proc ::ai::generate::onToolStepImpl {state result} {
	set script [dict get $state script]

	if {![dict get $result ok]} {
		uplevel #0 [list {*}$script [dict create ok 0 error [dict get $result error]]]
		return
	}

	set msg [dict get $result message]
	dict incr state rounds

	if {   [dict exists $msg tool_calls] && [llength [dict get $msg tool_calls]]
	    && [dict get $state rounds] < [dict get $state maxRounds]} {
		dict lappend state messages $msg
		foreach call [dict get $msg tool_calls] {
			set fn [dict get $call function]
			set name [dict get $fn name]
			set cargs [expr {[dict exists $fn arguments] ? [dict get $fn arguments] : {}}]
			dict lappend state messages [dict create role tool content [runTool $name $cargs] tool_name $name]
		}
		toolsStep $state
		return
	}

	set text [expr {[dict exists $msg content] ? [dict get $msg content] : ""}]
	set problems [noAnswer $text [::ai::claims::check [dict get $state fen] $text [dict get $state line]]]

	# one more try when the narrative contradicts the facts
	if {[llength $problems] && [dict get $state attempt] < [dict get $state retries]} {
		dict incr state attempt
		dict lappend state messages [dict create role assistant content $text]
		dict lappend state messages [dict create role user content \
			"Your previous answer made claims the facts contradict: [join $problems {; }]. Rewrite it without those claims."]
		toolsStep $state
		return
	}

	set user ""
	foreach m [dict get $state messages] {
		if {[dict get $m role] eq "user"} { set user [dict get $m content]; break }
	}

	# the deterministic fact line the model was given, for "show your work"
	set facts ""
	catch { set facts [::scidb::ai::text [dict get $state fen]] }

	uplevel #0 [list {*}$script [dict create \
		ok 1 text $text claims $problems attempts [dict get $state rounds] \
		grounded [expr {[llength $problems] == 0}] \
		evidence [evidenceFromText $user] facts $facts]]
	return
}
