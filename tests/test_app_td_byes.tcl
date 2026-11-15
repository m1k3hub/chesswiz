package require tcltest 2.5

namespace eval ::tdByes { variable counter 0 }
proc ::tdByes::call {path cmd domain} {
    variable counter
    ::td::command::Execute $cmd [dict merge $domain [dict create path $path commit 1 expected_revision [dict get [::td::store::Read $path] revision] idempotency bye[incr counter]]]
}

tcltest::test td-byes-categories-and-swiss-withdrawals {distinct bye categories, pre/post pairing Swiss withdrawals, and C.07 16.2.5/16.4 Buchholz shift} -body {
    set path [file join $::env(HOME) byes.tdj]
    ::tdByes::call $path create {name {Swiss Byes} players {A B C D E F} system swiss rounds 3 start 0}
    # A requests half-point bye in round 1; B requests zero-point bye in round 1
    ::tdByes::call $path bye {player p1 round 1 category requested-bye}
    ::tdByes::call $path bye {player p2 round 1 category zero-point-bye}
    # Pair round 1: only C, D, E, F are paired (2 boards)
    ::tdByes::call $path pair_round {round 1}
    set st1 [dict get [::td::store::Read $path] state]
    set r1Boards [llength [lmap p [::td::model::Pairings $st1 1] {expr {[dict get $p black] ne "" ? $p : [continue]}}]]
    # Duplicate bye in same round rejected
    set dupBye [catch {::tdByes::call $path bye {player p1 round 1 category full-point-bye}}]
    # Complete round 1 games
    foreach p [::td::model::Pairings $st1 1] {
        if {[dict get $p black] ne ""} {
            ::tdByes::call $path enter_result [dict create pairing [dict get $p id] result 1-0 category played]
        }
    }
    # Withdraw F before round 2 pairing -> withdrawal-before-pairing
    set wBefore [::tdByes::call $path withdraw {player p6 round 2}]
    # Pair round 2 (5 remaining players: A, B, C, D, E -> 2 boards + 1 pairing-allocated bye)
    ::tdByes::call $path pair_round {round 2}
    set st2 [dict get [::td::store::Read $path] state]
    set pabCount 0
    set r2Pending {}
    foreach p [::td::model::Pairings $st2 2] {
        if {[dict get $p category] eq "pairing-bye"} { incr pabCount }
        if {[dict get $p status] eq "pending"} { lappend r2Pending $p }
    }
    # Withdraw White of first pending board in round 2 after pairing -> withdrawal-after-pairing (forfeit win for Black)
    set b0 [lindex $r2Pending 0]
    set wPlayer [dict get $b0 white]
    set bPlayer [dict get $b0 black]
    set wAfter [::tdByes::call $path withdraw [dict create player $wPlayer round 2]]
    set b1 [lindex $r2Pending 1]
    ::tdByes::call $path enter_result [dict create pairing [dict get $b1 id] result 1/2-1/2 category played]
    # Give p2 a trailing requested bye in round 3 so C.07 16.2.5 adjusts p2's trailing requested byes to draws for opponents
    ::tdByes::call $path bye {player p2 round 3 category requested-bye}
    set st3 [dict get [::td::store::Read $path] state]
    set trf [::td::trf::Write $st3 trf26]
    set hasH [regexp {\m0000 - H\M} $trf]
    set hasZ [regexp {\m0000 - Z\M} $trf]
    set hasU [regexp {\m0000 - U\M} $trf]
    set rows [::td::score::Compute $st3]
    list $r1Boards $dupBye [dict get $wBefore timing] $pabCount [dict get $wAfter timing] [dict get $wAfter changed] $hasH $hasZ $hasU [llength $rows]
} -result {2 1 withdrawal-before-pairing 1 withdrawal-after-pairing 1 1 1 1 6}

tcltest::cleanupTests
