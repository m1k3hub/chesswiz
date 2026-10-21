# ======================================================================
# Scidb App Test — set_position (tcl/ai-setup-position.tcl): a position
# from a FEN or a line, always in a new game, checked before anything
# changes.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::setuppos {
	variable Najdorf {1.e4 c5 2.Nf3 d6 3.d4 cxd4 4.Nxd4 Nf6 5.Nc3 a6}
}

proc ::scidb::test::setuppos::noTab {body} {
	rename ::application::switchTab ::scidb::test::setuppos::realTab
	proc ::application::switchTab {args} {}
	set rc [catch { uplevel 1 $body } result opts]
	rename ::application::switchTab {}
	rename ::scidb::test::setuppos::realTab ::application::switchTab
	return -options $opts $result
}

tcltest::test setuppos-tokens {move numbers, dots, results and marks are ignored} -body {
	list [::ai::setup::Tokens {1.e4 c5 2. Nf3 d6!? 3...Nc6 1-0}] [::ai::setup::Tokens {e4 e5}]
} -result {{e4 c5 Nf3 d6 Nc6} {e4 e5}}

tcltest::test setuppos-validate {a line is played out without touching any game} -body {
	set before [::scidb::pos::fen]
	set d [::ai::setup::validate -moves $::scidb::test::setuppos::Najdorf]
	list [lrange [dict get $d fen] 0 1] [dict get $d plies] [expr {[::scidb::pos::fen] eq $before}]
} -result {{rnbqkb1r/1p2pppp/p2p1n2/8/3NP3/2N5/PPP2PPP/R1BQKB1R w} 10 1}

tcltest::test setuppos-illegal {an illegal move is named and nothing changes} -body {
	set before [::scidb::pos::fen]
	set current [::scidb::game::current]
	set err [::application::assistant::runTool set_position {moves {1.e4 e5 2.Nf3 Nc6 3.Bb5 a6 4.Qxf7}}]
	list $err [expr {[::scidb::pos::fen] eq $before}] [expr {[::scidb::game::current] == $current}]
} -result {{error: move 4.Qxf7 is not legal here; the board is unchanged} 1 1}

tcltest::test setuppos-moves {a line is played out in a new game on the board} -body {
	::scidb::test::setuppos::noTab {
		set reply [::application::assistant::runTool set_position [list moves $::scidb::test::setuppos::Najdorf]]
	}
	list [string match "a new game is on the board after 10 half-moves (last a6); position rnbqkb1r/1p2pppp/p2p1n2/8/3NP3/2N5/PPP2PPP/R1BQKB1R w*" $reply] \
		[lrange [::scidb::pos::fen] 0 1]
} -result {1 {rnbqkb1r/1p2pppp/p2p1n2/8/3NP3/2N5/PPP2PPP/R1BQKB1R w}}

tcltest::test setuppos-fen {a FEN, and moves from it} -body {
	::scidb::test::setuppos::noTab {
		::application::assistant::runTool set_position {fen {4k3/8/8/8/8/8/4P3/4K3 w - - 0 1}}
		set a [lindex [::scidb::pos::fen] 0]
		::application::assistant::runTool set_position {fen {4k3/8/8/8/8/8/4P3/4K3 w - - 0 1} moves {e4 Kd7}}
		set b [lindex [::scidb::pos::fen] 0]
	}
	list $a $b
} -cleanup {
	# later files expect an empty game on the board
	::scidb::test::setuppos::noTab { ::menu::gameNew .application }
} -result {4k3/8/8/8/8/8/4P3/4K3 8/3k4/8/8/4P3/8/8/4K3}

tcltest::test setuppos-checks {an empty request is refused} -body {
	::application::assistant::runTool set_position {}
} -result {error: give a fen, moves or both}

tcltest::testConstraint nativeSetupCursors [expr {[tk windowingsystem] in {aqua win32}}]
tcltest::test setup-native-cursors {native setup initializes cursors for every piece without an undefined fig} -constraints nativeSetupCursors -setup {
    ::util::source setup-board
    set savedCursors [array get ::setup::board::Cursor]
    array unset ::setup::board::Cursor
} -body {
    ::setup::board::SetupCursors
    set complete [info exists ::setup::board::Cursor(.)]
    foreach side {w b} {
        foreach piece {k q r b n p} {
            if {![info exists ::setup::board::Cursor($side$piece)]} {set complete 0}
        }
    }
    set complete
} -cleanup {
    array unset ::setup::board::Cursor
    array set ::setup::board::Cursor $savedCursors
} -result 1

tcltest::cleanupTests
