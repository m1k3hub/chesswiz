# The setup dialog and the Assistant path must stay usable while the Analysis
# pane streams four UCI lines. Opening Play shuts down analysis first;
# the Play transport stays lazy until Start.
package require tcltest 2.5
namespace eval ::scidb::test::playanalysis {}
proc ::scidb::test::playanalysis::wait {ms} {
    set ::scidb::test::playanalysis::wake 0
    after $ms {set ::scidb::test::playanalysis::wake 1}
    vwait ::scidb::test::playanalysis::wake
}
set ::scidb::test::playanalysis::program {}
foreach path {/usr/games/stockfish /usr/local/games/stockfish-chesswiz} {
    if {[file executable $path]} {
        set ::scidb::test::playanalysis::program $path
        break
    }
}
tcltest::testConstraint playAnalysisEngine [expr {$::scidb::test::playanalysis::program ne {}}]
foreach route {direct assistant} {
    tcltest::test play-analysis-$route {Play stops analysis, timer fires and Cancel closes} \
    -constraints playAnalysisEngine -setup {
        set timer {}
        ::application::switchTab board
        update idletasks
        set savedEngines $::engine::Engines
        set ::engine::Engines [list [dict merge $::engine::EmptyEngine [list \
            Name PlayAnalysisStockfish Command $::scidb::test::playanalysis::program \
            Protocol UCI Profiles:UCI {Default {}} Features:UCI {analyze true multiPV 256 threads {1 1024} hashSize {1 33554432}}]]]
        set number [::application::analysis::startEngine PlayAnalysisStockfish 1 {lines 4 threads 1 hash 16}]
        set deadline [expr {[clock milliseconds]+10000}]
        while {[llength [::application::analysis::lines $number]] < 4 && [clock milliseconds] < $deadline} {
            ::scidb::test::playanalysis::wait 25
        }
    } -body {
        set count [llength [::application::analysis::lines $number]]
        set ::scidb::test::playanalysis::tick 0
        set started [clock milliseconds]
        set timer [after 50 {set ::scidb::test::playanalysis::tick [clock milliseconds]}]
        if {$route eq "direct"} {
            ::playengine::open .application
        } else {
            ::application::assistant::runTool open_play_engine {color black}
        }
        ::scidb::test::playanalysis::wait 250
        set alive [expr {$::scidb::test::playanalysis::tick > 0 && $::scidb::test::playanalysis::tick-$started < 500}]
        puts "EVIDENCE play-analysis-$route tickMs=[expr {$::scidb::test::playanalysis::tick-$started}]"
        set dialog [winfo exists .application.playengine]
        set pipe $::playengine::Priv(pipe)
        [::util::place::playingBody .application.playengine].cancel invoke
        ::scidb::test::playanalysis::wait 100
        list $count $alive $dialog $pipe [winfo exists .application.playengine] \
            [::application::analysis::active? $number]
    } -cleanup {
        after cancel $timer
        catch {::playengine::Close}
        ::application::analysis::stopEngine $number
        ::scidb::test::playanalysis::wait 100
        set ::engine::Engines $savedEngines
    } -result {4 1 1 {} 0 0}
}
# Even a UCI process that ignores stop/quit must not make opening Play wait
# for process exit. This fixture exits itself after 20 seconds if shutdown
# accidentally regresses to a blocking close.
tcltest::test play-analysis-hung {Play closes all analysis engines without waiting for a hung child} \
-constraints unix -setup {
    set timer {}
    ::application::switchTab board
    update idletasks
    set savedEngines $::engine::Engines
    set fixture [file join [file dirname [info script]] fixtures fake-uci-hung.tcl]
    set ::engine::Engines [list [dict merge $::engine::EmptyEngine [list \
        Name PlayAnalysisHung Command $fixture Protocol UCI Profiles:UCI {Default {}} \
        Features:UCI {analyze true multiPV 8}]]]
    set numbers {}
    foreach number {1 2} {
        lappend numbers [::application::analysis::startEngine PlayAnalysisHung $number {lines 4}]
    }
    set deadline [expr {[clock milliseconds]+5000}]
    foreach number $numbers {
        while {[llength [::application::analysis::lines $number]] < 4 && [clock milliseconds] < $deadline} {
            ::scidb::test::playanalysis::wait 25
        }
    }
} -body {
    set before [llength [::application::analysis::Running]]
    set counts [lmap number $numbers {llength [::application::analysis::lines $number]}]
    set ::scidb::test::playanalysis::tick 0
    set started [clock milliseconds]
    set timer [after 50 {set ::scidb::test::playanalysis::tick [clock milliseconds]}]
    ::application::assistant::runTool open_play_engine {color black}
    ::scidb::test::playanalysis::wait 100
    set alive [expr {$::scidb::test::playanalysis::tick-$started < 500 && $::scidb::test::playanalysis::tick > 0}]
    set color $::playengine::Priv(dlg:color)
    [::util::place::playingBody .application.playengine].cancel invoke
    puts "EVIDENCE play-analysis-hung tickMs=[expr {$::scidb::test::playanalysis::tick-$started}]"
    list $before $counts $alive $color [::application::analysis::Running] [winfo exists .application.playengine]
} -cleanup {
    after cancel $timer
    catch {::playengine::Close}
    foreach number $numbers {::application::analysis::stopEngine $number}
    ::scidb::test::playanalysis::wait 100
    set ::engine::Engines $savedEngines
    # This test created a second analysis pane; leave the original one alone.
    catch {
        set twm $::application::Vars(board:twm)
        $twm close [$twm leaf analysis:[::application::mapToTerminalNumber 2]]
    }
} -result {2 {4 4} 1 black {} 0}

tcltest::cleanupTests
