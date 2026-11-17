package require tcltest 2.5
source [file join [file dirname [info script]] .. tcl command-table.tcl]
source [file join [file dirname [info script]] .. tcl command-line.tcl]
proc fixtureSource {type query} {
 set state {player {{Kasparov, Garry} {Kasparov, Sergei} {Carlsen, Magnus}} database {Main Other} engine {Stockfish} motif {knight_fork} tab {board database} move {e4}}
 set out {}
 if {![dict exists $state $type]} {return {}}
 foreach value [dict get $state $type] {if {[::commandline::NameMatch $query $value]} {lappend out $value}}
 return $out
}
set ::commandline::Source fixtureSource
::tcltest::test command-table-50 {all planned command ids exist} -body {
 llength [lsort -unique -integer [lmap row $::commandline::Table {lindex $row 0}]]
} -result 51
::tcltest::test command-ambiguity {ambiguous player names stay separate and exact} -body {
 set rows [::commandline::Suggest {find kasp wins wh}]
 lmap row $rows {dict get $row args}
} -result {{player {Kasparov, Garry} result win color white} {player {Kasparov, Sergei} result win color white}}
::tcltest::test command-no-invention {unknown names never become slot values} -body {
 ::commandline::Suggest {find games player imaginary}
} -result {}
::tcltest::test command-missing {required slot is visible and not runnable} -body {
 dict get [lindex [::commandline::Suggest {switch to}] 0] missing
} -result database
::tcltest::test command-ranges {fixed grammars reject invalid years and ratings} -body {
 list [::commandline::Values from 99] [::commandline::Values min_elo 4001] [::commandline::Values threads -1] [::commandline::Values from 2020]
} -result {{} {} {} 2020}
::tcltest::test command-no-eval {input is data, including Tcl metacharacters} -body {
 set ::injected 0
 ::commandline::Suggest {find games [set ::injected 1]}
 set ::injected
} -result 0
::tcltest::test command-deterministic {identical input and state have identical rows} -body {
 expr {[::commandline::Suggest {find kasp wins wh}] eq [::commandline::Suggest {find kasp wins wh}]}
} -result 1
::tcltest::test command-legal-move {move comes from board validation} -body {
 list [llength [::commandline::Suggest {check move e4}]] [llength [::commandline::Suggest {check move e5}]]
} -result {1 0}
::tcltest::test command-options {optional range fields retain independent dictionary keys} -body {
 dict get [lindex [::commandline::Suggest {find games from 2015 to 2018 min elo 2600}] 0] args
} -result {from 2015 to 2018 min_elo 2600}
::tcltest::test command-scratch-untracked {generated test scratch files are never committed} -body {
 set root [file normalize [file join [file dirname [info script]] ..]]
 if {[catch {exec git -C $root ls-files tests/tmp-app/cmdline} tracked]} {set tracked ""}
 llength [split [string trim $tracked] \n]
} -result 0
::tcltest::cleanupTests
