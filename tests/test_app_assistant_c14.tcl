package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
::scidb::test::actions::ready
namespace eval ::c14 {}
tcltest::test c14-default-context {an omitted selection uses the same current object as capability availability} -setup {
 rename ::context::Invoke ::c14::invoke
 proc ::context::Invoke {id object} {return [list $id $object]}
} -body {
 set results {}
 foreach id {c9.float c9.maximise c9.fold c9.amalgamate c9.close c9.docking c9.stay_on_top c9.hide_leaving} {
  set selected [::context::CurrentObjectFor $id]
  set got [::context::InvokeArgs $id [dict create object {}]]
  lappend results [expr {[lindex $got 1] eq [lindex $selected 1]}]
 }
 lsort -unique $results
} -cleanup {
 rename ::context::Invoke {}
 rename ::c14::invoke ::context::Invoke
} -result 1

tcltest::test c14-missing-pane-details {every direct pane operation refuses incomplete objects with named missing fields} -body {
 set results {}
 foreach id {c9.float c9.maximise c9.fold c9.amalgamate c9.close c9.docking c9.stay_on_top c9.hide_leaving} {
  lappend results [string match {error: precondition:*} [::context::Invoke $id [dict create parent .application]]]
 }
 lsort -unique $results
} -result 1

tcltest::test c14-fact-type {related read-only results never replace the bounded decline for a missing fact} -setup {
 set saved [array get ::application::assistant::Priv]
 rename ::ai::systemone::chooseManySync ::c14::choose
 proc ::ai::systemone::chooseManySync {feature state questions args} {
  set ::c14::state $state
  if {$::c14::coverage eq "abstain"} {return {}}
  return [dict create coverage $::c14::coverage]
 }
} -body {
 set out {}
 foreach {request result} {
  {What is Alpha's rating?} {player Alpha; games 12; wins 5}
  {How many Sicilian games did Alpha play?} {database games 200; Sicilian 50; players Alpha Beta}
 } {
  array set ::application::assistant::Priv [list busy 1 observer {} reqconfirm {} pending {} plan {} planConfirmed 0 turnTools 1 turnResults {} turnRefusal {} prohibitedAnalysis 0 resultFacts {} internalReplies {} lastRequest $request messages [list [dict create role user content $request] [dict create role tool tool_name player_stats content $result]]]
  set ::c14::coverage missing
  ::application::assistant::Finish [dict create ok 1 message [dict create content $result]] 1
  set final [dict get [lindex $::application::assistant::Priv(messages) end] content]
  lappend out [expr {$final eq [::application::assistant::BoundsDecline $request] && [string first $result $final] < 0}]
  set ::c14::coverage supported
  lappend out [::application::assistant::RequestedFactSupport]
  set ::c14::coverage abstain
  lappend out [expr {![::application::assistant::RequestedFactSupport]}]
 }
 set out
} -cleanup {
 rename ::ai::systemone::chooseManySync {}
 rename ::c14::choose ::ai::systemone::chooseManySync
 array unset ::application::assistant::Priv
 array set ::application::assistant::Priv $saved
} -result {1 1 1 1 1 1}

tcltest::test c14-import-partial {an import error after append reports its exact effect and retry does not append again} -setup {
 set saved [array get ::application::assistant::Priv]
 set ::application::assistant::Priv(busy) 1
 set ::application::assistant::Priv(importedFiles) {}
 set ::c14::count 5
 set ::c14::imports 0
 set file [file join $::tcltest::temporaryDirectory c14-import.pgn]
 set f [open $file w];puts $f {generated};close $f
 foreach {command alias} {::application::assistant::ActiveBase base ::scidb::db::get get ::scidb::db::count count ::import::import import ::application::database::refreshBase refresh} {
  rename $command ::c14::real_$alias
 }
 proc ::application::assistant::ActiveBase {} {return {generated Normal}}
 proc ::scidb::db::get {kind args} {if {$kind eq {readonly?}} {return 0};return generated}
 proc ::scidb::db::count {args} {return $::c14::count}
 proc ::import::import {args} {incr ::c14::imports;incr ::c14::count 2;error {}}
 proc ::application::database::refreshBase {args} {error {refresh failed}}
} -body {
 set first [::application::assistant::DoImportGames [list $file]]
 set second [::application::assistant::DoImportGames [list $file]]
 list $::c14::imports $::c14::count [string match {*imported 2 games*do not retry*} $first] [string match {*already imported this turn*not repeated*} $second]
} -cleanup {
 foreach {command alias} {::application::assistant::ActiveBase base ::scidb::db::get get ::scidb::db::count count ::import::import import ::application::database::refreshBase refresh} {
  rename $command {};rename ::c14::real_$alias $command
 }
 file delete $file
 array unset ::application::assistant::Priv
 array set ::application::assistant::Priv $saved
} -result {1 7 1 1}
tcltest::test c14-native-float {current board refuses truthfully and a focused assistant really floats and docks} -body {
 set twm [::application::twm board]
 focus -force [$twm leaf board]
 set unavailable [::knowledge::Runnable c9.float]
 set refused [::application::assistant::runTool run_action {id c9.float}]
 ::application::assistant::show
 update
 focus -force $::application::assistant::Priv(entry)
 set object [::context::CurrentObject C9]
 set reply [::application::assistant::runTool run_action {id c9.float}]
 set floating [::menu::PaneFloating assistant $twm]
 set dock [::context::Invoke c9.float $object]
 list [lindex $unavailable 0] [string match {*pane that supports floating*} [lindex $unavailable 1]] \
  [string match {error: precondition:*pane that supports floating*} $refused] \
  $reply $floating $dock [::menu::PaneFloating assistant $twm]
} -result {0 1 1 {completed c9.float} 1 {completed c9.float} 0}
tcltest::cleanupTests
