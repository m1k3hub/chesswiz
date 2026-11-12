# Loopback-only proof of the live smoke policy. Never loads real credentials.
package require tcltest 2.5
package require json
source [file join [file dirname [info script]] app_wait.tcl]
source [file join [file dirname [info script]] lichess_fake_server.tcl]
source [file join [file dirname [info script]] lichess_live_guard.tcl]
::scidb::test::wait::ready

proc ::scidb::test::live::FakeSetup {} {
    rename ::lichess::api::TokenLoad ::lichess::api::LiveOriginalTokenLoad
    proc ::lichess::api::TokenLoad {} { return fixture-live-guard }
    rename ::lichess::api::TokenDelete ::lichess::api::LiveOriginalTokenDelete
    proc ::lichess::api::TokenDelete {} {}
    set origin [::lichess::fake::Start]
    set ::lichess::fake::Token fixture-live-guard
    Install $origin
}
proc ::scidb::test::live::FakeCleanup {} {
    Uninstall
    ::lichess::fake::Stop
    foreach name {TokenLoad TokenDelete} {
        rename ::lichess::api::$name {}
        rename ::lichess::api::LiveOriginal$name ::lichess::api::$name
    }
}

# Every denial is checked at the server journal, not only via a caught error.
foreach {case command} {
    seek {::lichess::api::seek 10 0 0 random list}
    human {::lichess::api::challengeUser alice 10 0 0 white standard {} list}
    bot {::lichess::api::botUpgrade list}
    query {::lichess::api::Request GET /api/account?extra=1 {} list}
    method {::lichess::api::Request POST /api/account {} list}
    arbitrary-game {::lichess::api::resign otherGame list}
    wrong-level {::lichess::api::challengeAi 2 10 0 white list}
    extra-form {::lichess::api::Request POST /api/challenge/ai level=1&user=alice list}
    origin {::http::geturl https://example.invalid/api/account}
    direct-wire {::http::geturl $::lichess::api::Base/api/board/seek -method POST -query {}}
    implicit-post {::http::geturl $::lichess::api::Base/api/account -query {}}
} {
    tcltest::test lichess-live-guard-$case {forbidden request aborts before wire dispatch} -setup {
        ::scidb::test::live::FakeSetup
        ::scidb::test::live::Call Request GET /api/account {}
    } -body {
        set before [llength [::lichess::fake::Requests]]
        set code [catch $command message options]
        update
        list $code [dict get $options -errorcode] \
            [expr {[llength [::lichess::fake::Requests]] == $before}]
    } -cleanup { ::scidb::test::live::FakeCleanup } -result {1 {LICHESS LIVE GUARD} 1}
}

tcltest::test lichess-live-guard-unverified {no POST before account response} -setup {
    ::scidb::test::live::FakeSetup
} -body {
    list [catch {::lichess::api::challengeAi 1 10 0 white list}] [llength [::lichess::fake::Requests]]
} -cleanup { ::scidb::test::live::FakeCleanup } -result {1 0}

tcltest::test lichess-live-guard-bot {bot account aborts full runner and every POST} -setup {
    ::scidb::test::live::FakeSetup
    ::lichess::fake::Set botAccount 1
} -body {
    set aborted [catch {::scidb::test::live::Run}]
    set denied [catch {::lichess::api::challengeAi 1 10 0 white list}]
    list $aborted $denied $::scidb::test::live::Bot \
        [lmap r [::lichess::fake::Requests] {list [dict get $r method] [dict get $r path]}]
} -cleanup { ::scidb::test::live::FakeCleanup } -result {1 1 1 {{GET /api/account}}}

tcltest::test lichess-live-guard-smoke {entire live runner uses seven allowed requests and resigns its AI game} -setup {
    ::scidb::test::live::FakeSetup
} -body {
    set result [::scidb::test::live::Run]
    set game $::scidb::test::live::Game
    set expected [list {GET /api/account} {GET /api/tv/channels} {GET /api/puzzle/daily} \
        {GET /api/broadcast/top} {POST /api/challenge/ai} \
        [list GET /api/board/game/stream/$game] [list POST /api/board/game/$game/resign]]
    set journal [lmap r [::lichess::fake::Requests] {list [dict get $r method] [dict get $r path]}]
    list $result [expr {$journal eq $expected && $journal eq $::scidb::test::live::Wire}] \
        [llength $::scidb::test::live::Log] [dict size $::lichess::api::Requests] \
        $::scidb::test::live::FirstState [dict get $::lichess::fake::Games $game status] \
        [lmap row $::scidb::test::live::Log {lindex $row 2}]
} -cleanup { ::scidb::test::live::FakeCleanup } -result {ok 1 7 0 1 resign {200 200 200 200 200 200 200}}

tcltest::test lichess-live-guard-queued-url {URL tampering between API creation and dispatch is blocked} -setup {
    ::scidb::test::live::FakeSetup
} -body {
    set id [::lichess::api::tvChannels list]
    dict set ::lichess::api::Requests $id url "$::lichess::api::Base/api/board/seek"
    ::scidb::test::wait::until {$::scidb::test::live::Violations > 0}
    list [llength [::lichess::fake::Requests]] [llength $::scidb::test::live::Wire]
} -cleanup { ::scidb::test::live::FakeCleanup } -result {0 0}

tcltest::test lichess-live-guard-one-game {a second AI challenge is rejected before dispatch} -setup {
    ::scidb::test::live::FakeSetup
} -body {
    ::scidb::test::live::Call Request GET /api/account {}
    ::scidb::test::live::Call challengeAi 1 10 0 white
    set before [llength [::lichess::fake::Requests]]
    list [catch {::lichess::api::challengeAi 1 10 0 white list}] \
        [expr {[llength [::lichess::fake::Requests]] == $before}]
} -cleanup { ::scidb::test::live::FakeCleanup } -result {1 1}

tcltest::test lichess-live-guard-stream-timeout {failure after AI creation still closes stream and resigns} -setup {
    ::scidb::test::live::FakeSetup
    ::lichess::fake::Control /api/board/game/stream/cw000001 stall
} -body {
    set failed [catch {::scidb::test::live::Run 250}]
    set game $::scidb::test::live::Game
    set last [lindex [::lichess::fake::Requests] end]
    list $failed $::scidb::test::live::FirstState [dict size $::lichess::api::Requests] \
        [dict get $last method] [expr {[dict get $last path] eq "/api/board/game/$game/resign"}] \
        [dict get $::lichess::fake::Games $game status]
} -cleanup { ::scidb::test::live::FakeCleanup } -result {1 0 0 POST 1 resign}

tcltest::test lichess-live-guard-unauthorized {failed account authentication never reaches a POST} -setup {
    ::scidb::test::live::FakeSetup
    ::lichess::fake::Control /api/account 401
} -body {
    set failed [catch {::scidb::test::live::Run}]
    list $failed $::scidb::test::live::AccountOK \
        [lmap r [::lichess::fake::Requests] {list [dict get $r method] [dict get $r path]}]
} -cleanup { ::scidb::test::live::FakeCleanup } -result {1 0 {{GET /api/account}}}

tcltest::cleanupTests
