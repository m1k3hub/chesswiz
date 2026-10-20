# Run headlessly with the app interpreter:
# xvfb-run -a /path/to/tkchesswiz tests/startup_timing.tcl
# Optional STARTUP_BUDGET_MS overrides the generous CI budget.
set startupTimingRoot [file normalize [file join [file dirname [info script]] ..]]
set startupTimingHome [file join $startupTimingRoot tests tmp-app startup-timing-[pid]]
file mkdir $startupTimingHome
set env(HOME) $startupTimingHome
set env(SCIDB_USERDIR) $startupTimingHome
set env(CHESSWIZ_LOG) debug
set env(SCIDB_AI_CLASSIFIER) off
set env(SCIDB_AI_TRIAGE) 0
set argv {--single-process}
set argc 1
set startupTimingBudget 5000
if {[info exists env(STARTUP_BUDGET_MS)]} {
    set startupTimingBudget $env(STARTUP_BUDGET_MS)
}
set startupTimingStarted [clock milliseconds]
set startupTimingMapped -1
set startupTimingError {}

proc startupTimingBgerror {msg} {
    set ::startupTimingError $msg
    puts stderr "STARTUP-TIMING background error: $msg"
}
proc startupTimingFinish {} {
    set elapsed $::startupTimingMapped
    set failed [expr {$elapsed < 0 || $elapsed > $::startupTimingBudget
        || $::startupTimingError ne {}}]
    puts "STARTUP-TIMING mapped=${elapsed}ms budget=$::startupTimingBudget result=[expr {$failed ? {FAIL} : {PASS}}]"
    file delete -force $::startupTimingHome
    exit $failed
}
proc startupTimingMap {w} {
    if {$w ne {.application} || $::startupTimingMapped >= 0} {return}
    set ::startupTimingMapped [expr {[clock milliseconds] - $::startupTimingStarted}]
    # Include deferred startup work in the background-error check.
    after 2000 startupTimingFinish
}
bind all <Map> {+startupTimingMap %W}
after 20000 startupTimingFinish
after 500 {interp bgerror {} startupTimingBgerror}
if {[catch {source [file join $startupTimingRoot tcl chesswiz]} msg opts]} {
    puts stderr [dict get $opts -errorinfo]
    set startupTimingError $msg
    startupTimingFinish
}
set ::scidb::dir::setup 0
vwait startupTimingForever
