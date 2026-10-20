# ======================================================================
# Scidb App Test - New Game resets the board to the start position
# (tests/test_app_new_game_fen.tcl)
#
# G16 (laptop-loop BUGS.md run29): "New Game" changed the current game
# but the board kept showing the old position. The board follows the
# current game, so the defect is where the new game's start position
# comes from: the scratch game kept open in position 9 seeds every new
# game in the C++ layer, and ::menu::gameNew (tcl/menu.tcl) re-applies
# its start FEN ("::scidb::game::query 9 fen"/clear) to the fresh game.
# When no game slot was open, e.g. right after startup, a position setup
# written into that scratch game (the setup-position dialog clears the
# current game) made every later New Game begin at that stale FEN.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

tcltest::testConstraint x11 [expr {[tk windowingsystem] eq "x11"}]

namespace eval ::scidb::test::newgame {
	variable testDir [file dirname [file normalize [info script]]]
	variable kpFen {8/8/8/4k3/8/8/4KP2/8 w - - 0 1}
	variable startFen {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}
	variable slots {}
}

# --- shared helpers -----------------------------------------------------

proc ::scidb::test::newgame::diagram {} {
	return [::board::diagram::data $::application::board::board]
}

proc ::scidb::test::newgame::startDiagram {} {
	variable startFen
	return [::scidb::board::fenToBoard [lindex [split $startFen " "] 0]]
}

proc ::scidb::test::newgame::endgameDiagram {} {
	variable kpFen
	return [::scidb::board::fenToBoard [lindex [split $kpFen " "] 0]]
}

# from test_app_board_sync.tcl: the pieces actually drawn on the canvas
proc ::scidb::test::newgame::canvasBoard {w} {
	set canv $w.c
	set board ""
	for {set sq 0} {$sq < 64} {incr sq} {
		set item [$canv find withtag piece:$sq]
		if {$item eq ""} {
			append board "."
		} else {
			set img [$canv itemcget $item -image]
			if {[regexp {photo_Piece\(([a-z]+),} $img -> p]} {
				set ch [string index $p 1]
				if {[string index $p 0] eq "w"} {
					set ch [string toupper $ch]
				}
				append board $ch
			} else {
				append board "?"
			}
		}
	}
	return $board
}

proc ::scidb::test::newgame::drain {} {
	after 20; update
	after 20; update
}

proc ::scidb::test::newgame::nop {args} { return 0 }

# Let New Game into a free slot even if earlier test files filled them up
# (the whole app suite runs in one process; ::game::max is 9).
proc ::scidb::test::newgame::makeRoom {} {
	if {[llength $::game::List] < 9} { return }
	for {set i 0} {$i < 9} {incr i} {
		set entry [lindex $::game::List $i]
		if {	[lindex $entry 1] == 0 && [lindex $entry 2] == 0 && [lindex $entry 3] == 0
			&& [lindex [lindex $entry 4] 0] ne ""} {
			catch { ::application::pgn::release $i }
			catch { ::game::release $i }
			return
		}
	}
	error "no game slot could be freed"
}

# New Game through the menu entry; returns the game slot it landed in.
proc ::scidb::test::newgame::newGame {} {
	::scidb::test::newgame::makeRoom
	::menu::gameNew .application
	::scidb::test::newgame::drain
	set pos [::scidb::game::current]
	if {[lindex [::game::gameList] $pos 0] ne "Scratchbase"} {
		error "New Game did not register a scratch game (slot $pos)"
	}
	lappend ::scidb::test::newgame::slots $pos
	return $pos
}

proc ::scidb::test::newgame::testBoardAtStart {state} {
	list $state \
		[expr {[::scidb::game::fen] eq $::scidb::test::newgame::startFen}] \
		[expr {[::scidb::test::newgame::diagram]
			eq [::scidb::test::newgame::startDiagram]}] \
		[expr {[::scidb::test::newgame::canvasBoard $::application::board::board]
			eq [::scidb::test::newgame::startDiagram]}]
}

# Restore the template game in position 9 to the start position, so the
# next test file starts from the state the app normally ships in.
proc ::scidb::test::newgame::restoreTemplate {} {
	variable startFen
	if {[catch { [::scidb::game::query 9 open?] }] || ![::scidb::game::query 9 open?]} { return }
	::scidb::game::switch 9
	::scidb::game::clear $startFen
	::scidb::test::newgame::drain
}

proc ::scidb::test::newgame::cleanup {{pgn {}}} {
	foreach pos $::scidb::test::newgame::slots {
		catch { ::application::pgn::release $pos }
		catch { ::game::release $pos }
	}
	set ::scidb::test::newgame::slots {}
	catch { ::scidb::db::close $pgn }
	::scidb::test::newgame::restoreTemplate
}

proc ::scidb::test::newgame::openFixture {} {
	variable testDir
	variable kpFen
	set dir [file join $testDir tmp-app newgame]
	file mkdir $dir
	set pgn [file join $dir endgame.pgn]
	set chan [open $pgn w]
	puts $chan "\[Event \"?\"\]"
	puts $chan "\[Site \"?\"\]"
	puts $chan "\[Date \"?\"\]"
	puts $chan "\[Round \"?\"\]"
	puts $chan "\[White \"K\"\]"
	puts $chan "\[Black \"KP\"\]"
	puts $chan "\[Result \"\*\"\]"
	puts $chan "\[SetUp \"1\"\]"
	puts $chan "\[FEN \"$kpFen\"\]"
	puts $chan ""
	puts $chan "\*"
	close $chan
	::scidb::db::open $pgn ::scidb::test::newgame::nop {} ::scidb::test::newgame::nop {}
	::scidb::test::newgame::makeRoom
	::game::new .application -base $pgn -variant Normal -number 0
	::scidb::test::newgame::drain
	lappend ::scidb::test::newgame::slots [::scidb::game::current]
	return $pgn
}

# --- the task-specified flow: an endgame game is loaded, then New Game --

tcltest::test newgame-fen-db-endgame {a loaded game at an endgame position; the board resets to start} \
	-constraints x11 -setup {
	::application::switchTab board
	update
	catch { destroy .tipoftheday }
	set pgn [::scidb::test::newgame::openFixture]
} -body {
	set loaded [::scidb::game::fen]
	set sane [expr {
		$loaded eq $::scidb::test::newgame::kpFen
		&& [::scidb::test::newgame::diagram] eq [::scidb::test::newgame::endgameDiagram]}]
	::scidb::test::newgame::newGame
	set after [::scidb::test::newgame::testBoardAtStart $sane]
	return $after
} -cleanup {
	::scidb::test::newgame::cleanup $pgn
} -result {1 1 1 1}

# --- the defect itself (run29): a position setup with no game open ------
# --- stamps the template game; New Game must return to the start position

proc ::scidb::test::newgame::contaminateTemplate {} {
	variable kpFen
	# the run29 flow: with no game open the board is the template game in
	# position 9, and the setup-position dialog's clear writes into it
	::scidb::game::switch 9
	::scidb::game::clear $kpFen
	::scidb::test::newgame::drain
}

tcltest::test newgame-fen-after-possetup {a position setup written into the template game does not stamp New Game} \
	-constraints x11 -setup {
	::application::switchTab board
	update
	::scidb::test::newgame::contaminateTemplate
} -body {
	set sane [expr {
		[::scidb::game::query 9 fen] eq $::scidb::test::newgame::kpFen
		&& [::scidb::test::newgame::diagram]
			eq [::scidb::test::newgame::endgameDiagram]}]
	# first New Game: back at the start position
	::scidb::test::newgame::newGame
	set first [::scidb::test::newgame::testBoardAtStart $sane]
	# and a second one as well (run29 repeated New Game in the loop)
	set pos2 [::scidb::test::newgame::newGame]
	set second [expr {
		[::scidb::game::fen] eq $::scidb::test::newgame::startFen
		&& [::scidb::test::newgame::diagram]
			eq [::scidb::test::newgame::startDiagram]}]
	return [list $first $second]
} -cleanup {
	::scidb::test::newgame::cleanup
} -result {{1 1 1 1} 1}


# --- the explanation is translated like its neighbouring strings --------

# The lang files are only ever loaded inside the app, so scan them as
# source: each file must assign both Maintenance strings a non-empty text.

proc ::scidb::test::newgame::langDefines {path encoding} {
	set result ""
	set chan [open $path r]
	fconfigure $chan -encoding $encoding
	set source [read $chan]
	close $chan
	foreach name {MaintenanceReadOnlyPgn MaintenanceReadOnly} {
		set found 0
		foreach line [split $source "\n"] {
			if {[string first "::application::database::mc::$name\t" $line] >= 0
				&& [regexp {"([^"]+)"\s*$} $line -> text]
				&& [string length [string trim $text]]} {
				set found 1
				append result " $text"
			}
		}
		lappend result [expr {$found ? "yes" : "MISSING"}]
	}
	return $result
}

tcltest::test newgame-fen-readonly-hint-translated {the read-only explanation is translated in the neighbouring languages} -body {
	set dir [file join [file dirname [file normalize [info script]]] .. tcl lang]
	set missing ""
	foreach {lang encoding} {
		deutsch		iso8859-1
		espanol		utf-8
		italiano	utf-8
		magyar		utf-8
		svenska		utf-8
	} {
		set got [::scidb::test::newgame::langDefines [file join $dir $lang.tcl] $encoding]
		if {[lsearch -exact $got MISSING] >= 0} { append missing " $lang" }
		# the text tells the user to convert: it names the .sci target format
		unset -nocomplain text
		if {[lsearch -regexp $got {\.sci}] < 0} { append missing " $lang(.sci)" }
	}
	if {[string length $missing]} { return "missing:$missing" }
	return "all-translated"
} -result all-translated

tcltest::cleanupTests
