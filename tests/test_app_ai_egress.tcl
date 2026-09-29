# ======================================================================
# Scidb App Test — cloud egress gate (tcl/ai-egress.tcl): the
# deterministic rule over what a prompt carries (a PGN movetext block
# with tags, a [%clk]/comment run, or a FEN plus a player name = private;
# a FEN/position facts alone = public; else abstain), the System One
# classifier over the closed set {private public}, and its answer
# mapping: hold for private, send for public -- and send when nothing
# decides, which is today's behaviour.
# ======================================================================
# Modelled on tests/test_app_ai_duplicate.tcl / test_app_novelty.tcl,
# the closest existing app tests of a System One module. The classifier
# is stubbed in this process: ::ai::decide answers from a canned
# decision and records every call, and is renamed back after every test,
# so the next test files see the real command. The stub reads its state
# through fully qualified names (a renamed proc resolves variables
# relative to its current name, not the namespace it was defined in).
# The module is sourced when the app does not ship it yet.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::egress {}

# --- the prompts of each scenario ---------------------------------------

# A game the user has open: PGN tags and movetext.
proc ::scidb::test::egress::Game {} {
	return "Annotate this game:\n\[White \"Kasparov, Garry\"\]\n\[Black \"Short, Nigel D.\"\]\n\[Result \"1-0\"\]\n1. e4 e5 2. Nf3 Nc6 3. Bb5"
}

# Movetext with a clock run: a game plus a private annotation.
proc ::scidb::test::egress::ClockRun {} {
	return "1. e4 e5 2. Nf3 \[%clk 0:05:00\] 2... Nc6 3. Bb5 \[%eval 0.35\]"
}

# A comment on a move, inside movetext.
proc ::scidb::test::egress::CommentRun {} {
	set LB "\x7b"
	set RB "\x7d"
	return "1. e4 e5 2. Nf3 ${LB}The only move, and a strong one.${RB} 2... Nc6"
}

# A bare position with no facts: the FEN alone.
proc ::scidb::test::egress::Fen {} {
	return "r1bqkbnr/pppppppp/2n5/8/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 1 2"
}

# The position prompt ::ai::prompt::position builds: a FEN and its facts.
proc ::scidb::test::egress::FactsPrompt {} {
	return "Audience: club player. Perspective: neutral.\nFACTS (JSON):\n{\"fen\":\"[::scidb::test::egress::Fen]\",\"phase\":\"opening\"}\nSections:\nSTRUCTURE: pawn structure, space, and weaknesses."
}

# The same position pinned to a person: private by association.
proc ::scidb::test::egress::FenWithPlayer {} {
	return "Does the position [::scidb::test::egress::Fen] belong to Kasparov, Garry?"
}

# --- the module (sourced when the app does not ship it yet) -------------

if {[llength [info commands ::ai::egress::decide]] == 0} {
	source [file join [file dirname [file normalize [info script]]] .. tcl ai-egress.tcl]
}

# ::ai::decide's contract, reduced to what these tests need: the canned
# decision when it says ok, else the recorded -fallback prefix, else
# {ok 0}. Every call is recorded under Calls.
proc ::scidb::test::egress::Decide {feature state question script args} {
	upvar #0 ::scidb::test::egress::Calls calls
	upvar #0 ::scidb::test::egress::Decision decision

	lappend calls [dict create feature $feature state $state question $question args $args]
	array set opts {-fallback {} -threshold 0.6}
	array set opts $args
	if {[dict get $decision ok]} {
		set d $decision
	} elseif {[llength $opts(-fallback)]} {
		set d [list ok 1 label [uplevel #0 $opts(-fallback)] confidence {} source rules]
	} else {
		set d [list ok 0]
	}
	after 0 [list {*}$script $d]
	return
}

# ::ai::decide with a canned decision for one test: <what> is what
# ::ai::decide answers ({ok 0} makes the recorded -fallback decide).
proc ::scidb::test::egress::stub {what} {
	variable SavedDecide {}

	set ::scidb::test::egress::Calls {}
	set ::scidb::test::egress::Decision $what

	if {[llength [info commands ::ai::decide]]} {
		set SavedDecide ::scidb::test::egress::savedDecide
		rename ::ai::decide $SavedDecide
	}
	rename ::scidb::test::egress::Decide ::ai::decide
	return
}

# The other app tests run in this process after this file: the real
# command goes back. Both states undo: with a real ::ai::decide saved
# aside, and with no classifier in the process at all (the stub then
# sits at ::ai::decide, and only the stub may be taken away).
proc ::scidb::test::egress::restore {} {
	variable SavedDecide

	if {$SavedDecide ne "" && [info commands $SavedDecide] ne ""} {
		if {[llength [info commands ::scidb::test::egress::Decide]] == 0
		 && [llength [info commands ::ai::decide]]} {
			rename ::ai::decide ::scidb::test::egress::Decide
		}
		rename $SavedDecide ::ai::decide
		set SavedDecide {}
	} elseif {[llength [info commands ::scidb::test::egress::Decide]] == 0
	 && [llength [info commands ::ai::decide]]} {
		rename ::ai::decide ::scidb::test::egress::Decide
		set SavedDecide {}
	}
	return
}

# The decision of decide's <script> arrives from after 0: pump the loop.
proc ::scidb::test::egress::wait {var} {
	set timer [after 5000 [list set $var timeout]]
	vwait $var
	after cancel $timer
	return [set $var]
}

# One decide run through the stub: the answer dict as a short list.
proc ::scidb::test::egress::Run {prompt} {
	set ::scidb::test::egress::Result {}
	::ai::egress::decide $prompt {set ::scidb::test::egress::Result}
	set result [::scidb::test::egress::wait ::scidb::test::egress::Result]
	return [list [dict get $result label] [dict get $result source] \
		[dict get $result confidence]]
}

# --- the rule: what the prompt carries settles the obvious cases --------

tcltest::test egress-rule-private-games {tags, clocks and comments on a game are private} -body {
	list [::ai::egress::rule [::scidb::test::egress::Game]] \
		[::ai::egress::rule [::scidb::test::egress::ClockRun]] \
		[::ai::egress::rule [::scidb::test::egress::CommentRun]]
} -result {private private private}

tcltest::test egress-rule-private-player {a position pinned to a player name is private} -body {
	::ai::egress::rule [::scidb::test::egress::FenWithPlayer]
} -result {private}

tcltest::test egress-rule-public {a FEN alone, or a FEN with its facts, is public} -body {
	list [::ai::egress::rule [::scidb::test::egress::Fen]] \
		[::ai::egress::rule [::scidb::test::egress::FactsPrompt]] \
		[::ai::egress::rule "Position [::scidb::test::egress::Fen] white to move"] \
		[::ai::egress::rule "[::scidb::test::egress::Fen]  (white to move)\nmaterial   white Q1 R2 B2 N2 P8   black Q1 R2 B2 N2 P8   balance +0cp"]
} -result {public public public public}

# A bare movetext run is a game the rule cannot prove: abstain, like
# empty input, a JSON facts object (its runs quote their keys) and a
# numbered instruction that is not chess notation. The classifier is
# asked; only a prompt that names private data is held.
tcltest::test egress-rule-abstains {unproven prompts, malformed input and junk withhold} -body {
	set LB "\x7b"
	set RB "\x7d"
	list [::ai::egress::rule "1. e4 e5 2. Nf3 Nc6"] \
		[::ai::egress::rule "What is the best move in this position?"] \
		[::ai::egress::rule ""] \
		[::ai::egress::rule "   "] \
		[::ai::egress::rule "1. Read the rules 2. Answer the question"] \
		[::ai::egress::rule "${LB}\"material\":${LB}\"white\":${LB}\"pawns\":8${RB}${RB}${RB}"] \
		[::ai::egress::rule "a comment on nothing"]
} -result {{} {} {} {} {} {} {}}

# --- the question: the closed set the classifier answers over -----------

tcltest::test egress-question {the classifier is asked a choice question over private and public} -body {
	set q [::ai::egress::Question]
	list [dict get $q type] [dict keys [dict get $q criteria]] \
		[expr {[string first "private" [dict get $q instructions]] >= 0}]
} -result {choice {private public} 1}

# --- the rule shortcut: the classifier is never asked ------------------

tcltest::test egress-decide-rule-private {a rule 'private' holds the prompt without asking the classifier} -setup {
	::scidb::test::egress::stub {ok 1 label public confidence 0.99 source classifier}
} -body {
	list [::scidb::test::egress::Run [::scidb::test::egress::Game]] \
		$::scidb::test::egress::Calls
} -cleanup {
	::scidb::test::egress::restore
} -result {{hold rules 1.0} {}}

tcltest::test egress-decide-rule-public {a rule 'public' sends the prompt without asking the classifier} -setup {
	::scidb::test::egress::stub {ok 1 label private confidence 0.99 source classifier}
} -body {
	list [::scidb::test::egress::Run [::scidb::test::egress::FactsPrompt]] \
		$::scidb::test::egress::Calls
} -cleanup {
	::scidb::test::egress::restore
} -result {{send rules 1.0} {}}

# --- the classifier path: an unsettled prompt asks over the two labels --

# private -> hold: the prompt is held for the user, nothing is sent.
tcltest::test egress-decide-classifier-private {an unsettled prompt goes to the classifier; 'private' holds it} -setup {
	::scidb::test::egress::stub {ok 1 label private confidence 0.87 source classifier}
} -body {
	set prompt "1. e4 e5 2. Nf3 Nc6"
	set answer [::scidb::test::egress::Run $prompt]
	set call [lindex $::scidb::test::egress::Calls 0]
	list [::ai::egress::rule $prompt] [llength $::scidb::test::egress::Calls] \
		[dict get $call feature] [expr {[dict get $call state] eq $prompt}] \
		[dict get $call question type] [dict keys [dict get $call question criteria]] \
		$answer
} -cleanup {
	::scidb::test::egress::restore
} -result {{} 1 egress 1 choice {private public} {hold classifier 0.87}}

# public -> send: the classifier's 'public' is an answer, not a hold.
tcltest::test egress-decide-classifier-public {an unsettled prompt answered 'public' is sent} -setup {
	::scidb::test::egress::stub {ok 1 label public confidence 0.72 source classifier}
} -body {
	::scidb::test::egress::Run "What is the best move in this position?"
} -cleanup {
	::scidb::test::egress::restore
} -result {send classifier 0.72}

# --- the fallback: nothing decided leaves today's behaviour ------------

# The canned decision is {ok 0}, so the recorded -fallback prefix is the
# only thing that can decide: 'send' here comes out of ::ai::egress::Send
# through the real gate mechanics. A gate must not hold a request on its
# own uncertainty.
tcltest::test egress-decide-fallback {an undecided prompt is sent, as before} -setup {
	::scidb::test::egress::stub {ok 0}
} -body {
	set answer [::scidb::test::egress::Run "1. e4 e5 2. Nf3 Nc6"]
	set call [lindex $::scidb::test::egress::Calls 0]
	list $answer [dict get $call feature] \
		[lindex [dict get $call args] 0] [lindex [lindex [dict get $call args] 1] end]
} -cleanup {
	::scidb::test::egress::restore
} -result {{send rules {}} egress -fallback Send}

# --- without ::ai::decide at all ----------------------------------------

tcltest::test egress-decide-no-decide {without a classifier command an unsettled prompt is sent} -body {
	if {[llength [info commands ::ai::decide]]} {
		rename ::ai::decide ::scidb::test::egress::realDecide
	}
	set answer [::scidb::test::egress::Run "1. e4 e5 2. Nf3 Nc6"]
	list $answer [::ai::egress::rule [::scidb::test::egress::Game]]
} -cleanup {
	if {[llength [info commands ::scidb::test::egress::realDecide]]} {
		rename ::scidb::test::egress::realDecide ::ai::decide
	}
} -result {{send rules {}} private}

# --- labels -> phrases --------------------------------------------------

tcltest::test egress-describe {labels have human phrases; unknown labels echo} -body {
	list [::ai::egress::describe private] [::ai::egress::describe public] \
		[::ai::egress::describe send] [::ai::egress::describe hold] \
		[::ai::egress::describe zugzwang]
} -match glob -result {{private*} {public*} {send*} {hold*} zugzwang}

::tcltest::cleanupTests
return
