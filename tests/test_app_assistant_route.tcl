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
proc ::scidb::test::route::reply {id conf sat {probs {}}} {
	if {![dict size $probs]} {
		set probs [dict create $id $conf]
	}
	dict create ok 1 answers [dict create \
		route [dict create type choice choice $id confidence $conf \
			probabilities $probs] \
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

	# flush startup events (the app schedules Startup2/switchTab/tips at
	# startup) before the recorder replaces the real procs
	catch { update }

	::application::assistant::show
	if {[llength [info commands ::application::assistant::CancelRouteTimer]]} {
		::application::assistant::CancelRouteTimer
	}
	set ::application::assistant::Priv(routeWait) 0
	set ::application::assistant::Priv(routeClarify) {}
	::application::assistant::SetBusy 0
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

	if {[llength [info commands ::application::assistant::CancelRouteTimer]]} {
		::application::assistant::CancelRouteTimer
	}
	set ::application::assistant::Priv(routeWait) 0
	set ::application::assistant::Priv(routeClarify) {}
	::application::assistant::SetBusy 0
	catch { rename ::application::switchTab {} }
	catch { rename ::scidb::test::route::realSwitchTab ::application::switchTab }
	::scidb::test::route::uninstall
	set ::application::assistant::RouteMode $mode
	array set ::ai::systemone::Config $s1
	set ::application::assistant::Priv(confirm) $confirm
	set ::application::assistant::Priv(messages) $messages
	set ::application::assistant::Priv(pending) $pending
	set ::application::assistant::ErrorLogFile $errlog
	if {$rc} { return -code error $result }
	return $result
}

proc ::scidb::test::route::waitBusy {{timeoutMs 2000}} {
	if {!$::application::assistant::Priv(busy)} { return }
	set timer [after $timeoutMs { set ::scidb::test::route::WaitDone timeout }]
	trace add variable ::application::assistant::Priv(busy) write ::scidb::test::route::onBusyWrite
	try {
		while {$::application::assistant::Priv(busy)} {
			vwait ::scidb::test::route::WaitDone
			if {$::scidb::test::route::WaitDone eq "timeout"} {
				break
			}
		}
	} finally {
		catch { after cancel $timer }
		catch { trace remove variable ::application::assistant::Priv(busy) write ::scidb::test::route::onBusyWrite }
		unset -nocomplain ::scidb::test::route::WaitDone
	}
	return
}

proc ::scidb::test::route::onBusyWrite {args} {
	if {!$::application::assistant::Priv(busy)} {
		set ::scidb::test::route::WaitDone ok
	}
}

proc ::scidb::test::route::ask {request {timeoutMs 2000}} {
	::application::assistant::ask $request
	::scidb::test::route::waitBusy $timeoutMs
	return [$::application::assistant::Priv(text) get 1.0 end-1c]
}

# Create a tiny executable UCI stub script in $Dir that speaks the UCI
# handshake and returns a deterministic evaluation for any position.
proc ::scidb::test::route::makeFakeUciEngine {} {
	file mkdir $::scidb::test::route::Dir
	set exe [file join $::scidb::test::route::Dir fake_uci_engine.sh]
	set log [file join $::scidb::test::route::Dir fake_uci_engine.log]
	file delete -force $log
	set ch [open $exe w]
	puts $ch "#!/bin/sh"
	puts $ch "LOG=[list $log]"
	puts $ch {while IFS= read -r line; do}
	puts $ch {  printf '%s\n' "$line" >> "$LOG"}
	puts $ch {  case "$line" in}
	puts $ch {    uci)}
	puts $ch {      printf 'id name StubStockfish\nuciok\n'}
	puts $ch {      ;;}
	puts $ch {    isready)}
	puts $ch {      printf 'readyok\n'}
	puts $ch {      ;;}
	puts $ch {    go*)}
	puts $ch {      printf 'info depth 18 multipv 1 score cp 35 pv e2e4 e7e5\n'}
	puts $ch {      printf 'info depth 18 multipv 2 score cp 20 pv d2d4 d7d5\n'}
	puts $ch {      printf 'bestmove e2e4\n'}
	puts $ch {      ;;}
	puts $ch {    quit)}
	puts $ch {      exit 0}
	puts $ch {      ;;}
	puts $ch {  esac}
	puts $ch {done}
	close $ch
	file attributes $exe -permissions 0755
	return [list $exe $log]
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
		set ::scidb::test::route::RouteReply [::scidb::test::route::reply install_chessbase_fonts 0.95 0.95]
		set transcript [::scidb::test::route::ask "install the ChessBase fonts"]
		list $::scidb::test::route::Asked $::scidb::test::route::ChatCalls \
			[string match {*NOT performed*} $transcript]
	}
} -result {{{install the ChessBase fonts}} 0 1}

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

# ----------------------------------------------------------------------
# VAL-AI-003: Timeout, ambiguity, clarification execution, offline engine,
#             watchdog idle behavior, and async races
# ----------------------------------------------------------------------

tcltest::test route-active-timeout {classifier timeout falls back to the model} -body {
	::scidb::test::route::isolated {
		set ::application::assistant::RouteMode active
		set savedTimeout $::application::assistant::RouteTimeout
		set ::application::assistant::RouteTimeout 50

		# Make the classifier hang (never reply)
		rename ::ai::systemone::evaluateAsync {}
		proc ::ai::systemone::evaluateAsync {state questions script} {
			incr ::scidb::test::route::EvalCalls
			return
		}

		::scidb::test::route::ask "switch to the database tab" 1000

		set ::application::assistant::RouteTimeout $savedTimeout
		list $::scidb::test::route::ChatCalls $::scidb::test::route::Switched \
			$::application::assistant::Priv(busy)
	}
} -result {1 {} 0}

tcltest::test route-watchdog-no-idle-monopoly {watchdog uses a timer and never monopolizes update idletasks} -body {
	::scidb::test::route::isolated {
		set ::application::assistant::RouteMode active
		set savedTimeout $::application::assistant::RouteTimeout
		set ::application::assistant::RouteTimeout 400

		rename ::ai::systemone::evaluateAsync {}
		proc ::ai::systemone::evaluateAsync {state questions script} {
			set ::scidb::test::route::PendingCallback $script
			return
		}

		::application::assistant::ask "switch to the database tab"
		set t0 [clock milliseconds]
		update idletasks
		set elapsed [expr {[clock milliseconds] - $t0}]
		set stillWaiting [expr {$::application::assistant::Priv(routeWait) != 0}]
		set chatBeforeTimeout $::scidb::test::route::ChatCalls

		# Deliver the reply normally before the 400ms timer expires
		uplevel #0 [list {*}$::scidb::test::route::PendingCallback \
			[::scidb::test::route::reply switch_tab(database) 0.95 0.95]]
		::scidb::test::route::waitBusy 500

		set ::application::assistant::RouteTimeout $savedTimeout
		unset -nocomplain ::scidb::test::route::PendingCallback
		list [expr {$elapsed < 100}] $stillWaiting $chatBeforeTimeout \
			$::scidb::test::route::Switched $::scidb::test::route::ChatCalls \
			$::application::assistant::Priv(busy)
	}
} -result {1 1 0 database 0 0}

tcltest::test route-ambiguous-clarifies {ambiguous request asks clarifying question instead of falling back} -body {
	::scidb::test::route::isolated {
		set ::application::assistant::RouteMode active

		# Simulate ambiguous response matching several actions with no clear winner
		set ::scidb::test::route::RouteReply [::scidb::test::route::reply switch_tab(board) 0.48 0.9 \
			[dict create switch_tab(board) 0.48 switch_tab(database) 0.42]]

		set transcript [::scidb::test::route::ask "show me something"]

		# Must ask a clarifying question listing the candidate actions,
		# without running a tool or falling back to the language model.
		set askedQuestion [string match {*Which did you mean:*\?*} $transcript]
		set namesBoard [string match {*switch_tab(board)*} $transcript]
		set namesDatabase [string match {*switch_tab(database)*} $transcript]

		list $::scidb::test::route::ChatCalls $::scidb::test::route::Switched \
			$askedQuestion $namesBoard $namesDatabase
	}
} -result {0 {} 1 1 1}

tcltest::test route-ambiguous-followup-runs-choice {choosing a clarification candidate by name or ordinal executes it once} -body {
	::scidb::test::route::isolated {
		set ::application::assistant::RouteMode active

		# Turn 1: ambiguous between board and database tabs
		set ::scidb::test::route::RouteReply [::scidb::test::route::reply switch_tab(board) 0.48 0.9 \
			[dict create switch_tab(board) 0.48 switch_tab(database) 0.42]]
		::scidb::test::route::ask "switch tab"

		# Turn 2: user replies "the second one" -> executes switch_tab(database)
		# without calling the classifier or the language model
		set evalBefore $::scidb::test::route::EvalCalls
		set transcript [::scidb::test::route::ask "the second one"]
		set afterOrdinal [list $::scidb::test::route::Switched \
			[expr {$::scidb::test::route::EvalCalls - $evalBefore}] \
			$::scidb::test::route::ChatCalls \
			[dict size $::application::assistant::Priv(routeClarify)]]

		# Repeat two-turn flow, this time selecting by name ("board")
		set ::scidb::test::route::Switched {}
		set ::scidb::test::route::RouteReply [::scidb::test::route::reply switch_tab(board) 0.46 0.9 \
			[dict create switch_tab(board) 0.46 switch_tab(database) 0.41]]
		::scidb::test::route::ask "switch tab"
		set evalBefore2 $::scidb::test::route::EvalCalls
		::scidb::test::route::ask "board"
		set afterNamed [list $::scidb::test::route::Switched \
			[expr {$::scidb::test::route::EvalCalls - $evalBefore2}] \
			$::scidb::test::route::ChatCalls \
			[dict size $::application::assistant::Priv(routeClarify)]]

		# Unrelated follow-up clears pending clarification and routes normally
		set ::scidb::test::route::Switched {}
		set ::scidb::test::route::RouteReply [::scidb::test::route::reply switch_tab(board) 0.46 0.9 \
			[dict create switch_tab(board) 0.46 switch_tab(database) 0.41]]
		::scidb::test::route::ask "switch tab"
		set ::scidb::test::route::RouteReply [::scidb::test::route::reply existing_assistant 0.99 0.99]
		::scidb::test::route::ask "what do you think of the Caro-Kann?"
		set afterUnrelated [list $::scidb::test::route::Switched \
			$::scidb::test::route::ChatCalls \
			[dict size $::application::assistant::Priv(routeClarify)]]

		# Conversation reset (clear) also clears pending clarification
		set ::scidb::test::route::RouteReply [::scidb::test::route::reply switch_tab(board) 0.46 0.9 \
			[dict create switch_tab(board) 0.46 switch_tab(database) 0.41]]
		::scidb::test::route::ask "switch tab"
		set pendingBeforeClear [expr {[dict size $::application::assistant::Priv(routeClarify)] > 0}]
		::application::assistant::clear
		set pendingAfterClear [dict size $::application::assistant::Priv(routeClarify)]

		list $afterOrdinal $afterNamed $afterUnrelated [list $pendingBeforeClear $pendingAfterClear]
	}
} -result {{database 0 0 0} {board 0 0 0} {{} 1 0} {1 0}}

tcltest::test route-lowconf-clear-lead-abstains {low confidence with a clear winner abstains to the model instead of clarifying} -body {
	::scidb::test::route::isolated {
		set ::application::assistant::RouteMode active

		# Top candidate is below minConf (0.65 < 0.70), but leads runner-up by 0.50:
		# must fall back to the model, never ask a clarifying question or invent candidates.
		set ::scidb::test::route::RouteReply [::scidb::test::route::reply switch_tab(board) 0.65 0.9 \
			[dict create switch_tab(board) 0.65 switch_tab(database) 0.15]]
		set t1 [::scidb::test::route::ask "maybe the board"]
		set r1 [list $::scidb::test::route::ChatCalls $::scidb::test::route::Switched \
			[string match {*Which did you mean:*} $t1]]

		# Single candidate with moderate confidence and low satisfied score (no runner-up):
		# must also fall back to the model, never manufacture sibling/fallback candidates.
		set ::scidb::test::route::RouteReply [::scidb::test::route::reply switch_tab(board) 0.58 0.25 \
			[dict create switch_tab(board) 0.58]]
		set t2 [::scidb::test::route::ask "switch to the board and show 20 moves"]
		set r2 [list $::scidb::test::route::ChatCalls $::scidb::test::route::Switched \
			[string match {*Which did you mean:*} $t2]]

		list $r1 $r2
	}
} -result {{1 {} 0} {2 {} 0}}

tcltest::test route-chess-judgment-stays-with-engine {chess position evaluation uses engine offline without calling model or classifier} -body {
	::scidb::test::route::isolated {
		set ::application::assistant::RouteMode active
		set savedEngine [array get ::ai::engine::Config]
		lassign [::scidb::test::route::makeFakeUciEngine] fakeExe fakeLog
		::ai::engine::kill
		::ai::engine::configure -engine $fakeExe

		# Make network / classifier and LLM services completely unavailable
		::ai::systemone::configure -backend off
		rename ::ai::systemone::evaluateAsync {}
		proc ::ai::systemone::evaluateAsync {state questions script} {
			incr ::scidb::test::route::EvalCalls
			error "network classifier unavailable offline"
		}
		rename ::ai::provider::chatAsync {}
		proc ::ai::provider::chatAsync {messages tools script} {
			incr ::scidb::test::route::ChatCalls
			uplevel #0 [list {*}$script [dict create ok 0 down 1 error "network LLM unavailable offline"]]
		}

		set transcript [::scidb::test::route::ask "what's the best move here?"]
		set engineRan [file exists $fakeLog]
		set engineLog ""
		if {$engineRan} {
			set ch [open $fakeLog]
			set engineLog [read $ch]
			close $ch
		}
		::ai::engine::kill
		array set ::ai::engine::Config $savedEngine
		file delete -force $::scidb::test::route::Dir

		list $::scidb::test::route::ChatCalls \
			$::scidb::test::route::EvalCalls \
			[llength $::scidb::test::route::Switched] \
			$engineRan \
			[string match {*go depth*} $engineLog] \
			[string match {*+0.35*1.e4 e5*} $transcript]
	}
} -result {0 0 0 1 1 1}

tcltest::test route-async-races {late replies after timeout, duplicate callbacks, and stale replies across requests} -body {
	::scidb::test::route::isolated {
		set ::application::assistant::RouteMode active
		set savedTimeout $::application::assistant::RouteTimeout

		# 1. Late reply arriving after timeout fallback has already completed:
		#    must not execute the tool or complete a second time.
		set ::application::assistant::RouteTimeout 40
		set ::scidb::test::route::Callbacks {}
		rename ::ai::systemone::evaluateAsync {}
		proc ::ai::systemone::evaluateAsync {state questions script} {
			incr ::scidb::test::route::EvalCalls
			lappend ::scidb::test::route::Callbacks $script
			return
		}
		::scidb::test::route::ask "switch to the database tab" 500
		set afterTimeout [list $::scidb::test::route::ChatCalls $::scidb::test::route::Switched]
		set lateCb [lindex $::scidb::test::route::Callbacks 0]
		uplevel #0 [list {*}$lateCb [::scidb::test::route::reply switch_tab(database) 0.99 0.99]]
		set afterLate [list $::scidb::test::route::ChatCalls $::scidb::test::route::Switched]

		# 2. Duplicate callback invocation for the same request:
		#    action runs once and model is not called.
		set ::application::assistant::RouteTimeout 1000
		set ::scidb::test::route::Callbacks {}
		set ::scidb::test::route::Switched {}
		set ::scidb::test::route::ChatCalls 0
		::application::assistant::ask "switch to the board tab"
		set cb2 [lindex $::scidb::test::route::Callbacks 0]
		uplevel #0 [list {*}$cb2 [::scidb::test::route::reply switch_tab(board) 0.95 0.95]]
		uplevel #0 [list {*}$cb2 [::scidb::test::route::reply switch_tab(database) 0.95 0.95]]
		::scidb::test::route::waitBusy 500
		set afterDup [list $::scidb::test::route::Switched $::scidb::test::route::ChatCalls]

		# 3. Stale reply from request A arriving while request B is in flight:
		#    must be ignored and leave request B's state intact until B's callback fires.
		set ::scidb::test::route::Callbacks {}
		set ::scidb::test::route::Switched {}
		set ::scidb::test::route::ChatCalls 0
		set ::application::assistant::RouteTimeout 40
		::scidb::test::route::ask "first request times out" 500
		set staleCbA [lindex $::scidb::test::route::Callbacks 0]

		set ::application::assistant::RouteTimeout 1000
		set ::scidb::test::route::ChatCalls 0
		::application::assistant::ask "switch to the database tab"
		set activeCbB [lindex $::scidb::test::route::Callbacks 1]
		set genB $::application::assistant::Priv(routeGen)

		# Deliver stale callback A while B is waiting
		uplevel #0 [list {*}$staleCbA [::scidb::test::route::reply switch_tab(board) 0.99 0.99]]
		set bStillWaiting [list \
			[expr {$::application::assistant::Priv(routeWait) == $genB}] \
			$::application::assistant::Priv(busy) \
			$::scidb::test::route::Switched]

		# Now deliver B's own callback
		uplevel #0 [list {*}$activeCbB [::scidb::test::route::reply switch_tab(database) 0.95 0.95]]
		::scidb::test::route::waitBusy 500
		set afterB [list $::scidb::test::route::Switched $::scidb::test::route::ChatCalls \
			$::application::assistant::Priv(busy)]

		set ::application::assistant::RouteTimeout $savedTimeout
		unset -nocomplain ::scidb::test::route::Callbacks
		list $afterTimeout $afterLate $afterDup $bStillWaiting $afterB
	}
} -result {{1 {}} {1 {}} {board 0} {1 1 {}} {database 0 0}}

tcltest::test route-chess-judgment-requested-position {chess judgment with moves or FEN evaluates the requested position without changing the board, and abstains on unresolvable context} -body {
	::scidb::test::route::isolated {
		set ::application::assistant::RouteMode active
		set savedEngine [array get ::ai::engine::Config]
		lassign [::scidb::test::route::makeFakeUciEngine] fakeExe fakeLog
		::ai::engine::kill
		::ai::engine::configure -engine $fakeExe

		# Put a known starting position on the user's board and verify it never changes
		set boardFenBefore [::scidb::pos::fen]

		# 1. "what is the best move after 1.e4 e5?" must evaluate the position
		#    after 1.e4 e5 (rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2),
		#    not the current starting board, and must not change the user's board.
		set transcript1 [::scidb::test::route::ask "what is the best move after 1.e4 e5?"]
		set boardFenAfter1 [::scidb::pos::fen]
		set ch [open $fakeLog]
		set log1 [read $ch]
		close $ch
		file delete -force $fakeLog

		# 1b. Annotated moves keep the whole line (1.e4! e5? is still after e5).
		::scidb::test::route::ask "what is the best move after 1.e4! e5?"
		set ch [open $fakeLog]
		set log1b [read $ch]
		close $ch
		file delete -force $fakeLog

		# 2. "is Nf3 a blunder after 1.d4 d5?" must pass the post-1.d4 d5 FEN to engine_check_move
		set transcript2 [::scidb::test::route::ask "is Nf3 a blunder after 1.d4 d5?"]
		set boardFenAfter2 [::scidb::pos::fen]
		set ch [open $fakeLog]
		set log2 [read $ch]
		close $ch
		file delete -force $fakeLog

		# 3. Unresolvable context ("what is the best move in game 3 move 12?") and
		#    negated requests ("do not evaluate this position, switch to the database tab")
		#    must NOT evaluate the wrong position on the current board.
		set ::scidb::test::route::ChatCalls 0
		set ::scidb::test::route::RouteReply [::scidb::test::route::reply existing_assistant 0.99 0.99]
		::scidb::test::route::ask "what is the best move in game 3 at move 12?"
		set engineRanOnGameRef [file exists $fakeLog]
		set chatAfterGameRef $::scidb::test::route::ChatCalls

		set ::scidb::test::route::RouteReply [::scidb::test::route::reply switch_tab(database) 0.95 0.95]
		::scidb::test::route::ask "do not evaluate this position, switch to the database tab"
		set engineRanOnNegated [file exists $fakeLog]

		::ai::engine::kill
		array set ::ai::engine::Config $savedEngine
		file delete -force $::scidb::test::route::Dir

		list \
			[string match {*position fen rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq * 0 2*} $log1] \
			[expr {$boardFenAfter1 eq $boardFenBefore}] \
			[string match {*position fen rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq * 0 2*} $log1b] \
			[string match {*position fen rnbqkbnr/ppp1pppp/8/3p4/3P4/8/PPP1PPPP/RNBQKBNR w KQkq * 0 2*} $log2] \
			[expr {$boardFenAfter2 eq $boardFenBefore}] \
			$engineRanOnGameRef $chatAfterGameRef \
			$engineRanOnNegated $::scidb::test::route::Switched
	}
} -result {1 1 1 1 1 0 1 0 database}

tcltest::test route-clarify-negated-unresolved {negated or uncertain clarification replies do not select the named candidate} -body {
	::scidb::test::route::isolated {
		set ::application::assistant::RouteMode active

		foreach reply {"not board" "neither" "maybe board" "don't switch to board" "board?"} {
			set ::scidb::test::route::Switched {}
			set ::scidb::test::route::ChatCalls 0
			set ::scidb::test::route::RouteReply [::scidb::test::route::reply switch_tab(board) 0.48 0.9 \
				[dict create switch_tab(board) 0.48 switch_tab(database) 0.42]]
			::scidb::test::route::ask "switch tab"

			# Reply with negated/uncertain text; classifier routes the follow-up to the model
			set ::scidb::test::route::RouteReply [::scidb::test::route::reply existing_assistant 0.99 0.99]
			::scidb::test::route::ask $reply
			lappend results [list $::scidb::test::route::Switched $::scidb::test::route::ChatCalls]
		}
		set results
	}
} -result {{{} 1} {{} 1} {{} 1} {{} 1} {{} 1}}

tcltest::cleanupTests