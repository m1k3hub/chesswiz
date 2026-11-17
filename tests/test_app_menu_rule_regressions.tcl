# Independent validator probes: do not derive the expected hidden IDs from ownership.
package require tcltest 2.5
source tests/app_actions_support.tcl
source tests/app_menu_reseal_scope_support.tcl
::scidb::test::actions::ready

proc ::scidb::test::askscope::RuleHidden {ids {object {}}} {
 set bad {}
 set ask [lmap row [::action::labels asklist {}] {lindex $row 0}]
 foreach id $ids {
  if {[dict get [::menu::state $id $object] visible] || $id in $ask} {lappend bad $id}
 }
 return $bad
}
tcltest::test rule-regression-no-game {R1 hides dynamic paste/merge/history rows and their cascades} -body {
 ::scidb::test::askscope::NoGame
 menu .rulegame -tearoff 0
 ::menu::FillTop Game .rulegame
 set labels {}
 for {set i 0} {$i <= [.rulegame index end]} {incr i} {
  if {[.rulegame type $i] ne "separator"} {lappend labels [.rulegame entrycget $i -label]}
 }
 set bad [::scidb::test::askscope::RuleHidden {menu.game.paste_clip menu.game.paste_tab menu.game.merge_clip menu.game.merge_tab menu.game.history.recent menu.game.history.clear}]
 foreach key {PasteGame MergeGame GameHistory} {
  lassign [::menu::AmpText [::menu::MC $key]] label underline
  if {$label in $labels} {lappend bad $key}
 }
 set bad
} -cleanup {destroy .rulegame} -result {}

tcltest::test rule-regression-download {actual download backend removal hides C4 alias, Ask and tool} -setup {
 ::scidb::test::askscope::NewGame
 set base [::scidb::test::actions::fixture]
 ::action::run open_database [list path $base]
 set object [dict create base $base variant Normal]
 if {![::capability::present download] || ![dict get [::menu::state c4.download_games $object] visible]} {error {download positive precondition missing}}
 rename ::application::download::openActive ::application::download::openActive_ruleSaved
} -body {
 menu .ruledownload -tearoff 0
 ::context::Build C4 .ruledownload $object
 set ids [::scidb::test::askscope::MenuIds .ruledownload C4]
 set tools [lmap tool [::json::json2dict [::application::assistant::toolsJson]] {dict get $tool function name}]
 list [::capability::present download] [::scidb::test::askscope::RuleHidden {c4.download_games menu.tools.download download_games} $object] [expr {"c4.download_games" in $ids}] [expr {"download_games" in $tools}]
} -cleanup {
 rename ::application::download::openActive_ruleSaved ::application::download::openActive
 destroy .ruledownload
} -result {0 {} 0 0}

tcltest::test rule-regression-trial {real trial hides C2 mutations and refuses direct execution without changing game} -setup {
 ::scidb::test::askscope::NewGame
 ::scidb::game::go 2
 ::game::flipTrialMode
 update
} -body {
 set obj [::context::CurrentObject C2]
 set before [::scidb::game::query length]
 set forbidden {c2.add_variation c2.replace_move c2.strip c2.strip.moves c2.strip.truncate c2.strip.variations c2.strip.annotations c2.strip.info c2.strip.marks c2.strip.comments c2.strip.language}
 menu .ruletrial -tearoff 0
 ::context::Build C2 .ruletrial $obj
 set posted [::scidb::test::askscope::MenuIds .ruletrial C2]
 set bad [::scidb::test::askscope::RuleHidden $forbidden $obj]
 foreach id $forbidden {
  if {$id in $posted || ![string match error:* [::action::run $id [dict create object $obj]]]} {lappend bad $id}
 }
 list [::game::trialMode?] $bad [expr {$before == [::scidb::game::query length]}]
} -cleanup {destroy .ruletrial; ::game::flipTrialMode; update} -result {1 {} 1}

proc ::scidb::test::askscope::RuleText {{w .application}} {
 foreach c [winfo children $w] {
  if {[winfo viewable $c] && [winfo class $c] eq "Text" && [string match *PopupMenu* [bind $c <Button-3>]]} {return $c}
  set found [RuleText $c]
  if {$found ne ""} {return $found}
 }
 return ""
}
tcltest::test rule-regression-blank-notation {native right click on tagless notation does not post current move menu} -body {
 ::scidb::test::askscope::FocusPane editor
 set text [::scidb::test::askscope::RuleText]
 if {$text eq ""} {error {no notation text}}
 set x [expr {[winfo width $text]-10}]
 set y [expr {[winfo height $text]-10}]
 if {[$text tag names @$x,$y] ne {}} {error {blank pixel must have no tags}}
 event generate $text <ButtonPress-3> -x $x -y $y
 event generate $text <ButtonRelease-3> -x $x -y $y
 update
 set m $::application::pgn::Vars(frame).__menu__
 expr {[winfo exists $m] && [winfo ismapped $m]}
} -result 0

tcltest::test rule-regression-board-fold {each listed board fold reverses without geometry errors and restores flat state} -body {
 ::scidb::test::askscope::FocusPane board
 set obj [::context::CurrentObject C9]
 set twm [dict get $obj twm]
 set frame [dict get $obj frame]
 set initial [$twm get! $frame flat 0]
 set bad {}
 for {set i 0} {$i<6} {incr i} {
  ::scidb::test::askscope::FocusPane board
  if {"c9.fold" ni [::scidb::test::askscope::AskContextIds C9]} {lappend bad not-listed}
  set reply [::action::run c9.fold [dict create object $obj]]
  update
  if {[string match error:* $reply]} {lappend bad $reply}
  set flat [$twm get! $frame flat 0]
  if {$flat != ($initial ^ (($i+1)%2))} {lappend bad wrong-state}
  set packed [pack slaves $frame.__header__]
  if {("$frame.__header__.title" in $packed) == $flat || ("$frame.__header__.zoom" in $packed) == $flat} {lappend bad wrong-header}

 }
 set bad
} -result {}
::scidb::test::actions::release
::tcltest::cleanupTests
