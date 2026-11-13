# A rebuilt editor must restore notation before selection callbacks run.
package require tcltest 2.5
source tests/app_actions_support.tcl
::scidb::test::actions::ready
::action::run open_database [dict create path [::scidb::test::actions::fixture]]
::action::run open_game {number 1 move 1 after white}
namespace eval ::reg9pane {variable errors {}}
proc ::reg9pane::Log {call op} {
 if {[lindex $call 1] eq "menu"} {lappend ::reg9pane::errors [lindex $call 2]}
}
trace add execution ::log::error enter ::reg9pane::Log
set reg9slot [::scidb::game::current]
foreach boardState {present absent} {
 tcltest::test reg9-editor-reopen-$boardState {repeated editor reconstruction restores game text and marks with or without a board} -body {
  if {[::menu::PaneChecked board] != ($boardState eq "present")} {::action::invoke menu.view.panes.board;update}
  set observed {}
  for {set round 0} {$round < 3} {incr round} {
   if {[::menu::PaneChecked editor]} {::action::invoke menu.view.panes.editor;update}
   set reply [::action::invoke menu.view.panes.editor]
   update
   set w $::application::pgn::Vars(pgn:$reg9slot)
   set text [$w get 1.0 end]
   lappend observed [list [string match error:* $reply] [winfo ismapped $w] \
    [expr {[string first e4 $text] >= 0}] [expr {"m-start" in [$w mark names]}] \
    [expr {[::scidb::game::current] == $reg9slot}]]
   puts [list REOPENED_EDITOR $boardState $round widget $w text $text]
  }
  list $observed $::reg9pane::errors
 } -result {{{0 1 1 1 1} {0 1 1 1 1} {0 1 1 1 1}} {}}
}
trace remove execution ::log::error enter ::reg9pane::Log

# Verify that a synchronous pane callback error remains visible when
# debug logging is disabled, instead of merely returning an error string.
tcltest::test reg9-menu-error-is-logged {synchronous menu errors reach the application log with their stack} -setup {
 rename ::menu::TogglePaneId ::reg9pane::SavedToggle
 proc ::menu::TogglePaneId args {error reg9-synchronous-sentinel}
 rename ::log::error ::reg9pane::SavedLog
 proc ::log::error args {set ::reg9pane::logged $args}
 set ::reg9pane::logged {}
} -body {
 set reply [::action::invoke menu.view.panes.editor]
 list [string match {error: reg9-synchronous-sentinel} $reply] \
  [expr {[string first {reg9-synchronous-sentinel} $::reg9pane::logged] >= 0}] \
  [expr {[string first {::menu::Do} $::reg9pane::logged] >= 0}]
} -cleanup {
 rename ::menu::TogglePaneId {};rename ::reg9pane::SavedToggle ::menu::TogglePaneId
 rename ::log::error {};rename ::reg9pane::SavedLog ::log::error
} -result {1 1 1}
if {![::menu::PaneChecked board]} {::action::invoke menu.view.panes.board;update}
::scidb::test::actions::cleanup
::tcltest::cleanupTests
