# ======================================================================
# Scidb App Test Suite - board synchronization (tests/test_app_board_sync.tcl)
# ======================================================================
package require Tcl 8.5
package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]

namespace eval ::scidb::test::boardsync {
	variable testDir [file dirname [file normalize [info script]]]
	variable BaseOpened ""
	variable SavedVariationPosition

	proc nop {args} { return 0 }

	# The long game the tester reported with: 600 moves, a long comment on
	# every White move and a side line after every tenth Black move.  It is
	# scratch (tests/tmp-app is not tracked), so the test writes it.
	proc writeFixture {path} {
		file mkdir [file dirname $path]
		set tokens {}
		for {set i 1} {$i <= 600} {incr i} {
			set white [expr {$i % 2 ? "Nf3" : "Ng1"}]
			set black [expr {$i % 2 ? "Nf6" : "Ng8"}]
			lappend tokens "$i. $white {Move $i: a long comment [string repeat x 80]}"
			lappend tokens $black
			if {$i % 10 == 1} {
				lappend tokens "($i... Nc6 [expr {$i + 1}]. Nc3 {side line})"
			}
		}
		# written aside and renamed, so two test runs cannot read half a file
		set tmp "$path.[pid].tmp"
		set fh [open $tmp w]
		fconfigure $fh -encoding utf-8
		puts $fh "\[Event \"Huge\"\]"
		puts $fh "\[White \"Long\"\]"
		puts $fh "\[Black \"Game\"\]"
		puts $fh "\[Result \"1/2-1/2\"\]"
		puts $fh ""
		puts $fh "[join $tokens { }] 1/2-1/2"
		puts $fh ""
		close $fh
		file rename -force $tmp $path
	}

	proc findFixture {} {
		variable testDir
		set candidates [list \
			[file join $testDir tmp-app board-lag huge.pgn] \
			[file join $testDir .. tests tmp-app board-lag huge.pgn] \
			[file join $testDir tmp-app huge.pgn] \
			[file join [pwd] tests tmp-app board-lag huge.pgn] \
		]
		foreach path $candidates {
			if {[file exists $path]} {
				return [file normalize $path]
			}
		}
		set path [lindex $candidates 0]
		writeFixture $path
		return [file normalize $path]
	}

	proc canvasBoard {w} {
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

	proc drainQueue {} {
		# Allow in-flight move animation timer (250ms) to complete and update
		after 300
		update
	}

	proc openFixture {} {
		variable BaseOpened
		variable SavedVariationPosition
		::scidb::test::wait::ready
		set SavedVariationPosition $::variation::Options(slide:position)
		# Right means forward in a vertical selector. In a horizontal one,
		# once its animation completes, Right changes the selected variation
		# instead; that made the 50-step oracle depend on event-loop speed.
		::variation::hide 0
		set ::variation::Options(slide:position) right
		catch { destroy .tipoftheday }
		::application::switchTab board
		update

		set pgn [findFixture]
		set BaseOpened $pgn
		::scidb::db::open $pgn ::scidb::test::boardsync::nop {} ::scidb::test::boardsync::nop {}
		::game::new .application -base $pgn -variant Normal -number 0
		::scidb::game::go -1 start
		update

		set canvas [::board::diagram::canvas $::application::board::board]
		focus -force $canvas
		update
	}

	proc closeFixture {} {
		variable BaseOpened
		variable SavedVariationPosition
		::variation::hide 0
		if {[info exists SavedVariationPosition]} {
			set ::variation::Options(slide:position) $SavedVariationPosition
		}
		catch { ::scidb::game::go -1 start }
		if {$BaseOpened ne ""} {
			catch { ::scidb::db::close $BaseOpened }
			set BaseOpened ""
		}
	}
}

tcltest::test boardsync-load {game 1 loads into Board tab with correct initial position} -setup {
	::scidb::test::boardsync::openFixture
} -body {
	set b $::application::board::board
	set ply [::scidb::game::ply]
	set fen [::scidb::game::fen]
	set boardData [::board::diagram::data $b]
	set canvBoard [::scidb::test::boardsync::canvasBoard $b]
	set expected [::scidb::board::fenToBoard [lindex [split $fen " "] 0]]

	list $ply \
		[expr {$boardData eq $expected}] \
		[expr {$canvBoard eq $expected}]
} -cleanup {
	::scidb::test::boardsync::closeFixture
} -result {0 1 1}

tcltest::test boardsync-right-50-no-update {50 Right-arrow steps without update catch up after queue drains} -setup {
	::scidb::test::boardsync::openFixture
} -body {
	set b $::application::board::board
	set canvas [::board::diagram::canvas $b]

	for {set i 1} {$i <= 50} {incr i} {
		event generate $canvas <KeyPress-Right> -keysym Right
	}

	set fenBefore [::scidb::game::fen]
	set expectedBefore [::scidb::board::fenToBoard [lindex [split $fenBefore " "] 0]]
	# In-memory board state immediately matches the current game position
	set dataMatchesBefore [expr {[::board::diagram::data $b] eq $expectedBefore}]

	# Wait for animation timer and drain event queue
	::scidb::test::boardsync::drainQueue

	set fenAfter [::scidb::game::fen]
	set expectedAfter [::scidb::board::fenToBoard [lindex [split $fenAfter " "] 0]]
	set canvMatchesAfter [expr {[::scidb::test::boardsync::canvasBoard $b] eq $expectedAfter}]
	set dataMatchesAfter [expr {[::board::diagram::data $b] eq $expectedAfter}]

	list [::scidb::game::ply] $dataMatchesBefore $dataMatchesAfter $canvMatchesAfter
} -cleanup {
	::scidb::test::boardsync::closeFixture
} -result {47 1 1 1}

tcltest::test boardsync-home-and-step {Home restores start position and 1 Right step moves 1.Nf3 with next move highlighted} -setup {
	::scidb::test::boardsync::openFixture
} -body {
	set b $::application::board::board
	set canvas [::board::diagram::canvas $b]
	set pgn $::application::pgn::Vars(pgn:0)

	# 10 steps forward first
	for {set i 1} {$i <= 10} {incr i} {
		event generate $canvas <KeyPress-Right> -keysym Right
	}
	::scidb::test::boardsync::drainQueue

	# Press Home
	event generate $canvas <KeyPress-Home> -keysym Home
	::scidb::test::boardsync::drainQueue

	set homePly [::scidb::game::ply]
	set homeExpected [::scidb::board::fenToBoard [lindex [split [::scidb::game::fen] " "] 0]]
	set homeCanvMatch [expr {[::scidb::test::boardsync::canvasBoard $b] eq $homeExpected}]
	# In notation, h:curr is empty at start; h:next highlights 1.Nf3
	set homeCurrTag [$pgn tag ranges h:curr]
	set homeNextText [$pgn get {*}[$pgn tag ranges h:next]]

	# One Right step
	event generate $canvas <KeyPress-Right> -keysym Right
	::scidb::test::boardsync::drainQueue

	set stepPly [::scidb::game::ply]
	set stepExpected [::scidb::board::fenToBoard [lindex [split [::scidb::game::fen] " "] 0]]
	set stepCanvMatch [expr {[::scidb::test::boardsync::canvasBoard $b] eq $stepExpected}]
	set stepCurrText [$pgn get {*}[$pgn tag ranges h:curr]]

	list $homePly $homeCanvMatch [expr {$homeCurrTag eq ""}] [string match "1.*" $homeNextText] \
		$stepPly $stepCanvMatch [string match "1.*" $stepCurrText]
} -cleanup {
	::scidb::test::boardsync::closeFixture
} -result {0 1 1 1 1 1 1}

tcltest::test boardsync-right-50-with-update {50 Right-arrow steps WITH update between them stay in sync} -setup {
	::scidb::test::boardsync::openFixture
} -body {
	set b $::application::board::board
	set canvas [::board::diagram::canvas $b]

	for {set i 1} {$i <= 50} {incr i} {
		event generate $canvas <KeyPress-Right> -keysym Right
		update
	}

	set fenBefore [::scidb::game::fen]
	set expectedBefore [::scidb::board::fenToBoard [lindex [split $fenBefore " "] 0]]
	set dataMatchesBefore [expr {[::board::diagram::data $b] eq $expectedBefore}]

	::scidb::test::boardsync::drainQueue

	set fenAfter [::scidb::game::fen]
	set expectedAfter [::scidb::board::fenToBoard [lindex [split $fenAfter " "] 0]]
	set canvMatchesAfter [expr {[::scidb::test::boardsync::canvasBoard $b] eq $expectedAfter}]
	set dataMatchesAfter [expr {[::board::diagram::data $b] eq $expectedAfter}]

	list [::scidb::game::ply] $dataMatchesBefore $dataMatchesAfter $canvMatchesAfter
} -cleanup {
	::scidb::test::boardsync::closeFixture
} -result {47 1 1 1}

tcltest::test boardsync-end {End key navigates to game end and board catches up immediately} -setup {
	::scidb::test::boardsync::openFixture
} -body {
	set b $::application::board::board
	set canvas [::board::diagram::canvas $b]

	event generate $canvas <KeyPress-End> -keysym End
	::scidb::test::boardsync::drainQueue

	set endExpected [::scidb::board::fenToBoard [lindex [split [::scidb::game::fen] " "] 0]]
	set canvMatches [expr {[::scidb::test::boardsync::canvasBoard $b] eq $endExpected}]
	set dataMatches [expr {[::board::diagram::data $b] eq $endExpected}]

	list [::scidb::game::ply] $dataMatches $canvMatches
} -cleanup {
	::scidb::test::boardsync::closeFixture
} -result {1200 1 1}

tcltest::test boardsync-right-proc-50-no-update {50 calls to goto +1 without update catch up after drain} -setup {
	::scidb::test::boardsync::openFixture
} -body {
	set b $::application::board::board

	for {set i 1} {$i <= 50} {incr i} {
		::application::board::goto +1
	}

	set fenBefore [::scidb::game::fen]
	set expectedBefore [::scidb::board::fenToBoard [lindex [split $fenBefore " "] 0]]
	set dataMatchesBefore [expr {[::board::diagram::data $b] eq $expectedBefore}]

	::scidb::test::boardsync::drainQueue

	set fenAfter [::scidb::game::fen]
	set expectedAfter [::scidb::board::fenToBoard [lindex [split $fenAfter " "] 0]]
	set canvMatchesAfter [expr {[::scidb::test::boardsync::canvasBoard $b] eq $expectedAfter}]
	set dataMatchesAfter [expr {[::board::diagram::data $b] eq $expectedAfter}]

	list [::scidb::game::ply] $dataMatchesBefore $dataMatchesAfter $canvMatchesAfter
} -cleanup {
	::scidb::test::boardsync::closeFixture
} -result {50 1 1 1}

tcltest::test boardsync-right-proc-50-with-update {50 calls to goto +1 WITH update catch up after drain} -setup {
	::scidb::test::boardsync::openFixture
} -body {
	set b $::application::board::board

	for {set i 1} {$i <= 50} {incr i} {
		::application::board::goto +1
		update
	}

	set fenBefore [::scidb::game::fen]
	set expectedBefore [::scidb::board::fenToBoard [lindex [split $fenBefore " "] 0]]
	set dataMatchesBefore [expr {[::board::diagram::data $b] eq $expectedBefore}]

	::scidb::test::boardsync::drainQueue

	set fenAfter [::scidb::game::fen]
	set expectedAfter [::scidb::board::fenToBoard [lindex [split $fenAfter " "] 0]]
	set canvMatchesAfter [expr {[::scidb::test::boardsync::canvasBoard $b] eq $expectedAfter}]
	set dataMatchesAfter [expr {[::board::diagram::data $b] eq $expectedAfter}]

	list [::scidb::game::ply] $dataMatchesBefore $dataMatchesAfter $canvMatchesAfter
} -cleanup {
	::scidb::test::boardsync::closeFixture
} -result {50 1 1 1}

tcltest::cleanupTests
