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
} -body {
	set fallback .noSuchViewer
	set c [::mediainset::surface $fallback]
	list [string match *.mediainset.video $c] [::scidb::test::insetState]
} -cleanup { ::mediainset::hide; set ::mediainset::Options(minWidth) 200 } -result {1 {place {} pack {}}}

tcltest::test inset-swap {expand swaps size and place with the board, and back} -setup {
	set ::mediainset::Options(enabled) 1
	set ::mediainset::Options(minWidth) 100000
	::mediainset::surface .noSuchViewer
} -body {
	::mediainset::swap
	set a [list [::mediainset::swapped?] [::scidb::test::insetState]]
	::mediainset::swap
	lappend a [::mediainset::swapped?] [::scidb::test::insetState]
} -cleanup { ::mediainset::hide; set ::mediainset::Options(minWidth) 200 } -result {1 {place 1 place 0.34} 0 {place {} pack {}}}

tcltest::test inset-hide-restores {stopping while swapped gives the board its pane back} -setup {
	set ::mediainset::Options(enabled) 1
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
