# ======================================================================
# Scidb App Test Suite - the CQL 6.2-only part of the pattern library
# (tcl/ai-search.tcl Patterns6: mates, tactics, structures and endgames
# from the instructional canon). Each pattern must match the positions
# that show it and miss the near misses; its aliases must name it in a
# plain-language request.
# ======================================================================
package require Tcl 8.6
package require tcltest 2.5

namespace eval ::scidb::test::plib {
	variable Fixture [file join [file dirname [file normalize [info script]]] tmp-app plib-[pid].pgn]
	# id must|miss FEN moves
	variable Positions {
		back_rank_mate must {6k1/5ppp/8/8/8/8/8/3R2K1 w - - 0 1} {1. Rd8# *}
		back_rank_mate miss {6k1/5p1p/5PpQ/8/8/8/8/6K1 w - - 0 1} {1. Qg7# *}
		boden_mate must {2kr4/p2n4/B7/8/5B2/8/8/6K1 b - - 0 1} {*}
		boden_mate miss {2kr4/p2n4/B7/8/5Q2/8/8/6K1 b - - 0 1} {*}
		anastasia_mate must {5r2/4N1pk/8/7R/8/8/8/6K1 b - - 0 1} {*}
		anastasia_mate miss {7k/7R/5N2/8/8/8/8/6K1 b - - 0 1} {*}
		arabian_mate must {7k/7R/5N2/8/8/8/8/6K1 b - - 0 1} {*}
		arabian_mate miss {5r2/4N1pk/8/7R/8/8/8/6K1 b - - 0 1} {*}
		knight_fork must {q3k3/2N5/8/8/8/8/8/4K3 b - - 0 1} {1... Kd8 *}
		knight_fork must {r3k3/2N5/8/8/8/8/8/4K3 b - - 0 1} {1... Kd7 *}
		knight_fork miss {q3k3/8/1N3N2/8/8/8/8/4K3 b - - 0 1} {1... Kd8 *}
		greek_gift must {r1bq1rk1/pppn1ppp/4p3/3pP3/1b1P4/2NB1N2/PPP2PPP/R2QK2R w KQ - 0 1} {1. Bxh7+ Kxh7 *}
		greek_gift miss {r1bq1rk1/pppn1ppp/4p3/3pP3/1b1P4/2NB1N2/PPP2PPP/R2QK2R w KQ - 0 1} {1. O-O h6 *}
		rook_seventh must {4k3/R7/8/8/8/8/8/4K3 b - - 0 1} {1... Kf8 *}
		rook_seventh miss {8/R4pk1/8/8/8/8/8/4K3 b - - 0 1} {1... Kg6 *}
		doubled_rooks_seventh must {4k3/R6R/8/8/8/8/8/4K3 b - - 0 1} {1... Kf8 *}
		doubled_rooks_seventh miss {4k3/R7/8/8/8/8/8/4K3 b - - 0 1} {1... Kf8 *}
		knight_outpost must {4k3/8/8/3N4/4P3/8/8/4K3 b - - 0 1} {1... Kf7 *}
		knight_outpost miss {4k3/8/8/3N4/8/8/8/4K3 b - - 0 1} {1... Kf7 *}
		knight_outpost miss {4k3/2p5/8/3N4/4P3/8/8/4K3 b - - 0 1} {1... Kf7 *}
		hanging_pawns must {4k3/pp3ppp/8/8/2PP4/8/P4PPP/4K3 b - - 0 1} {1... Kd7 *}
		hanging_pawns miss {4k3/pp3ppp/8/3p4/2PP4/8/P4PPP/4K3 b - - 0 1} {1... Kd7 *}
		carlsbad must {4k3/pp3ppp/2p5/3p4/3P4/4P3/PP3PPP/4K3 b - - 0 1} {1... Kd7 *}
		carlsbad miss {4k3/pp3ppp/2p5/3p4/2PP4/4P3/P4PPP/4K3 b - - 0 1} {1... Kd7 *}
		maroczy_bind must {4k3/pp2pppp/3p4/8/2P1P3/8/PP3PPP/4K3 b - - 0 1} {1... Kd7 *}
		maroczy_bind miss {4k3/pp2pppp/3p4/8/2PPP3/8/PP3PPP/4K3 b - - 0 1} {1... Kd7 *}
		stonewall must {4k3/pp3ppp/8/8/3P1P2/2P1P3/PP4PP/4K3 b - - 0 1} {1... Kd7 *}
		stonewall must {4k3/pp4pp/2p1p3/3p1p2/8/8/PP3PPP/4K3 w - - 0 1} {1. Kd2 *}
		stonewall miss {4k3/pp3ppp/8/8/3P4/2P1P3/PP3PPP/4K3 b - - 0 1} {1... Kd7 *}
		queen_vs_rook must {4k3/8/8/8/8/8/r7/Q3K3 w - - 0 1} {1. Kd1 *}
		queen_vs_rook miss {4k3/8/8/8/8/8/r6P/Q3K3 w - - 0 1} {1. Kd1 *}
		wrong_bishop must {7k/8/8/8/8/8/P7/2B1K3 b - - 0 1} {1... Kg7 *}
		wrong_bishop must {k7/8/8/8/8/8/7P/4KB2 b - - 0 1} {1... Kb7 *}
		wrong_bishop must {4kb2/7p/8/8/8/8/8/K7 w - - 0 1} {1. Ka2 *}
		wrong_bishop miss {7k/8/8/8/8/8/P7/4KB2 b - - 0 1} {1... Kg7 *}
		wrong_bishop miss {4kb2/p7/8/8/8/8/8/7K w - - 0 1} {1. Kg2 *}
		lucena must {3K4/3P2k1/8/8/8/8/2r5/4R3 w - - 0 1} {*}
		lucena must {4r3/2R5/8/8/8/8/3p2K1/3k4 b - - 0 1} {*}
		lucena miss {3K4/3P4/4k3/8/8/8/2r5/R7 w - - 0 1} {*}
		lucena miss {8/6k1/3P4/3K4/8/8/2r5/4R3 w - - 0 1} {*}
	}
}

proc ::scidb::test::plib::nop {args} { return 0 }

proc ::scidb::test::plib::openFixture {} {
	variable Fixture
	variable Positions
	file mkdir [file dirname $Fixture]
	set fh [open $Fixture w]
	set n 0
	set expect {}
	foreach {id kind fen moves} $Positions {
		puts $fh "\[Event \"$id $kind\"\]\n\[Site \"X\"\]\n\[Date \"2020.01.01\"\]\n\[Round \"[incr n]\"\]"
		puts $fh "\[White \"W\"\]\n\[Black \"B\"\]\n\[Result \"*\"\]\n\[SetUp \"1\"\]\n\[FEN \"$fen\"\]\n\n$moves\n"
		dict lappend expect $id [list $kind [expr {$n - 1}]]
	}
	close $fh
	::scidb::db::open $Fixture ::scidb::test::plib::nop {} ::scidb::test::plib::nop {}
	return $expect
}

# id -> the games its template matches
proc ::scidb::test::plib::matches {} {
	variable Fixture
	set ids [::ai::search::patternIds]
	set scripts [lmap id $ids { ::ai::search::pattern6 $id }]
	unset -nocomplain ::scidb::test::plib::Result
	::scidb::cql6::search $Fixture Normal [lindex $scripts 0] -scripts [lrange $scripts 1 end] \
		-compact 1 -command {set ::scidb::test::plib::Result}
	set timer [after 30000 {set ::scidb::test::plib::Result {ok 0 error timeout}}]
	vwait ::scidb::test::plib::Result
	after cancel $timer
	set r $::scidb::test::plib::Result
	if {![dict get $r ok]} { error [dict get $r error] }
	set out [dict create]
	foreach id $ids { dict set out $id {} }
	foreach {game ply script} [dict get $r matches] { dict lappend out [lindex $ids $script] $game }
	return $out
}

tcltest::testConstraint cql6 [expr {[llength [info commands ::scidb::cql6::search]]
	&& [::scidb::cql6::version] ne "cql6 stub 6.2"}]

tcltest::test plib-fixtures {every CQL 6.2-only pattern matches its positions and misses the near misses} -constraints cql6 -setup {
	set expect [::scidb::test::plib::openFixture]
} -body {
	set wrong {}
	if {[::scidb::db::count games $::scidb::test::plib::Fixture Normal] != [llength $::scidb::test::plib::Positions] / 4} {
		lappend wrong "a fixture game did not load"
	}
	set got [::scidb::test::plib::matches]
	dict for {id cases} $expect {
		foreach pair $cases {
			lassign $pair kind game
			set hit [expr {$game in [dict get $got $id]}]
			if {($kind eq "must") != $hit} { lappend wrong "$id: $kind game [expr {$game + 1}]" }
		}
	}
	join $wrong \n
} -cleanup {
	catch { ::scidb::db::close $::scidb::test::plib::Fixture }
	catch { file delete $::scidb::test::plib::Fixture }
} -result {}

tcltest::test plib-coverage {every CQL 6.2-only pattern has a position it must match and one it must miss} -body {
	set kinds [dict create]
	foreach {id kind fen moves} $::scidb::test::plib::Positions { dict lappend kinds $id $kind }
	lmap id [::ai::search::patternIds] {
		if {[dict get [::ai::search::pattern $id] cql] ne ""} continue
		if {[dict exists $kinds $id] && "must" in [dict get $kinds $id] && "miss" in [dict get $kinds $id]} continue
		set id
	}
} -result {}

tcltest::test plib-aliases {a request naming a pattern selects it} -body {
	lmap request {
		{back-rank mates since 2010}
		{Boden's mate}
		{games with Anastasia's mate}
		{an Arabian mate}
		{knight forks in rapid games}
		{the Greek gift sacrifice}
		{rook on the seventh rank}
		{doubled rooks on the 7th}
		{knight outposts}
		{hanging pawns}
		{Carlsbad structure games}
		{the Maroczy bind}
		{Stonewall Dutch}
		{queen vs rook endings}
		{wrong-coloured bishop draws}
		{the Lucena position}
		{smothered mates}
		{rook endings}
	} { dict get [::ai::search::extract $request] pattern }
} -result {back_rank_mate boden_mate anastasia_mate arabian_mate knight_fork greek_gift rook_seventh doubled_rooks_seventh knight_outpost hanging_pawns carlsbad maroczy_bind stonewall queen_vs_rook wrong_bishop lucena smothered_mate rook_endgame}

tcltest::test plib-labels {every pattern has a label, a description, aliases and a known kind} -body {
	lmap id [::ai::search::patternIds] {
		set p [::ai::search::pattern $id]
		if {[dict get $p label] ne "" && [dict get $p description] ne "" && [dict get $p kind] in {event structure}
		 && [string match "cql()*" [::ai::search::pattern6 $id]]} continue
		set id
	}
} -result {}

tcltest::cleanupTests
