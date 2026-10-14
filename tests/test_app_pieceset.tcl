# The piece-set chooser (Board Options) lists every set, also those without
# a preview image, and frees its images when it closes.
package require tcltest 2.5
tcltest::test pieceset-list {piece-set list builds with every set, and frees its images} -body {
	toplevel .pieceSetTest
	frame .pieceSetTest.f
	set before [llength [image names]]
	::board::pieceset::makePieceSelectionFrame .pieceSetTest.f 10
	set n [llength $::board_PieceSet]
	set during [llength [image names]]
	destroy .pieceSetTest
	list [expr {$n >= 10}] [expr {$during > $before}] [expr {[llength [image names]] == $before}]
} -result {1 1 1}
tcltest::cleanupTests
