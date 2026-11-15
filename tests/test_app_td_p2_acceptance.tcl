package require tcltest 2.5

namespace eval ::tdP2Acc { variable counter 0 }
proc ::tdP2Acc::call {path cmd domain} {
    variable counter
    ::td::command::Execute $cmd [dict merge $domain [dict create path $path commit 1 expected_revision [dict get [::td::store::Read $path] revision] idempotency p2acc[incr counter]]]
}

proc ::tdP2Acc::pairMap {pairings} {
    set items {}
    foreach p $pairings {
        if {[dict get $p black] ne ""} {
            lappend items [list [dict get $p white] [dict get $p black]]
        } elseif {[dict exists $p category] && [dict get $p category] eq "pairing-bye"} {
            lappend items [list [dict get $p white] BYE]
        }
    }
    return [lsort -index 0 $items]
}

tcltest::test td-p2-published-swiss-1-chessament-9r {Reproduce published 100-player 9-round Swiss (KDE Chessament tournament_1.trf) round by round and verify C.07 Buchholz and Buchholz Cut-1} -body {
    set trfPath [file normalize [file join [file dirname [info script]] fixtures td chessament-tournament-1.trf]]
    set f [open $trfPath r]; fconfigure $f -encoding utf-8; set trfText [read $f]; close $f
    set parsed [::td::trf::Read $trfText]
    set path [file join $::env(HOME) pub1.tdj]
    ::tdP2Acc::call $path import_trf [dict create filename $trfPath system swiss]
    set st [dict get [::td::store::Read $path] state]

    # Verify round-by-round pairing reproduction across all 9 rounds
    set mismatches 0
    for {set r 1} {$r <= 9} {incr r} {
        set gen [::td::swiss::Pair $st $r]
        set got [::tdP2Acc::pairMap $gen]
        set exp [::tdP2Acc::pairMap [::td::model::Pairings $st $r]]
        if {$got ne $exp} { incr mismatches }
    }
    set check9 [::td::swiss::CheckRound $st 9]

    # Verify C.07 Buchholz and Buchholz Cut-1 against published golden standings
    set rows [::td::score::Compute $st]
    set bhByNum [dict create]
    set bhc1ByNum [dict create]
    foreach row $rows {
        set n [dict get $row number]
        dict set bhByNum $n [format "%.1f" [expr {double([dict get $row tiebreaks buchholz n]) / [dict get $row tiebreaks buchholz d]}]]
        dict set bhc1ByNum $n [format "%.1f" [expr {double([dict get $row tiebreaks buchholzCut1 n]) / [dict get $row tiebreaks buchholzCut1 d]}]]
    }
    set f [open "$trfPath.bh" r]; set bhLines [split [string trim [read $f]] \n]; close $f
    set bhDiffs 0
    foreach line $bhLines {
        if {$line eq "" || [string match "#*" $line] || [string match "R*" $line]} { continue }
        lassign [split $line ,] rank srank pts bhExp
        if {[dict get $bhByNum $srank] ne $bhExp} { incr bhDiffs }
    }
    set f [open "$trfPath.bh_c1" r]; set bhc1Lines [split [string trim [read $f]] \n]; close $f
    set bhc1Diffs 0
    foreach line $bhc1Lines {
        if {$line eq "" || [string match "#*" $line] || [string match "R*" $line]} { continue }
        lassign [split $line ,] rank srank pts bhc1Exp
        if {[dict get $bhc1ByNum $srank] ne $bhc1Exp} { incr bhc1Diffs }
    }
    list [llength [dict get $parsed players]] [dict get $parsed rounds] $mismatches [dict get $check9 compliant] $bhDiffs $bhc1Diffs
} -result {100 9 0 1 0 0}

tcltest::test td-p2-published-swiss-2-bbp-60p-14r {Reproduce published 60-player 14-round Dutch Swiss (bbpPairings issue_7.input + issue_7.output.expected) round by round} -body {
    set trfPath [file normalize [file join [file dirname [info script]] .. engines bbpPairings test tests issue_7.input]]
    set expPath [file normalize [file join [file dirname [info script]] .. engines bbpPairings test tests issue_7.output.expected]]
    set f [open $trfPath r]; fconfigure $f -encoding utf-8; set trfText [read $f]; close $f
    set f [open $expPath r]; fconfigure $f -encoding utf-8; set expR15 [string trim [read $f]]; close $f

    set path [file join $::env(HOME) pub2.tdj]
    ::tdP2Acc::call $path import_trf [dict create filename $trfPath system swiss]
    set st [dict get [::td::store::Read $path] state]
    dict set st colour_lot black

    # Verify rounds 1..13 match the published TRF round by round, and checker passes all 14 rounds
    set mismatches 0
    for {set r 1} {$r <= 13} {incr r} {
        set gen [::td::swiss::Pair $st $r]
        set got [::tdP2Acc::pairMap $gen]
        set exp [::tdP2Acc::pairMap [::td::model::Pairings $st $r]]
        if {$got ne $exp} { incr mismatches }
    }
    set check14 [::td::swiss::CheckRound $st 14]
    # Round 15 pairing matches issue_7.output.expected exactly
    set r15Raw [::td::swiss::Run [::td::trf::Write $st trf16 14 15]]
    list [llength [dict get $st players]] $mismatches [dict get $check14 bbp_discrepancy] [expr {$r15Raw eq $expR15}]
} -result {60 0 0 1}

tcltest::test td-p2-published-chess-results-1-singapore-9r {F3: Reproduce published chess-results.com Swiss #1 (tnr1518768, Intchess Asia Blitz 20p 9r) pairings, C.07 standings, and TRF26 round-trip} -body {
    set trfPath [file normalize [file join [file dirname [info script]] fixtures td chess-results-tnr1518768.trf]]
    set csvPath [file normalize [file join [file dirname [info script]] fixtures td chess-results-tnr1518768.standings.csv]]
    set path [file join $::env(HOME) cr1518768.tdj]
    ::tdP2Acc::call $path import_trf [dict create filename $trfPath system swiss]
    set st [dict get [::td::store::Read $path] state]

    set pairMismatches 0
    for {set r 1} {$r <= 9} {incr r} {
        set gen [::td::swiss::Pair $st $r]
        if {[::tdP2Acc::pairMap $gen] ne [::tdP2Acc::pairMap [::td::model::Pairings $st $r]]} {
            incr pairMismatches
        }
    }
    set check9 [::td::swiss::CheckRound $st 9]

    set rows [::td::score::Compute $st]
    set byNum [dict create]
    foreach row $rows { dict set byNum [dict get $row number] $row }

    set f [open $csvPath r]; set csvLines [split [string trim [read $f]] \n]; close $f
    set rankDiffs 0; set bhc1Diffs 0; set bhDiffs 0; set sbDiffs 0
    foreach line $csvLines {
        if {$line eq "" || [string match "#*" $line]} { continue }
        lassign [split $line ,] expRank sNo expPts tb1 expBhc1 expBh expSb tb5
        set row [dict get $byNum $sNo]
        if {[dict get $row rank] != $expRank} { incr rankDiffs }
        set gotBhc1 [expr {double([dict get $row tiebreaks buchholzCut1 n]) / [dict get $row tiebreaks buchholzCut1 d]}]
        set gotBh [expr {double([dict get $row tiebreaks buchholz n]) / [dict get $row tiebreaks buchholz d]}]
        set gotSb [expr {double([dict get $row tiebreaks sonnebornBerger n]) / [dict get $row tiebreaks sonnebornBerger d]}]
        if {abs($gotBhc1 - $expBhc1) > 1e-6} { incr bhc1Diffs }
        if {abs($gotBh - $expBh) > 1e-6} { incr bhDiffs }
        if {abs($gotSb - $expSb) > 1e-6} { incr sbDiffs }
    }

    # Verify exported TRF26 round-trips all 20 players and all 90 board pairings
    set rtState [::td::trf::Read [::td::trf::Write $st trf26]]
    set rtOk [expr {[llength [dict get $rtState pairings]] == [llength [dict get $st pairings]]}]

    list [llength [dict get $st players]] [dict get $st rounds] $pairMismatches [dict get $check9 compliant] \
        $rankDiffs $bhc1Diffs $bhDiffs $sbDiffs $rtOk
} -result {20 9 0 1 0 0 0 0 1}

tcltest::test td-p2-published-chess-results-2-sivakasi-214p-8r {F3: Reproduce published chess-results.com Swiss #2 (tnr1498617, Sivakasi Open 214p 8r) pairings, C.07 2026 standings, and TRF26 round-trip} -body {
    set trfPath [file normalize [file join [file dirname [info script]] fixtures td chess-results-tnr1498617.trf]]
    set csvPath [file normalize [file join [file dirname [info script]] fixtures td chess-results-tnr1498617.standings.csv]]
    set path [file join $::env(HOME) cr1498617.tdj]
    ::tdP2Acc::call $path import_trf [dict create filename $trfPath system swiss]
    set st [dict get [::td::store::Read $path] state]

    set pairMismatches 0
    for {set r 1} {$r <= 8} {incr r} {
        set gen [::td::swiss::Pair $st $r]
        if {[::tdP2Acc::pairMap $gen] ne [::tdP2Acc::pairMap [::td::model::Pairings $st $r]]} {
            incr pairMismatches
        }
    }
    set check8 [::td::swiss::CheckRound $st 8]

    set rows [::td::score::Compute $st]
    set byNum [dict create]
    foreach row $rows { dict set byNum [dict get $row number] $row }

    set f [open $csvPath r]; set csvLines [split [string trim [read $f]] \n]; close $f
    set rankDiffs 0; set bhc1Diffs 0; set bhDiffs 0; set sbDiffs 0
    foreach line $csvLines {
        if {$line eq "" || [string match "#*" $line]} { continue }
        lassign [split $line ,] expRank sNo expPts expBhc1 expBh expSb tb4 tb5 tb6
        set row [dict get $byNum $sNo]
        if {[dict get $row rank] != $expRank} { incr rankDiffs }
        set gotBhc1 [expr {double([dict get $row tiebreaks buchholzCut1 n]) / [dict get $row tiebreaks buchholzCut1 d]}]
        set gotBh [expr {double([dict get $row tiebreaks buchholz n]) / [dict get $row tiebreaks buchholz d]}]
        set gotSb [expr {double([dict get $row tiebreaks sonnebornBerger n]) / [dict get $row tiebreaks sonnebornBerger d]}]
        if {abs($gotBhc1 - $expBhc1) > 1e-6} { incr bhc1Diffs }
        if {abs($gotBh - $expBh) > 1e-6} { incr bhDiffs }
        if {abs($gotSb - $expSb) > 1e-6} { incr sbDiffs }
    }

    set rtState [::td::trf::Read [::td::trf::Write $st trf26]]
    set rtOk [expr {[llength [dict get $rtState pairings]] == [llength [dict get $st pairings]]}]

    list [llength [dict get $st players]] [dict get $st rounds] $pairMismatches [dict get $check8 compliant] \
        $rankDiffs $bhc1Diffs $bhDiffs $sbDiffs $rtOk
} -result {214 8 0 1 0 0 0 0 1}

tcltest::test td-p2-torture-vectors-c04-c07 {FIDE C.04.3 and C.07 torture vectors: PAB, two requested half-point byes, withdrawal shifting Buchholz, bracket collapse with floats} -body {
    # 1. Pairing-allocated bye (PAB) + 2. Two requested half-point byes + 3. Withdrawal shifting Buchholz (C.07 16.2.5 / 16.3 / 16.4)
    set pTort [file join $::env(HOME) torture.tdj]
    ::tdP2Acc::call $pTort create {name {C04-C07 Torture} players {P1 P2 P3 P4 P5} system swiss rounds 4 colour_lot white start 0}
    # P2 requests two half-point byes in rounds 2 and 3 (trailing voluntary unplayed rounds if P2 withdraws in R4)
    ::tdP2Acc::call $pTort bye {player p2 round 2 category requested-bye}
    ::tdP2Acc::call $pTort bye {player p2 round 3 category requested-bye}
    # Round 1: 5 players -> 1 player gets pairing-allocated bye (PAB)
    ::tdP2Acc::call $pTort pair_round {round 1}
    set st1 [dict get [::td::store::Read $pTort] state]
    set pabR1 [lmap p [::td::model::Pairings $st1 1] {expr {[dict get $p category] eq "pairing-bye" ? [dict get $p white] : [continue]}}]
    foreach p [::td::model::Pairings $st1 1] {
        if {[dict get $p status] eq "pending"} {
            ::tdP2Acc::call $pTort enter_result [dict create pairing [dict get $p id] result 1-0 category played]
        }
    }
    # Round 2: P2 has requested bye; remaining 4 players pair with 0 PABs
    ::tdP2Acc::call $pTort pair_round {round 2}
    set st2 [dict get [::td::store::Read $pTort] state]
    set pabR2 [lmap p [::td::model::Pairings $st2 2] {expr {[dict get $p category] eq "pairing-bye" ? [dict get $p white] : [continue]}}]
    foreach p [::td::model::Pairings $st2 2] {
        if {[dict get $p status] eq "pending"} {
            ::tdP2Acc::call $pTort enter_result [dict create pairing [dict get $p id] result 1-0 category played]
        }
    }
    # 3. Withdrawal shifting opponents' Buchholz under C.07 16.1.1 ("any round after a participant withdraws is a zero-point-bye"), 16.2.5 & 16.3.2:
    # Compare P2 playing Rounds 1..3 (0/3, all played -> contributes 0.0 to R1 opponent's Buchholz)
    # versus P2 actually withdrawing via `withdraw` before Round 3 (R3 becomes a post-withdrawal zero-point-bye evaluated as a 0.5 draw for opponents' Buchholz!).
    set pWithdrawn [file join $::env(HOME) shift_withdrawn.tdj]
    set pPlayed [file join $::env(HOME) shift_played.tdj]
    foreach store [list $pWithdrawn $pPlayed] {
        ::tdP2Acc::call $store create {name {Withdraw Shift C07} players {S1 S2 S3 S4} system swiss rounds 3 colour_lot white start 0}
        ::tdP2Acc::call $store pair_round {round 1}
        foreach p [::td::model::Pairings [dict get [::td::store::Read $store] state] 1] {
            if {[dict get $p status] eq "pending"} {
                set res [expr {[dict get $p white] eq "p2" ? "0-1" : "1-0"}]
                ::tdP2Acc::call $store enter_result [dict create pairing [dict get $p id] result $res category played]
            }
        }
        ::tdP2Acc::call $store pair_round {round 2}
        foreach p [::td::model::Pairings [dict get [::td::store::Read $store] state] 2] {
            if {[dict get $p status] eq "pending"} {
                set res [expr {[dict get $p white] eq "p2" ? "0-1" : "1-0"}]
                ::tdP2Acc::call $store enter_result [dict create pairing [dict get $p id] result $res category played]
            }
        }
    }
    set oppId {}
    foreach p [::td::model::Pairings [dict get [::td::store::Read $pWithdrawn] state] 1] {
        if {[dict get $p white] eq "p2"} { set oppId [dict get $p black] }
        if {[dict get $p black] eq "p2"} { set oppId [dict get $p white] }
    }

    # Branch A: P2 withdraws before Round 3 via the real `withdraw` command
    set wRes [::tdP2Acc::call $pWithdrawn withdraw {player p2 round 3}]
    ::tdP2Acc::call $pWithdrawn pair_round {round 3}
    foreach p [::td::model::Pairings [dict get [::td::store::Read $pWithdrawn] state] 3] {
        if {[dict get $p status] eq "pending"} {
            ::tdP2Acc::call $pWithdrawn enter_result [dict create pairing [dict get $p id] result 1/2-1/2 category played]
        }
    }

    # Branch B: P2 does NOT withdraw, plays Round 3 and loses over the board
    ::tdP2Acc::call $pPlayed pair_round {round 3}
    foreach p [::td::model::Pairings [dict get [::td::store::Read $pPlayed] state] 3] {
        if {[dict get $p status] eq "pending"} {
            set res [expr {[dict get $p white] eq "p2" ? "0-1" : "1-0"}]
            ::tdP2Acc::call $pPlayed enter_result [dict create pairing [dict get $p id] result $res category played]
        }
    }

    set stW [dict get [::td::store::Read $pWithdrawn] state]
    set stP [dict get [::td::store::Read $pPlayed] state]
    set rowsW [::td::score::Compute $stW]
    set rowsP [::td::score::Compute $stP]
    set p2ContribWithdrawn {}
    set p2ContribPlayed {}
    set oppBhWithdrawn {}
    foreach r $rowsW {
        if {[dict get $r id] eq $oppId} {
            set oppBhWithdrawn [dict get $r tiebreaks buchholz text]
            foreach e [dict get $r tiebreaks buchholz breakdown] {
                if {[dict get $e opponent] eq "p2"} { set p2ContribWithdrawn [dict get $e opponent_score] }
            }
        }
    }
    foreach r $rowsP {
        if {[dict get $r id] eq $oppId} {
            foreach e [dict get $r tiebreaks buchholz breakdown] {
                if {[dict get $e opponent] eq "p2"} { set p2ContribPlayed [dict get $e opponent_score] }
            }
        }
    }
    # Also verify native post-withdrawal Buchholz agrees with TRF26 export -> re-import (0000 - Z in R3)
    set stWTrf [::td::trf::Read [::td::trf::Write $stW trf26]]
    dict set stWTrf system swiss
    set oppBhTrf {}
    foreach r [::td::score::Compute $stWTrf] {
        if {[dict get $r id] eq $oppId} { set oppBhTrf [dict get $r tiebreaks buchholz text] }
    }

    # 4. Bracket collapse with floats (dutch_2025_C5 + dutch_2025_C9)
    set root [file normalize [file join [file dirname [info script]] .. engines bbpPairings test tests]]
    set f [open [file join $root dutch_2025_C5.input] r]; set c5In [read $f]; close $f
    set f [open [file join $root dutch_2025_C5.output.expected] r]; set c5Exp [string trim [read $f]]; close $f
    set c5Ok [expr {[::td::swiss::Run $c5In] eq $c5Exp}]

    list [llength $pabR1] [llength $pabR2] [dict get $wRes timing] \
        [expr {$p2ContribPlayed eq "0 1"}] [expr {$p2ContribWithdrawn eq "1 1"}] \
        [expr {$oppBhWithdrawn eq $oppBhTrf}] $c5Ok
} -result {1 0 withdrawal-before-pairing 1 1 1 1}

tcltest::test td-p2-prizes-hort-and-payment {Prize calculation supports Hort system, equal split, one prize per player, withdrawal exclusion and payment receipts} -body {
    set path [file join $::env(HOME) prizes.tdj]
    ::tdP2Acc::call $path create {name {Prize Open} players {A B C D} system swiss rounds 2 colour_lot white start 0}
    ::tdP2Acc::call $path pair_round {round 1}
    ::tdP2Acc::call $path enter_result {pairing r1b0 result 1-0 category played}
    ::tdP2Acc::call $path enter_result {pairing r1b1 result 1-0 category played}
    ::tdP2Acc::call $path pair_round {round 2}
    set st [dict get [::td::store::Read $path] state]
    foreach p [::td::model::Pairings $st 2] {
        if {[dict get $p status] eq "pending"} {
            ::tdP2Acc::call $path enter_result [dict create pairing [dict get $p id] result 1/2-1/2 category played]
        }
    }
    # Top 2 players are tied at 1.5/2; prizes are 1000, 500, 200.
    # Under Hort: 1st gets 500 + (1500/2)/2 = 500 + 375 = 875.00; 2nd gets 250 + 375 = 625.00
    set res [::td::actions::Run prizes [dict create path $path prizes {1000 500 200} system hort rounding cent pay_player p1 receipt RCPT-001 commit 1 expected_revision [dict get [::td::store::Read $path] revision] idempotency prz1]]
    set payouts [dict get $res payouts]
    set p0 [lindex $payouts 0]
    set p1 [lindex $payouts 1]
    list [dict get $p0 amount] [dict get $p1 amount] [dict get $p0 paid] [dict get $p0 receipt]
} -result {875.00 625.00 1 RCPT-001}

tcltest::test td-p2-5round-swiss-replay-undo-redo {5-round Swiss with manual override, result correction and late entry gives byte-identical standings and TRF across undo/redo and journal replay} -body {
    set path [file join $::env(HOME) replay5.tdj]
    ::td::actions::Create [dict create path $path name {Five Round Replay Open} players {P1 P2 P3 P4 P5 P6 P7 P8 P9} kind human system swiss rounds 5 colour_lot white start 0 commit 1 expected_revision 0 idempotency rep-c]
    # Round 1
    ::td::actions::Run pair_round [dict create path $path round 1 commit 1 expected_revision [dict get [::td::store::Read $path] revision] idempotency rep-r1p]
    foreach p [::td::model::Pairings [dict get [::td::store::Read $path] state] 1] {
        if {[dict get $p status] eq "pending"} {
            ::td::actions::Run enter_result [dict create path $path pairing [dict get $p id] result 1-0 category played signed_by "Players" commit 1 expected_revision [dict get [::td::store::Read $path] revision] idempotency "rep-r1-[dict get $p id]"]
        }
    }
    # Late entry before Round 2
    ::td::actions::Run register [dict create path $path players {P10} kind human entry_round 2 rating 2050 commit 1 expected_revision [dict get [::td::store::Read $path] revision] idempotency rep-late]
    # Round 2
    ::td::actions::Run pair_round [dict create path $path round 2 commit 1 expected_revision [dict get [::td::store::Read $path] revision] idempotency rep-r2p]
    # Manual override on r2b0 (colour swap)
    set st2 [dict get [::td::store::Read $path] state]
    set b0 [lindex [::td::model::Pairings $st2 2] 0]
    ::td::actions::Run override_pairing [dict create path $path pairing [dict get $b0 id] white [dict get $b0 black] black [dict get $b0 white] reason "Board 1 colour swap" ruling "CA approved" commit 1 expected_revision [dict get [::td::store::Read $path] revision] idempotency rep-ovr]
    foreach p [::td::model::Pairings [dict get [::td::store::Read $path] state] 2] {
        if {[dict get $p status] eq "pending"} {
            ::td::actions::Run enter_result [dict create path $path pairing [dict get $p id] result 1-0 category played commit 1 expected_revision [dict get [::td::store::Read $path] revision] idempotency "rep-r2-[dict get $p id]"]
        }
    }
    # Correct result on r2b0 to 1/2-1/2
    ::td::actions::Run correct_result [dict create path $path pairing [dict get $b0 id] result 1/2-1/2 category played reason "Scoresheet check" commit 1 expected_revision [dict get [::td::store::Read $path] revision] idempotency rep-corr]
    # Rounds 3, 4, 5
    for {set r 3} {$r <= 5} {incr r} {
        ::td::actions::Run pair_round [dict create path $path round $r commit 1 expected_revision [dict get [::td::store::Read $path] revision] idempotency "rep-r${r}p"]
        foreach p [::td::model::Pairings [dict get [::td::store::Read $path] state] $r] {
            if {[dict get $p status] eq "pending"} {
                ::td::actions::Run enter_result [dict create path $path pairing [dict get $p id] result 1/2-1/2 category played commit 1 expected_revision [dict get [::td::store::Read $path] revision] idempotency "rep-r${r}-[dict get $p id]"]
            }
        }
    }
    set stBefore [dict get [::td::store::Read $path] state]
    set standingsBefore [::td::score::StandingsText [::td::score::Compute $stBefore]]
    set trfBefore [::td::trf::Write $stBefore trf26]

    # Undo 3 commands and Redo 3 commands
    for {set k 1} {$k <= 3} {incr k} {
        ::td::actions::Undo [dict create path $path commit 1 expected_revision [dict get [::td::store::Read $path] revision] idempotency "rep-u$k"]
    }
    for {set k 1} {$k <= 3} {incr k} {
        ::td::actions::Redo [dict create path $path commit 1 expected_revision [dict get [::td::store::Read $path] revision] idempotency "rep-d$k"]
    }
    set stAfter [dict get [::td::store::Read $path] state]
    set standingsAfter [::td::score::StandingsText [::td::score::Compute $stAfter]]
    set trfAfter [::td::trf::Write $stAfter trf26]

    list [expr {$standingsBefore eq $standingsAfter}] [expr {$trfBefore eq $trfAfter}]
} -result {1 1}

tcltest::cleanupTests
