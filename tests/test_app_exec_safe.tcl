# ======================================================================
# Test ::util::execSafe robustness against background pipeline exit (ECHILD)
# ======================================================================
# Systemic flake regression: when a background pipeline child (media/AI/engine,
# opened with open "|..." nonblocking) exits during a foreground exec in the
# app, Tcl's waitpid may be reaped by the SIGCHLD handler or event loop,
# causing Tcl's exec to raise "child process lost" (errorCode POSIX ECHILD).
# ::util::execSafe makes foreground execution robust without hiding real
# non-zero exit statuses (CHILDSTATUS).
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::execsafe {
    variable testDir [file dirname [file normalize [info script]]]
    variable rootDir [file dirname $testDir]
}

# Ensure ::util::execSafe is loaded
if {![llength [info commands ::util::execSafe]]} {
    set _sysPlatform [file join $::scidb::test::execsafe::rootDir tcl sys-platform.tcl]
    if {[file exists $_sysPlatform]} {
        source -encoding utf-8 $_sysPlatform
    }
}

tcltest::test execsafe-baseline-echo {execSafe returns standard output cleanly} -body {
    ::util::execSafe /bin/echo "hello world"
} -result "hello world"

tcltest::test execsafe-multiline-output {execSafe preserves multiline stdout without trailing newline} -body {
    ::util::execSafe /bin/sh -c "echo line1; echo line2"
} -result "line1\nline2"

tcltest::test execsafe-background-pipeline-exit {a background pipeline child exiting during foreground exec does not raise} -body {
    # Start a short-lived background pipeline
    set pipe [open "|sh -c 'sleep 0.05; exit 0'" r]
    fconfigure $pipe -blocking 0
    fileevent $pipe readable [list apply {{p} { catch {read $p}; catch {close $p} }} $pipe]

    after 25
    set out [::util::execSafe /bin/echo "safe under background exit"]
    catch { close $pipe }
    set out
} -result "safe under background exit"

tcltest::test execsafe-repeated-background-pipeline-race {20 iterations of background pipeline exit races all succeed} -body {
    set failed 0
    for {set i 0} {$i < 20} {incr i} {
        set p [open "|sh -c 'sleep 0.02; exit 0'" r]
        fconfigure $p -blocking 0
        fileevent $p readable [list apply {{chan} { catch {read $chan}; catch {close $chan} }} $p]
        after 10
        if {[catch {::util::execSafe /bin/echo "iter $i"} res opts]} {
            incr failed
        }
        catch { close $p }
    }
    set failed
} -result 0

tcltest::test execsafe-preserves-childstatus {real non-zero exit statuses are not hidden and raise CHILDSTATUS} -body {
    set rc [catch {::util::execSafe /bin/sh -c "echo custom_failure; exit 42"} out opts]
    set ec [expr {[dict exists $opts -errorcode] ? [dict get $opts -errorcode] : {}}]
    list $rc [lindex $ec 0] [lindex $ec 2] [string match "*custom_failure*" $out]
} -result {1 CHILDSTATUS 42 1}

tcltest::test execsafe-handles-stderr-redirect {execSafe captures stderr when 2>@1 is specified} -body {
    set out [::util::execSafe /bin/sh -c "echo std_out; echo std_err >&2" 2>@1]
    list [string match "*std_out*" $out] [string match "*std_err*" $out]
} -result {1 1}

tcltest::test execsafe-handles-ignorestderr {execSafe -ignorestderr does not raise on stderr when exit is 0} -body {
    set out [::util::execSafe -ignorestderr /bin/sh -c "echo std_err >&2; exit 0"]
    expr {$out ne "FAIL"}
} -result 1

tcltest::test execsafe-preserves-enoent {non-existent executable raises POSIX ENOENT} -body {
    set rc [catch {::util::execSafe /nonexistent/binary/path/xyz} out opts]
    set ec [expr {[dict exists $opts -errorcode] ? [dict get $opts -errorcode] : {}}]
    list $rc [lindex $ec 0] [lindex $ec 1]
} -result {1 POSIX ENOENT}

tcltest::cleanupTests
