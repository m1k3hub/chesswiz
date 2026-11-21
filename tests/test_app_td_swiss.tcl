package require tcltest 2.5

tcltest::test td-bbp-upstream-goldens {pinned upstream Dutch C5/C9 regression goldens} -body {
    set root [file normalize [file join [file dirname [info script]] .. engines bbpPairings test tests]]
    set outcomes {}
    foreach name {dutch_2025_C5 dutch_2025_C9} {
        set f [open [file join $root $name.input]]; set text [read $f]; close $f
        set f [open [file join $root $name.output.expected]]; set expected [string trim [read $f]]; close $f
        lappend outcomes [expr {[::td::swiss::Run $text] eq $expected}]
    }
    return $outcomes
} -result {1 1}

tcltest::test td-helper-validate {unknown, duplicate, omitted and malformed output rejected} -body {
    set out {}
    foreach text [list "2\n1 2\n1 3" "1\n1 4" "1\n1 2" "oops"] { lappend out [catch {::td::swiss::Parse $text {1 2 3}}] }
    return $out
} -result {1 1 1 1}

tcltest::test td-helper-absent {explicit missing helper fails closed} -body {
    set ::env(SCIDB_BBP_PAIRINGS) /nonexistent/td-helper
    catch {::td::swiss::Executable} message
    unset ::env(SCIDB_BBP_PAIRINGS)
    string match *unavailable* $message
} -result 1

tcltest::test td-swiss-command-flow {Swiss previews, sequential pairing and results use the journal} -body {
    set path [file join $::env(HOME) swiss.tdj]
    set args [dict create path $path name Swiss kind human players {A B C D} system swiss rounds 3 start 0 commit 0 expected_revision 0 idempotency create]
    set preview [::td::command::Execute create $args]
    set clean [expr {![file exists $path]}]
    ::td::command::Execute create [dict replace $args commit 1]
    set args [dict create path $path round 1 commit 0 expected_revision 1 idempotency pair]
    ::td::command::Execute pair_round $args
    set result [::td::command::Execute pair_round [dict replace $args commit 1]]
    set st [dict get $result state]
    set seats [lmap p [dict get $st pairings] {list [dict get $p white] [dict get $p black]}]
    set rejects [catch {::td::command::Execute pair_round [dict replace $args round 2 commit 1 expected_revision 2 idempotency early]}]
    list $clean $seats $rejects [dict get [::td::store::Read $path] revision]
} -result {1 {{p1 p3} {p4 p2}} 1 2}

tcltest::cleanupTests
