# ======================================================================
# Scidb App Test — the CQL 6.2 reference card's examples
# (tcl/ai-cql-reference.tcl). Every example must parse, and where a
# fixture exists it must match the position that shows the request and
# miss the one that does not: a wrong example would teach the model a
# wrong script.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::cqlref {
	variable Fixture [file join [file dirname [file normalize [info script]]] tmp-app cqlref.pgn]

	# id must|miss FEN moves
	variable Positions {
		knight_fork_kq must {q3k3/2N5/8/8/8/8/8/4K3 b - - 0 1} {1... Kd8 *}
		knight_fork_kq miss {q3k3/8/1N3N2/8/8/8/8/4K3 b - - 0 1} {1... Kd8 *}
		knight_fork_kr must {r3k3/2N5/8/8/8/8/8/4K3 b - - 0 1} {1... Kd7 *}
		knight_fork_kr miss {r3k3/8/1N3N2/8/8/8/8/4K3 b - - 0 1} {1... Kd8 *}
		royal_fork must {2q1k3/1r6/3N4/8/8/8/8/4K3 b - - 0 1} {1... Kf8 *}
		royal_fork miss {2q1k3/8/3N4/8/8/8/8/4K3 b - - 0 1} {1... Kf8 *}
		pawn_fork must {4k3/8/3n1r2/4P3/8/8/8/4K3 b - - 0 1} {1... Kd7 *}
		pawn_fork miss {4k3/8/3n1r2/2P3P1/8/8/8/4K3 b - - 0 1} {1... Kd7 *}
		queen_fork_kr must {4k3/8/8/8/r3Q3/8/8/4K3 b - - 0 1} {1... Kd7 *}
		queen_fork_kr miss {4k3/8/8/8/r3Q3/2n5/8/4K3 b - - 0 1} {1... Kd7 *}
		double_check must {4k3/8/8/1B6/8/8/8/4R1K1 b - - 0 1} {1... Kf7 *}
		double_check miss {4k3/8/8/8/8/8/8/4R1K1 b - - 0 1} {1... Kf7 *}
		knight_mate must {6rk/5Npp/8/8/8/8/8/6K1 b - - 0 1} {*}
		knight_mate miss {6k1/5ppp/8/8/8/8/8/3R2K1 w - - 0 1} {1. Rd8# *}
		smothered_mate must {6rk/5Npp/8/8/8/8/8/6K1 b - - 0 1} {*}
		smothered_mate miss {6k1/5ppp/8/8/8/8/8/3R2K1 w - - 0 1} {1. Rd8# *}
		back_rank_mate must {6k1/5ppp/8/8/8/8/8/3R2K1 w - - 0 1} {1. Rd8# *}
		back_rank_mate miss {6rk/5Npp/8/8/8/8/8/6K1 b - - 0 1} {*}
		checkmate must {6k1/5ppp/8/8/8/8/8/3R2K1 w - - 0 1} {1. Rd8# *}
		checkmate miss {7k/5Q2/6K1/8/8/8/8/8 b - - 0 1} {*}
		stalemate must {7k/5Q2/6K1/8/8/8/8/8 b - - 0 1} {*}
		stalemate miss {6k1/5ppp/8/8/8/8/8/3R2K1 w - - 0 1} {1. Rd8# *}
		underpromotion must {8/4P3/8/8/8/8/k7/4K3 w - - 0 1} {1. e8=N *}
		underpromotion miss {8/4P3/8/8/8/8/k7/4K3 w - - 0 1} {1. e8=Q *}
		knight_promotion must {8/4P3/8/8/8/8/k7/4K3 w - - 0 1} {1. e8=N *}
		knight_promotion miss {8/4P3/8/8/8/8/k7/4K3 w - - 0 1} {1. e8=R *}
		en_passant must {4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1} {1. exd6 *}
		en_passant miss {4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1} {1. e6 *}
		queen_taken_by_pawn must {4k3/8/3q4/4P3/8/8/8/4K3 w - - 0 1} {1. exd6 *}
		queen_taken_by_pawn miss {4k3/8/3q4/4P3/8/8/8/4K3 w - - 0 1} {1. e6 *}
		queenside_castling must {r3k3/8/8/8/8/8/8/R3K3 w Qq - 0 1} {1. O-O-O *}
		queenside_castling miss {r3k3/8/8/8/8/8/8/R3K3 w Qq - 0 1} {1. Kd2 *}
		opposite_castling must {6k1/8/8/8/8/8/8/2K5 w - - 0 1} {1. Kb1 *}
		opposite_castling miss {6k1/8/8/8/8/8/8/6K1 w - - 0 1} {1. Kh1 *}
		rook_seventh must {4k3/R7/8/8/8/8/8/4K3 b - - 0 1} {1... Kf8 *}
		rook_seventh miss {4k3/8/R7/8/8/8/8/4K3 b - - 0 1} {1... Kf8 *}
		two_rooks_seventh must {4k3/R6R/8/8/8/8/8/4K3 b - - 0 1} {1... Kf8 *}
		two_rooks_seventh miss {4k3/R7/8/8/8/8/8/4K3 b - - 0 1} {1... Kf8 *}
		passed_pawn_sixth must {4k3/8/3P4/8/8/8/8/4K3 b - - 0 1} {1... Kd7 *}
		passed_pawn_sixth miss {4k3/3p4/3P4/8/8/8/8/4K3 b - - 0 1} {1... Kf7 *}
		knight_outpost_d5 must {4k3/8/8/3N4/8/8/8/4K3 b - - 0 1} {1... Kf7 *}
		knight_outpost_d5 miss {4k3/2p5/8/3N4/8/8/8/4K3 b - - 0 1} {1... Kf7 *}
		isolated_queen_pawn must {4k3/8/8/8/3P4/8/8/4K3 b - - 0 1} {1... Kf7 *}
		isolated_queen_pawn miss {4k3/8/8/8/3P4/8/4P3/4K3 b - - 0 1} {1... Kf7 *}
		opposite_bishops must {2b1k3/8/8/8/8/8/8/2B1K3 b - - 0 1} {1... Kf7 *}
		opposite_bishops miss {4kb2/8/8/8/8/8/8/2B1K3 b - - 0 1} {1... Kf7 *}
		bishop_pair_vs_knights must {2nnk3/8/8/8/8/8/8/2BBK3 b - - 0 1} {1... Kf7 *}
		bishop_pair_vs_knights miss {2nnk3/8/8/8/8/8/8/2BNK3 b - - 0 1} {1... Kf7 *}
		queen_vs_rook must {4k3/8/8/8/8/8/r7/Q3K3 w - - 0 1} {1. Kd1 *}
		queen_vs_rook miss {4k3/8/8/8/8/8/r6P/Q3K3 w - - 0 1} {1. Kd1 *}
		exchange_up must {4k3/8/8/8/8/8/8/R3K2b w - - 0 1} {1. Kd2 *}
		exchange_up miss {4k2r/8/8/8/8/8/8/R3K3 w - - 0 1} {1. Kd2 *}
		three_checks must {4k3/8/8/8/8/8/8/R3K3 w - - 0 1} {1. Ra8+ Kd7 2. Ra7+ Kd6 3. Ra6+ Kd5 *}
		three_checks miss {4k3/8/8/8/8/8/8/R3K3 w - - 0 1} {1. Ra8+ Kd7 2. Ra7+ Kd6 3. Ke2 *}
		knight_check_move must {4k3/8/8/3N4/8/8/8/4K3 w - - 0 1} {1. Nf6+ Kf7 *}
		knight_check_move miss {4k3/8/8/3N4/8/8/8/4K3 w - - 0 1} {1. Ke2 Kf7 *}
		pinned_knight must {4k3/8/2n5/1B6/8/8/8/4K3 b - - 0 1} {1... Kf7 *}
		pinned_knight miss {4k3/8/2n5/8/8/8/8/4K3 b - - 0 1} {1... Kf7 *}
		doubled_pawns must {4k3/8/8/8/4P3/4P3/8/4K3 b - - 0 1} {1... Kf7 *}
		doubled_pawns miss {4k3/8/8/8/3P4/4P3/8/4K3 b - - 0 1} {1... Kf7 *}
	}
}

proc ::scidb::test::cqlref::nop {args} { return 0 }

# Write the fixture games; returns {id {must games} {miss games}} per example.
proc ::scidb::test::cqlref::openFixture {} {
	variable Fixture
	variable Positions

	file mkdir [file dirname $Fixture]
	set fh [open $Fixture w]
	fconfigure $fh -encoding utf-8
	set n 0
	set expect {}
	foreach {id kind fen moves} $Positions {
		puts $fh "\[Event \"$id $kind\"\]\n\[Site \"X\"\]\n\[Date \"2020.01.01\"\]\n\[Round \"[incr n]\"\]"
		puts $fh "\[White \"W\"\]\n\[Black \"B\"\]\n\[Result \"*\"\]\n\[SetUp \"1\"\]\n\[FEN \"$fen\"\]\n\n$moves\n"
		dict lappend expect $id [list $kind [expr {$n - 1}]]
	}
	close $fh
	::scidb::db::open $Fixture ::scidb::test::cqlref::nop {} ::scidb::test::cqlref::nop {}
	return $expect
}

proc ::scidb::test::cqlref::closeFixture {} {
	variable Fixture
	catch { ::scidb::db::close $Fixture }
	catch { file delete $Fixture }
}

# The games <script> matches, or "error: ...".
proc ::scidb::test::cqlref::games {script} {
	variable Fixture
	set ::scidb::test::cqlref::Result {}
	if {[catch { ::scidb::cql6::search $Fixture Normal $script -compact 1 \
			-command {set ::scidb::test::cqlref::Result} } err]} {
		return "error: $err"
	}
	set timer [after 20000 {set ::scidb::test::cqlref::Result {ok 0 error timeout}}]
	vwait ::scidb::test::cqlref::Result
	after cancel $timer
	set r $::scidb::test::cqlref::Result
	if {![dict get $r ok]} { return "error: [dict get $r error]" }
	return [lsort -integer -unique [lmap {g p} [dict get $r matches] { set g }]]
}

tcltest::testConstraint cql6 [expr {[llength [info commands ::scidb::cql6::search]]
	&& [::scidb::cql6::version] ne "cql6 stub 6.2"}]

tcltest::test cqlref-card {the card states the rules the examples depend on} -body {
	set card [::ai::cqlref::card]
	list [string match "*X attacks Y*the squares of X*" $card] \
		[string match "*square x in N {x attacks k x attacks q}*" $card] \
		[string match "*NOT written in CQL*" $card] \
		[string match "*move previous*" $card]
} -result {1 1 1 1}

tcltest::test cqlref-ids {ids are unique and every example has a request and a script} -body {
	set ids [::ai::cqlref::examples -ids]
	list [expr {[llength $ids] == [llength [lsort -unique $ids]]}] [expr {[llength $ids] >= 30}] \
		[llength [lmap e [::ai::cqlref::examples] {
			lassign $e id request cql
			if {$request ne "" && [string match "cql(*" $cql]} continue
			set id
		}]]
} -result {1 1 0}

tcltest::test cqlref-examples {every example parses; fixtures match and miss as the request says} -constraints cql6 -setup {
	set expect [::scidb::test::cqlref::openFixture]
} -body {
	set wrong {}
	foreach e [::ai::cqlref::examples] {
		lassign $e id request cql
		set got [::scidb::test::cqlref::games $cql]
		if {[string match "error: *" $got]} { lappend wrong "$id: $got"; continue }
		if {![dict exists $expect $id]} continue
		foreach pair [dict get $expect $id] {
			lassign $pair kind game
			set hit [expr {$game in $got}]
			if {($kind eq "must") != $hit} { lappend wrong "$id: $kind game [expr {$game + 1}] (matched: $got)" }
		}
	}
	join $wrong \n
} -cleanup {
	::scidb::test::cqlref::closeFixture
} -result {}

tcltest::test cqlref-coverage {most examples have fixtures} -body {
	set ids [::ai::cqlref::examples -ids]
	set covered [lsort -unique [lmap {id kind fen moves} $::scidb::test::cqlref::Positions { set id }]]
	list [expr {[llength $covered] >= 25}] [lmap id $covered { if {$id in $ids} continue; set id }]
} -result {1 {}}

tcltest::cleanupTests
