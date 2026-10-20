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
		what {} \
		object {} \
		doc {} \
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
		what {} \
		object {} \
		doc {} \
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
		what {} \
		object {} \
		doc {} \
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
		what {} \
		doc {} \
		object {} \
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
		what {} \
		doc {} \
		object {} \
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
		what {} \
		object {} \
		doc {} \
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
		what {} \
		object {} \
		doc {} \
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
		object {} \
		doc {} \
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
		object {} \
		doc {} \
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
		what {} \
		doc {} \
	]
} -body {
	::action::run test.obj.inject
	expr {[dict exists $::capturedArgs _object] && [dict get $::capturedArgs _object] eq "TEST_OBJ_REF"}
} -cleanup {
	rename ::testObjHandler {}
} -result 1

# ----------------------------------------------------------------------
# VAL-REG-005 on the production path: the real tools carry args specs,
# so run/runTool/invoke all use the one shared validator.
# ----------------------------------------------------------------------
test g1-real-tools-have-args-specs {
	every shipped assistant tool has a real args spec (not empty passthrough only)
} -body {
	package require json
	set missing {}
	foreach name [dict keys $::application::assistant::Actions] {
		set record [::action::get $name]
		if {[dict get $record args] eq "" && [dict get $record schema] ne ""} {
			# zero-argument tools legitimately use an empty spec with a schema
			if {[llength [::json::json2dict [dict get $record schema]]] && \
			    [dict size [dict get [::json::json2dict [dict get $record schema]] properties]]} {
				lappend missing $name
			}
		} elseif {[dict get $record args] eq ""} {
			lappend missing $name
		}
	}
	set missing
} -result {}

test g1-switch-tab-shared-validator {
	valid arguments pass the shared validator, invalid ones return error:
} -body {
	set ok [::action::validateArgs switch_tab {tab database}]
	set bad [::action::validateArgs switch_tab {tab definitely-not-a-tab}]
	list [lindex $ok 0] [dict get [lindex $ok 1] tab] \
		[lindex $bad 0] [string match "*must be*board*database*" [lindex $bad 1]]
} -result {ok database error 1}

test g1-switch-tab-invoke-validates {
	invoke accepts valid args and rejects invalid args before the handler
} -setup {
	variable ::scidb::test::g1::invoked 0
	rename ::application::assistant::DoSwitchTab ::scidb::test::g1::realSwitchTab
	proc ::application::assistant::DoSwitchTab {tab} {
		incr ::scidb::test::g1::invoked
		return "stub:$tab"
	}
} -body {
	set valid [::action::invoke switch_tab {tab database}]
	set afterValid $::scidb::test::g1::invoked
	set invalid [::action::invoke switch_tab {tab nonsense}]
	set afterInvalid $::scidb::test::g1::invoked
	list $valid $afterValid $invalid $afterInvalid
} -cleanup {
	rename ::application::assistant::DoSwitchTab {}
	rename ::scidb::test::g1::realSwitchTab ::application::assistant::DoSwitchTab
} -result {stub:database 1 {error: tab must be 'board' or 'database'} 1}

test g1-assistant-run-tool-shared-validator {
	assistant runTool rejects bad args before the handler and passes valid ones
} -setup {
	variable ::scidb::test::g1::toolInvoked 0
	rename ::application::assistant::DoSwitchTab ::scidb::test::g1::realSwitchTab2
	proc ::application::assistant::DoSwitchTab {tab} {
		incr ::scidb::test::g1::toolInvoked
		return "stub:$tab"
	}
} -body {
	set valid [::application::assistant::runTool switch_tab {tab board}]
	set afterValid $::scidb::test::g1::toolInvoked
	set invalid [::application::assistant::runTool switch_tab {tab nonsense}]
	set afterInvalid $::scidb::test::g1::toolInvoked
	list $valid $afterValid $invalid $afterInvalid
} -cleanup {
	rename ::application::assistant::DoSwitchTab {}
	rename ::scidb::test::g1::realSwitchTab2 ::application::assistant::DoSwitchTab
} -result {stub:board 1 {error: tab must be 'board' or 'database'} 1}

# ----------------------------------------------------------------------
# VAL-REG-006 on the production path: bulk gates apply to runTool and the
# router's DeliverRouted, not only to ::action::run.
# ----------------------------------------------------------------------
test g1-assistant-bulk-gate {
	compact_database is blocked on the assistant path when BulkHook declines
} -setup {
	variable ::scidb::test::g1::compactRan 0
	rename ::application::assistant::DoCompactDatabase ::scidb::test::g1::realCompact
	proc ::application::assistant::DoCompactDatabase {} {
		set ::scidb::test::g1::compactRan 1
		return stub-compact
	}
	proc ::scidb::test::g1::bulkNo {what} { return 0 }
	proc ::scidb::test::g1::bulkYes {what} { return 1 }
	set savedBulk $::action::BulkHook
	set savedConfirm $::application::assistant::Priv(confirm)
	set ::action::BulkHook ::scidb::test::g1::bulkNo
	set ::application::assistant::Priv(confirm) ::scidb::test::g1::bulkYes
} -body {
	set result [::application::assistant::runTool compact_database {}]
	list $result $::scidb::test::g1::compactRan [string match "*NOT performed*" $result]
} -cleanup {
	set ::action::BulkHook $savedBulk
	set ::application::assistant::Priv(confirm) $savedConfirm
	rename ::application::assistant::DoCompactDatabase {}
	rename ::scidb::test::g1::realCompact ::application::assistant::DoCompactDatabase
} -result {{The user declined: the action was NOT performed and no dialog was opened.} 0 1}

test g1-router-bulk-gate {
	compact_database is blocked on the router DeliverRouted path when BulkHook declines
} -setup {
	variable ::scidb::test::g1::routedRan 0
	rename ::application::assistant::DoCompactDatabase ::scidb::test::g1::realCompact2
	proc ::application::assistant::DoCompactDatabase {} {
		set ::scidb::test::g1::routedRan 1
		return stub-compact
	}
	proc ::scidb::test::g1::bulkNo2 {what} { return 0 }
	proc ::scidb::test::g1::bulkYes {what} { return 1 }
	set savedBulk $::action::BulkHook
	set savedConfirm $::application::assistant::Priv(confirm)
	set savedMessages $::application::assistant::Priv(messages)
	set ::action::BulkHook ::scidb::test::g1::bulkNo2
	set ::application::assistant::Priv(confirm) ::scidb::test::g1::bulkYes
} -body {
	::application::assistant::DeliverRouted compact_database {} 0
	list $::scidb::test::g1::routedRan \
		[string match "*NOT performed*" [lindex $::application::assistant::Priv(messages) end]]
} -cleanup {
	set ::action::BulkHook $savedBulk
	set ::application::assistant::Priv(confirm) $savedConfirm
	set ::application::assistant::Priv(messages) $savedMessages
	rename ::application::assistant::DoCompactDatabase {}
	rename ::scidb::test::g1::realCompact2 ::application::assistant::DoCompactDatabase
} -result {0 1}

# ----------------------------------------------------------------------
# VAL-REG-004: ai is the exposure flag, so ai-exposed == toolsJson.
# ----------------------------------------------------------------------
test g1-ai-exposed-equals-toolsjson {
	ai-exposed ids are exactly the toolsJson names in normal and debug mode
} -body {
	package require json
	set savedDebug $::application::assistant::Priv(debug)
	set ::application::assistant::Priv(debug) 0
	set normal [lsort [lmap t [::json::json2dict [::application::assistant::toolsJson]] {dict get $t function name}]]
	set exposed {}
	foreach id [::action::list] {
		if {[dict get [::action::get $id] ai] eq "1"} { lappend exposed $id }
	}
	set normalOk [expr {$normal eq [lsort $exposed]}]
	set ::application::assistant::Priv(debug) 1
	set debugJson [lsort [lmap t [::json::json2dict [::application::assistant::toolsJson]] {dict get $t function name}]]
	set exposedDebug {}
	foreach id [::action::list] {
		set ai [dict get [::action::get $id] ai]
		if {$ai eq "1" || $ai eq "debug"} { lappend exposedDebug $id }
	}
	set debugOk [expr {$debugJson eq [lsort $exposedDebug]}]
	set ::application::assistant::Priv(debug) $savedDebug
	list $normalOk $debugOk
} -result {1 1}


cleanupTests
