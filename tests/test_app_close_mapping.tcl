package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready
namespace eval ::closeMapping {
 variable rows {}
 set f [open [file join [file dirname [info script]] fixtures inventory-map.tsv]]
 foreach line [split [read $f] \n] {
  if {[regexp {^[0-9]+\t} $line]} {dict set rows [lindex [split $line \t] 0] [split $line \t]}
 }
 close $f
}
tcltest::test close-map-native-handler {historical close and floating-window rows retain the correct operation handler family} -body {
 ::knowledge::Ensure
 set bad {}
 set closeRows {}
 dict for {row fields} $::closeMapping::rows {
  if {[regexp -nocase close [join $fields { }]]} {lappend closeRows $row}
 }
 if {[lsort -integer $closeRows] ne {2 68 145 252 253 344 368 651 683 818}} {
  lappend bad [list {close row census changed; audit new native command} $closeRows]
 }
 # Rows include both original and repeated inventory entries. The callback
 # family is checked as well as the id, so aliasing an id to another operation
 # cannot turn this check green.
 foreach {row id handler} {
  2 c4.close {::context::InvokeArgs c4.close}
  68 c6.close_engine {::context::InvokeArgs c6.close_engine}
  145 c4.close {::context::InvokeArgs c4.close}
  249 c9.stay_on_top {::context::InvokeArgs c9.stay_on_top}
  252 c9.close {::context::InvokeArgs c9.close}
  253 c9.close {::context::InvokeArgs c9.close}
  344 view.dialog.close ::menu::CloseNamedDialog
  368 help.close ::menu::CloseHelp
  651 c6.close_engine {::context::InvokeArgs c6.close_engine}
  683 menu.file.close {::menu::Invoke menu.file.close}
  818 view.dialog.close ::menu::CloseNamedDialog
 } {
  set mapped [lindex [dict get $::closeMapping::rows $row] 3]
  if {$mapped ne $id || [dict get [::action::get $mapped] handler] ne $handler} {lappend bad [list $row $mapped]}
 }
 # Native leaf commands reached by the shared dispatcher must agree with
 # the menu operations, rather than merely sharing the word "Close".
 foreach {command pattern} {
  ::menu::CloseHelp {::help::Destroy}
  ::menu::CloseNamedDialog {destroy \$window}
  ::context::Command {c4[.]close [^\n]*::application::database::closeBase}
  ::context::Command {c6[.]close_engine [^\n]*::application::analysis::CloseEngine}
  ::context::Command {c9[.]close [^\n]*twm\] close}
 } {
  if {![regexp $pattern [info body $command]]} {lappend bad [list $command $pattern]}
 }
 set bad
} -result {}
tcltest::cleanupTests
