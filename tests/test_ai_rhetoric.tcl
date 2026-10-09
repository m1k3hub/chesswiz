# ======================================================================
# test_ai_rhetoric.tcl -- the advisory rhetoric/coverage second opinion.
#
#   xvfb-run -a ./src/tkchesswiz tests/test_ai_rhetoric.tcl
#
# The System One classifier is stubbed in-process: ::ai::systemone::evaluateAsync
# is replaced with a proc that answers from a queue. No network, no model.
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

set root [file join [file dirname [file normalize [info script]]] ..]
source [file join $root tcl ai-systemone.tcl]
source [file join $root tcl ai-rhetoric.tcl]

# ---- stub the classifier ------------------------------------------------

rename ::ai::systemone::evaluateAsync ::ai::systemone::_realEvaluateAsync

set ::rhetoricReply {}

proc ::ai::systemone::evaluateAsync {state questions script} {
	set ::rhetoricReply [lassign $::rhetoricReply first]
	if {![llength $::rhetoricReply]} { set ::rhetoricReply [list $first] }
	uplevel #0 [list {*}$script $first]
}

# ::ai::systemone::enabled is checked by ::ai::rhetoric::check; point it at
# the stub (no server is configured in this shell)
proc ::ai::systemone::enabled {} { return 1 }

# One /v1/systemone reply carrying both answers (the client asks both
# questions in a single request).
proc answer {rLabel rConf cLabel cConf} {
	set answers [dict create \
		rhetoric [dict create type choice choice $rLabel confidence $rConf \
			probabilities [dict create $rLabel $rConf]] \
		coverage [dict create type choice choice $cLabel confidence $cConf \
			probabilities [dict create $cLabel $cConf]]]
	return [dict create ok 1 answers $answers]
}

proc sync {task text} {
	# run ::ai::rhetoric::check and wait for the callback (the disabled path
	# fires via `after 0`, the stub path synchronously)
	set ::rhetoricScript ""
	set ::rhetoricDone 0
	::ai::rhetoric::check $task $text {apply {{r} {
		set ::rhetoricScript $r
		set ::rhetoricDone 1
	}}}
	while {!$::rhetoricDone} {
		after 5
		update
	}
	return $::rhetoricScript
}

proc noticesOf {r} {
	return [expr {[dict exists $r notices] ? [dict get $r notices] : {}}]
}

# ---- tests --------------------------------------------------------------

# 1. no classifier configured: ok 0
proc ::ai::systemone::enabled {} { return 0 }
set r [sync "Explain the position." "White stands better."]
check "disabled: ok 0" [expr {[dict get $r ok] == 0}]
proc ::ai::systemone::enabled {} { return 1 }

# 2. clean prose, confident ordinary + addresses_request: no notices
set ::rhetoricReply [list [answer ordinary 0.95 addresses_request 0.93]]
set r [sync "Explain the position." "White has an isolated pawn and better piece activity."]
check "clean: no notices" [expr {[dict get $r ok] == 1 && [llength [noticesOf $r]] == 0}]

# 3. rhetoric hit (emphatic, high confidence): one notice
set ::rhetoricReply [list [answer emphatic_certainty 0.91 addresses_request 0.90]]
set r [sync "Explain the move Nf3." "This is an absolutely brilliant, game-deciding move!"]
check "rhetoric hit: one notice" [expr {
	[dict get $r ok] == 1 && [llength [noticesOf $r]] == 1 &&
	[string match "*certainty*" [lindex [noticesOf $r] 0]]}]

# 4. coverage miss (generic_nonanswer, high confidence): one notice
set ::rhetoricReply [list [answer ordinary 0.88 generic_nonanswer 0.87]]
set r [sync "Explain the comment." "Chess is a game of strategy and tactics."]
check "coverage miss: one notice" [expr {
	[dict get $r ok] == 1 && [llength [noticesOf $r]] == 1 &&
	[string match "*address*" [lindex [noticesOf $r] 0]]}]

# 5. both hit: two notices
set ::rhetoricReply [list [answer promotional_hype 0.85 refusal_or_deferral 0.82]]
set r [sync "Explain the game." "The greatest game ever played! I will analyze it later."]
check "both hit: two notices" [expr {[dict get $r ok] == 1 && [llength [noticesOf $r]] == 2}]

# 6. low confidence: no notices (below the default thresholds 0.6 / 0.7)
set ::rhetoricReply [list [answer emphatic_certainty 0.55 generic_nonanswer 0.65]]
set r [sync "Explain the position." "This is clearly winning."]
check "low confidence: no notices" [expr {[dict get $r ok] == 1 && [llength [noticesOf $r]] == 0}]

# 7. malformed reply (no answers): no notices, ok 1 with empty notices
set ::rhetoricReply [list [dict create ok 1 answers [dict create]]]
set r [sync "Explain the position." "White is better."]
check "malformed: abstains" [expr {[dict get $r ok] == 1 && [llength [noticesOf $r]] == 0}]

# 8. classifier error: ok 0
set ::rhetoricReply [list [dict create ok 0 error "connection refused"]]
set r [sync "Explain the position." "White is better."]
check "error: ok 0" [expr {[dict get $r ok] == 0}]

puts "AI-RHETORIC-FAILURES: $failures"
exit $failures