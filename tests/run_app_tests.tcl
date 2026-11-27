#!/usr/bin/env tclsh

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::app {
    variable testDir [file dirname [file normalize [info script]]]
    variable rootDir [file dirname $testDir]
    # A second runner (a single-file repro beside a full run) must not
    # overwrite the report the first one is still writing.
    variable reportFile [expr {
        [info exists ::env(SCIDB_APP_TEST_REPORT)]
            ? $::env(SCIDB_APP_TEST_REPORT)
            : [file join $testDir app_test_report.txt]
    }]
    variable totalPass 0
    variable totalFail 0
    variable totalSkip 0
    variable reportHandle {}
}

# Test files locate support modules and fixtures from the repository root
# (``tests/...``).  The Makefile starts this runner with -C tests, while CI
# users may start it from the root; use one directory for both.
cd $::scidb::test::app::rootDir

# Placement fixtures must fit the current display, including WM decorations.
# Requested sizes retain the regression scenario on larger displays.
proc ::scidb::test::app::fitGeometry {width height} {
    lassign [winfo workarea .application] x y w h
    lassign [winfo extents .application] l r t b
    return "[expr {min($width,$w-$l-$r)}]x[expr {min($height,$h-$t-$b)}]+$x+$y"
}

proc ::scidb::test::app::emit {line} {
    variable reportHandle
    puts $line
    flush stdout
    puts $reportHandle $line
    flush $reportHandle
}

# Report the state a test file leaves behind.  A file that leaves game slots
# occupied (the app has only nine), opens databases it does not close, leaves
# after-handlers running or a grab held is not order-independent: the files
# that follow can then fail though they pass alone.  This is a report, not a
# reset -- the leaks are fixed where they are made.
# Files share one process and nine game slots.  Once the action-probe support
# module is loaded, use its process-wide reset (bases, slots, cards, engines,
# pane arrangement) after every file; before that, at least power down engines
# and drain the idle callbacks they leave behind.  A stopped engine's deferred
# callback firing inside the next file's native engine start aborts the whole
# suite, and panes a file left open decide the window minimum the next file
# measures.
proc ::scidb::test::app::settle {} {
    # A file may put the dialogs in non-interactive mode for a headless batch.
    # That mode answers every question with its safe reply, so leaving it on
    # refuses the next file's confirmation (resign, close, overwrite) without
    # showing anything.
    if {[info exists ::scidb::test::app::nonInteractiveDefault]
     && [llength [info commands ::dialog::nonInteractive]]
     && [::dialog::nonInteractive] ne $::scidb::test::app::nonInteractiveDefault} {
        catch { ::dialog::nonInteractive $::scidb::test::app::nonInteractiveDefault }
    }
    if {[llength [info commands ::scidb::test::actions::release]]} {
        catch { ::scidb::test::actions::release }
        # Panes, reopen overrides and maximised layouts also outlive a file:
        # the window minimum and board size they leave decide what the next
        # file can measure. Put the fresh-start arrangement back.
        # A file which maximised the window for a full-screen scenario must
        # not hand that surface (or a zoomed state) to the next file, which
        # measures the fresh-start one.
        catch { ::scidb::test::actions::restoreStartupWindow }
        catch { ::scidb::test::actions::restoreStartupArrangement }
        return
    }
    catch {
        foreach number [array names ::application::analysis::NumberToTree] {
            catch { ::engine::kill $number }
        }
        update
    }
}

# The action registry is process-wide, and several files register sample
# actions from their ``-setup`` blocks (test.bar.game, test.args.req, ...).
# Those are fixtures for the file that makes them: leaving them registered
# hands later files a registry the product never has, which changes the
# derived knowledge pack (its registry hash and record count) and every
# surface that enumerates actions. Drop what a file added; never touch a
# record the file merely edited in place.
proc ::scidb::test::app::settleRegistry {baseline} {
    if {![llength [info commands ::action::list]]} { return {} }
    set removed {}
    foreach id [::action::list] {
        if {$id ni $baseline} {
            catch { ::action::Unregister $id }
            lappend removed $id
        }
    }
    return $removed
}

proc ::scidb::test::app::checkCleanup {file} {
    set slots {}
    catch { set slots [::game::gameList] }
    set occupied {}
    foreach entry $slots {
        if {[lindex $entry 0] ne ""} { lappend occupied $entry }
    }
    set bases {}
    catch { set bases [$::application::database::Vars(switcher) bases] }
    set leaked {}
    foreach b $bases {
        catch {
            if {$b ne $::scidb::clipbaseName} { lappend leaked $b }
        }
    }
    set afters {}
    catch { set afters [after info] }
    set grab {}
    catch { set grab [grab current] }
    ::scidb::test::app::emit [format "  cleanup [file tail $file]: slots=%d bases=%s afters=%s grab={%s}" \
        [llength $occupied] \
        [expr {[llength $leaked] ? $leaked : "none"}] \
        [expr {[llength $afters] ? $afters : "none"}] \
        $grab]
}

set argvCopy $argv
set argcCopy $argc
# --single-process: no single-instance check, so test runs (several at a
# time, or beside a running Scidb) do not hand off to each other and exit
set argv {--single-process}
set argc 1
# errors raised by the tests go to a scratch log, not the user's
set ::env(SCIDB_ERROR_LOG) [file join $::scidb::test::app::testDir tmp-app errors-[pid].log]
# nor to the model: triage runs only where a test asks for it
set ::env(SCIDB_AI_TRIAGE) 0
# and no System One classifier unless a test points at its own
set ::env(SCIDB_AI_CLASSIFIER) off
# the classifier tests stub a backend that has no calibration, as
# tests/Makefile does; systemone-qualified tests the gate with this unset
if {![info exists ::env(SCIDB_AI_UNCALIBRATED)]} { set ::env(SCIDB_AI_UNCALIBRATED) 1 }
source [file join $::scidb::test::app::testDir no_open_stub.tcl]
source -encoding utf-8 [file join $::scidb::test::app::testDir .. tcl chesswiz]
# The action-probe files load this themselves for their own cleanup. Source it
# once here as well: settle below then resets the process the same way whether
# or not one of those files has already run, instead of leaving the first
# files in a run to leak games, trial mode and a moved board into later ones.
source [file join $::scidb::test::app::testDir app_actions_support.tcl]

# A fresh user directory (CI) is a first run, whose language chooser waits for
# a click; the tests are not one. Startup2 has not run yet: it is a timer.
set ::scidb::dir::setup 0
set argv $argvCopy
set argc $argcCopy

set matchPattern "*"
set verbose 0
set filePattern "test_app_*.tcl"
set shard ""

for {set i 0} {$i < [llength $argv]} {incr i} {
    switch -glob -- [lindex $argv $i] {
        -match { incr i; set matchPattern [lindex $argv $i] }
        -file { incr i; set filePattern [lindex $argv $i] }
        -shard { incr i; set shard [lindex $argv $i] }
        -verbose { set verbose 1 }
        -help {
            puts "Usage: tests/run_app_tests.tcl [-match PATTERN] [-file GLOB] [-shard K/N] [-verbose]"
            catch { destroy .application }
            catch { destroy . }
            return
        }
    }
}

set testFiles [lsort [glob -nocomplain -directory $::scidb::test::app::testDir $filePattern]]
# -shard K/N (1 <= K <= N): every Nth file from the K-th, for parallel CI jobs.
if {$shard ne ""} {
    if {![regexp {^([0-9]+)/([0-9]+)$} $shard -> shardK shardN] || $shardK < 1 || $shardK > $shardN} {
        error "-shard wants K/N with 1 <= K <= N, got \"$shard\""
    }
    set picked {}
    for {set j [expr {$shardK - 1}]} {$j < [llength $testFiles]} {incr j $shardN} { lappend picked [lindex $testFiles $j] }
    set testFiles $picked
}

set ::scidb::test::app::reportHandle [open $::scidb::test::app::reportFile w]

if {[llength $testFiles] == 0} {
    ::scidb::test::app::emit "ERROR: No app-backed test files found"
    catch { close $::scidb::test::app::reportHandle }
    catch { destroy .application }
    catch { destroy . }
    return
}

::scidb::test::app::emit "=============================================="
::scidb::test::app::emit "  Scidb App Test Suite"
::scidb::test::app::emit "=============================================="
::scidb::test::app::emit "Test directory: $::scidb::test::app::testDir"
::scidb::test::app::emit "Match pattern: $matchPattern"
::scidb::test::app::emit ""

rename exit ::scidb::test::app::_real_exit
proc exit {{code 0}} {}

rename tcltest::cleanupTests tcltest::_cleanupTests
proc tcltest::cleanupTests {args} {
    variable numTests
    incr ::scidb::test::app::totalPass $numTests(Passed)
    incr ::scidb::test::app::totalFail $numTests(Failed)
    incr ::scidb::test::app::totalSkip $numTests(Skipped)
    tailcall tcltest::_cleanupTests {*}$args
}

set startTime [clock seconds]

# The window a fresh start opens, before any file resizes it; settle puts it
# back after every file. Wait only for the window itself: the startup
# callbacks are still ahead, and a file which tests them must still see them.
set mapDeadline [expr {[clock milliseconds] + 10000}]
while {[winfo width .application] <= 1 && [clock milliseconds] < $mapDeadline} {
    after 10
    update
}
catch { ::scidb::test::actions::rememberStartupWindow }
# The dialog mode a first run has; settle restores it after every file.
set ::scidb::test::app::nonInteractiveDefault [::dialog::nonInteractive]
# The registry the product starts with; settleRegistry restores it per file.
::scidb::test::app::settle
set ::scidb::test::app::registryBaseline [::action::list]

foreach testFile $testFiles {
    ::scidb::test::app::emit "\n=== Running [file tail $testFile] ==="

    # Some files import the whole tcltest namespace.  An import left by an
    # earlier file points at the superseded cleanup command, which makes a
    # second import fail; refresh the global link to the current wrapper.
    catch { rename ::cleanupTests {} }
    namespace import ::tcltest::cleanupTests

    tcltest::configure -match $matchPattern
    if {$verbose} {
        tcltest::configure -verbose {pass body error}
    } else {
        tcltest::configure -verbose {error}
    }

    # A file that reads the language files it is about to commit points
    # ::scidb::dir::share at the worktree's tcl/. That redirect holds the
    # language catalogs only, not the installed layout every other file
    # expects (sample/, scripts/, themes/, images/). Put the installed share
    # back after each file, even one which fails half-way through.
    set shareBefore $::scidb::dir::share
    # A file's top-level foreach/lassign writes globals.  Namespace scripts
    # evaluated at the global level resolve an unqualified name to an existing
    # global first, so an earlier file's leftover ``kind`` (or ``id``, ``name``)
    # silently redirects a later file's namespace loop variable to ``::`` and
    # its own namespace reads then fail.  A file may create globals; it may not
    # hand them to the next file.  Keep the ones that were already here.
    set globalsBefore [concat [info vars] {globalsBefore leaked}]
    set rc [catch {source -encoding utf-8 $testFile} err opts]
    if {[info exists ::scidb::dir::share] && $::scidb::dir::share ne $shareBefore} {
        set ::scidb::dir::share $shareBefore
    }
    if {$rc} {
        ::scidb::test::app::emit "ERROR in [file tail $testFile]: $err"
        incr ::scidb::test::app::totalFail 1
    }
    ::scidb::test::app::settle
    # A test body runs in the global frame, so a ``namespace upvar`` there
    # creates a *link* in ``::`` to a live application variable.  Unsetting a
    # link unsets the variable it points at, not the link: dropping the
    # suite's ``Vars``/``engine`` links would wipe the analysis pane and the
    # engine arrays mid-run.  The leaks this removes are the scalars a
    # top-level foreach/lassign leaves behind, so only scalars are dropped.
    foreach leaked [info vars] {
        if {$leaked ni $globalsBefore && ![array exists ::$leaked]} {
            catch { unset ::$leaked }
        }
    }
    set fixtureActions [::scidb::test::app::settleRegistry $::scidb::test::app::registryBaseline]
    if {[llength $fixtureActions]} {
        ::scidb::test::app::emit [format "  unregistered %d fixture action(s): %s" \
            [llength $fixtureActions] [join $fixtureActions {, }]]
    }
    catch { ::scidb::test::app::checkCleanup $testFile }
}

set duration [expr {[clock seconds] - $startTime}]

::scidb::test::app::emit "\n=============================================="
::scidb::test::app::emit "  App Test Results Summary"
::scidb::test::app::emit "=============================================="
::scidb::test::app::emit "Total Passed: $::scidb::test::app::totalPass"
::scidb::test::app::emit "Total Failed: $::scidb::test::app::totalFail"
::scidb::test::app::emit "Total Skipped: $::scidb::test::app::totalSkip"
::scidb::test::app::emit "Duration: ${duration}s"
::scidb::test::app::emit ""

if {$::scidb::test::app::totalFail > 0} {
    ::scidb::test::app::emit "STATUS: FAILED"
} elseif {$::scidb::test::app::totalPass == 0} {
    ::scidb::test::app::emit "STATUS: NO TESTS RUN"
} else {
    ::scidb::test::app::emit "STATUS: PASSED"
}

catch { close $::scidb::test::app::reportHandle }
catch { destroy .application }
catch { destroy . }
if {[info commands ::scidb::test::app::_real_exit] ne ""} {
    ::scidb::test::app::_real_exit [expr {$::scidb::test::app::totalFail > 0 ? 1 : 0}]
}
