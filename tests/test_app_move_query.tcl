# ======================================================================
# Scidb App Test Suite - ::scidb::game::query move
# ======================================================================
# The SAN of the move at the current key, used by the notation pane's
# "Explain this move" context menu (C1).  Empty at the start position.
package require Tcl 8.5
package require tcltest 2.5
namespace eval ::scidb::test::movequery {
	variable testDir [file dirname [file normalize [info script]]]
	variable Fixture [file join $testDir tmp-app move-query-[pid].pgn]
	variable slot 6
}
proc ::scidb::test::movequery::nop {args} { return 0 }
proc ::scidb::test::movequery::openFixture {} {
	variable Fixture
	set fh [open $Fixture w]
	fconfigure $fh -encoding utf-8
	puts $fh "\[Event \"MoveQuery\"\]\n\[Site \"X\"\]\n\[Date \"2024.01.01\"\]\n\[Round \"1\"\]"
	puts $fh "\[White \"White\"\]\n\[Black \"Black\"\]\n\[Result \"1-0\"\]\n"
	puts $fh "1. e4 e5 2. Nf3 Nc6 3. Bb5 1-0\n"
	close $fh
	::scidb::db::open $Fixture ::scidb::test::movequery::nop {} ::scidb::test::movequery::nop {}
}
proc ::scidb::test::movequery::closeFixture {} {
	variable Fixture
	catch { ::scidb::db::close $Fixture }
	catch { file delete $Fixture }
}
::scidb::test::movequery::openFixture

tcltest::test move-query-start {no move at the start position} -body {
	::scidb::game::load $::scidb::test::movequery::slot $::scidb::test::movequery::Fixture Normal 0
	::scidb::game::layout $::scidb::test::movequery::slot
	::scidb::game::query $::scidb::test::movequery::slot move
} -result {}

tcltest::test move-query-after-forward {SAN of the move just played} -body {
	::scidb::game::go $::scidb::test::movequery::slot 1
	::scidb::game::query $::scidb::test::movequery::slot move
} -result {e4}

tcltest::test move-query-second {SAN of the second move} -body {
	::scidb::game::go $::scidb::test::movequery::slot 1
	::scidb::game::query $::scidb::test::movequery::slot move
} -result {e5}

tcltest::test move-query-third {SAN of the third move} -body {
	::scidb::game::go $::scidb::test::movequery::slot 1
	::scidb::game::query $::scidb::test::movequery::slot move
} -result {Nf3}

tcltest::test move-query-by-key {SAN of a move by key, without moving} -body {
	::scidb::game::go $::scidb::test::movequery::slot -3
	set before [::scidb::game::query $::scidb::test::movequery::slot current]
	set san [::scidb::game::query $::scidb::test::movequery::slot move m-0.2]
	list $san [::scidb::game::query $::scidb::test::movequery::slot current] $before
} -result {e5 m-0.0 m-0.0}

tcltest::test move-query-by-key-start {empty at the start key} -body {
	::scidb::game::query $::scidb::test::movequery::slot move m-0
} -result {}

tcltest::test move-query-by-key-invalid {empty for an unknown key} -body {
	::scidb::game::query $::scidb::test::movequery::slot move m-0.99
} -result {}

tcltest::test movefen-start {empty at the start key} -body {
	::scidb::game::query $::scidb::test::movequery::slot movefen m-0
} -result {}

tcltest::test movefen-first {FEN before the first move is the start position} -body {
	set fen [::scidb::game::query $::scidb::test::movequery::slot movefen m-0.1]
	list [expr {$fen eq "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"}] \
		[::scidb::game::query $::scidb::test::movequery::slot current]
} -result {1 m-0.0}

tcltest::test movefen-second {FEN before the second move is after e4} -body {
	set fen [::scidb::game::query $::scidb::test::movequery::slot movefen m-0.2]
	# after 1.e4: the e-pawn has left e2, and it is Black to move
	list [string match {*4P3*} $fen] [string range $fen end-12 end]
} -result {1 { b KQkq - 0 1}}

tcltest::test movefen-does-not-move {the current position is unchanged} -body {
	::scidb::game::go $::scidb::test::movequery::slot -3
	set before [::scidb::game::query $::scidb::test::movequery::slot current]
	::scidb::game::query $::scidb::test::movequery::slot movefen m-0.2
	list $before [::scidb::game::query $::scidb::test::movequery::slot current]
} -result {m-0.0 m-0.0}

tcltest::test movefen-invalid {empty for an unknown key} -body {
	::scidb::game::query $::scidb::test::movequery::slot movefen m-0.99
} -result {}

::scidb::test::movequery::closeFixture

tcltest::cleanupTests
