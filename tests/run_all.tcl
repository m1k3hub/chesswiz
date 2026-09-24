#!/usr/bin/env tclsh
# ======================================================================
# Scidb Test Suite - Main Runner
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test {
    variable testDir [file dirname [file normalize [info script]]]
    variable totalPass 0
    variable totalFail 0
    variable totalSkip 0
}

# Parse command line
set matchPattern "*"
set verbose 0

for {set i 0} {$i < [llength $argv]} {incr i} {
    switch -glob -- [lindex $argv $i] {
        -match { incr i; set matchPattern [lindex $argv $i] }
        -verbose { set verbose 1 }
        -help {
            puts "Usage: tclsh tests/run_all.tcl [-match PATTERN] [-verbose]"
            exit 0
        }
    }
}

# Create temp directory
file mkdir [file join $::scidb::test::testDir tmp]

puts "=============================================="
puts "  Scidb Test Suite"
puts "=============================================="
puts "Test directory: $::scidb::test::testDir"
puts "Match pattern: $matchPattern"
puts ""

# Discover test files (exclude test_framework.tcl which is a utility, not a test)
set testFiles [glob -nocomplain -directory $::scidb::test::testDir test_*.tcl]
set testFiles [lsearch -inline -all -not -exact $testFiles \
    [file join $::scidb::test::testDir test_framework.tcl]]
set testFiles [lsearch -inline -all -not -glob $testFiles \
    [file join $::scidb::test::testDir test_app_*.tcl]]
# AI grounding suites need the tkscidb shell (app-only ::scidb::ai::* commands) and
# use their own pass/fail harness, so they are not runnable under plain tclsh.
# They are exercised by the tests/Makefile `ai-tests` group instead.
set testFiles [lsearch -inline -all -not -glob $testFiles \
    [file join $::scidb::test::testDir test_ai_*.tcl]]

if {[llength $testFiles] == 0} {
    puts "ERROR: No test files found"
    exit 1
}

puts "Found [llength $testFiles] test file(s):"
foreach f $testFiles { puts "  - [file tail $f]" }
puts ""

# Prevent test files (especially those that load Tk) from exiting the master runner.
# tcltest::cleanupTests calls [exit] when ::tk_version exists and not in interactive
# mode. We intercept exit here and capture per-file stats before cleanupTests resets them.
rename exit ::scidb::test::_real_exit
proc exit {{code 0}} {}

rename tcltest::cleanupTests tcltest::_cleanupTests
proc tcltest::cleanupTests {args} {
    variable numTests
    incr ::scidb::test::totalPass $numTests(Passed)
    incr ::scidb::test::totalFail $numTests(Failed)
    incr ::scidb::test::totalSkip $numTests(Skipped)
    tailcall tcltest::_cleanupTests {*}$args
}

# Run tests
set startTime [clock seconds]

foreach testFile $testFiles {
    puts "\n=== Running [file tail $testFile] ==="
    
    # Configure tcltest
    tcltest::configure -match $matchPattern
    if {$verbose} {
        tcltest::configure -verbose {pass body error}
    } else {
        tcltest::configure -verbose {error}
    }
    
    # Source and run test file (each file calls tcltest::cleanupTests itself)
    try {
        source $testFile
    } on error {err} {
        puts "ERROR in [file tail $testFile]: $err"
        incr ::scidb::test::totalFail 1
    }
}

set endTime [clock seconds]
set duration [expr {$endTime - $startTime}]

# Cleanup temp
catch { file delete -force [file join $::scidb::test::testDir tmp] }

# Summary
puts "\n=============================================="
puts "  Test Results Summary"
puts "=============================================="
puts "Total Passed: $::scidb::test::totalPass"
puts "Total Failed: $::scidb::test::totalFail"
puts "Total Skipped: $::scidb::test::totalSkip"
puts "Duration: ${duration}s"
puts ""

rename exit {}
rename ::scidb::test::_real_exit exit

if {$::scidb::test::totalFail > 0} {
    puts "STATUS: FAILED"
    exit 1
} elseif {$::scidb::test::totalPass == 0} {
    puts "STATUS: NO TESTS RUN"
    exit 0
} else {
    puts "STATUS: PASSED"
    exit 0
}
