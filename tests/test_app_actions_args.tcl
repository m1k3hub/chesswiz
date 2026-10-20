# ======================================================================
# Scidb App Test — Action argument validation (VAL-REG-005)
# ======================================================================
# Tests that one shared validator checks types, enums, required and
# ranges; bad arguments return "error: ..." text and never reach handler.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::actions_args {}

if {[llength [info commands ::action::register]] == 0} {
	source [file join [file dirname [file normalize [info script]]] .. tcl actions.tcl]
}

tcltest::test args-schema-from-spec {args spec generates JSON schema} -body {
	set schema [::action::argsToSchema {
		name {type string required}
		count {type integer default 5 range {1 100}}
		mode {type enum enum {fast slow normal}}
	}]
	list [dict get $schema type] \
		[dict exists $schema properties name] \
		[dict exists $schema properties count] \
		[dict exists $schema properties mode]
} -result {object 1 1 1}

tcltest::test args-schema-empty {empty spec produces empty object schema} -body {
	dict get [::action::argsToSchema {}] type
} -result object

tcltest::test args-validate-required-missing {missing required arg returns error} -setup {
	::action::register test.args.req {
		label ::test::mc::Req
		args {{path {type string}}}
		handler {list ok}

		what {}
		object {}
		doc {}
	}
} -body {
	::action::run test.args.req {}
} -match glob -result {error:*missing*path*}

tcltest::test args-validate-required-present {required arg present reaches handler} -setup {
	variable ::scidb::test::actions_args::reached 0
	proc ::scidb::test::actions_args::stub {argsDict} {
		variable ::scidb::test::actions_args::reached
		set reached 1
		return ok
	}
	::action::register test.args.reqok {
		label ::test::mc::ReqOk
		args {{path {type string}}}
		handler ::scidb::test::actions_args::stub

		what {}
		object {}
		doc {}
	}
} -body {
	set r [::action::run test.args.reqok {path /tmp/x}]
	list $r $::scidb::test::actions_args::reached
} -cleanup {
	rename ::scidb::test::actions_args::stub {}
} -result {ok 1}

tcltest::test args-validate-enum-valid {valid enum value passes} -setup {
	proc ::scidb::test::actions_args::enumStub {argsDict} {
		return "got:[dict get $argsDict mode]"
	}
	::action::register test.args.enum {
		label ::test::mc::Enum
		args {{mode {type enum enum {fast slow}}}}
		handler ::scidb::test::actions_args::enumStub

		what {}
		object {}
		doc {}
	}
} -body {
	::action::run test.args.enum {mode fast}
} -cleanup {
	rename ::scidb::test::actions_args::enumStub {}
} -result {got:fast}

tcltest::test args-validate-enum-invalid {invalid enum returns error, handler not called} -setup {
	variable ::scidb::test::actions_args::enumCalled 0
	proc ::scidb::test::actions_args::enumStub2 {argsDict} {
		variable ::scidb::test::actions_args::enumCalled
		set enumCalled 1
		return ok
	}
	::action::register test.args.badenum {
		label ::test::mc::BadEnum
		args {{mode {type enum enum {fast slow}}}}
		handler ::scidb::test::actions_args::enumStub2

		what {}
		object {}
		doc {}
	}
} -body {
	set r [::action::run test.args.badenum {mode turbo}]
	list $r $::scidb::test::actions_args::enumCalled
} -cleanup {
	rename ::scidb::test::actions_args::enumStub2 {}
} -result {{error: argument 'mode' must be one of: fast, slow} 0}

tcltest::test args-validate-integer-range {integer out of range returns error} -setup {
	proc ::scidb::test::actions_args::intStub {argsDict} {return ok}
	::action::register test.args.int {
		label ::test::mc::Int
		args {{count {type integer range {1 10}}}}
		handler ::scidb::test::actions_args::intStub

		what {}
		object {}
		doc {}
	}
} -body {
	list [::action::run test.args.int {count 0}] [::action::run test.args.int {count 11}]
} -cleanup {
	rename ::scidb::test::actions_args::intStub {}
} -match glob -result {{error:*between 1 and 10*} {error:*between 1 and 10*}}

tcltest::test args-validate-integer-valid {integer in range passes} -setup {
	proc ::scidb::test::actions_args::intStub2 {argsDict} {
		return "count=[dict get $argsDict count]"
	}
	::action::register test.args.intok {
		label ::test::mc::IntOk
		args {{count {type integer range {1 10}}}}
		handler ::scidb::test::actions_args::intStub2

		what {}
		object {}
		doc {}
	}
} -body {
	::action::run test.args.intok {count 5}
} -cleanup {
	rename ::scidb::test::actions_args::intStub2 {}
} -result {count=5}

tcltest::test args-validate-default-used {default used when arg omitted} -setup {
	proc ::scidb::test::actions_args::defStub {argsDict} {
		return "n=[dict get $argsDict n]"
	}
	::action::register test.args.def {
		label ::test::mc::Def
		args {{n {type integer default 42}}}
		handler ::scidb::test::actions_args::defStub

		what {}
		object {}
		doc {}
	}
} -body {
	::action::run test.args.def {}
} -cleanup {
	rename ::scidb::test::actions_args::defStub {}
} -result {n=42}

tcltest::test args-validate-boolean-normalized {boolean values are normalized} -setup {
	proc ::scidb::test::actions_args::boolStub {argsDict} {
		return "flag=[dict get $argsDict flag]"
	}
	::action::register test.args.bool {
		label ::test::mc::Bool
		args {{flag {type boolean}}}
		handler ::scidb::test::actions_args::boolStub

		what {}
		object {}
		doc {}
	}
} -body {
	list [::action::run test.args.bool {flag true}] \
		[::action::run test.args.bool {flag false}] \
		[::action::run test.args.bool {flag yes}] \
		[::action::run test.args.bool {flag no}] \
		[::action::run test.args.bool {flag 1}] \
		[::action::run test.args.bool {flag 0}]
} -cleanup {
	rename ::scidb::test::actions_args::boolStub {}
} -result {flag=1 flag=0 flag=1 flag=0 flag=1 flag=0}

tcltest::test args-validate-no-args-action {action with no args rejects supplied args} -setup {
	proc ::scidb::test::actions_args::noArgStub {argsDict} {return ok}
	::action::register test.args.noargs {
		label ::test::mc::NoArgs
		args {}
		handler ::scidb::test::actions_args::noArgStub

		what {}
		object {}
		doc {}
	}
} -body {
	::action::run test.args.noargs {x 1}
} -cleanup {
	rename ::scidb::test::actions_args::noArgStub {}
} -match glob -result {error:*takes no arguments*}

::tcltest::cleanupTests
return
