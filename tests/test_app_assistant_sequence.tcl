package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

tcltest::test assistant-sequence-notation-show {discovered notation operator opens the editor on repeated requests} -body {
 set answers {}
 foreach i {1 2 3} {
  set reply [::application::assistant::runTool run_action {id c9.pane.notation}]
  update
  lappend answers [list [string match error:* $reply] [::menu::PaneChecked editor]]
 }
 set answers
} -result {{0 1} {0 1} {0 1}}

tcltest::test assistant-sequence-new-position {a user-provided line survives new-game replacement and accepts the next setup line} -setup {
 set savedMessages $::application::assistant::Priv(messages)
} -body {
 set ::application::assistant::Priv(messages) [list [dict create role user content {Set up c4 e5 Nc3 Nf6, then a new game, then Nf3 d5.}]]
 set a [::application::assistant::runTool set_position {moves {c4 e5 Nc3 Nf6}}]
 set b [::application::assistant::runTool new_game {}]
 set ::application::assistant::Priv(messages) [list [dict create role user content {Set up Nf3 d5.}]]
 set c [::application::assistant::runTool set_position {moves {Nf3 d5}}]
 update
 list [string match error:* $a] [string match error:* $b] [string match error:* $c] [::scidb::pos::fen]
} -cleanup {
 set ::application::assistant::Priv(messages) $savedMessages
} -result {0 0 0 {rnbqkbnr/ppp1pppp/8/3p4/8/5N2/PPPPPPPP/RNBQKB1R w KQkq - 0 2}}

# Replay the public development sequence's actions with native state checks.
# Model selection is covered by the separate live Ask run, not this replay.
namespace eval ::sequenceTest {}
proc ::sequenceTest::run {name args} {
 # This replay represents explicit user moves, not model-authored theory.
 if {$name eq "set_position"} {
  set ::application::assistant::Priv(messages) [list [dict create role user content "Set up [dict get $args moves]"]]
 }
 set reply [::application::assistant::runTool $name $args]
 if {[string match error:* $reply]} {error "$name: $reply"}
 update
}
proc ::sequenceTest::fen {moves} {
 expr {[::scidb::pos::fen] eq [dict get [::ai::setup::validate -moves $moves] fen]}
}
tcltest::test assistant-sequence-dev-actions {all fifteen development state predicates survive sequential pane and game operations} -setup {
 set savedMessages $::application::assistant::Priv(messages)
} -body {
 set checks {}
 ::sequenceTest::run set_position moves {d4 d5 c4 e6}
 lappend checks [::sequenceTest::fen {d4 d5 c4 e6}]
 ::sequenceTest::run goto_move move 2
 lappend checks [::sequenceTest::fen {d4 d5}]
 ::sequenceTest::run run_action id nav-end
 lappend checks [::sequenceTest::fen {d4 d5 c4 e6}]
 ::sequenceTest::run switch_tab tab database
 lappend checks [expr {[::application::activeTab] eq "database"}]
 ::sequenceTest::run switch_tab tab board
 lappend checks [expr {[::application::activeTab] eq "board"}]
 ::sequenceTest::run pane action show pane tree
 lappend checks [::menu::PaneChecked tree]
 ::sequenceTest::run pane action hide pane tree
 lappend checks [expr {![::menu::PaneChecked tree]}]
 ::sequenceTest::run pane action show pane report
 ::sequenceTest::run pane action hide pane report
 lappend checks [expr {![::menu::PaneChecked report]}]
 ::sequenceTest::run set_position moves {e4 e5 Nf3 Nc6}
 ::sequenceTest::run goto_move move 2
 lappend checks [::sequenceTest::fen {e4 e5}]
 ::sequenceTest::run switch_tab tab database
 ::sequenceTest::run switch_tab tab board
 lappend checks [expr {[::application::activeTab] eq "board"}]
 ::sequenceTest::run set_position moves {c4 e5 Nc3 Nf6}
 ::sequenceTest::run run_action id nav-start
 lappend checks [::sequenceTest::fen {}]
 ::sequenceTest::run pane action show pane tree
 ::sequenceTest::run pane action hide pane tree
 ::sequenceTest::run switch_tab tab board
 lappend checks [expr {![::menu::PaneChecked tree] && [::application::activeTab] eq "board"}]
 ::sequenceTest::run run_action id c9.pane.notation
 lappend checks [::menu::PaneChecked editor]
 ::sequenceTest::run new_game
 lappend checks [::sequenceTest::fen {}]
 ::sequenceTest::run set_position moves {Nf3 d5}
 lappend checks [::sequenceTest::fen {Nf3 d5}]
 puts "DEV_SEQUENCE_PREDICATES $checks"
 set checks
} -cleanup {
 set ::application::assistant::Priv(messages) $savedMessages
} -result {1 1 1 1 1 1 1 1 1 1 1 1 1 1 1}

tcltest::cleanupTests
