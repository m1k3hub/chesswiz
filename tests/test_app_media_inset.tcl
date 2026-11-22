# ======================================================================
# Scidb App Test - video inside the board window (tcl/media-inset.tcl)
# ======================================================================
# The user's suggestion (2026-10-17): the media panel inside the board
# window; its expand button swaps size and place with the board.
# ======================================================================
package require tcltest 2.5

proc ::scidb::test::insetState {} {
	set pane [winfo parent $::application::board::Vars(widget:frame)]
	set w $pane.mediainset
	set canv $pane.c
	set inset [expr {[winfo exists $w] ? [winfo manager $w] : "none"}]
	set insetInfo {}
	if {$inset eq "place"} { set insetInfo [dict get [place info $w] -relwidth] }
	set board [winfo manager $canv]
	set boardInfo {}
	if {$board eq "place"} { set boardInfo [dict get [place info $canv] -relwidth] }
	list $inset $insetInfo $board $boardInfo
}

tcltest::test inset-surface {without a free margin the video goes to the board's corner} -setup {
	set ::mediainset::Options(enabled) 1
	set ::mediainset::Options(minWidth) 100000
	# the inset maps only while the board tab is raised, as when the Media
	# pane inside it is used
	.application.nb select .application.nb.board
	update idletasks
} -body {
	set fallback .noSuchViewer
	set c [::mediainset::surface $fallback]
	list [string match *.mediainset.video $c] [::scidb::test::insetState]
} -cleanup { ::mediainset::hide; set ::mediainset::Options(minWidth) 200 } -result {1 {place {} pack {}}}

tcltest::test inset-swap {expand swaps size and place with the board, and back} -setup {
	set ::mediainset::Options(enabled) 1
	set ::mediainset::Options(minWidth) 100000
	.application.nb select .application.nb.board
	update idletasks
	::mediainset::surface .noSuchViewer
} -body {
	::mediainset::swap
	set a [list [::mediainset::swapped?] [::scidb::test::insetState]]
	::mediainset::swap
	lappend a [::mediainset::swapped?] [::scidb::test::insetState]
} -cleanup { ::mediainset::hide; set ::mediainset::Options(minWidth) 200 } -result {1 {place 1 place 0.34} 0 {place {} pack {}}}

tcltest::test inset-hide-restores {stopping while swapped gives the board its pane back} -setup {
	set ::mediainset::Options(enabled) 1
	.application.nb select .application.nb.board
	update idletasks
	::mediainset::surface .noSuchViewer
	::mediainset::swap
} -body {
	::mediainset::hide
	list [::mediainset::swapped?] [::scidb::test::insetState]
} -result {0 {{} {} pack {}}}

tcltest::test inset-off {with the option off the Media pane's viewer is used} -setup {
	set ::mediainset::Options(enabled) 0
} -body {
	::mediainset::surface .theViewer
} -cleanup { set ::mediainset::Options(enabled) 1 } -result .theViewer

tcltest::test inset-unmapped-fallback {an inset that never maps yields the Media pane's viewer} -setup {
	set ::mediainset::Options(enabled) 1
	rename ::mediainset::SurfaceReady ::mediainset::savedSurfaceReady
	proc ::mediainset::SurfaceReady {w} { return 0 }
} -body {
	set c [::mediainset::surface .theMediaViewer]
	set pane [winfo parent $::application::board::Vars(widget:frame)]
	list $c [expr {[winfo exists $pane.mediainset] ? [winfo manager $pane.mediainset] : "none"}]
} -cleanup {
	rename ::mediainset::SurfaceReady {}
	rename ::mediainset::savedSurfaceReady ::mediainset::SurfaceReady
	::mediainset::hide
} -result {.theMediaViewer {}}

tcltest::test inset-surfaceready {1 after the video canvas maps} -setup {
	set ::mediainset::Options(enabled) 1
	set ::mediainset::Options(minWidth) 100000
	.application.nb select .application.nb.board
	update idletasks
} -body {
	set w [string range [::mediainset::surface .noSuchViewer] 0 end-6]
	::mediainset::SurfaceReady $w
} -cleanup { ::mediainset::hide; set ::mediainset::Options(minWidth) 200 } -result 1

tcltest::test inset-surfaceready-withdrawn {0 when the canvas's toplevel stays withdrawn} -body {
	toplevel .srTest
	wm withdraw .srTest
	canvas .srTest.video -background black
	place .srTest.video -x 0 -y 0 -relwidth 1 -relheight 1
	set r [::mediainset::SurfaceReady .srTest]
	destroy .srTest
	return $r
} -result 0

tcltest::test inset-surfaceready-tiny {0 while the canvas is mapped but still 1x1} -body {
	toplevel .srTest
	wm geometry .srTest 1x1+0+0
	canvas .srTest.video -background black -highlightthickness 0 -borderwidth 0
	place .srTest.video -x 0 -y 0 -relwidth 1 -relheight 1
	# Windows maps the canvas only after the event loop runs, so wait for it
	# before reading its state (update idletasks is not enough there).
	for {set i 0} {$i < 40 && ![winfo ismapped .srTest.video]} {incr i} {
		update
		after 25
	}
	# SurfaceReady refuses a surface unless both width and height exceed 1.
	# Windows can enforce a minimum toplevel width (148 px seen on the laptop),
	# so the precondition checks only the height that the refusal depends on.
	set tiny [expr {[winfo ismapped .srTest.video] && [winfo height .srTest.video] <= 1}]
	set r [::mediainset::SurfaceReady .srTest]
	# The window manager may decorate or move the toplevel (+1+22 under
	# openbox); SurfaceReady must judge the canvas size, not its origin, so
	# report only the height and mapped state.
	set diag [list [winfo height .srTest.video] [winfo ismapped .srTest.video]]
	destroy .srTest
	list $tiny $r $diag
} -result {1 0 {1 1}}

tcltest::cleanupTests
