# Run 12 tester bugs: a plain surname in Advanced Search finds "Surname, X",
# Search by Material opens fully on screen, Find Duplicates sees identical games.
package require tcltest 2.5

namespace eval ::scidb::test::run12 {
	variable dir [file join $::scidb::test::app::testDir tmp-app run12]
	variable pgn [file join $dir run12.pgn]

	proc game {fh white black moves {event R12}} {
		puts $fh "\[Event \"$event\"\]\n\[Site \"Here\"\]\n\[Date \"2020.01.01\"\]\n\[Round \"1\"\]"
		puts $fh "\[White \"$white\"\]\n\[Black \"$black\"\]\n\[Result \"1-0\"\]\n\n$moves 1-0\n"
	}

	proc setup {} {
		variable dir
		variable pgn
		file mkdir $dir
		set fh [open $pgn w]
		game $fh "Carlsen, M" "Alpha, A" "1. e4 e5 2. Nf3 Nc6"
		game $fh "Beta, B" "Carlsen, Magnus" "1. d4 d5 2. c4 e6"
		game $fh "Carlsenx, Q" "Gamma, G" "1. c4 c5"
		game $fh "Carlsen" "Delta, D" "1. Nf3 Nf6"
		# two identical games
		game $fh "Twin, T" "Pair, P" "1. e4 c5 2. Nf3 d6 3. d4 cxd4" Dup
		game $fh "Twin, T" "Pair, P" "1. e4 c5 2. Nf3 d6 3. d4 cxd4" Dup
		close $fh
		::scidb::db::open $pgn {apply {args {return 0}}} {} {apply {args {return 0}}} {}
		::scidb::db::switch $pgn Normal
	}

	proc advanced {player} {
		variable pgn
		set ns ::application::database
		set dlg [${ns}::AdvancedDialogName $pgn Normal]
		if {![winfo exists $dlg]} { ${ns}::OpenAdvancedSearch .application $pgn Normal }
		update
		${ns}::ResetAdvancedSearch $dlg
		set ${ns}::AdvancedSearchData($dlg,player) $player
		${ns}::RunAdvancedSearch $dlg
		set n [::scidb::view::count games $pgn Normal [set ${ns}::AdvancedSearchData($dlg,view)]]
		return $n
	}
}

tcltest::test run12-player-surname {plain surname finds "Surname, X" but not longer names} -setup {
	::scidb::test::run12::setup
} -body {
	lmap p {Carlsen carlsen Carlsen* {Carlsen, M} Carlsenx Carls {Carlsen M}} {
		::scidb::test::run12::advanced $p
	}
} -result {3 3 4 1 1 0 0}

tcltest::test run12-material-on-screen {Search by Material opens fully on screen} -body {
	set ns ::application::database
	set pgn $::scidb::test::run12::pgn
	set dlg [${ns}::MaterialDialogName $pgn Normal]
	catch {destroy $dlg}
	# a narrow main window near the left edge, as on the tester's screen
	set g [wm geometry .application]
	wm geometry .application [::scidb::test::app::fitGeometry 500 400]
	update
	${ns}::OpenMaterialSearch .application $pgn Normal
	update
	set x [winfo rootx $dlg]
	set r [expr {$x + [winfo width $dlg]}]
	set geo [wm geometry $dlg]
	set c $dlg.controls.close
	set btn [expr {[winfo ismapped $c] && [winfo rootx $c] + [winfo width $c] <= $r}]
	lassign [winfo workarea $dlg] wx wy ww wh
	destroy $dlg
	wm geometry .application $g
	list [expr {$x >= $wx}] [expr {$r <= $wx+$ww}] [string match *+-* $geo] $btn
} -result {1 1 0 1}

tcltest::test run12-duplicates {Find Duplicates reports 1 group for two identical games} -body {
	set groups [::scidb::db::findDuplicates $::scidb::test::run12::pgn Normal]
	list [llength $groups] [llength [lindex $groups 0]]
} -result {1 2}

tcltest::cleanupTests
