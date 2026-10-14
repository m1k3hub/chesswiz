# ======================================================================
# Scidb App Test -- bugs found in the live error log (2026-09-30 17:10)
#   1. tree pane context menu: can't read "Options(repertoire:db)"
#   2. browse a game from the games table: can't read "Options(style:column)"
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

tcltest::test errfix-tree-novelty-options {the options the tree menu reads exist, with a safe default} -body {
	list [info exists ::application::tree::Options(repertoire:db)] \
		[info exists ::application::tree::Options(novelty:highlight)] \
		$::application::tree::Options(repertoire:db) \
		$::application::tree::Options(novelty:highlight)
} -result {1 1 {} 0}

tcltest::test errfix-tree-novelty-toggle {ticking "highlight novelties" with no repertoire database is a harmless no-op} -setup {
	ttk::treeview .errfixtree
	.errfixtree insert {} end -id r1 -text "e4"
	set efxSaved [list $::application::tree::Options(novelty:highlight) $::application::tree::Options(repertoire:db)]
} -body {
	set ::application::tree::Options(novelty:highlight) 1
	set ::application::tree::Options(repertoire:db) {}
	set rc [catch { ::application::tree::ToggleNoveltyHighlighting .errfixtree } msg]
	list $rc [.errfixtree tag has novelty r1]
} -cleanup {
	lassign $efxSaved ::application::tree::Options(novelty:highlight) ::application::tree::Options(repertoire:db)
	destroy .errfixtree
} -result {0 0}

tcltest::test errfix-browser-options-seeded-on-first-read {the first browse-open finds its display options, seeded from the defaults} -setup {
	set efxExisted [info exists ::pgn::browser::Options]
	set efxSaved [expr {$efxExisted ? [array get ::pgn::browser::Options] : {}}]
	catch { unset ::pgn::browser::Options }
} -body {
	set before [info exists ::pgn::browser::Options]
	# what browser::open does first; before the fix this read a variable that did not exist yet
	::pgn::setup::setupNags browser
	list $before $::pgn::browser::Options(style:column) $::pgn::browser::Options(style:move) \
		$::pgn::browser::Options(show:nagtext)
} -cleanup {
	catch { unset ::pgn::browser::Options }
	if {$efxExisted} { array set ::pgn::browser::Options $efxSaved }
} -result {0 0 san 1}

tcltest::test errfix-browser-options-not-overridden {seeding never replaces options that are already there} -setup {
	set efxExisted [info exists ::pgn::browser::Options]
	set efxSaved [expr {$efxExisted ? [array get ::pgn::browser::Options] : {}}]
	catch { unset ::pgn::browser::Options }
	set ::pgn::browser::Options(style:column) 1
} -body {
	::pgn::setup::EnsureOptions browser
	set ::pgn::browser::Options(style:column)
} -cleanup {
	catch { unset ::pgn::browser::Options }
	if {$efxExisted} { array set ::pgn::browser::Options $efxSaved }
} -result 1

tcltest::test errfix-browser-options-not-created-early {nothing is created before it is needed (the setup dialog reads the array's existence)} -body {
	# the load-time state of a context that was never opened: the file defines no Options for it
	set efxF [open [file join [file dirname [file dirname [file normalize [info script]]]] tcl browser.tcl]]
	set efxText [read $efxF]; close $efxF
	set i [string first "namespace eval pgn \{" $efxText]
	expr {[string first "array set Options" [string range $efxText $i end]] < 0}
} -result 1

::tcltest::cleanupTests
return
