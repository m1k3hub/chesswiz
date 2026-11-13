# Real effects for flag leaves, clipboard variants and board appearance.
# No registry, menu, database or handler substitutes.
package require tcltest 2.5
source tests/app_actions_support.tcl
source tests/app_menu_reseal_effect_support.tcl
::scidb::test::actions::ready
set base [::scidb::test::actions::fixture]
::action::run open_database [list path $base]
::action::run open_game {number 1 move 1 after white}
::scidb::game::copy game $::scidb::clipbaseName [::scidb::game::current] original
::application::database::switchToBase $::scidb::clipbaseName
::application::switchTab database
for {set i 0} {$i<10} {incr i} {after 30;update}
set manager $::application::database::Vars(games).twm
set table [set ::application::database::games::${manager}::Priv(table)]
::gamestable::select $table 0
::gamestable::activate $table 0
focus -force $table
update
proc ::reg6flags {} {
 set info [::scidb::db::get gameInfo 0 0 $::scidb::clipbaseName Normal]
 return [::gamestable::column $info flags]
}
foreach id [lsort -dictionary [dict keys $::context::Flags c3.flag.*]] {
 tcltest::test reg6-effect-$id {native flag leaf toggles its own persisted game flag both ways} -body {
  set flag [dict get $::context::Flags $id]
  set before [::reg6flags]
  ::reg5effect::postContext C3 $id
  set after [::reg6flags]
  ::reg5effect::postContext C3 $id
  set restored [::reg6flags]
  puts [list EFFECT $id before $before after $after restored $restored flag $flag]
  list [expr {[string first $flag $before] < 0}] [expr {[string first $flag $after] >= 0}] [expr {$before eq $restored}]
 } -result {1 1 1}
}
# Empty generated native databases make every supported variant available,
# including Bughouse, which deliberately cannot create a single-board game.
set variantBases {}
foreach variant {ThreeCheck Bughouse Crazyhouse Antichess Losers} {
 set native [file join $::scidb::test::actions::Dir variant-$variant.sci]
 ::application::database::newBase .application $variant $native
 lappend variantBases $native
}
::application::database::switchToBase $::scidb::clipbaseName
update
set index 0
foreach variant {Normal ThreeCheck Bughouse Crazyhouse Antichess Losers} {
 set id toolbar.database_clipbase.$index
 tcltest::test reg6-effect-$id {posted clipboard toolbar selects the actual variant and database} -body {
  # A different initial variant proves the first button too.
  ::application::database::SwitchVariant [expr {$variant eq "Normal" ? "Losers" : "Normal"}]
  set w $::application::database::Vars(widget:$variant)
  set command [$w cget -command]
  if {$command ne [list ::action::run $id]} {error "wrong native toolbar command: $command"}
  $w invoke
  update
  puts [list EFFECT $id variant $::application::database::Vars(variant) actual [::scidb::app::variant] base [::scidb::db::get name]]
  list $::application::database::Vars(variant) [::scidb::app::variant] [expr {[::scidb::db::get name] eq $::scidb::clipbaseName}]
 } -result [list $variant $variant 1]
 incr index
}
::application::database::SwitchVariant Normal
::application::switchTab board
::action::run open_game {number 1 move 1 after white}
# Every Appearance leaf has its own expected option, not a generic change spy.
foreach {suffix var} {
 side ::board::layout(side-to-move)
 material ::board::layout(material-values)
 border ::board::layout(border)
 coordinates ::board::layout(coordinates)
 small_letters ::board::layout(coords-small)
 suggested ::board::hilite(show-suggested)
 arrows ::application::board::Options(variations:arrows)
 annotation ::application::board::Options(show:annotation)
} {
 tcltest::test reg6-effect-board-$suffix {native appearance leaf toggles its intended board setting and restores it} -body {
  set before [set $var]
  ::reg5effect::postInvoke menu.board.appearance.$suffix
  set after [set $var]
  ::reg5effect::postInvoke menu.board.appearance.$suffix
  puts [list EFFECT menu.board.appearance.$suffix variable $var before $before after $after restored [set $var]]
  list [expr {$before ne $after}] [expr {$before eq [set $var]}]
 } -result {1 1}
}
foreach native $variantBases {::application::database::closeBase .application $native}
::scidb::test::actions::cleanup
::tcltest::cleanupTests
