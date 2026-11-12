# Manual opt-in smoke test: validator supplies a disposable HOME containing
# the token, then sets CHESSWIZ_LICHESS_LIVE=1. Never pass a token in argv.
package require tcltest 2.5
package require json
source [file join [file dirname [info script]] app_wait.tcl]
source [file join [file dirname [info script]] lichess_live_guard.tcl]
::scidb::test::wait::ready

set liveEnabled [expr {[info exists ::env(CHESSWIZ_LICHESS_LIVE)] && $::env(CHESSWIZ_LICHESS_LIVE) eq "1"}]
tcltest::testConstraint lichessLive $liveEnabled
if {!$liveEnabled} { puts "SKIP live lichess.org smoke: set CHESSWIZ_LICHESS_LIVE=1 explicitly" }
tcltest::test lichess-live-smoke {manual opt-in: public reads and one level-1 AI game, immediately resigned} \
    -constraints lichessLive -setup {
        ::scidb::test::live::Install https://lichess.org
    } -body {
        # Suppress exception details: Tcl transport stacks may contain headers.
        if {[catch {::scidb::test::live::Run}]} { error "Live smoke failed; inspect method/path/status log only" }
        set result ok
    } -cleanup { ::scidb::test::live::Uninstall } -result ok

tcltest::cleanupTests
