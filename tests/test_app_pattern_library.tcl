# ======================================================================
# Scidb App Test Suite - the CQL 6.2-only part of the pattern library
# (tcl/ai-search.tcl Patterns6: mates, tactics, structures and endgames
# from the instructional canon, Western and Soviet). Each pattern must match the positions
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
		epaulette_mate must {3rkr2/8/4Q3/8/8/8/8/4K3 b - - 0 1} {*}
		epaulette_mate miss {6k1/5ppp/8/8/8/8/8/3R2K1 w - - 0 1} {1. Rd8# *}
		queen_pawn_mate must {5rk1/5p2/6P1/8/8/8/8/6KQ w - - 0 1} {1. Qh7# *}
		queen_pawn_mate must {6k1/5p1p/5PpQ/8/8/8/8/6K1 w - - 0 1} {1. Qg7# *}
		queen_pawn_mate miss {3rkr2/8/4Q3/8/8/8/8/4K3 b - - 0 1} {*}
		skewer must {4q3/8/8/4k3/8/8/8/4R1K1 b - - 0 1} {*}
		skewer must {7q/8/5k2/8/3B4/8/8/6K1 b - - 0 1} {*}
		skewer miss {3q4/8/8/4k3/8/8/8/4R1K1 b - - 0 1} {*}
		discovered_check must {4k3/8/8/8/8/4N3/8/4R1K1 w - - 0 1} {1. Nd5+ Kd7 *}
		discovered_check miss {4k3/8/8/8/8/2N5/8/3R2K1 w - - 0 1} {1. Nd5 Kf7 *}
		discovered_check miss {4k3/8/8/8/8/8/8/R5K1 w - - 0 1} {1. Ra8+ Kd7 *}
		alekhines_gun must {4k3/8/8/8/8/3R4/3R4/3QK3 w - - 0 1} {1. Kf1 *}
		alekhines_gun miss {4k3/8/8/8/8/3R4/3Q4/3RK3 w - - 0 1} {1. Kf1 *}
		double_bishop_sacrifice must {r4rk1/5ppp/8/8/8/3B4/1B3PPP/3Q1RK1 w - - 0 1} {1. Bxh7+ Kxh7 2. Qh5+ Kg8 3. Bxg7 Kxg7 *}
		double_bishop_sacrifice miss {r4rk1/5ppp/8/8/8/3B4/1B3PPP/3Q1RK1 w - - 0 1} {1. Bxh7+ Kxh7 2. Qh5+ Kg8 3. Qh4 *}
		minority_attack must {4k3/pp3ppp/2p5/1P1p4/3P4/4P3/P4PPP/4K3 b - - 0 1} {1... Kd7 *}
		minority_attack miss {4k3/pp3ppp/2p5/3p4/3P4/4P3/PP3PPP/4K3 b - - 0 1} {1... Kd7 *}
		hedgehog must {4k3/5ppp/pp1pp3/8/2P1P3/8/PP3PPP/4K3 b - - 0 1} {1... Kd7 *}
		hedgehog miss {4k3/pp2pppp/3p4/8/2P1P3/8/PP3PPP/4K3 b - - 0 1} {1... Kd7 *}
		protected_passed_pawn must {4k3/8/8/3P4/4P3/8/8/4K3 b - - 0 1} {1... Kf7 *}
		protected_passed_pawn miss {4k3/8/8/3P4/8/8/8/4K3 b - - 0 1} {1... Kf7 *}
		weakened_fianchetto must {3qk3/8/8/8/8/6P1/5P1P/6K1 w - - 0 1} {*}
		weakened_fianchetto miss {3qk3/8/8/8/8/6P1/5P1P/5BK1 w - - 0 1} {*}
		pawn_fork must {4k3/8/2n1b3/8/3P4/8/8/4K3 w - - 0 1} {1. d5 Kd7 *}
		pawn_fork miss {4k3/8/2n5/8/3P4/8/8/4K3 w - - 0 1} {1. d5 Kd7 *}
		legals_mate must {rn1q1bnr/ppp1kB1p/3p2p1/3NN3/4P3/8/PPPP1PPP/R1BbK2R b KQ - 0 7} {*}
		legals_mate miss {6k1/5ppp/8/8/8/8/8/3R2K1 w - - 0 1} {1. Rd8# *}
		philidor_position must {4k3/8/r7/4P3/4K3/8/8/1R6 b - - 0 1} {1... Kd7 *}
		philidor_position miss {4k3/r7/8/4P3/4K3/8/8/1R6 b - - 0 1} {1... Kd7 *}
		vancura_position must {R7/6k1/P4r2/8/8/8/8/6K1 w - - 0 1} {1. Kg2 *}
		vancura_position miss {R7/6k1/P7/8/8/8/5r2/6K1 w - - 0 1} {1. Kh1 *}
		backward_pawn must {4k3/pp3ppp/3p4/2P1p3/4P3/8/PP3PPP/4K3 w - - 0 1} {1. Kd2 *}
		backward_pawn miss {4k3/pp3ppp/2pp4/4p3/4P3/8/PP3PPP/4K3 w - - 0 1} {1. Kd2 *}
		bad_bishop must {4k3/8/4p3/3pPp2/3P1P2/2P5/3B4/4K3 b - - 0 1} {1... Kd7 *}
		bad_bishop miss {4k3/8/4p3/3pPp2/3P1P2/2P5/8/4KB2 b - - 0 1} {1... Kd7 *}
		closed_center must {4k3/8/4p3/3pP3/3P4/8/8/4K3 b - - 0 1} {1... Kd7 *}
		closed_center miss {4k3/8/4p3/3p4/3P4/8/8/4K3 b - - 0 1} {1... Kd7 *}
		blackburne_mate must {5rk1/5p1B/8/6N1/8/8/1B6/6K1 b - - 0 1} {*}
		blackburne_mate miss {5rk1/5p1B/8/6N1/8/8/1Q6/6K1 b - - 0 1} {*}
		trebuchet must {8/8/8/3Kp3/4Pk2/8/8/8 w - - 0 1} {*}
		trebuchet miss {8/8/8/K3p3/4P3/8/8/k7 w - - 0 1} {*}
		boleslavsky_hole must {r1bq1rk1/pp3ppp/2np1n2/4p3/4P3/1NN5/PPP2PPP/R1BQ1RK1 w - - 0 1} {1. Kh1 *}
		boleslavsky_hole miss {r1bq1rk1/pp3ppp/2np1n2/2p1p3/4P3/1NN5/PPP2PPP/R1BQ1RK1 w - - 0 1} {1. Kh1 *}
		botvinnik_formation must {r1bq1rk1/ppp2ppp/2np1n2/4p3/2P1P3/2NP2P1/PP3PBP/R1BQK1NR w KQ - 0 1} {1. Kf1 *}
		botvinnik_formation miss {r1bq1rk1/ppp2ppp/2np1n2/4p3/2P1P3/2NP4/PP3PPP/R1BQKBNR w KQ - 0 1} {1. Be2 *}
		rook_behind_passed_pawn must {6k1/8/P7/8/8/R7/8/6K1 w - - 0 1} {1. Kg2 *}
		rook_behind_passed_pawn miss {6k1/R7/P7/8/8/8/8/6K1 w - - 0 1} {1. Kg2 *}
		pin_attacked_by_pawn must {4k3/8/8/4n3/8/3P4/8/4R1K1 w - - 0 1} {1. d4 Kd7 *}
		pin_attacked_by_pawn miss {4k3/8/8/4n3/8/3P4/8/4R1K1 w - - 0 1} {1. Kf2 Kd7 *}
		double_attack_loose must {7k/8/8/1n3b2/8/8/8/3QK3 w - - 0 1} {1. Qd3 *}
		double_attack_loose miss {7k/8/2p1p3/1n3b2/8/8/8/3QK3 w - - 0 1} {1. Qd3 *}
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
		{an epaulette mate}
		{Lolli's mate}
		{skewers}
		{discovered checks by White}
		{the Lasker-Bauer double bishop sacrifice}
		{Alekhine's gun}
		{minority attack in the Carlsbad}
		{hedgehog structures}
		{protected passed pawns}
		{weakened fianchetto}
		{pawn forks}
		{Legal's mate}
		{Blackburne's mate}
		{pin and win}
		{double attacks on loose pieces}
		{the Philidor position}
		{Vancura position}
		{backward pawns}
		{bad bishop endings}
		{closed centre}
		{trebuchet}
		{the Boleslavsky hole}
		{Botvinnik formation}
		{rook behind the passed pawn}
		{smothered mates}
		{rook endings}
	} { dict get [::ai::search::extract $request] pattern }
} -result {back_rank_mate boden_mate anastasia_mate arabian_mate knight_fork greek_gift rook_seventh doubled_rooks_seventh knight_outpost hanging_pawns carlsbad maroczy_bind stonewall queen_vs_rook wrong_bishop lucena epaulette_mate queen_pawn_mate skewer discovered_check double_bishop_sacrifice alekhines_gun minority_attack hedgehog protected_passed_pawn weakened_fianchetto pawn_fork legals_mate blackburne_mate pin_attacked_by_pawn double_attack_loose philidor_position vancura_position backward_pawn bad_bishop closed_center trebuchet boleslavsky_hole botvinnik_formation rook_behind_passed_pawn smothered_mate rook_endgame}

tcltest::test plib-labels {every pattern has a label, a description, aliases and a known kind} -body {
	lmap id [::ai::search::patternIds] {
		set p [::ai::search::pattern $id]
		if {[dict get $p label] ne "" && [dict get $p description] ne "" && [dict get $p kind] in {event structure phase}
		 && [string match "cql()*" [::ai::search::pattern6 $id]]} continue
		set id
	}
} -result {}

tcltest::test plib-themes {the annotator's move themes name the new mates and tactics} -constraints cql6 -body {
	lmap {fen san} {
		{6k1/5ppp/8/8/8/8/8/3R2K1 w - - 0 1} Rd8#
		{7k/R7/5N2/8/8/8/8/6K1 w - - 0 1} Rh7#
		{r1bq1rk1/pppn1ppp/4p3/3pP3/1b1P4/2NB1N2/PPP2PPP/R2QK2R w KQ - 0 1} Bxh7+
		{4k3/8/8/8/8/4N3/8/4R1K1 w - - 0 1} Nd5+
		{q3k3/8/8/1N6/8/8/8/4K3 w - - 0 1} Nc7+
		{4k3/8/2n1b3/8/3P4/8/8/4K3 w - - 0 1} d5
		{4k3/8/8/8/8/8/8/4R1K1 w - - 0 1} Kf2
	} { dict get [::ai::cql::themes $fen $san] events }
} -result {back_rank_mate arabian_mate greek_gift discovered_check knight_fork {pawn_fork double_attack_loose} {}}

tcltest::test plib-structures {the structures of a position include the new ones (these are pawn endings; a hedgehog is also a Maroczy bind)} -constraints cql6 -body {
	lmap fen {
		{4k3/pp3ppp/2p5/3p4/3P4/4P3/PP3PPP/4K3 b - - 0 1}
		{4k3/5ppp/pp1pp3/8/2P1P3/8/PP3PPP/4K3 b - - 0 1}
		{3K4/3P2k1/8/8/8/8/2r5/4R3 w - - 0 1}
	} { ::ai::search::structures $fen }
} -result {{pawn_endgame carlsbad} {pawn_endgame maroczy_bind hedgehog} {rook_endgame lucena}}

tcltest::testConstraint engine [expr {[llength [info commands ::ai::engine::available]] && [::ai::engine::available]}]

# A back-rank mate (matched after the move) and a discovered check that
# wins the queen (matched before it): both puzzles must be the right move.
tcltest::test plib-training {training sets take the new patterns, and the right move for each} -constraints {cql6 engine} -setup {
	set ::scidb::test::plib::TrainFixture [file join [file dirname $::scidb::test::plib::Fixture] plib-train-[pid].pgn]
	set ::scidb::test::plib::TrainFile [file join [file dirname $::scidb::test::plib::Fixture] plib-train-[pid]-out.pgn]
	set fh [open $::scidb::test::plib::TrainFixture w]
	set n 0
	foreach {fen moves} {
		{6k1/5ppp/8/8/8/8/8/3R2K1 w - - 0 1} {1. Rd8# 1-0}
		{4k3/2q5/8/8/8/4N3/8/4R1K1 w - - 0 1} {1. Nd5+ Kd8 2. Nxc7 *}
	} {
		puts $fh "\[Event \"T\"\]\n\[Site \"X\"\]\n\[Date \"2020.01.0[incr n]\"\]\n\[Round \"$n\"\]"
		puts $fh "\[White \"W\"\]\n\[Black \"B\"\]\n\[Result \"*\"\]\n\[SetUp \"1\"\]\n\[FEN \"$fen\"\]\n\n$moves\n"
	}
	close $fh
	::scidb::db::open $::scidb::test::plib::TrainFixture ::scidb::test::plib::nop {} ::scidb::test::plib::nop {}
	set saved [info body ::application::assistant::ActiveBase]
	proc ::application::assistant::ActiveBase {} { return [list $::scidb::test::plib::TrainFixture Normal] }
} -body {
	set ::scidb::test::plib::Done {}
	::ai::cql::training . -patterns {back_rank_mate discovered_check} -depth 8 \
		-file $::scidb::test::plib::TrainFile -done {set ::scidb::test::plib::Done}
	set timer [after 120000 {set ::scidb::test::plib::Done timeout}]
	vwait ::scidb::test::plib::Done
	after cancel $timer
	set pgn ""
	catch { set fh [open $::scidb::test::plib::TrainFile]; set pgn [read $fh]; close $fh }
	list [dict get $::scidb::test::plib::Done puzzles] \
		[string match "*find the back-rank mate*1. Rd8 *" $pgn] \
		[string match "*find the discovered check*1. Nd5 *" $pgn]
} -cleanup {
	proc ::application::assistant::ActiveBase {} $saved
	catch { ::scidb::db::close $::scidb::test::plib::TrainFixture }
	catch { file delete $::scidb::test::plib::TrainFixture $::scidb::test::plib::TrainFile }
} -result {2 1 1}

tcltest::cleanupTests
