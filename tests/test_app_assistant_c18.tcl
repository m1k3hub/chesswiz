package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
::scidb::test::actions::ready
namespace eval ::c18 {}

tcltest::test c18-first-class-facts {direct and wrapped engine/tablebase returns survive coverage and provider failures without inventing prose} -setup {
 set saved [array get ::application::assistant::Priv]
 rename ::ai::systemone::chooseManySync ::c18::choose
 proc ::ai::systemone::chooseManySync {args} {
  incr ::c18::coverageCalls
  if {$::c18::coverage eq "error"} {error unavailable}
  if {$::c18::coverage eq "abstain"} {return {}}
  return [dict create coverage $::c18::coverage]
 }
} -body {
 set checks {}
 foreach coverage {supported missing abstain error} {
  set ::c18::coverage $coverage
  foreach name {engine_analysis engine_evaluate engine_check_move tablebase} {
   foreach wrapped {0 1} {
    foreach ending {answer refusal error} {
     set request {How does the engine see it?}
     set facts {Stockfish depth 19: +0.36; PV: 1.e4 c5}
     array set ::application::assistant::Priv [list busy 1 observer {} reqconfirm {} pending {} plan {} planConfirmed 0 turnTools 1 turnResults {} turnFactResults {} turnRefusal {} prohibitedAnalysis 0 resultFacts {} internalReplies {} lastRequest $request messages [list [dict create role user content $request] [dict create role tool tool_name $name content $facts]]]
     set ::c18::coverageCalls 0
     if {$wrapped} {
      ::application::assistant::RecordToolOutcome run_action ok $facts [dict create id $name]
     } else {::application::assistant::RecordToolOutcome $name ok $facts {}}
     set result [dict create ok 1 message [dict create content {An invented positional story.}]]
     if {$ending eq "refusal"} {set result [dict create ok 1 message [dict create content {Chesswiz cannot do that.}]]}
     if {$ending eq "error"} {set result [dict create ok 0 error unavailable]}
     ::application::assistant::Finish $result 1
     set final [dict get [lindex $::application::assistant::Priv(messages) end] content]
     lappend checks [expr {$final eq $facts && $::c18::coverageCalls == 0 && [::application::assistant::ExecutedReply] eq ""}]
    }
   }
  }
 }
 list [llength $checks] [lsort -unique $checks]
} -cleanup {
 rename ::ai::systemone::chooseManySync {}
 rename ::c18::choose ::ai::systemone::chooseManySync
 array unset ::application::assistant::Priv
 array set ::application::assistant::Priv $saved
} -result {96 1}

tcltest::test c18-offline-database {deterministic database coverage admits exact inspections and refuses missing fact types and narrower scopes} -setup {
 set saved [array get ::application::assistant::Priv]
 rename ::ai::systemone::chooseManySync ::c18::choose
 proc ::ai::systemone::chooseManySync {args} {
  if {$::c18::coverage eq "error"} {error unavailable}
  return {}
 }
} -body {
 set checks {}
 foreach coverage {abstain error} {
  set ::c18::coverage $coverage
  foreach {tool request content expected} {
   list_open_databases {List open databases.} {generated Normal} 1
   database_summary {How many games are in the current database?} {games: 200} 1
   current_game {Show the current game.} {generated game} 1
   database_summary {How many Sicilian games did Alpha play?} {games: 200} 0
   player_stats {What is Alpha's rating?} {Alpha; games: 12} 0
   database_summary {Show the active database summary.} {error: unavailable} 0
  } {
   array set ::application::assistant::Priv [list turnFactResults {} turnResults {} internalReplies {} userDeclinedPlan 0 messages [list [dict create role user content $request] [dict create role tool tool_name $tool content $content]]]
   lappend checks [expr {[::application::assistant::RequestedFactSupport] == $expected}]
  }
 }
 list [llength $checks] [lsort -unique $checks]
} -cleanup {
 rename ::ai::systemone::chooseManySync {}
 rename ::c18::choose ::ai::systemone::chooseManySync
 array unset ::application::assistant::Priv
 array set ::application::assistant::Priv $saved
} -result {12 1}

tcltest::test c18-failed-engine {failed and pending engine tools do not create authoritative facts} -setup {
 set saved [array get ::application::assistant::Priv]
 set ::application::assistant::Priv(busy) 1
 set ::application::assistant::Priv(turnFactResults) {}
} -body {
 foreach outcome {error declined later} {
  ::application::assistant::RecordToolOutcome engine_analysis $outcome {error: unavailable} {}
 }
 ::application::assistant::EngineFactsReply
} -cleanup {
 array unset ::application::assistant::Priv
 array set ::application::assistant::Priv $saved
} -result {}
tcltest::cleanupTests
