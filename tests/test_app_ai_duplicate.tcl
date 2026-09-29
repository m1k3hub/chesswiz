# ======================================================================
# Scidb App Test — duplicate-merge arbitration (tcl/ai-duplicate.tcl):
# the deterministic rule over the four identity facts, the System One
# classifier over the closed set {same different unsure}, and its
# fallback ('unsure' -- today's behaviour: candidates are found,
# nothing is merged).
# ======================================================================
# Modelled on tests/test_app_novelty.tcl, the closest existing app test
# of a System One module (the task named test_app_ai_comment.tcl, which
# does not exist in this tree). The classifier is stubbed in this
# process: ::ai::decide answers from a canned decision and records
# every call, and is renamed back after every test, so the next test
# files see the real command. The stub reads its state through fully
# qualified names (a renamed proc resolves variable relative to its
# current name, not the namespace it was defined in). The module is
# sourced when the app does not ship it yet.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::dup {}

# --- the two records of each scenario -----------------------------------

# One game entered twice: same four identity facts, spellings vary
# (case, whitespace, result spelling, move count as string).
proc ::scidb::test::dup::SamePair {} {
	return [dict create \
		1 [dict create white "Kasparov, Garry" black "Short, Nigel D." \
			date "1992.11.04" result "1-0" eco "B90" moves 40 event "London"] \
		2 [dict create white "KASPAROV,  GARRY" black "short, nigel   d." \
			date "1992.11.04" result "1:0" eco "B90" moves "40" event "London WC m"]]
}

# A different known result: the same game cannot have two results.
proc ::scidb::test::dup::ConflictingResult {} {
	set facts [::scidb::test::dup::SamePair]
	dict set facts 2 result "0-1"
	return $facts
}

# Clearly different players: different surnames.
proc ::scidb::test::dup::DifferentPlayers {} {
	set facts [::scidb::test::dup::SamePair]
	dict set facts 2 white "Karpov, Anatoly"
	return $facts
}

# Near-miss identity: "G." against "Gary" is not "different" -- the
# rule abstains and the classifier is asked.
proc ::scidb::test::dup::MixedNames {} {
	set facts [::scidb::test::dup::SamePair]
	dict set facts 2 white "Kasparov, Gary"
	return $facts
}

# Placeholder dates and a missing move count: the rule withholds.
proc ::scidb::test::dup::VaguePair {} {
	set facts [::scidb::test::dup::SamePair]
	dict set facts 1 date "????.??.??"
	dict set facts 2 date "??.??.??"
	dict unset facts 2 moves
	return $facts
}

# --- the module (sourced when the app does not ship it yet) -------------

if {[llength [info commands ::ai::duplicate::decide]] == 0} {
	source [file join [file dirname [file normalize [info script]]] .. tcl ai-duplicate.tcl]
}

# ::ai::decide's contract, reduced to what these tests need: the canned
# decision when it says ok, else the recorded -fallback prefix, else
# {ok 0}. Every call is recorded under Calls.
proc ::scidb::test::dup::Decide {feature state question script args} {
	upvar #0 ::scidb::test::dup::Calls calls
	upvar #0 ::scidb::test::dup::Decision decision

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
proc ::scidb::test::dup::stub {what} {
	variable SavedDecide {}

	set ::scidb::test::dup::Calls {}
	set ::scidb::test::dup::Decision $what

	if {[llength [info commands ::ai::decide]]} {
		set SavedDecide ::scidb::test::dup::savedDecide
		rename ::ai::decide $SavedDecide
	}
	rename ::scidb::test::dup::Decide ::ai::decide
	return
}

# The other app tests run in this process after this file: the real
# command goes back. Both the fully and the partly installed state undo.
proc ::scidb::test::dup::restore {} {
	variable SavedDecide

	if {$SavedDecide ne "" && [info commands $SavedDecide] ne ""} {
		rename ::ai::decide ::scidb::test::dup::Decide
		rename $SavedDecide ::ai::decide
		set SavedDecide {}
	} elseif {[llength [info commands ::scidb::test::dup::Decide]] == 0
	 && [llength [info commands ::ai::decide]] == 0} {
		rename ::scidb::test::dup::Decide ::ai::decide
		set SavedDecide {}
	}
	return
}

# The decision of decide's <script> arrives from after 0: pump the loop.
proc ::scidb::test::dup::wait {var} {
	set timer [after 5000 [list set $var timeout]]
	vwait $var
	after cancel $timer
	return [set $var]
}

# --- the rule: the four identity facts settle the obvious cases ---------

tcltest::test dup-rule-same {identical players, date, result and move count are the same game} -body {
	::ai::duplicate::rule [::scidb::test::dup::SamePair]
} -result {same}

tcltest::test dup-rule-different-result {two known results cannot be one game} -body {
	::ai::duplicate::rule [::scidb::test::dup::ConflictingResult]
} -result {different}

tcltest::test dup-rule-different-players {different surnames are two different games} -body {
	::ai::duplicate::rule [::scidb::test::dup::DifferentPlayers]
} -result {different}

tcltest::test dup-rule-abstains {near-miss names, placeholder facts and malformed input withhold} -body {
	list [::ai::duplicate::rule [::scidb::test::dup::MixedNames]] \
		[::ai::duplicate::rule [::scidb::test::dup::VaguePair]] \
		[::ai::duplicate::rule {}] \
		[::ai::duplicate::rule {not a dict}]
} -result {{} {} {} {}}

# --- the decide rule shortcut: the classifier is never asked ------------

tcltest::test dup-decide-rule-same {a rule 'same' is returned without asking the classifier} -setup {
	::scidb::test::dup::stub {ok 1 label different confidence 0.99 source classifier}
} -body {
	set ::scidb::test::dup::Result {}
	::ai::duplicate::decide [::scidb::test::dup::SamePair] {set ::scidb::test::dup::Result}
	set result [::scidb::test::dup::wait ::scidb::test::dup::Result]
	list [dict get $result label] [dict get $result source] [dict get $result confidence] \
		$::scidb::test::dup::Calls
} -cleanup {
	::scidb::test::dup::restore
} -result {same rules 1.0 {}}

# --- the classifier path: an unsettled pair asks over the three labels --

tcltest::test dup-decide-classifier {an unsettled pair goes to the classifier as a choice question} -setup {
	::scidb::test::dup::stub {ok 1 label same confidence 0.87 source classifier}
} -body {
	set facts [::scidb::test::dup::MixedNames]
	set ::scidb::test::dup::Result {}
	::ai::duplicate::decide $facts {set ::scidb::test::dup::Result}
	set result [::scidb::test::dup::wait ::scidb::test::dup::Result]
	set call [lindex $::scidb::test::dup::Calls 0]
	list [::ai::duplicate::rule $facts] [llength $::scidb::test::dup::Calls] \
		[dict get $call feature] \
		[dict get $call question type] [dict keys [dict get $call question criteria]] \
		[expr {[string first "2:white=kasparov, gary" [dict get $call state]] > 0}] \
		[dict get $result label] [dict get $result source] [dict get $result confidence]
} -cleanup {
	::scidb::test::dup::restore
} -result {{} 1 duplicate choice {same different unsure} 1 same classifier 0.87}

# --- the fallback: no classifier answer leaves 'unsure' -----------------

# The canned decision is {ok 0}, so the recorded -fallback prefix is the
# only thing that can decide: 'unsure' here comes out of
# ::ai::duplicate::Unsure through the real gate mechanics.
tcltest::test dup-decide-fallback {an unsettled pair falls back to 'unsure': nothing is merged} -setup {
	::scidb::test::dup::stub {ok 0}
} -body {
	set ::scidb::test::dup::Result {}
	::ai::duplicate::decide [::scidb::test::dup::VaguePair] {set ::scidb::test::dup::Result}
	set result [::scidb::test::dup::wait ::scidb::test::dup::Result]
	set call [lindex $::scidb::test::dup::Calls 0]
	list [dict get $result ok] [dict get $result label] [dict get $result confidence] \
		[dict get $result source] [lindex [dict get $call args] 0] \
		[lindex [lindex [dict get $call args] 1] end]
} -cleanup {
	::scidb::test::dup::restore
} -result {1 unsure {} rules -fallback Unsure}

# --- without ::ai::decide at all ----------------------------------------

tcltest::test dup-decide-no-decide {without a classifier command the answer is 'unsure'} -body {
	if {[llength [info commands ::ai::decide]]} {
		rename ::ai::decide ::scidb::test::dup::realDecide
	}
	set ::scidb::test::dup::Result {}
	::ai::duplicate::decide [::scidb::test::dup::MixedNames] {set ::scidb::test::dup::Result}
	set result [::scidb::test::dup::wait ::scidb::test::dup::Result]
	list [dict get $result label] [dict get $result source] [dict get $result confidence]
} -cleanup {
	if {[llength [info commands ::scidb::test::dup::realDecide]]} {
		rename ::scidb::test::dup::realDecide ::ai::decide
	}
} -result {unsure rules {}}

# --- labels -> phrases -----------------------------------------------------

tcltest::test dup-describe {labels have human phrases; unknown labels echo} -body {
	list [::ai::duplicate::describe same] [::ai::duplicate::describe different] \
		[::ai::duplicate::describe unsure] \
		[::ai::duplicate::describe zugzwang]
} -result {{the same game (a duplicate record)} {a different game} {undecided (the classifier did not settle the pair)} zugzwang}

::tcltest::cleanupTests
return