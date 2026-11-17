# Real UCI snapshots must insert moves, not merely resolve an Add action.
package require tcltest 2.5
source tests/app_actions_support.tcl
source tests/app_menu_reseal_effect_support.tcl
::scidb::test::actions::ready
namespace eval ::reg6pv {}
set program [::scidb::test::actions::engineProgram]
if {![::engine::ProbeNewEngine .application [list Command $program] UCI]} {error {UCI probe failed}}
foreach entry $::engine::Engines {if {[dict get $entry Command] eq $program} {set ::reg6pv::name [dict get $entry Name];break}}
proc ::reg6pv::hasSnapshot {number tree} {
 set engine [::engine::id $number]
 ::scidb::engine::snapshot $engine
 expr {[::scidb::engine::snapshot $engine san 0] ne "" && [::scidb::engine::snapshot $engine san 1] ne ""
  && [info exists ::application::analysis::${tree}::Vars(pv:1)]
  && [llength [::application::analysis::LineMoves [set ::application::analysis::${tree}::Vars(pv:1)]]] > 1}
}
proc ::reg6pv::insert {id} {
 set pos [::game::new .application -variant Normal]
 ::application::pgn::select $pos
 ::scidb::game::import $pos {1. e4 e5 2. Nf3 Nc6 *} {} {} -encoding utf-8 -variation 0
 ::scidb::game::go start
 ::scidb::game::go 1
 set reply [::action::run start_engine [dict create engine $::reg6pv::name lines 2 threads 1 hash 16]]
 if {![regexp {analysis pane (\d+)} $reply -> label]} {error $reply}
 # The reply names the pane title; the analysis number can differ when a
 # previous file left a freed number on the list.
 set number $label
 if {[info exists ::application::MapTerminalToAnalysis($label)]} {
  set number $::application::MapTerminalToAnalysis($label)
 }
 set tree $::application::analysis::NumberToTree($number)
 ::application::analysis::SetMultiPV $tree 2
 set code [catch {
  ::scidb::test::actions::waitUntil {[::reg6pv::hasSnapshot $number $tree]}
  # Lock the analysis to this board so inserting a variation cannot start
  # a different search while the posted menu is being observed.
  set ::application::analysis::${tree}::Vars(engine:locked) 1
  focus -force $tree
  ::application::analysis::VisitItem $tree enter Moves [$tree item id Line1] 10 10
  update
  set before [::scidb::game::toPGN modified]
  set result [::reg5effect::postContext C6 $id]
  set after [::scidb::game::toPGN modified]
  # A full PV insertion contains a real multi-ply alternative. Add All
  # must insert both alternatives, not just the physically selected one.
  set branches [regexp -all {\(} $after]
  set actualMoves [regexp -all {\m[a-hKQRBN][a-h1-8x+#=]*\M} $after]
  puts [list EFFECT $id result $result branches $branches before $before after $after]
  list [expr {$before ne $after}] [expr {$branches >= ($id in {c6.add_all c6.add_include} ? 2 : 1)}] [expr {$actualMoves >= ($id eq "c6.add_move" ? 5 : 6)}] [string match error:* $result]
 } result opts]
 ::application::analysis::CloseEngine $tree
 ::application::pgn::release $pos
 ::game::release $pos
 for {set i 0} {$i<6} {incr i} {after 50;update}
 if {$code} {return -options $opts $result}
 return $result
}
foreach id {c6.add_move c6.add_sequence c6.add_line c6.add_all c6.add_merge c6.add_include} {
 tcltest::test reg6-effect-$id {native engine Add row inserts actual snapshot moves into PGN} -body {
  ::reg6pv::insert $id
 } -result {1 1 1 0}
}
::scidb::test::actions::cleanup
::tcltest::cleanupTests
