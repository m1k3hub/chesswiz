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
tcltest::test font-size-edges {the smallest size grows, the largest shrinks} -body {
	set min [::html::minFontSize]; set max [::html::maxFontSize]
	list [expr {[::html::incrFontSize $min 1] > $min}] [::html::incrFontSize $min -1] \
		[expr {[::html::incrFontSize $max -1] < $max}] [::html::incrFontSize $max 1]
} -result [list 1 [::html::minFontSize] 1 [::html::maxFontSize]]

tcltest::test ask-strip-fits {the Ask strip buttons and hint fit the strip} -body {
	update
	set f $::application::ask::Priv(frame)
	set bad {}
	foreach c {mic mode alias} {
		if {[winfo exists $f.$c] && [winfo reqheight $f.$c] > [winfo height $f] + 1} { lappend bad $c }
	}
	set ph $::application::ask::Priv(placeholder)
	if {[winfo ismapped $ph] && [winfo width $ph] > [winfo width $::application::ask::Priv(entry)]} {
		lappend bad placeholder
	}
	set bad
} -result {}

tcltest::test board-style-preview-fits {side-to-move and material marks stay on the preview} -body {
	after 100 { ::action::run menu.board.setup }
	set ::polishDone 0; after 2000 { set ::polishDone 1 }; vwait ::polishDone
	set dlg .application.boardConfigDialog
	if {![winfo exists $dlg]} { error "Board Style dialog did not open" }
	set p $::board::options::Vars(widget:canv:preview)
	set w [winfo width $p]
	set out {}
	foreach tag {stmb stmw mv1} {
		set bb [$p bbox $tag]
		if {[llength $bb] && [lindex $bb 2] > $w} { lappend out $tag }
	}
	$dlg.top.nb select 2; update
	set sel [$::board::pieceset::Listbox curselection]
	$dlg.cancel invoke; update
	list $out [expr {$sel >= 0}]
} -result {{} 1}

tcltest::test assistant-new-game-label {the New suggestion is not a bare "Normal"} -body {
	set ::application::assistant::panel::mc::NewGame
} -result {New Game}

tcltest::cleanupTests
