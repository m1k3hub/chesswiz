# ======================================================================
# Scidb App Test — positions like the one on the board
# (tcl/ai-similar-positions.tcl): the script for each aspect, tolerance
# and colour choice matches the fixture positions it should, and only
# those.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::simpos {
	variable Fixture [file join [file dirname [file normalize [info script]]] tmp-app simpos.pgn]
	# game 0 is the target: the pawn structure the searches start from. Game 3
# has it with the colours reversed, which also differs from it by one pawn
# per side (d4/e3, e6/d5), so a tolerance of 1 finds it as well.
	variable Target {6k1/pp3ppp/2p1p3/8/3P4/2P5/PP3PPP/6K1 w - - 0 1}
	variable WithKnights {6k1/pp3ppp/2p1pn2/8/3P4/2P2N2/PP3PPP/6K1 w - - 0 1}
	variable Games {
		{6k1/pp3ppp/2p1p3/8/3P4/2P5/PP3PPP/6K1 w - - 0 1} {1. Kf1 *}
		{r5k1/pp3ppp/2p1p3/8/3P4/2P5/PP3PPP/R5K1 w - - 0 1} {1. Kf1 *}
		{6k1/pp3ppp/2p1p3/8/3P4/2P4P/PP3PP1/6K1 w - - 0 1} {1. Kf1 *}
		{6k1/pp3ppp/2p5/3p4/8/2P1P3/PP3PPP/6K1 w - - 0 1} {1. Kf1 *}
		{} {1. e4 *}
		{6k1/pp3ppp/2p1pn2/8/3P4/2P2N2/PP3PPP/6K1 w - - 0 1} {1. Kf1 *}
		{6k1/pp3ppp/2p1p3/4n3/3P4/2P2N2/PP3PPP/6K1 w - - 0 1} {1. Kf1 *}
		{6k1/pp3ppp/2p1p3/8/3P4/2P3PP/PP3P2/6K1 w - - 0 1} {1. Kf1 *}
	}
}

proc ::scidb::test::simpos::nop {args} { return 0 }

proc ::scidb::test::simpos::openFixture {} {
	variable Fixture
	variable Games
	file mkdir [file dirname $Fixture]
	set fh [open $Fixture w]
	set n 0
	foreach {fen moves} $Games {
		puts $fh "\[Event \"S\"\]\n\[Site \"X\"\]\n\[Date \"2020.01.01\"\]\n\[Round \"[incr n]\"\]"
		puts $fh "\[White \"W\"\]\n\[Black \"B\"\]\n\[Result \"*\"\]"
		if {$fen ne ""} { puts $fh "\[SetUp \"1\"\]\n\[FEN \"$fen\"\]" }
		puts $fh "\n$moves\n"
	}
	close $fh
	::scidb::db::open $Fixture ::scidb::test::simpos::nop {} ::scidb::test::simpos::nop {}
}

proc ::scidb::test::simpos::closeFixture {} {
	variable Fixture
	catch { ::scidb::db::close $Fixture }
	catch { file delete $Fixture }
}

# The fixture games the script for <fen> with <args> matches.
proc ::scidb::test::simpos::games {fen args} {
	variable Fixture
	set script [::ai::similar::script $fen {*}$args]
	set ::scidb::test::simpos::Result {}
	::scidb::cql6::search $Fixture Normal $script -compact 1 -command {set ::scidb::test::simpos::Result}
	set timer [after 20000 {set ::scidb::test::simpos::Result {ok 0 error timeout}}]
	vwait ::scidb::test::simpos::Result
	after cancel $timer
	set r $::scidb::test::simpos::Result
	if {![dict get $r ok]} { return "error: [dict get $r error]\n$script" }
	return [lsort -integer -unique [lmap {g p} [dict get $r matches] { set g }]]
}

tcltest::testConstraint cql6 [expr {[llength [info commands ::scidb::cql6::search]]
	&& [::scidb::cql6::version] ne "cql6 stub 6.2"}]

tcltest::test simpos-matches {each aspect, tolerance and colour choice finds the right positions} -constraints cql6 -setup {
	::scidb::test::simpos::openFixture
} -body {
	set t $::scidb::test::simpos::Target
	set k $::scidb::test::simpos::WithKnights
	list \
		[::scidb::test::simpos::games $t] \
		[::scidb::test::simpos::games $t -aspects pawns] \
		[::scidb::test::simpos::games $t -aspects pawns -tolerance 1] \
		[::scidb::test::simpos::games $t -aspects pawns -colours both] \
		[::scidb::test::simpos::games $t -aspects material] \
		[::scidb::test::simpos::games $k -aspects pieces] \
		[::scidb::test::simpos::games $k -aspects {pawns material}]
} -cleanup {
	::scidb::test::simpos::closeFixture
} -result {0 {0 1 5 6} {0 1 2 3 5 6} {0 1 3 5 6} {0 2 3 7} 5 {5 6}}

tcltest::test simpos-tolerance-elsewhere {tolerance counts pawns standing elsewhere, not just the total} -constraints cql6 -setup {
	::scidb::test::simpos::openFixture
} -body {
	# game 7 has g3 and h3 for g2 and h2: two of its seven white pawns stand
	# off the target's squares, so tolerance 1 misses it and 2 finds it
	list [expr {7 in [::scidb::test::simpos::games $::scidb::test::simpos::Target -aspects pawns -tolerance 1]}] \
		[expr {7 in [::scidb::test::simpos::games $::scidb::test::simpos::Target -aspects pawns -tolerance 2]}]
} -cleanup {
	::scidb::test::simpos::closeFixture
} -result {0 1}

tcltest::test simpos-tomove {-tomove adds the side to move} -body {
	list [string match "*\twtm*" [::ai::similar::script $::scidb::test::simpos::Target -tomove 1]] \
		[string match "*tm*" [::ai::similar::script $::scidb::test::simpos::Target]]
} -result {1 0}

tcltest::test simpos-empty-side {a side without pawns still gives valid terms} -body {
	set script [::ai::similar::script {6k1/8/8/8/8/8/PP6/6K1 w - - 0 1} -aspects pawns -tolerance 1]
	list [expr {[string first "#p <= 1" $script] >= 0}] [expr {[string first "#P\[a2,b2\] >= 1" $script] >= 0}] \
		[expr {[string first "#P <= #P\[a2,b2\] + 1" $script] >= 0}]
} -result {1 1 1}

tcltest::test simpos-describe {the sentence names what is matched} -body {
	::ai::similar::describe $::scidb::test::simpos::Target -aspects {pawns material} -tolerance 1 -colours both
} -result {the same pawn structure (White: a2 b2 c3 d4 f2 g2 h2; Black: a7 b7 c6 e6 f7 g7 h7), at most 1 pawn per side elsewhere, and the same material, or the same with the colours reversed}

tcltest::test simpos-errors {a bad FEN or option is refused with a plain message} -body {
	list [catch { ::ai::similar::script {8/8 w} } e1] [string match "a FEN board has 8 ranks*" $e1] \
		[catch { ::ai::similar::script $::scidb::test::simpos::Target -aspects kings } e2] [string match "no such aspect*" $e2] \
		[catch { ::ai::similar::script {8/8/8/8/8/8/8/8 w - - 0 1} } e3] [string match "*one white and one black king*" $e3]
} -result {1 1 1 1 1 1}

tcltest::cleanupTests
