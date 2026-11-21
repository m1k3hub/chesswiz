package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready
namespace eval ::commandEffects {variable Calls {}; variable Message {}; variable Dir [file join $::env(HOME) command-effects]}
file mkdir $::commandEffects::Dir
proc ::commandEffects::trace {command op} {lappend ::commandEffects::Calls [lrange $command 1 end]}
proc ::commandEffects::run {text id} {
 set ::commandEffects::Calls {}; set ::commandEffects::Message {}
 set ::application::ask::Mode command
 set ::application::ask::Query $text
 unset -nocomplain ::application::ask::Priv(filtered)
 ::application::ask::Typed
 set i 0; set chosen -1
 foreach row $::application::ask::Priv(commands) {
  if {[dict get $row id] == $id && ![llength [dict get $row missing]]} {set chosen $i; break}
  incr i
 }
 if {$chosen < 0} {error "no runnable suggestion for $text: $::application::ask::Priv(commands)"}
 if {[llength $::commandEffects::Calls]} {error {typing executed an action}}
 set ::application::ask::Priv(index) $chosen
 ::application::ask::ShowList
 ::application::ask::Choose
 if {![llength $::commandEffects::Calls]} {error "Enter did not run $text"}
 if {[string match {error:*} $::commandEffects::Message]} {error $::commandEffects::Message}
 return $::commandEffects::Message
}
rename ::ui::message ::commandEffects::realMessage
proc ::ui::message {text args} {set ::commandEffects::Message $text}
trace add execution ::action::run enter ::commandEffects::trace
set base [file join $::commandEffects::Dir Main.pgn]
set f [open $base w]
puts $f {[Event "Karvina 5th"]
[Site "Karvina"]
[Date "2020.01.01"]
[Round "1"]
[White "Kasparov, Garry"]
[Black "Carlsen, Magnus"]
[Result "1-0"]
[ECO "C20"]

1. e4 e5 2. Nf3 Nc6 1-0

[Event "Biel"]
[Site "Biel"]
[Date "2021.01.01"]
[Round "2"]
[White "Carlsen, Magnus"]
[Black "Kasparov, Garry"]
[Result "1/2-1/2"]

1. d4 d5 1/2-1/2}
close $f
::tcltest::test command-effect-open {Enter opens the exact selected file} -body {
 ::commandEffects::run "open database $base" 1
 expr {[::scidb::db::get name] eq $base}
} -result 1
::tcltest::test command-effect-names {names and events are read from the active base} -body {
 list [::commandline::AppSource player Kasp] [::commandline::AppSource event Karv]
} -result {{{Kasparov, Garry}} {{Karvina 5th}}}
::tcltest::test command-effect-search {Enter searches the real name index and retains exact criteria} -body {
 set message [::commandEffects::run {find games player Kasparov wins white} 15]
 list [string match {*1 games found*} $message] [dict get $::application::assistant::LastSearchCriteria player]
} -result {1 {Kasparov, Garry}}
::tcltest::test command-effect-game {Enter loads the requested game on the board} -body {
 ::commandEffects::run {open game 1 at move 2 white} 16
 expr {[string match {* b *} [::scidb::pos::fen]]}
} -result 1
::tcltest::test command-effect-filter {find games filters the list and clear filter restores it} -body {
 set shown [::scidb::view::count games $base Normal 0]
 ::commandEffects::run {clear filter} 6
 list $shown [::scidb::view::count games $base Normal 0]
} -result {1 2}
::tcltest::test command-effect-me {identity selection stores an existing player} -body {
 ::commandEffects::run {i am Kasparov} 31
 set ::application::ai::Settings(me)
} -result {Kasparov, Garry}
::tcltest::test command-effect-tab {navigation changes the actual selected notebook tab} -body {
 ::commandEffects::run {go to database} 49
 ::application::activeTab
} -result database
foreach format {pgn html pdf} signature {{[Event} {<!DOCTYPE} %PDF} {
 ::tcltest::test command-effect-export-$format {export writes the selected collection in the requested format} -body {
  set output [file join $::commandEffects::Dir games.$format]
  ::commandEffects::run "export database as $format to $output" 8
  set f [open $output rb]; set data [read $f]; close $f
  expr {[string first $signature $data] >= 0}
 } -result 1
}
::tcltest::test command-effect-overwrite {declining overwrite preserves existing bytes} -setup {
 set confirm $::action::ConfirmHook
 proc ::commandEffects::deny {what} {set ::commandEffects::Confirmed $what; return 0}
 set ::action::ConfirmHook ::commandEffects::deny
} -body {
 set output [file join $::commandEffects::Dir keep.pgn]
 set f [open $output w]; puts -nonewline $f KEEP; close $f
 ::commandEffects::run "export list as pgn to $output" 8
 set f [open $output r]; set data [read $f]; close $f
 list $data [string match {declined*} $::commandEffects::Message] [expr {$::commandEffects::Confirmed ne ""}]
} -cleanup {set ::action::ConfirmHook $confirm} -result {KEEP 1 1}
::tcltest::test command-effect-opening {setup uses opening-table moves to change the board} -body {
 ::commandEffects::run {set up Najdorf after 6.Bg5} 22
 list [lindex [split [::scidb::pos::fen]] 1] [lindex [split [::scidb::pos::fen]] 5]
} -result {b 6}
::tcltest::test command-effect-new {new game restores the standard board} -body {
 ::commandEffects::run {new game} 43
 ::scidb::pos::fen
} -result {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}
::tcltest::test command-effect-play {the chosen engine, clock and side become the real play session} -setup {
 set engines $::engine::Engines
 set ::engine::Engines [list [dict merge $::engine::EmptyEngine {Name StubEngine Command /bin/true Protocol UCI Features:UCI {}}]]
 rename ::playengine::RequestMove ::commandEffects::realRequest
 proc ::playengine::RequestMove {} {}
} -body {
 ::commandEffects::run {play StubEngine 3+2 as black} 42
 list $::playengine::Priv(engine) $::playengine::Priv(color:user) $::playengine::Priv(minutes) $::playengine::Priv(increment)
} -cleanup {
 ::playengine::Finish
 rename ::playengine::RequestMove {}
 rename ::commandEffects::realRequest ::playengine::RequestMove
 set ::engine::Engines $engines
} -result {StubEngine b 3 2}
::tcltest::test command-effect-tournament {Enter creates and pairs a journal-backed event without a model} -setup {
 set engines $::engine::Engines
 set ::engine::Engines [list [dict merge $::engine::EmptyEngine {Name StubEngine Command /bin/true Protocol UCI Features:UCI {}}]]
 rename ::td::event::SchedulePump ::commandEffects::realPump
 proc ::td::event::SchedulePump {path} {set ::commandEffects::TournamentPath $path}
} -body {
 ::commandEffects::run {run double round robin of 4 engines 3+2} 47
 set state [dict get [::td::store::Read $::commandEffects::TournamentPath] state]
 list [dict get $state system] [llength [dict get $state players]] [llength [dict get $state pairings]] [dict get $state status]
} -cleanup {
 rename ::td::event::SchedulePump {}
 rename ::commandEffects::realPump ::td::event::SchedulePump
 set ::engine::Engines $engines
} -result {double-round-robin 4 12 active}
::tcltest::test command-effect-close {close removes the selected database} -body {
 ::game::closeAll .application $base Normal
 ::commandEffects::run "close database $base" 3
 ::scidb::db::get open? $base
} -result 0
trace remove execution ::action::run enter ::commandEffects::trace
rename ::ui::message {}
rename ::commandEffects::realMessage ::ui::message
foreach position [::game::usedPositions?] {catch {::game::release $position}}
catch {::application::database::closeBase .application $base}
set ::application::ask::Query {}
::application::ask::HideList
::tcltest::cleanupTests
