package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
::scidb::test::actions::ready

tcltest::test c15-games-current-tab {showing games after switching to database keeps that page and its actual list visible} -body {
 ::application::assistant::runTool switch_tab {tab database}
 set twm [::application::twm]
 set frame [$twm leaf games]
 set reply [::application::assistant::runTool pane {action show pane games}]
 update
 list [string match {*.database} [.application.nb select]] \
  [winfo ismapped $frame] [string match {the games pane is *shown} $reply]
} -cleanup {
 ::application::switchTab board
} -result {1 1 1}

tcltest::test c15-pane-host-tab {showing a board-only pane from database selects its host} -body {
 ::application::switchTab database
 set reply [::application::assistant::DoPane show board]
 update
 list [string match {*.board} [.application.nb select]] \
  [winfo ismapped [[::application::twm board] leaf board]] \
  [string match {the board pane is *shown} $reply]
} -result {1 1 1}
tcltest::cleanupTests
