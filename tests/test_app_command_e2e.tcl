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
 return [expr {$action in {database_summary list_open_databases clear_search remember_me
  current_game list_engines new_game pane open_view opening_score player_stats
  structure_profile opponent_brief maintenance_report find_similar open_game}}]
}
proc ::commandE2E::stub {action} {
 if {[dict exists $::commandE2E::Originals $action]} {return}
 if {![dict exists $::action::Registry $action]} {return}
 dict set ::commandE2E::Originals $action [::action::get $action]
 dict set ::action::Registry $action handler [list ::commandE2E::effect $action]
 dict set ::commandE2E::Stubbed $action 1
}
proc ::commandE2E::called {id} {
 foreach call $::commandE2E::Calls {if {[lindex $call 0] eq $id} {return 1}}
 return 0
}
proc ::commandE2E::argsOf {id} {
 foreach call $::commandE2E::Calls {if {[lindex $call 0] eq $id} {return [lindex $call 1]}}
 return {}
}
proc ::commandE2E::checkState {number} {
 # Every command must finish without an error notice and leave a real state
 # behind; stubbed terminal actions must have received the validated arguments.
 if {[string match "error:*" $::commandE2E::Message]} {return 0}
 switch -- $number {
  1 {return [expr {[::scidb::db::get open? $::commandE2E::Fixture]}]}
  2 {return [expr {[string equal [lindex [::application::assistant::ActiveBase] 0] $::commandE2E::Fixture]}]}
  3 {return [expr {![::scidb::db::get open? $::commandE2E::Other]}]}
  4 {return [expr {[string length $::commandE2E::Message] > 0}]}
  5 {return [expr {[string first Main $::commandE2E::Message] >= 0}]}
  6 {return [expr {[::scidb::view::count games $::commandE2E::Fixture Normal 0] == 12}]}
  7 {return [::commandE2E::called import_games]}
  8 {return [expr {[llength $::commandE2E::Message] > 0}]}
  9 {return [::commandE2E::called download_games]}
  10 {return [expr {[::commandE2E::called save_working_set] && [dict get [::commandE2E::argsOf save_working_set] name] eq "Tactics"}]}
  11 {return [expr {[string length $::commandE2E::Message] > 0}]}
  12 {return [::commandE2E::called compact_database]}
  13 {return [expr {[::commandE2E::called convert_database] && [dict get [::commandE2E::argsOf convert_database] format] eq "sci"}]}
  14 {return [expr {[string length $::commandE2E::Message] > 0}]}
  15 {return [expr {[string match {*games found*} $::commandE2E::Message] && [::scidb::view::count games $::commandE2E::Fixture Normal 0] > 0}]}
  16 {return [expr {[lindex [::scidb::game::sink? [::scidb::game::current]] 2] == 11}]}
  17 {return [expr {[lindex [::scidb::game::sink? [::scidb::game::current]] 2] == 1}]}
  18 {return [::commandE2E::called similar_games]}
  19 {return [expr {[string match {*games found*} $::commandE2E::Message]}]}
  20 {return [expr {[llength [lmap {token row} $::commandline::Pending {
   if {[dict get $row action] eq "find_similar"} {set token}}]] > 0}]}
  21 {return [::commandE2E::called open_search]}
  22 {return [expr {[string length $::commandE2E::Message] > 0}]}
  23 {return [expr {[string length $::commandE2E::Message] > 0}]}
  24 {return [expr {[string length $::commandE2E::Message] > 0}]}
  25 {return [expr {[string length $::commandE2E::Message] > 0}]}
  26 {return [expr {[string length $::commandE2E::Message] > 0}]}
  27 {return [::commandE2E::called add_to_repertoire]}
  28 {return [expr {[string length $::commandE2E::Message] > 0}]}
  29 {return [expr {[string length $::commandE2E::Message] > 0}]}
  30 {return [expr {[string length $::commandE2E::Message] > 0}]}
  31 {return [expr {[info exists ::application::ai::Settings(me)] && $::application::ai::Settings(me) eq "Thomas, Michael"}]}
  32 {return [expr {[::commandE2E::called study_plan] && [dict get [::commandE2E::argsOf study_plan] games] == 10}]}
  33 {return [::commandE2E::called study_plan]}
  34 {return [expr {[string length $::commandE2E::Message] > 0}]}
  35 {return [::commandE2E::called start_engine]}
  36 {return [::commandE2E::called engine_evaluate]}
  37 {return [::commandE2E::called engine_check_move]}
  38 {return [::commandE2E::called annotate_game]}
  39 {return [::commandE2E::called tablebase]}
  40 {return [expr {[::engine::DefaultThreads Stockfish] == 8}]}
  41 {return [expr {[string first Stockfish $::commandE2E::Message] >= 0}]}
  42 {return [::commandE2E::called command.play-start]}
  43 {return [expr {[::scidb::pos::fen] eq {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}}]}
  44 {return [::commandE2E::called training_set]}
  45 {return [expr {[string length $::commandE2E::Message] > 0}]}
  46 {return [expr {[string length $::commandE2E::Message] > 0}]}
  47 {return [::commandE2E::called td.create]}
  48 {return [::commandE2E::called td.workspace]}
  49 {return [expr {[lindex [split [.application.nb select] .] end] eq "database"}]}
  50 {return [expr {[string length $::commandE2E::Message] > 0}]}
  default {return 0}
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
set ::application::ai::Settings(me) {Thomas, Michael}
set ::action::ConfirmHook ::commandE2E::yes
set ::commandE2E::Fixture [file join $::env(HOME) Main.pgn]
set ::commandE2E::Other [file join $::env(HOME) Other.pgn]
set fixture [open $::commandE2E::Fixture w]
puts $fixture {[Event "Karvina 5th"]
[Site "Karvina"]
[Date "2020.01.01"]
[Round "1"]
[White "Carlsen, Magnus"]
[Black "Kasparov, Garry"]
[Result "1-0"]
[ECO "B90"]

1. e4 c5 1-0

[Event "Biel"]
[Site "Biel"]
[Date "2021.01.01"]
[Round "2"]
[White "Kasparov, Garry"]
[Black "Carlsen, Magnus"]
[Result "1-0"]
[ECO "D02"]

1. d4 d5 1-0}
set names [list {Caruana, Fabiano} {Corti, Horacio} {Thomas, Michael}]
for {set i 3} {$i <= 12} {incr i} {
 set white [lindex $names [expr {($i-3)%3}]]
 set black [lindex $names [expr {($i-2)%3}]]
 if {$i == 12} {
  # game 12 is long enough for "open game 12 at move 20 black".
  puts $fixture "\n\[Event \"Command Fixture\"\]\n\[Site \"Test\"\]\n\[Date \"2024.01.01\"\]\n\[Round \"$i\"\]\n\[White \"$white\"\]\n\[Black \"$black\"\]\n\[Result \"1-0\"\]\n\n1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 6. Re1 b5 7. Bb3 d6 8. c3 O-O 9. h3 Nb8 10. d4 Nbd7 11. c4 c6 12. cxb5 axb5 13. Nc3 Bb7 14. Bg5 b4 15. Nb1 h6 16. Bh4 c5 17. dxe5 Nxe4 18. Bxe7 Qxe7 19. exd6 Qf6 20. Nbd2 Nxd6 1-0"
 } else {
  puts $fixture "\n\[Event \"Command Fixture\"\]\n\[Site \"Test\"\]\n\[Date \"2024.01.01\"\]\n\[Round \"$i\"\]\n\[White \"$white\"\]\n\[Black \"$black\"\]\n\[Result \"1-0\"\]\n\n1. e4 e5 1-0"
 }
}
close $fixture
set other [open $::commandE2E::Other w]
puts $other {[Event "Other Event"]
[Site "Other"]
[Date "2024.01.01"]
[White "Carlsen, Magnus"]
[Black "Caruana, Fabiano"]
[Result "0-1"]

1. d4 d5 0-1}
close $other
::action::run open_database [dict create path $::commandE2E::Fixture]
::action::run open_database [dict create path $::commandE2E::Other]
::action::run command.database.select [dict create database $::commandE2E::Fixture]
::application::switchTab board
set ::commandE2E::SavedEngines $::engine::Engines
set ::engine::Engines [list [dict merge $::engine::EmptyEngine {
 Name Stockfish Command /bin/true Protocol UCI
 Features:UCI {analyze true threads {1 128} limitStrength {0 2000} skillLevel {0 20}}
}]]
# Nested terminal actions reached by the real adapters stay side-effect free.
foreach action {download_games import_games compact_database convert_database similar_games
                study_plan engine_evaluate training_set td.create stop_engine start_engine
                engine_check_move annotate_game tablebase save_working_set add_to_repertoire
                open_search td.workspace} {
 ::commandE2E::stub $action
}
# The convert adapter reaches DoConvertDatabase directly instead of dispatching
# the registry action, so replace that terminal step for the same reason.
rename ::application::assistant::DoConvertDatabase ::commandE2E::realConvertDatabase
proc ::application::assistant::DoConvertDatabase {args} {
 ::commandE2E::effect convert_database [dict create format [lindex $args 0]]
 return "converted"
}
rename ::playengine::StartGame ::commandE2E::realStartGame
proc ::playengine::StartGame {args} {
 lappend ::commandE2E::Calls [list command.play-start $args]
 return "started"
}
foreach {number input action expected} $CommandCases {
 set input [string map [list /tmp/command-fixture.pgn $::commandE2E::Fixture /tmp/command-other.pgn $::commandE2E::Other] $input]
 dict for {k v} $expected {dict set expected $k [string map [list /tmp/command-fixture.pgn $::commandE2E::Fixture /tmp/command-other.pgn $::commandE2E::Other] $v]}
 if {![::commandE2E::realAction $action]} {::commandE2E::stub $action}
 ::tcltest::test command-e2e-$number {input -> suggestion -> Enter -> real registry action, arguments, state} -body {
  set ::commandE2E::Message ""
  if {$number == 31} {catch {unset ::application::ai::Settings(me)}}
  if {$number == 49} {::application::switchTab board}
  # "check move e4" is a command about the initial position; earlier commands
  # may have left another opening on the board.
  if {$number == 37} {catch {::action::run new_game}}
  # Setup may run real app actions; only the Enter path is under test.
  set ::commandE2E::Calls {}; set ::commandE2E::State {}; set ::commandE2E::Seen {}
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
set ::engine::Engines $::commandE2E::SavedEngines
unset -nocomplain ::engine::Options(Stockfish:cores)
rename ::application::assistant::DoConvertDatabase {}
rename ::commandE2E::realConvertDatabase ::application::assistant::DoConvertDatabase
catch {::application::database::closeBase .application $::commandE2E::Other}
catch {::application::database::closeBase .application $::commandE2E::Fixture}
file delete $::commandE2E::Fixture $::commandE2E::Other
::application::ask::HideList
set ::application::ask::Query {}
rename ::ui::message {}
rename ::commandE2E::realMessage ::ui::message
::tcltest::cleanupTests
