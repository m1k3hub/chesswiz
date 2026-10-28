package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
::scidb::test::actions::ready
namespace eval ::c17 {}

tcltest::test c17-query-outcomes {direct and generic data tools never authorize a state-changing receipt} -setup {
 set saved [array get ::application::assistant::Priv]
} -body {
 set ::application::assistant::Priv(busy) 1
 set ::application::assistant::Priv(turnResults) {}
 foreach id {list_open_databases database_summary player_stats opening_score list_engines} {
  ::application::assistant::RecordToolOutcome $id ok {unrelated data 123 /tmp/database} {}
  ::application::assistant::RecordToolOutcome run_action ok {unrelated data 123 /tmp/database} [dict create id $id]
 }
 ::application::assistant::RecordToolOutcome run_action ok {running 0} {id menu.training.engine_match arguments {operation status}}
 set ::application::assistant::Priv(turnResults)
} -cleanup {
 array unset ::application::assistant::Priv
 array set ::application::assistant::Priv $saved
} -result {}

tcltest::test c17-inspection-defaults {omitted inspection operations and getter fields remain read-only; explicit setters still change state} -body {
 set out {}
 foreach {id arguments} {
  files.bookmark {} files.picker {} database.description {} toolbar.configure {}
  browser.display {position 9} gamebar.display {} board3d.theme {} board.display {}
  notation.display {} tournament.table {}
 } {lappend out [expr {![::action::changesState $id $arguments]}]}
 foreach {id arguments} {
  files.bookmark {operation add} files.picker {widget .picker operation directory}
  database.description {description {}} toolbar.configure {toolbar .bar state show}
  browser.display {position 9 columns 1} gamebar.display {alignment left}
  board3d.theme {name wood} board.display {promoted star} notation.display {columns 1}
  tournament.table {operation configure padding 3}
 } {lappend out [::action::changesState $id $arguments]}
 list [llength $out] [lsort -unique $out]
} -result {20 1}

tcltest::test c17-readonly-final {real direct and generic read-only calls end in a data-free decline for uncovered facts} -setup {
 set savedPriv [array get ::application::assistant::Priv]
 set savedAI [array get ::application::ai::Config]
 set savedProvider [array get ::ai::provider::Config]
 set savedRoute $::application::assistant::RouteMode
 set ::application::assistant::RouteMode off
 set ::application::ai::Config(provider) stub
 rename ::ai::systemone::chooseManySync ::c17::coverage
 proc ::ai::systemone::chooseManySync {args} {
  if {$::c17::coverage eq "abstain"} {return {}}
  return {coverage missing}
 }
} -body {
 set out {}
 foreach coverage {missing abstain} {
 set ::c17::coverage $coverage
 foreach wrapped {0 1} {
  foreach id {list_open_databases database_summary files.picker files.bookmark} {
   ::application::assistant::clear
   set request {What is the current rating of Generated Player?}
   set name $id
   set arguments {}
   if {$wrapped} {set name run_action;set arguments [dict create id $id]}
   ::ai::provider::configure -name stub -chatResponses [list \
    [dict create role assistant content {} tool_calls [list [dict create function [dict create name $name arguments $arguments]]]] \
    [dict create role assistant content {Here are the available database statistics.}]]
   ::application::assistant::ask $request
   if {$::application::assistant::Priv(busy)} {vwait ::application::assistant::Priv(busy)}
   set final [dict get [lindex $::application::assistant::Priv(messages) end] content]
   lappend out [expr {$final eq [::application::assistant::BoundsDecline $request] && [::application::assistant::ExecutedReply] eq ""}]
  }
 }
 }
 set out
} -cleanup {
 rename ::ai::systemone::chooseManySync {}
 rename ::c17::coverage ::ai::systemone::chooseManySync
 array unset ::application::assistant::Priv
 array set ::application::assistant::Priv $savedPriv
 array unset ::application::ai::Config
 array set ::application::ai::Config $savedAI
 array unset ::ai::provider::Config
 array set ::ai::provider::Config $savedProvider
 set ::application::assistant::RouteMode $savedRoute
} -result {1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1}

tcltest::test c17-fullscreen {exit is discoverable and explicit off is idempotent through the registry} -body {
 set ids {}
 foreach cap [::knowledge::Search {exit fullscreen} 5] {lappend ids [dict get $cap id]}
 ::menu::setFullscreen 1
 ::action::run app-fullscreen {state off}
 update
 after 100 {set ::c17::settled 1};vwait ::c17::settled
 update
 set first [::menu::fullscreen?]
 ::action::run app-fullscreen {state off}
 update
 list [expr {"app-fullscreen" in $ids}] $first [::menu::fullscreen?]
} -cleanup {::menu::setFullscreen 0} -result {1 0 0}

tcltest::test c17-open-trainers {explicit open requests show the actual match and repertoire dialogs} -body {
 set a [::action::run menu.training.engine_match {operation open}]
 set b [::action::run menu.training.repertoire {operation open}]
 update
 puts [list DIALOGS $a $b]
 list [winfo viewable .application.enginematch] [winfo viewable .application.__reptrainer__]
} -cleanup {
 catch {::enginematch::Close}
 catch {::reptrainer::Close .application.__reptrainer__}
} -result {1 1}

tcltest::test c17-match-bad-engines {invalid engine arrays return a typed validation error without opening a dialog or claiming a slot} -body {
 lassign [::action::validateArgs menu.training.engine_match {operation start engines {Missing, Other}}] kind why
 set args [lindex [::action::validateArgs menu.training.engine_match {operation open}] 1]
 dict set args operation start
 dict set args engines {Missing, Other}
 catch {::menu::ValidateMatchArgs $args} message options
 list $kind [string match {*unknown configured UCI engine*} $why] [dict get $options -errorcode] [winfo exists .application.enginematch]
} -result {error 1 {CHESSWIZ ARGUMENT engines} 0}

tcltest::test c17-no-slot {exhaustion returns a typed precondition error and leaves a visible setup dialog without taking a game} -setup {
 set engines $::engine::Engines
 set ::engine::Engines [list [dict merge $::engine::EmptyEngine {Name {Generated A} Protocol UCI Command /bin/true}] [dict merge $::engine::EmptyEngine {Name {Generated B} Protocol UCI Command /bin/true}]]
 rename ::enginematch::ClaimSlot ::c17::claim
 proc ::enginematch::ClaimSlot {} {return -1}
 set slot [::scidb::game::current]
 set fen [::scidb::pos::fen]
} -body {
 set result [::action::run menu.training.engine_match {operation start engines {{Generated A} {Generated B}}}]
 update
 list [string match {error: *no free game slot*} $result] [winfo viewable .application.enginematch] $::enginematch::Priv(running) [expr {[::scidb::game::current] == $slot && [::scidb::pos::fen] eq $fen}]
} -cleanup {
 rename ::enginematch::ClaimSlot {}
 rename ::c17::claim ::enginematch::ClaimSlot
 set ::engine::Engines $engines
 catch {::enginematch::Close}
} -result {1 1 0 1}

tcltest::test c17-slot {claiming a new match slot may reuse an unused empty game and never mistakes it for exhaustion} -body {
 set ::enginematch::Priv(pos) -1
 set pos [::enginematch::ClaimSlot]
 list [expr {$pos >= 0}] [expr {$pos == [::scidb::game::current]}] [::scidb::game::query $pos length]
} -result {1 1 0}

tcltest::test c17-observer {generic handler traces work inside action namespace despite list shadowing} -setup {
 namespace eval ::EvalHarness {variable Active 1;variable Attempt 1}
 namespace eval ::BoundsEval {variable Item observer}
 set oldWork [expr {[info exists ::env(SCIDB_EVAL_WORK)] ? $::env(SCIDB_EVAL_WORK) : ""}]
 set ::env(SCIDB_EVAL_WORK) [file join $::tcltest::temporaryDirectory c17-observer]
 file mkdir $::env(SCIDB_EVAL_WORK)
 source [file join [file dirname [info script]] eval_handler_observer.tcl]
} -body {
 ::action::run board-flip {}
 set seen 0
 foreach event $::EvalObserve::Events {
  if {[dict get $event kind] eq "registry-handler" && [dict get $event name] eq "board-flip"} {incr seen}
 }
 set seen
} -cleanup {
 trace remove execution ::action::Dispatch enterstep ::EvalObserve::DispatchStep
 trace remove execution ::application::assistant::ToolReply enter ::EvalObserve::ToolEnter
 set ::EvalHarness::Active 0
 ::action::run board-flip {}
 file delete -force $::env(SCIDB_EVAL_WORK)
 if {$oldWork eq ""} {unset ::env(SCIDB_EVAL_WORK)} else {set ::env(SCIDB_EVAL_WORK) $oldWork}
} -result 1

tcltest::cleanupTests
