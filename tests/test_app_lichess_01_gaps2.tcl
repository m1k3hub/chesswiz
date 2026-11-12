# Startup/reopen regressions use real Tk controls and loopback HTTP only.
package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
source [file join [file dirname [info script]] lichess_fake_server.tcl]
::scidb::test::wait::ready
namespace eval ::scidb::test::gaps2 {
 variable Out [file normalize tests/tmp-app/lichess-hardening/T-gaps2]
 file mkdir $Out
 proc Wait {condition} {uplevel 1 [list ::scidb::test::wait::until $condition 10000]}
 proc Pause {ms} {after $ms [list set ::scidb::test::gaps2::tick 1]; vwait ::scidb::test::gaps2::tick}
 proc PlayingChanged {args} {lappend ::scidb::test::gaps2::PlayingStates $::lichess::Priv(playingText)}
 proc Setup {{stored 1}} {
  variable SavedBase $::lichess::api::Base
  variable SavedOptions [array get ::lichess::Options]
  variable Credential {}
  ::lichess::Close
  ::lichess::api::signOut
  foreach name {TokenLoad TokenStore TokenDelete} {rename ::lichess::api::$name [namespace current]::Original$name}
  proc ::lichess::api::TokenLoad {} {return $::scidb::test::gaps2::Credential}
  proc ::lichess::api::TokenStore {token} {set ::scidb::test::gaps2::Credential $token}
  proc ::lichess::api::TokenDelete {} {set ::scidb::test::gaps2::Credential {}}
  set ::lichess::api::Base [::lichess::fake::Start]
  set ::lichess::api::BackoffUntil 0
  set ::lichess::fake::Token [::lichess::testToken]
  if {$stored} {::lichess::api::TokenStore [::lichess::testToken]}
  set ::lichess::Options(botMode) 0
  ::lichess::ToggleBotMode 0
  set ::scidb::test::gaps2::PlayingStates {}
  trace add variable ::lichess::Priv(playingText) write ::scidb::test::gaps2::PlayingChanged
 }
 proc Cleanup {} {
  trace remove variable ::lichess::Priv(playingText) write ::scidb::test::gaps2::PlayingChanged
  ::lichess::Close
  ::lichess::api::signOut
  ::lichess::fake::Stop
  update
  if {[llength [info commands ::lichess::fake::Gaps2Handle]]} {
   rename ::lichess::fake::Handle {}
   rename ::lichess::fake::Gaps2Handle ::lichess::fake::Handle
  }
  foreach name {TokenLoad TokenStore TokenDelete} {
   rename ::lichess::api::$name {}
   rename [namespace current]::Original$name ::lichess::api::$name
  }
  set ::lichess::api::Base $::scidb::test::gaps2::SavedBase
  array set ::lichess::Options $::scidb::test::gaps2::SavedOptions
  ::lichess::ToggleBotMode $::lichess::Options(botMode)
 }
 proc Shot {name} {
  update
  exec import -window [winfo id .online] [file join $::scidb::test::gaps2::Out $name.png]
 }
 proc Journal {name} {
  set f [open [file join $::scidb::test::gaps2::Out $name.log] w]
  foreach r [::lichess::fake::Requests] {puts $f "[dict get $r method] [dict get $r path]"}
  dict for {id r} $::lichess::api::Requests {puts $f "$id [dict get $r url]"}
  close $f
 }
 proc EventCount {} {
  set n 0
  dict for {id r} $::lichess::api::Requests {if {[string match */api/stream/event [dict get $r url]]} {incr n}}
  return $n
 }
 proc DelayAccount {} {
  rename ::lichess::fake::Handle ::lichess::fake::Gaps2Handle
  proc ::lichess::fake::Handle {ch} {
   if {[dict get $::lichess::fake::Connections $ch target] eq "/api/account"} {
    ::lichess::fake::Later 500 [list ::lichess::fake::Gaps2Handle $ch]
   } else {::lichess::fake::Gaps2Handle $ch}
  }
 }
}
namespace eval ::scidb::test::gaps2 {
 tcltest::test gaps2-reopen {WM close and two reopens restore exactly one event stream and playable AI game} -setup {Setup} -body {
  ::lichess::open .application
  Wait {[llength $::lichess::fake::EventStreams] == 1}
  set counts {}
  for {set cycle 1} {$cycle <= 2} {incr cycle} {
   uplevel #0 [wm protocol .online WM_DELETE_WINDOW]
   Wait {[llength $::lichess::fake::EventStreams] == 0}
   if {[dict size $::lichess::api::Requests]} {error "requests survived close"}
   ::lichess::open .application
   Wait {[llength $::lichess::fake::EventStreams] == 1}
   lappend counts [EventCount]
   Journal reopen-$cycle
   $::lichess::Priv(widget:lobby).ai.play invoke
   Wait {$::lichess::Priv(active) && $::lichess::Priv(state) eq "playing"}
   ::lichess::UserMove e4
   Wait {[lindex $::lichess::Priv(serverMoves) 0] eq "e2e4"}
   update
   if {![winfo ismapped $::lichess::Priv(view)]} {error "game tab not shown"}
   Journal reopen-$cycle-game
   Shot reopen-$cycle-game
   if {[EventCount] != 1 || [llength $::lichess::fake::EventStreams] != 1} {error "duplicate stream"}
  }
  set counts
 } -cleanup {Cleanup} -result {1 1}
 tcltest::test gaps2-hide-pending-account {late account reply cannot reopen streams while Online is hidden} -setup {Setup} -body {
  DelayAccount
  ::lichess::open .application
  Pause 150
  uplevel #0 [wm protocol .online WM_DELETE_WINDOW]
  Pause 600
  set hidden [list [EventCount] [llength $::lichess::fake::EventStreams]]
  ::lichess::open .application
  Wait {[llength $::lichess::fake::EventStreams] == 1}
  list $hidden [EventCount]
 } -cleanup {Cleanup} -result {{0 0} 1}
 tcltest::test gaps2-bot-race {queued gameStart with delayed BOT account never uses board game API} -setup {Setup} -body {
  ::lichess::fake::Set botAccount 1
  set id [::lichess::fake::CreateGame white lobby 0 600 0]
  ::lichess::fake::AnnounceGame $id
  DelayAccount
  ::lichess::open .application
  Pause 150
  if {[EventCount] || $::lichess::Priv(active)} {error "events started before account resolved"}
  Wait {$::lichess::Priv(active) && $::lichess::Priv(botMode)}
  ::lichess::UserMove e4
  Wait {[lindex $::lichess::Priv(serverMoves) 0] eq "e2e4"}
  ::lichess::SendChat {Hello from bot}
  Wait {[list POST /api/bot/game/$id/chat] in [lmap r [::lichess::fake::Requests] {list [dict get $r method] [dict get $r path]}]}
  set paths [lmap r [::lichess::fake::Requests] {dict get $r path}]
  Journal bot-race
  Shot bot-race
  list [expr {"/api/bot/game/stream/$id" in $paths}] [expr {"/api/bot/game/$id/move/e2e4" in $paths}] [expr {[lsearch -glob $paths /api/board/game/*] == -1}] $::lichess::Priv(gameBot)
 } -cleanup {Cleanup} -result {1 1 1 1}
 foreach stored {0 1} {
  foreach populated {0 1} {
   tcltest::test gaps2-playing-$stored-$populated {stored sign-in and token sign-in automatically load empty or populated playing list} -setup {Setup $stored} -body {
    set expected $::lichess::mc::NoPlaying
    if {$populated} {set expected [::lichess::fake::CreateGame white lobby 0 600 0]}
    ::lichess::open .application
    if {!$stored} {
     set ::lichess::Priv(dlg:token) [::lichess::testToken]
     $::lichess::Priv(widget:signin).useToken invoke
    }
    Wait {$::lichess::Priv(state) eq "lobby" && !$::lichess::Priv(signingIn)}
    set initial $::lichess::Priv(playingText)
    if {$initial eq {}} {error "blank playing panel after sign-in"}
    Wait {$::lichess::Priv(playingText) eq $expected}
    if {$::lichess::mc::LoadingList ni $::scidb::test::gaps2::PlayingStates} {error "loading state never displayed"}
    update
    if {![winfo ismapped $::lichess::Priv(widget:lobby).playing.list]} {error "playing label hidden"}
    Journal playing-$stored-$populated
    Shot playing-$stored-$populated
    expr {$initial eq $::lichess::mc::LoadingList || $initial eq $expected}
   } -cleanup {Cleanup} -result 1
  }
 }
}
tcltest::cleanupTests
