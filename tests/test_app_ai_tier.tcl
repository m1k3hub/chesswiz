# ======================================================================
# Scidb App Test — LLM tier routing (tcl/ai-tier.tcl): the deterministic
# rule (a short read-only request is local; a long request or long-form
# prose is cloud), the System One classifier over the closed set
# {local cloud}, and its fallback ('configured' -- today's behaviour:
# the configured provider serves the request, nothing is switched).
# ======================================================================
# Modelled on tests/test_app_ai_duplicate.tcl, the closest existing app
# test of a System One module. The classifier is stubbed in this
# process: ::ai::decide answers from a canned decision and records
# every call, and is renamed back after every test, so the other test
# files see the real command. The stub reads its state through fully
# qualified variable names (a renamed proc resolves variables relative
# to its current name, not the namespace it was defined in); recorded
# calls are variables, not commands. The module is sourced when the
# app does not ship it yet.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::tier {}

# --- the requests and tool sets of each scenario -------------------------

# A short request over read-only tools: the local model's job.
proc ::scidb::test::tier::ShortAsk {} {
	return "summarize the database for me"
}
proc ::scidb::test::tier::ReadOnlyTools {} {
	return {current_game tool_log list_open_databases}
}

# A request at or over the long bound (2000 chars) is cloud whatever
# the tools say; a request past the short bound (400) but under the
# long one says nothing.
proc ::scidb::test::tier::LongAsk {} {
	return [string repeat "explain this opening line " 100]
}
proc ::scidb::test::tier::MediumAsk {} {
	set s "list the games where the queenside majority meets a minority attack"
	while {[string length $s] < 500} { append s " and list the scorers of those games" }
	return $s
}

# Long-form prose asks: short requests whose answers are not short.
proc ::scidb::test::tier::ProseAsk {} {
	return "write an article about the Najdorf for our club newsletter"
}
proc ::scidb::test::tier::ProseAsk2 {} {
	return "a detailed step by step tutorial on tablebases"
}

# --- the module (sourced when the app does not ship it yet) -------------

if {[llength [info commands ::ai::tier::rule]] == 0} {
	source [file join [file dirname [file normalize [info script]]] .. tcl ai-tier.tcl]
}

# ::ai::decide's contract, reduced to what these tests need: the canned
# decision when it says ok, else the recorded -fallback prefix, else
# {ok 0}. Every call is recorded under Calls.
proc ::scidb::test::tier::Decide {feature state question script args} {
	upvar #0 ::scidb::test::tier::Calls calls
	upvar #0 ::scidb::test::tier::Decision decision

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
proc ::scidb::test::tier::stub {what} {
	variable SavedDecide {}

	set ::scidb::test::tier::Calls {}
	set ::scidb::test::tier::Decision $what

	if {[llength [info commands ::ai::decide]]} {
		set SavedDecide ::scidb::test::tier::savedDecide
		rename ::ai::decide $SavedDecide
	}
	rename ::scidb::test::tier::Decide ::ai::decide
	return
}

# The other app tests run in this process after this file: the real
# command goes back. Both the fully and the partly installed state undo.
proc ::scidb::test::tier::restore {} {
	variable SavedDecide

	if {$SavedDecide ne "" && [info commands $SavedDecide] ne ""} {
		rename ::ai::decide ::scidb::test::tier::Decide
		rename $SavedDecide ::ai::decide
		set SavedDecide {}
	} elseif {[llength [info commands ::scidb::test::tier::Decide]] == 0
	 && [llength [info commands ::ai::decide]] == 0} {
		rename ::scidb::test::tier::Decide ::ai::decide
		set SavedDecide {}
	}
	return
}

# The decision of decide's <script> arrives from after 0: pump the loop.
proc ::scidb::test::tier::wait {var} {
	set timer [after 5000 [list set $var timeout]]
	vwait $var
	after cancel $timer
	return [set $var]
}

# --- the rule: the obvious tiers without any model call -----------------

tcltest::test tier-rule-local {a short request over read-only tools is local} -body {
	list [::ai::tier::rule [::scidb::test::tier::ShortAsk] [::scidb::test::tier::ReadOnlyTools]] \
		[::ai::tier::rule [::scidb::test::tier::ShortAsk] current_game] \
		[::ai::tier::rule [::scidb::test::tier::ShortAsk] [list {name tool_log} {name classifier_status}]]
} -result {local local local}

tcltest::test tier-rule-cloud-long {a request at or over the long bound is cloud} -body {
	list [::ai::tier::rule [::scidb::test::tier::LongAsk] [::scidb::test::tier::ReadOnlyTools]] \
		[::ai::tier::rule [string repeat x 2000]] \
		[::ai::tier::rule [string repeat x 1999] [::scidb::test::tier::ReadOnlyTools]]
} -result {cloud cloud {}}

tcltest::test tier-rule-cloud-prose {long-form prose asks are cloud at any length} -body {
	list [::ai::tier::rule [::scidb::test::tier::ProseAsk]] \
		[::ai::tier::rule [::scidb::test::tier::ProseAsk2] [::scidb::test::tier::ReadOnlyTools]]
} -result {cloud cloud}

tcltest::test tier-rule-abstains {writing or unknown tools, missing tools, medium length and empty requests withhold} -body {
	list [::ai::tier::rule [::scidb::test::tier::ShortAsk] {start_engine annotate_game}] \
		[::ai::tier::rule [::scidb::test::tier::ShortAsk] {current_game export_database}] \
		[::ai::tier::rule [::scidb::test::tier::ShortAsk]] \
		[::ai::tier::rule [::scidb::test::tier::MediumAsk] [::scidb::test::tier::ReadOnlyTools]] \
		[::ai::tier::rule "" [::scidb::test::tier::ReadOnlyTools]] \
		[::ai::tier::rule [::scidb::test::tier::ShortAsk] "not a good tool"]
} -result {{} {} {} {} {} {}}

tcltest::test tier-rule-bounds-env {SCIDB_AI_TIER_LONG_CHARS and _SHORT_CHARS move the bounds} -setup {
	set savedLong [expr {[info exists ::env(SCIDB_AI_TIER_LONG_CHARS)] ? $::env(SCIDB_AI_TIER_LONG_CHARS) : ""}]
	set savedShort [expr {[info exists ::env(SCIDB_AI_TIER_SHORT_CHARS)] ? $::env(SCIDB_AI_TIER_SHORT_CHARS) : ""}]
	set ::env(SCIDB_AI_TIER_SHORT_CHARS) 10
	set ::env(SCIDB_AI_TIER_LONG_CHARS) 20
} -body {
	list [::ai::tier::rule "summarize the db" [::scidb::test::tier::ReadOnlyTools]] \
		[::ai::tier::rule [string repeat x 20]] \
		[::ai::tier::rule [string range [::scidb::test::tier::ShortAsk] 0 8] [::scidb::test::tier::ReadOnlyTools]]
} -cleanup {
	if {$savedLong eq ""} { unset -nocomplain ::env(SCIDB_AI_TIER_LONG_CHARS) } else { set ::env(SCIDB_AI_TIER_LONG_CHARS) $savedLong }
	if {$savedShort eq ""} { unset -nocomplain ::env(SCIDB_AI_TIER_SHORT_CHARS) } else { set ::env(SCIDB_AI_TIER_SHORT_CHARS) $savedShort }
} -result {{} cloud local}

tcltest::test tier-question {the classifier question is a choice over {local cloud}} -body {
	set q [::ai::tier::Question]
	list [dict get $q type] [dict keys [dict get $q criteria]]
} -result {choice {local cloud}}

# --- the decide rule shortcut: the classifier is never asked ------------

tcltest::test tier-decide-rule {a rule verdict is returned without asking the classifier} -setup {
	::scidb::test::tier::stub {ok 1 label cloud confidence 0.99 source classifier}
} -body {
	set ::scidb::test::tier::Result {}
	::ai::tier::decide [::scidb::test::tier::ShortAsk] [::scidb::test::tier::ReadOnlyTools] {set ::scidb::test::tier::Result}
	set result [::scidb::test::tier::wait ::scidb::test::tier::Result]
	list [dict get $result ok] [dict get $result label] [dict get $result source] \
		[dict get $result confidence] $::scidb::test::tier::Calls
} -cleanup {
	::scidb::test::tier::restore
} -result {1 local rules 1.0 {}}

# --- the classifier path: an undecided request asks {local cloud} -------

tcltest::test tier-decide-classifier {an undecided request goes to the classifier as a choice question} -setup {
	::scidb::test::tier::stub {ok 1 label cloud confidence 0.82 source classifier}
} -body {
	set ask [::scidb::test::tier::MediumAsk]
	set ::scidb::test::tier::Result {}
	::ai::tier::decide $ask {current_game player_stats} {set ::scidb::test::tier::Result}
	set result [::scidb::test::tier::wait ::scidb::test::tier::Result]
	set call [lindex $::scidb::test::tier::Calls 0]
	list [::ai::tier::rule $ask {current_game}] [llength $::scidb::test::tier::Calls] \
		[dict get $call feature] \
		[dict get $call question type] [dict keys [dict get $call question criteria]] \
		[regexp {^chars=\d+ tools=current_game player_stats$} [dict get $call state]] \
		[dict get $result label] [dict get $result source] [dict get $result confidence]
} -cleanup {
	::scidb::test::tier::restore
} -result {{} 1 tier choice {local cloud} 1 cloud classifier 0.82}

# --- the fallback: no classifier answer leaves 'configured' -------------

# The canned decision is {ok 0}, so the recorded -fallback prefix is
# the only thing that can decide: 'configured' here comes out of
# ::ai::tier::Configured through the real gate mechanics.
tcltest::test tier-decide-fallback {an unsettled request falls back to 'configured': nothing is switched} -setup {
	::scidb::test::tier::stub {ok 0}
} -body {
	set ::scidb::test::tier::Result {}
	::ai::tier::decide [::scidb::test::tier::MediumAsk] {current_game} {set ::scidb::test::tier::Result}
	set result [::scidb::test::tier::wait ::scidb::test::tier::Result]
	set call [lindex $::scidb::test::tier::Calls 0]
	list [dict get $result ok] [dict get $result label] [dict get $result confidence] \
		[dict get $result source] [lindex [dict get $call args] 0] \
		[lindex [lindex [dict get $call args] 1] end]
} -cleanup {
	::scidb::test::tier::restore
} -result {1 configured {} rules -fallback Configured}

# --- without ::ai::decide at all ----------------------------------------

tcltest::test tier-decide-no-decide {without a classifier command the answer is 'configured'} -body {
	if {[llength [info commands ::ai::decide]]} {
		rename ::ai::decide ::scidb::test::tier::realDecide
	}
	set ::scidb::test::tier::Result {}
	::ai::tier::decide [::scidb::test::tier::MediumAsk] {current_game} {set ::scidb::test::tier::Result}
	set result [::scidb::test::tier::wait ::scidb::test::tier::Result]
	list [dict get $result label] [dict get $result source] [dict get $result confidence]
} -cleanup {
	if {[llength [info commands ::scidb::test::tier::realDecide]]} {
		rename ::scidb::test::tier::realDecide ::ai::decide
	}
} -result {configured rules {}}

# --- labels -> phrases --------------------------------------------------

tcltest::test tier-describe {labels have human phrases; unknown labels echo} -body {
	list [::ai::tier::describe local] [::ai::tier::describe cloud] \
		[::ai::tier::describe configured] \
		[::ai::tier::describe zugzwang]
} -result {{the local model} {the cloud model} {undecided: the configured provider serves the request, nothing is switched} zugzwang}

::tcltest::cleanupTests
return
