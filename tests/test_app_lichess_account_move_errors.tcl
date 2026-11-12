# Account and move terminal-review regressions: real Tk, credential file and HTTP.
package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
source [file join [file dirname [info script]] lichess_fake_server.tcl]
::scidb::test::wait::ready
namespace eval ::scidb::test::am {
 variable Out [file normalize tests/tmp-app/lichess-hardening/T-gaps5]
 file mkdir $Out
}
proc ::scidb::test::am::Wait {condition} {uplevel 1 [list ::scidb::test::wait::until $condition 35000]}
proc ::scidb::test::am::Setup {} {
 variable Base $::lichess::api::Base
 variable SavedOptions [array get ::lichess::Options]
 variable SavedMode $::lichess::api::Mode
 ::lichess::Close
 ::lichess::api::signOut
 set ::lichess::api::Base [::lichess::fake::Start]
 set ::lichess::api::BackoffUntil 0
 set ::lichess::fake::Token [::lichess::testToken]
 ::lichess::api::TokenStore [::lichess::testToken]
 set ::lichess::Priv(username) {}
 set ::lichess::Priv(userId) {}
}
proc ::scidb::test::am::Cleanup {} {
 ::lichess::Close
 ::lichess::api::signOut
 ::lichess::fake::Stop
 array set ::lichess::Options $::scidb::test::am::SavedOptions
 ::lichess::ToggleBotMode $::lichess::Options(botMode)
 set ::lichess::api::Mode $::scidb::test::am::SavedMode
 set ::lichess::api::Base $::scidb::test::am::Base
 update
}
proc ::scidb::test::am::Assert {condition} {
 if {![uplevel 1 [list expr $condition]]} {error "Assertion failed: $condition"}
}
proc ::scidb::test::am::Shot {name} {
 update
 exec import -window [winfo id .online] [file join $::scidb::test::am::Out $name.png]
}
proc ::scidb::test::am::Refuse {} {
 set s [socket -server {apply {{args} {}}} -myaddr 127.0.0.1 0]
 set port [lindex [fconfigure $s -sockname] 2]
 close $s
 set ::lichess::api::Base http://127.0.0.1:$port
}
namespace eval ::scidb::test::am {
foreach entry {startup signin} {
 foreach failure {503 429 refused stall 401} {
  tcltest::test account-$entry-$failure {account failure preserves credential and visible Retry except 401} -setup {
   Setup
  } -body {
   if {$entry eq "signin"} {
    # Start at the personal-token sign-in view while a credential is stored.
    ::lichess::api::TokenDelete
    ::lichess::open .application
    ::lichess::api::TokenStore [::lichess::testToken]
   }
   switch $failure {
    refused {Refuse}
    stall {::lichess::fake::Control /api/account stall}
    default {::lichess::fake::ForceNext /api/account $failure 0}
   }
   if {$entry eq "startup"} {
    ::lichess::open .application
   } else {
    set ::lichess::Priv(dlg:token) [::lichess::testToken]
    ::lichess::UseToken
   }
   Wait {$::lichess::Priv(statusText) ne $::lichess::mc::LoadingAccount && !$::lichess::Priv(signingIn) && [dict size $::lichess::api::Requests] == 0}
   if {$failure eq "401"} {
    Assert {![file exists [::lichess::api::TokenFile]] && $::lichess::Priv(state) eq "offline"}
    Assert {$::lichess::Priv(statusText) eq $::lichess::mc::SessionExpired}
   } else {
    set expected [expr {$failure eq "503" ? "Lichess server error (503)" : $failure eq "429" ? "Lichess rate limit reached. Please wait 0 seconds." : $::lichess::api::mc::Network}]
    Assert {[file exists [::lichess::api::TokenFile]] && [::lichess::api::signedIn?]}
    Assert {$::lichess::Priv(statusText) eq $expected}
    set button $::lichess::Priv(widget:ok)
    update
    Assert {[winfo ismapped $button] && [$button cget -text] eq $::lichess::api::mc::Retry}
    set label $::lichess::Priv(widget:status)
    Assert {[$label cget -text] eq $expected && [winfo ismapped $label]}
    Assert {[winfo height $label] >= [winfo reqheight $label]}
    Assert {[winfo y $label] + [winfo height $label] <= [winfo height [winfo parent $label]]}
    puts "account $entry $failure: failure=<$expected> credential-retained=1 Retry-visible=1"
    Shot account-$entry-$failure
    ::lichess::fake::ClearControl /api/account
    set ::lichess::api::Base [::lichess::fake::Base]
    $button invoke
    Wait {$::lichess::Priv(username) ne "" && [llength $::lichess::fake::EventStreams] == 1}
    Assert {[$button cget -text] eq $::lichess::mc::Seek && [file exists [::lichess::api::TokenFile]]}
   }
   puts "account $entry $failure: status=<$::lichess::Priv(statusText)> credential=[file exists [::lichess::api::TokenFile]]"
   return ok
  } -cleanup {Cleanup} -result ok
 }
}
foreach bot {0 1} {
 foreach failure {503 refused 429 400 401} {
  tcltest::test move-$bot-$failure {board and bot move rollback keeps classified visible status} -setup {
   Setup
  } -body {
   ::lichess::fake::Set botAccount $bot
   ::lichess::open .application
   Wait {[llength $::lichess::fake::EventStreams] == 1}
   set id [::lichess::fake::CreateGame white ai 1 600 0]
   ::lichess::fake::AnnounceGame $id
   Wait {$::lichess::Priv(state) eq "playing"}
   set fen [::online::view::fen $::lichess::Priv(view)]
   set mode [expr {$bot ? "bot" : "board"}]
   if {$failure eq "refused"} {Refuse} else {::lichess::fake::ForceNext /api/$mode/game/$id/move/e2e4 $failure 0}
   ::lichess::UserMove e4
   Wait {$::lichess::Priv(pendingMove) eq ""}
   if {$failure eq "401"} {
    Assert {$::lichess::Priv(state) eq "offline" && ![file exists [::lichess::api::TokenFile]]}
   } else {
    set expected [expr {$failure eq "503" ? "Lichess server error (503); the move was taken back." : $failure eq "429" ? "Lichess rate limit reached. Please wait 0 seconds; the move was taken back." : $failure eq "400" ? "Lichess rejected e2e4; the move was taken back." : "[string trimright $::lichess::api::mc::Network .]; the move was taken back."}]
    Assert {$::lichess::Priv(statusText) eq $expected}
    set status [set ::online::view::$::lichess::Priv(view)::V(status)]
    Assert {[$status cget -text] eq $expected && [winfo ismapped $status]}
    Assert {[::online::view::fen $::lichess::Priv(view)] eq $fen && [::lichess::BoardPly] == 0}
    Shot move-$mode-$failure
    if {$failure ne "refused"} {
     set hits [lmap r [::lichess::fake::Requests] {dict get $r path}]
     Assert {[llength [lsearch -all -exact $hits /api/$mode/game/$id/move/e2e4]] == 1}
    }
   }
   puts "move $mode $failure: status=<$::lichess::Priv(statusText)>"
   return ok
  } -cleanup {Cleanup} -result ok
 }
}
foreach value {0 {Wed, 21 Oct 2015 07:28:00 GMT}} {
 tcltest::test immediate-retry-$value {zero or past date allows immediate exactly-once queued request} -setup {Setup} -body {
  ::lichess::fake::ForceNext /api/tv/channels 429 $value
  unset -nocomplain reply queued
  ::lichess::api::tvChannels {set ::scidb::test::am::reply}
  Wait {[info exists reply]}
  Assert {$::lichess::api::BackoffUntil <= [clock milliseconds]}
  set now [clock milliseconds]
  ::lichess::api::user alice {set ::scidb::test::am::queued}
  Wait {[info exists queued]}
  set elapsed [expr {[clock milliseconds]-$now}]
  Assert {$elapsed < 750 && [dict get $queued ok]}
  set hits [lmap r [::lichess::fake::Requests] {dict get $r path}]
  Assert {[llength [lsearch -all -exact $hits /api/user/alice]] == 1}
  puts "Retry-After <$value>: immediate queued delivery ${elapsed}ms"
  return ok
 } -cleanup {Cleanup} -result ok
}
}
tcltest::cleanupTests
