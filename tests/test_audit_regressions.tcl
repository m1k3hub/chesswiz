# ======================================================================
# Audit Regression Tests
# These tests encode verified intended behavior from the 2026-04-09 audit.
# They are expected to fail until the underlying defects are fixed.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test {

variable repoRoot [file dirname [file dirname [file normalize [info script]]]]
variable testsDir [file join $repoRoot tests]
variable srcDir [file join $repoRoot src]

proc slurp {path} {
    set fd [open $path r]
    set data [read $fd]
    close $fd
    return $data
}

tcltest::test audit-export-html-enabled-01 {HTML export should not be unconditionally blocked} -body {
    variable repoRoot
    set exportScript [slurp [file join $repoRoot tcl export.tcl]]
    expr {![regexp {html\s*\{\s*return\s+\[::beta::notYetImplemented} $exportScript]}
} -result 1

tcltest::test audit-export-pdf-enabled-02 {PDF export should not be unconditionally blocked} -body {
    variable repoRoot
    set exportScript [slurp [file join $repoRoot tcl export.tcl]]
    expr {![regexp {pdf\s*\{\s*return\s+\[::beta::notYetImplemented} $exportScript]}
} -result 1

tcltest::test audit-cpp-test-banner-valid-03 {C++ backend test file should begin with legal C++ comments} -body {
    variable testsDir
    set lines [split [slurp [file join $testsDir test_cpp_backend.cpp]] "\n"]
    set first [string trim [lindex $lines 0]]
    expr {![string match "# *" $first]}
} -result 1

tcltest::test audit-cpp-test-syntax-04 {C++ backend test file should pass syntax-only compilation} -body {
    variable repoRoot
    if {![llength [info commands ::util::execSafe]]} {
        set _sysPlatform [file normalize [file join $repoRoot tcl sys-platform.tcl]]
        if {[file exists $_sysPlatform]} { catch { source -encoding utf-8 $_sysPlatform } }
    }
    if {[catch {::util::execSafe g++ --version}]} {
        return 1
    }
    set testFile [file join $repoRoot tests test_cpp_backend.cpp]
    set cmd [list g++ -std=c++17 -Wall -Wextra -fsyntax-only \
        -I[file join $repoRoot src] \
        -I[file join $repoRoot src db] \
        -I[file join $repoRoot src sys] \
        -I[file join $repoRoot src util] \
        -I[file join $repoRoot src mstl] \
        -I/usr/include/tcl8.6 \
        $testFile]
    set rc [catch {::util::execSafe {*}$cmd} output]
    if {$rc} {
        puts stderr $output
    }
    expr {$rc == 0}
} -result 1

tcltest::test audit-make-cpp-target-05 {Documented C++ test target should work from tests directory} -body {
    variable repoRoot
    if {[catch {::util::execSafe make --version}]} {
        return 1
    }
    # -ignorestderr: the corr-duration truncation tests throw on purpose and
    # the exception logger writes to stderr; only the exit status matters here
    set rc [catch {::util::execSafe -ignorestderr make -C [file join $repoRoot tests] cpp} output]
    if {$rc} {
        puts stderr $output
    }
    expr {$rc == 0}
} -result 1

tcltest::test audit-db-tests-load-framework-06 {Database tests should load shared framework or define its helpers locally} -body {
    variable testsDir
    set script [slurp [file join $testsDir test_database.tcl]]
    set hasSource [regexp {source\s+.*test_framework\.tcl} $script]
    set hasTmpDir [regexp {variable\s+tmpDir\s+\[file join} $script]
    set hasCreateHelper [regexp {proc\s+createTestPgn\s+} $script]
    expr {$hasSource || ($hasTmpDir && $hasCreateHelper)}
} -result 1

tcltest::test audit-db-tests-not-fully-skipped-07 {Database test file should not opt out wholesale when db commands are absent} -body {
    variable testsDir
    set script [slurp [file join $testsDir test_database.tcl]]
    expr {![regexp {tcltest::configure\s+-match\s+none} $script]}
} -result 1

tcltest::cleanupTests

} ;# namespace ::scidb::test
