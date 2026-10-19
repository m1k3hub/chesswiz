# Run this file with a binary rebuilt after tk_twm.cpp changes. Keep the
# malformed command in a child: the regression used to SIGSEGV the process.
package require tcltest 2.5
tcltest::test twm-invalid-undock {an unknown pane path raises Tcl error instead of dereferencing null} -setup {
    set twmHome [file normalize [file join $::scidb::test::app::testDir tmp-app native-undock-[pid]]]
    file mkdir $twmHome
} -body {
    set root [file dirname $::scidb::test::app::testDir]
    set out [exec timeout 120 env HOME=$twmHome SCIDB_USERDIR=$twmHome/.chesswiz \
        MIG_ROOT=$root MIG_PHASE=invalid-undock \
        [info nameofexecutable] [file join $root tests fixtures media-mig phase.tcl] 2>@1]
    regexp {MIG invalid-undock rejected 1 board 1} $out
} -cleanup {file delete -force $twmHome} -result 1
tcltest::cleanupTests
