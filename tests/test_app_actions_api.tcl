# ======================================================================
# Scidb App Test — Script API by action id (VAL-REG-008)
# ======================================================================
# ::action::labels <surface> returns rows without posting any menu.
# ::action::invoke <id> runs an action as a user click would.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::actions_api {}

if {[llength [info commands ::action::register]] == 0} {
	source [file join [file dirname [file normalize [info script]]] .. tcl actions.tcl]
}

tcltest::test api-labels-bar {labels bar surface returns menu actions} -setup {
	::action::register test.bar.game {
		label ::gamebar::mc::GameNew
		menu {Game 10}
		keys {chesswiz Control-n}
		handler {list ok}

		what {}
		object {}
		doc {}
	}
	::action::register test.bar.open {
		label ::menu::mc::Open
		menu {File 1}
		handler {list ok}

		what {}
		object {}
		doc {}
	}
	::action::register test.ctx.only {
		label ::ctx::mc::Only
		context {C3}
		handler {list ok}

		what {}
		object {}
		doc {}
	}
} -body {
	set rows [::action::labels bar]
	set ids [lmap row $rows {lindex $row 0}]
	list \
		[expr {"test.bar.game" in $ids}] \
		[expr {"test.bar.open" in $ids}] \
		[expr {"test.ctx.only" ni $ids}]
} -result {1 1 1}

tcltest::test api-labels-context {labels context:<id> returns matching context actions} -setup {
	::action::register test.ctx.c1a {
		label ::ctx::mc::C1A
		context {C1}
		handler {list ok}

		what {}
		object {}
		doc {}
	}
	::action::register test.ctx.c1b {
		label ::ctx::mc::C1B
		context {C1 C2}
		handler {list ok}

		what {}
		object {}
		doc {}
	}
	::action::register test.ctx.c2only {
		label ::ctx::mc::C2Only
		context {C2}
		handler {list ok}

		what {}
		object {}
		doc {}
	}
} -body {
	set c1rows [::action::labels context:C1]
	set c1ids [lmap r $c1rows {lindex $r 0}]
	set c2rows [::action::labels context:C2]
	set c2ids [lmap r $c2rows {lindex $r 0}]
	list \
		[expr {"test.ctx.c1a" in $c1ids}] \
		[expr {"test.ctx.c1b" in $c1ids}] \
		[expr {"test.ctx.c2only" ni $c1ids}] \
		[expr {"test.ctx.c1b" in $c2ids}] \
		[expr {"test.ctx.c2only" in $c2ids}]
} -result {1 1 1 1 1}

tcltest::test api-labels-row-format {each row has id label accelerator enabled visible} -setup {
	::action::register test.row.fmt {
		label ::fmt::mc::Row
		menu {Edit 5}
		keys {chesswiz Shift-F5}
		handler {list ok}

		what {}
		object {}
		doc {}
	}
} -body {
	set rows [::action::labels bar]
	foreach row $rows {
		if {[lindex $row 0] eq "test.row.fmt"} {
			return [llength $row]
		}
	}
	return 0
} -result 5

tcltest::test api-invoke-runs-action {invoke calls the action like run} -setup {
	variable ::scidb::test::actions_api::invoked 0
	proc ::scidb::test::actions_api::invStub {argsDict} {
		variable ::scidb::test::actions_api::invoked
		set invoked 1
		return invoked_ok
	}
	::action::register test.invoke.me {
		label ::inv::mc::Me
		handler ::scidb::test::actions_api::invStub

		what {}
		object {}
		doc {}
	}
} -body {
	set r [::action::invoke test.invoke.me]
	list $r $::scidb::test::actions_api::invoked
} -cleanup {
	rename ::scidb::test::actions_api::invStub {}
} -result {invoked_ok 1}

tcltest::test api-invoke-with-args {invoke passes args through} -setup {
	proc ::scidb::test::actions_api::argInvStub {argsDict} {
		if {[dict exists $argsDict x]} { return "x=[dict get $argsDict x]" }
		return "x=none"
	}
	::action::register test.invoke.args {
		label ::inv::mc::Args
		args {{x {type integer}}}
		handler ::scidb::test::actions_api::argInvStub

		what {}
		object {}
		doc {}
	}
} -body {
	::action::invoke test.invoke.args {x 7}
} -cleanup {
	rename ::scidb::test::actions_api::argInvStub {}
} -result {x=7}

tcltest::test api-invoke-unknown {invoke returns error for unknown id} -body {
	::action::invoke totally.missing.action
} -match glob -result {error:*unknown*}

tcltest::test api-labels-palette {palette surface returns visible actions} -setup {
	::action::register test.pal.vis {
		label ::pal::mc::Vis
		handler {list ok}
		doc "visible in palette"

		what {}
		object {}
	}
} -body {
	set rows [::action::labels palette]
	set ids [lmap r $rows {lindex $r 0}]
	expr {"test.pal.vis" in $ids}
} -result 1

tcltest::test api-invoke-multiword-handler {invoke works with multi-word handler prefix like adapter} -setup {
	variable ::scidb::test::actions_api::adapterCalled 0
	variable ::scidb::test::actions_api::adapterArgs {}
	proc ::scidb::test::actions_api::adapterProc {name realHandler argsDict} {
		variable ::scidb::test::actions_api::adapterCalled
		variable ::scidb::test::actions_api::adapterArgs
		set adapterCalled 1
		set adapterArgs [list $name $realHandler $argsDict]
		return "adapted:$name"
	}
	::action::register test.multiword.adapter [dict create \
		label ::multi::mc::Adapter \
		handler [list ::scidb::test::actions_api::adapterProc switch_tab DoSwitchTab] \
		what {} \
		object {} \
		doc {} \
	]
} -body {
	set r [::action::invoke test.multiword.adapter]
	list $r $::scidb::test::actions_api::adapterCalled
} -cleanup {
	rename ::scidb::test::actions_api::adapterProc {}
} -result {adapted:switch_tab 1}

tcltest::test api-run-multiword-handler-with-args {run passes args to multi-word handler} -setup {
	proc ::scidb::test::actions_api::mwArgProc {prefix suffix argsDict} {
		if {[dict exists $argsDict tab]} {
			return "$prefix-$suffix-[dict get $argsDict tab]"
		}
		return "$prefix-$suffix"
	}
	::action::register test.mw.args [dict create \
		label ::mw::mc::Args \
		args {{tab {type string}}} \
		handler [list ::scidb::test::actions_api::mwArgProc pre suf] \
		what {} \
		object {} \
		doc {} \
	]
} -body {
	::action::run test.mw.args {tab board}
} -cleanup {
	rename ::scidb::test::actions_api::mwArgProc {}
} -result {pre-suf-board}

::tcltest::cleanupTests
return
