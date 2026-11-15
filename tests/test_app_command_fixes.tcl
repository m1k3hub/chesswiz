# Regression tests for the independent review of branch cmdline (FIX-BRIEF).
package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

namespace eval ::fix {
 variable Notices {}
 variable Assistant {}
 variable Calls {}
 variable Dir [file join $::env(HOME) command-fixes]
}
file mkdir $::fix::Dir

proc ::fix::run {text id} {
 set ::fix::Calls {}
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
 if {[llength $::fix::Calls]} {error {typing executed an action}}
 set ::application::ask::Priv(index) $chosen
 ::application::ask::ShowList
 ::application::ask::Choose
 return $::fix::Calls
}

proc ::fix::trace {command op} {lappend ::fix::Calls [lrange $command 1 end]}
trace add execution ::action::run enter ::fix::trace

set ::fix::Base [file join $::fix::Dir Main.pgn]
set f [open $::fix::Base w]
puts $f {[Event "Karvina 5th"]
[Site "Karvina"]
[Date "2020.01.01"]
[Round "1"]
[White "Kasparov, Garry"]
[Black "Carlsen, Magnus"]
[Result "1-0"]
[ECO "B90"]

1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6 6. Bg5 1-0

[Event "Biel"]
[Site "Biel"]
[Date "2021.01.01"]
[Round "2"]
[White "Carlsen, Magnus"]
[Black "Kasparov, Garry"]
[Result "1/2-1/2"]
[ECO "D02"]

1. d4 d5 1/2-1/2}
close $f
::action::run open_database [dict create path $::fix::Base]

# ----------------------------------------------------------------------
# F-01: query replies and dispatch errors must be visible on screen.
# ----------------------------------------------------------------------
::tcltest::test F-01-query-output-visible {query output is posted as a visible notice, not only written to the hidden log} -setup {
 set ::fix::Notices {}
 rename ::dialog::notice::post ::fix::realPost
 proc ::dialog::notice::post {kind message args} {lappend ::fix::Notices [list $kind $message]}
} -body {
 set calls [::fix::run {database summary} 4]
 set text [lindex $::fix::Notices 0 1]
 list [llength $::fix::Notices] [expr {[string first "Main" $text] >= 0}] [lindex $::fix::Notices 0 0] $calls
} -cleanup {
 catch {rename ::dialog::notice::post {}}
 rename ::fix::realPost ::dialog::notice::post
} -result {1 1 info {{database_summary {}}}}

::tcltest::test F-01-error-visible {dispatch errors are posted as error notices} -setup {
 set ::fix::Notices {}
 rename ::dialog::notice::post ::fix::realPost
 proc ::dialog::notice::post {kind message args} {lappend ::fix::Notices [list $kind $message]}
 rename ::commandline::Run ::fix::realRun
 proc ::commandline::Run {row} {return "error:handler exploded"}
} -body {
 ::fix::run {database summary} 4
 list [llength $::fix::Notices] [lindex $::fix::Notices 0 0] [lindex $::fix::Notices 0 1]
} -cleanup {
 catch {rename ::dialog::notice::post {}}
 rename ::fix::realPost ::dialog::notice::post
 catch {rename ::commandline::Run {}}
 rename ::fix::realRun ::commandline::Run
} -result {1 error {error:handler exploded}}

# ----------------------------------------------------------------------
# F-02: async handlers answer later through Resolve; the token must not
# leak to the user and the reply must reach them.
# ----------------------------------------------------------------------
::tcltest::test F-02-async-completion {a later token is hidden and its reply is shown when resolved} -setup {
 set ::fix::Notices {}
 set ::fix::Picked 0
 rename ::dialog::notice::post ::fix::realPost
 proc ::dialog::notice::post {kind message args} {lappend ::fix::Notices [list $kind $message]}
 rename ::action::run ::fix::realActionRun
 proc ::action::run {action args} {return "\x00later:77"}
 rename ::commandline::RecordPick ::fix::realRecordPick
 proc ::commandline::RecordPick {row} {incr ::fix::Picked}
} -body {
 set row [lindex [::commandline::Suggest tablebase] 0]
 set result [::commandline::Run $row]
 set pickedBefore $::fix::Picked
 set resolved [::application::assistant::Resolve "\x00later:77" "Tablebase verdict: draw"]
 list [string match "\x00later:*" $result] $pickedBefore $resolved $::fix::Picked [llength $::fix::Notices] [lindex $::fix::Notices 0 1]
} -cleanup {
 catch {rename ::dialog::notice::post {}}
 rename ::fix::realPost ::dialog::notice::post
 catch {rename ::action::run {}}
 rename ::fix::realActionRun ::action::run
 catch {rename ::commandline::RecordPick {}}
 rename ::fix::realRecordPick ::commandline::RecordPick
} -result {0 0 1 1 1 {Tablebase verdict: draw}}

trace remove execution ::action::run enter ::fix::trace
foreach position [::game::usedPositions?] {catch {::game::release $position}}
catch {::application::database::closeBase .application $::fix::Base}
set ::application::ask::Query {}
::application::ask::HideList
::tcltest::cleanupTests
