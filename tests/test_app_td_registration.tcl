package require tcltest 2.5
tcltest::test td-fide-snapshot {local FIDE lookup is frozen at preview and late entry has a first round} -setup {
    rename ::scidb::player::lookup ::scidb::player::td_saved_lookup
    proc ::scidb::player::lookup {args} { return {name {Test, Player} fideID 123 elo 2100 federation ENG titles {FM} sex m born 2000.01.01} }
} -body {
    set path [file join $::env(HOME) fide.tdj]
    ::td::command::Execute create [dict create path $path name Test system swiss rounds 3 players {A B C D} start 0 commit 1 expected_revision 0 idempotency c]
    set args [dict create path $path fide_id 123 commit 0 expected_revision 1 idempotency f]
    set preview [::td::command::Execute register_fide $args]
    proc ::scidb::player::lookup {args} { error "rating list changed" }
    set result [::td::command::Execute register_fide [dict replace $args commit 1]]
    set p [lindex [dict get $result state players] end]
    ::td::command::Execute pair_round [dict create path $path round 1 commit 1 expected_revision 2 idempotency pair]
    set late [::td::command::Execute register [dict create path $path players Late kind human commit 1 expected_revision 3 idempotency late]]
    list [dict get $p fide_id] [dict get $p rating] [dict get $p title] [dict get $late entry_round] [dict get $preview preview]
} -cleanup {
    rename ::scidb::player::lookup {}
    rename ::scidb::player::td_saved_lookup ::scidb::player::lookup
} -result {123 2100 FM 2 1}

tcltest::test td-registration-f8-late-entry-ignores-future-byes-and-honours-entry-round {F8: late-entry entry_round ignores future requested byes, honours valid caller entry_round, and rejects already-paired rounds} -body {
    set path [file join $::env(HOME) fide_f8.tdj]
    ::action::run td.create [dict create path $path name {Late Entry Open} system swiss rounds 5 players {P1 P2 P3 P4} kind human start 0 commit 1 expected_revision 0 idempotency f8-c]
    # Existing player P1 pre-books a requested bye in Round 4
    ::action::run td.bye [dict create path $path player p1 round 4 category requested-bye commit 1 expected_revision 1 idempotency f8-bye4]
    # Pair and finish Round 1
    ::action::run td.pair_round [dict create path $path round 1 commit 1 expected_revision 2 idempotency f8-r1]
    ::action::run td.enter_result [dict create path $path pairing r1b0 result 1-0 category played commit 1 expected_revision 3 idempotency f8-res0]
    ::action::run td.enter_result [dict create path $path pairing r1b1 result 1/2-1/2 category played commit 1 expected_revision 4 idempotency f8-res1]

    # 1. Default late entry before Round 2 must get entry_round 2 (not 5 from P1's Round 4 bye)
    set regDef [::action::run td.register [dict create path $path players {LateDefault} kind human commit 1 expected_revision 5 idempotency f8-late-def]]
    set defEntry [dict get $regDef entry_round]

    # 2. Explicit future entry_round 3 must be honoured as 3
    set regExp3 [::action::run td.register [dict create path $path players {LateExplicit3} kind human entry_round 3 rating 1950 commit 1 expected_revision 6 idempotency f8-late-exp3]]
    set exp3Entry [dict get $regExp3 entry_round]

    # 3. Explicit entry_round 1 (already paired) and entry_round 6 (> rounds) must be rejected
    set resPast [::action::run td.register [dict create path $path players {TooEarly} kind human entry_round 1 commit 1 expected_revision 7 idempotency f8-err-past]]
    set resBeyond [::action::run td.register [dict create path $path players {TooLate} kind human entry_round 6 commit 1 expected_revision 7 idempotency f8-err-beyond]]
    set errPast [string match "error:*" $resPast]
    set errBeyond [string match "error:*" $resBeyond]

    # Pair Round 2: P1, P2, P3, P4 + LateDefault (p5) = 5 active players (2 boards + 1 PAB); LateExplicit3 (p6) waits until Round 3
    ::action::run td.pair_round [dict create path $path round 2 commit 1 expected_revision 7 idempotency f8-r2]
    set st [dict get [::td::store::Read $path] state]
    set r2Players {}
    foreach p [::td::model::Pairings $st 2] {
        foreach side {white black} {
            set pid [dict get $p $side]
            if {$pid ne ""} { lappend r2Players $pid }
        }
    }
    list $defEntry $exp3Entry $errPast $errBeyond [expr {"p5" in $r2Players}] [expr {"p6" ni $r2Players}]
} -result {2 3 1 1 1 1}

tcltest::cleanupTests
