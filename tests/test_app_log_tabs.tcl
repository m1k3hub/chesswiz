package require tcltest 2.5

tcltest::test log-tabs-native {log uses positive increasing native tab distances} -body {
    set tabs [::log::TabStops .]
    text .crossLogTabs -tabs $tabs
    set result [expr {[lindex $tabs 0] > 0 && [lindex $tabs 1] > [lindex $tabs 0]}]
    destroy .crossLogTabs
    set result
} -result 1

tcltest::test log-tabs-zero-screen {zero native physical metrics still allow a log widget} -setup {
    rename ::winfo ::crossOriginalWinfo
    proc ::winfo {args} {
        if {[lindex $args 0] eq "pixels" && [lindex $args 2] in {2c 15c}} {return 0}
        return [uplevel 1 [list ::crossOriginalWinfo {*}$args]]
    }
} -body {
    set tabs [::log::TabStops .]
    text .crossLogTabs -tabs $tabs
    list $tabs [winfo exists .crossLogTabs]
} -cleanup {
    catch {destroy .crossLogTabs}
    rename ::winfo {}
    rename ::crossOriginalWinfo ::winfo
} -result {{1 2} 1}

tcltest::cleanupTests
