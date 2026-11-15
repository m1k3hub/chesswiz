package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready
source [file join [file dirname [info script]] command_cases.tcl]
namespace eval ::commandE2E {variable Calls {}; variable State {}; variable Originals {}; variable Stubbed {}; variable Seen {}; variable Before}
# External/app services have a deterministic fixture state. Real registry validation
# and dispatch run; only terminal handlers are replaced in this contract suite.
# Actual app effects are exercised separately by test_app_command_effects.tcl.
proc ::commandE2E::source {type query} {
 set state {player {{Kasparov, Garry} {Kasparov, Sergei} {Carlsen, Magnus} {Caruana, Fabiano} {Corti, Horacio} {Thomas, Michael}} database {Main Other} engine {Stockfish} motif {knight_fork} tab {board database} pane {tree} opening {Najdorf {London System}} eco {B} event {{Karvina 5th} Biel} move {e4}}
 if {$type eq "eco"} {return [::commandline::EcoLookup eco $query]}
 set out {}
 if {[dict exists $state $type]} {foreach v [dict get $state $type] {if {[::commandline::NameMatch $query $v]} {lappend out $v}}}
 return $out
}
proc ::commandE2E::effect {id arguments} {
 lappend ::commandE2E::Calls [list $id $arguments]
 dict set ::commandE2E::State lastAction $id
 dict set ::commandE2E::State lastArguments $arguments
 return {}
}
# Real adapters and query/state handlers run; only terminal side effects are
# replaced. The trace records the dispatch contract even when a real handler
# then fails on the fixture's state.
proc ::commandE2E::recordRun {command op} {
 if {$op eq "enter"} {lappend ::commandE2E::Seen [lrange $command 1 end]}
}
trace add execution ::action::run enter ::commandE2E::recordRun
proc ::commandE2E::realAction {action} {
 if {[string match "command.*" $action]} {return 1}
 return [expr {$action in {database_summary list_open_databases clear_search remember_me current_game list_engines new_game pane}}]
}
proc ::commandE2E::stub {action} {
 if {[dict exists $::commandE2E::Originals $action]} {return}
 if {![dict exists $::action::Registry $action]} {return}
 dict set ::commandE2E::Originals $action [::action::get $action]
 dict set ::action::Registry $action handler [list ::commandE2E::effect $action]
 dict set ::commandE2E::Stubbed $action 1
}
proc ::commandE2E::checkState {number} {
 switch -- $number {
  4 {return [expr {[string length $::commandE2E::Message] > 0 && ![string match "error:*" $::commandE2E::Message]}]}
  31 {return [expr {[info exists ::application::ai::Settings(me)] && $::application::ai::Settings(me) eq "Thomas, Michael"}]}
  43 {return [expr {[::scidb::pos::fen] eq {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}}]}
  49 {return [expr {[lindex [split [.application.nb select] .] end] eq "database"}]}
  default {return 1}
 }
}
rename ::ui::message ::commandE2E::realMessage
proc ::ui::message {text args} {set ::commandE2E::Message $text}
set ::commandE2E::Before(source) $::commandline::Source
set ::commandE2E::Before(me) $::application::ai::Settings(me)
set ::commandE2E::Before(bulk) $::action::BulkHook
proc ::commandE2E::yes {what} {return 1}
set ::action::BulkHook ::commandE2E::yes
set ::commandE2E::Before(confirm) $::action::ConfirmHook
set ::commandline::Source ::commandE2E::source
set ::application::ai::Settings(me) {Thomas, Michael}
set ::action::ConfirmHook ::commandE2E::yes
set fixturePath [file join $::env(HOME) command-fixture.pgn]
set fixture [open $fixturePath w]
puts $fixture {[Event "Command Fixture"]
[Site "Test"]
[Date "2024.01.01"]
[Round "1"]
[White "Carlsen, Magnus"]
[Black "Kasparov, Garry"]
[Result "1-0"]

1. e4 e5 1-0}
close $fixture
::action::run open_database [dict create path $fixturePath]
::application::switchTab board
# Nested terminal actions reached by the real adapters stay side-effect free.
foreach action {download_games import_games compact_database convert_database similar_games
                player_stats study_plan engine_evaluate training_set td.create stop_engine} {
 ::commandE2E::stub $action
}
rename ::playengine::StartGame ::commandE2E::realStartGame
proc ::playengine::StartGame {args} {
 lappend ::commandE2E::Calls [list command.play-start $args]
 return "started"
}
foreach {number input action expected} $CommandCases {
 set input [string map [list /tmp/command-fixture.pgn $fixturePath] $input]
 dict for {k v} $expected {dict set expected $k [string map [list /tmp/command-fixture.pgn $fixturePath] $v]}
 if {![::commandE2E::realAction $action]} {::commandE2E::stub $action}
 ::tcltest::test command-e2e-$number {input -> suggestion -> Enter -> real registry action, arguments, state} -body {
  set ::commandE2E::Calls {}; set ::commandE2E::State {}; set ::commandE2E::Seen {}
  set ::commandE2E::Message ""
  if {$number == 31} {catch {unset ::application::ai::Settings(me)}}
  if {$number == 49} {::application::switchTab board}
  set ::application::ask::Mode command
  set ::application::ask::Query $input
  unset -nocomplain ::application::ask::Priv(filtered)
  ::application::ask::Typed
  set rows $::application::ask::Priv(commands)
  set chosen -1; set i 0
  foreach row $rows {
   if {[dict get $row id] == $number && [dict get $row action] eq $action && [dict get $row args] eq $expected} {set chosen $i; break}
   incr i
  }
  if {$chosen < 0} {error "missing expected suggestion for $input: $rows"}
  if {$::commandE2E::Calls ne {} || $::commandE2E::Seen ne {}} {error {typing ran a command}}
  set ::application::ask::Priv(index) $chosen
  ::application::ask::ShowList
  ::application::ask::Choose
  if {![llength $::commandE2E::Seen]} {error "Enter dispatched nothing: $::commandE2E::Message"}
  lassign [lindex $::commandE2E::Seen 0] actual arguments
  if {$actual ne $action} {error "dispatched '$actual', expected '$action'"}
  if {$arguments ne $expected} {error "wrong arguments: $arguments, expected $expected"}
  set real [::commandE2E::realAction $action]
  if {[string match "command.*" $action] && [dict exists $::commandE2E::Stubbed $action]} {error "adapter $action was stubbed"}
  if {$real && [dict exists $::commandE2E::Stubbed $action]} {error "real action $action was stubbed"}
  if {!$real && ![dict exists $::commandE2E::Stubbed $action]} {error "terminal action $action was not stubbed"}
  list 1 1 [::commandE2E::checkState $number]
 } -result {1 1 1}
}
dict for {id record} $::commandE2E::Originals {dict set ::action::Registry $id $record}
catch {rename ::playengine::StartGame {}}
rename ::commandE2E::realStartGame ::playengine::StartGame
trace remove execution ::action::run enter ::commandE2E::recordRun
set ::commandline::Source $::commandE2E::Before(source)
set ::application::ai::Settings(me) $::commandE2E::Before(me)
set ::action::ConfirmHook $::commandE2E::Before(confirm)
set ::action::BulkHook $::commandE2E::Before(bulk)
catch {::application::database::closeBase .application $fixturePath}
file delete $fixturePath
::application::ask::HideList
set ::application::ask::Query {}
rename ::ui::message {}
rename ::commandE2E::realMessage ::ui::message
::tcltest::cleanupTests
