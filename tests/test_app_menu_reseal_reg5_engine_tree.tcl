# Physical engine/tree/column selections without first opening a popup.
package require tcltest 2.5
source tests/app_actions_support.tcl
source tests/app_menu_reseal_effect_support.tcl
::scidb::test::actions::ready
set base [::scidb::test::actions::fixture]
::action::run open_database [dict create path $base]
::action::run open_game {number 1 move 1 after white}
puts {REG5_ENGINE probing};flush stdout
set program [::scidb::test::actions::engineProgram]
if {![::engine::ProbeNewEngine .application [list Command $program] UCI]} {error {Real UCI engine probe failed}}
set name {}
foreach entry $::engine::Engines {if {[dict get $entry Command] eq $program} {set name [dict get $entry Name];break}}
if {$name eq {}} {error {Probed engine was not registered}}
set argv [dict create engine $name lines 2 threads 1 hash 16]
puts {REG5_ENGINE starting};flush stdout
set reply [::action::run start_engine $argv]
puts [list REG5_ENGINE reply $reply];flush stdout
if {![regexp {analysis pane (\d+)} $reply -> number]} {error "engine did not start: $reply"}
set tree $::application::analysis::NumberToTree($number)
::application::analysis::SetMultiPV $tree 2
::scidb::test::actions::waitUntil {[info exists ::application::analysis::${tree}::Vars(pv:1)] && [set ::application::analysis::${tree}::Vars(pv:1)] ne ""}
focus -force $tree
::application::analysis::VisitItem $tree enter Moves [$tree item id Line1] 10 10
update
tcltest::test reg5-highlighted-engine {implicit Copy Line uses the physically highlighted second PV} -body {
 set expected [set ::application::analysis::${tree}::Vars(pv:1)]
 set object [::context::CurrentObject C6]
 set reply [::action::run c6.copy_line]
 puts [list HIGHLIGHTED_PV object $object reply $reply clipboard [clipboard get]]
 list [dict get $object lineId] [expr {[clipboard get] eq $expected}]
} -result {1 1}

::application::ai::configure -provider stub -model {}
::ai::engine::configure -engine [::scidb::test::actions::engineProgram] -depth 1
foreach id {c6.explain_line menu.analysis.explain.line} {
 tcltest::test reg5-native-engine-model-$id {engine line explanation runs the real pipeline and renders in the real report} -body {
  ::application::ai::showReport .application {Before line explanation} {<p>Before line explanation</p>}
  ::ai::provider::configure -name stub -chatResponses [list [dict create role assistant content {Generated line explanation.}]]
  if {$id eq "c6.explain_line"} {::reg5effect::postContext C6 $id} else {::reg5effect::postInvoke $id}
  ::scidb::test::actions::waitUntil {[::reg5effect::reportContains {Generated line explanation.}]} 30000
  ::reg5effect::reportContains {Generated line explanation.}
 } -result 1
}
::ai::engine::shutdown
::application::analysis::CloseEngine $tree
update
::scidb::game::go start
::scidb::tree::set $base
set table $::application::tree::Vars(table)
::application::tree::DoSearch $table
::scidb::test::actions::waitUntil {[llength $::application::tree::Vars(data)] > 0}
::table::select $table 0
::table::activate $table 0
focus -force $table.t
update
tcltest::test reg5-tree-current-continuation {implicit tree copy includes the selected next move} -body {
 set next [::scidb::tree::move 0]
 set obj [::context::CurrentObject C8]
 set reply [::action::run c8.copy_line]
 puts [list TREE_SELECTED object $obj reply $reply clipboard [clipboard get]]
 list [dict get $obj row] [expr {[clipboard get] eq $next}]
} -result {0 1}
tcltest::test reg5-tree-clear-selection {clearing the tree selection removes the object and refuses copy} -body {
 ::table::select $table none
 list [::context::CurrentObject C8] [string match error:* [::action::run c8.copy_line]]
} -result {{} 1}
::application::switchTab database
update
set manager $::application::database::Vars(games).twm
set path [set ::application::database::games::${manager}::Priv(table)]
set header [::scrolledtable::table $path]
focus -force $header.t
::table::VisitHeader $header enter {} white
update
tcltest::test reg5-column-current-header {Ask resolves the physically visited column and hides that exact column} -body {
 ::application::ask::Focus
 update
 set obj [::context::CurrentObject C10]
 set reply [::action::run c10.hide]
 update
 puts [list COLUMN_SELECTED object $obj reply $reply]
 list [dict get $obj table] [dict get $obj column] [$header.t column cget white -visible]
} -result [list $header white 0]
::scidb::test::actions::cleanup
::tcltest::cleanupTests
