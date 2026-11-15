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

tcltest::cleanupTests
