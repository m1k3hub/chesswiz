# ======================================================================
# Scidb App Test — the database-trend narrative (tcl/ai-trend.tcl)
# ======================================================================
# The language model is the stub provider (test_ai_ui.tcl's scheme); the
# claim checker runs for real against no position, the way narrate hands
# it a database fact block.  What is under test is the deterministic
# fact block, the facts summary of a small database, the grounded
# pipeline and its single retry, and the fall back to the facts when no
# model or no provider answers.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::trend {
	variable Dir [file join [file dirname [file normalize [info script]]] tmp-app trend_[pid]]
	variable Result
	variable Reports {}
	variable Saved {}
	variable SavedProvider {}
	variable Seq 0
}

# Replace <name> with <body> ({args} {script}), remembering what was there.
# Restore with restoreAll; the sequence keeps nested stubs of the same
# command apart (see test_app_annotate.tcl for the history of this scheme).
proc ::scidb::test::trend::stub {name body} {
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

# Remove <name> without a replacement: narrate's degrade needs a *missing*
# model command, not merely a failing one.
proc ::scidb::test::trend::hide {name} {
	variable Saved
	variable Seq
	if {![llength [info commands $name]]} { return }
	set real "$name.__saved[incr Seq]"
	rename $name $real
	lappend Saved [list $name $real]
	return
}

proc ::scidb::test::trend::restoreAll {} {
	variable Saved
	foreach pair [lreverse $Saved] {
		lassign $pair name real
		catch { rename $name {} }
		catch { rename $real $name }
	}
	set Saved {}
	return
}

# Point the pipeline's model at the stub provider: narrate reads the
# configuration saved by Extras > AI: Choose Model (app-ai), and the stub
# itself is the one test_ai_ui.tcl narrates against.
proc ::scidb::test::trend::stubModel {responses} {
	variable SavedProvider
	set SavedProvider [array get ::ai::provider::Config]
	set ::application::ai::Config(provider) stub
	::ai::provider::configure -name stub -responses $responses
	return
}

proc ::scidb::test::trend::unstubModel {} {
	variable SavedProvider
	array set ::ai::provider::Config $SavedProvider
	return
}

# The report pane, as a recorder: narrate must feed it exactly once per
# ending, through the ordinary ::application::ai surface.
proc ::scidb::test::trend::stubReport {} {
	stub ::application::ai::showReport {{parent title data} {
		lappend ::scidb::test::trend::Reports [list $parent $title \
			[expr {[dict exists $data html] ? [dict get $data html] : ""}]]
		return ""
	}}
	return
}

proc ::scidb::test::trend::clearResult {} {
	unset -nocomplain ::scidb::test::trend::Result
	set ::scidb::test::trend::Reports {}
	return
}

# A callback that never fires must fail the check, not hang the suite.
proc ::scidb::test::trend::wait {cond {ms 10000}} {
	set n 0
	while {![uplevel #1 [list expr $cond]] && $n < $ms} { update ; after 10 ; incr n }
	return [uplevel #1 [list expr $cond]]
}

proc ::scidb::test::trend::nop {args} { return 0 }

# A tiny database: two Sicilian games (one won by each side), one draw in
# B01, and one game that starts from a position -- it carries no ECO code
# (ecoStats keeps it as "?", outside the coded facts and the openings).
# ECO tags are honoured on import, so the codes are known exactly.
proc ::scidb::test::trend::openTrendDatabase {} {
	variable Dir
	file delete -force $Dir
	file mkdir $Dir
	set file [file join $Dir trend.pgn]
	set fh [open $file w]
	fconfigure $fh -encoding utf-8
	foreach {eco result} {
		C60 "1-0"
		C60 "0-1"
		B01 "1/2-1/2"
	} {
		puts $fh "\[Event \"Trend suite\"\]\n\[Site \"X\"\]\n\[Date \"2024.01.01\"\]\n\[Round \"1\"\]"
		puts $fh "\[White \"W\"\]\n\[Black \"B\"\]\n\[Result \"$result\"\]\n\[ECO \"$eco\"\]\n"
		puts $fh "\n1. e4 e5 2. Nf3 *\n"
	}
	puts $fh "\[Event \"Trend suite\"\]\n\[Site \"X\"\]\n\[Date \"2024.01.01\"\]\n\[Round \"2\"\]"
	puts $fh "\[White \"A\"\]\n\[Black \"C\"\]\n\[Result \"1-0\"\]\n\[SetUp \"1\"\]\n\[FEN \"4k3/8/8/8/8/8/8/4K3 w - - 0 1\"\]\n"
	puts $fh "\n*\n"
	close $fh

	::scidb::db::open $file ::scidb::test::trend::nop {} ::scidb::test::trend::nop {}
	return $file
}

proc ::scidb::test::trend::closeDatabase {file} {
	variable Dir
	::scidb::db::close $file
	file delete -force $Dir
	return
}

# A facts dict, built here: ::ai::trend::factsText and narrate are pure
# over it, and no database is needed to phrase their expectations.
proc ::scidb::test::trend::sample {} {
	return [dict create \
		games 50 eco 46 white 24 draws 9 black 13 \
		openings [list \
			[list B90 "Sicilian Najdorf" 20 10 4 6] \
			[list C60 "Ruy Lopez" 5 2 1 2]]]
}

# ----------------------------------------------------------------------

tcltest::test trend-fact-block {the block lists games, results and openings, one per line} -body {
	set text [::ai::trend::factsText [::scidb::test::trend::sample]]
	list \
		[expr {$text eq [join [list \
			"games: 50" \
			"games with an ECO code: 46 (white wins 24, draws 9, black wins 13)" \
			"most played openings:" \
			"  B90 Sicilian Najdorf: 20 games (white wins 10, draws 4, black wins 6)" \
			"  C60 Ruy Lopez: 5 games (white wins 2, draws 1, black wins 2)"] \n]}] \
		[expr {$text eq [::ai::trend::factsText [::scidb::test::trend::sample]]}]
} -result {1 1}

tcltest::test trend-fact-block-empty {a database without coded games says so} -body {
	::ai::trend::factsText [dict create games 50 eco 0 white 0 draws 0 black 0 openings {}]
} -result {games: 50
no games with an ECO code}

tcltest::test trend-fact-block-blank-name {a missing opening name does not break the block} -body {
	::ai::trend::factsText [dict create games 1 eco 1 white 1 draws 0 black 0 \
		openings [list [list B01 {} 1 1 0 0]]]
} -result {games: 1
games with an ECO code: 1 (white wins 1, draws 0, black wins 0)
most played openings:
  B01 : 1 games (white wins 1, draws 0, black wins 0)}

tcltest::test trend-openings-order {most games first; ties by ECO code} -body {
	set rows [list [list C60 x 5 0 0 0] [list B01 y 12 0 0 0] [list A00 z 5 0 0 0]]
	lsort -command ::ai::trend::Compare $rows
} -result {{B01 y 12 0 0 0} {A00 z 5 0 0 0} {C60 x 5 0 0 0}}

tcltest::test trend-prompt-grounding {the model is handed the fact block and is held to it} -body {
	set prompt [::ai::trend::prompt "GAMES: 50\nCODED: 46"]
	set system [::ai::trend::system]
	list \
		[string match {*trend facts:*GAMES: 50*CODED: 46*} $prompt] \
		[string match {*Use only the numbers*invent nothing*} $prompt] \
		[string match {*Do not name a game, a player, a move or an evaluation*} $system] \
		[string match {*position on the board*} $system]
} -result {1 1 1 1}


tcltest::test trend-facts-database {the facts summary of a small database (audit B4)} -setup {
	set f [::scidb::test::trend::openTrendDatabase]
} -body {
	set facts [::ai::trend::facts $f Normal]

	set proj {}
	foreach row [dict get $facts openings] {
		lappend proj [concat [lindex $row 0] [lrange $row 2 5]]
	}
	# the opening names come from the same lookup the assistant's database
	# summary uses: assert equivalence with it, not the locale's wording
	set names {}
	foreach row [dict get $facts openings] {
		lassign $row code name
		set want ""
		catch { set want [::application::assistant::EcoName $code Normal] }
		lappend names [expr {$name eq $want}]
	}
	# nothing to phrase for the game without a code: the sums stay equal
	list [lsort [dict keys $facts]] \
		[dict get $facts games] [dict get $facts eco] \
		[dict get $facts white] [dict get $facts draws] [dict get $facts black] \
		[expr {[dict get $facts white] + [dict get $facts draws] + [dict get $facts black]
			== [dict get $facts eco]}] \
		$proj $names
} -cleanup {
	::scidb::test::trend::closeDatabase $f
} -result {{black draws eco games openings white} 4 3 1 1 1 1 {{C60 2 1 0 1} {B01 1 0 1 0}} {1 1}}

tcltest::test trend-facts-sum {every sum over the openings rows matches its fact} -setup {
	set f [::scidb::test::trend::openTrendDatabase]
} -body {
	set facts [::ai::trend::facts $f Normal]
	set w 0
	set d 0
	set b 0
	foreach row [dict get $facts openings] {
		lassign $row _ name n ww dd bb
		incr w $ww
		incr d $dd
		incr b $bb
	}
	list [expr {$w <= [dict get $facts white]}] \
		[expr {$d <= [dict get $facts draws]}] \
		[expr {$b <= [dict get $facts black]}] \
		[llength [dict get $facts openings]]
} -cleanup {
	::scidb::test::trend::closeDatabase $f
} -result {1 1 1 2}

tcltest::test trend-facts-read-only {the facts only read: no file of the database changes} -setup {
	set f [::scidb::test::trend::openTrendDatabase]
} -body {
	set before [file mtime $f]
	::ai::trend::facts $f Normal
	list [expr {[file mtime $f] == $before}] [::scidb::db::count games $f Normal]
} -cleanup {
	::scidb::test::trend::closeDatabase $f
} -result {1 4}

# --- the grounded narrative (stub model) ---------------------------------

tcltest::test trend-narrate-grounded {the stub's phrase is audited and delivered with the facts} -setup {
	::scidb::test::trend::clearResult
	set ::scidb::test::trend::Facts \
		[dict create games 50 eco 46 white 24 draws 9 black 13 \
			openings [list [list C60 "Ruy Lopez" 30 15 5 10]]]
} -body {
	set block [::ai::trend::factsText $::scidb::test::trend::Facts]
	::scidb::test::trend::stubModel \
		[list "The openings C60 and B01 dominate; results are balanced."]
	::scidb::test::trend::stubReport
	unset -nocomplain ::scidb::test::trend::Result
	set ret [::ai::trend::narrate .application $::scidb::test::trend::Facts \
		-done {set ::scidb::test::trend::Result}]
	::scidb::test::trend::wait {[info exists ::scidb::test::trend::Result]}

	lassign [lindex $::scidb::test::trend::Reports 0] parent title html
	list \
		[expr {$ret eq $block}] \
		[dict get $::scidb::test::trend::Result ok] \
		[dict get $::scidb::test::trend::Result text] \
		[dict get $::scidb::test::trend::Result claims] \
		[dict get $::scidb::test::trend::Result grounded] \
		$parent $title \
		[expr {[llength $::scidb::test::trend::Reports] == 1}] \
		[string match {*<b>Assessment</b>*} $html] \
		[string match {*<b>Grounding facts</b>*most played openings:*} $html]
} -cleanup {
	::scidb::test::trend::unstubModel
	::scidb::test::trend::restoreAll
} -result {1 1 {The openings C60 and B01 dominate; results are balanced.} {} 1 .application {AI: database trends} 1 1 1}

tcltest::test trend-narrate-retry {contradicting prose is fed back and retried once} -setup {
	::scidb::test::trend::clearResult
} -body {
	set facts [dict create games 50 eco 46 white 24 draws 9 black 13 openings {}]
	::scidb::test::trend::stubModel [list \
		"The trend is clear; watch the fork on Qh5." \
		"The openings C60 and B01 dominate."]
	# the first answer names a move: a fact block about a database has no
	# position to ground it with, so the move claim fails the check and the
	# model answers once more
	::scidb::test::trend::stubReport
	unset -nocomplain ::scidb::test::trend::Result
	::ai::trend::narrate .application $facts -done {set ::scidb::test::trend::Result}
	::scidb::test::trend::wait {[info exists ::scidb::test::trend::Result]}
	list \
		[dict get $::scidb::test::trend::Result text] \
		[dict get $::scidb::test::trend::Result claims] \
		[dict get $::scidb::test::trend::Result grounded] \
		$::ai::provider::Config(index) \
		[llength $::scidb::test::trend::Reports]
} -cleanup {
	::scidb::test::trend::unstubModel
	::scidb::test::trend::restoreAll
} -result {{The openings C60 and B01 dominate.} {} 1 2 1}

tcltest::test trend-narrate-unverified {the second answer still ungrounded is delivered as such} -setup {
	::scidb::test::trend::clearResult
} -body {
	set facts [dict create games 50 eco 46 white 24 draws 9 black 13 openings {}]
	::scidb::test::trend::stubModel [list \
		"Watch the fork on Qh5." \
		"Still the fork on Qh5."]
	::scidb::test::trend::stubReport
	unset -nocomplain ::scidb::test::trend::Result
	::ai::trend::narrate .application $facts -done {set ::scidb::test::trend::Result}
	::scidb::test::trend::wait {[info exists ::scidb::test::trend::Result]}

	lassign [lindex $::scidb::test::trend::Reports 0] parent title html
	list \
		[dict get $::scidb::test::trend::Result text] \
		[dict get $::scidb::test::trend::Result claims] \
		[dict get $::scidb::test::trend::Result grounded] \
		$title \
		[string match {*<li>illegal move: "Qh5"</li>*} $html]
} -cleanup {
	::scidb::test::trend::unstubModel
	::scidb::test::trend::restoreAll
} -result {{Still the fork on Qh5.} {{illegal move: "Qh5"}} 0 {AI: database trends (unverified)} 1}

tcltest::test trend-narrate-fallback {without a model the facts themselves are the report} -setup {
	::scidb::test::trend::clearResult
} -body {
	set facts [dict create games 50 eco 46 white 24 draws 9 black 13 \
		openings [list [list B90 "Sicilian Najdorf" 20 10 4 6]]]
	::scidb::test::trend::stubReport
	set saved [array get ::ai::provider::Config]
	::scidb::test::trend::hide ::ai::provider::completeAsync

	set block [::ai::trend::factsText $facts]
	set ret [::ai::trend::narrate .application $facts \
		-done {set ::scidb::test::trend::Result}]
	::scidb::test::trend::wait {[info exists ::scidb::test::trend::Result]}

	lassign [lindex $::scidb::test::trend::Reports 0] parent title html
	list \
		[expr {$ret eq $block}] \
		[dict get $::scidb::test::trend::Result ok] \
		[expr {[dict get $::scidb::test::trend::Result text] eq $block}] \
		[dict get $::scidb::test::trend::Result claims] \
		[dict get $::scidb::test::trend::Result grounded] \
		$title \
		[expr {[llength $::scidb::test::trend::Reports] == 1}] \
		[string match {*Database trends*<pre>*games: 50*most played openings:*B90*</pre>*} $html]
} -cleanup {
	array set ::ai::provider::Config $saved
	::scidb::test::trend::restoreAll
} -result {1 1 1 {} 1 {AI: database trends} 1 1}

tcltest::test trend-narrate-provider-error {an unreachable provider falls back to the facts} -setup {
	::scidb::test::trend::clearResult
} -body {
	set facts [dict create games 50 eco 46 white 24 draws 9 black 13 openings {}]
	::scidb::test::trend::stubModel {{"the model would say something"}}
	::scidb::test::trend::stubReport
	::scidb::test::trend::stub ::ai::provider::completeAsync {{prompt script args} {
		after 0 [list {*}$script [list ok 0 error "provider is down"]]
	}}
	unset -nocomplain ::scidb::test::trend::Result
	set ret [::ai::trend::narrate .application $facts \
		-done {set ::scidb::test::trend::Result}]
	::scidb::test::trend::wait {[info exists ::scidb::test::trend::Result]}

	set block [::ai::trend::factsText $facts]
	lassign [lindex $::scidb::test::trend::Reports 0] parent title html
	list \
		[expr {$ret eq $block}] \
		[dict get $::scidb::test::trend::Result ok] \
		[expr {[dict get $::scidb::test::trend::Result text] eq $block}] \
		[dict get $::scidb::test::trend::Result claims] \
		[dict get $::scidb::test::trend::Result grounded] \
		$title \
		[string match {*Database trends*<pre>*games: 50*</pre>*} $html]
} -cleanup {
	::scidb::test::trend::unstubModel
	::scidb::test::trend::restoreAll
} -result {1 1 1 {} 1 {AI: database trends} 1}

::tcltest::cleanupTests
return
