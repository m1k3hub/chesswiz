# ======================================================================
# Scidb Test Suite Framework
# ======================================================================
# Comprehensive test framework for Scidb chess database application
# 
# Usage:
#   tclsh tests/run_all.tcl                    # Run all tests
#   tclsh tests/run_all.tcl -match db*         # Run tests matching pattern
#   tclsh tests/run_all.tcl -verbose           # Verbose output
#   tclsh tests/run_all.tcl -coverage          # With coverage
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test {

# ==============================================================================
# Test Configuration
# ==============================================================================

variable testDir [file dirname [file normalize [info script]]]
variable srcDir [file dirname $testDir]
variable tclDir [file join $srcDir tcl]
variable dataDir [file join $srcDir src/data]
# Per-process scratch dir: concurrent runs must not share (or delete) each
# other's artifacts under tests/tmp.
variable tmpDir [file join $testDir tmp run-[pid]]

variable verbose 0
variable coverage 0
variable passCount 0
variable failCount 0
variable skipCount 0

# ==============================================================================
# Test Utilities
# ==============================================================================

proc setup {} {
    variable tmpDir
    variable tclDir
    
    # Create temp directory for test artifacts
    if {![file exists $tmpDir]} {
        file mkdir $tmpDir
    }
    
    # Source core Tcl modules (headless)
    catch { namespace eval ::scidb {} }
    
    # Load utility modules
    foreach file {
        utils/misc.tcl
        utils/locale.tcl
        utils/clipboard.tcl
        log.tcl
        options.tcl
        game.tcl
        move.tcl
        comment.tcl
    } {
        set path [file join $tclDir $file]
        if {[file exists $path]} {
            catch { source $path }
        }
    }
}

proc cleanup {} {
    variable tmpDir
    
    # Remove temp directory
    if {[file exists $tmpDir]} {
        foreach f [glob -nocomplain -directory $tmpDir *] {
            catch { file delete -force $f }
        }
        catch { file delete -force $tmpDir }
    }
    
    # Reset any global state
    catch { ::scidb::db::reset }
}

proc createTestPgn {{filename ""}} {
    variable tmpDir
    
    if {$filename eq ""} {
        set filename [file join $tmpDir test_[clock microseconds].pgn]
    }
    
    set pgn {
[Event "Test Tournament"]
[Site "Test City"]
[Date "2024.01.15"]
[Round "1"]
[White "Test Player One"]
[Black "Test Player Two"]
[WhiteElo "2500"]
[BlackElo "2450"]
[ECO "C20"]
[Result "1-0"]

1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. c3 Nf6 5. d4 exd4 6. cxd4 Bb4+ 7. Nc3 Nxe4 8. O-O Bxc3 9. d5 Bf6 10. Re1 O-O 11. Rxe4 d6 12. Bg5 Bxg5 13. Nxg5 h6 14. Qh5 hxg5 15. Rh4 f5 16. Qh7+ Kf7 17. Qh5+ Kg8 18. Rh8# 1-0

[Event "Test Tournament"]
[Site "Test City"]
[Date "2024.01.15"]
[Round "2"]
[White "Test Player Three"]
[Black "Test Player Four"]
[WhiteElo "2400"]
[BlackElo "2380"]
[ECO "B01"]
[Result "0-1"]

1. e4 d5 2. exd5 Qxd5 3. Nc3 Qa5 4. d4 Nf6 5. Nf3 Bg4 6. Be2 Nc6 7. Be3 e6 8. O-O O-O-O 9. a3 Bxf3 10. Bxf3 Qh5 11. Bxc6 bxc6 12. Qe2 Bd6 13. g3 Qg4 14. Qxg4 Nxg4 15. Bf4 Bxf4 16. gxf4 Rxd4 17. Rad1 Rfd8 18. Rxd4 Rxd4 19. Kg2 Nf6 20. Kf3 Nd5 21. Ke4 Nxf4 22. Kxc6 Nxh2 23. Kb7 Rd6+ 0-1

[Event "Test Tournament"]
[Site "Test City"]
[Date "2024.01.16"]
[Round "3"]
[White "Test Player Five"]
[Black "Test Player Six"]
[WhiteElo "2350"]
[BlackElo "2320"]
[ECO "D30"]
[Result "1/2-1/2"]

1. d4 d5 2. c4 e6 3. Nc3 c6 4. Nf3 Nf6 5. Bg5 Be7 6. e3 O-O 7. Bd3 Nbd7 8. O-O dxc4 9. Bxc4 b5 10. Bd3 Bb7 11. e4 h6 12. Bh4 c5 13. d5 exd5 14. exd5 c4 15. Bc2 Re8 16. Re1 Nc5 17. Bxf6 Bxf6 18. Rxe8+ Qxe8 19. Qd2 Rd8 20. Re1 Qd7 21. h3 a5 22. Ne4 Be7 23. Ng3 Bf6 24. Re7 Qd6 25. Rxb7 Nxb7 26. Qe2 Nbxd5 27. Bf5 Qc6 28. Be4 Qc5 29. Bxd5 Qxd5 30. Qe8+ Kh7 31. Qxf7 Qxf7 32. Nxf7 Kg6 33. Ne5+ Bxe5 34. f4 Bd4+ 35. Kh2 Kf5 36. g4+ Kxf4 37. Kg2 Kg5 38. Kf3 Kxg4 39. Ke4 Kxh3 40. Kxd4 g5 41. Kxc4 g4 42. Kxb5 g3 43. Kxa5 g2 44. Kb4 g1=Q 45. a4 Qb1+ 46. Ka5 Qa2 47. Kb6 Qxa4 48. Kc7 h5 49. Kd8 h4 50. Ke8 h3 51. Kf8 h2 52. Kg8 h1=Q 53. Kf8 Qhh8# 1/2-1/2
}
    
    set fd [open $filename w]
    puts $fd $pgn
    close $fd
    
    return $filename
}

proc createTestDatabase {{filename ""}} {
    variable tmpDir
    
    if {$filename eq ""} {
        set filename [file join $tmpDir test_[clock microseconds].sci]
    }
    
    # Create database using C++ tools if available
    set cbh2si4 [file join [file dirname $tmpDir] src cbh2si4]
    if {[file executable $cbh2si4]} {
        set pgn [createTestPgn]
        if {![llength [info commands ::util::execSafe]]} {
            set _sysPlatform [file normalize [file join [file dirname [file normalize [info script]]] .. tcl sys-platform.tcl]]
            if {[file exists $_sysPlatform]} { catch { source -encoding utf-8 $_sysPlatform } }
        }
        if {[llength [info commands ::util::execSafe]]} {
            catch { ::util::execSafe $cbh2si4 $pgn $filename }
        } else {
            catch { exec $cbh2si4 $pgn $filename }
        }
    }
    
    return $filename
}

# ==============================================================================
# Assertion Helpers
# ==============================================================================

proc assertEq {actual expected {msg ""}} {
    if {$actual ne $expected} {
        error [format "Assertion failed: %s\n  Expected: %s\n  Actual: %s" \
            $msg $expected $actual]
    }
}

proc assertNe {actual expected {msg ""}} {
    if {$actual eq $expected} {
        error [format "Assertion failed: %s\n  Expected not: %s\n  Actual: %s" \
            $msg $expected $actual]
    }
}

proc assertTrue {value {msg ""}} {
    if {![string is true -strict $value]} {
        error [format "Assertion failed: %s\n  Expected: true\n  Actual: %s" \
            $msg $value]
    }
}

proc assertFalse {value {msg ""}} {
    if {[string is true -strict $value]} {
        error [format "Assertion failed: %s\n  Expected: false\n  Actual: %s" \
            $msg $value]
    }
}

proc assertExists {path {msg ""}} {
    if {![file exists $path]} {
        error [format "Assertion failed: %s\n  Path does not exist: %s" $msg $path]
    }
}

proc assertNotExists {path {msg ""}} {
    if {[file exists $path]} {
        error [format "Assertion failed: %s\n  Path should not exist: %s" $msg $path]
    }
}

proc assertMatch {value pattern {msg ""}} {
    if {![string match $pattern $value]} {
        error [format "Assertion failed: %s\n  Expected pattern: %s\n  Actual: %s" \
            $msg $pattern $value]
    }
}

proc assertLength {list expected {msg ""}} {
    set len [llength $list]
    if {$len != $expected} {
        error [format "Assertion failed: %s\n  Expected length: %d\n  Actual: %d" \
            $msg $expected $len]
    }
}

} ;# namespace ::scidb::test

# Export test utilities
namespace export *
