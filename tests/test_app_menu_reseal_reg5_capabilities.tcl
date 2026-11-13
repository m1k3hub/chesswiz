package require tcltest 2.5
source tests/app_actions_support.tcl
source tests/app_menu_reseal_scope_support.tcl
::scidb::test::actions::ready
set fixture [::scidb::test::actions::fixture]
::action::run open_database [list path $fixture]
::action::run open_game {number 1 move 1 after white}
::scidb::test::askscope::NewGame
set required {annotate_game opponent_brief study_plan database_trend factcheck_annotations training_set check_results menu.analysis.annotate menu.analysis.factcheck menu.training.studyplan menu.training.brief menu.training.training_set menu.training.check_results menu.db.reports.trends c2.explain_move c3.ask_about_game c6.explain_line c11.draft_comment c11.explain_comment explain_position menu.analysis.analyze menu.analysis.explain.comment menu.analysis.explain.line menu.analysis.explain.move menu.analysis.explain.position}
foreach mode {unconfigured module_removed} {
 if {$mode eq "module_removed"} {rename ::application::ai::analyze ::application::ai::analyze__saved}
 ::application::ai::configure -provider {} -model {}
 set ::application::ai::Settings(provider) {};set ::application::ai::Settings(model) {}
 ::ai::provider::configure -name {} -model {} -keys {}
 tcltest::test independent-ai-$mode {all AI owned rows disappear from every public label surface} -body {
  puts [list AI_REAL_STATE provider $::application::ai::Config(provider) model $::application::ai::Config(model) Ready [::application::ai::Ready {}] analyzeExists [llength [info commands ::application::ai::analyze]]]
  set leaks {}; set ask [lmap r [::action::labels asklist {}] {lindex $r 0}]
  set drop [lmap r [::action::labels dropdown] {if {![lindex $r 4]} continue; lindex $r 0}]
  set tools [lmap t [::json::json2dict [::application::assistant::toolsJson]] {dict get $t function name}]
  foreach id $required {
   set st [::menu::state $id];set reply {not invoked: side-effecting AI feature}
   puts [list INDEPENDENT_AI $mode $id state $st ask [expr {$id in $ask}] dropdown [expr {$id in $drop}] tools [expr {$id in $tools}] reply $reply]
   if {[dict get $st visible] || $id in $ask || $id in $drop || $id in $tools} {lappend leaks $id}
  }
  set leaks
 } -result {}
}
rename ::application::ai::analyze__saved ::application::ai::analyze
::application::ai::configure -provider stub -model {}
::ai::provider::configure -name stub -model {}

package require tcltest 2.5
source tests/app_actions_support.tcl
::scidb::test::actions::ready
foreach {module command ids} {annotate ::ai::annotate::toggle {annotate_game menu.analysis.annotate} brief ::ai::brief::ask {opponent_brief menu.training.brief} studyplan ::ai::studyplan::run {study_plan menu.training.studyplan} trend ::ai::trend::report {database_trend menu.db.reports.trends}} {
 set removed [list $command]
 if {$module eq "trend"} {set removed [info commands ::ai::trend::*]}
 foreach cmd $removed {rename $cmd ${cmd}__saved}
 tcltest::test alias-absent-$module {actual absent module hides all independently traced aliases} -body {
  set ask [lmap r [::action::labels asklist {}] {lindex $r 0}];set tools [lmap t [::json::json2dict [::application::assistant::toolsJson]] {dict get $t function name}];set leaks {}
  foreach id $ids {set st [::menu::state $id];puts [list ALIAS_ABSENT $module $command capability [::capability::present $module] id $id state $st ask [expr {$id in $ask}] tools [expr {$id in $tools}]];if {[dict get $st visible] || $id in $ask || $id in $tools} {lappend leaks $id}}
  if {$module eq "trend"} {puts [list TREND_ABSENT_DISPATCH [::action::run database_trend]]}
  set leaks
 } -result {}
 foreach cmd $removed {rename ${cmd}__saved $cmd}
}

# Sweep exact execution entry points as well as module-family probes.
dict for {id command} $::capability::ActionCommands {
 tcltest::test reg5-entrypoint-$id {every optional alias vanishes when its actual entry point is absent} -setup {
  rename $command ${command}__reg5_saved
 } -body {
  set state [::menu::state $id]
  set ask [lmap row [::action::labels asklist {}] {lindex $row 0}]
  set tools [lmap tool [::json::json2dict [::application::assistant::toolsJson]] {dict get $tool function name}]
  puts [list ENTRYPOINT_ABSENT $id $command state $state]
  list [::capability::actionAvailable $id] [dict get $state visible] [expr {$id in $ask}] [expr {$id in $tools}]
 } -cleanup {
  rename ${command}__reg5_saved $command
 } -result {0 0 0 0}
}
::tcltest::cleanupTests
