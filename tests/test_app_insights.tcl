# ======================================================================
# Scidb App Test - personal insights (tcl/insights.tcl)
# ======================================================================
# The aggregation core is pure: a list of game records in, one report
# dict of integers out (scores in hundredths of a percent, 8500 =
# 85.00%).  The record shape is
#   {white black result eco opening whiteElo blackElo date plies termination}
# and the exact numbers below are counted by hand from the fixture.
# The collector is exercised against a small real database at the end,
# with no network.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::insights {
	variable Dir [file join [file dirname [file normalize [info script]]] tmp-app insights_[pid]]
	variable Result {}
}

proc ::scidb::test::insights::nop {args} { return 0 }

proc ::scidb::test::insights::CollectDone {result} {
	set ::scidb::test::insights::Result $result
	if {[dict get $result ok]} {
		set ::scidb::test::insights::Records [dict get $result records]
	}
}

# One record, spelled out: white black result eco opening whiteElo
# blackElo date plies termination.
proc ::scidb::test::insights::rec {args} { return $args }

# The report of one player over the shared fixture, in the default shape
# (min 5 games for the weakest table).  Every game counts for "Me".
proc ::scidb::test::insights::fixture {} {
	return [list \
		[::scidb::test::insights::rec Me  A 1-0     C60 {Ruy Lopez}     2000 1900 2020.05.01  60 normal] \
		[::scidb::test::insights::rec Me  B 0-1     C60 {Ruy Lopez}     2000 2100 2020.06.01  40 {time forfeit}] \
		[::scidb::test::insights::rec Me  C 1/2-1/2 B01 {Scandinavian}  2000 2000 2021.01.01 130 normal] \
		[::scidb::test::insights::rec D   Me 1-0    B01 {Scandinavian}  1900 2000 2021.02.01  60 normal] \
		[::scidb::test::insights::rec E   Me 0-1    A00 {Irregular}     2200 2000 2022.03.01  20 normal] \
		[::scidb::test::insights::rec F   Me 1/2-1/2 D00 {Queen's pawn} 2000 2000 2022.04.01 122 normal] \
		[::scidb::test::insights::rec X   Y  1-0    C60 {Ruy Lopez}     2000 2000 2020.01.01  60 normal] \
		[::scidb::test::insights::rec Me  G  *      C50 {Italian}       2000    0 {????.??.??} 0 normal] \
	]
}

# Look one row up by its key, whatever order the section keeps.
proc ::scidb::test::insights::row {rows key} {
	foreach row $rows {
		if {[lindex $row 0] eq $key} { return $row }
	}
	return ""
}

# A game of <n> records all of <result> for "Me" as White in opening
# <eco>; ratings and date are fixed.
proc ::scidb::test::insights::games {n eco result} {
	set out {}
	for {set i 0} {$i < $n} {incr i} {
		lappend out [::scidb::test::insights::rec Me Opp $result $eco $eco 2000 2000 2020.01.01 60 normal]
	}
	return $out
}

file mkdir $::scidb::test::insights::Dir

# ----------------------------------------------------------------------
# overall and colour
# ----------------------------------------------------------------------

tcltest::test insights-overall {overall W-D-L, score and loss rate over the fixture} -body {
	set report [::insights::aggregate [::scidb::test::insights::fixture] Me]
	list \
		[dict get $report games] \
		[dict get $report decided] \
		[dict get $report unknown] \
		[dict get $report overall]
} -result {7 6 1 {overall 2 2 2 7 5000 3333}}

tcltest::test insights-colour {the same player scores as White and as Black} -body {
	set report [::insights::aggregate [::scidb::test::insights::fixture] Me]
	list [dict get $report white] [dict get $report black]
} -result {{white 1 1 1 4 5000 3333} {black 1 1 1 3 5000 3333}}

tcltest::test insights-ignores-others {games without the player are not counted} -body {
	set records [list \
		[::scidb::test::insights::rec X Y 1-0 C60 {Ruy Lopez} 2000 2000 2020.01.01 60 normal] \
		[::scidb::test::insights::rec Me A 1-0 C60 {Ruy Lopez} 2000 2000 2020.01.01 60 normal]]
	dict get [::insights::aggregate $records Me] games
} -result 1

# ----------------------------------------------------------------------
# openings and families
# ----------------------------------------------------------------------

tcltest::test insights-families {ECO family letters A-E, "?" for none} -body {
	set records [list \
		[::scidb::test::insights::rec Me A 1-0 A00 x 2000 2000 2020.01.01 60 normal] \
		[::scidb::test::insights::rec Me A 1-0 B01 x 2000 2000 2020.01.01 60 normal] \
		[::scidb::test::insights::rec Me A 1-0 C60 x 2000 2000 2020.01.01 60 normal] \
		[::scidb::test::insights::rec Me A 1-0 D00 x 2000 2000 2020.01.01 60 normal] \
		[::scidb::test::insights::rec Me A 1-0 E00 x 2000 2000 2020.01.01 60 normal] \
		[::scidb::test::insights::rec Me A 1-0 {} x 2000 2000 2020.01.01 60 normal] \
		[::scidb::test::insights::rec Me A 1-0 Z99 x 2000 2000 2020.01.01 60 normal]]
	set families [dict get [::insights::aggregate $records Me] families]
	list [llength $families] [lmap row $families {lindex $row 0}]
} -result {6 {A B C D E ?}}

tcltest::test insights-openings {the top openings carry their games and name} -body {
	set report [::insights::aggregate [::scidb::test::insights::fixture] Me]
	set openings [dict get $report openings]
	list \
		[::scidb::test::insights::row $openings C60] \
		[::scidb::test::insights::row $openings B01] \
		[::scidb::test::insights::row $openings A00] \
		[::scidb::test::insights::row $openings C50] \
		[llength $openings]
} -result {{C60 {Ruy Lopez} 1 0 1 2 5000 5000} {B01 Scandinavian 0 1 1 2 2500 5000} {A00 Irregular 1 0 0 1 10000 0} {C50 Italian 0 0 0 1 0 0} 5}

tcltest::test insights-openings-top-limit {the top list is capped by -top-openings} -body {
	set report [::insights::aggregate [::scidb::test::insights::fixture] Me -top-openings 2]
	llength [dict get $report openings]
} -result 2

tcltest::test insights-weakest {openings with enough games, lowest score first} -body {
	set records [concat \
		[::scidb::test::insights::games 5 A00 1-0] \
		[::scidb::test::insights::games 5 B00 0-1] \
		[::scidb::test::insights::games 4 C00 0-1]]
	set weakest [dict get [::insights::aggregate $records Me -min-games 5 -weakest-lines 10] weakest]
	list $weakest [llength $weakest]
} -result {{{B00 B00 0 0 5 5 0 10000} {A00 A00 5 0 0 5 10000 0}} 2}

tcltest::test insights-weakest-limit {the weakest list is capped by -weakest-lines} -body {
	set records [concat \
		[::scidb::test::insights::games 5 A00 1-0] \
		[::scidb::test::insights::games 5 B00 0-1]]
	set weakest [dict get [::insights::aggregate $records Me -min-games 5 -weakest-lines 1] weakest]
	list $weakest [llength $weakest]
} -result {{{B00 B00 0 0 5 5 0 10000}} 1}

# ----------------------------------------------------------------------
# opponent strength
# ----------------------------------------------------------------------

tcltest::test insights-elo-bands {the band boundaries are exclusive on the far side} -body {
	list \
		[::insights::eloBand 2000 1799] \
		[::insights::eloBand 2000 1800] \
		[::insights::eloBand 2000 1949] \
		[::insights::eloBand 2000 1950] \
		[::insights::eloBand 2000 2050] \
		[::insights::eloBand 2000 2051] \
		[::insights::eloBand 2000 2200] \
		[::insights::eloBand 2000 2201]
} -result {weaker200 weaker50 weaker50 even even stronger50 stronger50 stronger200}

tcltest::test insights-elo-unknown {a missing rating on either side has no band} -body {
	list \
		[::insights::eloBand 0 2000] \
		[::insights::eloBand 2000 0] \
		[::insights::eloBand {} 2000] \
		[::insights::eloBand 2000 {}]
} -result {unknown unknown unknown unknown}

tcltest::test insights-elo-negative {a rating the game did not carry is read by value} -body {
	list [::insights::eloBand -2000 -2100] [::insights::eloBand -2000 1800]
} -result {stronger50 weaker50}

tcltest::test insights-bands {the fixture's games fall into the right bands} -body {
	set report [::insights::aggregate [::scidb::test::insights::fixture] Me]
	set bands [dict get $report bands]
	list \
		[::scidb::test::insights::row $bands weaker50] \
		[::scidb::test::insights::row $bands even] \
		[::scidb::test::insights::row $bands stronger50] \
		[::scidb::test::insights::row $bands unknown] \
		[::scidb::test::insights::row $bands weaker200]
} -result {{weaker50 1 0 1 2 5000 5000} {even 0 2 0 2 5000 0} {stronger50 1 0 1 2 5000 5000} {unknown 0 0 0 1 0 0} {}}

# ----------------------------------------------------------------------
# year, length, loss reasons
# ----------------------------------------------------------------------

tcltest::test insights-years {newest year first, a missing date last once} -body {
	set report [::insights::aggregate [::scidb::test::insights::fixture] Me]
	set years [dict get $report years]
	list \
		[lmap row $years {lindex $row 0}] \
		[::scidb::test::insights::row $years 2022] \
		[::scidb::test::insights::row $years 2021] \
		[::scidb::test::insights::row $years 2020] \
		[::scidb::test::insights::row $years ?]
} -result {{2022 2021 2020 ?} {2022 1 1 0 2 7500 0} {2021 0 1 1 2 2500 5000} {2020 1 0 1 2 5000 5000} {? 0 0 0 1 0 0}}

tcltest::test insights-lengths {short under 30 moves, medium 30-60, long over 60} -body {
	list \
		[::insights::lengthBucket 0] \
		[::insights::lengthBucket 29] \
		[::insights::lengthBucket 30] \
		[::insights::lengthBucket 60] \
		[::insights::lengthBucket 61]
} -result {short short medium medium long}

tcltest::test insights-move-count {half-moves are rounded up to full moves} -body {
	list \
		[::insights::moveCount 0] \
		[::insights::moveCount 1] \
		[::insights::moveCount 2] \
		[::insights::moveCount 59] \
		[::insights::moveCount 60] \
		[::insights::moveCount 61] \
		[::insights::moveCount {}]
} -result {0 1 1 30 30 31 0}

tcltest::test insights-length-rows {the fixture's games by length} -body {
	set report [::insights::aggregate [::scidb::test::insights::fixture] Me]
	set lengths [dict get $report lengths]
	list \
		[::scidb::test::insights::row $lengths short] \
		[::scidb::test::insights::row $lengths medium] \
		[::scidb::test::insights::row $lengths long]
} -result {{short 1 0 1 3 5000 5000} {medium 1 0 1 2 5000 5000} {long 0 2 0 2 5000 0}}

tcltest::test insights-loss-reasons {losses are grouped by termination, most first} -body {
	set report [::insights::aggregate [::scidb::test::insights::fixture] Me]
	dict get $report lossReasons
} -result {{normal 1} {{time forfeit} 1}}

# ----------------------------------------------------------------------
# helpers
# ----------------------------------------------------------------------

tcltest::test insights-result-for {the player's result depends on the colour} -body {
	list \
		[::insights::resultFor 1-0 white] \
		[::insights::resultFor 1-0 black] \
		[::insights::resultFor 0-1 white] \
		[::insights::resultFor 0-1 black] \
		[::insights::resultFor 1/2-1/2 white] \
		[::insights::resultFor * white] \
		[::insights::resultFor {} white]
} -result {win loss loss win draw {} {}}

tcltest::test insights-eco-family {the family is the first letter, A-E} -body {
	list \
		[::insights::ecoFamily C60] \
		[::insights::ecoFamily b01] \
		[::insights::ecoFamily {}] \
		[::insights::ecoFamily Z99]
} -result {C B ? ?}

tcltest::test insights-score {score and loss rate are hundredths of a percent} -body {
	list \
		[::insights::score100 1 0 0] \
		[::insights::score100 0 1 0] \
		[::insights::score100 0 0 1] \
		[::insights::score100 1 1 1] \
		[::insights::score100 0 0 0] \
		[::insights::lossRate100 2 0 1]
} -result {10000 5000 0 5000 0 3333}

tcltest::test insights-format {percent and record lines} -body {
	list \
		[::insights::formatPercent 8500] \
		[::insights::formatPercent 3333] \
		[::insights::formatWdl 2 2 2]
} -result {85.0 33.3 {+2 =2 -2}}

# ----------------------------------------------------------------------
# empty input
# ----------------------------------------------------------------------

tcltest::test insights-empty {no games gives an empty report, not an error} -body {
	set report [::insights::aggregate {} Me]
	list \
		[dict get $report games] \
		[dict get $report decided] \
		[dict get $report unknown] \
		[dict get $report overall] \
		[dict get $report families] \
		[dict get $report openings] \
		[dict get $report weakest] \
		[dict get $report bands] \
		[dict get $report years] \
		[dict get $report lengths] \
		[dict get $report lossReasons] \
		[dict exists $report white] \
		[dict exists $report black]
} -result {0 0 0 {overall 0 0 0 0 0 0} {} {} {} {} {} {} {} 0 0}

tcltest::test insights-no-match {a player in no game has no colour rows} -body {
	set records [list [::scidb::test::insights::rec A B 1-0 C60 {Ruy Lopez} 2000 2000 2020.01.01 60 normal]]
	set report [::insights::aggregate $records Nobody]
	list [dict get $report games] [dict exists $report white] [dict exists $report black]
} -result {0 0 0}

# ----------------------------------------------------------------------
# the player menu entry
# ----------------------------------------------------------------------

tcltest::test insights-menu-entry {the player context menu offers the insights window} -setup {
	set m .insightsTestMenu
	catch { destroy $m }
	menu $m -tearoff 0
} -body {
	::application::database::player::addInsightsMenuEntry $m .application /nonexistent Normal 0
	set last [$m index end]
	list [expr {$last >= 0}] [string trim [$m entrycget $last -label]]
} -cleanup {
	catch { destroy $m }
} -result {1 Insights...}

# ----------------------------------------------------------------------
# a small real database for the collector and the window (no network)
# ----------------------------------------------------------------------

proc ::scidb::test::insights::openFixtureDatabase {} {
	set Dir $::scidb::test::insights::Dir
	file delete -force $Dir
	file mkdir $Dir
	set file [file join $Dir insights.pgn]
	set fh [open $file w]
	fconfigure $fh -encoding utf-8
	foreach {white black result eco} {
		{Me}   {Ann}  1-0     C60
		{Me}   {Bob}  0-1     B01
		{Carl} {Me}   1/2-1/2 A00
	} {
		puts $fh "\[Event \"Insights suite\"\]\n\[Site \"X\"\]\n\[Date \"2021.01.01\"\]\n\[Round \"1\"\]"
		puts $fh "\[White \"$white\"\]\n\[Black \"$black\"\]\n\[Result \"$result\"\]\n\[ECO \"$eco\"\]\n"
		puts $fh "\n1. e4 e5 2. Nf3 *\n"
	}
	close $fh
	::scidb::db::open $file ::scidb::test::insights::nop {} ::scidb::test::insights::nop {}
	set index -1
	for {set i 0} {$i < [::scidb::db::count players $file Normal]} {incr i} {
		if {[lindex [::scidb::db::get playerKey $file Normal $i] 0] eq "Me"} {
			set index $i
			break
		}
	}
	return [list $file $index]
}

proc ::scidb::test::insights::closeFixtureDatabase {file} {
	catch { ::scidb::db::close $file }
	file delete -force $::scidb::test::insights::Dir
	return
}

proc ::scidb::test::insights::wait {cond {ms 500}} {
	set n 0
	while {![uplevel #1 [list expr $cond]] && $n < $ms} {
		update
		after 10
		incr n
	}
	return [uplevel #1 [list expr $cond]]
}

tcltest::test insights-collect {the collector streams the player's headers} -setup {
	lassign [::scidb::test::insights::openFixtureDatabase] base index
	set ::scidb::test::insights::Base $base
	set ::scidb::test::insights::Index $index
	unset -nocomplain ::scidb::test::insights::Records ::scidb::test::insights::Result
} -body {
	::insights::collect $::scidb::test::insights::Base Normal \
		$::scidb::test::insights::Index \
		-done [list ::scidb::test::insights::CollectDone]
	::scidb::test::insights::wait {[info exists ::scidb::test::insights::Records]}
	set records $::scidb::test::insights::Records
	set report [::insights::aggregate $records Me]
	list \
		[dict get $report games] \
		[dict get $report overall] \
		[lsort [lmap r $records {lindex $r 3}]] \
		[dict get $::scidb::test::insights::Result ok]
} -cleanup {
	unset -nocomplain ::scidb::test::insights::Records ::scidb::test::insights::Result
	::scidb::test::insights::closeFixtureDatabase $::scidb::test::insights::Base
} -result {3 {overall 1 1 1 3 5000 3333} {A00 B01 C60} 1}

tcltest::test insights-window {the window builds and fills its sections} -setup {
	lassign [::scidb::test::insights::openFixtureDatabase] base index
	set ::scidb::test::insights::Base $base
	set ::scidb::test::insights::Index $index
} -body {
	set dlg [::insights::show .application $::scidb::test::insights::Base Normal \
		$::scidb::test::insights::Index]
	set n 0
	while {![dict exists $::insights::Data($dlg,result) games] && $n < 500} {
		update
		after 10
		incr n
	}
	set openings $::insights::Data($dlg,trees:openings)
	set bands $::insights::Data($dlg,trees:bands)
	set reasons $::insights::Data($dlg,trees:reasons)
	set report $::insights::Data($dlg,result)
	list \
		[winfo exists $dlg] \
		[dict get $report games] \
		[llength [$openings children {}]] \
		[llength [$bands children {}]] \
		[llength [$reasons children {}]] \
		[string length $::insights::Data($dlg,scoreText)] \
		[expr {[string first "%" $::insights::Data($dlg,scoreText)] > 0}]
} -cleanup {
	catch { destroy [::insights::DialogName $::scidb::test::insights::Base Normal $::scidb::test::insights::Index] }
	::scidb::test::insights::closeFixtureDatabase $::scidb::test::insights::Base
} -result {1 3 3 1 1 5 1}

tcltest::cleanupTests
return
