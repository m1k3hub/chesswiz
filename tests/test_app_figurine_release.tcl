# Board resizes release the figurine photos of sizes no longer shown, and a
# fresh user directory starts with the Wizard piece set.
package require tcltest 2.5

proc FigurineCount {} { llength [lsearch -all -glob [image names] photo_Piece(figurine,*] }

tcltest::test figurine-release {resizes do not accumulate figurine photos} -body {
	catch { .application.nb select .application.nb.board }
	set w [winfo toplevel .application]
	foreach g {900x700 1000x760 1100x820 1200x880 1300x940 900x700} {
		wm geometry $w $g; update; after 200; update
	}
	set base [FigurineCount]
	foreach g {950x730 1050x790 1150x850 1250x910 1350x970 900x700} {
		wm geometry $w $g; update; after 200; update
	}
	expr {[FigurineCount] - $base}
} -result 0

tcltest::test default-pieceset-wizard {fresh start and unknown sets use Wizard} -body {
	list $::board::theme::style(piece-set) [lindex [::board::pieceset::lookup NoSuchSet] 0]
} -result {Wizard Wizard}

tcltest::cleanupTests
