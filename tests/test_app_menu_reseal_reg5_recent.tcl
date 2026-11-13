package require tcltest 2.5
source tests/app_actions_support.tcl
::scidb::test::actions::ready
set pgn [::scidb::test::actions::fixture]
puts [list GENERATED $pgn]
set opened [::action::run open_database [dict create path $pgn]]
puts [list OPEN_RESULT $opened]
::application::database::closeBase .application $pgn
update
puts [list RECENT_STATE $::application::database::RecentFiles]
menu .realDropdown -tearoff 0
::menu::BuildDropdown .realDropdown
.realDropdown post 20 20
.realDropdown postcascade 0
update
set fileMenu [.realDropdown entrycget 0 -menu]
set recentMenu {}
for {set j 0} {$j <= [$fileMenu index end]} {incr j} {
 if {[$fileMenu type $j] ne "cascade"} {continue}
 set sub [$fileMenu entrycget $j -menu]
 if {[string match {*FillDynamic OpenRecent*} [$sub cget -postcommand]]} {
  set recentMenu $sub
  $fileMenu postcascade $j
  update
  break
 }
}
if {$recentMenu eq ""} {error {real File > Open Recent cascade not found}}
puts [list REACHED_MAIN_DROPDOWN root .realDropdown file $fileMenu recent $recentMenu mapped [winfo ismapped $recentMenu]]
set cropX [winfo rootx $recentMenu]
set cropY [expr {[winfo rooty $recentMenu]+[$recentMenu yposition end]}]
set cropW [winfo width $recentMenu]
set cropH [expr {[winfo height $recentMenu]-[$recentMenu yposition end]-2}]
set last [$recentMenu index end]
for {set i 0} {$i <= $last} {incr i} {
 if {[$recentMenu type $i] eq "separator"} {continue}
 puts [list RECENT_ROW index $i label [$recentMenu entrycget $i -label] state [$recentMenu entrycget $i -state] command [$recentMenu entrycget $i -command]]
}
set clearCmd [$recentMenu entrycget $last -command]
set before [llength $::application::database::RecentFiles]
set result [$recentMenu invoke $last]
update
set after [llength $::application::database::RecentFiles]
puts [list CLEAR_EFFECT before $before after $after result $result command $clearCmd]
$recentMenu unpost
catch {grab release $recentMenu}
tcltest::test recent-fixed-clear-is-registry {fixed Clear History is not a data-row exemption} -body {
 list [expr {$before>0 && $after==0}] [string match {::action::run *} $clearCmd]
} -result {1 1}
::tcltest::cleanupTests
