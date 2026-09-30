# ======================================================================
# Scidb App Test -- which game a lesson video belongs to
# (::application::media::ResolveOwner, GotoMissed in tcl/app-media.tcl)
#
# The media manifest sometimes names the neighbouring game as the owner of a
# video; Game::goToPosition then sends every unknown position to the END of
# the game, so the board sat on the final position for the whole video. The
# video's own positions decide which game it is.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::owner {
	variable Dir [file join [file dirname [file normalize [info script]]] tmp-app owner_[pid]]
	variable Pgn [file join $Dir three.pgn]
	variable Games {
		{1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 6. Re1 b5 7. Bb3 d6}
		{1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6 6. Be3 e6 7. f3 b5}
		{1. d4 d5 2. c4 e6 3. Nc3 Nf6 4. Bg5 Be7 5. e3 O-O 6. Nf3 h6 7. Bh4 b6}
	}
	variable Positions {}
}

proc ::scidb::test::owner::nop {args} { return 0 }

proc ::scidb::test::owner::setup {} {
	variable Dir
	variable Pgn
	variable Games
	variable Positions

	file delete -force $Dir
	file mkdir $Dir
	set fh [open $Pgn w]
	set n 0
	foreach moves $Games {
		incr n
		puts $fh "\[Event \"Owner\"\]\n\[Site \"X\"\]\n\[Date \"2021.01.0$n\"\]\n\[Round \"$n\"\]"
		puts $fh "\[White \"W$n\"\]\n\[Black \"B$n\"\]\n\[Result \"*\"\]\n\n$moves *\n"
	}
	close $fh
	::scidb::db::open $Pgn ::scidb::test::owner::nop {} ::scidb::test::owner::nop {}

	# the positions of game 2 (index 1), move by move, from the engine itself
	set slot [::game::nextGamePosition]
	::scidb::game::load $slot $Pgn Normal 1
	::scidb::game::go $slot start
	set Positions [list [::scidb::game::fen $slot]]
	for {set i 0} {$i < 14} {incr i} {
		::scidb::game::go $slot 1
		lappend Positions [::scidb::game::fen $slot]
	}
	::scidb::game::release $slot
}

proc ::scidb::test::owner::cleanup {} {
	variable Dir
	variable Pgn
	catch { ::scidb::db::close $Pgn }
	file delete -force $Dir
}

proc ::scidb::test::owner::stubLesson {positions} {
	if {[llength [info commands ::media::lesson::get.orig]] == 0} {
		rename ::media::lesson::get ::media::lesson::get.orig
	}
	proc ::media::lesson::get {path} [format {return [dict create valid 1 positions {%s} timeline {} events {}]} $positions]
}

proc ::scidb::test::owner::unstubLesson {} {
	if {[llength [info commands ::media::lesson::get.orig]]} {
		rename ::media::lesson::get {}
		rename ::media::lesson::get.orig ::media::lesson::get
	}
}

tcltest::test owner-probes {a lesson gives a handful of distinct probe positions, none of them the start} -body {
	set fens {}
	for {set i 0} {$i < 30} {incr i} { lappend fens "8/8/8/8/8/8/8/K6k w - - 0 $i" }
	set probes [::application::media::LessonProbes $fens]
	list [llength $probes] [expr {[lindex $fens 0] ni $probes}] [llength [::application::media::LessonProbes [lrange $fens 0 3]]]
} -result {5 1 0}

tcltest::test owner-resolved-by-content {the game holding the lesson's positions is found, whatever the manifest says} -setup {
	::scidb::test::owner::setup
	::scidb::test::owner::stubLesson $::scidb::test::owner::Positions
	set ::scidb::test::owner::Saved [list $::application::media::Priv(base) $::application::media::Priv(variant) $::application::media::Priv(index)]
	set ::application::media::Priv(base) $::scidb::test::owner::Pgn
	set ::application::media::Priv(variant) Normal
	set ::application::media::Priv(index) 0
	set ::application::media::Priv(ownerCache) {}
} -body {
	# the manifest names game 0 and game 2; the positions are those of game 1
	list [::application::media::ResolveOwner /x/a.wmv 0] \
		[::application::media::ResolveOwner /x/b.wmv 1] \
		[dict get $::application::media::Priv(ownerCache) "$::scidb::test::owner::Pgn|Normal|/x/a.wmv"]
} -cleanup {
	::scidb::test::owner::unstubLesson
	lassign $::scidb::test::owner::Saved ::application::media::Priv(base) ::application::media::Priv(variant) ::application::media::Priv(index)
	set ::application::media::Priv(ownerCache) {}
	::scidb::test::owner::cleanup
} -result {1 1 1}

tcltest::test owner-unknown-keeps-the-manifest {a lesson no game contains keeps the manifest's game} -setup {
	::scidb::test::owner::setup
	set stranger {}
	for {set i 0} {$i < 12} {incr i} { lappend stranger "8/8/8/8/8/8/8/K6k w - - 0 [expr {$i + 1}]" }
	::scidb::test::owner::stubLesson $stranger
	set ::scidb::test::owner::Saved [list $::application::media::Priv(base) $::application::media::Priv(variant) $::application::media::Priv(index)]
	set ::application::media::Priv(base) $::scidb::test::owner::Pgn
	set ::application::media::Priv(variant) Normal
	set ::application::media::Priv(index) 0
	set ::application::media::Priv(ownerCache) {}
} -body {
	::application::media::ResolveOwner /x/c.wmv 2
} -cleanup {
	::scidb::test::owner::unstubLesson
	lassign $::scidb::test::owner::Saved ::application::media::Priv(base) ::application::media::Priv(variant) ::application::media::Priv(index)
	set ::application::media::Priv(ownerCache) {}
	::scidb::test::owner::cleanup
} -result 2

tcltest::test owner-board-misses-stop-following {a board that cannot reach the lesson positions is put back, and following stops with a notice after three misses} -setup {
	set ::scidb::test::owner::Calls {}
	foreach c {::scidb::game::go ::scidb::game::fen} {
		rename $c $c.owner
	}
	proc ::scidb::game::go {args} { lappend ::scidb::test::owner::Calls $args; return }
	proc ::scidb::game::fen {args} { return "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1" }
	set ::scidb::test::owner::HadPos [info exists ::application::media::Priv(lessonPositions)]
	set ::scidb::test::owner::SavedPos [expr {$::scidb::test::owner::HadPos ? $::application::media::Priv(lessonPositions) : {}}]
	set ::application::media::Priv(lessonPositions) {
		{rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}
		{rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1}
		{rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq e6 0 2}
	}
	set ::application::media::Priv(gotoMisses) 0
	lassign [::media::sync::config] ::scidb::test::owner::T ::scidb::test::owner::F
	::media::sync::set-config 1 1
	::dialog::notice::enable 1
	foreach c $::dialog::notice::Cards { ::dialog::notice::Dismiss [lindex $c 0] }
} -body {
	::application::media::SyncBoardGoto 1
	::application::media::SyncBoardGoto 2
	set early [list [lindex [::media::sync::config] 1] [::dialog::notice::count]]
	::application::media::SyncBoardGoto 1
	list $early [lindex [::media::sync::config] 1] [::dialog::notice::count]
} -cleanup {
	foreach c {::scidb::game::go ::scidb::game::fen} {
		rename $c {}
		rename $c.owner $c
	}
	if {$::scidb::test::owner::HadPos} {
		set ::application::media::Priv(lessonPositions) $::scidb::test::owner::SavedPos
	} else {
		unset -nocomplain ::application::media::Priv(lessonPositions)
	}
	::media::sync::set-config $::scidb::test::owner::T $::scidb::test::owner::F
	foreach c $::dialog::notice::Cards { ::dialog::notice::Dismiss [lindex $c 0] }
} -result {{1 0} 0 1}

::tcltest::cleanupTests
return
