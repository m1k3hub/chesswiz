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

tcltest::test inset-surface {the video goes to a small window inside the board pane} -setup {
	set ::mediainset::Options(enabled) 1
} -body {
	set fallback .noSuchViewer
	set c [::mediainset::surface $fallback]
	list [string match *.mediainset.video $c] [::scidb::test::insetState]
} -cleanup { ::mediainset::hide } -result {1 {place 0.34 pack {}}}

tcltest::test inset-swap {expand swaps size and place with the board, and back} -setup {
	set ::mediainset::Options(enabled) 1
	::mediainset::surface .noSuchViewer
} -body {
	::mediainset::swap
	set a [list [::mediainset::swapped?] [::scidb::test::insetState]]
	::mediainset::swap
	lappend a [::mediainset::swapped?] [::scidb::test::insetState]
} -cleanup { ::mediainset::hide } -result {1 {place 1 place 0.34} 0 {place 0.34 pack {}}}

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

tcltest::cleanupTests
