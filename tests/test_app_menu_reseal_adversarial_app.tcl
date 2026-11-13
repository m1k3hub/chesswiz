# Retained from VS-reg-fresh / VU-reg-retry probes (2026-11-12).
package require tcltest 2.5
source tests/app_actions_support.tcl
::scidb::test::actions::ready
namespace eval ::audit {variable called 0}
proc ::audit::sentinel {args} {incr ::audit::called; return SENTINEL}
tcltest::test all-tools-unknown-key {every schema rejects invented argument before handler} -body {
 set bad {};set count 0
 dict for {name action} $::application::assistant::Actions {
  set command [lindex $action 5]
  if {[llength $command]!=1} {error "prefix $command"}
  rename $command ${command}__audit
  interp alias {} $command {} ::audit::sentinel
  set argv [::scidb::test::actions::sampleArgs $name]
  dict set argv __audit_unknown 1
  set code [catch {::application::assistant::runTool $name $argv} reply]
  rename $command {};rename ${command}__audit $command
  if {$code || ![string match error:* $reply]} {lappend bad [list $name $code $reply]}
  incr count
 }
 puts [list UNKNOWN_KEY count $count called $::audit::called bad $bad]
 list $count $::audit::called $bad
} -result {95 0 {}}
tcltest::test malformed-public-arguments {bad argument container returns error text without exception} -body {
 set bad {}
 set ::audit::called 0
 rename ::application::assistant::DoSwitchTab ::audit::savedSwitchTab
 interp alias {} ::application::assistant::DoSwitchTab {} ::audit::sentinel
 try {
  foreach path {::action::run ::application::assistant::runTool} {
   foreach value [list {tab} {tab board extra foo} [format %c 123]] {
    set code [catch {$path switch_tab $value} reply]
    puts [list MALFORMED $path input $value code $code reply $reply]
    if {$code || ![string match error:* $reply]} {lappend bad [list $path $value $code $reply]}
   }
  }
  foreach path {::action::run ::application::assistant::runTool} {
   set code [catch {$path run_action {id}} reply]
   if {$code || ![string match error:* $reply]} {lappend bad [list $path run_action $code $reply]}
  }
  if {$::audit::called} {lappend bad [list handler-called $::audit::called]}
 } finally {
  rename ::application::assistant::DoSwitchTab {}
  rename ::audit::savedSwitchTab ::application::assistant::DoSwitchTab
 }
 set bad
} -result {}
tcltest::test module-tools-hidden {absent optional modules have no hidden dedicated action in model tools} -body {
 package require json
 set bad {}
 dict for {module ids} $::capability::ActionModules {
  ::capability::Override $module 0
  set names [lmap tool [::json::json2dict [::application::assistant::toolsJson]] {dict get $tool function name}]
  foreach id $ids {if {$id in $names} {lappend bad [list $module $id]}}
  ::capability::ClearOverrides
 }
 set bad
} -result {}
proc ::audit::walk {w} {
 if {[winfo class $w] eq "Toolbar"} {
  foreach c [winfo children $w] {
   if {[winfo class $c] ni {Button DropdownButton Checkbutton Radiobutton}} continue
   if {![catch {$c cget -command} cmd] && $cmd eq ""} {
    set bindings {}
    foreach tag [bindtags $c] {foreach event [bind $tag] {if {[string match *Button* $event]} {lappend bindings [list $tag $event [bind $tag $event]]}}}
    puts [list EMPTY_TOOLBAR $c class [winfo class $c] bindings $bindings]
   }
  }
 }
 foreach c [winfo children $w] {::audit::walk $c}
}
::audit::walk .
::tcltest::cleanupTests
