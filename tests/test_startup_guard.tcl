# ======================================================================
# Chesswiz Startup Guard Unit Tests (Gap G04)
# ======================================================================
# Tests that startup fails only on truly fatal conditions (cannot load
# Tk / core packages) with a clear message naming what is missing,
# while recoverable conditions (missing optional package, slow probe,
# unusual path, non-ASCII path, read-only install dir, Windows/macOS layouts,
# empty nameofexecutable probe) log a warning to ::debuglog::log startup
# and continue.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::test_startup_guard {
    variable repoRoot [file normalize [file join [file dirname [info script]] ..]]
    variable execTcl [file join $repoRoot tcl exec.tcl]
    variable loggedStartupWarnings {}
    variable fatalMessages {}
    variable tempDirs {}
}

# Source exec.tcl in test mode so we have the startup procedures
namespace eval ::scidb::startup {
    variable testing 1
}

# Capture ::debuglog::log calls
namespace eval ::debuglog {
    variable queue {}
    proc log {category message} {
        if {$category eq "startup"} {
            lappend ::test_startup_guard::loggedStartupWarnings $message
        }
    }
}

# Load the startup definitions from tcl/exec.tcl
if {[catch { source $::test_startup_guard::execTcl } err]} {
    # If exec.tcl executes whole file at top-level, catch it
}

proc ::test_startup_guard::resetLogs {} {
    set ::test_startup_guard::loggedStartupWarnings {}
    set ::test_startup_guard::fatalMessages {}
}

proc ::test_startup_guard::hasWarningMatch {pattern} {
    foreach line $::test_startup_guard::loggedStartupWarnings {
        if {[string match $pattern $line]} { return 1 }
    }
    return 0
}

# ----------------------------------------------------------------------
# 1. TRULY FATAL: Missing core packages
# ----------------------------------------------------------------------
tcltest::test fatal-missing-core-package {Missing core package must refuse launch with clear message naming what is missing} -body {
    ::test_startup_guard::resetLogs
    set code [catch {
        ::scidb::startup::loadCorePackage __nonexistent_core_pkg_g04__ 9.9
    } err opts]
    set errCode [dict get $opts -errorcode]
    list $code [lindex $errCode 0] [lindex $errCode 1] [string match "*__nonexistent_core_pkg_g04__*" $err]
} -result {1 SCIDB STARTUP_FATAL 1}

tcltest::test fatal-missing-tk {Failure to load Tk must refuse launch with clear message} -body {
    ::test_startup_guard::resetLogs
    set code [catch {
        ::scidb::startup::loadCorePackage __fake_tk_unresolvable__ 99.0
    } err opts]
    set errCode [dict get $opts -errorcode]
    list $code [lindex $errCode 0] [lindex $errCode 1] [string match "*__fake_tk_unresolvable__*" $err]
} -result {1 SCIDB STARTUP_FATAL 1}

# ----------------------------------------------------------------------
# 2. RECOVERABLE: Missing optional package
# ----------------------------------------------------------------------
tcltest::test recoverable-missing-optional-package {Missing optional package must log warning and continue without throwing} -body {
    ::test_startup_guard::resetLogs
    set res [::scidb::startup::checkOptionalPackage __nonexistent_opt_pkg_g04__]
    list $res [::test_startup_guard::hasWarningMatch "*optional package '__nonexistent_opt_pkg_g04__'*"]
} -result {0 1}

# ----------------------------------------------------------------------
# 3. RECOVERABLE: Empty nameofexecutable probe (Gap G04 root cause)
# ----------------------------------------------------------------------
tcltest::test recoverable-empty-nameofexecutable {Empty nameofexecutable probe falls back gracefully and does not abort} -body {
    ::test_startup_guard::resetLogs
    set exe [::scidb::startup::probeExecutable -path ""]
    # Should resolve to a non-empty fallback path (e.g. tkchesswiz)
    set nonBlank [expr {[string trim $exe] ne ""}]
    set logged [::test_startup_guard::hasWarningMatch "*info nameofexecutable was empty*"]
    if {!$logged} {
        set logged [::test_startup_guard::hasWarningMatch "*executable path probe returned empty*"]
    }
    list $nonBlank $logged
} -result {1 1}

# ----------------------------------------------------------------------
# 4. RECOVERABLE: Slow probe
# ----------------------------------------------------------------------
tcltest::test recoverable-slow-probe {A slow probe logs warning and continues} -body {
    ::test_startup_guard::resetLogs
    # Simulate a probe that takes 260ms
    set exe [::scidb::startup::probeExecutable -delay 260 -path "/usr/local/bin/tkchesswiz"]
    list [file tail $exe] [::test_startup_guard::hasWarningMatch "*slow probe*"]
} -result {tkchesswiz 1}

# ----------------------------------------------------------------------
# 5. RECOVERABLE: Unusual path (spaces, brackets, symbols)
# ----------------------------------------------------------------------
tcltest::test recoverable-unusual-path {Unusual path with spaces and special symbols logs warning and normalizes cleanly} -body {
    ::test_startup_guard::resetLogs
    set unusualPath {/opt/Chess [v1.0] #test & games/tkchesswiz}
    set exe [::scidb::startup::probeExecutable -path $unusualPath]
    list [expr {[string first {Chess [v1.0]} $exe] >= 0}] [::test_startup_guard::hasWarningMatch "*unusual path detected*"]
} -result {1 1}

# ----------------------------------------------------------------------
# 6. RECOVERABLE: Non-ASCII path (accents, umlauts)
# ----------------------------------------------------------------------
tcltest::test recoverable-non-ascii-path {Non-ASCII path with umlauts logs warning and continues} -body {
    ::test_startup_guard::resetLogs
    set umlautPath "/tmp/cwexplore/Pfad mit & Ümlaut/tkchesswiz"
    set exe [::scidb::startup::probeExecutable -path $umlautPath]
    list [expr {[string first "Ümlaut" $exe] >= 0}] [::test_startup_guard::hasWarningMatch "*non-ASCII characters*"]
} -result {1 1}

# ----------------------------------------------------------------------
# 7. RECOVERABLE: Read-only install directory
# ----------------------------------------------------------------------
tcltest::test recoverable-readonly-install-dir {Read-only install dir logs warning and continues} -body {
    ::test_startup_guard::resetLogs
    set tmpDir [file join [::tcltest::temporaryDirectory] cw_ro_test_[pid]]
    file mkdir $tmpDir
    lappend ::test_startup_guard::tempDirs $tmpDir
    set fakeExe [file join $tmpDir tkchesswiz]
    set fd [open $fakeExe w]; puts $fd "#!/bin/sh"; close $fd
    # Set read-only
    catch { file attributes $tmpDir -permissions 0555 }
    set isWritable [::scidb::startup::checkInstallDir $fakeExe]
    # Cleanup permissions so cleanup can delete it
    catch { file attributes $tmpDir -permissions 0755 }
    list $isWritable [::test_startup_guard::hasWarningMatch "*install directory*is read-only*"]
} -cleanup {
    foreach d $::test_startup_guard::tempDirs {
        catch { file attributes $d -permissions 0755 }
        catch { file delete -force $d }
    }
} -result {0 1}

# ----------------------------------------------------------------------
# 8. RECOVERABLE: Windows / macOS layouts
# ----------------------------------------------------------------------
tcltest::test recoverable-windows-macos-layouts {Layout probe identifies macOS/Windows/Unix layouts and logs non-standard warnings} -body {
    ::test_startup_guard::resetLogs
    # Test macOS bundle with missing Resources
    set macExe "/Applications/Chesswiz.app/Contents/MacOS/tkchesswiz"
    set macRes [::scidb::startup::checkLayout $macExe "Darwin"]
    set macWarn [::test_startup_guard::hasWarningMatch "*macOS app bundle layout detected but Resources directory missing*"]
    
    # Test Windows layout with missing engines dir
    set winExe "C:/Chesswiz/tkchesswiz.exe"
    set winRes [::scidb::startup::checkLayout $winExe "windows"]
    set winWarn [::test_startup_guard::hasWarningMatch "*Windows layout detected but engines directory not found*"]

    list $macRes $macWarn $winRes $winWarn
} -result {macos-bundle-incomplete 1 windows-custom 1}

# ----------------------------------------------------------------------
# 9. RECOVERABLE: Legacy Tk 8.5.10 check
# ----------------------------------------------------------------------
tcltest::test recoverable-legacy-tk-check {Tk 8.5.10 logs warning instead of showing modal error box} -body {
    ::test_startup_guard::resetLogs
    ::scidb::startup::checkTkVersion "8.5.10"
    ::test_startup_guard::hasWarningMatch "*Tk patch level 8.5.10*"
} -result 1

tcltest::cleanupTests
