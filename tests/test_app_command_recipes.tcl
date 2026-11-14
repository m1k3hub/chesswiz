package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready
namespace eval ::commandRecipe {variable Calls {}; variable Saved {}}
proc ::commandRecipe::stub {name body} {
 rename $name ${name}_command_saved
 proc $name {args} $body
 lappend ::commandRecipe::Saved $name
}
proc ::commandRecipe::restore {} {
 foreach name [lreverse $::commandRecipe::Saved] {rename $name {}; rename ${name}_command_saved $name}
 set ::commandRecipe::Saved {}
}
::tcltest::test command-recipe-tournament {fixed recipe previews and commits exactly the same tournament} -setup {
 ::commandRecipe::stub ::action::run {lappend ::commandRecipe::Calls $args; return {commit 0}}
 set ::commandRecipe::Calls {}
} -body {
 ::commandline::Action tournament {system {double round robin} engine_count 4 time_control 3+2 opening {London System}}
 lassign $::commandRecipe::Calls preview commit
 set p [lindex $preview 1]; set c [lindex $commit 1]
 list [lindex $preview 0] [lindex $commit 0] [dict get $p commit] [dict get $c commit] \
  [expr {[dict remove $p commit] eq [dict remove $c commit]}] [dict get $c system] [dict get $c opening] [dict get $c engine_count]
} -cleanup {::commandRecipe::restore} -result {td.create td.create 0 1 1 double-round-robin {London System} 4}
::tcltest::test command-recipe-preview-failure {a failed preview never commits} -setup {
 ::commandRecipe::stub ::action::run {lappend ::commandRecipe::Calls $args; return {error: unavailable engines}}
 set ::commandRecipe::Calls {}
} -body {
 set failed [catch {::commandline::Action tournament {system {round robin} engine_count 4}}]
 list $failed [llength $::commandRecipe::Calls]
} -cleanup {::commandRecipe::restore} -result {1 1}
::tcltest::test command-recipe-stop {the named engine is stopped in its running pane only} -setup {
 ::commandRecipe::stub ::application::assistant::RunningPanes {return {1 2}}
 ::commandRecipe::stub ::engine::engineName {return [expr {[lindex $args 0] == 1 ? "Stockfish" : "Other"}]}
 ::commandRecipe::stub ::action::run {lappend ::commandRecipe::Calls $args; return {}}
 set ::commandRecipe::Calls {}
} -body {
 ::commandline::Action stop {engine Stockfish}
 set ::commandRecipe::Calls
} -cleanup {::commandRecipe::restore} -result {{stop_engine {pane 1}}}
::tcltest::test command-recipe-identity {my game jobs use the displayed identity} -setup {
 ::commandRecipe::stub ::action::run {lappend ::commandRecipe::Calls $args; return {}}
 set ::commandRecipe::Calls {}
} -body {
 ::commandline::Action review {player {Thomas, Michael} games 12}
 ::commandline::Action study {player {Thomas, Michael} games {}}
 ::commandline::Action my_score {player {Thomas, Michael}}
 ::commandline::Action training {source {my games} player {Thomas, Michael} pattern knight_fork}
 set ::commandRecipe::Calls
} -cleanup {::commandRecipe::restore} -result {{study_plan {player {Thomas, Michael} games 12}} {study_plan {player {Thomas, Michael} games 10}} {player_stats {name {Thomas, Michael}}} {training_set {player {Thomas, Michael} pattern knight_fork}}}
::tcltest::test command-recipe-missing-identity {unknown user never means every player} -body {
 catch {::commandline::Action study {player {}}} message
 set message
} -result {First use 'I am <player>' to select your name.}
::tcltest::test command-recipe-twic-issue {an issue number is a concrete issue, not number of weeks} -setup {
 ::commandRecipe::stub ::action::run {lappend ::commandRecipe::Calls $args; return {}}
 set ::commandRecipe::Calls {}
} -body {
 ::commandline::Action twic {issue 1650}
 set ::commandRecipe::Calls
} -cleanup {::commandRecipe::restore} -result {{download_games {source url url https://theweekinchess.com/zips/twic1650g.zip}}}
::tcltest::cleanupTests
