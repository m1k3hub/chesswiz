package require tcltest 2.5

namespace eval ::tdArbiter { variable counter 0 }
proc ::tdArbiter::call {path cmd domain} {
    variable counter
    ::td::command::Execute $cmd [dict merge $domain [dict create path $path commit 1 expected_revision [dict get [::td::store::Read $path] revision] idempotency arb[incr counter]]]
}

tcltest::test td-arbiter-laws-2023-and-appeals {Laws 2023 illegal moves across settings/regimes, dead-position flag fall, checkmate precedence, and human TD accountability} -body {
    set path [file join $::env(HOME) arbiter.tdj]
    ::tdArbiter::call $path create {name {Arbiter Event} players {A B C D} system swiss rounds 3 start 1}
    # Missing human arbiter name is rejected
    set missingArb [catch {::tdArbiter::call $path ruling {pairing r1b0 incident illegal-move arbiter {}}}]
    # Ordinary OTB first illegal move -> +120s
    set rStd1 [::tdArbiter::call $path ruling {pairing r1b0 setting otb pace standard regime standard incident illegal-move offence_count 1 arbiter {CA Smith}}]
    # Rapid A.4 first illegal move -> +60s
    set rRap1 [::tdArbiter::call $path ruling {pairing r1b0 setting otb pace rapid regime A4 incident illegal-move offence_count 1 arbiter {CA Smith}}]
    # Blitz B.2 supervised first illegal move -> +120s; Blitz B.3 unsupervised -> +60s
    set rBlitzB2 [::tdArbiter::call $path ruling {pairing r1b0 setting otb pace blitz regime B2 incident illegal-move offence_count 1 arbiter {CA Smith}}]
    set rBlitzB3 [::tdArbiter::call $path ruling {pairing r1b0 setting otb pace blitz regime B3 incident illegal-move offence_count 1 arbiter {CA Smith}}]
    # Unsupervised A.5 not claimed before opponent's next move -> stands (0s, continue)
    set rA5Late [::tdArbiter::call $path ruling {pairing r1b0 setting otb pace rapid regime A5 incident illegal-move claimed_in_time 0 arbiter {CA Smith}}]
    # Second illegal move when opponent cannot mate by any legal sequence -> draw
    set rSecondDead [::tdArbiter::call $path ruling {pairing r1b0 setting otb pace standard regime standard incident illegal-move offence_count 2 opponent_can_mate 0 arbiter {CA Smith}}]
    # Rejected GUI attempt is not an OTB illegal move
    set rGui [::tdArbiter::call $path ruling {pairing r1b0 setting local incident gui-illegal-attempt arbiter {CA Smith}}]
    # Checkmate takes precedence over 75-move rule
    set rMate75 [::tdArbiter::call $path ruling {pairing r1b0 setting otb incident 75-move checkmate_on_board 1 arbiter {CA Smith}}]
    # Apply a provisional result pending appeal on r1b1
    set rAppeal [::tdArbiter::call $path ruling {pairing r1b1 setting otb incident flag-fall opponent_can_mate 0 apply_result 1/2-1/2 appeal_status provisional-pending-appeal appeal_committee {Appeals Board} appeal_deposit {100 EUR} arbiter {CA Smith}}]
    set st [dict get [::td::store::Read $path] state]
    set p1 [lindex [dict get $st pairings] 1]
    list $missingArb \
        [dict get $rStd1 penalty_seconds] \
        [dict get $rRap1 penalty_seconds] \
        [dict get $rBlitzB2 penalty_seconds] \
        [dict get $rBlitzB3 penalty_seconds] \
        [dict get $rA5Late penalty_seconds] [dict get $rA5Late game_result] \
        [dict get $rSecondDead game_result] \
        [dict get $rGui penalty_seconds] [dict get $rGui game_result] \
        [dict get $rMate75 game_result] \
        [dict get $p1 status] [dict get $p1 result] [llength [dict get $st rulings]]
} -result {1 120 60 120 60 0 continue draw 0 continue decisive provisional 1/2-1/2 9}

tcltest::cleanupTests
