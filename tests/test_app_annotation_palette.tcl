# ======================================================================
# Scidb App Test - the annotation palette (Run 14 tester bug)
# ======================================================================
# Run 14: clicking !? in the "Annotation" palette left 1.d4 unmarked.
# Run 20: Ctrl-Shift-C with the notation focused did not open the comment
# editor; the shortcuts were bound on the board only.
# ======================================================================

package require tcltest 2.5
namespace eval ::scidb::test::annpal {}

proc ::scidb::test::annpal::button {nag} {
	set dlg $::annotation::Vars(dialog)
	foreach f [winfo children $dlg.top.std] {
		if {[winfo exists $f.$nag]} { return $f.$nag }
	}
	return ""
}

tcltest::test annpal-interesting {!? from the palette marks the current move} -setup {
	::menu::gameNew .application
	update
	::move::addMove menu d4
	update
} -body {
	::annotation::open .application
	update
	set b [::scidb::test::annpal::button 5]
	$b invoke
	update
	set a [::scidb::game::query annotation]
	::annotation::close
	expr {[string first 5 $a] >= 0 || [string first "!?" $a] >= 0}
} -result 1

tcltest::test annpal-notation-keys {the notation has the shortcuts its context menu lists} -body {
	set pgn [lindex [lsearch -all -inline -glob $::application::board::Vars(need-binding) *.pgn] 0]
	lmap key {Control-Shift-C Control-c Control-a Control-m} { expr {[bind $pgn <$key>] ne ""} }
} -result {1 1 1 1}

tcltest::cleanupTests
