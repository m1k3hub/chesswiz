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
tcltest::cleanupTests
