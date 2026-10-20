# A pane reopened with an explicit analysis number must not also be handed out
# from the freed-number queue when Compare Engines starts a second engine.
package require tcltest 2.5

namespace eval ::scidb::test::paneids {
    variable program ""
    if {[info exists ::env(SCIDB_TEST_ENGINE)]} {
        set program $::env(SCIDB_TEST_ENGINE)
    } else {
        set program [lindex [auto_execok stockfish] 0]
    }
}
tcltest::testConstraint paneIdsEngine [file executable $::scidb::test::paneids::program]

proc ::scidb::test::paneids::wait {ms} {
    after $ms [list set [namespace current]::tick 1]
    vwait [namespace current]::tick
}
proc ::scidb::test::paneids::until {condition} {
    for {set elapsed 0} {$elapsed < 15000} {incr elapsed 50} {
        if {[uplevel 1 [list expr $condition]]} { return 1 }
        wait 50
    }
    return [uplevel 1 [list expr $condition]]
}
proc ::scidb::test::paneids::confirm {args} { return 1 }

namespace eval ::scidb::test::paneids {
tcltest::test analysis-comparison-reopened-pane-ids {close/reopen Analysis then compare two real engines in one process} \
        -constraints paneIdsEngine -setup {
    if {![until {$::application::Vars(ready)}]} { error "application startup timed out" }
    catch {destroy .tipoftheday}
    ::application::switchTab board
    update
    set savedEngines $::engine::Engines
    set savedFile $::scidb::file::engines
    set savedDefault $::engine::Options(engine)
    set savedConfirm $::application::assistant::Priv(confirm)
    set savedSeconds $::application::analysis::compare::Seconds
    set ::engine::Engines {}
    set ::scidb::file::engines [file join [tcltest::temporaryDirectory] paneids-engines-[pid].dat]
    set ::application::assistant::Priv(confirm) [namespace current]::confirm
    ::application::assistant::runTool add_engine [list path $program]
    set first [dict get [lindex $::engine::Engines 0] Name]
    set second "$first copy"
    lappend ::engine::Engines [dict replace [lindex $::engine::Engines 0] Name $second]
    set ::application::analysis::compare::Seconds 2
    set twm $::application::Vars(board:twm)
} -body {
    # Recreate pane 1 as explicit-number callers (including player preparation)
    # do, without altering allocator state.
    # Repeating also checks that multiple stale entries cannot survive reuse.
    for {set i 0} {$i < 2} {incr i} {
        $twm close [$twm leaf analysis:1]
        update idletasks
        ::application::newAnalysisPane 1
        update idletasks
    }
    ::application::analysis::openComparison .application
    set dlg .compareEngines
    $dlg.top.engines selection set 0 end
    $dlg.start invoke
    set entries $::application::analysis::compare::Vars(engines)
    set numbers [lmap entry $entries {lindex $entry 1}]
    set running [llength [::application::analysis::Running]]
    set live [until {
        [llength [::application::analysis::lines [lindex $numbers 0]]] > 0
        && [llength [::application::analysis::lines [lindex $numbers 1]]] > 0
    }]
    set names [lmap number $numbers {set ::engine::${number}::Vars(current:name)}]
    set rows [$dlg.top.results children {}]
    $dlg.stop invoke
    list $running [llength $rows] [expr {[llength [lsort -unique $numbers]] == 2}] \
        [expr {$names eq [list $first $second]}] $live [llength [::application::analysis::Running]]
} -cleanup {
    catch {::application::analysis::CloseComparison}
    foreach number [::application::analysis::Running] {
        ::application::analysis::stopEngine $number
    }
    # Retain the first pane for subsequent files; remove only extra panes.
    foreach uid [lreverse [$twm leaves]] {
        if {[string match {analysis:*} $uid] && $uid ne "analysis:1"} {
            $twm close [$twm leaf $uid]
        }
    }
    update idletasks
    wait 100
    file delete -force $::scidb::file::engines
    set ::engine::Engines $savedEngines
    set ::scidb::file::engines $savedFile
    set ::engine::Options(engine) $savedDefault
    set ::application::assistant::Priv(confirm) $savedConfirm
    set ::application::analysis::compare::Seconds $savedSeconds
    ::options::hookWriter ::engine::WriteEngineOptions engines
} -result {2 2 1 1 1 0}
}

tcltest::cleanupTests
