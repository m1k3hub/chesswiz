# VS/VU-reg3: real public provider configuration, without capability overrides.
package require tcltest 2.5
source tests/app_actions_support.tcl
source tests/app_menu_reseal_scope_support.tcl
::scidb::test::actions::ready
::scidb::test::askscope::NewGame
::scidb::game::go 2

tcltest::test reseal-no-provider {unconfigured AI is absent from native menus, Ask and tools} -setup {
 set savedAI [array get ::application::ai::Config]
 set savedProvider [array get ::ai::provider::Config]
} -body {
 ::capability::ClearOverrides
 ::application::ai::configure -provider {} -model {}
 ::ai::provider::configure -name {} -model {}
 set ask [lmap row [::action::labels asklist {}] {lindex $row 0}]
 menu .noProvider -tearoff 0
 ::menu::BuildDropdown .noProvider
 set analysis [.noProvider entrycget 5 -menu]
 ::menu::FillTop Analysis $analysis
 .noProvider post 50 100
 $analysis post 300 100
 update
 set posted [::scidb::test::askscope::PostedIds $analysis]
 set bad {}
 foreach id {explain_position menu.analysis.analyze menu.analysis.explain.position menu.analysis.explain.line menu.analysis.explain.comment c2.explain_move c3.ask_about_game c6.explain_line c11.draft_comment c11.explain_comment} {
  set state [::menu::state $id]
  puts [list NO_PROVIDER_ROW $id state $state ask [expr {$id in $ask}] posted [expr {$id in $posted}]]
  if {[dict get $state visible] || $id in $ask || $id in $posted} {lappend bad $id}
 }
 # Also build every context with its real current object, checking the
 # same AI-owned rows cannot leak through a native context menu.
 foreach cid {C1 C2 C3 C4 C5 C6 C7 C8 C9 C10 C11 C12} {
  menu .noProviderContext -tearoff 0
  ::context::Build $cid .noProviderContext [::context::CurrentObject $cid]
  foreach id [::scidb::test::askscope::PostedIds .noProviderContext $cid] {
   if {$id in [dict get $::capability::ActionModules ai]} {lappend bad [list $cid $id]}
  }
  destroy .noProviderContext
 }
 package require json
 set tools [lmap tool [::json::json2dict [::application::assistant::toolsJson]] {dict get $tool function name}]
 if {"explain_position" in $tools} {lappend bad explain_position}
 list [::capability::present ai] $::capability::Overrides $bad
} -cleanup {
 catch {$analysis unpost}; catch {.noProvider unpost}; catch {destroy .noProvider}
 catch {destroy .noProviderContext}
 array set ::application::ai::Config $savedAI
 array set ::ai::provider::Config $savedProvider
} -result {0 {} {}}
tcltest::test reseal-configured-stub-provider {the built-in deterministic provider remains usable} -setup {
 set savedAI [array get ::application::ai::Config]
 set savedProvider [array get ::ai::provider::Config]
} -body {
 ::application::ai::configure -provider stub -model {}
 ::ai::provider::configure -name stub -model {}
 list [::application::ai::Ready stub] [::capability::present ai] [dict get [::menu::state menu.analysis.explain.position] visible]
} -cleanup {
 array set ::application::ai::Config $savedAI
 array set ::ai::provider::Config $savedProvider
} -result {1 1 1}
::tcltest::cleanupTests
