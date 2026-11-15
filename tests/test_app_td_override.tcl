package require tcltest 2.5

namespace eval ::tdOverride { variable counter 0 }
proc ::tdOverride::call {path cmd domain} {
    variable counter
    ::td::command::Execute $cmd [dict merge $domain [dict create path $path commit 1 expected_revision [dict get [::td::store::Read $path] revision] idempotency ov[incr counter]]]
}

tcltest::test td-override-checker-and-audit {bbpPairings -c and C.04.3 checker flag discrepancies and prohibited rematches; TD ruling never marks a prohibited pairing compliant} -body {
    set path [file join $::env(HOME) override.tdj]
    ::tdOverride::call $path create {name {Swiss Override} players {A B C D} system swiss rounds 3 start 1}
    # Round 1 initial pairings from bbpPairings are compliant
    set chk1 [::td::actions::CheckPairings [dict create path $path round 1]]
    set initialCompliant [dict get $chk1 compliant]
    # Swap colours on r1b0: creates a quality/colour discrepancy vs bbpPairings -c
    set swap1 [::tdOverride::call $path override_pairing {pairing r1b0 white p3 black p1 reason {Swap colours on board 1}}]
    set swapCompliant [dict get $swap1 compliant]
    set swapBbp [string match "*Checker pairings*" [dict get $swap1 bbp_report]]
    # Complete round 1
    ::tdOverride::call $path enter_result {pairing r1b0 result 1-0 category played}
    ::tdOverride::call $path enter_result {pairing r1b1 result 1-0 category played}
    # Pair round 2
    ::tdOverride::call $path pair_round {round 2}
    # Attempt prohibited C1 rematch (p3 vs p1 again) without a TD ruling -> must be rejected
    set noRuling [catch {::tdOverride::call $path override_pairing {pairing r2b0 white p1 black p3 reason {Force rematch}}}]
    # With an explicit TD ruling, the override is recorded in the audit log, but compliant remains 0
    set withRuling [::tdOverride::call $path override_pairing {pairing r2b0 white p1 black p3 reason {Force rematch} ruling {Chief Arbiter exception logged}}]
    set st [dict get [::td::store::Read $path] state]
    set p0 [lindex [::td::model::Pairings $st 2] 0]
    set codes [lmap v [dict get $withRuling violations] {dict get $v code}]
    list $initialCompliant $swapCompliant $swapBbp $noRuling [dict get $withRuling compliant] [expr {"C1-REMATCH" in $codes}] [dict get $p0 override compliant] [llength [dict get $st rulings]]
} -result {1 0 1 1 0 1 0 1}

tcltest::test td-override-f4-checker-fail-closed {F4: missing or broken bbpPairings -c helper fails closed with C04-CHECKER-UNAVAILABLE and compliant=0} -body {
    set path [file join $::env(HOME) override_f4.tdj]
    ::tdOverride::call $path create {name {Swiss Fail Closed} players {A B C D} system swiss rounds 3 start 1}
    set hadEnv [info exists ::env(SCIDB_BBP_PAIRINGS)]
    if {$hadEnv} { set savedEnv $::env(SCIDB_BBP_PAIRINGS) }
    set brokenHelper [file join $::env(HOME) broken-bbp.sh]
    set fh [open $brokenHelper w]
    puts $fh "#!/bin/sh\necho ' simulated crash' >&2\nexit 2"
    close $fh
    file attributes $brokenHelper -permissions 0755
    try {
        # 1. Missing helper path
        set ::env(SCIDB_BBP_PAIRINGS) [file join $::env(HOME) no-such-bbpPairings]
        set chkMissing [::td::actions::CheckPairings [dict create path $path round 1]]
        set codesMissing [lmap v [dict get $chkMissing violations] {dict get $v code}]
        set rejectWithoutRuling [catch {
            ::tdOverride::call $path override_pairing {pairing r1b0 white p3 black p1 reason {Swap colours with missing helper}}
        }]

        # 2. Crashing helper executable
        set ::env(SCIDB_BBP_PAIRINGS) $brokenHelper
        set chkBroken [::td::actions::CheckPairings [dict create path $path round 1]]
        set codesBroken [lmap v [dict get $chkBroken violations] {dict get $v code}]
        set ruledOverride [::tdOverride::call $path override_pairing {
            pairing r1b0 white p3 black p1 reason {Swap colours under broken helper} ruling {CA emergency manual verification}
        }]
    } finally {
        if {$hadEnv} {
            set ::env(SCIDB_BBP_PAIRINGS) $savedEnv
        } else {
            unset -nocomplain ::env(SCIDB_BBP_PAIRINGS)
        }
    }
    list [dict get $chkMissing compliant] [dict get $chkMissing bbp_discrepancy] [expr {"C04-CHECKER-UNAVAILABLE" in $codesMissing}] \
        $rejectWithoutRuling [dict get $chkBroken compliant] [expr {"C04-CHECKER-UNAVAILABLE" in $codesBroken}] [dict get $ruledOverride compliant]
} -result {0 1 1 1 0 1 0}

tcltest::test td-override-f6-final-round-c3-absolute-colour {F6: C3 absolute-colour violation is enforced in the final round for non-topscorers} -body {
    set path [file join $::env(HOME) override_f6.tdj]
    ::tdOverride::call $path create {name {Final Round C3} players {P1 P2 P3 P4 P5 P6} system swiss rounds 3 colour_lot white start 1}
    # Round 1: all draws (every player has 0.5 <= 1.5; R1 colours: p1 W vs p4 B, p5 W vs p2 B, p3 W vs p6 B)
    foreach p [::td::model::Pairings [dict get [::td::store::Read $path] state] 1] {
        ::tdOverride::call $path enter_result [dict create pairing [dict get $p id] result 1/2-1/2 category played]
    }
    ::tdOverride::call $path pair_round {round 2}
    # Force p1 to have White again in Round 2 (with ruling if needed) so p1 has {W W} entering final Round 3 with score <= 1.0 (non-topscorer: <= 50% of 3)
    set st2 [dict get [::td::store::Read $path] state]
    set r2b0 [lindex [::td::model::Pairings $st2 2] 0]
    set opp2 [expr {[dict get $r2b0 white] eq "p1" ? [dict get $r2b0 black] : [dict get $r2b0 white]}]
    if {[dict get $r2b0 white] ne "p1"} {
        ::tdOverride::call $path override_pairing [dict create pairing [dict get $r2b0 id] white p1 black $opp2 reason {Setup WW history} ruling {Setup}]
    }
    foreach p [::td::model::Pairings [dict get [::td::store::Read $path] state] 2] {
        ::tdOverride::call $path enter_result [dict create pairing [dict get $p id] result 1/2-1/2 category played]
    }
    # Pair final Round 3: all players have 1.0 / 3.0 (<= 50% max score -> NO topscorers per C.04.3 1.8)
    ::tdOverride::call $path pair_round {round 3}
    set st3 [dict get [::td::store::Read $path] state]
    set p1Board {}
    set p1Opp {}
    foreach p [::td::model::Pairings $st3 3] {
        if {[dict get $p white] eq "p1" || [dict get $p black] eq "p1"} {
            set p1Board [dict get $p id]
            set p1Opp [expr {[dict get $p white] eq "p1" ? [dict get $p black] : [dict get $p white]}]
        }
    }
    # Override final-round board to give non-topscorer p1 a 3rd consecutive White without a TD ruling -> must fail C3
    set rejectedNoRuling [catch {
        ::tdOverride::call $path override_pairing [dict create pairing $p1Board white p1 black $p1Opp reason {Third White in final round}]
    }]
    set withRuling [::tdOverride::call $path override_pairing [dict create pairing $p1Board white p1 black $p1Opp reason {Third White in final round} ruling {CA exception}]]
    set codes [lmap v [dict get $withRuling violations] {dict get $v code}]
    list $rejectedNoRuling [dict get $withRuling compliant] [expr {"C3-ABSOLUTE-COLOUR" in $codes}]
} -result {1 0 1}

tcltest::cleanupTests
