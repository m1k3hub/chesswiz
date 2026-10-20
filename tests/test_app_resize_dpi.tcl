# ======================================================================
# Scidb App Test - resize and runtime DPI change (contract VAL-RSZ-001..005,
# VAL-RSZ-007)
# ======================================================================
# VAL-RSZ-001: resizing the main window recomputes board, inset and pane
#              layout within 500 ms and keeps the window inside the work
#              area (WindowResized/KeepInWorkArea -> util::place::fitWindow).
# VAL-RSZ-002: a runtime `tk scaling` change (1.0 -> 2.0 -> 1.0) relays out
#              board, inset and panes via ::application::scalingChanged
#              (twm refresh, forced board rebuild, listeners).
# VAL-RSZ-003: tests/test_startup_geometry.tcl stays green, and a saved
#              off-screen/oversized Options(window:geometry) opens inside
#              the Xvfb work area.
# VAL-RSZ-004: a changed work area re-clamps the window on the next size
#              change; a pure move inside the work area is not yanked. On
#              X11 winfo workarea is one desktop-wide rect, so the changed
#              monitor/taskbar is scripted (stub rects, incl. negative origin).
# VAL-RSZ-005: the window minimum honours wm minsize, pane minimums and the
#              board square minimum (or BRD-004 corner fallback); resizing
#              back restores the layout.
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
		[list [winfo width $canv] [winfo height $canv]] [::rsz::panes] \
		$::application::board::Dim(borderthickness)]
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
	# Distinguish a synchronous change that lands inside the first
	# millisecond (report 1, "changed") from no change at all (report 0).
	set lastChange -1
	while {[clock milliseconds] - $t0 < $timeout} {
		update
		set now [::rsz::snapshot]
		set t [expr {[clock milliseconds] - $t0}]
		if {$now ne $prev} {
			set prev $now
			set lastChange [expr {max($t, 1)}]
		}
		if {$lastChange >= 0 && $t - $lastChange >= $quiet} { break }
		after 10
	}
	return [list [expr {$lastChange < 0 ? 0 : $lastChange}] $prev]
}

proc ::rsz::setScaling {scale} {
	tk scaling $scale
	::application::scalingChanged
}

# Change tk scaling behind the application's ::tk setter wrapper, the way an
# OS-level DPI change would (VAL-RSZ-007). The display watch, not this test,
# must notice it and run the relayout.
proc ::rsz::rawScaling {scale} {
	if {[info commands ::__application_tk_orig] ne ""} {
		::__application_tk_orig scaling $scale
	} else {
		tk scaling $scale
	}
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

# BRD-004 arithmetic, computed here rather than trusting FitStrip: the
# minimum strip on a side carries a >=160 px video (frame adds 8 px) and
# must still leave squares >= MinimumReserveSquare. reserveSquare uses the
# board renderer's own decoration/DPI arithmetic, so this holds at every
# tk scaling.
proc ::rsz::minimumStripSquare {side} {
	set view [::mediainset::BoardView]
	set pane [winfo parent $view]
	set w $pane.mediainset
	set ch [expr {[winfo reqheight $w.controls] + 8}]
	set width [winfo width $view]
	set height [winfo height $view]
	if {$side eq "right"} {
		return [::application::board::reserveSquare right 168 $width $height]
	}
	set aspect $::mediainset::Aspect
	set px [expr {int(round(160/$aspect)) + $ch}]
	return [::application::board::reserveSquare bottom $px $width $height]
}

# True only when the documented BRD-004 condition holds: no strip (right
# or bottom) with a >=160 px video fits with squares >= the minimum.
proc ::rsz::brd004? {} {
	set view [::mediainset::BoardView]
	set pane [winfo parent $view]
	set w $pane.mediainset
	set ch [expr {[winfo reqheight $w.controls] + 8}]
	set choice [::mediainset::FitStrip [winfo width $view] [winfo height $view] $ch]
	set minimum $::application::board::MinimumReserveSquare
	return [expr {![llength $choice]
		&& [::rsz::minimumStripSquare right] < $minimum
		&& [::rsz::minimumStripSquare bottom] < $minimum}]
}

# Zero overlap, or exactly the BRD-004 corner overlay when the arithmetic
# proves no minimum strip fits at the current scaling. A reserved strip
# must never overlap.
proc ::rsz::overlapOk? {tag} {
	set overlap [::rsz::overlap?]
	if {!$overlap} { return 1 }
	set brd [::rsz::brd004?]
	set reserve $::application::board::ReserveSide
	set corner [::rsz::insetCorner?]
	set minimum $::application::board::MinimumReserveSquare
	puts "EVIDENCE $tag overlap=1 brd004=$brd reserve={$reserve} corner=$corner right=[::rsz::minimumStripSquare right] bottom=[::rsz::minimumStripSquare bottom] min=$minimum"
	return [expr {$brd && $reserve eq "" && $corner}]
}

# Pump events for <ms> without changing the geometry.
proc ::rsz::wait {ms} {	set ::rsz::Waiting 0
	after $ms {set ::rsz::Waiting 1}
	vwait ::rsz::Waiting
	update idletasks
}

# Flatten nested {rects panes} lists and compare numbers within <tol>.
proc ::rsz::flat {value} {
	set out {}
	foreach item $value {
		if {[llength $item] > 1} {
			lappend out {*}[::rsz::flat $item]
		} else {
			lappend out $item
		}
	}
	return $out
}
proc ::rsz::near {a b {tol 1}} {
	set a [::rsz::flat $a]
	set b [::rsz::flat $b]
	if {[llength $a] != [llength $b]} { return 0 }
	foreach x $a y $b {
		if {[string is integer -strict $x] && [string is integer -strict $y]} {
			if {abs($x - $y) > $tol} { return 0 }
		} elseif {$x ne $y} {
			return 0
		}
	}
	return 1
}

# Count the three relayout entry points for the "settled means quiet" part of
# VAL-RSZ-001. The twm's load subcommand goes through the native command, so a
# command trace sees it without touching the widget.
proc ::rsz::countCmd {name cmd op} { incr ::rsz::Counter($name) }
proc ::rsz::countTwm {cmd op} {
	if {[lindex $cmd 1] eq "load"} { incr ::rsz::Counter(load) }
}
proc ::rsz::tracesOn {} {
	::rsz::tracesOff
	array set ::rsz::Counter {RebuildBoard 0 Relayout 0 load 0}
	trace add execution ::application::board::RebuildBoard enter [list ::rsz::countCmd RebuildBoard]
	trace add execution ::mediainset::Relayout enter [list ::rsz::countCmd Relayout]
	trace add execution ::scidb::tk::twm enter ::rsz::countTwm
}
proc ::rsz::tracesOff {} {
	catch { trace remove execution ::application::board::RebuildBoard enter [list ::rsz::countCmd RebuildBoard] }
	catch { trace remove execution ::mediainset::Relayout enter [list ::rsz::countCmd Relayout] }
	catch { trace remove execution ::scidb::tk::twm enter ::rsz::countTwm }
}
proc ::rsz::counterSnapshot {} {
	if {![info exists ::rsz::Counter]} { return {} }
	return [array get ::rsz::Counter]
}

# The window is inside <area> by the codebase's own rule (clampGeometry is a
# no-op).
proc ::rsz::insideArea {w area} {
	set geometry [wm geometry $w]
	return [expr {
		[::util::place::clampGeometry $geometry $area [winfo extents $w]] eq $geometry
	}]
}

# A wide (non-reflow) window geometry that fits the current work area, so
# the same test runs on 1920x1080, 1280x800 and 1080x1920 Xvfb screens.
proc ::rsz::wideGeometry {scale {aspect 1.6} {margin 30}} {
	lassign [winfo workarea .application] wx wy ww wh
	set w [expr {int(($ww - 2*$margin) * $scale)}]
	set h [expr {min($wh - 2*$margin, int($w / $aspect))}]
	set x [expr {$wx + max(0, ($ww - $w)/2)}]
	set y [expr {$wy + max(0, ($wh - $h)/2)}]
	return "${w}x${h}+${x}+${y}"
}

# Run <script> with `winfo workarea .application` reporting <area>. X11 has a
# single desktop-wide work area, so this is how a monitor/taskbar move is
# scripted for the arithmetic that a real Windows/macOS monitor move drives.
proc ::rsz::withWorkArea {area script} {
	if {[info commands ::rsz::realWinfo] eq ""} { rename ::winfo ::rsz::realWinfo }
	set ::rsz::StubWorkArea $area
	proc ::winfo {args} {
		if {[lindex $args 0] eq "workarea" && [lindex $args 1] eq ".application"} {
			return $::rsz::StubWorkArea
		}
		return [uplevel 1 [linsert $args 0 ::rsz::realWinfo]]
	}
	try {
		uplevel 1 $script
	} finally {
		catch { rename ::winfo {} }
		rename ::rsz::realWinfo ::winfo
	}
}

# Every visible pane must still be at least its panedwindow -minsize.
proc ::rsz::paneMins {} {
	set t .application.nb.board
	set bad {}
	foreach uid {board editor games tree media analysis explorer} {
		if {[catch { set leaf [$t leaf $uid] }] || ![winfo exists $leaf]} { continue }
		set node $leaf
		set pw ""
		while {1} {
			if {[catch { set p [$t parent $node] }] || $p eq "" || $p eq $t} { break }
			if {[$t ispanedwindow $p]} { set pw $p; break }
			set node $p
		}
		if {$pw eq "" || ![winfo ismapped $node]} { continue }
		set minimum [$pw panecget $node -minsize]
		if {![string is integer -strict $minimum] || $minimum < 1} { continue }
		set dim [expr {[$pw cget -orient] eq "horizontal" ? "width" : "height"}]
		if {[winfo $dim $node] < $minimum} {
			lappend bad [list $uid [winfo $dim $node] $minimum]
		}
	}
	return $bad
}

# The inset's own frame in the expanded state: inset by FrameMargin, with the
# small board framed and offset from the transport cluster.
proc ::rsz::frameState {} {
	set w [::mediainset::Pane].mediainset
	set view [::mediainset::BoardView]
	set pane [winfo parent $w]
	set m $::mediainset::FrameMargin
	set gap $::mediainset::BoardGap
	return [list \
		[expr {[winfo x $w] == $m && [winfo y $w] == $m}] \
		[expr {[winfo width $w] == [winfo width $pane] - 2*$m \
			&& [winfo height $w] == [winfo height $pane] - 2*$m}] \
		[$view cget -highlightthickness] \
		[winfo manager $view] \
		[expr {[winfo x $view] == $gap && [winfo y $view] == $gap}]]
}

proc ::rsz::insetCorner? {} {
	set w [::mediainset::Pane].mediainset
	if {![winfo exists $w] || [winfo manager $w] eq ""} { return 1 }
	return [expr {[dict get [place info $w] -anchor] eq "se"}]
}

# The visible board and inset lie inside their pane.
proc ::rsz::coherent? {} {
	set r [::rsz::rects]
	set board [dict get $r board]
	set pane [dict get $r pane]
	set inset [dict get $r inset]
	if {[llength $board] != 4 || [llength $pane] != 2} { return 0 }
	lassign $board bx0 by0 bx1 by1
	lassign $pane pw ph
	set boardOk [expr {$bx0 >= 0 && $by0 >= 0 && $bx1 <= $pw && $by1 <= $ph}]
	set insetOk [expr {[llength $inset] != 4 || (
		[lindex $inset 0] >= 0 && [lindex $inset 1] >= 0
		&& [lindex $inset 2] <= $pw && [lindex $inset 3] <= $ph)}]
	return [expr {$boardOk && $insetOk}]
}


# ---------------------------------------------------------------- VAL-RSZ-001

# A window resize must recompute board, inset and panes within 500 ms.
tcltest::test rsz-resize-recomputes {a resize relays out board, pane and inset within 500 ms} -setup {
	::rsz::showBoard
	::rsz::showInset
} -body {
	::rsz::settle [list wm geometry .application [::rsz::wideGeometry 0.70]]
	set before [::rsz::rects]
	set panesBefore [::rsz::panes]
	lassign [::rsz::settle [list wm geometry .application [::rsz::wideGeometry 0.90]]] ms after
	set changed [expr {[::rsz::rects] ne $before && [::rsz::panes] ne $panesBefore}]
	set overlapOk [::rsz::overlapOk? rsz-resize]
	puts "EVIDENCE rsz-resize settleMs=$ms changed=$changed inside=[::rsz::inside .application] overlap=$overlapOk rects=[::rsz::rects]"
	list [expr {$ms > 0 && $ms <= 500}] $changed [::rsz::inside .application] $overlapOk
} -cleanup {
	::rsz::hideInset
} -result {1 1 1 1}

# Kept inside the work area even when the requested size is larger than it.
tcltest::test rsz-resize-workarea {an oversized resize is clamped into the work area} -body {
	::rsz::showBoard
	lassign [winfo workarea .application] wx wy ww wh
	# Stay wide after clamping (a very tall result would also exercise the
	# reflow, which has its own tests) and make only the width oversized.
	set reqW [expr {$ww + 400}]
	set reqH [expr {min(750, $wh - 100)}]
	lassign [::rsz::settle [list wm geometry .application ${reqW}x${reqH}+0+0]] ms after
	puts "EVIDENCE rsz-workarea settleMs=$ms geom=[wm geometry .application] inside=[::rsz::inside .application] requested=${reqW}x${reqH}"
	list [expr {$ms <= 500}] [::rsz::inside .application] \
		[expr {[winfo width .application] <= [lindex [winfo workarea .application] 2]}]
} -result {1 1 1}

# A pure move inside the work area must not be yanked back by the clamp.
tcltest::test rsz-move-not-yanked {a move inside the work area is not reclamped} -setup {
	::rsz::showBoard
	set ::rsz::MoveGeometry [::rsz::wideGeometry 0.68]
	::rsz::settle [list wm geometry .application $::rsz::MoveGeometry]
} -body {
	::rsz::settle {wm geometry .application +120+90} 900 200
	set geom [wm geometry .application]
	set size [regexp -inline {^[0-9]+x[0-9]+} [wm geometry .application]]
	puts "EVIDENCE rsz-move geom=$geom inside=[::rsz::inside .application] expected=${size}+120+90"
	list [::rsz::inside .application] [expr {$geom eq "${size}+120+90"}]
} -result {1 1}

# ---------------------------------------------------------------- VAL-RSZ-002

# Runtime scaling 1.0 -> 2.0 -> 1.0 relays out board, inset and panes.
tcltest::test rsz-scaling-roundtrip {tk scaling 1.0 -> 2.0 -> 1.0 relays out and back within 500 ms} -setup {
	::rsz::saveScaling
	::rsz::showBoard
	::rsz::showInset
} -body {
	# Normalise to the contract's 1.0 baseline first: the app's startup
	# scaling (screen DPI) can already render the same border margin as
	# 1.0, making the first loop step a genuine no-op.
	::rsz::settle [list ::rsz::setScaling 1.0]
	::rsz::settle [list wm geometry .application [::rsz::wideGeometry 1.0 1.3 10]]
	# Make the 1.0 baseline a board rebuilt for the settled canvas: the
	# first paint can predate the notebook page size.
	set canv [::rsz::canvas]
	::rsz::settle [list ::application::board::ConfigureWindow $canv \
		[winfo width $canv] [winfo height $canv]]
	set g0 [wm geometry .application]
	set times {}
	set boards {}
	set insets {}
	set overlaps {}
	set inside {}
	set borders {}
	set panes {}
	foreach scale {1.0 2.0 1.0} {
		lassign [::rsz::settle [list ::rsz::setScaling $scale]] ms after
		# Step 1.0 is the no-op baseline; a synchronous relayout may
		# legitimately complete inside the first millisecond.
		lappend times [expr {$ms >= 0 && $ms <= 500}]
		lappend boards [::rsz::boardRect]
		lappend insets [::rsz::insetRect]
		lappend overlaps [::rsz::overlapOk? "rsz-scaling-$scale"]
		lappend inside [::rsz::inside .application]
		lappend borders $::application::board::Dim(borderthickness)
		lappend panes [::rsz::panes]
		puts "EVIDENCE rsz-scaling scale=$scale settleMs=$ms geom=[wm geometry .application] board=[::rsz::boardRect] inset=[::rsz::insetRect] border=$::application::board::Dim(borderthickness) square=$::application::board::Dim(squaresize:Normal) reserve=$::application::board::ReserveSide/$::application::board::ReservePixels canvas=[winfo width [::rsz::canvas]]x[winfo height [::rsz::canvas]] overlap=[::rsz::overlap?]"
	}
	# 2.0 relayout must differ (border margins follow tk scaling) and 1.0
	# must restore the 1.0 geometry. No scaling may overlap board/inset
	# except the BRD-004 corner overlay, and only when ::rsz::overlapOk?
	# recomputes that condition (no >=160 px strip at the minimum square).
	# The rule in ::application::scalingChanged says a fitting window keeps
	# its size.
	set g2 [wm geometry .application]
	# A relayout may show as a board/inset move, a scaling-dependent border
	# margin, or a pane size change (small screens keep the pane sizes).
	list $times \
		[expr {[lindex $boards 0] ne [lindex $boards 1] \
			|| [lindex $insets 0] ne [lindex $insets 1] \
			|| [lindex $borders 0] ne [lindex $borders 1] \
			|| [lindex $panes 0] ne [lindex $panes 1]}] \
		[expr {$g2 eq $g0 && [lindex $borders 0] eq [lindex $borders 2] && [::rsz::coherent?]}] \
		[expr {[lindex $borders 1] > [lindex $borders 0]}] \
		$overlaps $inside
} -cleanup {
	::rsz::hideInset
	::rsz::restoreScaling
} -result {{1 1 1} 1 1 1 {1 1 1} {1 1 1}}

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
	set rc [catch {::util::execSafe [auto_execok tclsh] $script} out opts]
	puts "EVIDENCE rsz-startup-geometry rc=$rc [string trim [lindex [split $out \n] end-1]]"
	list $rc [regexp {Failed\s+0} $out]
} -result {0 1}

# The saved Options(window:geometry) may come from a larger monitor or a
# session that ran off-screen; the app must open inside the current one.
tcltest::test rsz-startup-offscreen {a saved oversized/off-screen geometry opens inside the work area} -setup {
	set savedGeometry [wm geometry .application]
	set savedOption $::application::Options(window:geometry)
	set savedState $::application::Options(window:state)
	set savedMin [wm minsize .application]
} -body {
	::rsz::showBoard
	set ::application::Options(window:geometry) 4000x3000+1900+1050
	set ::application::Options(window:state) normal
	::application::RestoreWindowGeometry .application
	::rsz::wait 350
	set geometry [wm geometry .application]
	set inside [::rsz::inside .application]
	set fitsWidth [expr {[winfo width .application] <= [lindex [winfo workarea .application] 2]}]
	set fitsHeight [expr {[winfo height .application] <= [lindex [winfo workarea .application] 3]}]
	puts "EVIDENCE rsz-startup-offscreen geometry=$geometry workarea=[winfo workarea .application] inside=$inside fits=$fitsWidth,$fitsHeight"
	list $inside $fitsWidth $fitsHeight
} -cleanup {
	set ::application::Options(window:geometry) $savedOption
	set ::application::Options(window:state) $savedState
	wm minsize .application {*}$savedMin
	wm geometry .application $savedGeometry
	::rsz::wait 200
} -result {1 1 1}

# ---------------------------------------------------------------- VAL-RSZ-006

# ------------------------------------------------- VAL-RSZ-001 (5 sizes, no-op)

# Five different sizes must each settle within 500 ms, with the board, the
# inset and at least one pane moving, and no relayout afterwards.
tcltest::test rsz-resize-five-sizes {VAL-RSZ-001 five resizes settle within 500 ms and stay quiet} -setup {
	::rsz::showBoard
	::rsz::showInset
	::rsz::settle [list wm geometry .application [::rsz::wideGeometry 0.95 1.55]]
} -body {
	set sizes {}
	foreach scale {0.82 0.76 0.70 0.64 0.79} {
		lappend sizes [::rsz::wideGeometry $scale 1.55]
	}
	set out {}
	::rsz::tracesOn
	foreach size $sizes {
		set beforeRects [::rsz::rects]
		set beforePanes [::rsz::panes]
		lassign [::rsz::settle [list wm geometry .application $size]] ms
		set afterRects [::rsz::rects]
		set afterPanes [::rsz::panes]
		set boardChanged [expr {[dict get $afterRects board] ne [dict get $beforeRects board]}]
		set insetChanged [expr {[dict get $afterRects inset] ne [dict get $beforeRects inset]}]
		set paneChanged [expr {$afterPanes ne $beforePanes}]
		set settled [expr {$ms > 0 && $ms <= 500}]
		set inside [::rsz::inside .application]
		set overlap [::rsz::overlapOk? "rsz-five-$size"]
		set c1 [::rsz::counterSnapshot]
		::rsz::wait 550
		set c2 [::rsz::counterSnapshot]
		set quiet [expr {$c1 eq $c2}]
		puts "EVIDENCE rsz-five $size settleMs=$ms board=$boardChanged inset=$insetChanged pane=$paneChanged inside=$inside overlap=$overlap counters=$c1 after=$c2"
		set ok [expr {$settled && $boardChanged && $insetChanged && $paneChanged && $inside && $overlap && $quiet}]
		lappend out $ok
		if {!$ok} { error "resize $size did not settle cleanly: ms=$ms board=$boardChanged inset=$insetChanged pane=$paneChanged inside=$inside overlap=$overlap counters=$c1/$c2" }
	}
	::rsz::tracesOff
	expr {[llength [lsearch -all $out 0]] == 0}
} -cleanup {
	::rsz::tracesOff
	::rsz::hideInset
} -result 1

# Resizing to the size the window already has is not a recompute: no
# rectangle changes and no relayout counter moves afterwards.
tcltest::test rsz-resize-noop {VAL-RSZ-001 a no-op resize leaves the layout untouched} -setup {
	::rsz::showBoard
	::rsz::showInset
	set ::rsz::NoopGeometry [::rsz::wideGeometry 0.88]
	::rsz::settle [list wm geometry .application $::rsz::NoopGeometry]
} -body {
	set before [::rsz::snapshot]
	::rsz::tracesOn
	lassign [::rsz::settle [list wm geometry .application $::rsz::NoopGeometry]] ms after
	set c1 [::rsz::counterSnapshot]
	::rsz::wait 550
	set c2 [::rsz::counterSnapshot]
	::rsz::tracesOff
	set unchanged [expr {$after eq $before && $ms == 0}]
	set quiet [expr {$c1 eq $c2}]
	puts "EVIDENCE rsz-noop settleMs=$ms unchanged=$unchanged counters=$c1 after=$c2"
	list $unchanged $quiet
} -cleanup {
	::rsz::tracesOff
	::rsz::hideInset
} -result {1 1}

# ---------------------------------------------------------------- VAL-RSZ-004

# The reported work area changes (monitor move, taskbar/monitor change). The
# next size change re-clamps into it; a pure move inside it is not yanked.
tcltest::test rsz-workarea-change {VAL-RSZ-004 a changed work area re-clamps on the next size change} -setup {
	::rsz::showBoard
	catch { ::application::reflow::reset }
	::rsz::showInset
	::rsz::settle [list wm geometry .application [::rsz::wideGeometry 0.98 1.55]]
} -body {
	# 1280x800 work area (smaller monitor / larger taskbar).
	set small {}
	::rsz::withWorkArea {0 0 1500 950} {
		lassign [::rsz::settle {wm geometry .application 1600x1000+200+100}] ms
		::rsz::settle {::mediainset::Relayout}
		lappend small [wm geometry .application] [::rsz::insideArea .application {0 0 1500 950}] $ms [::rsz::overlap?]
		lappend small [::rsz::rects] $::application::board::ReserveSide $::application::board::ReservePixels
	}
	# A work area left of the primary one uses a negative origin.
	set negative {}
	::rsz::withWorkArea {-1920 0 1920 1080} {
		lassign [::rsz::settle {wm geometry .application 1500x950+-1800+100}] ms
		::rsz::settle {::mediainset::Relayout}
		lappend negative [wm geometry .application] [::rsz::insideArea .application {-1920 0 1920 1080}] $ms [::rsz::overlap?]
		lappend negative [::rsz::rects] $::application::board::ReserveSide $::application::board::ReservePixels
	}
	# Back on the real work area: same size, moved outside -> clamped; a
	# pure move that stays inside -> left exactly where the user put it.
	set base [::rsz::wideGeometry 0.7 1.55]
	::rsz::settle [list wm geometry .application $base]
	set size [regexp -inline {^[0-9]+x[0-9]+} $base]
	::rsz::settle {wm geometry .application +4000+150} 1200 200
	set outside [wm geometry .application]
	set outsideInside [::rsz::inside .application]
	::rsz::settle {wm geometry .application +120+90} 900 200
	set moved [wm geometry .application]
	set movedInside [::rsz::inside .application]
	set geometryRule [expr {
		[::util::place::clampGeometry "${size}+120+90" [winfo workarea .application] [winfo extents .application]]
			eq "${size}+120+90"
	}]
	puts "EVIDENCE rsz-workarea small=$small negative=$negative outside=$outside/$outsideInside moved=$moved/$movedInside rule=$geometryRule"
	list [lindex $small 1] [lindex $small 3] [lindex $negative 1] [lindex $negative 3] \
		$outsideInside $movedInside $geometryRule
} -cleanup {
	::rsz::settle [list wm geometry .application [::rsz::wideGeometry 0.82 1.55]]
	::rsz::hideInset
} -result {1 0 1 0 1 1 1}

# ---------------------------------------------------------------- VAL-RSZ-007

# Scaling changed behind the ::tk wrapper (an OS-level update): the display
# watch must see it and relay out once, without any window resize, and the
# next poll must be a no-op.
tcltest::test rsz-display-watch-scaling {VAL-RSZ-007 a scaling change bypassing the wrapper is detected by the poll and relays out once} -setup {
	::rsz::saveScaling
	::rsz::showBoard
	::rsz::settle [list ::rsz::setScaling 1.0]
	::rsz::settle [list wm geometry .application [::rsz::wideGeometry 1.0 1.3 10]]
	set ::rsz::Ticks {}
	::application::addScalingListener {::rsz::noteListener}
	::application::resetDisplayChangeCount
	set before [list [::rsz::boardRect] [::rsz::panes] $::application::board::Dim(borderthickness)]
} -body {
	::rsz::rawScaling 2.0
	# Tk 8.6 emits no event for this; wait for the one-second display poll.
	set deadline [expr {[clock milliseconds] + 2500}]
	while {[clock milliseconds] < $deadline && [::application::displayChangeCount] == 0} {
		after 50
		update
	}
	set changes [::application::displayChangeCount]
	update
	set ticks [llength $::rsz::Ticks]
	set after [list [::rsz::boardRect] [::rsz::panes] $::application::board::Dim(borderthickness)]
	# One further poll: unchanged display, so nothing runs.
	after 1200
	update
	set idleChanges [expr {[::application::displayChangeCount] - $changes}]
	set idleTicks [expr {[llength $::rsz::Ticks] - $ticks}]
	puts "EVIDENCE rsz-display-scaling changes=$changes ticks=$ticks idle=$idleChanges/$idleTicks border=[lindex $after 2] before=[lindex $before 2]"
	list $changes $ticks $idleChanges $idleTicks [expr {$after ne $before}] \
		[expr {[lindex $after 2] > [lindex $before 2]}]
} -cleanup {
	::application::removeScalingListener {::rsz::noteListener}
	::rsz::restoreScaling
} -result {1 1 0 0 1 1}

# A work area shrunk without a window resize: the poll runs the same
# relayout/re-clamp as the wrapper path and keeps the window inside it.
tcltest::test rsz-display-watch-workarea {VAL-RSZ-007 a work-area change without a resize is detected and re-clamps} -setup {
	::rsz::saveScaling
	::rsz::showBoard
	::rsz::settle [list wm geometry .application [::rsz::wideGeometry 0.98 1.55]]
	::application::resetDisplayChangeCount
	set before [::rsz::boardRect]
} -body {
	# A work area clearly smaller than the current window on every screen.
	set size [regexp -inline {^[0-9]+x[0-9]+} [wm geometry .application]]
	lassign [split [lindex $size 0] x] winW winH
	set area [list 0 0 [expr {min(1100, $winW-100)}] [expr {min(700, $winH-100)}]]
	set inside {}
	set changed {}
	set geometry {}
	::rsz::withWorkArea $area {
		# The display poll tick, executed while the reported work area is
		# the changed one. It must not need a window resize.
		::application::displayWatch
		::rsz::settle {::mediainset::Relayout} 1200 150
		set geometry [wm geometry .application]
		lappend inside [::rsz::insideArea .application $area]
		lappend changed [expr {[::rsz::boardRect] ne $before}]
		lappend changed [::application::displayChangeCount]
	}
	# Back on the real work area: one synchronising tick, no loop.
	::application::displayWatch
	set synced [::application::displayChangeCount]
	update
	puts "EVIDENCE rsz-display-workarea geometry=$geometry inside=$inside changed=$changed synced=$synced real=[wm geometry .application]"
	list $inside [lindex $changed 0] [lindex $changed 1] $synced
} -cleanup {
	::rsz::restoreScaling
	::rsz::settle [list wm geometry .application [::rsz::wideGeometry 0.82 1.55]]
} -result {1 1 1 2}

# The poll is cheap: many unchanged ticks perform no relayout.
tcltest::test rsz-display-watch-idle {VAL-RSZ-007 the display poll is a cheap no-op when nothing changes} -setup {
	::rsz::saveScaling
	::rsz::showBoard
	set ::rsz::Ticks {}
	::application::addScalingListener {::rsz::noteListener}
	::application::resetDisplayChangeCount
	set signature [::application::displaySignature]
} -body {
	set t0 [clock microseconds]
	for {set i 0} {$i < 200} {incr i} {
		::application::displayWatch
	}
	set us [expr {[clock microseconds] - $t0}]
	update
	set changes [::application::displayChangeCount]
	set ticks [llength $::rsz::Ticks]
	puts "EVIDENCE rsz-display-idle polls=200 us=$us changes=$changes ticks=$ticks sameSignature=[expr {[::application::displaySignature] eq $signature}]"
	list $changes $ticks [expr {$us < 500000}] [expr {[::application::displaySignature] eq $signature}]
} -cleanup {
	::application::removeScalingListener {::rsz::noteListener}
	::rsz::restoreScaling
} -result {0 0 1 1}

# ---------------------------------------------------------------- VAL-RSZ-005

# At the window minimum every visible pane keeps its -minsize, the board keeps
# its square minimum (or BRD-004 fallback) and resizing back restores the
# layout.
tcltest::test rsz-window-minimum {VAL-RSZ-005 the window minimum keeps pane and board minimums and restores} -setup {
	::rsz::showBoard
	::rsz::showInset
	set ::rsz::MinGeometry [::rsz::wideGeometry 0.9 1.55]
	::rsz::settle [list wm geometry .application $::rsz::MinGeometry]
	set savedMin [wm minsize .application]
	set before [list [::rsz::rects] [::rsz::panes]]
} -body {
	lassign [wm minsize .application] mw mh
	# Ask for less than the minimum; Tk/the WM must keep the minimum.
	set belowW [expr {max(1, $mw - 80)}]
	set belowH [expr {max(1, $mh - 80)}]
	lassign [::rsz::settle [list wm geometry .application ${belowW}x${belowH}+0+0]] ms
	set geometry [wm geometry .application]
	lassign [wm minsize .application] cw ch
	regexp {^([0-9]+)x([0-9]+)} $geometry -> aw ah
	set honoured [expr {$aw >= $cw && $ah >= $ch}]
	set panes [::rsz::paneMins]
	set square $::application::board::Dim(squaresize:Normal)
	set minimum $::application::board::MinimumReserveSquare
	set boardOk [expr {$square >= $minimum || $::application::board::ReserveSide eq ""}]
	set overlap [::rsz::overlap?]
	set overlay [::rsz::overlapOk? rsz-minimum]
	# 640x400 when the layout allows it (a floor below the layout minimum is
	# not a legal window size, so it is deliberately not attempted).
	set floorTried 0
	set floorOk 1
	if {$cw <= 640 && $ch <= 400} {
		set floorTried 1
		::rsz::settle {wm geometry .application 640x400+0+0}
		lassign [wm minsize .application] fw fh
		set floorOk [expr {[winfo width .application] >= $fw && [winfo height .application] >= $fh}]
	}
	lassign [::rsz::settle [list wm geometry .application $::rsz::MinGeometry]] ms2
	set after [list [::rsz::rects] [::rsz::panes]]
	set restored [::rsz::near $before $after 2]
	puts "EVIDENCE rsz-minimum minsize=$cw,$ch requested=${belowW}x${belowH} actual=$geometry honour=$honoured panes=$panes square=$square/$minimum board=$boardOk overlap=$overlap overlay=$overlay floor=$floorTried/$floorOk restored=$restored"
	list $honoured [expr {[llength $panes] == 0}] $boardOk $overlay $floorOk $restored
} -cleanup {
	wm minsize .application {*}$savedMin
	::rsz::settle [list wm geometry .application $::rsz::MinGeometry]
	::rsz::hideInset
} -result {1 1 1 1 1 1}

# ------------------------------------------------- VAL-RSZ-001 / MED-009 link

# Resizing and going fullscreen while the video is expanded (the board is the
# small framed window) keeps the inset frame, and returning restores the
# prior board/inset/pane rectangles.
tcltest::test rsz-expanded-resize {VAL-RSZ-001/MED-009 resize and fullscreen while expanded keep the frame and restore} -setup {
	::rsz::showBoard
	::rsz::showInset
	set ::rsz::ExpandedGeometry [::rsz::wideGeometry 0.9 1.6]
	::rsz::settle [list wm geometry .application $::rsz::ExpandedGeometry]
} -body {
	set w [::mediainset::Pane].mediainset
	set view [::mediainset::BoardView]
	set original [$view cget -highlightthickness]
	set before [list [::rsz::rects] [::rsz::panes]]
	::mediainset::swap
	::rsz::settle {::mediainset::Relayout}
	lassign [::rsz::settle [list wm geometry .application [::rsz::wideGeometry 0.8 1.6]]] ms
	set resized [::rsz::frameState]
	# Fullscreen while expanded: the event path must relayout the inset.
	if {[catch {::menu::viewFullscreen toggle}]} { error "fullscreen is unavailable" }
	::rsz::settle {::mediainset::Relayout}
	set fullscreen [::rsz::frameState]
	set isFullscreen [::menu::fullscreen?]
	::menu::viewFullscreen toggle
	::rsz::settle {::mediainset::Relayout}
	# Return to the original size while still expanded, then restore.
	::rsz::settle [list wm geometry .application $::rsz::ExpandedGeometry]
	set back [::rsz::frameState]
	::mediainset::swap
	::rsz::settle {::mediainset::Relayout}
	set after [list [::rsz::rects] [::rsz::panes]]
	set restored [::rsz::near $before $after 2]
	set highlight [expr {[$view cget -highlightthickness] == $original}]
	set manager [winfo manager $view]
	puts "EVIDENCE rsz-expanded resized=$resized resizeMs=$ms fullscreen=$fullscreen isFullscreen=$isFullscreen back=$back restored=$restored highlight=$highlight manager=$manager after=$after"
	list \
		[lindex $resized 0] [lindex $resized 1] [lindex $resized 2] [lindex $resized 3] [lindex $resized 4] \
		[lindex $fullscreen 0] [lindex $fullscreen 1] $isFullscreen \
		$restored $highlight [expr {$manager eq "pack"}]
} -cleanup {
	if {[::menu::fullscreen?]} { catch { ::menu::viewFullscreen toggle } }
	if {$::mediainset::Swapped} { catch { ::mediainset::swap } }
	::rsz::hideInset
	::rsz::settle [list wm geometry .application $::rsz::ExpandedGeometry]
} -result {1 1 3 place 1 1 1 1 1 1 1}

# Windows keeps the pre-maximise normal rect, so an options file written while
# zoomed can carry 200x200 as the normal geometry. Restoring it must give a
# window at least the computed layout minimum with coherent panes and a sane
# board square; a zoomed -> normal restore below the minimum must re-apply the
# remembered normal geometry, and the saved value must never stay below it.
tcltest::test rsz-zoomed-normal {VAL-RSZ-006 a 200x200 normal geometry saved while zoomed restores at least the layout minimum} -setup {
	::rsz::showBoard
	set ::rsz::SavedGeometry [wm geometry .application]
	set ::rsz::SavedOption $::application::Options(window:geometry)
	set ::rsz::SavedState $::application::Options(window:state)
	set ::rsz::SavedStateLast $::application::Vars(window:state:last)
	set ::rsz::SavedNormal $::application::Vars(last:normal:geometry)
	set ::rsz::SavedMin [wm minsize .application]
} -body {
	set ::application::Options(window:geometry) 200x200+849+382
	set ::application::Options(window:state) zoomed
	::application::RestoreWindowGeometry .application
	::rsz::wait 350
	lassign [::application::LayoutMinimum] minw minh
	regexp {^([0-9]+)x([0-9]+)} [wm geometry .application] -> rw rh
	set restored [expr {$rw >= $minw && $rh >= $minh}]
	regexp {^([0-9]+)x([0-9]+)} $::application::Options(window:geometry) -> ow oh
	set savedSane [expr {$ow >= $minw && $oh >= $minh}]
	set panes [::rsz::paneMins]
	set square $::application::board::Dim(squaresize:Normal)
	set minimum $::application::board::MinimumReserveSquare
	set boardOk [expr {$square >= $minimum || $::application::board::ReserveSide eq ""}]
	set coherent [::rsz::coherent?]
	# A known normal geometry is remembered while the window is not zoomed.
	wm minsize .application {*}$::rsz::SavedMin
	wm geometry .application 1200x800+150+120
	::rsz::wait 500
	regexp {^([0-9]+)x([0-9]+)} [wm geometry .application] -> mw mh
	# Real maximize/restore round trip where the WM supports it.
	set zoomSupported [expr {![catch {wm attributes .application -zoomed 1}]}]
	::rsz::wait 500
	set zoomed [expr {$zoomSupported && [wm attributes .application -zoomed]}]
	if {$zoomed} {
		wm attributes .application -zoomed 0
		::rsz::wait 500
	}
	regexp {^([0-9]+)x([0-9]+)} [wm geometry .application] -> zw zh
	set zoomRoundTrip [expr {!$zoomed || ($zw >= $minw && $zh >= $minh)}]
	# Simulate the Windows Restore: the WM hands back the stale pre-maximise
	# rect (200x200) as the normal size. The remembered normal geometry must
	# come back, not the degenerate rect or a derived default.
	set lastBefore $::application::Vars(last:normal:geometry)
	set ::application::Vars(window:state:last) zoomed
	wm minsize .application 1 1
	wm geometry .application 200x200+120+120
	::rsz::wait 600
	regexp {^([0-9]+)x([0-9]+)} [wm geometry .application] -> nw nh
	set reApplied [expr {$nw == $mw && $nh == $mh && $nw >= $minw && $nh >= $minh}]
	set panesAfter [::rsz::paneMins]
	set coherentAfter [::rsz::coherent?]
	puts "EVIDENCE rsz-zoomed-normal min=${minw}x${minh} restored=${rw}x${rh} savedSane=$savedSane panes=$panes square=$square/$minimum board=$boardOk coherent=$coherent remembered=${mw}x${mh} lastBefore=$lastBefore lastAfter=$::application::Vars(last:normal:geometry) zoomed=$zoomed zoomRoundTrip=$zoomRoundTrip normal=${nw}x${nh} reApplied=$reApplied panesAfter=$panesAfter coherentAfter=$coherentAfter"
	list $restored $savedSane [expr {[llength $panes] == 0}] $boardOk $coherent \
		$zoomRoundTrip $reApplied [expr {[llength $panesAfter] == 0}] $coherentAfter
} -cleanup {
	catch {wm attributes .application -zoomed 0}
	wm minsize .application {*}$::rsz::SavedMin
	set ::application::Options(window:geometry) $::rsz::SavedOption
	set ::application::Options(window:state) $::rsz::SavedState
	set ::application::Vars(window:state:last) $::rsz::SavedStateLast
	set ::application::Vars(last:normal:geometry) $::rsz::SavedNormal
	wm geometry .application $::rsz::SavedGeometry
	::rsz::wait 250
} -result {1 1 1 1 1 1 1 1 1}

proc ::rsz::displayWait {ms} {
 after $ms {set ::rsz::displayDone 1}
 vwait ::rsz::displayDone
 unset ::rsz::displayDone
 update
}
tcltest::test rsz-display-watch-fullscreen {display changes in fullscreen replay once after exit, including wrapper changes} -setup {
 ::rsz::saveScaling
 ::rsz::showBoard
 ::rsz::settle [list ::rsz::setScaling 1.0]
 set ::rsz::Ticks {}
 ::application::addScalingListener {::rsz::noteListener}
} -body {
 set results {}
 foreach setter {::rsz::rawScaling ::rsz::setScaling} {
  ::menu::viewFullscreen toggle
  ::rsz::displayWait 1800
  set ::rsz::Ticks {}
  ::application::resetDisplayChangeCount
  $setter 1.3
  ::application::displayWatch
  ::rsz::displayWait 1200
  set during [llength $::rsz::Ticks]
  ::menu::viewFullscreen toggle
  ::rsz::displayWait 2200
  set replay [llength $::rsz::Ticks]
  ::application::displayWatch
  update
  lappend results [list $during $replay [llength $::rsz::Ticks]]
  ::rsz::settle [list ::rsz::setScaling 1.0]
 }
 set results
} -cleanup {
 if {[::menu::fullscreen?]} {::menu::viewFullscreen toggle}
 ::application::removeScalingListener {::rsz::noteListener}
 ::rsz::restoreScaling
} -result {{0 1 1} {0 1 1}}

tcltest::cleanupTests
