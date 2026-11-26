# Board Style dialog: every piece set has a preview, the title matches the
# menu entry, and the drop-down fills its cascades before Tk places them.
package require tcltest 2.5
tcltest::test previews {every piece set has a non-blank preview} -body {
	set f [toplevel .pv]
	set lb [::board::pieceset::makePieceSelectionFrame $f 12]
	update
	set blank {}
	foreach ps $::board_PieceSet {
		set name [lindex $ps 0]
		set img [::board::pieceset::RenderSample $ps]
		set opaque 0
		for {set x 0} {$x < 200} {incr x 3} { for {set y 0} {$y < 34} {incr y 3} {
			if {[$img transparency get $x $y] == 0} { incr opaque } } }
		image delete $img
		if {$opaque < 20} { lappend blank $name }
	}
	destroy $f
	list $blank [llength [lsearch -all -glob [image names] photo_Piece(sample,*]]
} -result {{} 0}
tcltest::test title {} -body { set ::board::options::mc::BoardSetup } -result {Board Style}
tcltest::test cascade-prefill {cascades are filled once the main menu posts} -body {
	set m [menu .zzmenu]
	::menu::build $m
	if {$m eq ""} { error "no dropdown widget" }
	::menu::RefreshTopStates $m
	set empty {}
	for {set i 0} {$i <= [$m index end]} {incr i} {
		if {[$m type $i] ne "cascade"} continue
		set sm [$m entrycget $i -menu]
		if {[$sm index end] in {"" none}} { lappend empty $sm }
	}
	destroy $m
	set empty
} -result {}
tcltest::cleanupTests
