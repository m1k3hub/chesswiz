# ======================================================================
# Scidb App Test — bounded operator and grounding predicates
# (VAL-AI-012, VAL-KNOW-008, tcl/app-assistant.tcl, tcl/app-assistant-route.tcl)
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

# 1. Grounding and possessive handling in UngroundedFacts
tcltest::test bounds-grounding-possessives {UngroundedFacts allows FactStop possessives and tool entity possessives} -body {
	set r1 [::application::assistant::UngroundedFacts "It is White's turn." "turn: White" "whose turn is it"]
	set r2 [::application::assistant::UngroundedFacts "It is Black's turn." "turn: Black" "whose turn is it"]
	set r3 [::application::assistant::UngroundedFacts "Erigaisi's score is 2750." "Erigaisi 2750" "show erigaisi"]
	list $r1 $r2 $r3
} -result {{} {} {}}

tcltest::test bounds-grounding-catches-unmentioned {UngroundedFacts catches names and numbers not in tool results} -body {
	set r1 [::application::assistant::UngroundedFacts "The player Kasparov won." "The player Carlsen won." "who won"]
	set r2 [::application::assistant::UngroundedFacts "The score is 3.5." "The score is 1.2." "eval"]
	list $r1 $r2
} -result {Kasparov 3.5}

# 2. Capability question recognition
tcltest::test route-capability-colloquial {RouteCapabilityQuestion recognizes colloquial capability queries} -body {
	list [::application::assistant::RouteCapabilityQuestion "what can u do"] \
	     [::application::assistant::RouteCapabilityQuestion "what can you do"] \
	     [::application::assistant::RouteCapabilityQuestion "how do I archive this"] \
	     [::application::assistant::RouteCapabilityQuestion "start a new game"]
} -result {1 1 1 0}

# 3. Safe routable actions vs excluded data-modifying commands
tcltest::test route-invocations-safe-actions {routeInvocations includes safe actions and excludes data-destructive tools} -body {
	set ids [lmap inv [::application::assistant::routeInvocations] { dict get $inv id }]
	list [expr {"start_engine" in $ids}] \
	     [expr {"export_database" in $ids}] \
	     [expr {"convert_database" in $ids}]
} -result {1 1 0}

tcltest::test bounds-decline-cannot-smuggle-facts {a decline uses registry suggestions instead of model additions} -setup {
	set savedPriv [array get ::application::assistant::Priv]
} -body {
	array set ::application::assistant::Priv {
		observer {} turnRefusal {} turnResults {} internalReplies {} resultFacts {} lastFacts {} prohibitedAnalysis 0 turnTools 1 lastRequest {send this game to a friend}
	}
	set expected [::application::assistant::BoundsDecline $::application::assistant::Priv(lastRequest)]
	::application::assistant::Finish [dict create ok 1 message [dict create content \
		{Chesswiz cannot do that. Run invented_mail_action to send a PDF to Alice, rated 2999.}]] 1
	set actual [dict get [lindex $::application::assistant::Priv(messages) end] content]
	list [expr {$actual eq $expected}] [string match *invented_mail_action* $actual]
} -cleanup {
	array unset ::application::assistant::Priv
	array set ::application::assistant::Priv $savedPriv
} -result {1 0}

tcltest::test bounds-finish-preserves-chesswiz-cant-refusal {Finish turns "Chesswiz can't..." into BoundsDecline even when related tools ran} -setup {
	set savedPriv [array get ::application::assistant::Priv]
} -body {
	array set ::application::assistant::Priv {
		observer {} turnRefusal {} turnResults {} internalReplies {} resultFacts {} lastFacts {} prohibitedAnalysis 0 turnTools 2 lastRequest {Send the PGN to my phone.}
		messages {}
	}
	set expected [::application::assistant::BoundsDecline $::application::assistant::Priv(lastRequest)]
	::application::assistant::Finish [dict create ok 1 message [dict create content \
		"Chesswiz can't send anything to a phone itself, but I opened the export dialog."]] 1
	set actual [dict get [lindex $::application::assistant::Priv(messages) end] content]
	expr {$actual eq $expected}
} -cleanup {
	array unset ::application::assistant::Priv
	array set ::application::assistant::Priv $savedPriv
} -result 1

tcltest::test bounds-model-decline-before-tools {a reply declining with a proposed tool call cannot run it or substitute existing facts} -setup {
 set savedPriv [array get ::application::assistant::Priv]
} -body {
 array set ::application::assistant::Priv {
  observer {} turnTools 1 turnResults {} internalReplies {} prohibitedAnalysis 0 turnRefusal {} lastRequest {Perform an unsupported operation.}
  messages {{role user content {Perform an unsupported operation.}} {role tool content {related data: 17} tool_name database_info}}
  nudged 0 continued 0 resultFacts {} lastFacts {related data: 17}
 }
 set expected [::application::assistant::BoundsDecline $::application::assistant::Priv(lastRequest)]
 ::application::assistant::OnReplyImpl 0 [dict create ok 1 message [dict create \
   content {I cannot perform that operation, but here is a related action:} \
   tool_calls [list [dict create function [dict create name unknown_must_not_run arguments {}]]]]]
 set actual [dict get [lindex $::application::assistant::Priv(messages) end] content]
 list [expr {$actual eq $expected}] $::application::assistant::Priv(turnTools) $::application::assistant::Priv(nudged)
} -cleanup {
 array unset ::application::assistant::Priv
 array set ::application::assistant::Priv $savedPriv
} -result {1 1 0}

# Amendment e permits read-only discovery before a model-authored decline.
# Count execution independently of telemetry; action dispatch is forbidden.
tcltest::test bounds-lookup-then-model-decline {an in-scope turn can discover capabilities then decline without actions or substituted data} -setup {
 source [file join [file dirname [info script]] app_wait.tcl]
 ::scidb::test::wait::ready
 ::application::assistant::show
 set savedPriv [array get ::application::assistant::Priv]
 set savedAI [array get ::application::ai::Config]
 set savedProvider [array get ::ai::provider::Config]
 set savedRoute $::application::assistant::RouteMode
 set savedS1 [array get ::ai::systemone::Config]
 set ::application::assistant::RouteMode active
 ::ai::systemone::configure -backend plumb
 rename ::ai::systemone::evaluateAsync ::boundsRealEvaluate
 proc ::ai::systemone::evaluateAsync {state questions script} {
  uplevel #0 [list {*}$script [dict create ok 1 answers [dict create \
   route [dict create choice existing_assistant confidence 1] \
   refusal [dict create choice in_bounds confidence 1]]]]
 }
 set ::application::ai::Config(provider) stub
 set ::boundsLookupCalls 0
 set ::boundsActionCalls 0
 proc ::boundsObserveAction {args} {incr ::boundsActionCalls}
 trace add execution ::action::run enter ::boundsObserveAction
 proc ::boundsObserveLookup {args} {incr ::boundsLookupCalls}
 trace add execution ::knowledge::FindCapability enter ::boundsObserveLookup
} -body {
 ::application::assistant::clear
 ::ai::provider::configure -name stub -chatResponses [list \
  [dict create role assistant content {} tool_calls [list [dict create function [dict create name find_capability arguments [dict create request {Show sharing options for this game.}]]]]] \
  [dict create role assistant content {Chesswiz cannot send this game to a phone. Related data: 987654.}]]
 ::application::assistant::ask {Show sharing options for this game.}
 if {$::application::assistant::Priv(busy)} {vwait ::application::assistant::Priv(busy)}
 set text [dict get [lindex $::application::assistant::Priv(messages) end] content]
 list $::boundsLookupCalls $::boundsActionCalls $::application::assistant::Priv(turnTools) \
  [expr {$text eq [::application::assistant::BoundsDecline {Show sharing options for this game.}]}] \
  [string match *987654* $text]
} -cleanup {
 trace remove execution ::knowledge::FindCapability enter ::boundsObserveLookup
 rename ::boundsObserveLookup {}
 trace remove execution ::action::run enter ::boundsObserveAction
 rename ::boundsObserveAction {}
 unset ::boundsLookupCalls ::boundsActionCalls
 array unset ::application::assistant::Priv
 array set ::application::assistant::Priv $savedPriv
 array unset ::application::ai::Config
 array set ::application::ai::Config $savedAI
 array unset ::ai::provider::Config
 array set ::ai::provider::Config $savedProvider
 rename ::ai::systemone::evaluateAsync {}
 rename ::boundsRealEvaluate ::ai::systemone::evaluateAsync
 array unset ::ai::systemone::Config
 array set ::ai::systemone::Config $savedS1
 set ::application::assistant::RouteMode $savedRoute
} -result {1 0 1 1 0}

tcltest::test bounds-typed-refusal-zero-tools {a typed refusal prevents the queued model lookup and every action} -setup {
 source [file join [file dirname [info script]] app_wait.tcl]
 ::scidb::test::wait::ready
 ::application::assistant::show
 set savedPriv [array get ::application::assistant::Priv]
 set savedAI [array get ::application::ai::Config]
 set savedProvider [array get ::ai::provider::Config]
 set savedRoute $::application::assistant::RouteMode
 set savedS1 [array get ::ai::systemone::Config]
 set ::application::assistant::RouteMode active
 ::ai::systemone::configure -backend plumb
 rename ::ai::systemone::evaluateAsync ::boundsRealEvaluate
 proc ::ai::systemone::evaluateAsync {state questions script} {
  uplevel #0 [list {*}$script [dict create ok 1 answers [dict create \
   route [dict create choice existing_assistant confidence 1] \
   refusal [dict create choice unsupported_feature confidence 1]]]]
 }
 set ::application::ai::Config(provider) stub
 set ::boundsLookupCalls 0
 set ::boundsActionCalls 0
 proc ::boundsObserveAction {args} {incr ::boundsActionCalls}
 trace add execution ::action::run enter ::boundsObserveAction
 proc ::boundsObserveLookup {args} {incr ::boundsLookupCalls}
 trace add execution ::knowledge::FindCapability enter ::boundsObserveLookup
} -body {
 ::application::assistant::clear
 ::ai::provider::configure -name stub -chatResponses [list \
  [dict create role assistant content {} tool_calls [list [dict create function [dict create name find_capability arguments [dict create request {Show sharing options for this game.}]]]]] \
  [dict create role assistant content {Chesswiz cannot send this game to a phone. Related data: 987654.}]]
 ::application::assistant::ask {Show sharing options for this game.}
 if {$::application::assistant::Priv(busy)} {vwait ::application::assistant::Priv(busy)}
 set text [dict get [lindex $::application::assistant::Priv(messages) end] content]
 list $::boundsLookupCalls $::boundsActionCalls $::application::assistant::Priv(turnTools) \
  [expr {$text eq [::application::assistant::BoundsDecline {Show sharing options for this game.}]}] \
  [string match *987654* $text]
} -cleanup {
 trace remove execution ::knowledge::FindCapability enter ::boundsObserveLookup
 rename ::boundsObserveLookup {}
 trace remove execution ::action::run enter ::boundsObserveAction
 rename ::boundsObserveAction {}
 unset ::boundsLookupCalls ::boundsActionCalls
 array unset ::application::assistant::Priv
 array set ::application::assistant::Priv $savedPriv
 array unset ::application::ai::Config
 array set ::application::ai::Config $savedAI
 array unset ::ai::provider::Config
 array set ::ai::provider::Config $savedProvider
 rename ::ai::systemone::evaluateAsync {}
 rename ::boundsRealEvaluate ::ai::systemone::evaluateAsync
 array unset ::ai::systemone::Config
 array set ::ai::systemone::Config $savedS1
 set ::application::assistant::RouteMode $savedRoute
} -result {0 0 0 1 0}

tcltest::test bounds-plan-decline-needs-user-decision {a model cannot invent user cancellation after discovery or without tools} -setup {
 set savedPriv [array get ::application::assistant::Priv]
} -body {
 set results {}
 foreach toolCount {0 1} {
  array set ::application::assistant::Priv {
   observer {} turnRefusal {} turnResults {} internalReplies {} resultFacts {} lastFacts {} prohibitedAnalysis 0
   lastRequest {Perform an unsupported operation} userDeclinedPlan 0
   messages {}
  }
  set ::application::assistant::Priv(turnTools) $toolCount
  set expected [::application::assistant::BoundsDecline $::application::assistant::Priv(lastRequest)]
  ::application::assistant::Finish [dict create ok 1 message [dict create content $::application::assistant::mc::PlanDeclined]] 1
  lappend results [expr {[dict get [lindex $::application::assistant::Priv(messages) end] content] eq $expected}]
 }
 set ::application::assistant::Priv(userDeclinedPlan) 1
 lappend results [::application::assistant::NoToolReplyAllowed $::application::assistant::mc::PlanDeclined]
 set results
} -cleanup {
 array unset ::application::assistant::Priv
 array set ::application::assistant::Priv $savedPriv
} -result {1 1 1}

tcltest::cleanupTests
