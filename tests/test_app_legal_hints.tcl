# ======================================================================
# Legal-move hints: selecting a piece marks each square it can move to.
# ======================================================================
package require tcltest 2.5

namespace eval ::scidb::test::hints {}

proc ::scidb::test::hints::count {} {
	set w $::application::board::board
	return [llength [$w.c find withtag legalhint]]
}

# In the starting position: the e-pawn (square 12) has two moves, and so
# does the b1 knight (square 1). Hints disappear when the selection is cleared.
tcltest::test legal-hints-pawn {the e2 pawn shows hints on its two destinations} -body {
	set w $::application::board::board
	::board::diagram::hilite $w 12 selected
	set shown [::scidb::test::hints::count]
	::board::diagram::hilite $w 12 off
	list $shown [::scidb::test::hints::count]
} -result {2 0}

tcltest::test legal-hints-knight {the b1 knight shows hints on its two destinations} -body {
	set w $::application::board::board
	::board::diagram::hilite $w 1 selected
	set shown [::scidb::test::hints::count]
	::board::diagram::hilite $w 1 off
	set shown
} -result 2

tcltest::test legal-hints-off {the option turns the hints off} -body {
	set w $::application::board::board
	set ::board::hilite(legal-hints) 0
	::board::diagram::hilite $w 12 selected
	set shown [::scidb::test::hints::count]
	::board::diagram::hilite $w 12 off
	set ::board::hilite(legal-hints) 1
	set shown
} -result 0

tcltest::cleanupTests
