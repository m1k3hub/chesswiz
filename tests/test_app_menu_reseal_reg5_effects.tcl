# Native posted operations: production handlers, database and renderer.
# Only the language model provider is deterministic at the network boundary.
package require tcltest 2.5
source tests/app_actions_support.tcl
source tests/app_menu_reseal_scope_support.tcl
::scidb::test::actions::ready
::application::ai::configure -provider stub -model {}
::ai::provider::configure -name stub -model {} -responses {{The database contains generated games.}}
namespace eval ::reg5effect {}
proc ::reg5effect::postInvoke {id} {
 catch {destroy .reg5effect}
 menu .reg5effect -tearoff 0
 ::menu::BuildDropdown .reg5effect
 .reg5effect post 20 20
 set found [findRow .reg5effect $id]
 if {![llength $found]} {error "Native dropdown did not post $id"}
 lassign $found m i
 if {[$m entrycget $i -state] ne "normal"} {error "Posted $id is disabled"}
 set command [$m entrycget $i -command]
 if {[lrange $command 0 1] ne [list ::action::run $id]} {error "Unregistered posted row: $command"}
 set result [$m invoke $i]
 catch {::tk::MenuUnpost .reg5effect};catch {destroy .reg5effect}
 update
 puts [list POSTED_EFFECT $id result $result title $::application::report::Priv(title)]
 return $result
}
proc ::reg5effect::findRow {m id} {
 set last [$m index end]
 if {$last eq "none"} {return {}}
 for {set i 0} {$i <= $last} {incr i} {
  if {[$m type $i] eq "cascade"} {
   $m postcascade $i;update
   set result [findRow [$m entrycget $i -menu] $id]
   if {[llength $result]} {return $result}
  } elseif {[$m type $i] in {command radiobutton checkbutton} && [lindex [$m entrycget $i -command] 1] eq $id} {return [list $m $i]}
 }
 return {}
}
proc ::reg5effect::reportContains {text} {
 update
 set w $::application::report::Priv(html).sub.html
 expr {[winfo exists $w] && [winfo ismapped $w] && [string first $text [$w text text]] >= 0}
}
set base [::scidb::test::actions::fixture]
set f [open $base a]
puts $f {[Event "Generated result defect"]
[Site "Test"]
[Date "2026.01.02"]
[Round "2"]
[White "Generated White"]
[Black "Generated Black"]
[Result "1-0"]

1. f3 e5 2. g4 Qh4# 1-0}
close $f
proc ::reg5effect::nop {args} {return 0}
::scidb::db::open $base ::reg5effect::nop {} ::reg5effect::nop {}
set native [file rootname $base].sci
::scidb::db::new $native Normal [::application::database::lookupType Unspecific]
::scidb::db::attach $native $native
::scidb::db::copy $base $native {} ::reg5effect::nop {} ::reg5effect::nop {}
::scidb::db::save $native ::reg5effect::nop {}
::scidb::db::close $native
::scidb::db::close $base
set base $native
::action::run open_database [dict create path $base]
# Import normalises terminal results; deliberately edit the generated
# game's characteristics through the real database API after import.
set tags [::scidb::db::get tags 1 $base Normal]
set tags [lmap pair $tags {if {[lindex $pair 0] eq "Result"} {list Result 1-0} else {set pair}}]
if {[catch {::scidb::db::update $base Normal 1 [concat {*}$tags]} err opts]} {puts [list TAG_SETUP tags $tags error $err options $opts];error {Unable to set generated result characteristics}}
::action::run open_game {number 1 move 1 after white}
::application::switchTab board
::scidb::game::go 1
::scidb::game::update addcomment [::scidb::game::position key] after {White has an isolated pawn.}
update
tcltest::test reg5-posted-factcheck {native Fact Check examines the loaded game's annotations and renders actual findings} -body {
 set key [::scidb::game::position key]
 set result [::reg5effect::postInvoke menu.analysis.factcheck]
 list [string match {*1 annotation*} $result] [::reg5effect::reportContains {White has an isolated pawn.}] [expr {$key eq [::scidb::game::position key]}]
} -result {1 1 1}
tcltest::test reg5-posted-result-check {native Check Results filters the real database to the inconsistent result and renders it} -body {
 ::reg5effect::postInvoke menu.training.check_results
 set info [::scidb::db::get gameInfo 0 0 $base Normal]
 list [::scidb::view::count games $base Normal 0] [::reg5effect::reportContains {White is mated, but the result is 1-0}]
} -result {1 1}
tcltest::test reg5-posted-trend {native Trends calls the provider and renders its grounded response in the real pane} -body {
 ::ai::provider::configure -name stub -responses {{The database contains generated games.}}
 ::reg5effect::postInvoke menu.db.reports.trends
 ::scidb::test::actions::waitUntil {[::reg5effect::reportContains {The database contains generated games.}]}
 set ok [::reg5effect::reportContains {The database contains generated games.}]
 list $ok $::application::report::Priv(title)
} -result {1 {AI: database trends}}
# A real comment editor and rule-recognised script: no classifier stub.
proc ::reg5effect::commentTest {} {
set w $::comment::Vars(widget:text:$::comment::Vars(lang)).text
::comment::SetupComment $::comment::Vars(lang) {{str {Καλή κίνηση}}} 1
focus -force $w
update
tcltest::test reg5-posted-detect-language {native Detect Language carries editor text to the detected language tab} -body {
 menu .reg5comment -tearoff 0
 ::context::Build C11 .reg5comment [::context::CurrentObject C11]
 set found [::reg5effect::findRow .reg5comment c11.detect_language]
 if {![llength $found]} {error {Detect Language was not posted}}
 lassign $found m i
 $m invoke $i
 update
 list $::comment::Vars(lang) [string trim [$::comment::Vars(widget:text:el).text get 1.0 end]]
} -cleanup {catch {destroy .reg5comment};catch {destroy $::comment::Vars(dialog)}} -result {el {Καλή κίνηση}}
}
after 100 ::reg5effect::commentTest
::scidb::game::go 1
::application::pgn::editComment after
update
# Jobs deliberately return an executable plan, with no downstream handlers replaced.
foreach {job required} {prepare opponent_brief review study_plan repertoire repertoire_check train training_set} {
 tcltest::test reg5-job-$job {job operation creates its actual tool plan through registry dispatch} -body {
  set ::application::ai::Settings(me) {Generated White}
  set result [::action::run run_job [dict create job $job name {Generated Black}]]
  puts [list JOB_EFFECT $job result $result]
  expr {[string first $required $result] >= 0 && $::application::assistant::Priv(maxRounds) == 14}
 } -result 1
}
foreach pos [::game::usedPositions?] {::application::pgn::release $pos;::game::release $pos}
::application::database::closeBase .application $base
::scidb::test::actions::cleanup
::tcltest::cleanupTests
