# ======================================================================
# ::application::assistant (pre-routing) -- a System One fast path for
# requests one default tool invocation fully performs.
#
# The assistant normally answers every request through the language
# model's tool loop. For the common, argument-free requests -- "explain
# this position", "switch to the database tab", "summarize the database"
# -- the routing decision is a bounded classification the System One
# classifier can make in one pass (~0.5 s locally) instead of a full
# language-model round (seconds on constrained hardware).
#
# Two gates, both must pass (JEV_USE_CASES.md §7, candidate A):
#   route      choice over the derived allowlist of default invocations
#              plus an existing_assistant sentinel; picking a relevant
#              tool is not enough --
#   satisfied  noul: the request names one simple action and contains no
#              specific values to extract ("show twenty continuations"
#              fails this gate even though position_moves is the right
#              tool).
#
# The allowlist is derived from the Actions table at call time -- never
# hard-coded: a tool qualifies when its JSON schema has no properties
# (a bare invocation), or all-optional properties (defaults), or exactly
# one required small-enum property (expanded into one invocation per
# value, e.g. switch_tab(board)). Debug-only and required-argument tools
# fall out of the schema rule by construction. No model or backend is
# named anywhere: the router uses ::ai::systemone with whatever backend
# the user configured, and is skipped entirely when it is off.
#
# Modes (SCIDB_AI_ROUTE, default "shadow"):
#   off      no classifier call; every request goes to the model
#   shadow   the classifier predicts and the prediction is logged against
#            what the model actually did (route-shadow.log next to the
#            error log); behaviour is unchanged -- this is the evaluation
#            data the thresholds are tuned on
#   active   a gated hit runs the tool directly (through runTool, so
#            CheckArgs, the confirm gate and the tool log all still run);
#            anything else -- sentinel, low confidence, timeout, error,
#            no server -- falls through to the model loop unchanged
#
# A watchdog (SCIDB_AI_ROUTE_TIMEOUT_MS, default 4000) bounds the active
# wait: the model loop starts without the classifier rather than let a
# slow server stall the request. Late predictions are still logged.
#
# Environment: SCIDB_AI_ROUTE, SCIDB_AI_ROUTE_MIN_CONFIDENCE (0.7),
# SCIDB_AI_ROUTE_MIN_SATISFIED (0.7), SCIDB_AI_ROUTE_TIMEOUT_MS (4000).
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source app-assistant-route
}

package require Tcl 8.5

namespace eval application {
namespace eval assistant {

variable RouteMode shadow
variable RouteThreshold 0.7
# Calibrated against plumb-4b on a 10-request battery (5 satisfied-by-
# default, 5 needing values or prose): positives >= 0.50, negatives <= 0.26
# with the instruction below; 0.4 keeps a margin on both sides. Other
# backends answer with different distributions -- retune via the env var,
# and watch route-shadow.log for the live numbers.
variable SatisfiedThreshold 0.4
variable RouteTimeout 4000

if {[info exists ::env(SCIDB_AI_ROUTE)]} {
	if {$::env(SCIDB_AI_ROUTE) in {off shadow active}} {
		set RouteMode $::env(SCIDB_AI_ROUTE)
	}
}
if {[info exists ::env(SCIDB_AI_ROUTE_MIN_CONFIDENCE)]
 && [string is double -strict $::env(SCIDB_AI_ROUTE_MIN_CONFIDENCE)]} {
	set RouteThreshold $::env(SCIDB_AI_ROUTE_MIN_CONFIDENCE)
}
if {[info exists ::env(SCIDB_AI_ROUTE_MIN_SATISFIED)]
 && [string is double -strict $::env(SCIDB_AI_ROUTE_MIN_SATISFIED)]} {
	set SatisfiedThreshold $::env(SCIDB_AI_ROUTE_MIN_SATISFIED)
}
if {[info exists ::env(SCIDB_AI_ROUTE_TIMEOUT_MS)]
 && [string is integer -strict $::env(SCIDB_AI_ROUTE_TIMEOUT_MS)]} {
	set RouteTimeout $::env(SCIDB_AI_ROUTE_TIMEOUT_MS)
}

# The sentinel option: "hand this to the language model".
variable RouteSentinel existing_assistant

} ;# namespace assistant
} ;# namespace application


# ----------------------------------------------------------------------
# The allowlist, derived from the Actions table.
# Returns a list of dicts {id name cargs description}; ids are
# "tool" for a bare invocation or "tool(value)" for an enum expansion.
# ----------------------------------------------------------------------
proc ::application::assistant::routeInvocations {} {
	variable Actions
	variable Priv
	variable RouteSentinel

	if {[catch { package require json }]} { return {} }

	set out {}
	dict for {name entry} $Actions {
		lassign $entry confirm debug what description parameters handler
		if {$debug} { continue }
		if {[catch { set schema [::json::json2dict $parameters] }]} { continue }
		set props [expr {[dict exists $schema properties] ? [dict get $schema properties] : {}}]
		set required [expr {[dict exists $schema required] ? [dict get $schema required] : {}}]

		if {[dict size $props] == 0} {
			# a bare invocation: no arguments at all
			lappend out [dict create id $name name $name cargs {} \
				description [string range $description 0 109]]
			continue
		}
		if {[llength $required] == 0} {
			# all arguments optional: the defaults must satisfy the
			# request, which the second gate decides
			lappend out [dict create id $name name $name cargs {} \
				description [string range "$description (with its default arguments)" 0 109]]
			continue
		}
		# exactly one required small enum: expand into one invocation
		# per value, so the classifier picks the destination directly
		if {[dict size $props] == 1 && [llength $required] == 1} {
			set prop [lindex $required 0]
			set def [dict get $props $prop]
			if {[dict exists $def enum] && [llength [dict get $def enum]] in {2 3 4}} {
				foreach value [dict get $def enum] {
					lappend out [dict create id "${name}($value)" name $name \
						cargs [dict create $prop $value] \
						description [string range "$description -- '$value'" 0 109]]
				}
				continue
			}
		}
		# required free-text arguments: the language model must extract
		# them; not fast-pathable
	}
	return $out
}


proc ::application::assistant::routeCriteria {invocations} {
	variable RouteSentinel

	set criteria {}
	foreach inv $invocations {
		dict set criteria [dict get $inv id] [dict get $inv description]
	}
	dict set criteria $RouteSentinel \
		"the request needs the language model: values to extract, several steps, a prose answer, or anything unclear"
	return $criteria
}


proc ::application::assistant::routeQuestions {criteria} {
	return [dict create \
		route [dict create type choice \
			instructions "Which single Scidb assistant action, run with its default arguments, would by itself perform this request?" \
			criteria $criteria] \
		satisfied [dict create type noul \
			instructions "Does this request name a single simple action and contain no specific values -- no names, no numbers, no paths, no search criteria?"] \
	]
}


proc ::application::assistant::routeState {request} {
	return "REQUEST:\n[string range $request 0 1999]"
}


# ----------------------------------------------------------------------
# The gate in front of Step. Called from ask in place of Step 0.
# ----------------------------------------------------------------------
proc ::application::assistant::RouteOrStep {request} {
	variable Priv
	variable RouteMode
	variable RouteTimeout

	if {$RouteMode eq "off"
	 || [llength [info commands ::ai::systemone::evaluateAsync]] == 0
	 || ![::ai::systemone::enabled]} {
		Step 0
		return
	}

	incr Priv(routeGen)
	set gen $Priv(routeGen)
	array unset Priv routePred,*
	array unset Priv routeActual,*
	set Priv(routeWait) 0

	if {[catch { set invocations [routeInvocations] }] || ![llength $invocations]} {
		Step 0
		return
	}
	set Priv(routeInvocations) $invocations

	# Arm the wait BEFORE asking: a fast (or synchronously failing) server
	# can answer inside evaluateAsync, and the reply must find the wait
	# already armed. The watchdog bounds the active wait; RouteTimeoutFired
	# no-ops once the reply consumed it.
	if {$RouteMode eq "active"} {
		set Priv(routeWait) $gen
		after $RouteTimeout [namespace code [list RouteTimeoutFired $gen]]
	}

	if {[catch {
		::ai::systemone::evaluateAsync [routeState $request] \
			[routeQuestions [routeCriteria $invocations]] \
			[namespace code [list OnRouted $gen $request]]
	}]} {
		set Priv(routeWait) 0 ;# the watchdog must not wait for a reply that never comes
		Step 0
		return
	}

	if {$RouteMode ne "active"} {
		# shadow: behaviour unchanged; the prediction is logged when it
		# arrives and compared with what the model does. (In active mode a
		# synchronous answer has already acted inside evaluateAsync.)
		Step 0
	}
	return
}


proc ::application::assistant::RouteTimeoutFired {gen} {
	variable Priv

	if {[expr {[info exists Priv(routeWait)] ? $Priv(routeWait) : 0}] != $gen} { return }
	set Priv(routeWait) 0
	Step 0
	return
}


# The classifier's answer, validated: {ok 1 id ID conf C sat S} or {ok 0}.
proc ::application::assistant::RouteDecision {result criteria} {
	variable RouteSentinel

	if {![dict get $result ok]} { return [dict create ok 0] }
	if {[catch {
		set answers [dict get $result answers]
		set route [dict get $answers route]
		set sat [dict get $answers satisfied]
		set id [dict get $route choice]
		set conf [dict get $route confidence]
		set p [dict get $sat noul]
	}]} {
		return [dict create ok 0]
	}
	# validate the shape: the label must be one we offered, the numbers
	# must be probabilities
	if {$id ni [dict keys $criteria] && $id ne $RouteSentinel} { return [dict create ok 0] }
	if {![string is double -strict $conf] || $conf < 0 || $conf > 1} { return [dict create ok 0] }
	if {![string is double -strict $p] || $p < 0 || $p > 1} { return [dict create ok 0] }
	return [dict create ok 1 id $id conf $conf sat $p]
}


proc ::application::assistant::OnRouted {gen request result} {
	variable Priv
	variable RouteMode
	variable RouteThreshold
	variable SatisfiedThreshold
	variable RouteSentinel

	if {![info exists Priv(routeGen)] || $gen != $Priv(routeGen)} { return } ;# stale

	set criteria [routeCriteria $Priv(routeInvocations)]
	set decision [RouteDecision $result $criteria]
	set Priv(routePred,$gen) $decision
	set Priv(routeRequest,$gen) $request
	TryLogRoute $gen

	# act only when this generation is still waiting for the classifier
	if {[expr {[info exists Priv(routeWait)] ? $Priv(routeWait) : 0}] != $gen} { return }
	set Priv(routeWait) 0
	if {$RouteMode ne "active"} { return }

	if {![dict get $decision ok] || [dict get $decision id] eq $RouteSentinel
	 || [dict get $decision conf] < $RouteThreshold
	 || [dict get $decision sat] < $SatisfiedThreshold} {
		Step 0
		return
	}

	set id [dict get $decision id]
	set inv [lsearch -inline -index 1 $Priv(routeInvocations) $id]
	if {![llength $inv]} { Step 0 ; return } ;# cannot happen: validated above
	DeliverRouted [dict get $inv name] [dict get $inv cargs] 1
	return
}


# ----------------------------------------------------------------------
# Delivery: the routed tool runs through the ordinary runTool path, so
# CheckArgs, the confirm gate and the tool log all behave exactly as for
# a model-called tool. The conversation history gets the same shape the
# model loop would have produced (assistant tool_calls, tool reply,
# assistant answer), so later rounds see a consistent transcript.
# ----------------------------------------------------------------------
proc ::application::assistant::RouteArgsJson {cargs} {
	if {![llength $cargs]} { return "\{\}" }
	return [::ai::provider::jsonObject $cargs]
}


proc ::application::assistant::DeliverRouted {name cargs round} {
	variable Priv

	lappend Priv(messages) [dict create role assistant content "" tool_calls \
		[list [dict create function [dict create name $name arguments [RouteArgsJson $cargs]]]]]

	set reply [runTool $name $cargs]
	if {[string match "\x00later:*" $reply]} {
		# an asynchronous handler: park exactly as RunCalls would, marked
		# so Resolve delivers the reply instead of re-entering the model
		Append tool "$name: (working...)"
		set Priv(pending) [list $reply $round $name $cargs {} 1]
		return
	}
	if {[string match "error:*" $reply]} {
		# a routed tool that fails is the model's chance to recover: keep
		# the protocol shape (assistant tool_calls, tool error) and fall
		# back to the ordinary loop
		lappend Priv(messages) [dict create role tool content $reply tool_name $name]
		Append tool "$name: $reply"
		Notify tool $name $reply
		Step 0
		return
	}
	DeliverRoutedReply $name $reply $round
	return
}


proc ::application::assistant::DeliverRoutedReply {name reply round} {
	variable Priv

	lappend Priv(messages) [dict create role tool content $reply tool_name $name]
	Notify tool $name $reply
	Finish [dict create ok 1 message [dict create role assistant content $reply]] $round
	return
}


# ----------------------------------------------------------------------
# The shadow log: one line per request once both the prediction and the
# model's actual first action are known.
# ----------------------------------------------------------------------

# Called from OnReplyImpl with the model's first-round action: a tool
# name, "prose", or "error".
proc ::application::assistant::RecordRouteActual {what} {
	variable Priv

	if {![info exists Priv(routeGen)]} { return }
	set gen $Priv(routeGen)
	if {[info exists Priv(routeActual,$gen)]} { return } ;# first action only
	set Priv(routeActual,$gen) $what
	TryLogRoute $gen
	return
}


proc ::application::assistant::TryLogRoute {gen} {
	variable Priv
	variable RouteMode

	if {![info exists Priv(routePred,$gen)] || ![info exists Priv(routeActual,$gen)]} { return }
	set pred $Priv(routePred,$gen)
	set actual $Priv(routeActual,$gen)
	set request [expr {[info exists Priv(routeRequest,$gen)] ? $Priv(routeRequest,$gen) : ""}]

	set predId [expr {[dict get $pred ok] ? [dict get $pred id] : "-"}]
	set predConf [expr {[dict get $pred ok] ? [format %.2f [dict get $pred conf]] : "-"}]
	set predSat [expr {[dict get $pred ok] ? [format %.2f [dict get $pred sat]] : "-"}]
	# the prediction matches when it names the tool the model actually
	# called (an enum expansion matches on its base tool name)
	set predName [expr {$predId eq "-" ? "-" : [lindex [split $predId (] 0]}]
	set match [expr {$predName eq $actual ? 1 : 0}]

	set line [format {%s | %s | pred=%s conf=%s sat=%s | actual=%s | match=%d | %s} \
		[clock format [clock seconds] -format {%Y-%m-%d %T}] \
		$RouteMode $predId $predConf $predSat $actual $match \
		[string map {\n { } \r { } \t { }} [string range $request 0 119]]]

	if {[catch { LogRouteLine $line }]} { ;# logging must never break a request
	}
	array unset Priv routePred,$gen
	array unset Priv routeActual,$gen
	array unset Priv routeRequest,$gen
	return
}


proc ::application::assistant::LogRouteLine {line} {
	variable ErrorLogFile

	if {![string length $ErrorLogFile]} { return }
	set dir [file dirname $ErrorLogFile]
	file mkdir $dir
	set file [file join $dir route-shadow.log]
	if {[file exists $file] && [file size $file] > 1048576} {
		catch { file delete -force $file.1 }
		catch { file rename $file $file.1 }
	}
	set chan [open $file a]
	fconfigure $chan -encoding utf-8
	puts $chan $line
	close $chan
	return
}

# vi:set ts=3 sw=3:
