# Retained from VS-reg-fresh / VU-reg-retry probes (2026-11-12).
package require tcltest 2.5
source tests/app_actions_support.tcl
::scidb::test::actions::ready
::menu::gameNew .application
update
set ::calls {}
proc recordAction {args} {lappend ::calls [lindex $args 0]}
trace add execution ::action::run enter recordAction
set button ""
foreach key [array names ::toolbar::Specs checkvar:*] {
 if {$::toolbar::Specs($key) eq "::board::hilite(show-suggested)"} {
  set button [lindex [split [string range $key 9 end] :] 0]
  break
 }
}
if {$button eq ""} {error "suggested-move toolbar control not found"}
puts [list CANDIDATE $button mapped [winfo ismapped $button] command [$button cget -command] release [bind $button <ButtonRelease-1>]]
set before $::board::hilite(show-suggested)
event generate $button <ButtonRelease-1> -x 5 -y 5
update
puts [list REGISTRY_BYPASS before $before after $::board::hilite(show-suggested) actionCalls $::calls]
trace remove execution ::action::run enter recordAction
tcltest::test toolbar-registry-contract {every executable toolbar control dispatches a registry action} -body {
 list [expr {$before ne $::board::hilite(show-suggested)}] [expr {[llength $::calls] == 1}]
} -result {1 1}
::tcltest::cleanupTests
