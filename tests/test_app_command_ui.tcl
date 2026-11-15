package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready
namespace eval ::commandtest {variable calls {}; variable state {}}
proc ::commandtest::type {text} {
 set ::application::ask::Mode command
 set ::application::ask::Query $text
 unset -nocomplain ::application::ask::Priv(filtered)
 ::application::ask::Typed
}
rename ::action::run ::commandtest::realRun
proc ::action::run {id args} {lappend ::commandtest::calls [::list $id {*}$args]; return {}}
::tcltest::test command-ui-type {typing and full sentences never run anything} -body {
 set ::commandtest::calls {}
 ::commandtest::type {list engines}
 set n 0
 foreach row $::application::ask::Priv(commands) {
  if {![dict exists $row palette]} {incr n}
 }
 ::commandtest::type {Please start a new game for me.}
 ::application::ask::Choose
 list $n $::commandtest::calls
} -result {1 {}}
::tcltest::test command-ui-enter {Enter runs precisely the highlighted row} -body {
 ::commandtest::type {list engines}
 ::application::ask::Choose
 set ::commandtest::calls
} -result {{list_engines {}}}
::tcltest::test command-ui-click {click selects without execution} -body {
 set ::commandtest::calls {}
 ::commandtest::type {new game}
 ::application::ask::Click 2
 set ::commandtest::calls
} -result {}
::tcltest::test command-ui-stale-text {an edit without KeyRelease cannot run stale rows} -body {
 ::commandtest::type {new game}
 set ::application::ask::Query {list engines}
 ::application::ask::Choose
 set ::commandtest::calls
} -result {}
::tcltest::test command-ui-missing {Enter selects the missing placeholder and offers candidates} -body {
 ::commandtest::type {go to}
 ::application::ask::Choose
 set e [::application::ask::Entry]
 list [$e selection present] [string range [$e get] [$e index sel.first] [expr {[$e index sel.last]-1}]] [expr {[llength $::application::ask::Priv(commands)] > 0}] $::commandtest::calls
} -result {1 <tab> 1 {}}
::tcltest::test command-ui-voice {speech fills input; punctuated go confirms} -body {
 ::commandtest::type {}
 ::application::speech::InsertTranscript {list engines}
 ::application::ask::Typed
 set before $::commandtest::calls
 # whisper-cli terminates sentences with punctuation.
 ::application::speech::InsertTranscript {Go.}
 list $before $::commandtest::calls
} -result {{} {{list_engines {}}}}
::tcltest::test command-ui-voice-spacing {spoken transcripts keep word boundaries} -body {
 set ::commandtest::calls {}
 ::commandtest::type {}
 ::application::speech::InsertTranscript {list engines}
 ::application::ask::HideList
 set visible [::application::ask::ListVisible]
 ::application::speech::InsertTranscript go
 list $visible $::application::ask::Query $::commandtest::calls
} -result {0 {list engines go} {}}
::tcltest::test command-ui-question-refuses-tools {a provider cannot smuggle a command into question mode} -setup {
 rename ::application::assistant::Append ::commandtest::realAppend
 proc ::application::assistant::Append {role text args} {set ::commandtest::reply $text}
} -body {
 set ::commandtest::calls {}
 ::application::assistant::QuestionReply {ok 1 message {tool_calls {{function {name new_game arguments {}}}} content done}}
 list $::commandtest::calls $::commandtest::reply
} -cleanup {
 rename ::application::assistant::Append {}
 rename ::commandtest::realAppend ::application::assistant::Append
} -result {{} {Questions cannot run commands. Use Commands to choose an action.}}
rename ::action::run {}
rename ::commandtest::realRun ::action::run
::application::ask::HideList
set ::application::ask::Query {}
::tcltest::cleanupTests
