# Regression: View > Panes > Board off must not raise background errors.
# Before the fix, with the board pane closed, the reflow debounce
# (updateCollapse) did "$twm leaf board" -> "cannot find leaf 'board'", and
# board::setFocus did "focus <gone canvas>" -> "bad window path name".
package require tcltest 2.5

namespace eval ::boardPaneTest {
	variable bg {}
	proc wait {ms} { set ::boardPaneTest::w 0; after $ms {set ::boardPaneTest::w 1}; vwait ::boardPaneTest::w }
	proc record {cmd op} { lappend ::boardPaneTest::bg [lindex $cmd 1] }
}

tcltest::test boardpane-bgerror-1.0 {closed board pane: reflow, tab switch and focus raise no background error} -body {
	set t $::application::Vars(board:twm)
	::application::switchTab board
	::boardPaneTest::wait 500
	set ::boardPaneTest::bg {}
	trace add execution ::scidb::bgerror enter ::boardPaneTest::record
	$t close [$t leaf board]
	::boardPaneTest::wait 1500
	# direct calls: the stale-handle paths, deterministic
	::application::reflow::updateCollapse
	::application::board::setFocus
	::application::switchTab board
	# and the timer-driven path: window resize -> debounced reflow
	set g [wm geometry .application]
	wm geometry .application 1500x900; ::boardPaneTest::wait 1200
	wm geometry .application 1700x1000; ::boardPaneTest::wait 1200
	wm geometry .application $g; ::boardPaneTest::wait 600
	list [expr {"board" in [$t leaves]}] $::boardPaneTest::bg
} -cleanup {
	trace remove execution ::scidb::bgerror enter ::boardPaneTest::record
} -result {0 {}}

tcltest::test boardpane-bgerror-1.1 {reopened board pane focuses its new canvas} -body {
	::application::openPane board
	::boardPaneTest::wait 1500
	set c $::application::board::Vars(widget:frame)
	::application::board::setFocus
	list [winfo exists $c] [expr {[focus] eq $c}]
} -result {1 1}

tcltest::cleanupTests
