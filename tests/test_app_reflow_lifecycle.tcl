package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready
namespace eval ::reflowLifecycle {
    variable rebuilt 0
    variable errors {}
    proc recordError {command op} { variable errors; lappend errors $command }
    proc rebuild {t layout} {
        set ::application::Vars(loading) 1
        $t load $layout
        set ::application::Vars(loading) 0
        set ::reflowLifecycle::rebuilt 1
    }
    proc queueRebuild {target event t layout args} {
        trace remove execution $target $event [list ::reflowLifecycle::queueRebuild $target $event $t $layout]
        after idle [list ::reflowLifecycle::rebuild $t $layout]
    }
}
foreach {phase target event} {
 idle ::application::focuszoom::Snapshot leave
 restore ::application::reflow::restoreCollapsed enter
} {
tcltest::test reflow-collapse-rebuild-$phase {a real docking rebuild during collapse never uses retired panedwindows} -setup {
    .application.nb select .application.nb.board
    ::application::reflow::reset
    set t [::application::twm board]
    set original [::application::twm::inspectLayout $t]
    set ::application::Vars(loading) 1
    $t load [::application::reflow::substTpl [string map {{-orient horz} {-orient vert}} $::application::BoardLayout]]
    set ::application::Vars(loading) 0
    ::application::openPane analysis:1
    update
    ::scidb::test::wait::until {[winfo ismapped [$t leaf board]]}
    ::application::reflow::restoreCollapsed
    set ::application::reflow::S(override) {}
    set layout [::application::twm::inspectLayout $t]
    set retired [::application::focuszoom::Snapshot $t]
    set ::reflowLifecycle::rebuilt 0
    set ::reflowLifecycle::errors {}
    trace add execution ::scidb::bgerror enter ::reflowLifecycle::recordError
    if {$phase eq "restore"} {set ::application::reflow::S(snapshot) $retired}
    set hook [list ::reflowLifecycle::queueRebuild $target $event $t $layout]
    trace add execution $target $event $hook
} -body {
    set code [catch {::application::reflow::updateCollapse} message]
    update
    set destroyed 0
    foreach {pw coords} $retired { if {![winfo exists $pw]} { incr destroyed } }
    puts "REFLOW_LIFECYCLE code=$code rebuilt=$::reflowLifecycle::rebuilt destroyed=$destroyed errors=$::reflowLifecycle::errors message=$message"
    list $code $::reflowLifecycle::rebuilt [expr {$destroyed > 0}] $::application::reflow::S(busy) $::reflowLifecycle::errors
} -cleanup {
    catch {trace remove execution $target $event $hook}
    trace remove execution ::scidb::bgerror enter ::reflowLifecycle::recordError
    ::application::reflow::reset
    update
} -result {0 1 1 0 {}}
}
tcltest::cleanupTests
