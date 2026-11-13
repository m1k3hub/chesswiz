# Complete native caller menus, after their named-object builders return.
package require tcltest 2.5
source tests/test_app_menu_registry_walk.tcl
source tests/app_actions_support.tcl
::scidb::test::actions::ready
set base [::scidb::test::actions::fixture]
::action::run open_database [dict create path $base]
::action::run open_game {number 1 move 1 after white}
update
set second [::game::new .application -base $base -variant Normal -number 0 -lock 1]
::application::pgn::select $second
update
puts [list POPULATED_HISTORY gameCount [llength $::game::History] tabCount [::gamebar::size $::application::pgn::Vars(gamebar)]]
set gamebar $::application::pgn::Vars(gamebar)
set slot [::scidb::game::current]
::application::switchTab database
update
set manager $::application::database::Vars(games).twm
set path [set ::application::database::games::${manager}::Priv(table)]
::gamestable::Open(browse) $path 0
update
set ns {}
foreach candidate [namespace children ::browser] {if {[info exists ${candidate}::Vars(board)]} {set ns $candidate;break}}
if {$ns eq {}} {error {native game browser did not open}}
set position [namespace tail $ns];set board [set ${ns}::Vars(board)]
foreach kind {{} white black event} {
 tcltest::test reg5-browser-$kind {completed browser caller routes every operation through registry} -body {
  ::browser::PopupMenu .application $board $position $kind
  set m [winfo toplevel $board].__menu__
  ::scidb::test::rgw::PostTree $m
  set rows {};::scidb::test::rgw::WalkMenu $m rows browser.$kind
  puts [list COMPLETE_CALLER browser.$kind rows [llength $rows]]
  set violations [::scidb::test::rgw::BadCommands $rows]
  lassign [::scidb::test::rgw::ResolveRows $rows] resolved exempt unknown
  puts [list CALLER_RESOLUTION resolved $resolved exemptions $exempt unknown $unknown]
  foreach row $rows {puts [list FULL_CALLER_ROW {*}$row]}
  if {[llength $unknown]} {error [list UNKNOWN_IDS $unknown]}
  set violations
 } -cleanup {catch {::tk::MenuUnpost $m};catch {destroy $m}} -result {}
}
tcltest::test reg5-browser-board-effect {registered browser resizing changes its real board} -body {
 set before [set ${ns}::Vars(board:size)]
 set reply [::action::run browser.decrease [dict create object [dict create position $position board $board parent .application value {}]]]
 puts [list BROWSER_SIZE before $before after [set ${ns}::Vars(board:size)] reply $reply]
 update
 expr {[set ${ns}::Vars(board:size)] < $before}
} -result 1

tcltest::test reg5-browser-ask-selection {implicit browser actions resolve the focused browser and vanish after leaving it} -body {
 focus -force $board
 update
 # The preceding size probe may leave the board at its minimum.
 ::action::run browser.increase
 update
 set ids [lmap row [::action::labels asklist {}] {lindex $row 0}]
 set before [set ${ns}::Vars(board:size)]
 set result [::action::run browser.decrease]
 update
 set changed [expr {[set ${ns}::Vars(board:size)] < $before}]
 ::application::switchTab board
 focus -force $::application::board::Vars(widget:frame)
 update
 set other [lmap row [::action::labels asklist {}] {lindex $row 0}]
 puts [list BROWSER_ASK before $before result $result changed $changed]
 list [expr {"browser.decrease" in $ids}] $changed [expr {"browser.decrease" in $other}]
} -result {1 1 0}

tcltest::test reg5-browser-native-check-effect {native checkbutton arguments also change the option through direct action invocation} -setup {
 set savedCustomStyle $::theme::useCustomStyleMenuEntries
 set ::theme::useCustomStyleMenuEntries 0
} -body {
 set before $::pgn::browser::Options(style:column)
 ::browser::PopupMenu .application $board $position
 set m [winfo toplevel $board].__menu__
 set command {}
 for {set i 0} {$i <= [$m index end]} {incr i} {
  if {[$m type $i] eq "checkbutton" && [lindex [$m entrycget $i -command] 1] eq "browser.column_style_check"} {set command [$m entrycget $i -command];break}
 }
 if {$command eq {}} {error {native column-style checkbutton did not post}}
 # Include the native-checkbutton variant in the same invoke-every-row
 # inventory, alongside the four completed browser popup kinds above.
 set rows {}; ::scidb::test::rgw::WalkMenu $m rows browser.native-check
 if {[llength [::scidb::test::rgw::BadCommands $rows]]} {error {unregistered browser row}}
 lassign [::scidb::test::rgw::ResolveRows $rows] resolved exempt unknown
 if {[llength $unknown] || [llength $exempt]} {error [list unresolved-browser-rows $unknown $exempt]}
 set reply [::action::invoke browser.column_style_check [lindex $command 2]]
 update
 puts [list BROWSER_CHECK_EFFECT before $before after $::pgn::browser::Options(style:column) reply $reply]
 expr {$::pgn::browser::Options(style:column) != $before}
} -cleanup {
 set ::theme::useCustomStyleMenuEntries $savedCustomStyle
 catch {::tk::MenuUnpost $m};catch {destroy $m}
} -result 1

tcltest::test browser-disabled-real-merge {disabled merge cannot enter the real dialog through invoke} -body {
 ::browser::PopupMenu .application $board $position
 set m [winfo toplevel $board].__menu__
 set command {}
 for {set i 0} {$i <= [$m index end]} {incr i} {
  if {![catch {$m entrycget $i -command} cmd] && [lindex $cmd 1] eq "browser.merge"} {
   set command $cmd; set row $i; break
  }
 }
 if {$command eq {}} {error {merge row absent}}
 set nativeState [$m entrycget $row -state]
 set ::browserMergeCalls 0
 proc ::browserMergeTrace {args} {incr ::browserMergeCalls}
 trace add execution ::merge::openDialog enter ::browserMergeTrace
 $m invoke $row
 catch {::tk::MenuUnpost $m}
 set result [::action::invoke browser.merge [lindex $command 2]]
 update
 list $nativeState [string match {error:*not enabled} $result] $::browserMergeCalls [winfo exists .mergeDialog]
} -cleanup {
 catch {trace remove execution ::merge::openDialog enter ::browserMergeTrace}
 catch {rename ::browserMergeTrace {}}
 catch {destroy .mergeDialog}
 catch {destroy $m}
} -result {disabled 1 0 0}

# All registered enabled predicates share the dispatch gate, even outside
# browser actions. Errors fail closed and never reach a real operation.
tcltest::test browser-generic-enabled-gate {invoke enforces ordinary and argument-aware predicates} -body {
 set ::browserGateCalls 0
 proc ::browserGateLeaf {args} {incr ::browserGateCalls}
 set results {}
 foreach predicate {{expr 0} {error unavailable} {expr 1}} {
  ::action::register browser.test_gate [dict create label Gate object {} handler ::browserGateLeaf what Gate doc Gate enabled $predicate]
  lappend results [::action::invoke browser.test_gate]
  dict unset ::action::Registry browser.test_gate
 }
 list [string match {error:*not enabled} [lindex $results 0]] [string match {error:*not enabled} [lindex $results 1]] $::browserGateCalls
} -cleanup {
 catch {dict unset ::action::Registry browser.test_gate}
 rename ::browserGateLeaf {}
 unset ::browserGateCalls
} -result {1 1 1}

catch {destroy [winfo toplevel $board]}

::tcltest::cleanupTests
