# Complete native caller menus, after their named-object builders return.
package require tcltest 2.5
source tests/test_app_menu_registry_walk.tcl
source tests/app_actions_support.tcl
::scidb::test::actions::ready
set base [::scidb::test::actions::fixture]
::action::run open_database [dict create path $base]
::action::run open_game {number 1 move 1 after white}
update
set gamebar $::application::pgn::Vars(gamebar)
set slot [::scidb::game::current]
foreach kind {player event site tab} {
 tcltest::test reg5-gamebar-$kind {completed native named caller has no raw operation callbacks} -body {
  switch $kind {
   player {::gamebar::PopupPlayerMenu $gamebar $slot white}
   event {::gamebar::PopupEventMenu $gamebar $slot}
   site {::gamebar::PopupSiteMenu $gamebar $slot}
   tab {::gamebar::PopupMenu $gamebar $slot}
  }
  set m $gamebar.menu
  ::scidb::test::rgw::PostTree $m
  set rows {};::scidb::test::rgw::WalkMenu $m rows gamebar.$kind
  puts [list COMPLETE_CALLER gamebar.$kind rows [llength $rows]]
  ::scidb::test::rgw::BadCommands $rows
 } -cleanup {catch {::tk::MenuUnpost $gamebar.menu};catch {destroy $gamebar.menu}} -result {}
}
::application::switchTab database
update
set manager $::application::database::Vars(games).twm
set path [set ::application::database::games::${manager}::Priv(table)]
::gamestable::Open(browse) $path 0
update
set ns {}
foreach candidate [namespace children ::browser] {if {[info exists ${candidate}::Vars(board)]} {set ns $candidate;break}}
if {$ns eq {}} {error {native game browser did not open}}
set position [namespace tail $ns];set board [set ${ns}::Vars(board)]
foreach kind {{} white black event} {
 tcltest::test reg5-browser-$kind {completed browser caller routes every operation through registry} -body {
  ::browser::PopupMenu .application $board $position $kind
  set m [winfo toplevel $board].__menu__
  ::scidb::test::rgw::PostTree $m
  set rows {};::scidb::test::rgw::WalkMenu $m rows browser.$kind
  puts [list COMPLETE_CALLER browser.$kind rows [llength $rows]]
  ::scidb::test::rgw::BadCommands $rows
 } -cleanup {catch {::tk::MenuUnpost $m};catch {destroy $m}} -result {}
}
tcltest::test reg5-browser-board-effect {registered browser resizing changes its real board} -body {
 set before [set ${ns}::Vars(board:size)]
 set reply [::action::run browser.decrease [dict create object [dict create position $position board $board parent .application value {}]]]
 puts [list BROWSER_SIZE before $before after [set ${ns}::Vars(board:size)] reply $reply]
 update
 expr {[set ${ns}::Vars(board:size)] < $before}
} -result 1

tcltest::test reg5-browser-ask-selection {implicit browser actions resolve the focused browser and vanish after leaving it} -body {
 focus -force $board
 update
 # The preceding size probe may leave the board at its minimum.
 ::action::run browser.increase
 update
 set ids [lmap row [::action::labels asklist {}] {lindex $row 0}]
 set before [set ${ns}::Vars(board:size)]
 set result [::action::run browser.decrease]
 update
 set changed [expr {[set ${ns}::Vars(board:size)] < $before}]
 ::application::switchTab board
 focus -force $::application::board::Vars(widget:frame)
 update
 set other [lmap row [::action::labels asklist {}] {lindex $row 0}]
 puts [list BROWSER_ASK before $before result $result changed $changed]
 list [expr {"browser.decrease" in $ids}] $changed [expr {"browser.decrease" in $other}]
} -result {1 1 0}

tcltest::test reg5-browser-native-check-effect {native checkbutton arguments also change the option through direct action invocation} -setup {
 set savedCustomStyle $::theme::useCustomStyleMenuEntries
 set ::theme::useCustomStyleMenuEntries 0
} -body {
 set before $::pgn::browser::Options(style:column)
 ::browser::PopupMenu .application $board $position
 set m [winfo toplevel $board].__menu__
 set command {}
 for {set i 0} {$i <= [$m index end]} {incr i} {
  if {[$m type $i] eq "checkbutton" && [lindex [$m entrycget $i -command] 1] eq "browser.column_style_check"} {set command [$m entrycget $i -command];break}
 }
 if {$command eq {}} {error {native column-style checkbutton did not post}}
 set reply [::action::invoke browser.column_style_check [lindex $command 2]]
 update
 puts [list BROWSER_CHECK_EFFECT before $before after $::pgn::browser::Options(style:column) reply $reply]
 expr {$::pgn::browser::Options(style:column) != $before}
} -cleanup {
 set ::theme::useCustomStyleMenuEntries $savedCustomStyle
 catch {::tk::MenuUnpost $m};catch {destroy $m}
} -result 1
catch {destroy [winfo toplevel $board]}

::tcltest::cleanupTests
