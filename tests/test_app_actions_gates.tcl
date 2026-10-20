# ======================================================================
# Scidb App Test — Action registry confirm/bulk/debug gates (VAL-REG-006)
# ======================================================================
# Tests for confirm, bulk and debug enforcement on all paths.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::actions_gates {}

if {[llength [info commands ::action::register]] == 0} {
	source [file join [file dirname [file normalize [info script]]] .. tcl actions.tcl]
}

tcltest::test gate-confirm-run-blocks {confirm action declines when hook returns 0} -setup {
	variable ::scidb::test::actions_gates::hookCalled 0
	proc ::scidb::test::actions_gates::declineHook {what} {
		variable ::scidb::test::actions_gates::hookCalled
		set hookCalled 1
		return 0
	}
	proc ::scidb::test::actions_gates::dummyHandler {argsDict} { return ok }
	set ::action::ConfirmHook ::scidb::test::actions_gates::declineHook
	::action::register test.gates.confirm.decline {
		label ::test::mc::ConfirmDecline
		confirm 1
		what "test confirm action"
		handler ::scidb::test::actions_gates::dummyHandler

		object {}
		doc {}
	}
} -body {
	set result [::action::run test.gates.confirm.decline]
	list $result $::scidb::test::actions_gates::hookCalled
} -cleanup {
	set ::action::ConfirmHook {}
	rename ::scidb::test::actions_gates::declineHook {}
	rename ::scidb::test::actions_gates::dummyHandler {}
} -result {declined 1}

tcltest::test gate-confirm-run-allows {confirm action proceeds when hook returns 1} -setup {
	variable ::scidb::test::actions_gates::allowCalled 0
	proc ::scidb::test::actions_gates::allowHook {what} {
		variable ::scidb::test::actions_gates::allowCalled
		set allowCalled 1
		return 1
	}
	proc ::scidb::test::actions_gates::dummyHandler2 {argsDict} { return ok }
	set ::action::ConfirmHook ::scidb::test::actions_gates::allowHook
	::action::register test.confirm.allow {
		label ::test::mc::ConfirmAllow
		confirm 1
		what "test confirm action"
		handler ::scidb::test::actions_gates::dummyHandler2

		object {}
		doc {}
	}
} -body {
	set result [::action::run test.confirm.allow]
	list $result $::scidb::test::actions_gates::allowCalled
} -cleanup {
	set ::action::ConfirmHook {}
	rename ::scidb::test::actions_gates::allowHook {}
	rename ::scidb::test::actions_gates::dummyHandler2 {}
} -result {ok 1}

tcltest::test gate-bulk-run-blocks {bulk action declines when bulk hook returns 0} -setup {
	variable ::scidb::test::actions_gates::bulkCalled 0
	proc ::scidb::test::actions_gates::bulkDecline {what} {
		variable ::scidb::test::actions_gates::bulkCalled
		set bulkCalled 1
		return 0
	}
	proc ::scidb::test::actions_gates::dummyHandler3 {argsDict} { return ok }
	set ::action::BulkHook ::scidb::test::actions_gates::bulkDecline
	::action::register test.gates.bulk.decline {
		label ::test::mc::BulkDecline
		bulk 1
		what "test bulk action"
		handler ::scidb::test::actions_gates::dummyHandler3

		object {}
		doc {}
	}
} -body {
	set result [::action::run test.gates.bulk.decline]
	list $result $::scidb::test::actions_gates::bulkCalled
} -cleanup {
	set ::action::BulkHook {}
	rename ::scidb::test::actions_gates::bulkDecline {}
	rename ::scidb::test::actions_gates::dummyHandler3 {}
} -result {declined 1}

tcltest::test gate-debug-labels-excluded {debug actions do not appear in labels} -setup {
	proc ::scidb::test::actions_gates::dummyHandler4 {argsDict} { return ok }
	::action::register test.debug.hidden {
		label ::test::mc::DebugHidden
		ai debug
		menu {Test 1}
		handler ::scidb::test::actions_gates::dummyHandler4

		what {}
		object {}
		doc {}
	}
	::action::register test.normal.visible {
		label ::test::mc::NormalVisible
		menu {Test 2}
		handler ::scidb::test::actions_gates::dummyHandler4

		what {}
		object {}
		doc {}
	}
} -body {
	set rows [::action::labels bar]
	set ids [lmap r $rows {lindex $r 0}]
	list \
		[expr {"test.debug.hidden" ni $ids}] \
		[expr {"test.normal.visible" in $ids}]
} -cleanup {
	rename ::scidb::test::actions_gates::dummyHandler4 {}
} -result {1 1}

tcltest::test gate-debug-list-included {debug actions are in list (for non-debug tool filtering)} -setup {
	proc ::scidb::test::actions_gates::dummyHandler5 {argsDict} { return ok }
	::action::register test.debug.listed {
		label ::test::mc::DebugListed
		ai debug
		handler ::scidb::test::actions_gates::dummyHandler5

		what {}
		object {}
		doc {}
	}
} -body {
	set ids [::action::list]
	expr {"test.debug.listed" in $ids}
} -cleanup {
	rename ::scidb::test::actions_gates::dummyHandler5 {}
} -result 1

tcltest::test gate-confirm-no-hook-proceeds {confirm action proceeds when no hook is set} -setup {
	proc ::scidb::test::actions_gates::dummyHandler6 {argsDict} { return ok }
	set ::action::ConfirmHook {}
	::action::register test.confirm.nohook {
		label ::test::mc::ConfirmNoHook
		confirm 1
		what "test"
		handler ::scidb::test::actions_gates::dummyHandler6

		object {}
		doc {}
	}
} -body {
	::action::run test.confirm.nohook
} -cleanup {
	rename ::scidb::test::actions_gates::dummyHandler6 {}
} -result {ok}

tcltest::test gate-bulk-and-confirm-bulk-takes-precedence {bulk hook is called for bulk+confirm action} -setup {
	variable ::scidb::test::actions_gates::whichHook ""
	proc ::scidb::test::actions_gates::trackHook {what} {
		variable ::scidb::test::actions_gates::whichHook
		lappend whichHook $what
		return 1
	}
	proc ::scidb::test::actions_gates::dummyHandler7 {argsDict} { return ok }
	set ::action::ConfirmHook ::scidb::test::actions_gates::trackHook
	set ::action::BulkHook ::scidb::test::actions_gates::trackHook
	::action::register test.both.hooks {
		label ::test::mc::BothHooks
		confirm 1
		bulk 1
		what "test both"
		handler ::scidb::test::actions_gates::dummyHandler7

		object {}
		doc {}
	}
} -body {
	set ::scidb::test::actions_gates::whichHook {}
	::action::run test.both.hooks
	set ::scidb::test::actions_gates::whichHook
} -cleanup {
	set ::action::ConfirmHook {}
	set ::action::BulkHook {}
	rename ::scidb::test::actions_gates::trackHook {}
	rename ::scidb::test::actions_gates::dummyHandler7 {}
} -result {{test both}}

::tcltest::cleanupTests
return
