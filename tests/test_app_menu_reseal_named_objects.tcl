# VS/VU-reg3 native C5 resolver and popup/Ask parity regressions.
package require tcltest 2.5
source tests/app_actions_support.tcl
source tests/app_menu_reseal_scope_support.tcl
::scidb::test::actions::ready
set base [::scidb::test::actions::fixture]
::action::run open_database [list path $base]
::action::run open_game {number 1 move 1 after white}
::application::switchTab database
update

foreach state {start mid end} {
 foreach kind {player event site} {
  tcltest::test reseal-native-C5-$kind-$state {native popup selects the typed object for Ask and implicit dispatch} -body {
   ::scidb::game::go [expr {$state eq "mid" ? 3 : $state}]
   menu .named -tearoff 0
   switch $kind {
    player {
     ::application::database::selectPlayer $base Normal 0
     for {set i 0} {$i < 10} {incr i} {after 30; update}
     set manager $::application::database::Vars(player).twm
     set frame [set ::application::database::player::${manager}::Vars(frame:player)]
     ::playertable::select $frame 0
     ::playertable::activate $frame 0
     focus -force $frame
     set view [::application::database::player::View $manager $base Normal]
     set info [::scidb::db::get playerInfo 0 $view $base Normal -info]
     ::playertable::popupMenu .named $base Normal $info 0 0
    }
    event - site {
     ::application::database::select[string totitle $kind] $base Normal 0
     for {set i 0} {$i < 10} {incr i} {after 30; update}
     set manager $::application::database::Vars($kind).twm
     set frame [set ::application::database::${kind}::${manager}::Vars(frame:$kind)]
     ::${kind}table::select $frame 0
     ::${kind}table::activate $frame 0
     focus -force $frame
     if {$kind eq "site"} {
      ::sitetable::PopupMenu $frame .named $base Normal 0 site
     } else {
      set view [::application::database::event::View $manager $base Normal]
      ::eventtable::popupMenu $frame .named $base Normal $view 0 event
     }
    }
   }
   .named post 100 100
   update
   if {![winfo ismapped .named]} {error {native named-object popup was not mapped}}
   set object [::context::CurrentObject C5]
   set expected [::scidb::test::askscope::PostedIds .named C5]
   set got [::scidb::test::askscope::AskContextIds C5]
   lassign [::scidb::test::askscope::Diff $got $expected] missing extra
   set unresolved {}
   foreach id $expected {
    if {[::context::CurrentObjectFor $id] ne [list C5 $object]} {lappend unresolved $id}
   }
   puts [list NATIVE_C5 $kind $state mapped [winfo ismapped .named] object $object expected $expected ask $got missing $missing extra $extra unresolved $unresolved]
   list [dict get $object kind] [expr {[llength $expected] > 0}] $missing $extra $unresolved
  } -cleanup {catch {::tk::MenuUnpost .named}; catch {destroy .named}} -result [list $kind 1 {} {} {}]
 }
}
# Exercise the actual public action with no manufactured object, and compare
# its effect to the native row command. Both must open the selected player's card.
tcltest::test reseal-C5-implicit-effect {native and implicit player action open the same named card} -body {
 menu .named -tearoff 0
 ::playertable::popupMenu .named $base Normal [list {Generated White}] 0 0
 set row -1
 for {set i 0} {$i <= [.named index end]} {incr i} {
  if {[.named type $i] eq "command" && [lindex [.named entrycget $i -command] 1] eq "c5.player_card"} {set row $i; break}
 }
 if {$row < 0} {error {missing player card native row}}
 .named invoke $row
 update
 set cards [lsearch -all -inline -glob [winfo children .application] .application.__card__*]
 if {[llength $cards] != 1} {error "native row did not open one player card: $cards"}
 set nativeCard [lindex $cards 0]
 set nativeTitle [wm title $nativeCard]
 if {![winfo ismapped $nativeCard]} {error {native player card is not mapped}}
 destroy $nativeCard
 destroy .named
 update
 # The current typed selection outlives the popup widget.
 set reply [::action::run c5.player_card]
 update
 set cards [lsearch -all -inline -glob [winfo children .application] .application.__card__*]
 if {[llength $cards] != 1} {error "implicit action did not open one player card: $cards"}
 set implicitCard [lindex $cards 0]
 puts [list C5_IMPLICIT_EFFECT reply $reply nativeTitle $nativeTitle implicitTitle [wm title $implicitCard] mapped [winfo ismapped $implicitCard]]
 list [string match error:* $reply] [expr {$nativeTitle eq [wm title $implicitCard]}] [winfo ismapped $implicitCard]

} -cleanup {catch {destroy .named}} -result {0 1 1}
tcltest::test reseal-C5-empty-selection {empty named popup clears selection and refuses implicit dispatch} -body {
 menu .named -tearoff 0
 set built [::context::Build C5 .named {}]
 set reply [::action::run c5.player_card]
 list $built [::context::CurrentObject C5] [::scidb::test::askscope::AskContextIds C5] [string match {error: precondition:*} $reply]
} -cleanup {catch {destroy .named}} -result {0 {} {} 1}
::tcltest::cleanupTests
