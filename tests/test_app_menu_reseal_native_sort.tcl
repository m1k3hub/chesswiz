# Permanent VS/VU-reg4 regression probe; no network or private data.
foreach key {VAL_EVIDENCE OBJECT_EVIDENCE} {
 if {![info exists ::env($key)]} {set ::env($key) [file join $::env(HOME) evidence];file mkdir $::env($key)}
}
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

foreach state {end} {
 foreach kind {player event site} {
  tcltest::test reseal-native-C5-$kind-$state {native popup selects the typed object for Ask and implicit dispatch} -body {
   ::scidb::game::go [expr {$state eq "mid" ? 3 : $state}]
   ::application::database::select[string totitle $kind] $base Normal 0
   for {set i 0} {$i < 10} {incr i} {after 30; update}
   set manager $::application::database::Vars($kind).twm
   set frame [set ::application::database::${kind}::${manager}::Vars(frame:$kind)]
   set table [expr {$kind eq "player" ? "$frame.table.top.table" : "$frame.top.table"}]
   set point {}
   for {set y 1} {$y < [winfo height $table.t] && $point eq {}} {incr y 3} {
    for {set x 1} {$x < [winfo width $table.t]} {incr x 10} {
     if {[lindex [::table::identify $table $x $y] 0] eq "0"} {set point [list $x $y];break}
    }
   }
   if {$point eq {}} {error "no visible first $kind row: $frame"}
   lassign $point x y
   puts [list NATIVE_POINTER $kind $state table $table point $point root [list [winfo rootx $table.t] [winfo rooty $table.t]]]
   exec xdotool mousemove [expr {[winfo rootx $table.t]+$x}] [expr {[winfo rooty $table.t]+$y}] click 3
   for {set i 0} {$i < 10} {incr i} {after 30;update}
   set nativeMenu $table.menu
   if {![winfo exists $nativeMenu] || ![winfo ismapped $nativeMenu]} {error "native pointer did not map $nativeMenu"}
   exec import -window root [file join $::env(VAL_EVIDENCE) pointer-C5-$kind-$state.png]
   set object [::context::CurrentObject C5]
   proc DumpNativeRows {menu} {
    set last [$menu index end]
    if {$last eq "none" || $last eq ""} {return}
    for {set j 0} {$j <= $last} {incr j} {
     set typ [$menu type $j]
     if {$typ eq "separator"} {continue}
     set cmd {}; catch {set cmd [$menu entrycget $j -command]}
     puts [list NATIVE_ROW $menu $j $typ [$menu entrycget $j -label] [$menu entrycget $j -state] $cmd]
     if {$typ eq "cascade"} {DumpNativeRows [$menu entrycget $j -menu]} elseif {$cmd ne ""} {
      if {[lindex $cmd 0] ne "::action::run"} {error "unregistered native row: $cmd"}
      ::action::get [lindex $cmd 1]
     }
    }
   }
   DumpNativeRows $nativeMenu
   set allPosted [::scidb::test::askscope::PostedIds $nativeMenu C5]
   set globalAsk [lmap row [::action::labels asklist {}] {lindex $row 0}]
   puts [list POINTER_ALL_ROWS $kind $state posted $allPosted globalAskContains [lmap id $allPosted {list $id [expr {$id in $globalAsk}]}]]
   set expected [lsearch -all -inline -glob $allPosted c5.*]
   set sortIds [lsearch -all -inline -glob $allPosted c5.sort.*]
   set count [expr {$kind eq "player" ? 14 : ($kind eq "event" ? 16 : 0)}]
   if {[llength $sortIds] != $count} {error "expected $count native sort rows, got $sortIds"}
   foreach id $sortIds {
    set record [::action::get $id]
    if {[dict get $record ai] != 0 || ![dict get $record operator]} {error "sort action exposure missing: $id"}
    if {![dict exists $::knowledge::Explicit $id]} {error "sort knowledge missing: $id"}
   }
   set got [::scidb::test::askscope::AskContextIds C5]
   lassign [::scidb::test::askscope::Diff $got $expected] missing extra
   set unresolved {}
   foreach id $expected {
    if {[::context::CurrentObjectFor $id] ne [list C5 $object]} {lappend unresolved $id}
   }
   puts [list NATIVE_C5 $kind $state mapped [winfo ismapped $nativeMenu] object $object expected $expected ask $got missing $missing extra $extra unresolved $unresolved]
   if {$kind eq "player"} {
    catch {grab release $nativeMenu}; $nativeMenu unpost
    set reply [::action::run c5.player_card]; update
    set cards [lsearch -all -inline -glob [winfo children .application] .application.__card__*]
    if {[llength $cards] != 1 || ![winfo ismapped [lindex $cards 0]]} {error "pointer implicit card effect failed $cards $reply"}
    puts [list POINTER_IMPLICIT_EFFECT object $object reply $reply card [lindex $cards 0] title [wm title [lindex $cards 0]]]
    exec import -window root [file join $::env(VAL_EVIDENCE) pointer-player-implicit-effect.png]
    destroy [lindex $cards 0]
   }
   # Real table effect, through the same bare action exposed in Ask.
   if {$kind eq "player"} {
    foreach direction {descending ascending} {
     if {$direction eq "ascending"} {
      set reply [::knowledge::RunAction c5.sort.player.lastName.$direction {}]
     } else {set reply [::action::run c5.sort.player.lastName.$direction]}
     update
     if {[string match error:* $reply]} {error $reply}
     set first [lindex [::scidb::db::get playerInfo 0 [dict get $object view] $base Normal -info] 0]
     set wanted [expr {$direction eq "descending" ? "Generated White" : "Generated Black"}]
     if {$first ne $wanted} {error "sort $direction first=$first wanted=$wanted"}
     puts [list NATIVE_SORT_EFFECT $direction first $first reply $reply]
    }
   }
   list [dict get $object kind] [expr {[llength $expected] > 0}] $missing $extra $unresolved
  } -cleanup {catch {grab release $nativeMenu}; catch {$nativeMenu unpost}; catch {destroy $nativeMenu}; update} -result [list $kind 1 {} {} {}]
 }
}

::tcltest::cleanupTests
