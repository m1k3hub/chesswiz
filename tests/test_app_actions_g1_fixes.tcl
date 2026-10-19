# Tests for G1 Part B fixes (VAL-REG-005/006/007)
# Run: HOME=$PWD/tests/tmp-app/app-home-g1 xvfb-run -a -s '-screen 0 1920x1080x24' \
#      src/tkchesswiz tests/run_app_tests.tcl -match 'g1-*'

package require Tcl 8.5
package require tcltest 2.5
namespace import ::tcltest::*

namespace eval ::scidb::test::g1 {}

if {[llength [info commands ::action::register]] == 0} {
	source [file join [file dirname [file normalize [info script]]] .. tcl actions.tcl]
}

# ----------------------------------------------------------------------
# VAL-REG-005: argsToSchema honors explicit required; cross-arg hook; 
#              passthrough schemas go through validator
# ----------------------------------------------------------------------

test g1-schema-explicit-required-1 {
	argsToSchema marks param as required when explicit required 1 even with default
} -body {
	set spec {{mode {type enum default auto required 1 enum {auto manual}}}}
	set schema [::action::argsToSchema $spec]
	set req [dict get $schema required]
	expr {"mode" in $req}
} -result 1

test g1-schema-explicit-required-2 {
	argsToSchema does NOT mark param as required when explicit required 0
} -body {
	set spec {{mode {type string default auto required 0}}}
	set schema [::action::argsToSchema $spec]
	dict exists $schema required
} -result 0

test g1-validate-explicit-required-missing {
	validateArgs rejects missing arg marked required even with default
} -setup {
	::action::register test.req.explicit [dict create \
		label TestRequired \
		args {{mode {type enum default auto required 1 enum {auto manual}}}} \
		handler [list return ok] \
	]
} -body {
	set result [::action::validateArgs test.req.explicit [dict create]]
	lindex $result 0
} -cleanup {
	# Cannot unregister, but that's okay for tests
} -result error

test g1-validate-explicit-required-present {
	validateArgs accepts present arg marked required
} -body {
	set result [::action::validateArgs test.req.explicit [dict create mode manual]]
	lindex $result 0
} -result ok

test g1-crossarg-hook-called {
	cross-argument validation hook is invoked after basic validation
} -setup {
	set ::scidb::test::g1::hookCalled 0
	proc ::scidb::test::g1::crossArgHook {argsDict} {
		set ::scidb::test::g1::hookCalled 1
		return ok
	}
	::action::register test.crossarg [dict create \
		label TestCrossArg \
		args {{x {type integer}} {y {type integer}}} \
		validate ::scidb::test::g1::crossArgHook \
		handler [list return ok] \
	]
} -body {
	set ::scidb::test::g1::hookCalled 0
	::action::validateArgs test.crossarg [dict create x 1 y 2]
	set ::scidb::test::g1::hookCalled
} -cleanup {
	rename ::scidb::test::g1::crossArgHook {}
} -result 1

test g1-crossarg-hook-rejects {
	cross-argument validation hook can reject with error
} -setup {
	proc ::scidb::test::g1::crossArgReject {argsDict} {
		if {[dict get $argsDict x] > [dict get $argsDict y]} {
			return [list error "x must be <= y"]
		}
		return ok
	}
	::action::register test.crossarg.reject [dict create \
		label TestCrossArgReject \
		args {{x {type integer}} {y {type integer}}} \
		validate ::scidb::test::g1::crossArgReject \
		handler [list return ok] \
	]
} -body {
	set result [::action::validateArgs test.crossarg.reject [dict create x 10 y 5]]
	list [lindex $result 0] [string match "*x must be <= y*" [lindex $result 1]]
} -cleanup {
	rename ::scidb::test::g1::crossArgReject {}
} -result {error 1}

test g1-passthrough-with-args-validates {
	passthrough schema with args spec still runs validator
} -setup {
	::action::register test.passthrough.validate [dict create \
		label TestPassthroughValidate \
		schema {{type object properties {mode {type string}}}} \
		args {mode {type enum enum {a b c}}} \
		handler [list return ok] \
	]
} -body {
	set result [::action::run test.passthrough.validate [dict create mode invalid]]
	string match "error:*" $result
} -result 1

test g1-passthrough-no-args-skips {
	passthrough schema without args spec skips validation
} -setup {
	proc ::scidb::test::g1::passthroughHandler {argsDict} {
		return passthrough-ok
	}
	::action::register test.passthrough.noargs [dict create \
		label TestPassthroughNoArgs \
		schema {{type object properties {mode {type string}}}} \
		handler ::scidb::test::g1::passthroughHandler \
	]
} -body {
	set result [::action::run test.passthrough.noargs [dict create anything goes]]
	string match "passthrough-ok" $result
} -cleanup {
	rename ::scidb::test::g1::passthroughHandler {}
} -result 1

# ----------------------------------------------------------------------
# VAL-REG-006: ConfirmHook/BulkHook wired; debug gate in registry
# ----------------------------------------------------------------------

test g1-confirm-hook-variable-exists {
	ConfirmHook variable exists and can be set
} -body {
	set saved $::action::ConfirmHook
	set ::action::ConfirmHook ::testConfirmHook
	set result [expr {$::action::ConfirmHook eq "::testConfirmHook"}]
	set ::action::ConfirmHook $saved
	set result
} -result 1

test g1-bulk-hook-variable-exists {
	BulkHook variable exists and can be set
} -body {
	set saved $::action::BulkHook
	set ::action::BulkHook ::testBulkHook
	set result [expr {$::action::BulkHook eq "::testBulkHook"}]
	set ::action::BulkHook $saved
	set result
} -result 1

test g1-debug-gate-variable-exists {
	DebugGate variable exists and can be set
} -body {
	set saved $::action::DebugGate
	set ::action::DebugGate "expr {1}"
	set result [expr {$::action::DebugGate ne ""}]
	set ::action::DebugGate $saved
	set result
} -result 1

test g1-debug-action-blocked-without-gate {
	debug action returns error when DebugGate evaluates to 0
} -setup {
	set saved $::action::DebugGate
	set ::action::DebugGate {expr {0}}
	::action::register test.debug.blocked [dict create \
		label TestDebugBlocked \
		ai debug \
		handler [list return should-not-run] \
	]
} -body {
	set result [::action::run test.debug.blocked]
	string match "error:*debug mode*" $result
} -cleanup {
	set ::action::DebugGate $saved
} -result 1

test g1-debug-action-allowed-with-gate {
	debug action runs when DebugGate evaluates to 1
} -setup {
	set saved $::action::DebugGate
	set ::action::DebugGate "expr {1}"
	proc ::scidb::test::g1::debugHandler {argsDict} {
		return debug-ok
	}
	::action::register test.debug.allowed [dict create \
		label TestDebugAllowed \
		ai debug \
		handler ::scidb::test::g1::debugHandler \
	]
} -body {
	set result [::action::run test.debug.allowed]
	string match "debug-ok" $result
} -cleanup {
	set ::action::DebugGate $saved
	rename ::scidb::test::g1::debugHandler {}
} -result 1

test g1-invoke-debug-gate {
	invoke also enforces debug gate
} -body {
	set saved $::action::DebugGate
	set ::action::DebugGate {expr {0}}
	set result [::action::invoke test.debug.blocked]
	set ::action::DebugGate $saved
	string match "error:*debug mode*" $result
} -result 1

test g1-confirm-gate-enforced-via-run {
	confirm action blocked when declined via ConfirmHook
} -setup {
	proc ::testDeclineHook {what} { return 0 }
	set saved $::action::ConfirmHook
	set ::action::ConfirmHook ::testDeclineHook
	::action::register test.confirm.decline [dict create \
		label TestConfirmDecline \
		confirm 1 \
		what "test confirm" \
		handler [list return should-not-run] \
	]
} -body {
	set result [::action::run test.confirm.decline]
	expr {$result eq "declined"}
} -cleanup {
	set ::action::ConfirmHook $saved
	rename ::testDeclineHook {}
} -result 1

test g1-bulk-gate-enforced-via-run {
	bulk action blocked when declined via BulkHook
} -setup {
	proc ::testBulkDecline {what} { return 0 }
	set saved $::action::BulkHook
	set ::action::BulkHook ::testBulkDecline
	::action::register test.bulk.decline [dict create \
		label TestBulkDecline \
		bulk 1 \
		what "test bulk" \
		handler [list return should-not-run] \
	]
} -body {
	set result [::action::run test.bulk.decline]
	expr {$result eq "declined"}
} -cleanup {
	set ::action::BulkHook $saved
	rename ::testBulkDecline {}
} -result 1

# ----------------------------------------------------------------------
# VAL-REG-007: resolver::register fixed; production resolvers exist
# ----------------------------------------------------------------------

test g1-resolver-register-doesnt-wipe {
	resolver::register preserves existing resolvers (not wipe bug)
} -body {
	::action::resolver::register typeA {return A}
	::action::resolver::register typeB {return B}
	set a [::action::resolver::resolve typeA]
	set b [::action::resolver::resolve typeB]
	expr {$a eq "A" && $b eq "B"}
} -result 1

test g1-resolver-can-register-multiple {
	can register multiple resolvers without wiping
} -body {
	::action::resolver::register game_test {return GAME}
	::action::resolver::register db_test {return DB}
	::action::resolver::register move_test {return MOVE}
	set g [::action::resolver::resolve game_test]
	set d [::action::resolver::resolve db_test]
	set m [::action::resolver::resolve move_test]
	expr {$g eq "GAME" && $d eq "DB" && $m eq "MOVE"}
} -result 1

test g1-resolver-injects-object {
	run() injects _object from resolver into validated args
} -setup {
	::action::resolver::register testobj {return TEST_OBJ_REF}
	variable ::capturedArgs {}
	proc ::testObjHandler {argsDict} {
		variable ::capturedArgs
		set ::capturedArgs $argsDict
		return ok
	}
	::action::register test.obj.inject [dict create \
		label TestObjInject \
		object testobj \
		handler ::testObjHandler \
	]
} -body {
	::action::run test.obj.inject
	expr {[dict exists $::capturedArgs _object] && [dict get $::capturedArgs _object] eq "TEST_OBJ_REF"}
} -cleanup {
	rename ::testObjHandler {}
} -result 1

cleanupTests
