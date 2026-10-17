# ======================================================================
# Scidb App Test — shared beside-board dialog placement helper
# (VAL-DLG-001..004: tcl/utils/place.tcl, tcl/play-engine.tcl,
#  tcl/guess-move.tcl, tcl/game-review.tcl, tcl/repertoire-trainer.tcl,
#  tcl/insights.tcl, tcl/annotation.tcl)
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::dlgplace {
	variable testDir [file dirname [file normalize [info script]]]
}

# Rectangles are {x y w h}; returns the intersection area (0 when disjoint).
proc ::scidb::test::dlgplace::overlapArea {r1 r2} {
	lassign $r1 x1 y1 w1 h1
	lassign $r2 x2 y2 w2 h2
	set ox [expr {max(0, min($x1 + $w1, $x2 + $w2) - max($x1, $x2))}]
	set oy [expr {max(0, min($y1 + $h1, $y2 + $h2) - max($y1, $y2))}]
	return [expr {$ox * $oy}]
}

proc ::scidb::test::dlgplace::widgetRect {w} {
	update idletasks
	return [list [winfo rootx $w] [winfo rooty $w] [winfo width $w] [winfo height $w]]
}

# Set up the application window on the board tab at a given geometry.
proc ::scidb::test::dlgplace::setupBoardAt {geom} {
	::application::switchTab board
	wm state .application normal
	wm geometry .application $geom
	update
	after 50 { set ::scidb::test::dlgplace::settled 1 }
	vwait ::scidb::test::dlgplace::settled
	update
	update idletasks
	return [widgetRect $::application::board::board]
}

# ----------------------------------------------------------------------
# VAL-DLG-001: Shared placement helper arithmetic (headless unit cases)
# ----------------------------------------------------------------------

tcltest::test dlgplace-001-arithmetic {besidePosition places right, else left, else below, clamped to real work area incl. negative origins and Run 37 layout} -body {
	set out {}
	# Run 37 layout cases (1920x1080 workarea, default extents {16 0 40 0}, dialog 323x215):
	lappend out [::util::place::besidePosition 300 100 600 600 323 215 {0 0 1920 1080}]
	lappend out [::util::place::besidePosition 1000 200 860 860 323 215 {0 0 1920 1080}]
	lappend out [::util::place::besidePosition 0 0 1920 800 323 215 {0 0 1920 1080}]
	# Taskbar excluded (workarea height 1040 vs 1080 screen; top bar 28 px):
	lappend out [::util::place::besidePosition 100 850 500 500 323 215 {0 28 1920 1012} {6 6 30 6}]
	# Multi-monitor negative origin (secondary monitor at -1920,0 size 1920x1040):
	lappend out [::util::place::besidePosition -1600 120 600 600 320 220 {-1920 0 1920 1040} {6 6 30 6}]
	lappend out [::util::place::besidePosition -900 120 860 860 320 220 {-1920 0 1920 1040} {6 6 30 6}]
	# Play-engine BesidePosition wrapper delegates to besidePosition:
	lappend out [::playengine::BesidePosition 1000 200 860 860 323 215 1920 1080]
	set out
} -result {{912 100 323 215} {649 200 323 215} {0 812 323 215} {612 789 323 215} {-988 120 320 220} {-1244 120 320 220} {649 200}}

# ----------------------------------------------------------------------
# VAL-DLG-002: Board-time dialogs open beside the board (1920x1080 & 1280x800)
# ----------------------------------------------------------------------

tcltest::testConstraint screen1920 [expr {
	[winfo screenwidth .application] >= 1920 && [winfo screenheight .application] >= 1080
}]

foreach {label geom constraints} {
	1920x1080 1920x1080+0+0 screen1920
	1280x800  1280x800+0+0  {}
} {
	tcltest::test dlgplace-002-board-dialogs-$label "Play Against Engine, Guess the Move and Repertoire trainer avoid the board at $label" -constraints $constraints -setup {
		set savedGeom [wm geometry .application]
		::scidb::game::clear {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}
		update
		foreach san {e4 e5 Nf3 Nc6} { ::move::addMove menu $san }
		::scidb::game::go -1 start
		update
		::scidb::test::dlgplace::setupBoardAt $geom
	} -body {
		# 1. Play Against Engine
		set b1 [::scidb::test::dlgplace::widgetRect $::application::board::board]
		set peDlg [::playengine::open .application]
		update
		set peRect [::scidb::test::dlgplace::widgetRect $peDlg]
		set peOverlap [::scidb::test::dlgplace::overlapArea $b1 $peRect]
		::playengine::Close

		# 2. Guess the Move
		set b2 [::scidb::test::dlgplace::widgetRect $::application::board::board]
		::guessmove::start white
		update
		set gmDlg $::guessmove::Priv(dialog)
		set gmRect [::scidb::test::dlgplace::widgetRect $gmDlg]
		set gmOverlap [::scidb::test::dlgplace::overlapArea $b2 $gmRect]
		::guessmove::stop
		catch { destroy $gmDlg }

		# 3. Repertoire trainer
		set b3 [::scidb::test::dlgplace::widgetRect $::application::board::board]
		::reptrainer::open .application
		update
		set rtDlg .application.__reptrainer__
		set rtRect [::scidb::test::dlgplace::widgetRect $rtDlg]
		set rtOverlap [::scidb::test::dlgplace::overlapArea $b3 $rtRect]
		::reptrainer::Close $rtDlg

		puts "VAL-DLG-002 ($label): board=$b1 playengine=$peRect (overlap=$peOverlap) guessmove=$gmRect (overlap=$gmOverlap) reptrainer=$rtRect (overlap=$rtOverlap)"
		list $peOverlap $gmOverlap $rtOverlap
	} -cleanup {
		catch { ::playengine::Close }
		catch { ::guessmove::stop }
		catch { destroy $::guessmove::Priv(dialog) }
		catch { ::reptrainer::Close .application.__reptrainer__ }
		catch { wm geometry .application $savedGeom; update }
	} -result {0 0 0}
}

# ----------------------------------------------------------------------
# VAL-DLG-003: Review, insights, annotation avoid the board (1920x1080 & 1280x800)
# ----------------------------------------------------------------------

proc ::scidb::test::dlgplace::openInsightsFixture {} {
	variable testDir
	set dir [file join $testDir tmp-app dlgplace_ins_[pid]]
	file mkdir $dir
	set pgn [file join $dir fixture.pgn]
	set ch [open $pgn w]
	puts $ch {[Event "Test"]}
	puts $ch {[Site "?"]}
	puts $ch {[Date "2024.01.01"]}
	puts $ch {[Round "1"]}
	puts $ch {[White "Me"]}
	puts $ch {[Black "Opp"]}
	puts $ch {[Result "1-0"]}
	puts $ch {[ECO "C60"]}
	puts $ch ""
	puts $ch "1. e4 e5 2. Nf3 Nc6 3. Bb5 1-0"
	close $ch
	proc nop {args} { return 0 }
	catch { ::scidb::db::close $pgn }
	::scidb::db::open $pgn ::scidb::test::dlgplace::nop {} ::scidb::test::dlgplace::nop {}
	set n [::scidb::db::count players $pgn Normal]
	set meIdx -1
	for {set i 0} {$i < $n} {incr i} {
		set k [::scidb::db::get playerKey $pgn Normal $i]
		if {[lindex $k 0] eq "Me"} { set meIdx $i; break }
	}
	return [list $pgn $meIdx]
}

foreach {label geom constraints} {
	1920x1080 1920x1080+0+0 screen1920
	1280x800  1280x800+0+0  {}
} {
	tcltest::test dlgplace-003-review-insights-annotation-$label "Game Review (both dialogs), Insights and Annotation popup avoid the board at $label" -constraints $constraints -setup {
		set savedGeom [wm geometry .application]
		set savedPos $::annotation::Position
		set ::annotation::Position {}
		catch { destroy .application.__annotation__ }
		set ::annotation::Vars(dialog) {}
		lassign [::scidb::test::dlgplace::openInsightsFixture] insBase insIdx
		::scidb::game::clear {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}
		update
		foreach san {e4 e5 Nf3 Nc6} { ::move::addMove menu $san }
		::scidb::game::go -1 start
		update
		::scidb::test::dlgplace::setupBoardAt $geom
	} -body {
		# 1. Game Review progress dialog
		set b1 [::scidb::test::dlgplace::widgetRect $::application::board::board]
		set ::gamereview::Priv(total) 4
		::gamereview::ShowProgress .application
		update
		set grProgDlg .application.__gamereview_progress
		set grProgRect [::scidb::test::dlgplace::widgetRect $grProgDlg]
		set grProgOverlap [::scidb::test::dlgplace::overlapArea $b1 $grProgRect]
		destroy $grProgDlg

		# 2. Game Review results dialog
		set b2 [::scidb::test::dlgplace::widgetRect $::application::board::board]
		set review [::gamereview::classify {
			{san e4 before 0 after 0 best 1}
			{san e5 before 0 after -250 best 0}
		}]
		::gamereview::ShowWindow .application $review {} 0
		update
		set grWinDlg .application.__gamereview
		set grWinRect [::scidb::test::dlgplace::widgetRect $grWinDlg]
		set grWinOverlap [::scidb::test::dlgplace::overlapArea $b2 $grWinRect]
		destroy $grWinDlg

		# 3. Insights dialog
		set b3 [::scidb::test::dlgplace::widgetRect $::application::board::board]
		set insDlg [::insights::show .application $insBase Normal $insIdx]
		update
		set insRect [::scidb::test::dlgplace::widgetRect $insDlg]
		set insOverlap [::scidb::test::dlgplace::overlapArea $b3 $insRect]
		destroy $insDlg

		# 4. Annotation popup (no saved offset)
		set b4 [::scidb::test::dlgplace::widgetRect $::application::board::board]
		::annotation::open .application
		update
		set annDlg .application.__annotation__
		set annRect [::scidb::test::dlgplace::widgetRect $annDlg]
		set annOverlap [::scidb::test::dlgplace::overlapArea $b4 $annRect]
		::annotation::close
		destroy $annDlg
		set ::annotation::Vars(dialog) {}

		puts "VAL-DLG-003 ($label): board=$b1 gr_progress=$grProgRect (overlap=$grProgOverlap) gr_window=$grWinRect (overlap=$grWinOverlap) insights=$insRect (overlap=$insOverlap) annotation=$annRect (overlap=$annOverlap)"
		list $grProgOverlap $grWinOverlap $insOverlap $annOverlap
	} -cleanup {
		catch { destroy .application.__gamereview_progress }
		catch { destroy .application.__gamereview }
		catch { destroy [::insights::DialogName $insBase Normal $insIdx] }
		catch { ::scidb::db::close $insBase }
		catch { file delete -force [file dirname $insBase] }
		catch { destroy .application.__annotation__ }
		set ::annotation::Vars(dialog) {}
		set ::annotation::Position $savedPos
		catch { wm geometry .application $savedGeom; update }
	} -result {0 0 0 0}
}

# ----------------------------------------------------------------------
# VAL-DLG-004: No-room fallback keeps dialogs usable
# ----------------------------------------------------------------------

tcltest::test dlgplace-004-no-room-fallback {when neither side nor below fits, dialog is clamped fully on screen with buttons visible and board overlap minimised} -setup {
	set savedGeom [wm geometry .application]
	::scidb::test::dlgplace::setupBoardAt 1920x1080+0+0
} -body {
	# 1. Arithmetic no-room test: a 1024x600 screen where the board occupies
	#    x=100..900, y=20..580 (800x560); right has 124 px, left has 100 px,
	#    below has 20 px. Dialog 360x260 with extents {6 6 30 6} cannot fit
	#    without overlap; rule picks right far edge (spaceRight 124 >= spaceLeft 100),
	#    x = 1024 - 360 - 12 = 652, y = 20, clamped in {0 0 1024 600}.
	set posRight [::util::place::besidePosition 100 20 800 560 360 260 {0 0 1024 600} {6 6 30 6}]
	# When left has more space (board at x=200..950 -> spaceRight=74, spaceLeft=200),
	# rule aligns to left workarea edge x=0.
	set posLeft  [::util::place::besidePosition 200 20 750 560 360 260 {0 0 1024 600} {6 6 30 6}]

	# 2. GUI test on a simulated small work area (800x500) where the board fills
	#    most of the work area: open Play Against Engine and Repertoire Trainer,
	#    verify the dialog and its action buttons stay completely inside the work area.
	rename ::winfo ::scidb::test::dlgplace::orig_winfo
	proc ::winfo {args} {
		set cmd [lindex $args 0]
		if {$cmd eq "workarea"} { return {0 0 800 500} }
		if {$cmd eq "workareawidth"} { return 800 }
		if {$cmd eq "workareaheight"} { return 500 }
		return [uplevel 1 ::scidb::test::dlgplace::orig_winfo $args]
	}

	set peDlg [::playengine::open .application]
	update
	set peRect [::scidb::test::dlgplace::widgetRect $peDlg]
	set okRect [::scidb::test::dlgplace::widgetRect $peDlg.ok]
	set cancelRect [::scidb::test::dlgplace::widgetRect $peDlg.cancel]
	lassign $peRect px py pw ph
	lassign $okRect ox oy ow oh
	lassign $cancelRect cx cy cw ch
	set peOnScreen [expr {$px >= 0 && $py >= 0 && $px + $pw <= 800 && $py + $ph <= 500}]
	set okVisible  [expr {[winfo ismapped $peDlg.ok] && $ox >= 0 && $oy >= 0 && $ox + $ow <= 800 && $oy + $oh <= 500}]
	set cancelVisible [expr {[winfo ismapped $peDlg.cancel] && $cx >= 0 && $cy >= 0 && $cx + $cw <= 800 && $cy + $ch <= 500}]
	::playengine::Close

	puts "VAL-DLG-004: posRight=$posRight posLeft=$posLeft peRect=$peRect okRect=$okRect cancelRect=$cancelRect"
	list $posRight $posLeft $peOnScreen $okVisible $cancelVisible
} -cleanup {
	catch { ::playengine::Close }
	if {[info commands ::scidb::test::dlgplace::orig_winfo] ne ""} {
		rename ::winfo {}
		rename ::scidb::test::dlgplace::orig_winfo ::winfo
	}
	catch { wm geometry .application $savedGeom; update }
} -result {{652 20 360 260} {0 20 360 260} 1 1 1}

tcltest::cleanupTests
