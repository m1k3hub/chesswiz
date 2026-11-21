# The Wizard set (tcl/pieces/wizard.tcl) loads with all twelve pieces and
# the board draws with it. Set CHESSWIZ_WIZARD_SHOT to a file to also save a
# screenshot of the board.
package require tcltest 2.5

tcltest::test pieceset-wizard-listed {Wizard is listed with all twelve pieces} -body {
	set i [lsearch -exact -index 0 $::board_PieceSet Wizard]
	set have {}
	foreach p {wk wq wr wb wn wp bk bq br bb bn bp} {
		if {[info exists ::svg_Wizard($p)]} { lappend have $p }
	}
	list [expr {$i >= 0}] [llength $have]
} -result {1 12}

tcltest::test pieceset-wizard-draws {the board switches to Wizard and back} -body {
	set old $::board::theme::style(piece-set)
	::board::setPieceSet Wizard
	update
	set now $::board::theme::style(piece-set)
	if {[info exists ::env(CHESSWIZ_WIZARD_SHOT)]} {
		catch { .application.nb select .application.nb.board }
		after 800; update
		catch {exec import -window root $::env(CHESSWIZ_WIZARD_SHOT)}
	}
	::board::setPieceSet $old
	update
	list $now [expr {$::board::theme::style(piece-set) eq $old}]
} -result {Wizard 1}

tcltest::cleanupTests
