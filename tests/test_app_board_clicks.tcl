# ======================================================================
# Scidb App Test - click-click moves on the board (Run 10/14 tester bug)
# ======================================================================
# With suggested moves on (the default), releasing the button on the
# pressed square always cleared the selection: a click on e2 and then on e4
# did nothing when no move was suggested (no hover before the click).
# ======================================================================

package require tcltest 2.5
namespace eval ::scidb::test::clicks {}

# The test app is not mapped, so screen coordinates cannot find a square:
# the click passes the square as its coordinate.
proc ::scidb::test::clicks::click {sq} {
	rename ::board::diagram::getSquare ::scidb::test::clicks::getSquare
	proc ::board::diagram::getSquare {w x y} { return $x }
	try {
		::move::pressSquare $sq 0
		update
		::move::releaseSquare $sq $sq 0
		update
	} finally {
		rename ::board::diagram::getSquare {}
		rename ::scidb::test::clicks::getSquare ::board::diagram::getSquare
	}
}

tcltest::test clicks-e2-e4 {a click on e2, then on e4, plays 1.e4} -setup {
	::menu::gameNew .application
	update
	set ::board::hilite(show-suggested) 1
	# no hover: nothing suggested, as with a click that arrives without motion
	set ::move::Square(suggested) -1
	set ::move::Square(current) -1
} -body {
	::scidb::test::clicks::click 12
	set selected $::move::Square(selected)
	::scidb::test::clicks::click 28
	list $selected [::scidb::game::position atStart?] [lindex [::scidb::pos::fen] 0]
} -result {12 0 rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR}

tcltest::test clicks-reclick {a second click on the selected piece deselects it} -setup {
	::menu::gameNew .application
	update
	set ::move::Square(suggested) -1
} -body {
	::scidb::test::clicks::click 6
	set a $::move::Square(selected)
	::scidb::test::clicks::click 6
	list $a $::move::Square(selected) [::scidb::game::position atStart?]
} -result {6 -1 1}

tcltest::cleanupTests
