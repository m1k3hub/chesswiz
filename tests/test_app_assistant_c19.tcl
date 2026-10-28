package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
::scidb::test::actions::ready
namespace eval ::c19 {}

tcltest::test c19-engine-fact-type {engine facts cannot substitute for requested metadata, with coverage on or off} -setup {
 set saved [array get ::application::assistant::Priv]
 rename ::ai::systemone::chooseManySync ::c19::choose
 proc ::ai::systemone::chooseManySync {args} {
  if {$::c19::coverage eq "off"} {error unavailable}
  return {coverage supported}
 }
} -body {
 set checks {}
 foreach ::c19::coverage {on off} {
  foreach request {{What is Alpha's rating?} {Analyze the position.} {How many games did Alpha win?} {What is the player's name?} {What date was the game played?} {What was the game result?} {Show Najdorf opening theory.} {What is the best move?} {What is the tablebase result?}} {
   set expected [expr {$request in {{Analyze the position.} {What is the best move?} {What is the tablebase result?}}}]
   set facts {Stockfish depth 19: +0.36; PV: 1.e4 c5}
   array set ::application::assistant::Priv [list busy 1 observer {} reqconfirm {} pending {} plan {} planConfirmed 0 turnTools 1 turnResults {} turnFactResults {} turnRefusal {} prohibitedAnalysis 0 resultFacts {} internalReplies {} userDeclinedPlan 0 lastRequest $request messages [list [dict create role user content $request] [dict create role tool tool_name engine_analysis content $facts]]]
   ::application::assistant::RecordToolOutcome engine_analysis ok $facts {}
   ::application::assistant::Finish [dict create ok 1 message [dict create content {Chesswiz cannot do that.}]] 1
   set final [dict get [lindex $::application::assistant::Priv(messages) end] content]
   lappend checks [expr {$final eq [expr {$expected ? $facts : [::application::assistant::BoundsDecline $request]}]}]
  }
 }
 list [llength $checks] [lsort -unique $checks]
} -cleanup {
 rename ::ai::systemone::chooseManySync {}
 rename ::c19::choose ::ai::systemone::chooseManySync
 array unset ::application::assistant::Priv
 array set ::application::assistant::Priv $saved
} -result {18 1}

tcltest::test c19-engine-position {explicit starting and FEN requests require the queried position, not just the right fact type} -setup {
 set saved [array get ::application::assistant::Priv]
} -body {
 set initial {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}
 set other {rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1}
 set checks {}
 foreach fen [list $initial $other] {
  array set ::application::assistant::Priv {busy 1 turnFactResults {} turnFactPositions {}}
  ::application::assistant::RecordToolOutcome engine_evaluate ok {score +0.20} [dict create fen $fen]
  lappend checks [expr {[::application::assistant::EngineFactSupport {What is the best move in the starting position?}] == ($fen eq $initial)}]
  lappend checks [expr {[::application::assistant::EngineFactSupport "Evaluate $other"] == ($fen eq $other)}]
 }
 set checks
} -cleanup {
 array unset ::application::assistant::Priv
 array set ::application::assistant::Priv $saved
} -result {1 1 1 1}

tcltest::test c19-moves-provenance {memory moves are refused before mutation, user and current-turn tool sequences are accepted} -setup {
 set saved [array get ::application::assistant::Priv]
 ::application::assistant::DoNewGame
 set ::application::assistant::Priv(messages) [list [dict create role user content {Show the Najdorf mainline.}]]
} -body {
 set before [::scidb::pos::fen]
 set code [catch {::application::assistant::DoSetPosition {} {1.e4 c5 2.Nf3 d6 3.d4 cxd4 4.Nxd4 Nf6 5.Nc3 a6}} text options]
 set checks [list [expr {$code == 1 && [dict get $options -errorcode] eq {CHESSWIZ MOVES PROVENANCE} && $text eq {moves must come from you or the database} && [::scidb::pos::fen] eq $before}]]
 set ::application::assistant::Priv(messages) [list [dict create role user content {Set up 1.e4 c5 2.Nf3 d6.}]]
 lappend checks [::application::assistant::MovesHaveSource {e4 c5 Nf3 d6}]
 lappend checks [expr {![::application::assistant::MovesHaveSource {e4 c5 Nf3 d6 d4}]}]
 lappend checks [expr {![::application::assistant::MovesHaveSource {c5 e4}]}]
 set ::application::assistant::Priv(messages) [list [dict create role tool content {1.e4 c5 2.Nf3 d6}] [dict create role user content {Show a line.}] [dict create role assistant content {1.d4 d5}] [dict create role tool content {1.c4 e5 2.Nc3 Nf6}]]
 lappend checks [::application::assistant::MovesHaveSource {c4 e5 Nc3 Nf6}]
 lappend checks [expr {![::application::assistant::MovesHaveSource {e4 c5}]}]
 lappend checks [expr {![::application::assistant::MovesHaveSource {d4 d5}]}]
 set ::application::assistant::Priv(messages) [list [dict create role user content {Set up 1.e4 c5}]]
 lappend checks [expr {![string match error:* [::application::assistant::DoSetPosition {} {e4 c5}]]}]
 set ::application::assistant::Priv(messages) [list [dict create role user content {Use the current game.}]]
 lappend checks [::application::assistant::MovesHaveSource {e4 c5}]
 puts [list PROVENANCE_CHECKS $checks]
 list [llength $checks] [lsort -unique $checks]
} -cleanup {
 array unset ::application::assistant::Priv
 array set ::application::assistant::Priv $saved
} -result {9 1}
tcltest::test c19-model-memory {the model cannot launder remembered opening moves through direct or wrapped setup} -setup {
 set saved [array get ::application::assistant::Priv]
 set savedAI [array get ::application::ai::Config]
 set savedProvider [array get ::ai::provider::Config]
 set route $::application::assistant::RouteMode
 set ::application::assistant::RouteMode off
 set ::application::ai::Config(provider) stub
} -body {
 set checks {}
 foreach tool {set_position run_action} {
  ::application::assistant::DoNewGame
  ::application::assistant::clear
  set before [::scidb::pos::fen]
  set request {Show the Najdorf mainline.}
  set arguments [dict create moves {1.e4 c5 2.Nf3 d6 3.d4 cxd4 4.Nxd4 Nf6 5.Nc3 a6}]
  if {$tool eq "run_action"} {set arguments [dict create id set_position arguments $arguments]}
  ::ai::provider::configure -name stub -chatResponses [list \
   [dict create role assistant content {} tool_calls [list [dict create function [dict create name $tool arguments $arguments]]]] \
   [dict create role assistant content {Chesswiz cannot do that.}]]
  ::application::assistant::ask $request
  if {$::application::assistant::Priv(busy)} {vwait ::application::assistant::Priv(busy)}
  set final [dict get [lindex $::application::assistant::Priv(messages) end] content]
  set errors {}
  foreach message $::application::assistant::Priv(messages) {
   if {[dict get $message role] eq "tool"} {lappend errors [dict get $message content]}
  }
  lappend checks [expr {$final eq [::application::assistant::BoundsDecline $request] && [::scidb::pos::fen] eq $before && [string match {*moves must come from you or the database*} $errors] && [::application::assistant::ExecutedReply] eq ""}]
 }
 set checks
} -cleanup {
 array unset ::application::assistant::Priv
 array set ::application::assistant::Priv $saved
 array unset ::application::ai::Config
 array set ::application::ai::Config $savedAI
 array unset ::ai::provider::Config
 array set ::ai::provider::Config $savedProvider
 set ::application::assistant::RouteMode $route
} -result {1 1}
tcltest::cleanupTests
