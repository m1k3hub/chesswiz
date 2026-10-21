# Condition waits for app-backed fixtures; timing assertions start afterwards.
namespace eval ::scidb::test::wait { variable serial 0 }

proc ::scidb::test::wait::until {condition {timeout 10000}} {
    variable serial
    set deadline [expr {[clock milliseconds] + $timeout}]
    while {1} {
        update
        if {[uplevel 1 [list expr $condition]]} { return }
        if {[clock milliseconds] >= $deadline} { error "condition timed out: $condition" }
        set flag [namespace current]::tick[incr serial]
        after 10 [list set $flag 1]
        vwait $flag
        unset $flag
    }
}

proc ::scidb::test::wait::ready {} {
    # ready is set before Startup2; display:after is installed at its end.
    until {$::application::Vars(ready) && [info exists ::application::Vars(display:after)]}
    update idletasks
    catch {destroy .tipoftheday}
}
