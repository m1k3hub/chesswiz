package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
::scidb::test::actions::ready
namespace eval ::c20 {}

tcltest::test c20-move-position-scope {native move resolution accepts only the requested engine position} -setup {
 set saved [array get ::application::assistant::Priv]
} -body {
 set checks {}
 foreach line {{e4 e5} {d4 d5}} {
  set fen [dict get [::ai::setup::validate -moves $line] fen]
  set ::application::assistant::Priv(turnFactPositions) [list $fen]
  lappend checks [expr {[::application::assistant::EngineFactSupport {Evaluate after 1.d4 d5.}] == ($line eq {d4 d5})}]
  lappend checks [::application::assistant::EngineFactSupport {Evaluate this position.}]
  lappend checks [expr {![::application::assistant::EngineFactSupport {Evaluate this FEN.}]}]
 }
 set checks
} -cleanup {
 array unset ::application::assistant::Priv
 array set ::application::assistant::Priv $saved
} -result {1 1 1 1 1 1}

tcltest::test c20-fen-provenance {direct and wrapped model calls require user or same-turn FEN provenance} -setup {
 set saved [array get ::application::assistant::Priv]
 ::application::assistant::DoNewGame
 set fen {4k3/8/8/8/8/8/4P3/4K3 w - - 0 1}
} -body {
 set checks {}
 foreach name {set_position run_action} {
  foreach source {memory user tool previous} {
   ::ai::setup::position -moves {}
   set request {Show an opening from memory.}
   set messages [list [dict create role user content $request]]
   switch $source {
    user {set messages [list [dict create role user content "Set up $fen"]]}
    tool {lappend messages [dict create role tool content $fen]}
    previous {set messages [linsert $messages 0 [dict create role tool content $fen]]}
   }
   array set ::application::assistant::Priv [list busy 1 scriptPosition 0 messages $messages lastRequest $request turnTools 0]
   set arguments [dict create fen $fen moves {}]
   if {$name eq "run_action"} {set arguments [dict create id set_position arguments $arguments]}
   set before [::scidb::pos::fen]
   set result [::application::assistant::runTool $name $arguments]
   if {$source in {user tool}} {
    lappend checks [expr {![string match error:* $result] && [::scidb::pos::fen] eq $fen}]
   } else {
    lappend checks [expr {[string match {*FEN must come from you or the database*} $result] && [::scidb::pos::fen] eq $before}]
   }
  }
 }
 set checks
} -cleanup {
 array unset ::application::assistant::Priv
 array set ::application::assistant::Priv $saved
} -result {1 1 1 1 1 1 1 1}

tcltest::test c20-script-setup {explicit script arguments work while active unsourced model moves fail} -setup {
 set saved [array get ::application::assistant::Priv]
} -body {
 set checks {}
 foreach busy {0 1} {
  ::ai::setup::position -moves {}
  array set ::application::assistant::Priv [list busy $busy messages [list [dict create role user content {Show remembered theory.}]] turnTools 0]
  set result [::application::assistant::runTool set_position {moves {d4 d5}}]
  lappend checks [expr {[string match error:* $result] == $busy}]
 }
 set checks
} -cleanup {
 array unset ::application::assistant::Priv
 array set ::application::assistant::Priv $saved
} -result {1 1}

tcltest::test c20-dialog-intent {missing facts never reach view handlers; explicit dialog operations and read-only queries remain usable} -setup {
 set saved [array get ::application::assistant::Priv]
 rename ::ai::systemone::chooseManySync ::c20::choose
 proc ::ai::systemone::chooseManySync {args} {return [list intent $::c20::intent]}
 set ::c20::calls {}
 proc ::c20::entered {args} {lappend ::c20::calls [lindex [lindex $args 0] 0]}
 foreach proc {DoOpenView DoDiscover} {trace add execution ::application::assistant::$proc enter ::c20::entered}
 set windows [winfo children .]
} -body {
 array set ::application::assistant::Priv {busy 1 lastRequest {What is Carlsen's current rating?} turnTools 0}
 set ::c20::intent fact
 set a [::application::assistant::runTool open_view {kind player_card name Carlsen}]
 set b [::application::assistant::runTool discover_databases {}]
 set query [::application::assistant::runTool current_game {}]
 set noCalls [expr {![llength $::c20::calls]}]
 set ::c20::intent operation
 set ::application::assistant::Priv(lastRequest) {Open the database discovery dialog.}
 set c [::application::assistant::runTool discover_databases {}]
 list [dict get [::action::get discover_databases] effect] \
  [::action::changesState database_properties {}] \
  [::action::changesState correspondence_games {action open}] \
  [::action::changesState correspondence_games {action status}] \
  [string match error:* $a] [string match error:* $b] $noCalls \
  [expr {![string match error:* $query]}] \
  [expr {[llength $::c20::calls] == 1 && ![string match error:* $c]}]
} -cleanup {
 foreach proc {DoOpenView DoDiscover} {trace remove execution ::application::assistant::$proc enter ::c20::entered}
 foreach w [winfo children .] {if {$w ni $windows} {catch {destroy $w}}}
 rename ::ai::systemone::chooseManySync {}
 rename ::c20::choose ::ai::systemone::chooseManySync
 array unset ::application::assistant::Priv
 array set ::application::assistant::Priv $saved
} -result {change 1 1 0 1 1 1 1 1}

tcltest::test c20-view-offline {abstaining view intent accepts explicit UI commands and refuses factual questions} -setup {
 rename ::ai::systemone::chooseManySync ::c20::choose
 proc ::ai::systemone::chooseManySync {args} {error offline}
} -body {
 list [::application::assistant::ViewActionAllowed {Open the player card.} open_view] \
  [::application::assistant::ViewActionAllowed {What is Carlsen's rating?} open_view]
} -cleanup {
 rename ::ai::systemone::chooseManySync {}
 rename ::c20::choose ::ai::systemone::chooseManySync
} -result {1 0}

tcltest::test c20-tree-identity {an explicit opening tree request targets tree; explorer requests keep explorer} -setup {
 set saved [array get ::application::assistant::Priv]
} -body {
 set checks {}
 foreach request {{Hide the opening tree pane.} {Hide the opening explorer pane.}} expected {tree explorer} {
  ::application::assistant::DoPane show tree
  ::application::assistant::DoPane show explorer
  array set ::application::assistant::Priv [list busy 1 lastRequest $request turnTools 0]
  ::application::assistant::runTool pane {action hide pane explorer}
  update
  lappend checks [expr {![::menu::PaneChecked $expected]}]
  set other [expr {$expected eq "tree" ? "explorer" : "tree"}]
  lappend checks [::menu::PaneChecked $other]
 }
 set checks
} -cleanup {
 array unset ::application::assistant::Priv
 array set ::application::assistant::Priv $saved
} -result {1 1 1 1}

tcltest::test c20-native-position-source {native preset generators and explicit registry callers supply positions independently of model arguments} -setup {
 set saved [array get ::application::assistant::Priv]
} -body {
 set fen {7k/P7/8/8/8/8/8/7K w - - 0 1}
 array set ::application::assistant::Priv {busy 0 scriptPosition 0 messages {} lastRequest {Show an opening from memory.}}
 set a [::action::run set_position [dict create fen $fen]]
 set direct [expr {![string match error:* $a] && [::scidb::pos::fen] eq $fen}]
 set ::application::assistant::Priv(busy) 1
 set b [::action::run board.start_preset {preset Chess960}]
 set native [expr {![string match error:* $b] && [::scidb::pos::fen] ne $fen}]
 set ::application::assistant::Priv(messages) [list [dict create role user content {Show an opening from memory.}]]
 set before [::scidb::pos::fen]
 set c [::application::assistant::runTool set_position [dict create fen $fen]]
 list $direct $native [expr {[string match error:* $c] && [::scidb::pos::fen] eq $before}]
} -cleanup {
 array unset ::application::assistant::Priv
 array set ::application::assistant::Priv $saved
} -result {1 1 1}

tcltest::cleanupTests
