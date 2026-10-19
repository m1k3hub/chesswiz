# Run with a fresh HOME. Unlike run_app_tests.tcl, leave first-run setup on.
set argv {--single-process}
set argc 1
set ::env(SCIDB_AI_TRIAGE) 0
set ::env(SCIDB_AI_CLASSIFIER) off
proc checkLanguage {} {
    if {[winfo exists .application.lang] && [winfo viewable .application.lang]} {
        puts "PASS: fresh HOME reached the mapped Language dialog"
        flush stdout
        exit 0
    }
    after 50 checkLanguage
}
after 50 checkLanguage
after 15000 {puts stderr "FAIL: first-run Language dialog did not map"; exit 1}
source -encoding utf-8 [file join [file dirname [info script]] .. .. tcl chesswiz]
vwait ::firstRunForever
