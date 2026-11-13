# R8: a full native record with empty identity values is still a hit miss.
package require tcltest 2.5
source tests/app_actions_support.tcl
source tests/app_menu_reseal_scope_support.tcl
::scidb::test::actions::ready
namespace eval ::scidb::test::blank {
 variable observed {}
 variable timer {}
 variable done 0
}

# Check all identity alternatives, including numeric zero, independently of
# menu::state (shared parity alone cannot catch a wrong HasObject predicate).
foreach {cid keys} {
 C1 {fen square} C2 {index ply san} C3 {index} C4 {base}
 C5 {name} C6 {lineId pv} C7 {mediaId path} C8 {fen table}
 C9 {paneUid} C10 {column} C11 {widget index} C12 {gameSlot id}
} {
 tcltest::test context-empty-values-$cid {empty identity values are not an object} -body {
  set object {engine 1 kind player parent .application}
  foreach key $keys {dict set object $key {}}
  set bad {}
  if {$cid ne "C4"} {
   menu .blankIdentity -tearoff 0
   set built [::context::Build $cid .blankIdentity $object]
   if {$built || [.blankIdentity index end] ni {{} none}} {lappend bad built-empty}
   destroy .blankIdentity
  }
  if {[::context::HasObject $cid $object]} {lappend bad all-empty}
  foreach key $keys {
   if {[::context::HasObject $cid [dict create $key {}]]} {lappend bad $key}
   if {![::context::HasObject $cid [dict create $key 0]]} {lappend bad zero-$key}
  }
  set bad
 } -result {}
}
tcltest::test context-empty-native-sentinels {native no-row/no-tab sentinels stay empty with other populated fields} -body {
 list [::context::HasObject C3 {index outside base b}] \
  [::context::HasObject C3 {index none base b}] \
  [::context::HasObject C8 {row -1 fen fen table .tree}] \
  [::context::HasObject C8 {row {} fen fen table .tree}] \
  [::context::HasObject C12 {gameSlot -1 id -1 parent .bar}]
} -result {0 0 0 0 0}

proc ::scidb::test::blank::Widgets {{w .}} {
 set result [list $w]
 foreach child [winfo children $w] {lappend result {*}[Widgets $child]}
 return $result
}
proc ::scidb::test::blank::Menus {} {
 set result {}
 foreach w [Widgets] {
  if {[winfo class $w] eq "Menu" && [winfo ismapped $w]} {lappend result $w}
 }
 return $result
}
proc ::scidb::test::blank::Unpost {} {
 foreach w [Menus] {catch {grab release $w};catch {$w unpost}}
 catch {::tk::MenuUnpost {}}
 update
}
proc ::scidb::test::blank::Capture {w event} {
 variable observed
 if {[winfo class $w] eq "Menu"} {lappend observed [list $event $w]}
}
proc ::scidb::test::blank::DuringClick {} {
 variable observed
 variable done
 foreach w [Menus] {lappend observed [list during $w]}
 Unpost
 set done 1
}
proc ::scidb::test::blank::Maximise {w} {
 focus -force $w
 update
 set object [::context::CurrentObject C9]
 if {![dict exists $object frame]} {error "no native pane for $w"}
 set twm [dict get $object twm]
 set frame [dict get $object frame]
 if {![$twm get $frame zoomable 0]} {
  # Database-tab tables are fixed, non-zoomable panes. Maximise their
  # containing window instead, using the actual display's work area.
  dict set object windowGeometry [wm geometry .application]
  wm geometry .application [::scidb::test::app::fitGeometry [winfo screenwidth .application] [winfo screenheight .application]]
  update
  puts [list MAXIMISED_WINDOW [dict get $object paneUid] [wm geometry .application]]
 } else {
  set reply [::action::run c9.maximise [dict create object $object]]
  if {[string match error:* $reply]} {error $reply}
  update
 }
 return $object
}
proc ::scidb::test::blank::Click {w x y} {
 variable observed
 variable timer
 variable done
 Unpost
 set observed {}
 set done 0
 set savedMap [bind all <Map>]
 # Map records even a popup that unposts before the scheduled observer.
 bind all <Map> {+::scidb::test::blank::Capture %W map}
 focus -force $w
 event generate $w <Motion> -warp 1 -x $x -y $y
 update
 set timer [after 300 ::scidb::test::blank::DuringClick]
 set code [catch {
  event generate $w <ButtonPress-3> -x $x -y $y \
   -rootx [expr {[winfo rootx $w]+$x}] -rooty [expr {[winfo rooty $w]+$y}]
  event generate $w <ButtonRelease-3> -x $x -y $y
  if {!$done} {vwait ::scidb::test::blank::done}
 } message options]
 after cancel $timer
 bind all <Map> $savedMap
 Unpost
 if {$code} {return -options $options $message}
 return $observed
}
proc ::scidb::test::blank::Restore {object} {
 if {[dict exists $object windowGeometry]} {
  wm geometry .application [dict get $object windowGeometry]
  update
  return
 }
 set reply [::action::run c9.maximise [dict create object $object]]
 if {[string match error:* $reply]} {error $reply}
 update
}
proc ::scidb::test::blank::TableClick {table} {
 set w $table.t
 set x 80
 set y [expr {[winfo height $w]-8}]
 set hit [::table::identify $table $x $y]
 puts [list BLANK_TABLE $table pixel [list $x $y] hit $hit]
 if {[string is integer -strict [lindex $hit 0]] && [lindex $hit 0]>=0} {error "not a blank table pixel: $hit"}
 return [Click $w $x $y]
}

set base [::scidb::test::actions::fixture]
::action::run open_database [dict create path $base]
::action::run open_game {number 1 move 1 after black}
::application::openPane editor
update

tcltest::test context-blank-pixel-notation {maximised notation blank pixel posts no menu} -setup {
 set text {}
 foreach w [::scidb::test::blank::Widgets $::application::pgn::Vars(frame)] {
  if {[winfo viewable $w] && [string match *PopupMenu* [bind $w <ButtonPress-3>]]} {set text $w;break}
 }
 if {$text eq {}} {error {no mapped notation text}}
} -body {
 set object [::scidb::test::blank::Maximise $text]
 set x [expr {[winfo width $text]-8}];set y [expr {[winfo height $text]-8}]
 if {[$text tag names @$x,$y] ne {}} {error {notation pixel has tags}}
 ::scidb::test::blank::Click $text $x $y
} -cleanup {::scidb::test::blank::Restore $object} -result {}

::application::switchTab database
update
tcltest::test context-blank-pixel-games {maximised game list blank pixel posts no menu} -body {
 set manager $::application::database::Vars(games).twm
 set st [set ::application::database::games::${manager}::Priv(table)]
 ::gamestable::select $st none
 set table [::scrolledtable::table $st]
 set object [::scidb::test::blank::Maximise $table.t]
 ::scidb::test::blank::TableClick $table
} -cleanup {::scidb::test::blank::Restore $object} -result {}
foreach kind {player event site} {
 tcltest::test context-blank-pixel-$kind {maximised named table blank pixel with no selection posts no menu} -body {
  ::application::database::select[string totitle $kind] $base Normal 0
  for {set i 0} {$i<10} {incr i} {after 30;update}
  set manager $::application::database::Vars($kind).twm
  set frame [set ::application::database::${kind}::${manager}::Vars(frame:$kind)]
  set st $frame
  if {$kind eq "player"} {set st $frame.table}
  ::${kind}table::select $frame none
  if {$kind eq "player"} {::playertable::activate $frame none}
  set table [::scrolledtable::table $st]
  set object [::scidb::test::blank::Maximise $table.t]
  ::scidb::test::blank::TableClick $table
 } -cleanup {::scidb::test::blank::Restore $object} -result {}
}
foreach kind {annotator position} {
 tcltest::test context-blank-pixel-$kind {maximised named group blank pixel posts no menu} -body {
  $::application::database::Vars(contents) select $::application::database::Vars($kind)
  update
  set path $::application::database::Vars($kind).twm
  ::application::database::${kind}::InitBase $path $base Normal
  update
  set table {}
  foreach w [::scidb::test::blank::Widgets .application] {
   if {[info exists ::scrolledtable::${w}::(popupcmd)]
    && [string match "*::${kind} *PopupMenu*" [set ::scrolledtable::${w}::(popupcmd)]]} {set table $w;break}
  }
  if {$table eq {} || ![winfo viewable $table.t]} {error "no mapped $kind table"}
  ::table::select $table none
  set object [::scidb::test::blank::Maximise $table.t]
  ::scidb::test::blank::TableClick $table
 } -cleanup {::scidb::test::blank::Restore $object} -result {}
}
::application::switchTab board
update

tcltest::test context-blank-pixel-tree {maximised opening tree blank pixel posts no row menu} -body {
 ::scidb::game::go start
 ::scidb::tree::set $base
 set table $::application::tree::Vars(table)
 ::application::tree::DoSearch $table
 ::scidb::test::actions::waitUntil {[llength $::application::tree::Vars(data)]>0}
 ::application::openPane tree
 update
 set object [::scidb::test::blank::Maximise $table.t]
 ::scidb::test::blank::TableClick $table
} -cleanup {::scidb::test::blank::Restore $object} -result {}

tcltest::test context-blank-pixel-media {maximised media list blank pixel posts no entry menu} -body {
 ::application::openPane media
 ::application::media::ToggleList
 update
 set tree $::application::media::Priv(tree)
 set object [::scidb::test::blank::Maximise $tree]
 set x 80;set y [expr {[winfo height $tree]-8}]
 if {[$tree identify item $x $y] ne {}} {error {media pixel identifies an entry}}
 ::scidb::test::blank::Click $tree $x $y
} -cleanup {::scidb::test::blank::Restore $object} -result {}

tcltest::test context-blank-pixel-analysis {maximised populated analysis blank pixel posts no line menu during binding} -body {
 set program [::scidb::test::actions::engineProgram]
 if {![::engine::ProbeNewEngine .application [list Command $program] UCI]} {error {engine probe failed}}
 set engineName {}
 foreach entry $::engine::Engines {if {[dict get $entry Command] eq $program} {set engineName [dict get $entry Name];break}}
 set reply [::action::run start_engine [dict create engine $engineName threads 1 hash 16 lines 1]]
 if {![regexp {analysis pane (\d+)} $reply -> number]} {error $reply}
 set tree $::application::analysis::NumberToTree($number)
 ::scidb::test::actions::waitUntil {[info exists ::application::analysis::${tree}::Vars(pv:0)] && [set ::application::analysis::${tree}::Vars(pv:0)] ne {}}
 ::application::openPane analysis:$number
 update
 set object [::scidb::test::blank::Maximise $tree]
 set x 80;set y [expr {[winfo height $tree]-8}]
 puts [list BLANK_ENGINE pixel [list $x $y] identify [$tree identify $x $y]]
 if {[lindex [$tree identify $x $y] 0] eq "item"} {error {analysis pixel identifies a line}}
 ::scidb::test::blank::Click $tree $x $y
} -cleanup {
 ::scidb::test::blank::Restore $object
 if {[info exists tree] && [winfo exists $tree]} {::application::analysis::CloseEngine $tree}
 ::ai::engine::shutdown
} -result {}
# C1 and C9 always have a position/pane object; C10 is a header object,
# C11's text widget itself is the editing object, and C4 retains R5's
# documented New/Open menu. The native census covers their positive posts.
::tcltest::cleanupTests
