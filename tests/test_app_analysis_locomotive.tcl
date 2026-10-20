# Exercise the first locomotive click in the Board tab, without start_engine
# or the setup dialog starting the engine on the test's behalf.
package require tcltest 2.5

namespace eval ::scidb::test::locomotive {
    variable tick
    variable log {}
    variable setupOpened 0
    variable program ""
    if {[info exists ::env(SCIDB_TEST_ENGINE)]} {
        set program $::env(SCIDB_TEST_ENGINE)
    } else {
        foreach path [list [file normalize [file join [file dirname [info script]] .. .. .. engines stockfish stockfish-chesswiz]] /usr/games/stockfish [lindex [auto_execok stockfish] 0]] {
            if {$path ne "" && [file executable $path]} { set program $path; break }
        }
    }
}
tcltest::testConstraint locomotiveEngine [file executable $::scidb::test::locomotive::program]

proc ::scidb::test::locomotive::wait {ms} {
    variable tick
    after $ms [list set [namespace current]::tick 1]
    vwait [namespace current]::tick
}
proc ::scidb::test::locomotive::until {condition {timeout 15000}} {
    for {set elapsed 0} {$elapsed < $timeout} {incr elapsed 50} {
        if {[uplevel 1 [list expr $condition]]} { return 1 }
        wait 50
    }
    return [uplevel 1 [list expr $condition]]
}
proc ::scidb::test::locomotive::confirm {args} { return 1 }
proc ::scidb::test::locomotive::logLine {arg line} {
    variable log
    append log $line "\n"
}
proc ::scidb::test::locomotive::locomotiveButton {parent} {
    foreach child [winfo children $parent] {
        if {![catch {$child cget -image} img] && $img eq $::icon::toolbarEngine} { return $child }
        if {![catch {::toolbar::childcget $child -tooltipvar} value] && ([string match "*StartEngine*" $value] || [string match "*SetupEngine*" $value])} { return $child }
        set found [locomotiveButton $child]
        if {$found ne ""} { return $found }
    }
    return ""
}
proc ::scidb::test::locomotive::click {button} {
    if {$button eq "" || ![winfo viewable $button]} { error "toolbar button is not visible: $button" }
    set x [expr {[winfo width $button] / 2}]
    set y [expr {[winfo height $button] / 2}]
    event generate $button <Enter> -x $x -y $y
    event generate $button <Motion> -x $x -y $y
    event generate $button <ButtonPress-1> -x $x -y $y
    event generate $button <ButtonRelease-1> -x $x -y $y
    update
}
# Old builds open a modal setup dialog. Close it without starting anything,
# so the regression reports missing analysis rather than hanging unattended.
proc ::scidb::test::locomotive::dismissSetup {number} {
    if {[winfo exists .setupEngine$number.close]} {
        set ::scidb::test::locomotive::setupOpened 1
        .setupEngine$number.close invoke
    }
}

namespace eval ::scidb::test::locomotive {
tcltest::test analysis-locomotive-tooltip {the Board locomotive toolbar button has the Start engine tooltip} -setup {
    if {![::scidb::test::locomotive::until {$::application::Vars(ready)}]} { error "application startup timed out" }
    catch {destroy .tipoftheday}
    ::application::switchTab board
    update
    set number [lindex [lsort -integer [array names ::application::analysis::NumberToTree]] 0]
    set tree $::application::analysis::NumberToTree($number)
    ::application::openPane analysis:[::application::mapToTerminalNumber $number] false
    update
    set start [::scidb::test::locomotive::locomotiveButton [winfo parent [winfo parent [winfo parent $tree]]]]
} -body {
    set tipVar [::toolbar::childcget $start -tooltipvar]
    list $tipVar [set $tipVar]
} -result {::application::analysis::mc::StartEngine {Start engine}}

foreach useSelected {1 0} {
tcltest::test analysis-locomotive-first-click-$useSelected {the Board locomotive starts its configured engine, live lines update, and a real Stop click freezes them} \
        -constraints locomotiveEngine -setup {
    if {![::scidb::test::locomotive::until {$::application::Vars(ready)}]} { error "application startup timed out" }
    catch {destroy .tipoftheday}
    ::application::switchTab board
    wm geometry .application 1900x1000+0+0
    update
    set savedEngines $::engine::Engines
    set savedFile $::scidb::file::engines
    set savedDefault $::engine::Options(engine)
    set savedConfirm $::application::assistant::Priv(confirm)
    set ::engine::Engines {}
    set ::scidb::file::engines [file join [tcltest::temporaryDirectory] locomotive-engines-[pid].dat]
    set ::application::assistant::Priv(confirm) ::scidb::test::locomotive::confirm
    ::application::assistant::runTool add_engine [list path $::scidb::test::locomotive::program]
    set name [dict get [lindex $::engine::Engines 0] Name]
    # Keep another valid default: the button must respect this pane's engine.
    lappend ::engine::Engines [dict replace [lindex $::engine::Engines 0] Name "$name pane"]
    set ::engine::Options(engine) $name
    if {$useSelected} { set name "$name pane" }
    set number [lindex [lsort -integer [array names ::application::analysis::NumberToTree]] 0]
    set tree $::application::analysis::NumberToTree($number)
    # An empty Analysis pane now collapses by content at every size
    # (VAL-PANE-010), so open it as the user does: an explicit open keeps
    # its locomotive visible for the click under test.
    ::application::openPane analysis:[::application::mapToTerminalNumber $number] true
    update
    namespace upvar ::application::analysis ${tree}::Vars pane
    ::engine::initVars $number
    namespace upvar ::engine::$number Vars engine
    set savedEngine [array get engine]
    set engine(current:name) [expr {$useSelected ? $name : ""}]
    set engine(current:cores) 1
    set engine(current:memory) 16
    set start [::scidb::test::locomotive::locomotiveButton [winfo parent [winfo parent [winfo parent $tree]]]]
    set ::scidb::test::locomotive::log {}
    set ::scidb::test::locomotive::setupOpened 0
    ::scidb::engine::log open ::scidb::test::locomotive::logLine {}
} -body {
    set tipVar [::toolbar::childcget $start -tooltipvar]
    set tipText [set $tipVar]
    set fresh [list [::engine::active? $number] $pane(engine:state) [llength [::application::analysis::lines $number]]]
    set watchdog [after 1000 [list ::scidb::test::locomotive::dismissSetup $number]]
    ::scidb::test::locomotive::click $start
    after cancel $watchdog
    if {![::scidb::test::locomotive::until {[llength [::application::analysis::lines $number]] > 0}]} {
        error "first locomotive click produced no engine lines (fresh=$fresh, setupOpened=$::scidb::test::locomotive::setupOpened, state=$pane(engine:state))"
    }
    set first [::application::analysis::lines $number]
    set updating [::scidb::test::locomotive::until {[::application::analysis::lines $number] ne $first}]
    ::scidb::test::locomotive::until {[::toolbar::childcget $pane(widget:button:stop) -state] eq "normal"}
    ::scidb::test::locomotive::click $pane(widget:button:stop)
    set answered [::scidb::test::locomotive::until {[string first "< bestmove" $::scidb::test::locomotive::log] >= 0}]
    ::scidb::test::locomotive::wait 200
    set stopped [::application::analysis::lines $number]
    set ::scidb::test::locomotive::log {}
    ::scidb::test::locomotive::wait 1200
    list $fresh $::scidb::test::locomotive::setupOpened \
        [expr {$engine(engine:name) eq $name}] $updating $answered \
        [::engine::active? $number] $pane(engine:stopped) \
        [expr {[llength $stopped] > 0 && $stopped eq [::application::analysis::lines $number]}] \
        [expr {[string first "< info " $::scidb::test::locomotive::log] == -1}] \
        $tipText
} -cleanup {
    catch {after cancel $watchdog}
    ::application::analysis::stopEngine $number
    ::scidb::test::locomotive::wait 100
    # Do not leave the explicit reopen override behind for the rest of the
    # single-process suite (the pane is engine-empty now).
    catch { set ::application::reflow::S(override) {} }
    catch { ::application::reflow::updateCollapse }
    # Closing hides the lines but retains their cached values. Remove the
    # lines produced by this test before testing another fresh start.
    array unset pane lines:*
    catch {::scidb::engine::log close}
    array unset engine
    array set engine $savedEngine
    file delete -force $::scidb::file::engines
    set ::engine::Engines $savedEngines
    set ::scidb::file::engines $savedFile
    set ::engine::Options(engine) $savedDefault
    set ::application::assistant::Priv(confirm) $savedConfirm
    ::options::hookWriter ::engine::WriteEngineOptions engines
} -result {{0 disabled 0} 0 1 1 1 1 1 1 1 {Start engine}}
}
} ;# namespace ::scidb::test::locomotive

tcltest::cleanupTests
