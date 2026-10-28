package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
namespace eval ::scidb::test::presetform {
    proc apply {} {
        variable result
        set result {}
        if {[catch {
            foreach preset {Chess960 Symm960 Shuffle 4015 4012} {
                set fen [::knowledge::RunAction board.start_preset [list preset $preset target setup]]
                if {[string match error:* $fen]} {error $fen}
                lappend result [expr {[::scidb::board::fenToBoard $fen] eq $::setup::board::Vars(pos)}]
            }
        } err]} {set result $err}
        destroy .application.setup_board
    }
}
tcltest::test inventory-preset-form {named and numeric presets change the existing native setup form without changing the game} -setup {
    ::scidb::test::actions::ready
    set gameFen [::scidb::pos::fen]
} -body {
    after 250 ::scidb::test::presetform::apply
    ::setup::board::open .application
    concat $::scidb::test::presetform::result [expr {[::scidb::pos::fen] eq $gameFen}]
} -cleanup {catch {destroy .application.setup_board}} -result {1 1 1 1 1 1}
tcltest::cleanupTests
