# Reviewer customRound7 scenario, plus same-HOME seed/restore regression.
package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
source [file join [file dirname [info script]] lichess_fake_server.tcl]
::scidb::test::wait::ready
namespace eval ::scidb::test::broadcastPersist {
 variable base $::lichess::api::Base
 variable saved $::lichess::Options(broadcastRound)
 variable phase [expr {[info exists ::env(CW_BROADCAST_PHASE)] ? $::env(CW_BROADCAST_PHASE) : "seed"}]
}
namespace eval ::scidb::test::broadcastPersist {
proc Wait {condition} {uplevel 1 [list ::scidb::test::wait::until $condition]}
proc Paths {} {lmap r [::lichess::fake::Requests] {dict get $r path}}
proc Entry {} {
 return [$::lichess::tv::Priv(widget:top).left.broadcasts.form.rentry get]
}
proc Shot {name} {
 if {[info exists ::env(CW_BROADCAST_EVIDENCE)]} {
  update
  exec import -window [winfo id .online] [file join $::env(CW_BROADCAST_EVIDENCE) $name.png]
 }
}
proc Save {} {
 ::options::startTransaction
 ::options::saveOptionsFile
 ::options::endTransaction
}
::lichess::api::signOut
set ::lichess::api::Base [::lichess::fake::Start]
set ::lichess::api::BackoffUntil 0
set ::lichess::fake::Token [::lichess::testToken]
::lichess::api::TokenStore [::lichess::testToken]
if {$phase eq "restore"} {
 tcltest::test broadcast-custom-restart {startup refresh retains saved off-list round without opening a stream} -body {
  set loaded $::lichess::Options(broadcastRound)
  ::lichess::tv::open
  Wait {[dict size $::lichess::api::Requests] == 0}
  update
  puts "Restart: loaded=$loaded saved=$::lichess::Options(broadcastRound) entry=$::lichess::tv::Priv(roundId)"
  Shot restart-preselection
  list $loaded $::lichess::Options(broadcastRound) [Entry] \
   [$::lichess::tv::Priv(widget:broadcasts) selection] \
   [lsearch -all -inline -glob [Paths] */stream/*]
 } -result {customRound7 customRound7 customRound7 {} {}}
} else {
 tcltest::test broadcast-custom-refresh {following an off-list round survives top-list refresh with the same stream} -body {
  set ::lichess::Options(broadcastRound) {}
  ::lichess::tv::open
  Wait {[dict size $::lichess::api::Requests] == 0}
  ::lichess::tv::FollowBroadcastRound customRound7
  Wait {[llength [lsearch -all -exact [Paths] /api/stream/broadcast/round/customRound7.pgn]] == 1}
  set handle $::lichess::tv::Priv(streamHandle)
  puts "Before refresh: saved=$::lichess::Options(broadcastRound) entry=$::lichess::tv::Priv(roundId)"
  ::lichess::tv::RefreshBroadcasts
  Wait {[dict size $::lichess::api::Requests] == 1}
  update
  puts "After refresh: saved=$::lichess::Options(broadcastRound) entry=$::lichess::tv::Priv(roundId)"
  Shot custom-refresh
  list $::lichess::Options(broadcastRound) [Entry] \
   [expr {$handle eq $::lichess::tv::Priv(streamHandle)}] \
   [dict get $::lichess::api::Requests $handle url] \
   [llength [lsearch -all -exact [Paths] /api/stream/broadcast/round/customRound7.pgn]]
 } -match glob -result {customRound7 customRound7 1 http://127.0.0.1:*/api/stream/broadcast/round/customRound7.pgn 1}
 tcltest::test broadcast-custom-empty-list {an empty top list preserves an off-list saved round} -body {
  ::lichess::fake::Set dropBroadcastRound round1
  ::lichess::tv::RefreshBroadcasts
  Wait {[dict size $::lichess::api::Requests] == 1}
  list $::lichess::Options(broadcastRound) [Entry] \
   [$::lichess::tv::Priv(widget:broadcasts) children {}]
 } -result {customRound7 customRound7 {}}
 tcltest::test broadcast-custom-explicit-follow {only following a different round replaces the saved round} -body {
  ::lichess::tv::FollowBroadcastRound anotherRound8
  Wait {"/api/stream/broadcast/round/anotherRound8.pgn" in [Paths]}
  list $::lichess::Options(broadcastRound) [Entry]
 } -result {anotherRound8 anotherRound8}
 tcltest::test broadcast-empty-fallback {empty saved option selects the first available round without streaming} -body {
  ::lichess::tv::StopStream
  set ::lichess::Options(broadcastRound) {}
  ::lichess::fake::Set dropBroadcastRound {}
  ::lichess::tv::RefreshBroadcasts
  Wait {[dict size $::lichess::api::Requests] == 0}
  list $::lichess::Options(broadcastRound) [Entry] \
   [$::lichess::tv::Priv(widget:broadcasts) selection] $::lichess::tv::Priv(streamHandle)
 } -result {round1 round1 round1 {}}
 # Leave an actual followed custom round in the options file for process two.
 ::lichess::tv::FollowBroadcastRound customRound7
 Wait {"/api/stream/broadcast/round/customRound7.pgn" in [Paths]}
 ::lichess::tv::StopStream
 Save
}
::lichess::tv::StopStream
catch {::online::window::closeTab lichess-tv}
::lichess::api::signOut
::lichess::fake::Stop
set ::lichess::api::Base $base
# Restore in-memory state for the combined runner; seed remains on disk.
set ::lichess::Options(broadcastRound) $saved
}
tcltest::cleanupTests
