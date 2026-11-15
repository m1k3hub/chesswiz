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

tcltest::test td-arbiter-f13-ui-ruling-and-appeal-controls {F13: TD workspace RecordRuling exposes setting, pace, offence count, claim/mate flags, apply_result, and full appeal fields} -body {
    set path [file join $::env(HOME) arbiter_ui_f13.tdj]
    ::tdArbiter::call $path create {name {UI Arbiter Event} players {A B C D} system swiss rounds 2 start 1}
    try {
        ::td::ui::Open $path results
        update idletasks
        set rf $::td::ui::Notebook.results.ruling
        set hasWidgets [expr {
            [winfo exists $rf.setting] &&
            [winfo exists $rf.pace] &&
            [winfo exists $rf.offence] &&
            [winfo exists $rf.claimed] &&
            [winfo exists $rf.can_mate] &&
            [winfo exists $rf.apply_result] &&
            [winfo exists $rf.appeal_status] &&
            [winfo exists $rf.appeal_committee] &&
            [winfo exists $rf.appeal_deposit]
        }]

        # 1. Unsupervised Rapid A.5 not claimed in time on r1b0 -> 0s, continue
        $::td::ui::Notebook.results.tree selection set r1b0
        set ::td::ui::Fields(ruling_setting) otb
        set ::td::ui::Fields(ruling_pace) rapid
        set ::td::ui::Fields(ruling_regime) A5
        set ::td::ui::Fields(ruling_incident) illegal-move
        set ::td::ui::Fields(ruling_offence_count) 1
        set ::td::ui::Fields(ruling_claimed_in_time) 0
        set ::td::ui::Fields(ruling_opponent_can_mate) 1
        set ::td::ui::Fields(ruling_claim_valid) 1
        set ::td::ui::Fields(ruling_checkmate_on_board) 0
        set ::td::ui::Fields(ruling_default_time_minutes) 0
        set ::td::ui::Fields(ruling_late_minutes) 1
        set ::td::ui::Fields(ruling_apply_result) {}
        set ::td::ui::Fields(ruling_appeal_status) none
        set ::td::ui::Fields(ruling_appeal_committee) {}
        set ::td::ui::Fields(ruling_appeal_deadline) 0
        set ::td::ui::Fields(ruling_appeal_deposit) {}
        set ::td::ui::Fields(ruling_decision) {}
        set ::td::ui::Fields(ruling_arbiter) {FA Jones}
        ::td::ui::RecordRuling

        # 2. Second illegal move on r1b0 where opponent cannot mate -> draw
        $::td::ui::Notebook.results.tree selection set r1b0
        set ::td::ui::Fields(ruling_offence_count) 2
        set ::td::ui::Fields(ruling_claimed_in_time) 1
        set ::td::ui::Fields(ruling_opponent_can_mate) 0
        ::td::ui::RecordRuling

        # 3. Provisional result pending appeal on r1b1 from the UI
        $::td::ui::Notebook.results.tree selection set r1b1
        set ::td::ui::Fields(ruling_setting) otb
        set ::td::ui::Fields(ruling_pace) standard
        set ::td::ui::Fields(ruling_regime) standard
        set ::td::ui::Fields(ruling_incident) flag-fall
        set ::td::ui::Fields(ruling_offence_count) 1
        set ::td::ui::Fields(ruling_opponent_can_mate) 1
        set ::td::ui::Fields(ruling_apply_result) 1-0
        set ::td::ui::Fields(ruling_appeal_status) provisional-pending-appeal
        set ::td::ui::Fields(ruling_appeal_committee) {Appeals Committee}
        set ::td::ui::Fields(ruling_appeal_deadline) 1794768000
        set ::td::ui::Fields(ruling_appeal_deposit) {50 EUR}
        set ::td::ui::Fields(ruling_decision) {Flag fall upheld provisionally pending appeal}
        ::td::ui::RecordRuling
    } finally {
        catch { ::td::ui::Close }
        update idletasks
    }

    set st [dict get [::td::store::Read $path] state]
    set rulings [dict get $st rulings]
    set r1 [lindex $rulings 0]
    set r2 [lindex $rulings 1]
    set r3 [lindex $rulings 2]
    set p1 [lindex [dict get $st pairings] 1]
    list $hasWidgets \
        [dict get $r1 pace] [dict get $r1 penalty_seconds] [dict get $r1 game_result] \
        [dict get $r2 game_result] \
        [dict get $r3 appeal_status] [dict get $r3 appeal_committee] [dict get $r3 appeal_deposit] \
        [dict get $p1 status] [dict get $p1 result]
} -result {1 rapid 0 continue draw provisional-pending-appeal {Appeals Committee} {50 EUR} provisional 1-0}

tcltest::cleanupTests
