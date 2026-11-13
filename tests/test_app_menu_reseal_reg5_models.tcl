# Native model and long-running job rows: real engine, renderer and files.
# Only the ordinary provider's built-in deterministic transport is selected.
package require tcltest 2.5
source tests/app_actions_support.tcl
source tests/app_menu_reseal_effect_support.tcl
::scidb::test::actions::ready
::application::ai::configure -provider stub -model {}
::ai::provider::configure -name stub -model {} -responses {{Generated explanation.}}
::ai::engine::configure -engine [::scidb::test::actions::engineProgram] -depth 1
set base [::scidb::test::actions::fixture]
set f [open $base a]
puts $f {[Event "Generated tactical finish"]
[Site "Test"]
[Date "2026.01.02"]
[Round "2"]
[White "Generated White"]
[Black "Generated Black"]
[Result "0-1"]

1. f3 e5 2. g4 Qh4# 0-1}
close $f
::action::run open_database [dict create path $base]
::action::run open_game {number 1 move 1 after white}
::application::switchTab board
::scidb::game::go 1
::scidb::game::update addcomment [::scidb::game::position key] after {A generated comment.}
foreach id {menu.analysis.explain.position menu.analysis.explain.move menu.analysis.explain.comment} {
 tcltest::test reg5-posted-model-$id {posted model operation renders the actual provider reply} -body {
  ::application::ai::showReport .application {Before operation} {<p>Before operation</p>}
  ::ai::provider::configure -name stub -responses {{Generated explanation.}} -chatResponses [list [dict create role assistant content {Generated explanation.}]]
  ::reg5effect::postInvoke $id
  ::scidb::test::actions::waitUntil {[::reg5effect::reportContains {Generated explanation.}]} 30000
  ::reg5effect::reportContains {Generated explanation.}
 } -result 1
}

tcltest::test reg5-native-move-explanation {native move context renders the provider response} -body {
 ::ai::provider::configure -name stub -chatResponses [list [dict create role assistant content {Generated move explanation.}]]
 ::reg5effect::postContext C2 c2.explain_move
 ::scidb::test::actions::waitUntil {[::reg5effect::reportContains {Generated move explanation.}]} 30000
 ::reg5effect::reportContains {Generated move explanation.}
} -result 1
tcltest::test reg5-posted-brief {native Brief collects an actual opponent name and renders the brief} -body {
 ::ai::provider::configure -name stub -responses {{Generated opponent brief.}}
 ::reg5effect::postInvoke menu.training.brief
 set dlg .application.__briefask__
 if {![winfo ismapped $dlg]} {error {Brief name form did not open}}
 $dlg.name insert 0 {Generated Black}
 $dlg.buttons.ok invoke
 ::scidb::test::actions::waitUntil {[::reg5effect::reportContains {Generated opponent brief.}]} 30000
 ::reg5effect::reportContains {Generated opponent brief.}
} -result 1
tcltest::test reg5-posted-studyplan {native Study Plan completes its engine audit and renders the measured result} -body {
 ::ai::studyplan::configure -games 1 -depth 1 -prose 0
 ::reg5effect::postInvoke menu.training.studyplan
 ::scidb::test::actions::waitUntil {![::ai::studyplan::running?]} 30000
 puts [list STUDY_EFFECT games $::ai::studyplan::Priv(gameIndex) moves $::ai::studyplan::Priv(moveIndex) html [dict get $::application::report::Priv(data) html]]
 list [expr {$::ai::studyplan::Priv(gameIndex) > 0}] [expr {$::ai::studyplan::Priv(moveIndex) > 0}] [winfo ismapped $::application::report::Priv(window)]
} -result {1 1 1}
tcltest::test reg5-posted-annotate {native Annotate completes an actual engine classification and writes a grounded comment} -body {
 ::scidb::game::go start
 ::ai::annotate::configure -classes {Best Excellent Good Inaccuracy Mistake Blunder} -depth 1 -maxPlies 1 -prose 0
 ::reg5effect::postInvoke menu.analysis.annotate
 ::scidb::test::actions::waitUntil {![::ai::annotate::running?]} 30000
 ::scidb::game::go 1
 set comment [::scidb::game::query comment after]
 puts [list ANNOTATE_EFFECT comment $comment report [dict get $::application::report::Priv(data) html]]
 expr {[string length $comment] > 0 && $comment ne {A generated comment.}}
} -result 1
tcltest::test reg5-posted-training-set {native Training Set creates its output artifact and renders a completion report} -body {
 ::reg5effect::postInvoke menu.training.training_set
 ::scidb::test::actions::waitUntil {![::ai::cql::running?]} 60000
 set file $::ai::cql::Priv(file)
 puts [list TRAINING_EFFECT file $file bytes [file size $file] report [dict get $::application::report::Priv(data) html]]
 list [file exists $file] [winfo ismapped $::application::report::Priv(window)]
} -result {1 1}

proc ::reg5effect::commentModels {} {
 set w $::comment::Vars(widget:text:$::comment::Vars(lang)).text
 foreach {id text} {c11.explain_comment {Generated live comment explanation.} c11.draft_comment {Generated live comment draft.}} {
  tcltest::test reg5-native-model-$id {native comment operation uses the live editor and its real model pipeline} -body {
   ::comment::SetupComment $::comment::Vars(lang) {{str {Unsaved current editor text.}}} 1
   ::ai::provider::configure -name stub -chatResponses [list [dict create role assistant content $text]]
   ::reg5effect::postContext C11 $id
   ::scidb::test::actions::waitUntil {![::application::ai::busy?]} 30000
   if {$id eq "c11.draft_comment"} {
    expr {[string first $text [$w get 1.0 end]] >= 0}
   } else {::reg5effect::reportContains $text}
  } -result 1
 }

 tcltest::test reg5-native-comment-classification {native classification reads unsaved text and shows its actual rule result} -body {
  ::comment::SetupComment $::comment::Vars(lang) {{str {The plan is to improve the position.}}} 1
  set ::reg5effect::classification {}
  set ::reg5effect::classTimer [after 20 ::reg5effect::observeClassification]
  ::reg5effect::postContext C11 c11.classify_comment
  ::scidb::test::actions::waitUntil {[llength $::reg5effect::classification]} 5000
  lassign $::reg5effect::classification mapped text
  puts [list CLASSIFICATION_EFFECT mapped $mapped text $text]
  list $mapped [expr {[string first [::ai::comment::Name plan] $text] >= 0}]
 } -cleanup {after cancel $::reg5effect::classTimer} -result {1 1}
 destroy $::comment::Vars(dialog)
}
::scidb::game::go 1
after 100 ::reg5effect::commentModels
::application::pgn::editComment after
::ai::engine::shutdown
::scidb::test::actions::cleanup
::tcltest::cleanupTests
