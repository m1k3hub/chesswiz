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
	update idletasks
	set tiny [expr {[winfo ismapped .srTest.video] && [winfo width .srTest.video] <= 1}]
	set r [::mediainset::SurfaceReady .srTest]
	set diag [list [winfo geometry .srTest] [winfo width .srTest.video]x[winfo height .srTest.video] [winfo ismapped .srTest.video]]
	destroy .srTest
	list $tiny $r $diag
} -result {1 0 {1x1+0+0 1x1 1}}

# FreeRect on a stand-alone canvas: a 400x400 "board" item in a wide or tall pane.
proc ::scidb::test::freeRect {cw ch bx by} {
	set c [canvas .freeRectTest -width $cw -height $ch -highlightthickness 0 -borderwidth 0]
	place $c -x 0 -y 0 -width $cw -height $ch
	$c create rectangle $bx $by [expr {$bx + 400}] [expr {$by + 400}] -tags board -outline {}
	update idletasks
	set r [::mediainset::FreeRect $c]
	destroy $c
	return $r
}

tcltest::test inset-free-right {a wide pane with the board on the left: the video goes right of it} -body {
	lassign [::scidb::test::freeRect 1000 420 10 10] x y w h
	list [expr {$x >= 416}] [expr {$x + $w <= 1000}] [expr {abs($w*9 - $h*16) <= 16}] [expr {$w >= 200}]
} -result {1 1 1 1}

tcltest::test inset-free-below {a tall pane: the video goes below the board} -body {
	lassign [::scidb::test::freeRect 420 900 10 10] x y w h
	list [expr {$y >= 416}] [expr {$y + $h <= 900}] [expr {$w >= 200}]
} -result {1 1 1}

tcltest::test inset-free-none {a pane the board fills: no free rectangle} -body {
	::scidb::test::freeRect 420 420 10 10
} -result {}

tcltest::cleanupTests
