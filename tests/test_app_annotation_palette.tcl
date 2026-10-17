# ======================================================================
# Scidb App Test - the annotation palette (Run 14 tester bug)
# ======================================================================
# Run 14: clicking !? in the "Annotation" palette left 1.d4 unmarked.
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

tcltest::cleanupTests
