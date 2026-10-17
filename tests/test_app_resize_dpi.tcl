# ======================================================================
# Scidb App Test - resize and runtime DPI change (contract VAL-RSZ-001..003)
# ======================================================================
# VAL-RSZ-001: resizing the main window recomputes board, inset and pane
#              layout within 500 ms and keeps the window inside the work
#              area (WindowResized/KeepInWorkArea -> util::place::fitWindow).
# VAL-RSZ-002: a runtime `tk scaling` change (1.0 -> 2.0 -> 1.0) relays out
#              board, inset and panes via ::application::scalingChanged
#              (twm refresh, forced board rebuild, listeners).
# VAL-RSZ-003: tests/test_startup_geometry.tcl stays green.
#
# The reported time is the moment of the last visible change after the
# action: a layout that settles in one pass is not charged for the quiet
# window the sampler needs to be sure nothing else moves.
# ======================================================================
package require tcltest 2.5

namespace eval ::rsz {
	variable Quiet 260
	variable MinWidth 200
	variable Ticks {}
}

# The harness opens on Information and Startup2 (an after-1 timer) selects
# that tab once, so let it run, then reselect the board until the selection
# sticks and the notebook page is mapped and sized.
proc ::rsz::showBoard {{ms 6000}} {
	set nb .application.nb
	update
	after 40
	update
	set deadline [expr {[clock milliseconds] + $ms}]
	while {[clock milliseconds] < $deadline} {
		catch { $nb select .application.nb.board }
		update
		if {[$nb select] eq ".application.nb.board" && [winfo exists $nb.board] \
			&& [winfo ismapped $nb.board] && [winfo width $nb.board] > 100} {
			update
			if {[$nb select] eq ".application.nb.board"} { return 1 }
		}
		after 25
	}
	return 0
}

proc ::rsz::canvas {} { return $::application::board::Vars(widget:frame) }

# The board item, the pane and the inset, all in pane coordinates.
proc ::rsz::rects {} {
	set canv [::rsz::canvas]
	set pane [winfo parent $canv]
	set cx [winfo x $canv]
	set cy [winfo y $canv]
	set board {}
	set bb [$canv bbox board]
	if {[llength $bb] == 4} {
		lassign $bb x0 y0 x1 y1
		set board [list [expr {$cx + $x0}] [expr {$cy + $y0}] \
			[expr {$cx + $x1}] [expr {$cy + $y1}]]
	}
	set inset {}
	set w $pane.mediainset
	if {[winfo exists $w] && [winfo manager $w] ne ""} {
		set inset [list [winfo x $w] [winfo y $w] \
			[expr {[winfo x $w] + [winfo width $w]}] \
			[expr {[winfo y $w] + [winfo height $w]}]]
	}
	return [list board $board pane [list [winfo width $pane] [winfo height $pane]] inset $inset]
}

proc ::rsz::boardRect {} { return [dict get [::rsz::rects] board] }
proc ::rsz::insetRect {} { return [dict get [::rsz::rects] inset] }

# Pane geometries, to see that the pane layout followed the window.
proc ::rsz::panes {} {
	set twm .application.nb.board
	set r {}
	foreach uid {board editor games tree media} {
		if {[catch { set p [$twm leaf $uid] }] || ![winfo exists $p]} { continue }
		lappend r $uid [winfo width $p] [winfo height $p]
	}
	return $r
}

proc ::rsz::snapshot {} {
	set canv [::rsz::canvas]
	return [list [wm geometry .application] [::rsz::rects] \
		[list [winfo width $canv] [winfo height $canv]] [::rsz::panes]]
}

# Run <action>, pump events until nothing changed for Quiet ms, and return
# {lastChangeMs snapshot}. The board rebuild is scheduled 100 ms after the
# canvas <Configure> and the inset 120 ms after, so a sampler that stops at
# the first stable pair would miss them; the "before" snapshot is taken
# here, so a synchronous action counts too.
proc ::rsz::settle {action {timeout 2500} {quiet 260}} {
	set t0 [clock milliseconds]
	set prev [::rsz::snapshot]
	uplevel 1 $action
	set lastChange 0
	while {[clock milliseconds] - $t0 < $timeout} {
		update
		set now [::rsz::snapshot]
		set t [expr {[clock milliseconds] - $t0}]
		if {$now ne $prev} {
			set prev $now
			set lastChange $t
		}
		if {$t - $lastChange >= $quiet} { break }
		after 10
	}
	return [list $lastChange $prev]
}

proc ::rsz::setScaling {scale} {
	tk scaling $scale
	::application::scalingChanged
}

# Show the video inset; a low minimum width so it can sit in a free margin
# beside the board even on the narrower board pane on a 1920 px screen.
proc ::rsz::showInset {} {
	set ::mediainset::Options(minWidth) 100
	::mediainset::surface .noSuchViewer
}
proc ::rsz::hideInset {} {
	catch { ::mediainset::hide }
	set ::mediainset::Options(minWidth) $::rsz::MinWidth
}

# Do not leak the test's scaling into the rest of the suite.
proc ::rsz::saveScaling {} { set ::rsz::SavedScaling [tk scaling] }
proc ::rsz::restoreScaling {} {
	if {[info exists ::rsz::SavedScaling]} {
		catch { ::rsz::setScaling $::rsz::SavedScaling }
	}
}

# True when the window is inside the work area by the codebase's own
# convention (clampGeometry is a no-op).
proc ::rsz::inside {w} {
	set geometry [wm geometry $w]
	return [expr {
		[::util::place::clampGeometry $geometry [winfo workarea $w] [winfo extents $w]] eq $geometry
	}]
}

proc ::rsz::overlap? {} {
	set board [::rsz::boardRect]
	set inset [::rsz::insetRect]
	if {[llength $board] != 4 || [llength $inset] != 4} { return 0 }
	lassign $board bx0 by0 bx1 by1
	lassign $inset ix0 iy0 ix1 iy1
	return [expr {$bx0 < $ix1 && $ix0 < $bx1 && $by0 < $iy1 && $iy0 < $by1}]
}


# ---------------------------------------------------------------- VAL-RSZ-001

# A window resize must recompute board, inset and panes within 500 ms.
tcltest::test rsz-resize-recomputes {a resize relays out board, pane and inset within 500 ms} -setup {
	::rsz::showBoard
	::rsz::showInset
} -body {
	::rsz::settle {wm geometry .application 1100x760+260+120}
	set before [::rsz::rects]
	set panesBefore [::rsz::panes]
	lassign [::rsz::settle {wm geometry .application 1500x950+180+60}] ms after
	set changed [expr {[::rsz::rects] ne $before && [::rsz::panes] ne $panesBefore}]
	puts "EVIDENCE rsz-resize settleMs=$ms changed=$changed inside=[::rsz::inside .application] overlap=[::rsz::overlap?] rects=[::rsz::rects]"
	list [expr {$ms > 0 && $ms <= 500}] $changed [::rsz::inside .application] [::rsz::overlap?]
} -cleanup {
	::rsz::hideInset
} -result {1 1 1 0}

# Kept inside the work area even when the requested size is larger than it.
tcltest::test rsz-resize-workarea {an oversized resize is clamped into the work area} -body {
	::rsz::showBoard
	lassign [::rsz::settle {wm geometry .application 2400x1400+0+0}] ms after
	puts "EVIDENCE rsz-workarea settleMs=$ms geom=[wm geometry .application] inside=[::rsz::inside .application]"
	list [expr {$ms <= 500}] [::rsz::inside .application] \
		[expr {[winfo width .application] <= [lindex [winfo workarea .application] 2]}]
} -result {1 1 1}

# A pure move inside the work area must not be yanked back by the clamp.
tcltest::test rsz-move-not-yanked {a move inside the work area is not reclamped} -setup {
	::rsz::showBoard
	::rsz::settle {wm geometry .application 1100x760+260+120}
} -body {
	::rsz::settle {wm geometry .application +300+150} 900 200
	set geom [wm geometry .application]
	puts "EVIDENCE rsz-move geom=$geom inside=[::rsz::inside .application]"
	list $geom [::rsz::inside .application]
} -result {1100x760+300+150 1}

# ---------------------------------------------------------------- VAL-RSZ-002

# Runtime scaling 1.0 -> 2.0 -> 1.0 relays out board, inset and panes.
tcltest::test rsz-scaling-roundtrip {tk scaling 1.0 -> 2.0 -> 1.0 relays out and back within 500 ms} -setup {
	::rsz::saveScaling
	::rsz::showBoard
	::rsz::showInset
} -body {
	::rsz::settle {wm geometry .application 1500x900+200+80}
	set times {}
	set boards {}
	set insets {}
	set overlaps {}
	set inside {}
	set borders {}
	foreach scale {1.0 2.0 1.0} {
		lassign [::rsz::settle [list ::rsz::setScaling $scale]] ms after
		lappend times [expr {$ms > 0 && $ms <= 500}]
		lappend boards [::rsz::boardRect]
		lappend insets [::rsz::insetRect]
		lappend overlaps [::rsz::overlap?]
		lappend inside [::rsz::inside .application]
		lappend borders $::application::board::Dim(borderthickness)
		puts "EVIDENCE rsz-scaling scale=$scale settleMs=$ms geom=[wm geometry .application] board=[::rsz::boardRect] inset=[::rsz::insetRect] border=$::application::board::Dim(borderthickness) overlap=[::rsz::overlap?]"
	}
	# 2.0 relayout must differ (border margins follow tk scaling) and 1.0
	# must restore the 1.0 geometry. No scaling may overlap board/inset.
	list $times \
		[expr {[lindex $boards 0] ne [lindex $boards 1] || [lindex $insets 0] ne [lindex $insets 1]}] \
		[expr {[lindex $boards 0] eq [lindex $boards 2] && [lindex $insets 0] eq [lindex $insets 2]}] \
		[expr {[lindex $borders 1] > [lindex $borders 0]}] \
		$overlaps $inside
} -cleanup {
	::rsz::hideInset
	::rsz::restoreScaling
} -result {{1 1 1} 1 1 1 {0 0 0} {1 1 1}}

proc ::rsz::noteListener {} { lappend ::rsz::Ticks [tk scaling] }

# The entry point refreshes every twm and notifies each listener once.
tcltest::test rsz-scaling-notifies {scalingChanged notifies registered listeners} -setup {
	::rsz::saveScaling
} -body {
	::rsz::showBoard
	set ::rsz::Ticks {}
	::application::addScalingListener {::rsz::noteListener}
	::application::scalingChanged
	::application::scalingChanged
	update
	::application::removeScalingListener {::rsz::noteListener}
	puts "EVIDENCE rsz-notifies ticks=$::rsz::Ticks"
	llength $::rsz::Ticks
} -cleanup {
	::rsz::restoreScaling
} -result 2

# ---------------------------------------------------------------- VAL-RSZ-003

tcltest::test rsz-startup-geometry {headless startup geometry regression stays green} -body {
	set script [file join [file dirname [info script]] test_startup_geometry.tcl]
	set rc [catch {exec [auto_execok tclsh] $script} out opts]
	puts "EVIDENCE rsz-startup-geometry rc=$rc [string trim [lindex [split $out \n] end-1]]"
	list $rc [regexp {Failed\s+0} $out]
} -result {0 1}

tcltest::cleanupTests
