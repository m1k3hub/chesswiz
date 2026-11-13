# Real native URL actions through an owned HTTP client process and loopback.
# No product handler or network API is replaced; PATH supplies the browser
# executable at the process boundary, keeping the developer desktop untouched.
package require tcltest 2.5
source tests/app_actions_support.tcl
::scidb::test::actions::ready
namespace eval ::reg5external {variable requests {}}
proc ::reg5external::accept {channel address port} {
 fconfigure $channel -blocking 0 -buffering line -translation crlf
 fileevent $channel readable [list ::reg5external::read $channel]
}
proc ::reg5external::read {channel} {
 if {[eof $channel]} {close $channel;return}
 while {[gets $channel line] >= 0} {
  if {[string match {GET *} $line]} {lappend ::reg5external::requests [lindex $line 1]}
  if {[string trim $line] eq {}} {
   puts -nonewline $channel "HTTP/1.0 200 OK\nContent-Length: 2\n\nOK"
   flush $channel;close $channel;return
  }
 }
}
proc ::reg5external::findRow {m id} {
 if {$m eq "" || ![winfo exists $m]} {return {}}
 set last [$m index end];if {$last eq "none"} {return {}}
 for {set i 0} {$i <= $last} {incr i} {
  if {[$m type $i] eq "cascade"} {
   $m postcascade $i;update
   set found [findRow [$m entrycget $i -menu] $id]
   if {[llength $found]} {return $found}
  } elseif {[$m type $i] in {command checkbutton radiobutton} && [lindex [$m entrycget $i -command] 1] eq $id} {return [list $m $i]}
 }
 return {}
}
proc ::reg5external::traceRun {command code result operation} {puts [list ACTION_LEAVE $command code $code result $result]}
trace add execution ::action::run leave ::reg5external::traceRun
set server [socket -server ::reg5external::accept -myaddr 127.0.0.1 0]
set port [lindex [fconfigure $server -sockname] 2]
set url http://127.0.0.1:$port/generated
set dir $::scidb::test::actions::Dir
file mkdir $dir/bin
set shim [open $dir/bin/xdg-open w]
puts $shim {#!/usr/bin/python3
import sys,urllib.request
with urllib.request.urlopen(sys.argv[1],timeout=5) as response:
    assert response.read()==b'OK'}
close $shim
file attributes $dir/bin/xdg-open -permissions 0755
set savedPath $::env(PATH)
set ::env(PATH) $dir/bin:$::env(PATH)
unset -nocomplain ::auto_execs(xdg-open)
set base [::scidb::test::actions::fixture]
set f [open $base r];set pgn [read $f];close $f
set f [open $base w];puts $f [string map [list {[Site "Test"]} "\[Site \"$url\"\]"] $pgn];close $f
::action::run open_database [dict create path $base]
::action::run open_game {number 1 move 1 after white}
::application::switchTab database
update
set manager $::application::database::Vars(games).twm
set path [set ::application::database::games::${manager}::Priv(table)]
::gamestable::select $path 0
::gamestable::activate $path 0
set gamebar $::application::pgn::Vars(gamebar)
set slot [::scidb::game::current]
foreach {kind id} {game c3.open_url event c5.event_url site c5.site_url} {
 tcltest::test reg5-native-external-$kind {native posted URL operation produces its real HTTP request in an owned browser process} -body {
  switch $kind {
   game {menu .reg5ext -tearoff 0;::gamestable::PopupMenu $path .reg5ext $base Normal 0 white;set m .reg5ext}
   event {::gamebar::PopupEventMenu $gamebar $slot;set m $gamebar.menu}
   site {::gamebar::PopupSiteMenu $gamebar $slot;set m $gamebar.menu}
  }
  set found [::reg5external::findRow $m $id]
  if {![llength $found]} {error "Native $kind caller did not post $id"}
  lassign $found rowMenu row
  set before [llength $::reg5external::requests]
  set command [$rowMenu entrycget $row -command]
  puts [list EXTERNAL_POSTED $id command $command state [$rowMenu entrycget $row -state]]
  if {$kind eq "event"} {
   set obj [dict get [lindex $command 2] object]
   puts [list EVENT_REFERENCE $obj info [::scidb::db::get eventInfo [dict get $obj index] [dict get $obj view] $base Normal] site [::eventtable::GetSite $base Normal [dict get $obj view] [dict get $obj index]]]
  }
  if {[lrange $command 0 1] ne [list ::action::run $id]} {error "Raw external command $command"}
  $rowMenu invoke $row
  ::scidb::test::actions::waitUntil {[llength $::reg5external::requests] > $before}
  puts [list EXTERNAL_EFFECT $id command $command requests $::reg5external::requests]
  list [expr {[llength $::reg5external::requests] == $before+1}] [lindex $::reg5external::requests end]
 } -cleanup {catch {::tk::MenuUnpost $m};catch {destroy $m}} -result {1 /generated}
}
trace remove execution ::action::run leave ::reg5external::traceRun
set ::env(PATH) $savedPath
unset -nocomplain ::auto_execs(xdg-open)
close $server
::scidb::test::actions::cleanup
::tcltest::cleanupTests
