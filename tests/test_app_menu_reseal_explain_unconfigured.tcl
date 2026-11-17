# Permanent VS/VU-reg4 regression probe; no network or private data.
foreach key {VAL_EVIDENCE OBJECT_EVIDENCE} {
 if {![info exists ::env($key)]} {set ::env($key) [file join $::env(HOME) evidence];file mkdir $::env($key)}
}
package require tcltest 2.5
source tests/app_actions_support.tcl
::scidb::test::actions::ready
source tests/app_menu_reseal_scope_support.tcl
::scidb::test::askscope::NewGame
set ::explainUnconfiguredRestore(savedProvider) [array get ::ai::provider::Config]
set ::explainUnconfiguredRestore(savedConfig) [array get ::application::ai::Config]
set ::explainUnconfiguredRestore(savedSettings) [array get ::application::ai::Settings]
::application::ai::configure -provider {} -model {}
set ::application::ai::Settings(provider) {}
set ::application::ai::Settings(model) {}
::ai::provider::configure -name {} -model {} -keys {}
tcltest::test R14-no-provider {unconfigured provider hides AI rows} -body {
 set ask [lmap row [::action::labels asklist {}] {lindex $row 0}]
 set st [::menu::state menu.analysis.explain.position]
 puts [list NO_PROVIDER configured [expr {$::application::ai::Config(provider) ne ""}] ready [::application::ai::Ready {}] capability [::capability::present ai] state $st ask_has [expr {"menu.analysis.explain.position" in $ask}]]
 foreach row [::action::labels dropdown] {if {[lindex $row 0] eq "menu.analysis.explain.position"} {puts [list NO_PROVIDER_DROPDOWN_ROW $row]}}
 menu .noprov -tearoff 0;::menu::BuildDropdown .noprov;.noprov post 100 100;update
 for {set i 0} {$i <= [.noprov index end]} {incr i} {
 if {[.noprov type $i] eq "cascade" && [string trim [.noprov entrycget $i -label]] eq "Analysis"} {
  set analysis [.noprov entrycget $i -menu]; .noprov postcascade $i;update
  for {set j 0} {$j <= [$analysis index end]} {incr j} {
   if {[$analysis type $j] eq "cascade" && [string match *Explain* [$analysis entrycget $j -label]]} {
    set explain [$analysis entrycget $j -menu];$analysis postcascade $j;update
    for {set k 0} {$k <= [$explain index end]} {incr k} {
     if {[$explain type $k] eq "command"} {puts [list NO_PROVIDER_POSTED label [$explain entrycget $k -label] state [$explain entrycget $k -state] command [$explain entrycget $k -command]]}
    }
   }
  }
 }
 }
 exec import -window root [file join $::env(VAL_EVIDENCE) R14-no-provider.png]
 set leaks {}
 foreach suffix {position line move comment} {
  set id menu.analysis.explain.$suffix
  set state [::menu::state $id]
  puts [list PROVIDER_ALL $id state $state ask [expr {$id in $ask}]]
  if {[dict get $state visible] || $id in $ask} {lappend leaks $id}
 }
 set leaks
} -cleanup {
 catch {destroy .noprov}
 array unset ::ai::provider::Config *
 array set ::ai::provider::Config $::explainUnconfiguredRestore(savedProvider)
 array unset ::application::ai::Config *
 array set ::application::ai::Config $::explainUnconfiguredRestore(savedConfig)
 array unset ::application::ai::Settings *
 array set ::application::ai::Settings $::explainUnconfiguredRestore(savedSettings)
 catch {::action::InvalidateAskRows}
} -result {}
::scidb::test::actions::release
::tcltest::cleanupTests
