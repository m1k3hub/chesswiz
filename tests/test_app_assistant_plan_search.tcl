package require tcltest 2.5
source [file join [file dirname [info script]] test_app_assistant_plan.tcl]

# Public arguments and positional handler arguments are distinct APIs.
# Run real database searches through the multi-call provider/plan surface.
proc ::scidb::test::plan::ClosePlayerCard {} {
 foreach w [::application::assistant::PlanWindows] {
  if {[string match *Alpha* [wm title $w]] && [winfo ismapped $w]} {
   set ::scidb::test::plan::CardSeen 1
   destroy $w
   return
  }
 }
 set ::scidb::test::plan::CardTimer [after 100 ::scidb::test::plan::ClosePlayerCard]
}
tcltest::test plan-search-display {a confirmed plan displays matching games and opens the real player card} -setup {
 set planPgn [file join $::env(HOME) plan-search.pgn]
 set f [open $planPgn w]
 puts $f {[Event "Generated"]
[White "Alpha, Alice"]
[Black "Beta, Bob"]
[Result "1/2-1/2"]

1. e4 e5 1/2-1/2

[Event "Generated"]
[White "Beta, Bob"]
[Black "Gamma, Grace"]
[Result "1-0"]

1. d4 d5 1-0
}
 close $f
 ::application::assistant::DoOpenDatabase $planPgn
 update
} -body {
 ::scidb::test::plan::isolated {
  ::scidb::test::plan::action test.plan.confirm confirmed [dict create confirm 1 what "confirm plan"]
  set ::scidb::test::plan::CardSeen 0
  set ::scidb::test::plan::CardTimer [after 100 ::scidb::test::plan::ClosePlayerCard]
  set calls {}
  foreach {name arguments} {test.plan.confirm {} search_games {player Alpha result draw} show_search {} open_view {kind player_card name Alpha}} {
   lappend calls [dict create function [dict create name $name arguments $arguments]]
  }
  set ::scidb::test::plan::Queue [list [::scidb::test::plan::reply $calls]]
  set done [::scidb::test::plan::Run "Show Alpha's draws and player card"]
  after 250 {set ::scidb::test::plan::CardSettled 1}
  vwait ::scidb::test::plan::CardSettled
  lassign [::application::assistant::ActiveBase] base variant
  set replies [::scidb::test::plan::toolReplies]
  puts [list PLAN_SEARCH_REPLIES $replies CARD $::scidb::test::plan::CardSeen]
  list $done [::scidb::view::count games $base $variant 0] \
   [string match {*unknown argument*} $replies] \
   [string match {*game list shows the 1 games*} $replies] \
   $::scidb::test::plan::CardSeen [llength $::scidb::test::plan::ConfirmAsked]
 }
} -cleanup {
 catch {after cancel $::scidb::test::plan::CardTimer}
 catch {::application::database::closeBase .application $planPgn}
 catch {file delete $planPgn}
} -result {1 1 0 1 1 1}

tcltest::test plan-search-approval {confirmation binds to normalized arguments without dispatching them as public input} -body {
 set call [dict create function [dict create name search_games arguments {player Alpha result draw}]]
 set prepared [lindex [::application::assistant::PreparePlan [list $call]] 0]
 list [dict get $prepared function arguments] \
  [dict exists $prepared checkedArguments criteria] \
  [expr {[dict get $prepared checkedArguments] eq [::application::assistant::CheckArgs search_games [dict get $prepared function arguments]]}]
} -result {{player Alpha result draw} 1 1}

tcltest::cleanupTests
