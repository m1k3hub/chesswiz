package require tcltest 2.5
set ::env(SCIDB_REACHABILITY_LIBRARY) 1
source tests/test_app_action_reachability.tcl
unset ::env(SCIDB_REACHABILITY_LIBRARY)
source tests/app_actions_support.tcl
::scidb::test::actions::ready
source tests/app_menu_reseal_scope_support.tcl
::scidb::test::askscope::NewGame
set gameSlot [::scidb::game::current]
namespace eval ::c9probe {variable seen {}; variable timer {}}
proc ::c9probe::windows {{w .}} {
 set out {}
 foreach c [winfo children $w] {
  if {[winfo toplevel $c] eq $c && [winfo ismapped $c]} {lappend out $c}
  lappend out {*}[windows $c]
 }
 return [lsort -unique $out]
}
proc ::c9probe::watch {} {
 foreach w [windows] {
  if {$w ni $::c9probe::baseline && $w ne ".application"} {
   lappend ::c9probe::seen [list $w [winfo class $w]]
   if {[winfo class $w] eq "Menu"} {catch {$w unpost};catch {grab release $w}} else {
    set close [wm protocol $w WM_DELETE_WINDOW]
    if {$close ne {} && $close ne {#}} {catch {uplevel #0 $close}} else {
     foreach wanted {cancel no ok} {
      set button [::scidb::test::reachability::cancelButton $w $wanted]
      if {$button ne {}} {catch {$button invoke}; break}
     }
    }
   }
  }
 }
 set ::c9probe::timer [after 50 ::c9probe::watch]
}
proc ::c9probe::value {id obj} {
 set twm [dict get $obj twm];set frame [dict get $obj frame];set uid [dict get $obj paneUid]
 switch -- $id {
  c9.maximise {return [$twm zoomed]}
  c9.fold - c9.amalgamate {return [::application::twm::inspectLayout $twm]}
  c9.float {return [::menu::PaneFloating $uid $twm]}
  c9.stay_on_top {return [$twm get! [$twm toplevel $frame] stayontop 0]}
  c9.hide_leaving {return [$twm get! [$twm toplevel $frame] hide 0]}
  c9.close {return [$twm leaves]}
  c9.docking {return $::application::twm::Options($::application::Vars($twm:id):docking:showall)}
  c9.flip_board {return [::application::board::rotated?]}
  c9.tablebase {return $::tablebase::Options(enabled)}
  c9.analysis.best - c9.analysis.opponents {
   regexp {^analysis:(\d+)$} $uid -> number
   if {[info exists ::application::MapTerminalToAnalysis($number)]} {set number $::application::MapTerminalToAnalysis($number)}
   if {$id eq "c9.analysis.best"} {return [set ::application::analysis::${number}::Options(engine:bestFirst)]}
   set tree $::application::analysis::NumberToTree($number)
   return [set ::application::analysis::${tree}::Vars(engine:opponent)]
  }
  c9.not.font_inc - c9.not.font_dec - c9.not.font_reset {return [::context::PaneFontSize $uid]}
  c9.not.spacing {return $::pgn::editor::Options(spacing:paragraph)}
  c9.not.numbering {return $::pgn::editor::Options(show:varnumbers)}
  c9.not.markers {return $::pgn::editor::Options(show:markers)}
  c9.not.diagrams {return $::pgn::editor::Options(show:diagram)}
  c9.not.emoticons {return $::pgn::editor::Options(show:emoticon)}
  c9.tree.automatic {return $::application::tree::Options(search:automatic)}
  c9.tree.novelties {return $::application::tree::Options(novelty:highlight)}
  c9.media.show {return $::mediainset::Options(enabled)}
  c9.assistant.clear {return $::application::assistant::Priv(messages)}
  default {return [windows]}
 }
}
set pane [expr {[info exists ::env(RESEAL_PANE)] ? $::env(RESEAL_PANE) : "board"}]
set initialLeaves [::scidb::test::askscope::InitialLeaves]
set initialBoard [::scidb::test::actions::captureBoard]
# c9.tablebase opens the options dialog, which leaves the lookups switched
# off.  That is a process-wide option: restore it so a following file can
# still show a tablebase line under the board.
set initialTablebase [array get ::tablebase::Options]

tcltest::test c9-every-listed-effect {every listed pane row opens choices/dialog or changes its native state} -body {
 ::scidb::test::askscope::FocusPane $pane
 if {[info exists ::env(RESEAL_FLOAT)]} {
  ::application::assistant::DoPane undock [::scidb::test::askscope::PaneUid $pane]
  update
  ::scidb::test::askscope::FocusPane $pane
 }
 set ids [::scidb::test::askscope::AskContextIds C9]
 puts [list C9_LIST $pane $ids]
 set bad {}
 # Closing the pane is last; other layout operations are reversed after checking.
 set ids [concat [lsearch -all -inline -not -exact $ids c9.close] c9.close]
 if {[info exists ::env(RESEAL_ID)]} {
  if {$::env(RESEAL_ID) ni $ids} {error {requested row is not listed}}
  set ids [list $::env(RESEAL_ID)]
 }
 foreach id $ids {
  ::scidb::test::askscope::FocusPane $pane
  set obj [::context::CurrentObject C9]
  if {$id eq "c9.not.font_reset"} {::context::PaneFont $obj +2}
  if {$id eq "c9.assistant.clear"} {set ::application::assistant::Priv(messages) [list [dict create role user content {Generated test}]]}
  set before [::c9probe::value $id $obj]
  set ::c9probe::seen {}
  set ::c9probe::baseline [::c9probe::windows]
  set dialog [expr {$id in {c9.board_setup c9.tablebase c9.not.configure c9.analysis.setup c9.assistant.model c9.media.stream}}]
  if {$dialog} {set ::c9probe::timer [after 50 ::c9probe::watch]}
  set reply [::action::run $id [dict create object $obj]]
  update
  set after [::c9probe::value $id $obj]
  set changed [expr {$before ne $after}]
  if {$dialog} {
   after cancel $::c9probe::timer
   ::c9probe::watch
   after cancel $::c9probe::timer
   if {[llength $::c9probe::seen]} {set changed 1}
  }
  if {[winfo exists .contextChoices_paneCascade]} {
   if {[winfo ismapped .contextChoices_paneCascade] && [::context::HasRunnableRow .contextChoices_paneCascade]} {set changed 1}
   catch {grab release .contextChoices_paneCascade}
   destroy .contextChoices_paneCascade
  }
  foreach popup {.contextChoices_reportFont .contextChoices_paneCascade} {
   if {[winfo exists $popup]} {
    if {[winfo ismapped $popup] && [$popup index end] ne "none"} {set changed 1}
    catch {grab release $popup}
    destroy $popup
   }
  }
  puts [list C9_EFFECT $pane $id changed $changed before $before after $after reply $reply dialogs $::c9probe::seen]
  if {!$changed || [string match error:* $reply]} {lappend bad [list $id $reply $changed]}
  if {$id in {c9.maximise c9.fold c9.amalgamate c9.float c9.docking c9.flip_board c9.not.spacing c9.not.numbering c9.not.markers c9.not.diagrams c9.not.emoticons c9.tree.automatic c9.tree.novelties c9.media.show}} {
   set reverse [::action::run $id [dict create object $obj]]
   update
   puts [list C9_REVERSE $pane $id reply $reverse]
   if {[string match error:* $reverse]} {lappend bad [list $id reverse $reverse]}

  }
 }
 puts [list C9_COMPLETE $pane listed [llength $ids] bad $bad]
 set bad
} -cleanup {
 ::scidb::test::askscope::RestoreLayout $initialLeaves
 ::scidb::test::actions::restoreBoard $initialBoard
 ::scidb::test::askscope::Reset
 catch { array set ::tablebase::Options $initialTablebase }
 catch { ::tablebase::positionChanged $::application::board::Vars(widget:frame) }
 catch { ::application::pgn::release $gameSlot }
 catch { ::game::release $gameSlot }
} -result {}
::tcltest::cleanupTests
