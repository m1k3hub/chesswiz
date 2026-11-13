# Retained from VS-reg-fresh / VU-reg-retry probes (2026-11-12).
package require tcltest 2.5
source tests/app_actions_support.tcl
::scidb::test::actions::ready
source tests/app_menu_reseal_scope_support.tcl
namespace eval ::reseal {}
proc ::reseal::snap {tag} {
 set ask {}; foreach row [::action::labels asklist {}] {lappend ask [lindex $row 0]}
 set bad {}; set forbidden 0; set runnable 0
 foreach row [::action::labels dropdown] {
  lassign $row id label accel en vis
  puts [list STATE_ROW $tag $id $en $vis]
  set listed [expr {$id in $ask}]
  if {!$en || !$vis} {incr forbidden; if {$listed} {lappend bad [list $id leaked]}} else {incr runnable; if {!$listed} {lappend bad [list $id missing]}}
 }
 set allExpected {}
 foreach cid {C1 C2 C3 C4 C5 C6 C7 C8 C9 C10 C11 C12} {
  set obj [::context::CurrentObject $cid]
  set expected {}
  if {[dict size $obj] && [::context::HasObject $cid $obj]} {
   menu .statectx -tearoff 0
   if {[::context::Build $cid .statectx $obj]} {set expected [::scidb::test::askscope::PostedIds .statectx $cid]}
   destroy .statectx
  }
  lappend allExpected {*}$expected
  set got [::scidb::test::askscope::AskContextIds $cid]
  # Actions shared with another context are valid in either object.
  set exclusiveExpected {}; set exclusiveGot {}
  foreach id $expected {if {[dict get [::action::get $id] context] eq $cid} {lappend exclusiveExpected $id}}
  foreach id $got {if {[dict get [::action::get $id] context] eq $cid} {lappend exclusiveGot $id}}
  lassign [::scidb::test::askscope::Diff $exclusiveGot $exclusiveExpected] missing extra
  puts [list CONTEXT_PARITY $tag $cid expected $exclusiveExpected got $exclusiveGot missing $missing extra $extra]
  if {[llength $missing] || [llength $extra]} {lappend bad [list $cid missing $missing extra $extra]}
 }
 set allAsk {}
 foreach id $ask {if {[string match {c[0-9]*.*} $id]} {lappend allAsk $id}}
 lassign [::scidb::test::askscope::Diff [lsort -unique $allAsk] [lsort -unique $allExpected]] unionMissing unionExtra
 if {[llength $unionMissing] || [llength $unionExtra]} {lappend bad [list all-contexts missing $unionMissing extra $unionExtra]}

 set expect {}
 switch -glob -- $tag {
  R1-* {set expect {game-save 0 1 menu.game.copy 0 1}}
  R2-* {set expect {game-save 0 1 game-replace 0 1}}
  R4-* {set expect {menu.file.save 1 0 menu.db.maintenance.compact 1 0}}
  R9-* {set expect {menu.board.start.standard 0 1}}
  R10-start {set expect {c2.strip.truncate 0 1 c2.comment_before 0 1}}
  R10-mid {set expect {c2.strip.truncate 1 1 c2.comment_before 1 1}}
  R10-end {set expect {c2.strip.truncate 0 1 c2.comment_before 1 1}}
  R11-* {set expect {c3.sort_column 0 1}}
  R14-* {set expect {menu.analysis.analyze 0 1 menu.analysis.explain.position 0 1 menu.analysis.explain.line 0 1 menu.analysis.explain.comment 0 1}}
 }
 foreach {id visible enabled} $expect {
  set st [::menu::state $id]
  puts [list ORACLE $tag $id expected $visible $enabled observed $st]
  if {[dict get $st visible] != $visible || ($visible && [dict get $st enabled] != $enabled)} {error "oracle mismatch $tag $id $st"}
 }
 if {[string match R16-* $tag]} {
  menu .oracleDrop -tearoff 0
  ::menu::BuildDropdown .oracleDrop
  set row [expr {$tag eq "R16-database-tab" ? 4 : 3}]
  puts [list CASCADE_ORACLE $tag type [.oracleDrop type $row] label [.oracleDrop entrycget $row -label] state [.oracleDrop entrycget $row -state]]
  if {[.oracleDrop type $row] ne "cascade" || [.oracleDrop entrycget $row -state] ne "disabled"} {error "whole cascade not disabled"}
  .oracleDrop post 100 100
  update
  .oracleDrop unpost
  destroy .oracleDrop
 }

 puts [list STATE_PARITY $tag forbidden $forbidden runnable $runnable bad $bad]
 if {[llength $bad]} {error $bad}
}

tcltest::test reseal-rules-real-states {same live fixtures compare dropdown/context availability and Ask rows} -body {
 ::reseal::snap R1-no-game-R3-clipbase-R5-no-base-R6-idle-R8-no-selection
 ::scidb::test::askscope::NewGame
 ::scidb::game::go start
 ::reseal::snap R10-start
 ::scidb::game::go 2
 ::reseal::snap R10-mid
 ::scidb::game::go end
 ::reseal::snap R10-end
 ::game::flipTrialMode
 ::reseal::snap R2-trial
 ::game::flipTrialMode
 set base [::scidb::test::actions::fixture]
 ::action::run open_database [dict create path $base]
 ::reseal::snap R4-readonly-pgn
 set gameManager $::application::database::Vars(games).twm
 set gameTable [set ::application::database::games::${gameManager}::Priv(table)]
 set ::gamestable::${gameTable}::Vars(sortable) 0
 if {[dict get [::context::CurrentObject C3] sortable]} {error {unsortable table lost its state}}
 ::reseal::snap R11-unsortable
 set ::gamestable::${gameTable}::Vars(sortable) 1
 set ::action::ConfirmHook {apply {{args} {return 1}}}
 ::action::run add_engine {path /usr/games/stockfish}
 set engName [dict get [lindex $::engine::Engines end] Name]
 set ownEngine [::application::analysis::startEngine $engName {} {lines 1}]
 for {set i 0} {$i < 50 && ![::menu::EngineRunning]} {incr i} {after 50; update}
 if {![::menu::EngineRunning]} {error {owned engine did not start}}
 ::scidb::test::askscope::FocusPane analysis
 for {set i 0} {$i < 100 && ![dict size [::context::CurrentObject C6]]} {incr i} {after 50;update}
 set engineObject [::context::CurrentObject C6]
 if {![dict size $engineObject]} {error {running engine has no current line reference}}
 puts [list LIVE_ENGINE_REFERENCE $engineObject]
 set activeAsk [lmap row [::action::labels asklist {}] {lindex $row 0}]
 foreach id {c6.copy_line c9.analysis.best c9.analysis.opponents} {if {$id ni $activeAsk} {error "missing active engine row $id"}}
 ::reseal::snap R7-running-engine
 ::application::analysis::stopEngine $ownEngine
 update
 ::reseal::snap R6-stopped-engine
 # The application's normal variant command creates the non-Normal game.
 ::menu::gameNew .application ThreeCheck
 update
 ::reseal::snap R9-three-check
 ::scidb::test::askscope::FocusPane analysis
 ::application::assistant::DoPane undock analysis:1
 update
 ::scidb::test::askscope::FocusPane analysis
 if {![::menu::PaneFloating [dict get [::context::CurrentObject C9] paneUid] [::application::twm board]]} {error {floating pane fixture did not retain focus}}
 ::reseal::snap R12-floating-analysis
 ::application::assistant::DoPane dock analysis:1
 update
 foreach module [dict keys $::capability::Modules] {
  ::capability::Override $module 0
  ::reseal::snap absent-$module
  ::capability::ClearOverrides
 }
 ::capability::Override report 0
 ::reseal::snap R13-report-absent
 ::capability::ClearOverrides
 set savedAI [array get ::application::ai::Config]
 set savedProvider [array get ::ai::provider::Config]
 ::application::ai::configure -provider {} -model {}
 ::ai::provider::configure -name {} -model {}
 try {::reseal::snap R14-ai-absent} finally {
  array set ::application::ai::Config $savedAI
  array set ::ai::provider::Config $savedProvider
 }
 ::reseal::snap R15-native-platform
 ::application::switchTab database
 update
 ::reseal::snap R16-database-tab
 ::application::switchTab board
 update
 set boardManager [::application::twm board]
 foreach uid [$boardManager leaves] {
  if {$uid ne "board"} {::application::twm::ChangeState $boardManager $uid}
 }
 update
 if {[$boardManager leaves] ne {board}} {error {fixture is not physically board-only}}
 ::action::run menu.view.layout.save_as {name {Generated Board only}}
 ::action::run menu.view.layout.manage {operation load name {Generated Board only}}
 update
 if {![::menu::BoardOnlyLayout]} {error {board-only layout fixture was not active}}
 ::reseal::snap R16-board-only-layout
 return ok
} -result ok
::tcltest::cleanupTests
