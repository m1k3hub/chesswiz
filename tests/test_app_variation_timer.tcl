# The stored opening-animation handle must name the real cancellable timer.
package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

tcltest::test variation-opening-timer-cancel {hiding the selector cancels its actual opening timer} -setup {
    set savedPosition $::variation::Options(slide:position)
    ::application::switchTab board
    update
    ::variation::hide 0
    set ::variation::Options(slide:position) bottom
} -body {
    set before [after info]
    ::variation::show {e4 d4}
    set handle $::variation::Vars(afterid)
    set valid [expr {![catch {after info $handle}]}]
    set created {}
    foreach timer [after info] {
        if {$timer ni $before} {lappend created $timer}
    }
    ::variation::hide 0
    set left {}
    foreach timer $created {
        if {$timer in [after info]} {lappend left $timer}
    }
    list $valid [expr {[llength $created] > 0}] [llength $left]
} -cleanup {
    ::variation::hide 0
    set ::variation::Options(slide:position) $savedPosition
    foreach timer $created {after cancel $timer}
} -result {1 1 0}

tcltest::cleanupTests
