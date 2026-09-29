# ======================================================================
# Scidb App Test — the event report narrative (tcl/ai-eventreport.tcl)
# ======================================================================
# The language model is the stub provider (as in test_app_ai_trend.tcl);
# this narrative is counts-only, so no position is handed to the claim
# checker.  Under test: the deterministic fact block, the grounded
# pipeline, and the fall back to the facts.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

# ::ai::eventreport is sourced from the tree until it is part of the built
# app (the same guard tests/test_app_transcript.tcl uses for ai-transcript).
if {[llength [info commands ::ai::eventreport::facts]] == 0} {
	source [file join [file dirname [file normalize [info script]]] .. tcl ai-eventreport.tcl]
}

namespace eval ::scidb::test::evrep {
	variable Result
	variable Reports {}
	variable Saved {}
	variable SavedProvider {}
	variable Seq 0
}

proc ::scidb::test::evrep::stub {name body} {
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

proc ::scidb::test::evrep::hide {name} {
	variable Saved
	variable Seq
	if {![llength [info commands $name]]} { return }
	set real "$name.__saved[incr Seq]"
	rename $name $real
	lappend Saved [list $name $real]
	return
}

proc ::scidb::test::evrep::restoreAll {} {
	variable Saved
	foreach pair [lreverse $Saved] {
		lassign $pair name real
		catch { rename $name {} }
		catch { rename $real $name }
	}
	set Saved {}
	return
}

proc ::scidb::test::evrep::stubModel {responses} {
	variable SavedProvider
	set SavedProvider [array get ::ai::provider::Config]
	set ::application::ai::Config(provider) stub
	::ai::provider::configure -name stub -responses $responses
	return
}

proc ::scidb::test::evrep::unstubModel {} {
	variable SavedProvider
	array set ::ai::provider::Config $SavedProvider
	return
}

proc ::scidb::test::evrep::stubReport {} {
	stub ::application::ai::showReport {{parent title data} {
		lappend ::scidb::test::evrep::Reports [list $parent $title \
			[expr {[dict exists $data html] ? [dict get $data html] : ""}]]
		return ""
	}}
	return
}

proc ::scidb::test::evrep::clearResult {} {
	unset -nocomplain ::scidb::test::evrep::Result
	set ::scidb::test::evrep::Reports {}
	return
}

proc ::scidb::test::evrep::wait {cond {ms 10000}} {
	set n 0
	while {![uplevel #1 [list expr $cond]] && $n < $ms} { update ; after 10 ; incr n }
	return [uplevel #1 [list expr $cond]]
}

# Standings rows, the two shapes the crosstable may deliver: a dict with
# name/points/games and a plain list.
proc ::scidb::test::evrep::rows {} {
	return [list \
		[dict create name "Kramnik" points 7.0 games 11] \
		[list "Anand" 7.5 11] \
		[dict create name "Topalov" points 6.5 games 10]]
}

# ----------------------------------------------------------------------

tcltest::test evrep-facts {most points first, ties by name; totals and counts} -body {
	set f [::ai::eventreport::facts "Wijk aan Zee 2024" [::scidb::test::evrep::rows]]
	list [dict get $f event] [dict get $f players] [dict get $f games] \
		[dict get $f standings]
} -result {{Wijk aan Zee 2024} 3 32 {{Anand 7.5 11} {Kramnik 7.0 11} {Topalov 6.5 10}}}

tcltest::test evrep-facts-games {an explicit game count wins over the total} -body {
	set f [::ai::eventreport::facts E [::scidb::test::evrep::rows] -games 30]
	list [dict get $f games] [dict get $f players]
} -result {30 3}

tcltest::test evrep-facts-limit {the limit caps the rows, not the player total} -body {
	set f [::ai::eventreport::facts E [::scidb::test::evrep::rows] -limit 2]
	list [dict get $f players] [dict get $f games] [llength [dict get $f standings]]
} -result {3 32 2}

tcltest::test evrep-fact-block {the block is deterministic and empty tables say so} -body {
	set f [::ai::eventreport::facts "Wijk aan Zee 2024" [::scidb::test::evrep::rows]]
	set text [::ai::eventreport::factsText $f]
	list \
		[expr {$text eq [::ai::eventreport::factsText $f]}] \
		[string match "event: Wijk aan Zee 2024\nplayers: 3\ngames: 32\nfinal standings, most points first:\n  Anand: 7.5 points from 11 games*" $text] \
		[::ai::eventreport::factsText [::ai::eventreport::facts E {}]]
} -result {1 1 {event: E
players: 0
games: 0
no players}}

tcltest::test evrep-prompt-grounding {the model is handed the block and held to it} -body {
	set prompt [::ai::eventreport::prompt "STANDINGS: 3"]
	set system [::ai::eventreport::system]
	list \
		[string match {*crosstable facts:*STANDINGS: 3*} $prompt] \
		[string match {*Use only the names*scores*invent nothing*} $prompt] \
		[string match {*Do not name a move*} $system]
} -result {1 1 1}

tcltest::test evrep-narrate-grounded {counts only, so no position is judged} -setup {
	::scidb::test::evrep::clearResult
	set f [::ai::eventreport::facts "Wijk aan Zee 2024" [::scidb::test::evrep::rows]]
} -body {
	set block [::ai::eventreport::factsText $f]
	::scidb::test::evrep::stubModel [list "Anand finished first with 7.5 points from 11 games."]
	::scidb::test::evrep::stubReport
	set ret [::ai::eventreport::narrate .application $f \
		-done {set ::scidb::test::evrep::Result}]
	::scidb::test::evrep::wait {[info exists ::scidb::test::evrep::Result]}
	lassign [lindex $::scidb::test::evrep::Reports 0] parent title html
	list \
		[expr {$ret eq $block}] \
		[dict get $::scidb::test::evrep::Result ok] \
		[dict get $::scidb::test::evrep::Result text] \
		[dict get $::scidb::test::evrep::Result claims] \
		[dict get $::scidb::test::evrep::Result grounded] \
		$parent $title \
		[expr {[llength $::scidb::test::evrep::Reports] == 1}] \
		[string match {*<b>Assessment</b>*} $html] \
		[string match {*<b>Grounding facts</b>*final standings, most points first:*Anand: 7.5*} $html]
} -cleanup {
	::scidb::test::evrep::unstubModel
	::scidb::test::evrep::restoreAll
} -result {1 1 {Anand finished first with 7.5 points from 11 games.} {} 1 .application {AI: event report} 1 1 1}

tcltest::test evrep-narrate-fallback {without a model the facts are the report} -setup {
	::scidb::test::evrep::clearResult
	set f [::ai::eventreport::facts "Wijk aan Zee 2024" [::scidb::test::evrep::rows]]
} -body {
	::scidb::test::evrep::hide ::ai::provider::completeAsync
	::scidb::test::evrep::stubReport
	::ai::eventreport::narrate .application $f -done {set ::scidb::test::evrep::Result}
	::scidb::test::evrep::wait {[info exists ::scidb::test::evrep::Result]}
	lassign [lindex $::scidb::test::evrep::Reports 0] parent title html
	list [expr {[dict get $::scidb::test::evrep::Result text] eq [::ai::eventreport::factsText $f]}] \
		[dict get $::scidb::test::evrep::Result grounded] $title \
		[string match {*<pre>event: Wijk aan Zee 2024*Anand: 7.5*</pre>*} $html]
} -cleanup {
	::scidb::test::evrep::restoreAll
} -result {1 1 {AI: event report} 1}

tcltest::test eventreport-standings-tags {points from Result tags: win 1, draw 1/2, unfinished 0 but played} -body {
	set games [list \
		[dict create Event "Open" White "A" Black "B" Result "1-0"] \
		[dict create Event "Open" White "B" Black "C" Result "1/2-1/2"] \
		[dict create Event "Open" White "C" Black "A" Result "*"]]
	lassign [::ai::eventreport::standingsFromTags $games] event rows
	list $event [lsort -index 0 $rows]
} -result {Open {{A 1 2} {B 0.5 2} {C 0.5 2}}}


::tcltest::cleanupTests
return
