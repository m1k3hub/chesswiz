package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready
namespace eval ::learningUI {variable Calls {}}
rename ::action::run ::learningUI::realRun
proc ::action::run {id args} {lappend ::learningUI::Calls [::list $id {*}$args]; return {}}
::tcltest::test command-learning-ui {an alias made in the UI only runs after Enter} -body {
 set ::application::ask::Query {list engines}
 unset -nocomplain ::application::ask::Priv(filtered)
 ::application::ask::Typed
 ::application::ask::Aliases
 set w .application.commandAliases
 $w.name insert 0 {my engines}
 $w.save invoke
 set saved [$w.list get 0 end]
 destroy $w
 set before $::learningUI::Calls
 set ::application::ask::Query {my engines}
 ::application::ask::Typed
 set label [dict get [lindex $::application::ask::Priv(commands) 0] label]
 ::application::ask::Choose
 list $saved $before $::learningUI::Calls [string match {my engines → *} $label] [dict size $::commandline::Picks]
} -result {{{my engines}} {} {{list_engines {}}} 1 1}
::tcltest::test command-learning-decline {declined actions are not learned} -setup {
 rename ::action::run ::learningUI::successfulRun
 proc ::action::run {id args} {return declined}
 rename ::ui::message ::learningUI::realMessage
 proc ::ui::message {args} {}
} -body {
 set before $::commandline::Picks
 ::commandline::Run [lindex [::commandline::Suggest {list engines}] 0]
 expr {$before eq $::commandline::Picks}
} -cleanup {
 rename ::action::run {}
 rename ::learningUI::successfulRun ::action::run
 rename ::ui::message {}
 rename ::learningUI::realMessage ::ui::message
} -result 1
::tcltest::test command-learning-ui-remove {aliases can be removed from the same dialog} -body {
 ::application::ask::Aliases
 .application.commandAliases.list selection set 0
 .application.commandAliases.remove invoke
 set count [.application.commandAliases.list size]
 destroy .application.commandAliases
 list $count [::commandline::Suggest {my engines}]
} -result {0 {}}
rename ::action::run {}
rename ::learningUI::realRun ::action::run
set ::application::ask::Query {}
::application::ask::HideList
::tcltest::cleanupTests
