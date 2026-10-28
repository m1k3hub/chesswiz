package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
namespace eval ::scidb::test::endgameargs {
    proc call {args} {
        set reply [::knowledge::RunAction menu.training.endgame $args]
        if {[string match error:* $reply]} { error $reply }
        return $reply
    }
    proc cleanup {} {
        ::endtrainer::Close
        ::scidb::test::actions::cleanup
    }
}

tcltest::test endgame-args-validation {bad identifiers and indexes never silently start another position} -setup {
    ::scidb::test::actions::ready
} -body {
    list \
        [string match {error:*unknown ending*} [::knowledge::RunAction menu.training.endgame {operation start ending missing}]] \
        [string match {error:*position index*} [::knowledge::RunAction menu.training.endgame {operation start ending kqk index 99}]] \
        [string match {error:*} [::knowledge::RunAction menu.training.endgame {operation start ending kqk index -1}]] \
        [string match {error:*no faulty move*} [::knowledge::RunAction menu.training.endgame {operation retry}]] \
        [llength [::scidb::test::endgameargs::call operation catalog]] \
        $::endtrainer::Priv(dialog)
} -cleanup { ::scidb::test::endgameargs::cleanup } -result {1 1 1 1 10 {}}

# The regular suite can run without downloaded tables. The assigned offline
# evidence run supplies SCIDB_TEST_SYZYGY and requires this test to execute.
set hasTables [expr {[info exists ::env(SCIDB_TEST_SYZYGY)] && [file isdirectory $::env(SCIDB_TEST_SYZYGY)]}]
tcltest::testConstraint endgameLocalTables $hasTables
tcltest::test endgame-args-local-retry-continue {real Syzygy fault, undo and tablebase defence through the public assistant operator} -constraints endgameLocalTables -setup {
    ::scidb::test::actions::ready
    set savedLocal $::tablebase::Options(local)
    set savedOnline $::tablebase::Options(online)
    set savedTrainerOnline $::endtrainer::Options(online)
    set ::tablebase::Options(local) $::env(SCIDB_TEST_SYZYGY)
    set ::tablebase::Options(online) 0
    set ::endtrainer::Options(online) 0
} -body {
    if {[::tablebase::LocalLargest] < 3} { error "real three-piece tablebase is required" }
    ::scidb::test::endgameargs::call operation start ending kqk index 0
    set initial [::scidb::pos::fen]
    ::scidb::test::endgameargs::call operation move move Qf5+
    ::scidb::test::actions::waitUntil {$::endtrainer::Priv(phase) eq "fault"}
    set verdict [dict get [::tablebase::LocalAnswer [::scidb::pos::fen]] category]
    set fault $::endtrainer::Priv(fault)
    ::scidb::test::endgameargs::call operation retry
    puts "RETRY initial=$initial actual=[::scidb::pos::fen] length=[::scidb::game::query length] phase=$::endtrainer::Priv(phase)"
    set retried [expr {[::scidb::pos::fen] eq $initial && [::scidb::game::query length] == 0 && $::endtrainer::Priv(phase) eq "user"}]
    ::scidb::test::endgameargs::call operation move move Qf5+
    ::scidb::test::actions::waitUntil {$::endtrainer::Priv(phase) eq "fault"}
    set answer [::tablebase::LocalAnswer [::scidb::pos::fen]]
    set expected [::endtrainer::BestMoveSan $answer]
    ::scidb::test::endgameargs::call operation continue
    ::scidb::test::actions::waitUntil {[::scidb::game::query length] == 2}
    set pgn [::scidb::game::toPGN modified -position [::scidb::game::current]]
    set defended [expr {$expected ne "" && [string first $expected $pgn] >= 0}]
    set absent $::endtrainer::Priv(dialog)
    ::scidb::test::endgameargs::call operation next
    set next $::endtrainer::Priv(index)
    ::scidb::test::endgameargs::call operation give_up
    set givenUp [expr {!$::endtrainer::Priv(active)}]
    ::scidb::test::endgameargs::call operation close
    puts "REAL_ENDGAME verdict=$verdict fault=$fault retry=$retried defence=$expected next=$next give_up=$givenUp dialog=$absent"
    list $verdict $fault $retried $defended $next $givenUp $absent $::endtrainer::Priv(dialog)
} -cleanup {
    ::scidb::test::endgameargs::cleanup
    set ::tablebase::Options(local) $savedLocal
    set ::tablebase::Options(online) $savedOnline
    set ::endtrainer::Options(online) $savedTrainerOnline
} -result {draw letWinSlip 1 1 1 1 {} {}}

tcltest::test endgame-args-dialog {dialog buttons share the registry operation and only missing arguments open the chooser} -constraints endgameLocalTables -setup {
    ::scidb::test::actions::ready
    set savedLocal $::tablebase::Options(local)
    set ::tablebase::Options(local) $::env(SCIDB_TEST_SYZYGY)
} -body {
    ::knowledge::RunAction menu.training.endgame {}
    set tree $::endtrainer::Priv(widget:tree)
    dict for {node id} $::endtrainer::Priv(treeIds) {
        if {$id eq "kqk"} { $tree selection set $node; break }
    }
    $::endtrainer::Priv(widget:ok) invoke
    set started [expr {$::endtrainer::Priv(active) && $::endtrainer::Priv(endingId) eq "kqk"}]
    ::scidb::test::endgameargs::call operation move move Qf5+
    ::scidb::test::actions::waitUntil {$::endtrainer::Priv(phase) eq "fault"}
    set buttons $::endtrainer::Priv(widget:buttons)
    set giveReply [$buttons.giveup invoke]
    puts "DIALOG_GIVEUP state=[$buttons.giveup state] reply=$giveReply session=[::endtrainer::SessionState]"
    set stopped [expr {!$::endtrainer::Priv(active)}]
    $::endtrainer::Priv(widget:cancel) invoke
    list $started $stopped $::endtrainer::Priv(dialog)
} -cleanup {
    ::scidb::test::endgameargs::cleanup
    set ::tablebase::Options(local) $savedLocal
} -result {1 1 {}}
tcltest::cleanupTests
