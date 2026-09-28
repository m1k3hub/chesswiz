# ======================================================================
# Scidb App Test — auto-annotation (tcl/ai-annotate.tcl)
# ======================================================================
# The engine, the game access and the drafting pipeline are all stubbed:
# what is under test is the division of labour — the gate, the marks, the
# wording, the writing, and the refusal to write ungrounded prose.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::annotate {
	variable Saved {}
	variable Seq 0
	variable Plys {}
	variable Written {}
	variable Marks {}
	variable Classifications {}
	variable Info {}
	variable Draft
}

# Replace <name> with <body> ({args} {script}), remembering what was there.
# The previous scheme (rename, then rename back) silently failed when a second
# test replaced the same command, which left stubs installed for the tests that
# ran after this file -- the triage suite then never got its provider back.
proc ::scidb::test::annotate::stub {name body} {
	variable Saved

	if {[llength [info commands $name]]} {
		set real "$name.__saved[incr ::scidb::test::annotate::Seq]"
		rename $name $real
		lappend Saved [list $name $real]
	}
	proc $name {*}$body
	return
}


proc ::scidb::test::annotate::restoreAll {} {
	variable Saved

	foreach pair [lreverse $Saved] {
		lassign $pair name real
		catch { rename $name {} }
		catch { rename $real $name }
	}
	set Saved {}
	return
}


proc ::scidb::test::annotate::wait {cond ms} {
	set n 0
	while {![uplevel #1 [list expr $cond]] && $n < $ms} { update ; after 10 ; incr n }
	return [uplevel #1 [list expr $cond]]
}

# <plys> is a list of {key san fen}; <classes> a dict san -> classification.
proc ::scidb::test::annotate::isolated {plys classes body} {
	variable Plys $plys
	variable Classifications $classes
	variable Written {}
	variable Marks {}
	variable Info {}
	variable Draft

	set settings [array get ::ai::annotate::Settings]
	set priv [array get ::ai::annotate::Priv]

	# engine: available, and scripted per move
	stub ::ai::engine::available {{} {return 1}}
	stub ::ai::engine::classify {{fen san args} {
		set c [expr {[dict exists $::scidb::test::annotate::Classifications $san]
			? [dict get $::scidb::test::annotate::Classifications $san] : "Good"}]
		set onlyMove [expr {$c eq "Best" && [string match {*Nf3*} $san]}]
		return [dict create san $san uci "x" bestMove "Nf3" classification $c \
			cpLoss [expr {$c eq "Blunder" ? 350 : ($c eq "Mistake" ? 150 : 10)}] \
			winPercentLoss 20 onlyMove $onlyMove evalBeforeCp 20 evalAfterCp -10 depth 12]
	}}

	# the game: mainline, navigation, comment and mark paths
	stub ::scidb::game::query {{args} {
		if {[lindex $args end] eq "mainline"} { return $::scidb::test::annotate::Plys }
		if {[lindex $args end-1] eq "marks"} { return {$1} }
		return ""
	}}
	stub ::scidb::game::update {{what key args} {
		if {$what eq "addcomment"} {
			lappend ::scidb::test::annotate::Written [list $key [lindex $args 0] [lindex $args 1]]
		} elseif {$what eq "annotation"} {
			lappend ::scidb::test::annotate::Marks [list $key [lindex $args 0]]
		}
		return
	}}
	stub ::scidb::game::go {{args} {return}}
	stub ::scidb::game::position {{args} {return "m-0.1"}}
	stub ::dialog::info {{args} {lappend ::scidb::test::annotate::Info $args ; return}}
	stub ::ai::provider::configure {{args} {return}}

	# the drafting pipeline, when the test provides one
	if {[info exists Draft(script)]} {
		stub ::ai::provider::completeAsync {{prompt script args} {
			uplevel #0 [list {*}$script $::scidb::test::annotate::Draft(script)]
		}}
		stub ::ai::claims::check {{fen text} {
			return [expr {[info exists ::scidb::test::annotate::Draft(claims)]
				? $::scidb::test::annotate::Draft(claims) : {}}]
		}}
	}

	set rc [catch { uplevel 1 $body } result]

	restoreAll
	array set ::ai::annotate::Settings $settings
	array set ::ai::annotate::Priv $priv
	if {$rc} { return -code error $result }
	return $result
}

proc ::scidb::test::annotate::plys {} {
	return [list \
		[list m-0.1 e4  {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}] \
		[list m-0.2 e5  {rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1}] \
		[list m-0.3 Nf3 {rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2}] \
		[list m-0.4 Nc6 {rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2}] \
		[list m-0.5 Bc4 {r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 1 3}] \
		[list m-0.6 Bc5 {r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 1 3}]] \
}

# ----------------------------------------------------------------------

tcltest::test annotate-worth {the gate follows the engine's verdict} -body {
	list [::ai::annotate::worth Blunder] [::ai::annotate::worth Mistake] \
		[::ai::annotate::worth Inaccuracy] [::ai::annotate::worth Best 1] \
		[::ai::annotate::worth Best 0] [::ai::annotate::worth Excellent] \
		[::ai::annotate::worth Good]
} -result {1 1 1 1 0 0 0}

tcltest::test annotate-marks {each verdict maps to its standard mark} -body {
	list [::ai::annotate::nagFor Blunder] [::ai::annotate::nagFor Mistake] \
		[::ai::annotate::nagFor Inaccuracy] [::ai::annotate::nagFor Best]
} -result {{$4} {$2} {$6} {}}

tcltest::test annotate-merge-marks {marks already on the move are kept} -body {
	list [::ai::annotate::extractNags {$1 $14}] \
		[::ai::annotate::mergeNags {$1} {$4}] \
		[::ai::annotate::mergeNags {} {$4}] \
		[::ai::annotate::mergeNags {$4} {$4}]
} -result {{{$1} {$14}} {$1 $4} {$4} {$4}}

tcltest::test annotate-plain-comment {the engine's verdict, in words, without a model} -body {
	::ai::annotate::plainComment Nf6 Blunder \
		[dict create classification Blunder cpLoss 350 bestMove Nf3 uci Nf6]
} -result {Blunder; loses about 3.5 pawns; best was Nf3.}

tcltest::test annotate-prompt {the instruction carries the verdict the model may not contradict} -body {
	set text [::ai::annotate::prompt Nf6 Blunder \
		[dict create classification Blunder cpLoss 350 bestMove Nf3 uci Nf6 fen x]]
	list [string match {*Nf6*} $text] [string match {*Blunder*} $text] \
		[string match {*best was Nf3*} $text] [string match {*must not contradict*} $text]
} -result {1 1 1 1}

tcltest::test annotate-run-writes {only the gated moves get a comment, in order} -body {
	set classes [dict create e4 Good e5 Excellent Nf3 Best Nc6 Blunder Bc4 Inaccuracy Bc5 Good]
	::scidb::test::annotate::isolated [::scidb::test::annotate::plys] $classes {
		::ai::annotate::configure -prose 0 -marks 0 -maxPlies 60
		::ai::annotate::annotate .application
		::scidb::test::annotate::wait {![::ai::annotate::running?]} 400
		list [lmap w $::scidb::test::annotate::Written { lindex $w 0 }] \
			[llength $::scidb::test::annotate::Written] \
			[lmap w $::scidb::test::annotate::Written { lindex $w 1 }] \
			$::scidb::test::annotate::Marks
	}
} -result {{m-0.3 m-0.4 m-0.5} 3 {after after after} {}}

tcltest::test annotate-marks-merged {with marks on, the existing mark survives} -body {
	set classes [dict create Nc6 Blunder]
	::scidb::test::annotate::isolated [::scidb::test::annotate::plys] $classes {
		::ai::annotate::configure -prose 0 -marks 1
		::ai::annotate::annotate .application
		::scidb::test::annotate::wait {![::ai::annotate::running?]} 400
		list $::scidb::test::annotate::Marks
	}
} -result {{{m-0.4 {$1 $4}}}}

tcltest::test annotate-cap {maxPlies bounds the work} -body {
	set classes [dict create e5 Blunder Bc5 Blunder]
	::scidb::test::annotate::isolated [::scidb::test::annotate::plys] $classes {
		::ai::annotate::configure -prose 0
		::ai::annotate::annotate .application -maxPlies 2
		::scidb::test::annotate::wait {![::ai::annotate::running?]} 400
		list [llength $::scidb::test::annotate::Written] $::ai::annotate::Priv(index)
	}
} -result {1 2}

tcltest::test annotate-prose-grounded {grounded prose is written} -setup {
	set ::scidb::test::annotate::Draft(script) [list ok 1 text "Nc6 allows a fork."]
	set ::scidb::test::annotate::Draft(claims) {}
} -body {
	set classes [dict create Nc6 Blunder]
	::scidb::test::annotate::isolated [::scidb::test::annotate::plys] $classes {
		::ai::annotate::configure -prose 1
		::ai::annotate::annotate .application
		::scidb::test::annotate::wait {![::ai::annotate::running?]} 400
		list [lmap w $::scidb::test::annotate::Written { lindex $w 2 }] $::ai::annotate::Priv(skipped)
	}
} -cleanup {
	unset -nocomplain ::scidb::test::annotate::Draft(script) ::scidb::test::annotate::Draft(claims)
} -result {{{Nc6 allows a fork.}} 0}

tcltest::test annotate-prose-ungrounded {ungrounded prose never reaches the game} -setup {
	set ::scidb::test::annotate::Draft(script) [list ok 1 text "Nc6 wins the queen."]
	set ::scidb::test::annotate::Draft(claims) {illegal move: "Qh9"}
} -body {
	set classes [dict create Nc6 Blunder]
	::scidb::test::annotate::isolated [::scidb::test::annotate::plys] $classes {
		::ai::annotate::configure -prose 1
		::ai::annotate::annotate .application
		::scidb::test::annotate::wait {![::ai::annotate::running?]} 400
		list [llength $::scidb::test::annotate::Written] $::ai::annotate::Priv(skipped)
	}
} -cleanup {
	unset -nocomplain ::scidb::test::annotate::Draft(script) ::scidb::test::annotate::Draft(claims)
} -result {0 1}

tcltest::test annotate-no-engine {without an engine the run says so and does not start} -body {
	set classes {}
	::scidb::test::annotate::isolated [::scidb::test::annotate::plys] $classes {
		rename ::ai::engine::available ::scidb::test::annotate::tmpAvailable
		proc ::ai::engine::available {} { return 0 }
		set started [::ai::annotate::annotate .application]
		rename ::ai::engine::available {}
		rename ::scidb::test::annotate::tmpAvailable ::ai::engine::available
		list $started [llength $::scidb::test::annotate::Info] [::ai::annotate::running?]
	}
} -result {0 1 0}

tcltest::test annotate-cancel-idle {cancelling when nothing runs is a no-op} -body {
	list [::ai::annotate::cancel] [::ai::annotate::running?]
} -result {0 0}

tcltest::cleanupTests