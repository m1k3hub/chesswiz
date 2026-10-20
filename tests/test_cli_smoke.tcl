# ======================================================================
# CLI Smoke Tests
# These are low-cost checks for user-facing converter entry points.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test {

variable repoRoot [file dirname [file dirname [file normalize [info script]]]]

proc executablePath {name} {
    variable repoRoot
    set p [file join $repoRoot src $name]
    if {![file executable $p]} {
        set mainSrc [file join /media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex src $name]
        if {[file executable $mainSrc]} { return $mainSrc }
    }
    return $p
}

proc commandOutput {args} {
    if {![llength [info commands ::util::execSafe]]} {
        set _sysPlatform [file normalize [file join [file dirname [file normalize [info script]]] .. tcl sys-platform.tcl]]
        if {[file exists $_sysPlatform]} { catch { source -encoding utf-8 $_sysPlatform } }
    }
    if {[llength [info commands ::util::execSafe]]} {
        return [::util::execSafe {*}$args]
    }
    return [exec {*}$args]
}

set hasVerifyCbhWrite [file executable [executablePath verify_cbh_write]]
tcltest::testConstraint hasVerifyCbhWrite $hasVerifyCbhWrite

tcltest::test cli-cdb2sci-help-01 {cdb2sci should print a usage banner} -body {
    set exe [executablePath cdb2sci]
    set out [commandOutput $exe --help]
    expr {[string match {*Usage: cdb2sci*} $out] && [string match {*--count-games*} $out]}
} -result 1

tcltest::test cli-cbh2si4-help-02 {cbh2si4 should print a usage banner} -body {
    set exe [executablePath cbh2si4]
    set out [commandOutput $exe --help]
    expr {[string match {*Usage: cbh2si4*} $out] && [string match {*--convertto <encoding>*} $out]}
} -result 1

tcltest::test cli-verify-cbh-write-03 {verify_cbh_write should pass a normal-game CBH round trip} \
    -constraints hasVerifyCbhWrite -body {
    set exe [executablePath verify_cbh_write]
    set out [commandOutput $exe 2>@1]
    expr {[string match {*CBH write round-trip verification PASSED*} $out]}
} -result 1

tcltest::cleanupTests

} ;# namespace ::scidb::test
