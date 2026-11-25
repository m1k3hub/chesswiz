# Board resizes release the figurine photos of sizes no longer shown, the
# check-count icons keep live images, and unknown piece sets use Wizard.
package require tcltest 2.5

proc FigurineCount {} { llength [lsearch -all -glob [image names] photo_Piece(figurine,*] }

# Resize the main window and wait until the board has rebuilt at that size.
proc ResizeTo {g} {
	set w [winfo toplevel .application]
	wm geometry $w $g
	set deadline [expr {[clock milliseconds] + 5000}]
	lassign [split $g x] gw gh
	while {[clock milliseconds] < $deadline} {
		update
		if {[winfo width $w] == $gw && [winfo height $w] == $gh
			&& ![string length $::application::board::Vars(after)]} { break }
		after 20
	}
	after 100; update
}

proc DeadCheckIcons {} {
	set canv $::application::board::Vars(widget:frame)
	set dead {}
	foreach item [$canv find withtag checks] {
		set img [$canv itemcget $item -image]
		if {$img ni [image names]} { lappend dead $img }
	}
	return $dead
}

tcltest::test figurine-release {resizes do not accumulate figurine photos} -body {
	catch { .application.nb select .application.nb.board }
	set sizes {}
	foreach g {900x700 1000x760 1100x820 1200x880 1300x940 900x700} {
		ResizeTo $g
		lappend sizes $::application::board::Dim(piece:size)
	}
	set base [FigurineCount]
	foreach g {950x730 1050x790 1150x850 1250x910 1350x970 900x700} {
		ResizeTo $g
		lappend sizes $::application::board::Dim(piece:size)
	}
	# the resizes must really have changed the figurine size
	list [expr {[llength [lsort -unique $sizes]] > 1}] [expr {[FigurineCount] - $base}] [DeadCheckIcons]
} -result {1 0 {}}

tcltest::test figurine-release-board-style {the Board Style dialog gives its figurines back} -body {
	set before $::board::pieceset::FigurineDict
	foreach round {1 2} {
		after 100 { ::action::run menu.board.setup }
		set ::figDialogDone 0
		after 2000 { set ::figDialogDone 1 }
		vwait ::figDialogDone
		set dlg .application.boardConfigDialog
		if {![winfo exists $dlg]} { error "Board Style dialog did not open" }
		$dlg.cancel invoke
		update
	}
	expr {$::board::pieceset::FigurineDict eq $before}
} -result 1

tcltest::test default-pieceset-wizard {unknown sets fall back to Wizard} -body {
	lindex [::board::pieceset::lookup NoSuchSet] 0
} -result Wizard

tcltest::cleanupTests
