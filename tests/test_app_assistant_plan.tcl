# ======================================================================
# Scidb App Test - a multi-call reply is one plan (VAL-AI-002)
# ======================================================================
# The provider is stubbed, so no model and no network are involved. A
# reply with several tool calls is shown as one numbered plan, confirmed
# once when any step is confirm/bulk, and then run in order. Declining
# runs no handler; a modal step pauses the chain; an asynchronous (Later)
# step is awaited; a failure keeps the effects of the steps before it and
# stops the chain; too many rounds stops with a plain message.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::plan {
	variable Ran {}
	variable Times {}
	variable ConfirmAsked {}
	variable ConfirmAnswer 1
	variable Events {}
	variable ChatCalls 0
	variable Queue {}
	variable AlwaysCall {}
	variable FailAt ""
	variable DialogAt ""
	variable LaterAt ""
}

proc ::scidb::test::plan::yes {} { return 1 }
proc ::scidb::test::plan::no {} { return 0 }

proc ::scidb::test::plan::confirm {what} {
	lappend ::scidb::test::plan::ConfirmAsked $what
	return $::scidb::test::plan::ConfirmAnswer
}

proc ::scidb::test::plan::observe {tag args} {
	lappend ::scidb::test::plan::Events [list $tag {*}$args]
	return
}

proc ::scidb::test::plan::step {name args} {
	variable Ran
	variable Times
	variable FailAt
	variable DialogAt
	variable LaterAt

	lappend Ran $name
	lappend Times [clock milliseconds]
	if {$FailAt eq $name} { error "step $name exploded" }
	if {$DialogAt eq $name} {
		toplevel .planDialog
		after 150 [list destroy .planDialog]
	}
	if {$LaterAt eq $name} {
		set token [::application::assistant::Later]
		after 150 [list ::application::assistant::Resolve $token "late result for $name"]
		return $token
	}
	return "ok $name"
}

proc ::scidb::test::plan::action {id name opts} {
	set record [dict merge [dict create \
		label    "Plan Step $name" \
		object   {} \
		handler  [list ::scidb::test::plan::step $name] \
		what     "" \
		doc      "" \
		args     {} \
		schema   {}] $opts]
	::action::register $id $record
	return $id
}

proc ::scidb::test::plan::forget {args} {
	foreach id $args { catch { dict unset ::action::Registry $id } }
}

proc ::scidb::test::plan::cleanupRegistry {} {
	foreach id [dict keys $::action::Registry] {
		if {[string match "test.plan.*" $id]} {
			catch { dict unset ::action::Registry $id }
		}
	}
}

proc ::scidb::test::plan::call {name {id 0}} {
	return [dict create id "call_[incr id]" type function \
		function [dict create name $name arguments {}]]
}

proc ::scidb::test::plan::calls {names} {
	set out {}
	set i 0
	foreach name $names { lappend out [::scidb::test::plan::call $name $i]; incr i }
	return $out
}

proc ::scidb::test::plan::reply {calls} {
	return [dict create ok 1 message [dict create role assistant content "" tool_calls $calls]]
}

proc ::scidb::test::plan::prose {text} {
	return [dict create ok 1 message [dict create role assistant content $text]]
}

proc ::scidb::test::plan::install {} {
	rename ::ai::provider::chatAsync ::scidb::test::plan::realChatAsync
	proc ::ai::provider::chatAsync {messages tools script} {
		incr ::scidb::test::plan::ChatCalls
		if {$::scidb::test::plan::AlwaysCall ne ""} {
			set result $::scidb::test::plan::AlwaysCall
		} elseif {[llength $::scidb::test::plan::Queue]} {
			set q $::scidb::test::plan::Queue
			set result [lindex $q 0]
			set ::scidb::test::plan::Queue [lrange $q 1 end]
		} else {
			set result [::scidb::test::plan::prose "done"]
		}
		uplevel #0 [list {*}$script $result]
	}
}

proc ::scidb::test::plan::uninstall {} {
	catch { rename ::ai::provider::chatAsync {} }
	catch { rename ::scidb::test::plan::realChatAsync ::ai::provider::chatAsync }
}

# Wait until the request has finished (no busy flag), pumping events.
proc ::scidb::test::plan::wait {{ms 10000}} {
	set start [clock milliseconds]
	while {[set ::application::assistant::Priv(busy)]} {
		update
		if {[clock milliseconds] - $start > $ms} { return 0 }
		after 10
	}
	update
	return 1
}

proc ::scidb::test::plan::isolated {body} {
	variable Ran {}
	variable Times {}
	variable ConfirmAsked {}
	variable ConfirmAnswer 1
	variable Events {}
	variable ChatCalls 0
	variable Queue {}
	variable AlwaysCall {}
	variable FailAt ""
	variable DialogAt ""
	variable LaterAt ""

	set routeMode $::application::assistant::RouteMode
	set route [array get ::application::assistant::Priv]
	set bulk $::action::BulkHook
	set gate $::action::PlanGate

	set ::application::assistant::RouteMode off
	::application::assistant::show
	if {[llength [info commands ::application::assistant::CancelRouteTimer]]} {
		::application::assistant::CancelRouteTimer
	}
	set ::application::assistant::Priv(busy) 0
	set ::application::assistant::Priv(messages) {}
	set ::application::assistant::Priv(pending) {}
	set ::application::assistant::Priv(plan) {}
	set ::application::assistant::Priv(planConfirmed) 0
	set ::application::assistant::Priv(observer) {}
	set ::application::assistant::Priv(reqconfirm) {}
	set ::action::PlanGate 0
	::scidb::test::plan::cleanupRegistry
	::scidb::test::plan::install

	set rc [catch { uplevel 1 $body } result]

	::scidb::test::plan::uninstall
	::scidb::test::plan::cleanupRegistry
	set ::application::assistant::RouteMode $routeMode
	array set ::application::assistant::Priv $route
	set ::action::BulkHook $bulk
	set ::action::PlanGate $gate
	catch { update }
	if {$rc} { return -code error $result }
	return $result
}

proc ::scidb::test::plan::Run {text} {
	::application::assistant::ask $text \
		-confirm ::scidb::test::plan::confirm \
		-observer ::scidb::test::plan::observe
	return [::scidb::test::plan::wait]
}

# The message the pane/observer saw for a tag, or "".
proc ::scidb::test::plan::event {tag} {
	set out ""
	foreach event $::scidb::test::plan::Events {
		if {[lindex $event 0] eq $tag} { set out [lindex $event 1] }
	}
	return $out
}

# Tool replies recorded in the conversation.
proc ::scidb::test::plan::toolReplies {} {
	set out {}
	foreach msg $::application::assistant::Priv(messages) {
		if {[dict get $msg role] eq "tool"} { lappend out [dict get $msg content] }
	}
	return $out
}

# ----------------------------------------------------------------------
# One plan, one confirmation, steps in order.
# ----------------------------------------------------------------------
tcltest::test plan-accept-runs-all-steps {three calls run in order after one confirmation} -body {
	::scidb::test::plan::isolated {
		::scidb::test::plan::action test.plan.one one {}
		::scidb::test::plan::action test.plan.two two [dict create confirm 1 what "do step two"]
		::scidb::test::plan::action test.plan.three three {}
		set ::scidb::test::plan::Queue [list \
			[::scidb::test::plan::reply [::scidb::test::plan::calls \
				{test.plan.one test.plan.two test.plan.three}]] \
			[::scidb::test::plan::prose "ok three"]]
		set ::scidb::test::plan::ConfirmAnswer 1
		set done [::scidb::test::plan::Run "run the three steps"]
		set plan [::scidb::test::plan::event plan]
		set result [list $done \
			$::scidb::test::plan::Ran \
			[llength $::scidb::test::plan::ConfirmAsked] \
			$::scidb::test::plan::ChatCalls \
			[::scidb::test::plan::event reply] \
			[string match {*1. Plan Step one*} $plan] \
			[string match {*3. Plan Step three*} $plan] \
			$::application::assistant::Priv(planConfirmed) \
			$::action::PlanGate]
		::scidb::test::plan::forget test.plan.one test.plan.two test.plan.three
		set result
	}
} -result {1 {one two three} 1 2 {ok one
ok two
ok three} 1 1 0 0}

tcltest::test plan-decline-runs-nothing {declining the plan runs no handler} -body {
	::scidb::test::plan::isolated {
		::scidb::test::plan::action test.plan.one one {}
		::scidb::test::plan::action test.plan.two two [dict create confirm 1 what "do step two"]
		set ::scidb::test::plan::Queue [list \
			[::scidb::test::plan::reply [::scidb::test::plan::calls \
				{test.plan.one test.plan.two}]]]
		set ::scidb::test::plan::ConfirmAnswer 0
		set done [::scidb::test::plan::Run "run the two steps"]
		set result [list $done [llength $::scidb::test::plan::Ran] \
			[llength $::scidb::test::plan::ConfirmAsked] \
			[::scidb::test::plan::event reply] $::action::PlanGate]
		::scidb::test::plan::forget test.plan.one test.plan.two
		set result
	}
} -result {1 0 1 {Nothing was run: the plan was declined.} 0}

tcltest::test plan-single-call-is-not-a-plan {one tool call keeps the ordinary path} -body {
	::scidb::test::plan::isolated {
		::scidb::test::plan::action test.plan.only only {}
		set ::scidb::test::plan::Queue [list \
			[::scidb::test::plan::reply [::scidb::test::plan::calls {test.plan.only}]] \
			[::scidb::test::plan::prose "one done"]]
		set done [::scidb::test::plan::Run "run one step"]
		set result [list $done $::scidb::test::plan::Ran \
			[llength $::scidb::test::plan::ConfirmAsked] \
			[::scidb::test::plan::event plan]]
		::scidb::test::plan::forget test.plan.only
		set result
	}
} -result {1 only 0 {}}

# ----------------------------------------------------------------------
# Failure keeps earlier effects and stops the chain.
# ----------------------------------------------------------------------
tcltest::test plan-failure-stops-the-chain {a failing step keeps the earlier effects and skips the rest} -body {
	::scidb::test::plan::isolated {
		::scidb::test::plan::action test.plan.one one {}
		::scidb::test::plan::action test.plan.bad bad {}
		::scidb::test::plan::action test.plan.three three {}
		set ::scidb::test::plan::FailAt bad
		set ::scidb::test::plan::Queue [list \
			[::scidb::test::plan::reply [::scidb::test::plan::calls \
				{test.plan.one test.plan.bad test.plan.three}]]]
		set done [::scidb::test::plan::Run "run the three steps"]
		set skipped 0
		foreach reply [::scidb::test::plan::toolReplies] {
			if {[string match {*plan stopped at an earlier step*} $reply]} { incr skipped }
		}
		set result [list $done $::scidb::test::plan::Ran \
			[string match {*Stopped at step 2*} [::scidb::test::plan::event error]] \
			$skipped $::action::PlanGate \
            [string match {*remaining step could not be completed*} [dict get [lindex $::application::assistant::Priv(messages) end] content]]]
		::scidb::test::plan::forget test.plan.one test.plan.bad test.plan.three
		set result
	}
} -result {1 {one bad} 1 1 0 1}

# ----------------------------------------------------------------------
# A step that ends in a dialog pauses the chain until it closes.
# ----------------------------------------------------------------------
tcltest::test plan-modal-step-pauses {the next step waits for the dialog of the previous one} -body {
	::scidb::test::plan::isolated {
		::scidb::test::plan::action test.plan.dlg dlg [dict create ends-in-dialog 1]
		::scidb::test::plan::action test.plan.after after {}
		set ::scidb::test::plan::DialogAt dlg
		set ::scidb::test::plan::Queue [list \
			[::scidb::test::plan::reply [::scidb::test::plan::calls \
				{test.plan.dlg test.plan.after}]] \
			[::scidb::test::plan::prose "dialog done"]]
		set done [::scidb::test::plan::Run "run the dialog steps"]
		set gap [expr {[lindex $::scidb::test::plan::Times 1] - [lindex $::scidb::test::plan::Times 0]}]
		set result [list $done $::scidb::test::plan::Ran [expr {$gap >= 100}]]
		::scidb::test::plan::forget test.plan.dlg test.plan.after
		set result
	}
} -result {1 {dlg after} 1}

# ----------------------------------------------------------------------
# An asynchronous (Later) step is awaited before the next step.
# ----------------------------------------------------------------------
tcltest::test plan-async-step-is-awaited {a Later step parks the chain until Resolve} -body {
	::scidb::test::plan::isolated {
		::scidb::test::plan::action test.plan.slow slow {}
		::scidb::test::plan::action test.plan.next next {}
		set ::scidb::test::plan::LaterAt slow
		set ::scidb::test::plan::Queue [list \
			[::scidb::test::plan::reply [::scidb::test::plan::calls \
				{test.plan.slow test.plan.next}]] \
			[::scidb::test::plan::prose "late result for slow"]]
		set done [::scidb::test::plan::Run "run the async steps"]
		set gap [expr {[lindex $::scidb::test::plan::Times 1] - [lindex $::scidb::test::plan::Times 0]}]
		set result [list $done $::scidb::test::plan::Ran [expr {$gap >= 100}] \
			[::scidb::test::plan::event reply]]
		::scidb::test::plan::forget test.plan.slow test.plan.next
		set result
	}
} -result {1 {slow next} 1 {late result for slow
ok next}}

# ----------------------------------------------------------------------
# Too many rounds.
# ----------------------------------------------------------------------
tcltest::test plan-too-many-rounds {the round limit stops with a plain message} -body {
	::scidb::test::plan::isolated {
		::scidb::test::plan::action test.plan.again again {}
		set ::scidb::test::plan::AlwaysCall \
			[::scidb::test::plan::reply [::scidb::test::plan::calls {test.plan.again}]]
		set done [::scidb::test::plan::Run "loop forever"]
		set result [list $done $::scidb::test::plan::ChatCalls \
			[llength $::scidb::test::plan::Ran] \
			[string match {*more steps than the assistant allows*} [::scidb::test::plan::event error]]]
		::scidb::test::plan::forget test.plan.again
		set result
	}
} -result {1 8 8 1}

tcltest::test plan-withdrawn-window-does-not-pause {a hidden utility window cannot park the next tool} -body {
	set before [::application::assistant::PlanWindows]
	toplevel .planHidden
	wm withdraw .planHidden
	set ::scidb::test::plan::HiddenExpired 0
	set timer [after 200 {
		set ::scidb::test::plan::HiddenExpired 1
		destroy .planHidden
	}]
	::application::assistant::PlanWaitForDialog $before
	set result [list $::scidb::test::plan::HiddenExpired [winfo exists .planHidden]]
	after cancel $timer
	catch {destroy .planHidden}
	set result
} -result {0 1}

tcltest::cleanupTests
