# ======================================================================
# Scidb App Test — the opening-prep narrative (tcl/ai-openingprep.tcl)
# ======================================================================
# The language model is the stub provider (as in test_app_ai_trend.tcl);
# the claim checker runs for real against the position the table belongs
# to.  Under test: the deterministic fact block, the grounded pipeline
# with a move judged against the position, and the fall back to the facts.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::oprep {
	variable Result
	variable Reports {}
	variable Saved {}
	variable SavedProvider {}
	variable Seq 0
	variable Start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
}

proc ::scidb::test::oprep::stub {name body} {
	variable Saved
	variable Seq
	if {[llength [info commands $name]]} {
		set real "$name.__saved[incr Seq]"
		rename $name $real
		lappend Saved [list $name $real]
	}
	proc $name {*}$body
	return
}

proc ::scidb::test::oprep::hide {name} {
	variable Saved
	variable Seq
	if {![llength [info commands $name]]} { return }
	set real "$name.__saved[incr Seq]"
	rename $name $real
	lappend Saved [list $name $real]
	return
}

proc ::scidb::test::oprep::restoreAll {} {
	variable Saved
	foreach pair [lreverse $Saved] {
		lassign $pair name real
		catch { rename $name {} }
		catch { rename $real $name }
	}
	set Saved {}
	return
}

proc ::scidb::test::oprep::stubModel {responses} {
	variable SavedProvider
	set SavedProvider [array get ::ai::provider::Config]
	set ::application::ai::Config(provider) stub
	::ai::provider::configure -name stub -responses $responses
	return
}

proc ::scidb::test::oprep::unstubModel {} {
	variable SavedProvider
	array set ::ai::provider::Config $SavedProvider
	return
}

proc ::scidb::test::oprep::stubReport {} {
	stub ::application::ai::showReport {{parent title data} {
		lappend ::scidb::test::oprep::Reports [list $parent $title \
			[expr {[dict exists $data html] ? [dict get $data html] : ""}]]
		return ""
	}}
	return
}

proc ::scidb::test::oprep::clearResult {} {
	unset -nocomplain ::scidb::test::oprep::Result
	set ::scidb::test::oprep::Reports {}
	return
}

proc ::scidb::test::oprep::wait {cond {ms 10000}} {
	set n 0
	while {![uplevel #1 [list expr $cond]] && $n < $ms} { update ; after 10 ; incr n }
	return [uplevel #1 [list expr $cond]]
}

# Rows as ::scidb::tree::describe delivers them (score/draws in per-mille).
proc ::scidb::test::oprep::rows {} {
	set rows {}
	foreach {move eco n score draws rating year player} {
		d4 A40 3 500 200 2400 2021 Anand
		e4 B00 12 550 250 2450 2024 Carlsen
		c4 A10 3 400 100 2300 0 Kasparov
	} {
		lappend rows [dict create row [llength $rows] move $move eco $eco frequency $n \
			score $score draws $draws result {} averageRating $rating lastYear $year \
			bestPlayer $player identity {}]
	}
	return $rows
}

# ----------------------------------------------------------------------

tcltest::test oprep-facts {most played first, ties by move; percent and unknown year} -body {
	set f [::ai::openingprep::facts $::scidb::test::oprep::Start [::scidb::test::oprep::rows]]
	list [dict get $f games] [lmap m [dict get $f moves] { lindex $m 0 }] \
		[lindex [dict get $f moves] 0] [lindex [dict get $f moves] 1]
} -result {18 {e4 c4 d4} {e4 B00 12 55.0 25.0 2450 2024 Carlsen} {c4 A10 3 40.0 10.0 2300 ? Kasparov}}

tcltest::test oprep-facts-limit {the limit caps the moves, not the game total} -body {
	set f [::ai::openingprep::facts x [::scidb::test::oprep::rows] -limit 1]
	list [dict get $f games] [llength [dict get $f moves]]
} -result {18 1}

tcltest::test oprep-fact-block {the block is deterministic and empty tables say so} -body {
	set f [::ai::openingprep::facts $::scidb::test::oprep::Start [::scidb::test::oprep::rows]]
	set text [::ai::openingprep::factsText $f]
	list \
		[expr {$text eq [::ai::openingprep::factsText $f]}] \
		[string match "position: *\ngames: 18\ncandidate moves, most played first:\n  e4 (B00): 12 games, score 55.0%, draws 25.0%,*" $text] \
		[::ai::openingprep::factsText [::ai::openingprep::facts x {}]]
} -result {1 1 {position: x
games: 0
no candidate moves}}

tcltest::test oprep-prompt-grounding {the model is handed the block and held to it} -body {
	set prompt [::ai::openingprep::prompt "GAMES: 18"]
	set system [::ai::openingprep::system]
	list \
		[string match {*candidate moves for one position:*GAMES: 18*} $prompt] \
		[string match {*Use only the moves*invent nothing*} $prompt] \
		[string match {*Do not evaluate the position*} $system]
} -result {1 1 1}

tcltest::test oprep-narrate-grounded {a legal move is grounded against the table's position} -setup {
	::scidb::test::oprep::clearResult
	set f [::ai::openingprep::facts $::scidb::test::oprep::Start [::scidb::test::oprep::rows]]
} -body {
	::scidb::test::oprep::stubModel [list "e4 is played most, in 12 of 18 games."]
	::scidb::test::oprep::stubReport
	set ret [::ai::openingprep::narrate .application $f \
		-done {set ::scidb::test::oprep::Result}]
	::scidb::test::oprep::wait {[info exists ::scidb::test::oprep::Result]}
	lassign [lindex $::scidb::test::oprep::Reports 0] parent title html
	list [expr {$ret eq [::ai::openingprep::factsText $f]}] \
		[dict get $::scidb::test::oprep::Result claims] \
		[dict get $::scidb::test::oprep::Result grounded] $title
} -cleanup {
	::scidb::test::oprep::unstubModel
	::scidb::test::oprep::restoreAll
} -result {1 {} 1 {AI: opening preparation}}

tcltest::test oprep-narrate-fallback {without a model the facts are the report} -setup {
	::scidb::test::oprep::clearResult
	set f [::ai::openingprep::facts $::scidb::test::oprep::Start [::scidb::test::oprep::rows]]
} -body {
	::scidb::test::oprep::hide ::ai::provider::completeAsync
	::scidb::test::oprep::stubReport
	::ai::openingprep::narrate .application $f -done {set ::scidb::test::oprep::Result}
	::scidb::test::oprep::wait {[info exists ::scidb::test::oprep::Result]}
	lassign [lindex $::scidb::test::oprep::Reports 0] parent title html
	list [expr {[dict get $::scidb::test::oprep::Result text] eq [::ai::openingprep::factsText $f]}] \
		[dict get $::scidb::test::oprep::Result grounded] $title \
		[string match {*<pre>position:*e4 (B00)*</pre>*} $html]
} -cleanup {
	::scidb::test::oprep::restoreAll
} -result {1 1 {AI: opening preparation} 1}

::tcltest::cleanupTests
return
