package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
::scidb::test::actions::ready
namespace eval ::c16 {}
proc ::c16::yes {args} {return 1}

# Keep registry dispatch and menu wrappers real; control the native UI boundary
# and provider so final rendering cannot depend on a cloud coverage judgment.
tcltest::test c16-handler-receipt {successful registry calls survive missing/abstaining coverage and later model refusal/error} -setup {
 set savedPriv [array get ::application::assistant::Priv]
 set savedAI [array get ::application::ai::Config]
 set savedProvider [array get ::ai::provider::Config]
 set savedRoute $::application::assistant::RouteMode
 set ::application::assistant::RouteMode off
 set ::application::ai::Config(provider) stub
 rename ::ai::provider::chatAsync ::ai::provider::c16Chat
 proc ::ai::provider::chatAsync {messages tools callback} {
  if {$::c16::ending eq "error" && $::ai::provider::Config(chatIndex) > 0} {
   after 0 [list {*}$callback [dict create ok 0 error {scripted failure}]]
  } else {::ai::provider::c16Chat $messages $tools $callback}
 }
 rename ::ai::systemone::chooseManySync ::c16::choose
 proc ::ai::systemone::chooseManySync {args} {
  if {$::c16::coverage eq "abstain"} {return {}}
  return [dict create coverage $::c16::coverage]
 }
 rename ::application::download::openActive ::c16::download
 proc ::application::download::openActive {args} {incr ::c16::entries;return {opened download chooser}}
 rename ::dialog::saveFile ::c16::saveFile
 proc ::dialog::saveFile {args} {incr ::c16::entries;return {}}
} -body {
 set out {}
 foreach {id request} {
  menu.tools.download {Find every game Magnus Carlsen played in 2024 online.}
  toolbar.database_switcher.0 {Create a new database called Test.}
 } {
  foreach coverage {supported missing abstain} {
   foreach ending {receipt refusal error} {
    set ::c16::coverage $coverage
    set ::c16::ending $ending
    set ::c16::entries 0
    ::application::assistant::clear
    set last [dict create role assistant content {The requested action ran.}]
    if {$ending eq "refusal"} {set last [dict create role assistant content {Chesswiz cannot do that.}]}
    if {$ending eq "error"} {set last [dict create ok 0 error {scripted failure}]}
    ::ai::provider::configure -name stub -chatResponses [list \
     [dict create role assistant content {} tool_calls [list [dict create function [dict create name run_action arguments [dict create id $id]]]]] $last]
    ::application::assistant::ask $request -confirm ::c16::yes
    if {$::application::assistant::Priv(busy)} {vwait ::application::assistant::Priv(busy)}
    set text [dict get [lindex $::application::assistant::Priv(messages) end] content]
    puts [list RECEIPT $id $coverage $ending entries $::c16::entries text $text]
    lappend out [expr {$::c16::entries == 1 && [string first $id $text] >= 0 && ![string match -nocase {*cannot*} $text]}]
   }
  }
 }
 list [llength $out] [lsort -unique $out]
} -cleanup {
 rename ::application::download::openActive {}
 rename ::c16::download ::application::download::openActive
 rename ::dialog::saveFile {}
 rename ::c16::saveFile ::dialog::saveFile
 rename ::ai::provider::chatAsync {}
 rename ::ai::provider::c16Chat ::ai::provider::chatAsync
 rename ::ai::systemone::chooseManySync {}
 rename ::c16::choose ::ai::systemone::chooseManySync
 array unset ::application::assistant::Priv
 array set ::application::assistant::Priv $savedPriv
 array unset ::application::ai::Config
 array set ::application::ai::Config $savedAI
 array unset ::ai::provider::Config
 array set ::ai::provider::Config $savedProvider
 set ::application::assistant::RouteMode $savedRoute
} -result {18 1}

tcltest::cleanupTests
