# Permanent VS/VU-reg4 regression probe; no network or private data.
foreach key {VAL_EVIDENCE OBJECT_EVIDENCE} {
 if {![info exists ::env($key)]} {set ::env($key) [file join $::env(HOME) evidence];file mkdir $::env($key)}
}
package require tcltest 2.5
source tests/app_actions_support.tcl
source tests/app_menu_reseal_scope_support.tcl
::scidb::test::actions::ready
set base [::scidb::test::actions::fixture]
# Generate two events/sites while retaining the same two player rows.
set ch [open $base r]; set game [read $ch]; close $ch
set ch [open $base a]; puts $ch [string map {{Generated test} {Second event} {Test} {Second site}} $game]; close $ch
::action::run open_database [list path $base]
::action::run open_game {number 1 move 1 after white}
::application::switchTab database
::application::database::selectPlayer $base Normal 0
for {set i 0} {$i < 10} {incr i} {after 30; update}
set manager $::application::database::Vars(player).twm
set frame [set ::application::database::player::${manager}::Vars(frame:player)]
set view [::application::database::player::View $manager $base Normal]
::playertable::select $frame 0
::playertable::activate $frame 0
set first [::scidb::db::get playerInfo 0 $view $base Normal -info]
tcltest::test fresh-native-no-popup {current selected player is available to Ask before first right-click} -body {
 set current [::context::CurrentObject C5]
 set ask [::scidb::test::askscope::AskContextIds C5]
 puts [list FRESH_NAMED selection [::scrolledtable::selection $frame.table] player $first current $current ask $ask]
 expr {[dict size $current] && "c5.player_card" in $ask}
} -result 1
menu .native -tearoff 0
::playertable::popupMenu .native $base Normal $first 0 0
.native post 100 100;update
set old [::context::CurrentObject C5]
::tk::MenuUnpost .native;destroy .native
::playertable::select $frame 1
::playertable::activate $frame 1
focus -force $frame
update
set second [::scidb::db::get playerInfo 1 $view $base Normal -info]
tcltest::test stale-native-selection {implicit named action follows currently selected native row} -body {
 set current [::context::CurrentObject C5]
 set ask [::scidb::test::askscope::AskContextIds C5]
 puts [list STALE_NAMED first $first selectedNow $second old $old current $current ask $ask]
 set reply [::action::run c5.player_card];update
 set cards [lsearch -all -inline -glob [winfo children .application] .application.__card__*]
 puts [list STALE_EFFECT reply $reply cards [lmap c $cards {list $c [wm title $c] [winfo ismapped $c]}]]
 foreach c $cards {wm geometry $c +1000+450}
 update
 exec import -window root [file join $::env(VAL_EVIDENCE) stale-selected-player.png]
 expr {[dict get $current name] eq [lindex $second 0]}
} -result 1
tcltest::test stale-native-cleared {clearing current native selection removes named Ask rows even after changing the main tab} -body {
 ::application::switchTab board
 update
 ::playertable::select $frame none
 ::playertable::activate $frame none
 update
 set current [::context::CurrentObject C5]
 set ask [::scidb::test::askscope::AskContextIds C5]
 foreach c [lsearch -all -inline -glob [winfo children .application] .application.__card__*] {destroy $c}
 set reply [::action::run c5.player_card]
 update
 set cards [lsearch -all -inline -glob [winfo children .application] .application.__card__*]
 foreach c $cards {wm geometry $c +1000+450}
 update
 puts [list CLEARED_EFFECT cards [lmap c $cards {list $c [wm title $c] [winfo ismapped $c]}]]
 exec import -window root [file join $::env(VAL_EVIDENCE) stale-cleared-player.png]
 puts [list STALE_CLEARED selection [::scrolledtable::selection $frame.table] current $current ask $ask reply $reply]
 list $current $ask [string match {error: precondition:*} $reply]
} -result {{} {} 1}
foreach kind {event site} {
 tcltest::test reseal-current-$kind-selection {native selection resolves before popup, after another selection, and after clearing} -body {
  ::application::database::select[string totitle $kind] $base Normal 0
  for {set i 0} {$i < 10} {incr i} {after 30;update}
  set manager $::application::database::Vars($kind).twm
  set frame [set ::application::database::${kind}::${manager}::Vars(frame:$kind)]
  ::${kind}table::select $frame 0
  ::${kind}table::activate $frame 0
  set first [::context::CurrentObject C5]
  if {[dict get $first kind] ne $kind || ![llength [::scidb::test::askscope::AskContextIds C5]]} {error "missing fresh $kind object"}
  menu .native -tearoff 0
  ::${kind}table::PopupMenu $frame .native $base Normal 0 $kind
  destroy .native
  ::${kind}table::select $frame 1
  ::${kind}table::activate $frame 1
  update
  set current [::context::CurrentObject C5]
  if {[dict get $current name] eq [dict get $first name]} {error "stale $kind reference: $current"}
  if {![llength [::scidb::test::askscope::AskContextIds C5]] || [::context::CurrentObjectFor c5.open_switcher] ne [list C5 $current]} {error "current $kind Ask/reference unavailable"}
  ::${kind}table::select $frame none
  ::${kind}table::activate $frame none
  update
  set reply [::action::run c5.open_switcher]
  puts [list NAMED_CURRENT_SELECTION $kind first $first changed $current cleared [::context::CurrentObject C5] reply $reply]
  list [::context::CurrentObject C5] [::scidb::test::askscope::AskContextIds C5] [string match {error: precondition:*} $reply]
 } -cleanup {catch {destroy .native}} -result {{} {} 1}
}
::tcltest::cleanupTests
