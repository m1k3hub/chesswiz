# A board pane that is hidden and shown again shows the open game: its
# position, its variant layout (ThreeCheck counters) and no extra figurine
# registrations. It used to come back with the start position.
package require tcltest 2.5

namespace eval ::scidb::test::reopen {}

proc ::scidb::test::reopen::Settle {{ms 1500}} {
	set ::scidb::test::reopen::done 0
	after $ms { set ::scidb::test::reopen::done 1 }
	vwait ::scidb::test::reopen::done
	update
}

# The piece drawn on a square (file 0-7, rank 1-8), "" if empty.
proc ::scidb::test::reopen::PieceAt {file rank} {
	set canv [::board::diagram::canvas $::application::board::board]
	set i [lindex [$canv find withtag piece:[expr {($rank - 1)*8 + $file}]] 0]
	if {$i eq ""} { return "" }
	if {[regexp {photo_Piece\((..),} [$canv itemcget $i -image] -> p]} { return $p }
	return ""
}

# Figurine registrations as {entries highest-count}: a reopened pane may
# come back at another size, but must not hold more than it did.
proc ::scidb::test::reopen::FigShape {} {
	set d $::board::pieceset::FigurineDict
	list [dict size $d] [tcl::mathfunc::max 0 {*}[dict values $d]]
}

tcltest::test board-reopen-shows-game {hide/show keeps position and ThreeCheck counters} -body {
	catch { .application.nb select .application.nb.board }
	::action::run game.new.three
	::scidb::test::reopen::Settle
	foreach m {e4 f6 Qh5} { ::scidb::game::move $m; ::scidb::game::go 1 }
	::scidb::test::reopen::Settle 500
	set figs [::scidb::test::reopen::FigShape]

	::action::run menu.view.panes.board
	::scidb::test::reopen::Settle 800
	::action::run menu.view.panes.board
	::scidb::test::reopen::Settle

	set frame $::application::board::Vars(widget:frame)
	set shown 0
	foreach i [$frame find withtag checks] {
		if {[$frame itemcget $i -state] eq "normal"} { incr shown }
	}
	list \
		[::scidb::test::reopen::PieceAt 7 5] \
		[::scidb::test::reopen::PieceAt 3 1] \
		$::application::board::Vars(layout) \
		[expr {$shown > 0}] \
		[expr {[::scidb::test::reopen::FigShape] eq $figs}]
} -result {wq {} ThreeCheck 1 1}

tcltest::cleanupTests
