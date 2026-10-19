# ======================================================================
# Scidb App Test — Action registry core API (VAL-REG-001)
# ======================================================================
# Tests for ::action::register, run, list, get with rejection cases.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::actions {}

if {[llength [info commands ::action::register]] == 0} {
	source [file join [file dirname [file normalize [info script]]] .. tcl actions.tcl]
}

tcltest::test actions-register-basic {register stores an action with required label} -body {
	set id [::action::register test.basic {
		label ::test::mc::BasicAction
		doc "A basic test action"
	}]
	expr {$id eq "test.basic"}
} -result 1

tcltest::test actions-register-duplicate {duplicate ids are rejected with exact error} -setup {
	::action::register test.dup {label ::test::mc::Dup}
} -body {
	catch {::action::register test.dup {label ::test::mc::DupAgain}} err
	set err
} -match glob -result {error: duplicate action id*}

tcltest::test actions-register-missing-label {missing label field is rejected} -body {
	catch {::action::register test.nolabel {doc "no label"}} err
	set err
} -match glob -result {error:*missing*label*}

tcltest::test actions-register-empty-id {empty id is rejected} -body {
	catch {::action::register "" {label ::test::mc::Empty}} err
	set err
} -match glob -result {error:*empty*}

tcltest::test actions-get-existing {get returns the stored record} -setup {
	::action::register test.getme {
		label ::test::mc::GetMe
		doc "Get this action"
		handler {list got}
	}
} -body {
	set rec [::action::get test.getme]
	list [dict get $rec label] [dict get $rec doc]
} -result {::test::mc::GetMe {Get this action}}

tcltest::test actions-get-missing {get rejects unknown id} -body {
	catch {::action::get nonexistent.action} err
	set err
} -match glob -result {error:*unknown*}

tcltest::test actions-list-includes-registered {list returns all registered ids} -setup {
	foreach id [::action::list] {
		if {[string match "test.list.*" $id]} {
			catch { rename ::action::Registry ::action::_savedReg }
		}
	}
} -body {
	::action::register test.list.a {label ::test::mc::A}
	::action::register test.list.b {label ::test::mc::B}
	set ids [::action::list]
	expr {[lsearch -exact $ids "test.list.a"] >= 0 && [lsearch -exact $ids "test.list.b"] >= 0}
} -result 1

tcltest::test actions-run-no-handler {run returns error when no handler} -setup {
	::action::register test.nohandler {label ::test::mc::NoHandler}
} -body {
	::action::run test.nohandler
} -match glob -result {error:*no handler*}

tcltest::test actions-run-with-handler {run calls handler with validated args} -setup {
	variable ::scidb::test::actions::handlerCalled 0
	variable ::scidb::test::actions::handlerArgs {}
	proc ::scidb::test::actions::stubHandler {argsDict} {
		variable ::scidb::test::actions::handlerCalled
		variable ::scidb::test::actions::handlerArgs
		set handlerCalled 1
		set handlerArgs $argsDict
		return ok
	}
	::action::register test.withhandler {
		label ::test::mc::WithHandler
		args {{name {type string}}}
		handler ::scidb::test::actions::stubHandler
	}
} -body {
	set result [::action::run test.withhandler {name Alice}]
	list $result $::scidb::test::actions::handlerCalled $::scidb::test::actions::handlerArgs
} -cleanup {
	rename ::scidb::test::actions::stubHandler {}
} -result {ok 1 {name Alice}}

tcltest::test actions-run-unknown-id {run returns error for unknown id} -body {
	::action::run totally.unknown
} -match glob -result {error:*unknown*}

tcltest::test actions-normalized-fields {all fields are normalized with defaults} -setup {
	::action::register test.norm {
		label ::test::mc::Norm
		confirm 1
		bulk yes
		async true
	}
} -body {
	set r [::action::get test.norm]
	list [dict get $r confirm] [dict get $r bulk] [dict get $r async] \
		[dict get $r object] [dict get $r ai] [dict get $r maxreply]
} -result {1 1 1 {} 0 6000}

tcltest::test actions-register-invalid-ai {ai field must be 0, 1, or debug} -body {
	catch {::action::register test.badai {label ::test::mc::BadAI ai invalid}} err
	set err
} -match glob -result {error:*ai*must be*}

tcltest::test actions-register-valid-ai-debug {ai debug value is accepted} -body {
	set id [::action::register test.aidebug {label ::test::mc::AIDebug ai debug}]
	dict get [::action::get $id] ai
} -result debug

tcltest::test actions-register-invalid-boolean {boolean fields reject non-boolean values} -body {
	catch {::action::register test.badbool {label ::test::mc::BadBool confirm maybe}} err
	set err
} -match glob -result {error:*confirm*must be boolean*}

tcltest::test actions-register-invalid-maxreply {maxreply must be integer} -body {
	catch {::action::register test.badmr {label ::test::mc::BadMR maxreply slow}} err
	set err
} -match glob -result {error:*maxreply*must be*integer*}

tcltest::test actions-register-valid-maxreply {maxreply accepts integer} -body {
	set id [::action::register test.goodmr {label ::test::mc::GoodMR maxreply 3000}]
	dict get [::action::get $id] maxreply
} -result 3000

::tcltest::cleanupTests
return
