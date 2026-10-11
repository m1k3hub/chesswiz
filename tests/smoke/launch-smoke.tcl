# tkchesswiz -encoding utf-8 launch-smoke.tcl BUNDLE RESULT
# The macOS launcher supplies BUNDLE when CW_STARTUP_HARNESS is set.
if {[llength $argv] != 2} {
    puts stderr "usage: launch-smoke.tcl BUNDLE RESULT"
    exit 2
}
set smokeBundle [file normalize [lindex $argv 0]]
set smokeResult [file normalize [lindex $argv 1]]
set argv {}
set argc 0
proc smokePoll {} {
    if {[winfo exists .application] && [winfo ismapped .application]} {
        set out [open $::smokeResult w]
        puts $out OK
        close $out
        exit 0
    }
    after 100 smokePoll
}
after 60000 {puts stderr "SMOKE: timeout waiting for .application to map"; exit 1}
after 100 smokePoll
if {[catch {source -encoding utf-8 $smokeBundle} message options]} {
    puts stderr "SMOKE: $message"
    puts stderr [dict get $options -errorinfo]
    exit 1
}
vwait smokeNever
