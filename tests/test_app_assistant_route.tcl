# ======================================================================
# Scidb App Test — assistant tool pre-routing (tcl/app-assistant-route.tcl)
# ======================================================================
# The System One classifier and the provider are both stubbed in-process:
# the routing decision is scripted, the language-model loop is counted.
# No network, no model. Every test restores the state it touched.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::route {
	variable ChatCalls 0
	variable EvalCalls 0
	variable ChatQueue {}
	variable RouteReply {}
	variable Asked {}
	variable Answer 1
	variable Switched {}
	variable Dir [file join [file dirname [file normalize [info script]]] tmp-app route_[pid]]
}

proc ::scidb::test::route::install {} {
	variable ChatCalls 0
	variable EvalCalls 0
	variable ChatQueue {}

	rename ::ai::provider::chatAsync ::scidb::test::route::realChatAsync
	proc ::ai::provider::chatAsync {messages tools script} {
		incr ::scidb::test::route::ChatCalls
		set first [dict create ok 1 message [dict create role assistant content "model answered"]]
		if {[llength $::scidb::test::route::ChatQueue]} {
			set ChatQueueCopy $::scidb::test::route::ChatQueue
			set first [lindex $ChatQueueCopy 0]
			set ::scidb::test::route::ChatQueue [lrange $ChatQueueCopy 1 end]
		}
		uplevel #0 [list {*}$script $first]
	}

	rename ::ai::systemone::evaluateAsync ::scidb::test::route::realEvalAsync
	proc ::ai::systemone::evaluateAsync {state questions script} {
		incr ::scidb::test::route::EvalCalls
		uplevel #0 [list {*}$script $::scidb::test::route::RouteReply]
	}
}

proc ::scidb::test::route::uninstall {} {
	catch { rename ::ai::provider::chatAsync {} }
	catch { rename ::scidb::test::route::realChatAsync ::ai::provider::chatAsync }
	catch { rename ::ai::systemone::evaluateAsync {} }
	catch { rename ::scidb::test::route::realEvalAsync ::ai::systemone::evaluateAsync }
}

# A classifier reply: route <id> at <conf>, satisfied-noul at <sat>.
proc ::scidb::test::route::reply {id conf sat} {
	dict create ok 1 answers [dict create \
		route [dict create type choice choice $id confidence $conf \
			probabilities [dict create $id $conf]] \
		satisfied [dict create type noul noul $sat confidence $sat]]
}

proc ::scidb::test::route::confirm {what} {
	variable Asked
	variable Answer
	lappend Asked $what
	return $Answer
}

# Run <body> with routing state, confirm hook, stubs and the error log
# restored.
proc ::scidb::test::route::isolated {body} {
	set mode $::application::assistant::RouteMode
	set s1 [array get ::ai::systemone::Config]
	set confirm $::application::assistant::Priv(confirm)
	set messages $::application::assistant::Priv(messages)
	set errlog $::application::assistant::ErrorLogFile
	set pending $::application::assistant::Priv(pending)
	variable Asked {}
	variable Answer 1
	variable Switched {}

	# flush startup after-idle events (the app schedules switchTab/tips at
	# startup) before the recorder replaces the real procs
	catch { update idletasks }

	::application::assistant::show
	set ::application::assistant::Priv(confirm) ::scidb::test::route::confirm
	set ::application::assistant::Priv(messages) {}
	::ai::systemone::configure -backend plumb
	::scidb::test::route::install

	# record switch_tab without touching the real UI
	rename ::application::switchTab ::scidb::test::route::realSwitchTab
	proc ::application::switchTab {tab} {
		lappend ::scidb::test::route::Switched $tab
		return
	}

	set rc [catch { uplevel 1 $body } result]

	catch { rename ::application::switchTab {} }
	catch { rename ::scidb::test::route::realSwitchTab ::application::switchTab }
	::scidb::test::route::uninstall
	set ::application::assistant::RouteMode $mode
	array set ::ai::systemone::Config $s1
	set ::application::assistant::Priv(confirm) $confirm
	set ::application::assistant::Priv(messages) $messages
	set ::application::assistant::Priv(pending) $pending
	set ::application::assistant::ErrorLogFile $errlog
	set ::application::assistant::Priv(routeWait) 0
	if {$rc} { return -code error $result }
	return $result
}

proc ::scidb::test::route::ask {request} {
	::application::assistant::ask $request
	set n 0
	while {$::application::assistant::Priv(busy) && $n < 200} {
		update
		incr n
	}
	return [$::application::assistant::Priv(text) get 1.0 end-1c]
}

# ----------------------------------------------------------------------

tcltest::test route-invocations {the allowlist is derived from the Actions table} -body {
	::scidb::test::route::isolated {
		set ids [lmap inv [::application::assistant::routeInvocations] { dict get $inv id }]
		set missing {}
		foreach want {explain_position database_summary current_game new_game
		              position_moves switch_tab(board) switch_tab(database)
		              open_search(advanced) open_search(material) open_search(rating)} {
			if {$want ni $ids} { lappend missing $want }
		}
		set leaked {}
		# start_engine is routable since its engine is optional (the default
		# engine), like every all-optional tool
		foreach unwanted {open_database player_stats prepare_against
		                  handoff_issue eval_tcl list_procs read_variable proc_source} {
			if {[lsearch -exact $ids $unwanted] >= 0} { lappend leaked $unwanted }
		}
		# the enum expansion carries its argument
		set invs [::application::assistant::routeInvocations]
		set idx [lsearch -exact [lmap i $invs { dict get $i id }] switch_tab(board)]
		set inv [lindex $invs $idx]
		list $missing $leaked [dict get $inv cargs]
	}
} -result {{} {} {tab board}}

tcltest::test route-active-hit {a gated hit runs the tool without the model} -body {
	::scidb::test::route::isolated {
		set ::application::assistant::RouteMode active
		set ::scidb::test::route::RouteReply [::scidb::test::route::reply switch_tab(database) 0.93 0.95]
		set transcript [::scidb::test::route::ask "switch to the database tab"]
		set msgs $::application::assistant::Priv(messages)
		list $::scidb::test::route::Switched $::scidb::test::route::ChatCalls \
			$::scidb::test::route::EvalCalls \
			[string match {*switched to the database tab*} $transcript] \
			[lmap m $msgs { dict get $m role }]
	}
} -result {database 0 1 1 {system user assistant tool assistant}}

tcltest::test route-active-lowconf {a low-confidence route falls through to the model} -body {
	::scidb::test::route::isolated {
		set ::application::assistant::RouteMode active
		set ::scidb::test::route::RouteReply [::scidb::test::route::reply switch_tab(database) 0.4 0.9]
		::scidb::test::route::ask "switch to the database tab"
		list $::scidb::test::route::Switched $::scidb::test::route::ChatCalls
	}
} -result {{} 1}

tcltest::test route-active-sentinel {the sentinel routes to the model} -body {
	::scidb::test::route::isolated {
		set ::application::assistant::RouteMode active
		set ::scidb::test::route::RouteReply [::scidb::test::route::reply existing_assistant 0.99 0.99]
		::scidb::test::route::ask "what do you think of the Sicilian?"
		list $::scidb::test::route::Switched $::scidb::test::route::ChatCalls
	}
} -result {{} 1}

tcltest::test route-active-unsatisfied {a request needing arguments fails the second gate} -body {
	::scidb::test::route::isolated {
		set ::application::assistant::RouteMode active
		set ::scidb::test::route::RouteReply [::scidb::test::route::reply position_moves 0.9 0.2]
		::scidb::test::route::ask "show twenty continuations here"
		list $::scidb::test::route::ChatCalls
	}
} -result {1}

tcltest::test route-active-mutating-confirms {a routed mutating tool still asks the user} -body {
	::scidb::test::route::isolated {
		set ::application::assistant::RouteMode active
		set ::scidb::test::route::Answer 0 ;# decline
		set ::scidb::test::route::RouteReply [::scidb::test::route::reply new_game 0.95 0.95]
		set transcript [::scidb::test::route::ask "start a new game"]
		list $::scidb::test::route::Asked $::scidb::test::route::ChatCalls \
			[string match {*NOT performed*} $transcript]
	}
} -result {{{start a new game}} 0 1}

tcltest::test route-active-error-falls-back {a failing routed tool hands the request to the model} -body {
	::scidb::test::route::isolated {
		set ::application::assistant::RouteMode active
		proc ::application::switchTab {tab} { error "boom" }
		set ::scidb::test::route::RouteReply [::scidb::test::route::reply switch_tab(board) 0.95 0.95]
		::scidb::test::route::ask "switch to the board tab"
		list $::scidb::test::route::ChatCalls
	}
} -result {1}

tcltest::test route-active-history {a routed call keeps its arguments as a dict, as the model's calls do} -body {
	::scidb::test::route::isolated {
		set ::application::assistant::RouteMode active
		set ::scidb::test::route::RouteReply [::scidb::test::route::reply switch_tab(database) 0.93 0.95]
		::scidb::test::route::ask "switch to the database tab"
		set call [lindex [dict get [lindex $::application::assistant::Priv(messages) 2] tool_calls] 0]
		set args [dict get $call function arguments]
		list $args [::ai::provider::jsonObject $args]
	}
} -result {{tab database} {{"tab":"database"}}}

tcltest::test route-active-logs {a routed run is logged, marked as the router's} -body {
	::scidb::test::route::isolated {
		set ::application::assistant::RouteMode active
		file mkdir $::scidb::test::route::Dir
		set ::application::assistant::ErrorLogFile [file join $::scidb::test::route::Dir errors.log]
		file delete -force [file join $::scidb::test::route::Dir route-shadow.log]
		set ::scidb::test::route::RouteReply [::scidb::test::route::reply switch_tab(database) 0.93 0.95]
		::scidb::test::route::ask "switch to the database tab"
		set ch [open [file join $::scidb::test::route::Dir route-shadow.log]]
		set line [string trim [read $ch]]
		close $ch
		list $::scidb::test::route::ChatCalls [string match {*| active | pred=switch_tab(database)*actual=switch_tab routed | match=1 |*} $line]
	}
} -result {0 1}

tcltest::test route-auto-mode {auto routes actively only with a backend calibrated for the router} -body {
	::scidb::test::route::isolated {
		set saved $::ai::systemone::Thresholds
		set ::application::assistant::RouteMode auto
		set before [::application::assistant::EffectiveRouteMode]
		dict set ::ai::systemone::Thresholds route plumb 0.6
		dict set ::ai::systemone::Thresholds route_satisfied plumb 0.67
		set after [::application::assistant::EffectiveRouteMode]
		set thresholds [::application::assistant::RouteThresholds]
		set ::ai::systemone::Thresholds $saved
		list $before $after $thresholds
	}
} -result {shadow active {0.6 0.67}}

tcltest::test route-shadow-logs {shadow mode runs the model and logs the comparison} -body {
	::scidb::test::route::isolated {
		set ::application::assistant::RouteMode shadow
		file mkdir $::scidb::test::route::Dir
		set ::application::assistant::ErrorLogFile [file join $::scidb::test::route::Dir errors.log]
		file delete -force [file join $::scidb::test::route::Dir route-shadow.log]
		# the model calls switch_tab itself; the prediction agrees
		set call [dict create ok 1 message [dict create role assistant content "" tool_calls \
			[list [dict create function [dict create name switch_tab arguments {tab database}]]]]]
		set ::scidb::test::route::ChatQueue [list $call]
		set ::scidb::test::route::RouteReply [::scidb::test::route::reply switch_tab(database) 0.9 0.9]
		::scidb::test::route::ask "switch to the database tab"
		set log [file join $::scidb::test::route::Dir route-shadow.log]
		set ch [open $log]
		set lines [split [string trim [read $ch]] \n]
		close $ch
		list $::scidb::test::route::ChatCalls $::scidb::test::route::Switched \
			[llength $lines] \
			[string match {*pred=switch_tab(database)*} [lindex $lines 0]] \
			[string match {*actual=switch_tab*} [lindex $lines 0]] \
			[string match {*match=1*} [lindex $lines 0]]
	}
} -cleanup {
	file delete -force $::scidb::test::route::Dir
} -result {2 database 1 1 1 1}

tcltest::test route-off {off mode never calls the classifier} -body {
	::scidb::test::route::isolated {
		set ::application::assistant::RouteMode off
		set ::scidb::test::route::RouteReply [::scidb::test::route::reply switch_tab(database) 0.99 0.99]
		::scidb::test::route::ask "switch to the database tab"
		list $::scidb::test::route::EvalCalls $::scidb::test::route::ChatCalls $::scidb::test::route::Switched
	}
} -result {0 1 {}}

tcltest::test route-disabled-classifier {no configured classifier means the model loop, unchanged} -body {
	::scidb::test::route::isolated {
		set ::application::assistant::RouteMode active
		::ai::systemone::configure -backend off
		set ::scidb::test::route::RouteReply [::scidb::test::route::reply switch_tab(database) 0.99 0.99]
		::scidb::test::route::ask "switch to the database tab"
		list $::scidb::test::route::EvalCalls $::scidb::test::route::ChatCalls
	}
} -result {0 1}

tcltest::test route-malformed-abstains {a malformed classifier reply falls through to the model} -body {
	::scidb::test::route::isolated {
		set ::application::assistant::RouteMode active
		# a route label that was not offered
		set ::scidb::test::route::RouteReply [::scidb::test::route::reply drop_database 0.99 0.99]
		::scidb::test::route::ask "switch to the database tab"
		list $::scidb::test::route::ChatCalls $::scidb::test::route::Switched
	}
} -result {1 {}}

tcltest::cleanupTests