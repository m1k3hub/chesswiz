# Retained from VS-reg-fresh / VU-reg-retry probes (2026-11-12).
package require tcltest 2.5
source tests/app_actions_support.tcl
::scidb::test::actions::ready
set absentLeaks {}
foreach module {ai stream insights explorer playercard ics lichess} {
 set renamed {}
 foreach cmd [regexp -all -inline {::[A-Za-z0-9_:]+} [dict get $::capability::Modules $module]] {
  if {[llength [info commands $cmd]]} {rename $cmd ${cmd}__validatorSaved; lappend renamed $cmd}
 }
 puts [list ACTUAL_ABSENT $module capability [::capability::present $module] removed $renamed]
 puts [list TOOL_SCHEMA_ABSENT $module player_card [expr {[string first {"player_card"} [::application::assistant::toolsJson]] >= 0}] explorer [expr {[string first {"explorer"} [::application::assistant::toolsJson]] >= 0}]]
 foreach row [::action::labels dropdown] {lassign $row id label accel en vis; if {[regexp {playercard|insights|explorer|stream|ics|lichess} $id]} {puts [list ABSENT_DROPDOWN $module $row]}}
 set names [lmap tool [::json::json2dict [::application::assistant::toolsJson]] {dict get $tool function name}]
 set ask [lmap row [::action::labels asklist {}] {lindex $row 0}]
 if {[::capability::present $module]} {lappend absentLeaks [list $module capability-still-present]}
 foreach id [dict get $::capability::ActionModules $module] {
  if {$id in $names || $id in $ask || [dict get [::menu::state $id] visible]} {lappend absentLeaks [list $module $id]}
 }
 foreach cmd $renamed {rename ${cmd}__validatorSaved $cmd}
}
tcltest::test absent-module-commands {removing real optional commands hides all their owned rows} -body {
 set absentLeaks
} -result {}
tcltest::test absent-player-card-tool-schema {tool list must not expose absent player-card module} -setup {
 rename ::playercard::show ::playercard::show__validatorSaved
} -body {
 set denied {}
 foreach path {::action::run ::application::assistant::runTool} {
  lappend denied [string match {error:*unavailable module*} [$path open_view {kind player_card name {Generated Player}}]]
 }
 list [::capability::present playercard] [expr {[string first {"player_card"} [::application::assistant::toolsJson]] >= 0}] $denied
} -cleanup {rename ::playercard::show__validatorSaved ::playercard::show} -result {0 0 {1 1}}
::tcltest::cleanupTests
