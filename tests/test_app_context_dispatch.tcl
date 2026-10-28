package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready
namespace eval ::dispatchTest {}
# Tcl's switch body is a list; inspect its patterns without executing callbacks.
proc ::dispatchTest::patterns {} {
 set body [info body ::context::Command]
 set start [string first {switch -glob -- $id} $body]
 set script [string range $body $start end]
 # The complete switch is obtained by progressively reading complete Tcl script.
 set chunk {}
 foreach line [split $script \n] {
  append chunk $line \n
  if {[info complete $chunk]} {break}
 }
 set arms [lindex $chunk 4]
 set patterns {}
 foreach {pattern code} $arms {lappend patterns $pattern}
 return $patterns
}
tcltest::test dispatch-registry-leaves {every context registry leaf has a dispatch arm or a dynamic cascade builder} -body {
 set patterns [::dispatchTest::patterns]
 set parents {}
 dict for {cid spec} $::context::Menus {
  set text [lindex $spec 1]
  foreach {whole id} [regexp -all -inline {cascade ([^ {}]+)} $text] {lappend parents $id}
 }
 set missing {}
 dict for {id r} $::action::Registry {
  if {[lindex [dict get $r handler] 0] ne "::context::InvokeArgs" || $id in $parents} {continue}
  set found 0
  foreach pattern $patterns {if {$pattern ne "default" && [string match $pattern $id]} {set found 1;break}}
  if {!$found} {lappend missing $id}
 }
 set missing
} -result {}
tcltest::test dispatch-never-empty {missing dispatch and void results cannot become empty successful invocations} -body {
 set results {}
 foreach id {missing.leaf c1.copy_fen c9.assistant.clear c7.external c9.report.size c9.report.zoom c9.report.family c11.draft_comment c12.save.line c12.save.repertoire c2.strip.language c5.site_url c5.player.prep} {
  lappend results [expr {[::context::Invoke $id {}] ne ""}]
 }
 lsort -unique $results
} -result 1
tcltest::test dispatch-removed {unimplemented controls are absent from registry and menu definitions} -body {
 set retained {}
 if {[dict exists $::action::Registry print_report]} {lappend retained print_report}
 foreach suffix {assistant.local assistant.cloud explorer.tablebase report.print assistant.source} {
  set id c9.$suffix
  if {[dict exists $::action::Registry $id] || [string first $id $::context::Menus]>=0} {lappend retained $id}
 }
 set retained
} -result {}
tcltest::test dispatch-report-font {real HTML viewer size changes and native family callback update the viewer} -setup {
 catch {destroy .dispatchReport}
 toplevel .dispatchReport
 ::application::report::build .dispatchReport 400 300
} -body {
 ::font::html::setupFonts report
 set a [::application::report::SetSize 14]
 set b [$::application::report::Priv(html) fontsize?]
 ::font::html::SetFont report ::application::report::ApplyFont {DejaVu Sans}
 list $a $b [::font::html::textFont report]
} -cleanup {destroy .dispatchReport} -result {14 14 {DejaVu Sans}}


tcltest::test dispatch-draft {native draft callback writes model result into the comment editor for review} -setup {
 set savedVars [array get ::comment::Vars]
 toplevel .dispatchComment
 frame .dispatchComment.editor
 text .dispatchComment.editor.text
 set ::comment::Vars(lang) en
 set ::comment::Vars(widget:text:en) .dispatchComment.editor
 rename ::application::ai::generate ::dispatchTest::realGenerate
 proc ::application::ai::generate {parent title progress fen args} {
  set observer [lindex $args [expr {[lsearch -exact $args -observer]+1}]]
  {*}$observer [dict create ok 1 text {Generated annotation for review.}]
 }
} -body {
 set reply [::action::run c11.draft_comment [dict create object [dict create widget .dispatchComment.editor.text]]]
 list [string match error:* $reply] [.dispatchComment.editor.text get 1.0 end-1c]
} -cleanup {
 rename ::application::ai::generate {}
 rename ::dispatchTest::realGenerate ::application::ai::generate
 array unset ::comment::Vars
 array set ::comment::Vars $savedVars
 destroy .dispatchComment
} -result {0 {Generated annotation for review.}}

tcltest::test dispatch-external {native launcher passes selected media path to the OS boundary} -setup {
 rename ::platform::sys::openURL ::dispatchTest::realOpenURL
 proc ::platform::sys::openURL {url} {set ::dispatchTest::opened $url}
} -body {
 set reply [::action::run c7.external [dict create object [dict create path /tmp/generated-film.mp4]]]
 list $reply $::dispatchTest::opened
} -cleanup {
 rename ::platform::sys::openURL {}
 rename ::dispatchTest::realOpenURL ::platform::sys::openURL
} -result {{external media player requested} /tmp/generated-film.mp4}

tcltest::test dispatch-repertoire-menus {both native repertoire builders provide real destinations or the native no-destination explanation} -body {
 set result {}
 foreach id {c12.save.line c12.save.repertoire} {
  set reply [::action::run $id [dict create object [dict create gameSlot [::scidb::game::current] variant Normal]]]
  set m .contextChoices_repertoire
  lappend result [list $reply [expr {[$m index end] ne "none"}] [expr {[$m entrycget 0 -command] ne ""}]]
  $m unpost
  catch {grab release $m}
  destroy $m
 }
 set result
} -result {{{opened choices} 1 1} {{opened choices} 1 1}}

tcltest::test dispatch-report-choices {size zoom and family open working native font menus} -setup {
 toplevel .dispatchReport
 ::application::report::build .dispatchReport 400 300
} -body {
 set result {}
 foreach id {c9.report.size c9.report.zoom c9.report.family} {
  lappend result [::action::run $id [dict create object [dict create paneUid report]]]
  set m .contextChoices_reportFont
  if {$id ne "c9.report.family"} {$m invoke 6; lappend result [$::application::report::Priv(html) fontsize?]}
  $m unpost
  catch {grab release $m}
  destroy $m
 }
 set result
} -cleanup {destroy .dispatchReport} -result {{opened choices} 14 {opened choices} 14 {opened choices}}

tcltest::test dispatch-strip-language {selective removal acts on an imported game and rejects absent languages} -setup {
 ::menu::gameNew .application
 set slot [::scidb::game::current]
 ::scidb::game::import $slot {1. e4 {English annotation} e5 *} {} {} -encoding utf-8 -variation 0
 set savedLanguages $::application::pgn::Vars(lang:set)
 set ::application::pgn::Vars(lang:set) {xx}
} -body {
 set before [::scidb::game::count comments]
 set reply [::action::run c2.strip.language [dict create object [dict create language xx]]]
 set after [::scidb::game::count comments]
 list [expr {$before > 0}] $after $reply [string match error:* [::context::Invoke c2.strip.language {language zz}]]
} -cleanup {set ::application::pgn::Vars(lang:set) $savedLanguages} -result {1 0 {removed comments in xx} 1}


tcltest::test dispatch-site-url {selected site URL uses the native web opener; a non-URL fails} -setup {
 rename ::platform::sys::openURL ::dispatchTest::realOpenURL
 proc ::platform::sys::openURL {url} {set ::dispatchTest::opened $url}
} -body {
 set reply [::action::run c5.site_url [dict create object [dict create name https://example.org/generated]]]
 list $reply $::dispatchTest::opened [string match error:* [::context::Invoke c5.site_url {name Nowhere}]]
} -cleanup {
 rename ::platform::sys::openURL {}
 rename ::dispatchTest::realOpenURL ::platform::sys::openURL
} -result {{opened site web address} https://example.org/generated 1}

tcltest::test dispatch-player-preparation {native player preparation report opens on a generated database} -setup {
 source [file join [file dirname [info script]] app_actions_support.tcl]
 set base [::scidb::test::actions::fixture]
 set opened [::action::run open_database [dict create path $base]]
 update
 set ::application::database::NonSciWorkflowAdvice($base:Normal:prep-report) 1
 lassign [::application::assistant::ResolvePlayer $base Normal {Generated White}] index name
} -body {
 set reply [::action::run c5.player.prep [dict create object [dict create base $base variant Normal index $index name $name]]]
 set dlg [::application::database::player::PrepReportDialogName $base Normal $index]
 update
 list $reply [winfo exists $dlg]
} -cleanup {
 if {[info exists dlg] && [winfo exists $dlg]} {::application::database::player::ClosePrepReport $dlg}
 ::application::database::closeBase .application $base
 file delete -force $::scidb::test::actions::Dir
} -result {{opened player preparation report} 1}


tcltest::test dispatch-repertoire-destinations {both native menus name an actual writable repertoire and carry its save callback} -setup {
 set repDir [file join [file dirname [info script]] tmp-app dispatch-repertoire-[pid]]
 file mkdir $repDir
 set rep [file normalize [file join $repDir generated-repertoire.sci]]
 ::scidb::db::new $rep Normal [::application::database::lookupType OpeningsWhite]
 ::scidb::db::attach $rep $rep
} -body {
 set results {}
 foreach id {c12.save.line c12.save.repertoire} {
  set reply [::action::run $id [dict create object [dict create gameSlot [::scidb::game::current] variant Normal]]]
  set m .contextChoices_repertoire
  lappend results [list $reply [expr {[$m entrycget 0 -label] eq [::util::databaseName $rep]}] [expr {[string first $rep [$m entrycget 0 -command]]>=0}]]
  $m unpost
  catch {grab release $m}
  destroy $m
 }
 set results
} -cleanup {
 ::scidb::db::close $rep
 file delete -force $repDir
} -result {{{opened choices} 1 1} {{opened choices} 1 1}}
# No selected object must never be reported as an empty successful action.
# The unposted pane-toggle aliases identify their target in the id; their
# no-argument effects are covered by ask-scope-c9-pane-rows.
tcltest::test dispatch-all-leaves-no-object {every posted context leaf refuses missing selection before dispatch} -setup {
 set ::dispatchTest::calls 0
 proc ::dispatchTest::entered {args} {incr ::dispatchTest::calls}
 trace add execution ::context::Command enter ::dispatchTest::entered
 set clipBefore [catch {clipboard get} clipValue]
} -body {
 set bad {}
 set count 0
 dict for {id r} $::action::Registry {
  if {![::context::NeedsObject $r]} continue
  incr count
  foreach input {{object {}}} {
   set raw [::context::Invoke $id {}]
   if {![string match {error: precondition:*} $raw]} {lappend bad [list $id raw $raw]}
   set reply [::action::run $id $input]
   if {![string match {error: precondition:*} $reply]} {lappend bad [list $id $reply]}
  }
 }
 puts "CONTEXT_NO_OBJECT_LEAVES $count"
 list [expr {$count > 200}] $bad $::dispatchTest::calls [expr {[catch {clipboard get} now] == $clipBefore && $now eq $clipValue}]
} -cleanup {
 trace remove execution ::context::Command enter ::dispatchTest::entered
 rename ::dispatchTest::entered {}
} -result {1 {} 0 1}

tcltest::test dispatch-receipt-effect {a void callback receipt accompanies a real clipboard change} -body {
 clipboard clear; clipboard append {before action}
 set reply [::action::run c1.copy_fen [dict create object [::context::CurrentObject C1]]]
 list $reply [expr {[clipboard get] eq [::scidb::pos::fen]}]
} -result {{completed c1.copy_fen} 1}

tcltest::test dispatch-pane-alias-operator {a target named in the id runs through the generic operator without a separate selection} -setup {
 set twm [::application::twm board]
 set before [expr {"tree" in [$twm leaves]}]
} -body {
 set first [::knowledge::RunAction c9.pane.tree {}]
 update
 set after [expr {"tree" in [$twm leaves]}]
 set second [::knowledge::RunAction c9.pane.tree {}]
 update
 list $first $second [expr {$before != $after}] [expr {$before == ("tree" in [$twm leaves])}]
} -cleanup {
 if {$before != ("tree" in [$twm leaves])} {::action::run c9.pane.tree}
} -result {{completed c9.pane.tree} {completed c9.pane.tree} 1 1}

tcltest::test dispatch-export-precondition {an incomplete selected game refuses before the exporter is called} -setup {
 set ::dispatchTest::calls 0
 proc ::dispatchTest::entered {args} {incr ::dispatchTest::calls}
 trace add execution ::gamebar::exportGame enter ::dispatchTest::entered
} -body {
 set reply [::action::run c12.export {object {gameSlot 0}}]
 set operator [::knowledge::RunAction c12.export {object {gameSlot 0}}]
 list [string match {error: precondition:*} $reply] [string match {error: precondition:*} $operator] $::dispatchTest::calls
} -cleanup {
 trace remove execution ::gamebar::exportGame enter ::dispatchTest::entered
 rename ::dispatchTest::entered {}
} -result {1 1 0}

tcltest::test dispatch-export-error {a failed callback never receives a completion receipt} -setup {
 rename ::gamebar::exportGame ::dispatchTest::realExport
 proc ::gamebar::exportGame {args} {error {export failed deliberately}}
} -body {
 ::context::Invoke c12.export {id 0}
} -cleanup {
 rename ::gamebar::exportGame {}
 rename ::dispatchTest::realExport ::gamebar::exportGame
} -result {error: export failed deliberately}

tcltest::test dispatch-export-live {current game lookup and execution agree and the real exporter opens its dialog} -setup {
 ::menu::gameNew .application
 foreach move {d4 d5 c4 e6} {::move::addMove menu $move}
 set ::dispatchTest::calls 0
 set ::dispatchTest::dialog 0
 proc ::dispatchTest::entered {args} {incr ::dispatchTest::calls}
 proc ::dispatchTest::windows {w} {
  set out {}
  foreach c [winfo children $w] {lappend out $c {*}[windows $c]}
  return $out
 }
 proc ::dispatchTest::closeExport {} {
  foreach w [::dispatchTest::windows .application] {
   if {[string match *.export $w] && [winfo ismapped $w]} {
    set ::dispatchTest::dialog 1
    destroy $w
    return
   }
  }
  set ::dispatchTest::timer [after 50 ::dispatchTest::closeExport]
 }
 trace add execution ::gamebar::exportGame enter ::dispatchTest::entered
 set ::dispatchTest::timer [after 50 ::dispatchTest::closeExport]
} -body {
 set object [::context::CurrentObject C12]
 lassign [::knowledge::Runnable c12.export] runnable why
 set arg [lindex [::knowledge::ArgList c12.export [::action::get c12.export]] 0]
 set direct [::action::run c12.export {}]
 set first [list $direct $::dispatchTest::calls $::dispatchTest::dialog]
 set ::dispatchTest::dialog 0
 set ::dispatchTest::timer [after 50 ::dispatchTest::closeExport]
 set reply [::knowledge::RunAction c12.export {}]
 list $first $runnable [dict get $arg required] [string match {*id*} [dict get $arg description]] \
  [expr {[dict get $object id] == [::scidb::game::current]}] $reply $::dispatchTest::calls $::dispatchTest::dialog
} -cleanup {
 after cancel $::dispatchTest::timer
 trace remove execution ::gamebar::exportGame enter ::dispatchTest::entered
 rename ::dispatchTest::entered {}
 rename ::dispatchTest::closeExport {}
 rename ::dispatchTest::windows {}
} -result {{{completed c12.export} 1 1} 1 0 1 1 {completed c12.export} 2 1}

tcltest::test dispatch-create-databases {explicit file destinations create actual databases and return truthful receipts} -setup {
 set createDir [file normalize [file join [file dirname [info script]] tmp-app dispatch-create-[pid]]]
 file mkdir $createDir
} -body {
 set results {}
 foreach id {c4.new.scid c4.new.pgn} extension {sci pgn} {
  set target [file join $createDir generated.$extension]
  set reply [::action::run $id [dict create object [dict create file $target]]]
  lappend results [list $reply [file exists $target] [::scidb::db::get open? $target]]
  ::application::database::closeBase .application $target
 }
 set results
} -cleanup {file delete -force $createDir} -result {{{completed c4.new.scid} 1 1} {{completed c4.new.pgn} 1 1}}

::tcltest::cleanupTests
