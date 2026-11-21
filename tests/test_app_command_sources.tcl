package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready
::tcltest::test command-live-tabs {only existing notebook tabs are offered} -body {
 ::commandline::AppSource tab data
} -result database
::tcltest::test command-live-motifs {pattern names come from the pattern index} -body {
 expr {"knight_fork" in [::commandline::AppSource motif {knight fork}]}
} -result 1
::tcltest::test command-live-moves {current board checks moves without playing them} -body {
 ::scidb::game::clear {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}
 set before [::scidb::pos::fen]
 list [::commandline::AppSource move e4] [::commandline::AppSource move e5] [expr {$before eq [::scidb::pos::fen]}]
} -result {e4 {} 1}
::tcltest::cleanupTests
