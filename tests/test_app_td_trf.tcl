package require tcltest 2.5

namespace eval ::tdTrf { variable counter 0 }
proc ::tdTrf::call {path cmd domain} {
    variable counter
    ::td::command::Execute $cmd [dict merge $domain [dict create path $path commit 1 expected_revision [dict get [::td::store::Read $path] revision] idempotency trf[incr counter]]]
}

tcltest::test td-trf16-trf26-roundtrip-and-eligibility {TRF16 and TRF26 export/import round-trip preserves players, pairings, byes, forfeits and standings; engine events are rejected for FIDE report} -body {
    set path1 [file join $::env(HOME) src.tdj]
    ::tdTrf::call $path1 create {name {Spring Open 2026} players {Alice Bob Carol Dave Eve} system swiss rounds 3 colour_lot black start 0}
    ::tdTrf::call $path1 bye {player p5 round 1 category requested-bye}
    ::tdTrf::call $path1 pair_round {round 1}
    ::tdTrf::call $path1 enter_result {pairing r1b0 result 1-0 category played}
    ::tdTrf::call $path1 enter_result {pairing r1b1 result 0-1 category forfeit}
    ::tdTrf::call $path1 pair_round {round 2}
    set st1 [dict get [::td::store::Read $path1] state]
    foreach p [::td::model::Pairings $st1 2] {
        if {[dict get $p status] eq "pending"} {
            ::tdTrf::call $path1 enter_result [dict create pairing [dict get $p id] result 1/2-1/2 category played]
        }
    }
    set f16 [file join $::env(HOME) out16.trf]
    set f26 [file join $::env(HOME) out26.trf]
    set exp16 [::td::actions::Export [dict create path $path1 filename $f16 format trf16 overwrite 1]]
    set exp26 [::td::actions::Export [dict create path $path1 filename $f26 format trf26 overwrite 1]]
    set path16 [file join $::env(HOME) imp16.tdj]
    set path26 [file join $::env(HOME) imp26.tdj]
    ::tdTrf::call $path16 import_trf [dict create filename $f16 system swiss]
    ::tdTrf::call $path26 import_trf [dict create filename $f26 system swiss]
    set stOrig [dict get [::td::store::Read $path1] state]
    set stImp16 [dict get [::td::store::Read $path16] state]
    set stImp26 [dict get [::td::store::Read $path26] state]
    set sOrig [::td::score::StandingsText [::td::score::Compute $stOrig]]
    set s16 [::td::score::StandingsText [::td::score::Compute $stImp16]]
    set s26 [::td::score::StandingsText [::td::score::Compute $stImp26]]
    # Re-exporting imported TRF26 produces byte-identical TRF26
    set re26 [::td::trf::Write $stImp26 trf26]
    # Engine tournament is rejected for FIDE TRF export
    set engState [dict replace $stOrig players [list [dict replace [lindex [dict get $stOrig players] 0] kind engine]]]
    set elig [::td::trf::ValidateEligibility $engState]
    list [expr {$sOrig eq $s16}] [expr {$sOrig eq $s26}] [expr {$re26 eq [dict get $exp26 text]}] [dict get $elig fide_eligible]
} -result {1 1 1 0}

tcltest::cleanupTests
