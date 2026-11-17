# Permanent VS/VU-reg4 regression probe; no network or private data.
foreach key {VAL_EVIDENCE OBJECT_EVIDENCE} {
 if {![info exists ::env($key)]} {set ::env($key) [file join $::env(HOME) evidence];file mkdir $::env($key)}
}
package require tcltest 2.5
source tests/app_actions_support.tcl
::scidb::test::actions::ready
set base [::scidb::test::actions::fixture]
::action::run open_database [list path $base]
::action::run open_game {number 1 move 1 after white}
::application::switchTab database
::application::database::selectPlayer $base Normal 0
for {set i 0} {$i < 10} {incr i} {after 30;update}
set manager $::application::database::Vars(player).twm
set frame [set ::application::database::player::${manager}::Vars(frame:player)]
::playertable::select $frame 0
::playertable::activate $frame 0
focus -force $frame
set view [::application::database::player::View $manager $base Normal]
set first [::scidb::db::get playerInfo 0 $view $base Normal -info]
set second [::scidb::db::get playerInfo 1 $view $base Normal -info]
menu .stale -tearoff 0
::playertable::popupMenu .stale $base Normal $first 0 0
puts [list FIRST $first CURRENT [::context::CurrentObject C5]]
destroy .stale
::playertable::select $frame 1
::playertable::activate $frame 1
focus -force $frame
update
set tb $frame.table.top.table
puts [list ACTUAL_SELECTION [::table::selection $tb] INDEX [::playertable::index $frame] ACTIVE [$tb.t item id active] ITEMS [$tb.t item count] ROW1_EXISTS [$tb.t item id 1]]
puts [list SELECTED_SECOND $second CURRENT [::context::CurrentObject C5]]
set reply [::action::run c5.player_card]
update
set cards [lsearch -all -inline -glob [winfo children .application] .application.__card__*]
puts [list REPLY $reply CARDS $cards]
foreach card $cards {puts [list CARD_TITLE [wm title $card]]}
exec import -window root [file join $::env(OBJECT_EVIDENCE) REG007-stale-selection.png]

tcltest::test reseal-selected-player-card-title {the bare action opens the second selected player rather than the popup snapshot} -body {
 list [string match error:* $reply] [llength $cards] [string match *Generated\ White* [wm title [lindex $cards 0]]]
} -result {0 1 1}
::scidb::test::actions::release
::tcltest::cleanupTests
