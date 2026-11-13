package require tcltest 2.5
source tests/app_actions_support.tcl
source tests/app_menu_reseal_scope_support.tcl
::scidb::test::actions::ready
set base [::scidb::test::actions::fixture]
::action::run open_database [list path $base]
::action::run open_game {number 1 move 2 after black}
set ::c9errors {}
proc ::captureC9Bgerror {cmd op} {
 lappend ::c9errors [lindex $cmd 1]
 puts [list C9_BGERROR [lindex $cmd 1] errorInfo $::errorInfo]
}
set actualBgerror [lindex [interp bgerror {}] 0]
puts [list ACTUAL_BGERROR_HANDLER $actualBgerror]
if {![llength [info commands $actualBgerror]]} {auto_load $actualBgerror}
trace add execution $actualBgerror enter ::captureC9Bgerror
foreach id {c9.close c9.fold c9.float} {
 ::application::switchTab board
 ::scidb::test::askscope::FocusPane editor
 set object [::context::CurrentObject C9]
 set listed [::scidb::test::askscope::AskContextIds C9]
 if {$id ni $listed} {error "$id not listed in real editor context"}
 puts [list C9_BGPROBE_BEFORE $id object $object leaves [[dict get $object twm] leaves]]
 set reply [::action::run $id]
 for {set i 0} {$i<12} {incr i} {after 50;update}
 puts [list C9_BGPROBE_AFTER $id reply $reply errors $::c9errors]
 if {$id ne "c9.close"} {::action::run $id [dict create object [::context::CurrentObject C9]];update}
 ::application::openPane editor
 for {set i 0} {$i<12} {incr i} {after 50;update}
}
trace remove execution $actualBgerror enter ::captureC9Bgerror
tcltest::test populated-c9-no-bgerrors {each listed editor layout row runs without a background Tcl error in a loaded game} -body {set ::c9errors} -result {}
::tcltest::cleanupTests
