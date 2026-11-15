package require tcltest 2.5
namespace eval ::tdOtb { variable counter 0 }
proc ::tdOtb::call {path cmd domain} {
    variable counter
    ::td::command::Execute $cmd [dict merge $domain [dict create path $path commit 1 expected_revision [dict get [::td::store::Read $path] revision] idempotency otb[incr counter]]]
}
tcltest::test td-otb-adjourned-signed {adjournment blocks next round; signed corrections require reason} -body {
    set path [file join $::env(HOME) otb.tdj]
    ::tdOtb::call $path create {name OTB players {A B C D} system swiss rounds 3 start 1}
    ::tdOtb::call $path enter_result {pairing r1b0 result * category adjourned}
    ::tdOtb::call $path enter_result {pairing r1b1 result 1-0 category played signed_by {Both players}}
    set blocked [catch {::tdOtb::call $path pair_round {round 2}}]
    ::tdOtb::call $path enter_result {pairing r1b0 result 1/2-1/2 category played signed_by {Both players}}
    set correction [catch {::tdOtb::call $path correct_result {pairing r1b0 result 1-0 category played}}]
    ::tdOtb::call $path correct_result {pairing r1b0 result 1-0 category played reason {Scoresheet checked} signed_by {Chief arbiter}}
    set st [dict get [::td::store::Read $path] state]
    set p [lindex [dict get $st pairings] 0]
    list $blocked $correction [dict get $p signed_by] [llength [dict get $p result_history]]
} -result {1 1 {Chief arbiter} 1}
tcltest::cleanupTests
