package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::gameclear {
    variable fen {8/8/8/4k3/8/8/4KP2/8 w - - 0 1}
    variable start {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}
}

tcltest::test gameclear-fen {clear accepts FEN without leaking an integer parse error} -body {
    set result [::scidb::game::clear $::scidb::test::gameclear::fen]
    list $result [::scidb::pos::fen]
} -result [list {} $::scidb::test::gameclear::fen]

tcltest::test gameclear-idn {clear accepts the orthodox start position IDN} -body {
    set result [::scidb::game::clear 518]
    list $result [::scidb::pos::fen]
} -result [list {} $::scidb::test::gameclear::start]

tcltest::cleanupTests
