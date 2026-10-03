# ======================================================================
# Scidb App Test — the similar-games narrative (tcl/ai-similar.tcl)
# ======================================================================
# The language model is the stub provider (as in test_app_ai_trend.tcl);
# the claim checker runs for real against the reference position.  Under
# test: the ranking of the candidate games by shared plies, the
# deterministic fact block, the grounded pipeline with a move judged
# against the reference position, and the fall back to the facts.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::similar {
	variable Result
	variable Reports {}
	variable Saved {}
	variable SavedProvider {}
	variable Seq 0
	variable Start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
}

proc ::scidb::test::similar::stub {name body} {
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

proc ::scidb::test::similar::hide {name} {
	variable Saved
	variable Seq
	if {![llength [info commands $name]]} { return }
	set real "$name.__saved[incr Seq]"
	rename $name $real
	lappend Saved [list $name $real]
	return
}

proc ::scidb::test::similar::restoreAll {} {
	variable Saved
	foreach pair [lreverse $Saved] {
		lassign $pair name real
		catch { rename $name {} }
		catch { rename $real $name }
	}
	set Saved {}
	return
}

proc ::scidb::test::similar::stubModel {responses} {
	variable SavedProvider
	set SavedProvider [array get ::ai::provider::Config]
	set ::application::ai::Config(provider) stub
	::ai::provider::configure -name stub -responses $responses
	return
}

proc ::scidb::test::similar::unstubModel {} {
	variable SavedProvider
	array set ::ai::provider::Config $SavedProvider
	return
}

proc ::scidb::test::similar::stubReport {} {
	stub ::application::ai::showReport {{parent title data} {
		lappend ::scidb::test::similar::Reports [list $parent $title \
			[expr {[dict exists $data html] ? [dict get $data html] : ""}]]
		return ""
	}}
	return
}

proc ::scidb::test::similar::clearResult {} {
	unset -nocomplain ::scidb::test::similar::Result
	set ::scidb::test::similar::Reports {}
	return
}

proc ::scidb::test::similar::wait {cond {ms 10000}} {
	set n 0
	while {![uplevel #1 [list expr $cond]] && $n < $ms} { update ; after 10 ; incr n }
	return [uplevel #1 [list expr $cond]]
}

# --- the module (sourced when the app does not ship it yet) -------------

if {[llength [info commands ::ai::trend::narrate]] == 0} {
	catch {
		source [file join [file dirname [file normalize [info script]]] .. tcl ai-trend.tcl]
	}
}

if {[llength [info commands ::ai::similar::facts]] == 0} {
	source [file join [file dirname [file normalize [info script]]] .. tcl ai-similar.tcl]
}

# Candidate games as the retrieval delivers them: players, result, year
# and the number of plies shared with the reference game.
proc ::scidb::test::similar::candidates {} {
	return [list \
		[dict create white Carlsen black Nepo result "1-0" year 2021 shared 4] \
		[dict create white Aronian black Grischuk result "0-1" year 2020 shared 7] \
		[dict create white Anand black Kramnik result "1/2-1/2" year 2019 shared 4] \
		[dict create white Bareev black Short result "" year 0 shared 1]]
}

# ----------------------------------------------------------------------

tcltest::test similar-facts {most shared first, ties by white then black} -body {
	set f [::ai::similar::facts $::scidb::test::similar::Start \
		[::scidb::test::similar::candidates]]
	list [dict get $f games] [lmap r [dict get $f rows] { lindex $r 0 }] \
		[lindex [dict get $f rows] 0] [lindex [dict get $f rows] 3]
} -result {4 {Aronian Anand Carlsen Bareev} {Aronian Grischuk 0-1 2020 7} {Bareev Short ? ? 1}}

tcltest::test similar-facts-limit {the limit caps the rows, not the total} -body {
	set f [::ai::similar::facts x [::scidb::test::similar::candidates] -limit 2]
	list [dict get $f games] [llength [dict get $f rows]] [lmap r [dict get $f rows] { lindex $r 0 }]
} -result {4 2 {Aronian Anand}}

tcltest::test similar-fact-block {the block is deterministic and empty lists say so} -body {
	set f [::ai::similar::facts $::scidb::test::similar::Start \
		[::scidb::test::similar::candidates]]
	set text [::ai::similar::factsText $f]
	list \
		[expr {$text eq [::ai::similar::factsText $f]}] \
		[string match "position: *\ncandidate games: 4\ngames sharing the most opening plies (half-moves) with it:\n  Aronian - Grischuk (0-1, 2020): shares 7 plies\n*" $text] \
		[::ai::similar::factsText [::ai::similar::facts x {}]]
} -result {1 1 {position: x
candidate games: 0
no games share opening plies with this position}}

tcltest::test similar-prompt-grounding {the model is handed the block and held to it} -body {
	set prompt [::ai::similar::prompt "CANDIDATES: 4"]
	set system [::ai::similar::system]
	list \
		[string match {*compared with games from a database*CANDIDATES: 4*} $prompt] \
		[string match {*Use only the games*invent nothing*} $prompt] \
		[string match {*Do not evaluate any position*} $system]
} -result {1 1 1}

tcltest::test similar-narrate-grounded {a legal move is grounded against the reference position} -setup {
	::scidb::test::similar::clearResult
	set f [::ai::similar::facts $::scidb::test::similar::Start \
		[::scidb::test::similar::candidates]]
} -body {
	::scidb::test::similar::stubModel [list \
		"Aronian - Grischuk shares 7 plies with this game, the most of the four, and both start 1. e4."]
	::scidb::test::similar::stubReport
	set ret [::ai::similar::narrate .application $f \
		-done {set ::scidb::test::similar::Result}]
	::scidb::test::similar::wait {[info exists ::scidb::test::similar::Result]}
	lassign [lindex $::scidb::test::similar::Reports 0] parent title html
	list [expr {$ret eq [::ai::similar::factsText $f]}] \
		[dict get $::scidb::test::similar::Result claims] \
		[dict get $::scidb::test::similar::Result grounded] $title
} -cleanup {
	::scidb::test::similar::unstubModel
	::scidb::test::similar::restoreAll
} -result {1 {} 1 {AI: similar games}}

tcltest::test similar-narrate-fallback {without a model the facts are the report} -setup {
	::scidb::test::similar::clearResult
	set f [::ai::similar::facts $::scidb::test::similar::Start \
		[::scidb::test::similar::candidates]]
} -body {
	::scidb::test::similar::hide ::ai::provider::completeAsync
	::scidb::test::similar::stubReport
	::ai::similar::narrate .application $f -done {set ::scidb::test::similar::Result}
	::scidb::test::similar::wait {[info exists ::scidb::test::similar::Result]}
	lassign [lindex $::scidb::test::similar::Reports 0] parent title html
	list [expr {[dict get $::scidb::test::similar::Result text] eq [::ai::similar::factsText $f]}] \
		[dict get $::scidb::test::similar::Result grounded] $title \
		[string match {*<pre>position:*Aronian - Grischuk*shares 7 plies*</pre>*} $html]
} -cleanup {
	::scidb::test::similar::restoreAll
} -result {1 1 {AI: similar games} 1}

tcltest::test similar-report-narrates {report retrieves the candidates and narrates their facts (GUI/assistant entry)} -setup {
	::scidb::test::similar::stub ::ai::similar::StartingFen {{args} {return $::scidb::test::similar::Start}}
	::scidb::test::similar::clearResult
	::scidb::test::similar::stub ::ai::similar::candidates {{base variant number args} {
		set ::scidb::test::similar::Asked [list $base $variant $number $args]
		return [::scidb::test::similar::candidates]
	}}
} -body {
	::scidb::test::similar::hide ::ai::provider::completeAsync
	::scidb::test::similar::stubReport
	::ai::similar::report .application Normal Normal 6 -limit 3 -done {set ::scidb::test::similar::Result}
	::scidb::test::similar::wait {[info exists ::scidb::test::similar::Result]}
	list $::scidb::test::similar::Asked \
		[dict get $::scidb::test::similar::Result ok] \
		[string match {*Aronian - Grischuk*shares 7 plies*} \
			[dict get $::scidb::test::similar::Result text]]
} -cleanup {
	::scidb::test::similar::restoreAll
} -result {{Normal Normal 6 {-limit 3 -seconds 3}} 1 1}

tcltest::test similar-report-failure {a failing retrieval is reported, not raised} -setup {
	::scidb::test::similar::clearResult
	::scidb::test::similar::stub ::ai::similar::candidates {{args} { error "boom" }}
} -body {
	::ai::similar::report .application Normal Normal 0 -done {set ::scidb::test::similar::Result}
	::scidb::test::similar::wait {[info exists ::scidb::test::similar::Result]}
	list [dict get $::scidb::test::similar::Result ok] [dict get $::scidb::test::similar::Result text]
} -cleanup {
	::scidb::test::similar::restoreAll
} -result {0 {similar games could not be retrieved: boom}}

tcltest::test similar-report-unavailable {without the retrieval module the report says so} -setup {
	::scidb::test::similar::clearResult
	::scidb::test::similar::hide ::ai::similar::candidates
} -body {
	::ai::similar::report .application Normal Normal 0 -done {set ::scidb::test::similar::Result}
	::scidb::test::similar::wait {[info exists ::scidb::test::similar::Result]}
	dict get $::scidb::test::similar::Result ok
} -cleanup {
	::scidb::test::similar::restoreAll
} -result 0

tcltest::test similar-assistant-tool {the similar_games tool is registered and checks its arguments} -body {
	set defs [::application::assistant::toolsJson]
	list \
		[string match {*"name":"similar_games"*} $defs] \
		[::application::assistant::CheckArgs similar_games {number 3}] \
		[catch { ::application::assistant::CheckArgs similar_games {number 0} }] \
		[catch { ::application::assistant::CheckArgs similar_games {number abc} }] \
		[catch { ::application::assistant::CheckArgs similar_games {number 2 limit 0} }] \
		[catch { ::application::assistant::CheckArgs similar_games {} }]
} -result {1 {number 3 limit 10} 1 1 1 1}


::tcltest::cleanupTests
return
