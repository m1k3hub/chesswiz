package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

namespace eval ::startupProgress { variable observed {} }
# Native callbacks bypass Tcl execution traces; observe the real Tk grab instead.
proc ::startupProgress::Observe {command code result op} {
    if {[lindex $command 1] eq ".progress"} {
        update
        lappend ::startupProgress::observed [list [grab current] [focus]]
    }
}
foreach mode {quiet explicit} {
    tcltest::test database-startup-progress-$mode {sample quiet load preserves focus; explicit load still grabs and focuses progress} -setup {
        set sample [::application::sample::location]
        ::scidb::test::wait::until {![::scidb::db::get open? $sample]}
        set entry [::application::ask::Entry]
        focus -force $entry
        update
        set ::startupProgress::observed {}
        trace add execution ::ttk::grabWindow leave ::startupProgress::Observe
    } -body {
        set loadOptions {}
        if {$mode eq "quiet"} {set loadOptions {-progress 0}}
        set opened [::application::database::openBase .application $sample yes -readonly 1 {*}$loadOptions]
        set observations $::startupProgress::observed
        puts [list PROGRESS $mode observations $observations]
        if {$mode eq "quiet"} {
            set correct [expr {$observations eq {} && [focus] eq $entry && [grab current] eq {}}]
        } else {
            set correct [expr {[lsearch -exact $observations {.progress .progress}] >= 0}]
        }
        list $opened [::scidb::db::get readonly? $sample] \
            [expr {[::scidb::db::count games $sample Normal] >= 2000}] $correct
    } -cleanup {
        trace remove execution ::ttk::grabWindow leave ::startupProgress::Observe
        ::application::database::closeBase .application $sample
    } -result {1 1 1 1}
}
tcltest::cleanupTests
