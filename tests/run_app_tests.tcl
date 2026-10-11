#!/usr/bin/env tclsh

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::app {
    variable testDir [file dirname [file normalize [info script]]]
    variable reportFile [file join $testDir app_test_report.txt]
    variable totalPass 0
    variable totalFail 0
    variable totalSkip 0
    variable reportHandle {}
}

proc ::scidb::test::app::emit {line} {
    variable reportHandle
    puts $line
    flush stdout
    puts $reportHandle $line
    flush $reportHandle
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
source [file join $::scidb::test::app::testDir .. tcl chesswiz]
# A fresh user directory (CI) is a first run, whose language chooser waits for
# a click; the tests are not one. Startup2 has not run yet: it is a timer.
set ::scidb::dir::setup 0
set argv $argvCopy
set argc $argcCopy

set matchPattern "*"
set verbose 0

for {set i 0} {$i < [llength $argv]} {incr i} {
    switch -glob -- [lindex $argv $i] {
        -match { incr i; set matchPattern [lindex $argv $i] }
        -verbose { set verbose 1 }
        -help {
            puts "Usage: tests/run_app_tests.tcl [-match PATTERN] [-verbose]"
            catch { destroy .application }
            catch { destroy . }
            return
        }
    }
}

set testFiles [lsort [glob -nocomplain -directory $::scidb::test::app::testDir test_app_*.tcl]]

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

foreach testFile $testFiles {
    ::scidb::test::app::emit "\n=== Running [file tail $testFile] ==="

    tcltest::configure -match $matchPattern
    if {$verbose} {
        tcltest::configure -verbose {pass body error}
    } else {
        tcltest::configure -verbose {error}
    }

    set rc [catch {source $testFile} err opts]
    if {$rc} {
        ::scidb::test::app::emit "ERROR in [file tail $testFile]: $err"
        incr ::scidb::test::app::totalFail 1
    }
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
