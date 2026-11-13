package require tcltest 2.5
source tests/app_actions_support.tcl
::scidb::test::actions::ready
set base [::scidb::test::actions::fixture]
::action::run open_database [dict create path $base]
set slot [::game::new .application -base $base -variant Normal -number 0 -lock 1]
::application::pgn::select $slot
update
puts [list INITIAL gameHistory [llength $::game::History] recentFiles [llength $::application::database::RecentFiles]]
menu .freshhistory -tearoff 0
::menu::BuildDropdown .freshhistory
proc walkHistory {m} {
 if {$m eq "" || ![winfo exists $m]} {return {}}
 set last [$m index end]
 if {$last eq "none"} {return {}}
 for {set i 0} {$i <= $last} {incr i} {
  if {[$m type $i] eq "cascade"} {
   set sub [$m entrycget $i -menu]
   if {$sub eq "" || ![winfo exists $sub]} {continue}
   $sub post 30 30
   set found [walkHistory $sub]
   $sub unpost
   if {$found ne {}} {return $found}
  } elseif {[$m type $i] ne "separator"} {
   set cmd [$m entrycget $i -command]
   puts [list ACTUAL_ROW label [$m entrycget $i -label] command $cmd state [$m entrycget $i -state]]
   if {[lindex $cmd 1] eq "menu.game.history.clear"} {return [list $m $i]}
  }
 }
 return {}
}
.freshhistory post 20 20
set found [walkHistory .freshhistory]
.freshhistory unpost
if {$found eq {}} {error {Game History > Clear History not posted}}
lassign $found m i
set before $::game::History
set recentBefore $::application::database::RecentFiles
set reply [$m invoke $i]
update
puts [list HISTORY_CLEAR_EFFECT beforeGameCount [llength $before] afterGameCount [llength $::game::History] beforeRecentCount [llength $recentBefore] afterRecentCount [llength $::application::database::RecentFiles] reply $reply]
tcltest::test game-history-clear-native {posted Game History clear clears games rather than database file history} -body {list [expr {[llength $before] > 0}] [llength $::game::History] [expr {$recentBefore eq $::application::database::RecentFiles}]} -result {1 0 1}
tcltest::test database-history-clear-native {database Clear History preserves game history} -body {
 # Restore the history cleared by the preceding test using the real record.
 set ::game::History $before
 set gameBefore $::game::History
 ::action::run menu.file.recent.clear
 list [llength $::application::database::RecentFiles] [expr {$::game::History eq $gameBefore}]
} -result {0 1}
::tcltest::cleanupTests
