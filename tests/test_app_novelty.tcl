# ======================================================================
# Scidb App Test — move novelty (tcl/ai-novelty.tcl): the 'known' rule
# over the master-practice precedent index, the System One classifier
# over {novelty side_line transposition}, and its fallback.
# ======================================================================
# The classifier and the index are stubbed in this process:
# ::ai::decide answers from a canned decision and records every call,
# ::ai::precedent::lookup answers from a canned precedent. Both are
# renamed back after every test, so the next test files see the real
# commands. The stubs read their state through fully qualified names
# (a renamed proc resolves variable relative to its current name, not
# the namespace it was defined in). The module is sourced when the app
# does not ship it yet.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::nov {
	# the position the tests label a move in; the move is Nf3
	variable FEN {r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/2N2N2/PPPP1PPP/R1BQK2R w KQkq - 6 6}
	# what the precedent index answers (the real shape of ::ai::precedent::lookup)
	variable Precedent {games 41 sideToMove white moves {{move Nf3 share 48 scorePct 52}}}
}

# ::ai::novelty is usually in the built app; before the SOURCES line is
# applied (patches/ai-novelty-integration.md), source it from the tree.
if {[llength [info commands ::ai::novelty::label]] == 0} {
	source [file join [file dirname [file normalize [info script]]] .. tcl ai-novelty.tcl]
}

# ::ai::decide's contract, reduced to what these tests need: the canned
# decision when it says ok, else the recorded -fallback prefix, else
# {ok 0}. Every call is recorded under Calls.
proc ::scidb::test::nov::Decide {feature state question script args} {
	upvar #0 ::scidb::test::nov::Calls calls
	upvar #0 ::scidb::test::nov::Decision decision

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

# ::ai::precedent::lookup reduced the same way: the canned precedent for
# every position, {} when the index is meant to be unavailable.
proc ::scidb::test::nov::Lookup {fen args} {
	upvar #0 ::scidb::test::nov::Precedent precedent
	return $precedent
}

# Rename the real classifier and index aside and put the stubs in, for
# one test: <precedent> is the dict ::ai::precedent::lookup returns
# ("" leaves the position unknown), <what> is what ::ai::decide answers.
proc ::scidb::test::nov::stub {precedent what} {
	variable SavedDecide {}
	variable SavedLookup {}

	if {[llength [info commands ::scidb::test::nov::Decide]] == 0
	 || [llength [info commands ::scidb::test::nov::Lookup]] == 0} {
		error "the novelty stubs are already installed"
	}
	set ::scidb::test::nov::Calls {}
	set ::scidb::test::nov::Decision $what
	set ::scidb::test::nov::Precedent $precedent

	if {[llength [info commands ::ai::decide]]} {
		set SavedDecide ::scidb::test::nov::savedDecide
		rename ::ai::decide $SavedDecide
	}
	rename ::scidb::test::nov::Decide ::ai::decide

	if {[llength [info commands ::ai::precedent::lookup]]} {
		set SavedLookup ::scidb::test::nov::savedLookup
		rename ::ai::precedent::lookup $SavedLookup
	}
	rename ::scidb::test::nov::Lookup ::ai::precedent::lookup
	return
}

# The other app tests run in this process after this file: the real
# commands go back. Both the fully and the partly installed state undo.
proc ::scidb::test::nov::restore {} {
	variable SavedDecide
	variable SavedLookup

	if {$SavedDecide ne "" && [info commands $SavedDecide] ne ""} {
		rename ::ai::decide ::scidb::test::nov::Decide
		rename $SavedDecide ::ai::decide
		set SavedDecide {}
	} elseif {[llength [info commands ::scidb::test::nov::Decide]] == 0
	 && [llength [info commands ::ai::decide]]} {
		# no classifier ran before the stub went in (a naked interpreter)
		rename ::ai::decide ::scidb::test::nov::Decide
	}
	if {$SavedLookup ne "" && [info commands $SavedLookup] ne ""} {
		rename ::ai::precedent::lookup ::scidb::test::nov::Lookup
		rename $SavedLookup ::ai::precedent::lookup
		set SavedLookup {}
	} elseif {[llength [info commands ::scidb::test::nov::Lookup]] == 0
	 && [llength [info commands ::ai::precedent::lookup]]} {
		rename ::ai::precedent::lookup ::scidb::test::nov::Lookup
	}
	return
}

# The decision of label's <script> arrives from after 0: pump the loop.
proc ::scidb::test::nov::wait {var} {
	set timer [after 5000 [list set $var timeout]]
	vwait $var
	after cancel $timer
	return [set $var]
}

# --- the rules: a position in the index is known, whatever the classifier
#     would say, and the classifier is never called ------------------------

tcltest::test novelty-known-no-classifier {a position in the index is known; the classifier is not asked} -setup {
	::scidb::test::nov::stub $::scidb::test::nov::Precedent \
		[list ok 1 label transposition confidence 0.99 source classifier]
} -body {
	set ::scidb::test::nov::Result {}
	::ai::novelty::label $::scidb::test::nov::FEN Nf3 {set ::scidb::test::nov::Result}
	set result [::scidb::test::nov::wait ::scidb::test::nov::Result]
	list [::ai::novelty::known $::scidb::test::nov::FEN] [dict get $result label] \
		[dict get $result source] [dict get $result confidence] \
		[llength $::scidb::test::nov::Calls]
} -cleanup {
	::scidb::test::nov::restore
} -result {1 known rules 1.0 0}

# --- the classifier path: an unknown position asks over the four labels ---

tcltest::test novelty-label-classifier {an unknown position goes to the classifier as a choice question} -setup {
	::scidb::test::nov::stub {} [list ok 1 label side_line confidence 0.87 source classifier]
} -body {
	set ::scidb::test::nov::Result {}
	::ai::novelty::label $::scidb::test::nov::FEN Nf3 {set ::scidb::test::nov::Result}
	set result [::scidb::test::nov::wait ::scidb::test::nov::Result]
	set call [lindex $::scidb::test::nov::Calls 0]
	list [::ai::novelty::known $::scidb::test::nov::FEN] [llength $::scidb::test::nov::Calls] \
		[dict get $call feature] [dict get $call state] \
		[dict get $call question type] [dict keys [dict get $call question criteria]] \
		[dict get $result label] [dict get $result source] [dict get $result confidence]
} -cleanup {
	::scidb::test::nov::restore
} -result {0 1 novelty {fen=r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/2N2N2/PPPP1PPP/R1BQK2R w KQkq - 6 6 move=Nf3 known=0} choice {novelty side_line transposition} side_line classifier 0.87}

# --- the fallback: no classifier answer leaves 'unknown' ------------------

# The canned decision is {ok 0}, so the recorded -fallback prefix is the
# only thing that can decide: 'unknown' here comes out of
# ::ai::novelty::Unknown through the real gate mechanics.
tcltest::test novelty-label-fallback {an unsettled move falls back to 'unknown' from the rules} -setup {
	::scidb::test::nov::stub {} {ok 0}
} -body {
	set ::scidb::test::nov::Result {}
	::ai::novelty::label $::scidb::test::nov::FEN Nf3 {set ::scidb::test::nov::Result}
	set result [::scidb::test::nov::wait ::scidb::test::nov::Result]
	set call [lindex $::scidb::test::nov::Calls 0]
	list [dict get $result ok] [dict get $result label] [dict get $result confidence] \
		[dict get $result source] [lindex [dict get $call args] 0] \
		[lindex [lindex [dict get $call args] 1] end]
} -cleanup {
	::scidb::test::nov::restore
} -result {1 unknown {} rules -fallback Unknown}

# --- labels -> phrases -----------------------------------------------------

tcltest::test novelty-describe {labels have human phrases; unknown labels echo} -body {
	list [::ai::novelty::describe known] [::ai::novelty::describe novelty] \
		[::ai::novelty::describe side_line] [::ai::novelty::describe transposition] \
		[::ai::novelty::describe unknown] \
		[::ai::novelty::describe zugzwang]
} -result {{played by the masters (in the precedent index)} {a novelty: not a line the masters play} {a side line of known opening theory} {a transposition of well-known practice} {undecided (the classifier did not settle the move)} zugzwang}

::tcltest::cleanupTests
return
