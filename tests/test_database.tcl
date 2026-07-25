# ======================================================================
# Scidb Test Suite - Database Operations
# Tests for: app-database.tcl, db API wrappers
# Note: These tests require the full Scidb application
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

source [file join [file dirname [file normalize [info script]]] test_framework.tcl]

namespace eval ::scidb::test {

setup

# Check if Scidb is available
set scidbAvailable [expr {[info commands ::scidb::db::create] ne ""}]
tcltest::testConstraint scidbAvailable $scidbAvailable

if {!$scidbAvailable} {
    puts "  NOTE: Scidb application not loaded - database tests will be skipped individually"
}

# ==============================================================================
# Database Creation Tests
# ==============================================================================

tcltest::test db-create-01 {Create new database} -constraints scidbAvailable -setup {
    variable testDb
    variable tmpDir
    set testDb [file join $tmpDir test_create_[clock seconds].sci]
} -body {
    set result [::scidb::db::create $testDb]
    set created [file exists $testDb]
    expr {$result == 0 && $created}
} -cleanup {
    variable testDb
    catch { ::scidb::db::close $testDb }
    catch { file delete -force $testDb }
    catch { file delete -force "${testDb}.sci3" }
} -result 1

tcltest::test db-create-duplicate-02 {Prevent duplicate database names} -constraints scidbAvailable -setup {
    variable testDb
    variable tmpDir
    set testDb [file join $tmpDir test_dup_[clock seconds].sci]
    ::scidb::db::create $testDb
} -body {
    set result [catch {::scidb::db::create $testDb} err]
    expr {$result != 0}
} -cleanup {
    variable testDb
    catch { ::scidb::db::close $testDb }
    catch { file delete -force $testDb }
    catch { file delete -force "${testDb}.sci3" }
} -result 1

# ==============================================================================
# Database Open/Close Tests
# ==============================================================================

tcltest::test db-open-01 {Open existing database} -constraints scidbAvailable -setup {
    variable testDb
    variable tmpDir
    set testDb [file join $tmpDir test_open_[clock seconds].sci]
    ::scidb::db::create $testDb
} -body {
    set result [::scidb::db::open $testDb]
    set isOpen [::scidb::db::get open? $testDb]
    expr {$result == 0 && $isOpen}
} -cleanup {
    variable testDb
    catch { ::scidb::db::close $testDb }
    catch { file delete -force $testDb }
    catch { file delete -force "${testDb}.sci3" }
} -result 1

tcltest::test db-close-02 {Close database} -constraints scidbAvailable -setup {
    variable testDb
    variable tmpDir
    set testDb [file join $tmpDir test_close_[clock seconds].sci]
    ::scidb::db::create $testDb
    ::scidb::db::open $testDb
} -body {
    ::scidb::db::close $testDb
    set isClosed [expr {![::scidb::db::get open? $testDb]}]
    set isClosed
} -cleanup {
    variable testDb
    catch { file delete -force $testDb }
    catch { file delete -force "${testDb}.sci3" }
} -result 1

tcltest::test db-open-nonexistent-03 {Fail on nonexistent database} -constraints scidbAvailable -body {
    variable tmpDir
    set path [file join $tmpDir nonexistent_[clock seconds].sci]
    set result [catch {::scidb::db::open $path} err]
    expr {$result != 0}
} -result 1

# ==============================================================================
# Game Import Tests
# ==============================================================================

tcltest::test db-import-pgn-01 {Import PGN file} -constraints scidbAvailable -setup {
    variable testDb
    variable tmpDir
    set testDb [file join $tmpDir test_import_[clock seconds].sci]
    ::scidb::db::create $testDb
    ::scidb::db::open $testDb
} -body {
    set pgnFile [createTestPgn]
    set result [::scidb::db::importPgn $testDb $pgnFile]
    set count [::scidb::db::count games $testDb]
    expr {$result == 0 && $count == 3}
} -cleanup {
    variable testDb
    catch { ::scidb::db::close $testDb }
    catch { file delete -force $testDb }
    catch { file delete -force "${testDb}.sci3" }
} -result 1

# ==============================================================================
# Cleanup
# ==============================================================================

cleanup
tcltest::cleanupTests

} ;# namespace ::scidb::test
