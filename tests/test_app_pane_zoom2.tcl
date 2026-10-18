# Phase 2 pane zoom (focus follows size), docs/features/FEATURE_PANE_ZOOM.md.
package require tcltest 2.5

namespace eval ::zoom2Test {
	variable Title "Pane"
}

proc ::zoom2Test::makePane {twm parent type uid} {
	set w [tk::frame $parent.$uid]
	return [list $w ::zoom2Test::Title 100 0 1 1 1 [expr {$uid ne "eco"}]]
}
proc ::zoom2Test::buildPane {twm w uid width height} {
	pack [ttk::label $w.content -text $uid] -fill both -expand 1
}
proc ::zoom2Test::sashes {twm} {
	update idletasks
	set result {}
	set queue [winfo children $twm]
	while {[llength $queue]} {
		set queue [lassign $queue w]
		lappend queue {*}[winfo children $w]
		if {![string match *Panedwindow [winfo class $w]]} { continue }
		set coords {}
		for {set i 0} {$i < [llength [$w panes]]-1} {incr i} {
			lappend coords [$w sash coord $i]
		}
		lappend result $w $coords
	}
	return $result
}
# board (min 300), editor and games in one horizontal panedwindow;
# eco in a second panedwindow below, to watch "other panedwindows".
proc ::zoom2Test::fixture {} {
	toplevel .z2test
	wm geometry .z2test 1000x700
	set twm [::twm::twm .z2test.layout \
		-makepane ::zoom2Test::makePane -buildpane ::zoom2Test::buildPane]
	pack $twm -fill both -expand 1
	set layout {root {-width 1000 -height 700} {
		panedwindow {-orient vert} {
			panedwindow {-orient horz} {
				frame board {-width 400 -height 400 -minwidth 300 -minheight 300}
				frame editor {-width 320 -height 400 -minwidth 100 -minheight 100}
				frame games {-width 260 -height 400 -minwidth 100 -minheight 100}
			}
			frame eco {-width 980 -height 200 -minwidth 100 -minheight 100}
		}
	}}
	$twm init $layout
	$twm load $layout
	update
	::application::focuszoom::setRatio 1.4
	set ::application::focuszoom::pinBoard 0
	set ::application::focuszoom::duration 0
	return $twm
}
proc ::zoom2Test::cleanup {twm} {
	catch {::application::focuszoom::disable $twm}
	catch {destroy .z2test}
	set ::application::focuszoom::pinBoard 0
	set ::application::focuszoom::duration 0
	::application::focuszoom::setRatio 1.4
	update
}
proc ::zoom2Test::widths {t} {
	set result {}
	foreach uid {board editor games} { lappend result [winfo width [$t leaf $uid]] }
	return $result
}

tcltest::test pane-zoom2-grow-ratio {click grows the pane by R, siblings shrink proportionally, other panedwindows unchanged} -setup {
	set t [::zoom2Test::fixture]
	::application::focuszoom::enable $t
	set before [::zoom2Test::widths $t]
	set ecoBefore [winfo height [$t leaf eco]]
	::application::focuszoom::growPane $t [$t leaf editor]
	update
} -body {
	lassign $before b0 e0 g0
	lassign [::zoom2Test::widths $t] b1 e1 g1
	set R [expr {double($e1) / $e0}]
	# siblings shrink by a common factor (rounding: 1 px each)
	set fb [expr {double($b1) / $b0}]
	set fg [expr {double($g1) / $g0}]
	list [expr {abs($R - 1.4) < 0.02}] [expr {$b1 < $b0 && $g1 < $g0}] \
		[expr {abs($fb - $fg) < 0.02}] \
		[expr {$b1 + $e1 + $g1 == $b0 + $e0 + $g0}] \
		[expr {[winfo height [$t leaf eco]] == $ecoBefore}]
} -cleanup { ::zoom2Test::cleanup $t } -result {1 1 1 1 1}

tcltest::test pane-zoom2-repeat-same-pane {clicking the already grown pane does not grow it again} -setup {
	set t [::zoom2Test::fixture]
	::application::focuszoom::enable $t
	::application::focuszoom::growPane $t [$t leaf editor]
	update
	set once [::zoom2Test::widths $t]
	::application::focuszoom::growPane $t [$t leaf editor]
	update
} -body {
	expr {$once eq [::zoom2Test::widths $t]}
} -cleanup { ::zoom2Test::cleanup $t } -result 1

tcltest::test pane-zoom2-nonzoomable {a non-zoomable pane never grows} -setup {
	set t [::zoom2Test::fixture]
	::application::focuszoom::enable $t
	set before [::zoom2Test::sashes $t]
	::application::focuszoom::growPane $t [$t leaf eco]
	update
} -body {
	expr {$before eq [::zoom2Test::sashes $t]}
} -cleanup { ::zoom2Test::cleanup $t } -result 1

tcltest::test pane-zoom2-board-minimum {the board never goes below its minimum square size} -setup {
	set t [::zoom2Test::fixture]
	::application::focuszoom::enable $t
	::application::focuszoom::setRatio 1.8
	::application::focuszoom::growPane $t [$t leaf editor]
	update
	::application::focuszoom::growPane $t [$t leaf games]
	update
	::application::focuszoom::growPane $t [$t leaf editor]
	update
} -body {
	set board [$t leaf board]
	list [expr {[winfo width $board] >= 300}] [expr {[winfo height $board] >= 300}]
} -cleanup { ::zoom2Test::cleanup $t } -result {1 1}

tcltest::test pane-zoom2-board-pin {a pinned board never shrinks} -setup {
	set t [::zoom2Test::fixture]
	set ::application::focuszoom::pinBoard 1
	::application::focuszoom::enable $t
	set b0 [winfo width [$t leaf board]]
	set g0 [winfo width [$t leaf games]]
	::application::focuszoom::growPane $t [$t leaf editor]
	update
} -body {
	list [expr {[winfo width [$t leaf board]] == $b0}] \
		[expr {[winfo width [$t leaf games]] < $g0}]
} -cleanup { ::zoom2Test::cleanup $t } -result {1 1}

tcltest::test pane-zoom2-restore-exact {switching the mode off restores the user's layout exactly} -setup {
	set t [::zoom2Test::fixture]
	set before [::zoom2Test::sashes $t]
	::application::focuszoom::enable $t
	::application::focuszoom::growPane $t [$t leaf editor]
	update
	::application::focuszoom::growPane $t [$t leaf board]
	update
	::application::focuszoom::growPane $t [$t leaf editor]
	update
} -body {
	::application::focuszoom::disable $t
	update
	expr {$before eq [::zoom2Test::sashes $t]}
} -cleanup { ::zoom2Test::cleanup $t } -result 1

tcltest::test pane-zoom2-ratio-clamp {the ratio is configurable inside 1.2-1.8} -body {
	list [::application::focuszoom::setRatio 2.0] \
		[::application::focuszoom::setRatio 1.05] \
		[::application::focuszoom::setRatio 1.6]
} -cleanup { ::application::focuszoom::setRatio 1.4 } -result {1.8 1.2 1.6}

tcltest::test pane-zoom2-animation {the growth animates over ~150 ms and lands on the same target} -setup {
	set a [::zoom2Test::fixture]
	::application::focuszoom::enable $a
	::application::focuszoom::growPane $a [$a leaf editor]
	update
	set instant [::zoom2Test::sashes $a]
	::zoom2Test::cleanup $a

	set b [::zoom2Test::fixture]
	::application::focuszoom::enable $b
	set ::application::focuszoom::duration 150
	set ticks [clock milliseconds]
	::application::focuszoom::growPane $b [$b leaf editor]
} -body {
	set done 0
	after 500 {set done 1}
	vwait done
	set elapsed [expr {[clock milliseconds] - $ticks}]
	list [expr {[::zoom2Test::sashes $b] eq $instant}] \
		[expr {$elapsed >= 100}] \
		[expr {$::application::focuszoom::duration == 150}]
} -cleanup { ::zoom2Test::cleanup $b } -result {1 1 1}

### real application panes ##################################################

tcltest::test pane-zoom2-off-default {off by default: a click resizes nothing} -setup {
	.application.nb select .application.nb.board
	set t [::application::twm board]
	set p [::application::openPane editor]
	update
} -body {
	set before [::zoom2Test::sashes $t]
	::application::focuszoom::clicked $p
	update
	expr {$before eq [::zoom2Test::sashes $t]}
} -result 1

tcltest::test pane-zoom2-app-click {a click into a zoomable pane grows it by R} -setup {
	.application.nb select .application.nb.board
	set t [::application::twm board]
	::application::openPane editor
	set p [::application::openPane board]
	update
	set ::application::focuszoom::duration 0
	::application::focuszoom::enable $t
	set e0 [winfo width $p]
	set b0 [winfo width [$t leaf editor]]
} -body {
	::application::focuszoom::clicked $p
	update
	set e1 [winfo width $p]
	set b1 [winfo width [$t leaf editor]]
	set R [expr {double($e1) / $e0}]
	::application::focuszoom::disable $t
	update
	list [expr {$R > 1.2 && $R <= 1.8}] [expr {$b1 <= $b0}] \
		[expr {[winfo width $p] == $e0}]
} -cleanup {
	catch {::application::focuszoom::disable [::application::twm board]}
} -result {1 1 1}

tcltest::test pane-zoom2-program-focus {focus moved by the program never resizes} -setup {
	.application.nb select .application.nb.board
	set t [::application::twm board]
	set p [::application::openPane board]
	update
	set ::application::focuszoom::duration 0
	::application::focuszoom::enable $t
	set before [::zoom2Test::sashes $t]
} -body {
	# no arming key press: focusIn is a no-op
	focus $p
	::application::focuszoom::focusIn $p
	update
	set unchanged [expr {$before eq [::zoom2Test::sashes $t]}]
	# keyboard pane switch: the Tab arms the FocusIn that follows
	::application::focuszoom::keySwitch
	::application::focuszoom::focusIn $p
	update
	set grown [expr {[winfo width $p] > 0 && $before ne [::zoom2Test::sashes $t]}]
	::application::focuszoom::disable $t
	update
	list $unchanged $grown [expr {$before eq [::zoom2Test::sashes $t]}]
} -cleanup {
	catch {::application::focuszoom::disable [::application::twm board]}
} -result {1 1 1}

tcltest::test pane-zoom2-menu {the Window menu exposes the opt-in, the ratio and the board pin} -setup {
	.application.nb select .application.nb.board
} -body {
	menu .z2menu
	::menu::build .z2menu
	set m .z2menu.window
	set found {}
	for {set i 0} {$i <= [$m index end]} {incr i} {
		set type [$m type $i]
		if {$type eq "tearoff"} { continue }
		if {$type eq "cascade"} {
			lappend found [$m entrycget $i -menu]
			continue
		}
		lappend found [expr {[catch {$m entrycget $i -variable} v] ? $type : $v}]
	}
	set zoomIdx [lsearch -exact $found ::application::focuszoom::enabled([::application::twm board])]
	set ratioIdx [lsearch -glob $found *.mFocusZoomRatio]
	set pinIdx [lsearch -exact $found ::application::focuszoom::pinBoard]
	set ratios {}
	if {$ratioIdx >= 0} {
		set rm [lindex $found $ratioIdx]
		for {set i 0} {$i <= [$rm index end]} {incr i} { lappend ratios [$rm entrycget $i -value] }
	}
	destroy .z2menu
	list [expr {$zoomIdx >= 0}] [lsort -real $ratios] [expr {$pinIdx >= 0}]
} -result {1 {1.2 1.4 1.6 1.8} 1}

tcltest::cleanupTests
