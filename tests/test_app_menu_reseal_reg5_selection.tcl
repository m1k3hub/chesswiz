package require tcltest 2.5
source tests/app_actions_support.tcl
::scidb::test::actions::ready
set base [::scidb::test::actions::fixture]
set ch [open $base r];set text [read $ch];close $ch
set ch [open $base a];puts $ch [string map {{Generated test} {Second game}} $text];close $ch
::action::run open_database [list path $base]
::action::run open_game {number 1 move 1 after white}
::application::switchTab database
for {set i 0} {$i<10} {incr i} {after 30;update}
set manager $::application::database::Vars(games).twm
set table [set ::application::database::games::${manager}::Priv(table)]
puts [list TABLE $table]
::gamestable::select $table 1
::gamestable::activate $table 1
focus -force $table
update
puts [list SELECTED [::gamestable::selection $table] CURRENT [::context::CurrentObject C3]]
tcltest::test c3-current-selection {game-row action follows selected row without loading or popup} -body {
set before [::context::CurrentObject C3]
set reply [::action::run c3.load]
update
puts [list C3_RUN reply $reply before $before loaded [::scidb::game::link? [::scidb::game::current]]]
list [dict get $before index] [lindex [::scidb::game::link? [::scidb::game::current]] 2]
} -result {1 1}
source tests/app_menu_reseal_scope_support.tcl
menu .c3 -tearoff 0
::gamestable::PopupMenu $table .c3 $base Normal 1 white
set posted [::scidb::test::askscope::PostedIds .c3 C3]
set ask [::scidb::test::askscope::AskContextIds C3]
puts [list C3_PARITY selected [::gamestable::selection $table] posted $posted ask $ask]
set row -1
for {set i 0} {$i<=[.c3 index end]} {incr i} {if {[.c3 type $i] eq "command" && [lindex [.c3 entrycget $i -command] 1] eq "c3.load"} {set row $i}}
tcltest::test c3-native-menu-load {actual selected-row menu loads game1} -body {
 .c3 invoke $row
 update
 set loaded [lindex [::scidb::game::link? [::scidb::game::current]] 2]
 puts [list C3_NATIVE_EFFECT row $row loaded $loaded]
 set loaded
} -result 1


# The native Ask row composes a question about the selected row; it does
# not send the question before the user presses Enter.
::application::ai::configure -provider stub -model {}
tcltest::test reg5-native-ask-game {native Ask About Game composes the selected game's actual identity} -body {
 set path $table
 menu .reg5askgame -tearoff 0
 ::gamestable::PopupMenu $path .reg5askgame $base Normal 1 white
 set found -1
 for {set i 0} {$i <= [.reg5askgame index end]} {incr i} {
  if {[.reg5askgame type $i] eq "command" && [lindex [.reg5askgame entrycget $i -command] 1] eq "c3.ask_about_game"} {set found $i;break}
 }
 if {$found < 0} {error {native game Ask row missing}}
 .reg5askgame invoke $found
 update
 set entry $::application::assistant::Priv(entry)
 set text [$entry get]
 puts [list ASK_GAME_EFFECT text $text]
 list [winfo ismapped $entry] [expr {[string first {#2} $text] >= 0}]
} -cleanup {destroy .reg5askgame} -result {1 1}

# Selection changes and clearing need no popup and never reuse a loaded row.
tcltest::test reg5-c3-selection-clear {cleared list selection removes its actions and refuses load} -body {
 ::gamestable::select $table none
 set reply [::action::run c3.load]
 list [::context::CurrentObject C3] [string match error:* $reply]
} -result {{} 1}

package require tcltest 2.5
source tests/app_actions_support.tcl
source tests/app_menu_reseal_scope_support.tcl
::scidb::test::actions::ready
::scidb::test::askscope::NewGame
set initial [::scidb::test::askscope::FocusPane editor]
set before [::scidb::test::askscope::AskContextIds C9]
::application::ask::Focus
update
set after [::scidb::test::askscope::AskContextIds C9]
puts [list ASK_PANE beforePane $initial afterPane [dict get [::context::CurrentObject C9] paneUid] savedFocus $::application::ask::Priv(focusBefore) before $before after $after]
tcltest::test ask-retains-pane-context {entering Ask retains the current notation pane context} -body {list [dict get [::context::CurrentObject C9] paneUid] [expr {$before eq $after}]} -result {editor 1}
::scidb::test::actions::release
::tcltest::cleanupTests
