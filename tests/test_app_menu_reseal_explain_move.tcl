# VS/VU-reg4: current Move reaches the existing explanation boundary.
package require tcltest 2.5
source tests/app_actions_support.tcl
source tests/app_menu_reseal_scope_support.tcl
::scidb::test::actions::ready
::scidb::test::askscope::NewGame
::application::ai::configure -provider stub -model {}
::ai::provider::configure -name stub -model {}
proc ::resealMoveBoundary {command operation} {
 set ::resealMovePayload $command
 error RESEAL_EXPLANATION_BOUNDARY
}
tcltest::test reseal-explain-current-move {midgame Move passes the current game slot, SAN and preceding position} -body {
 ::scidb::game::go 2
 update
 set slot [::scidb::game::current]
 set key [::scidb::game::position key]
 set san [::scidb::game::query move $key]
 set fen [::scidb::game::query movefen $key]
 set ::resealMovePayload {}
 trace add execution ::application::ai::explainSelection enter ::resealMoveBoundary
 set reply [::action::run menu.analysis.explain.move]
 puts [list MOVE_EXPLANATION slot $slot key $key san $san fen $fen call $::resealMovePayload reply $reply]
 list [lrange $::resealMovePayload 1 end] [string match *RESEAL_EXPLANATION_BOUNDARY* $reply]
} -cleanup {
 trace remove execution ::application::ai::explainSelection enter ::resealMoveBoundary
} -result [list [list .application move [list e5 {rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1}]] 1]
tcltest::test reseal-explain-empty-move {no selected move returns a clear error} -body {
 ::scidb::game::go start
 update
 set reply [::action::run menu.analysis.explain.move]
 puts [list MOVE_START_ERROR $reply]
 string match {error:*move*} $reply
} -result 1
::scidb::test::actions::release
::tcltest::cleanupTests
