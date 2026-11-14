package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready
source [file join [file dirname [info script]] command_cases.tcl]
namespace eval ::commandE2E {variable Calls {}; variable State {}; variable Originals {}; variable Before}
# External/app services have a deterministic fixture state. Real registry validation
# and dispatch run; only terminal handlers are replaced in this contract suite.
# Actual app effects are exercised separately by test_app_command_effects.tcl.
proc ::commandE2E::source {type query} {
 set state {player {{Kasparov, Garry} {Kasparov, Sergei} {Carlsen, Magnus} {Caruana, Fabiano} {Corti, Horacio} {Thomas, Michael}} database {Main Other} engine {Stockfish} motif {knight_fork} tab {board database} pane {tree} opening {Najdorf {London System}} eco {B} event {{Karvina 5th} Biel} move {e4}}
 if {$type eq "eco" && $query eq "Sicilian"} {return B}
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
set fixture [open $fixturePath w]; close $fixture
foreach {number input action expected} $CommandCases {
 set input [string map [list /tmp/command-fixture.pgn $fixturePath] $input]
 dict for {k v} $expected {dict set expected $k [string map [list /tmp/command-fixture.pgn $fixturePath] $v]}
 if {![dict exists $::commandE2E::Originals $action]} {
  dict set ::commandE2E::Originals $action [::action::get $action]
  dict set ::action::Registry $action handler [list ::commandE2E::effect $action]
 }
 ::tcltest::test command-e2e-$number {input -> suggestion -> Enter -> registry action, arguments, state} -body {
  set ::commandE2E::Calls {}; set ::commandE2E::State {}
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
  if {$::commandE2E::Calls ne {}} {error {typing ran a command}}
  set ::application::ask::Priv(index) $chosen
  ::application::ask::ShowList
  ::application::ask::Choose
  if {[llength $::commandE2E::Calls] != 1} {error "Enter did not dispatch exactly once: $::commandE2E::Calls / $::commandE2E::Message"}
  lassign [lindex $::commandE2E::Calls 0] actual arguments
  dict for {k v} $expected {if {![dict exists $arguments $k] || [dict get $arguments $k] ne $v} {error "wrong argument $k: $arguments"}}
  list [expr {$actual eq $action}] [expr {[dict get $::commandE2E::State lastAction] eq $action}] [expr {[dict get $::commandE2E::State lastArguments] eq $arguments}]
 } -result {1 1 1}
}
dict for {id record} $::commandE2E::Originals {dict set ::action::Registry $id $record}
set ::commandline::Source $::commandE2E::Before(source)
set ::application::ai::Settings(me) $::commandE2E::Before(me)
set ::action::ConfirmHook $::commandE2E::Before(confirm)
set ::action::BulkHook $::commandE2E::Before(bulk)
file delete $fixturePath
::application::ask::HideList
set ::application::ask::Query {}
rename ::ui::message {}
rename ::commandE2E::realMessage ::ui::message
::tcltest::cleanupTests
