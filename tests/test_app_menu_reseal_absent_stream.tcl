# Retained from VS-reg-fresh / VU-reg-retry probes (2026-11-12).
package require tcltest 2.5
package require json
source tests/app_actions_support.tcl
::scidb::test::actions::ready
source tests/app_menu_reseal_scope_support.tcl
::scidb::test::askscope::NewGame
::scidb::test::askscope::FocusPane media
rename ::application::media::OpenStream ::auditSavedOpenStream
tcltest::test absent-stream-model-and-ask {Open Stream vanishes from all surfaces when its implementation is absent} -body {
 set tools [lmap t [::json::json2dict [::application::assistant::toolsJson]] {dict get $t function name}]
 set ask [lmap r [::action::labels asklist {}] {lindex $r 0}]
 set obj [::context::CurrentObject C9]
 set ctx [::menu::state c9.media.stream $obj]
 menu .absentctx -tearoff 0
 ::context::Build C9 .absentctx $obj
 set posted [::scidb::test::askscope::PostedIds .absentctx C9]
 set reply [::action::run c9.media.stream [dict create object $obj]]
 puts [list ABSENT_STREAM capability [::capability::present stream] tools_has_open_stream [expr {"open_stream" in $tools}] ask_has_open_stream [expr {"open_stream" in $ask}] ask_has_c9_stream [expr {"c9.media.stream" in $ask}] posted_has_c9_stream [expr {"c9.media.stream" in $posted}] context_state $ctx reply $reply]
 list [expr {"open_stream" in $tools}] [expr {"open_stream" in $ask}] [expr {"c9.media.stream" in $ask}] [expr {"c9.media.stream" in $posted}]
} -cleanup {rename ::auditSavedOpenStream ::application::media::OpenStream;destroy .absentctx} -result {0 0 0 0}
::scidb::test::actions::release
::tcltest::cleanupTests
