package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

tcltest::test board-rebuild-item-count {repeated layout redraws replace square markers rather than accumulating canvas items} -body {
 ::application::switchTab board
 update
 set board $::application::board::board
 ::board::diagram::rebuild $board
 set before [llength [$board.c find all]]
 for {set n 0} {$n < 20} {incr n} {::board::diagram::rebuild $board}
 set after [llength [$board.c find all]]
 puts "BOARD_ITEMS before=$before after=$after"
 expr {$before == $after}
} -result 1

tcltest::cleanupTests
