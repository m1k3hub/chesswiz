# Classified HTTP replies must survive OAuth and final stream callbacks.
package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
source [file join [file dirname [info script]] lichess_fake_server.tcl]
::scidb::test::wait::ready
namespace eval ::scidb::test::classify {
 variable Out [file normalize tests/tmp-app/lichess-hardening/T-classify]
 file mkdir $Out
}
proc ::scidb::test::classify::Wait {condition} {uplevel 1 [list ::scidb::test::wait::until $condition 8000]}
proc ::scidb::test::classify::Assert {condition} {
 if {![uplevel 1 [list expr $condition]]} {error "Assertion failed: $condition"}
}
proc ::scidb::test::classify::Refuse {} {
 set s [socket -server {apply {{args} {}}} -myaddr 127.0.0.1 0]
 set port [lindex [fconfigure $s -sockname] 2]
 close $s
 set ::lichess::api::Base http://127.0.0.1:$port
}
proc ::scidb::test::classify::Setup {} {
 variable Base $::lichess::api::Base
 variable SavedOptions [array get ::lichess::Options]
 variable SavedMode $::lichess::api::Mode
 variable Failure {}
 ::lichess::Close
 ::lichess::api::signOut
 set ::lichess::api::Base [::lichess::fake::Start]
 set ::lichess::api::BackoffUntil 0
 set ::lichess::fake::Token [::lichess::testToken]
 set ::lichess::Priv(username) {}
 set ::lichess::Priv(userId) {}
 rename ::lichess::api::OpenBrowser ::lichess::api::OpenBrowserBeforeClassify
 proc ::lichess::api::OpenBrowser {url} {::scidb::test::classify::Browser $url}
}
proc ::scidb::test::classify::Cleanup {} {
 ::lichess::Close
 ::lichess::api::signOut
 ::lichess::fake::Stop
 rename ::lichess::api::OpenBrowser {}
 rename ::lichess::api::OpenBrowserBeforeClassify ::lichess::api::OpenBrowser
 array set ::lichess::Options $::scidb::test::classify::SavedOptions
 ::lichess::ToggleBotMode $::lichess::Options(botMode)
 set ::lichess::api::Mode $::scidb::test::classify::SavedMode
 set ::lichess::api::Base $::scidb::test::classify::Base
 set ::lichess::api::BackoffUntil 0
 update
}
proc ::scidb::test::classify::Browser {url} {
 Assert {[string match http://127.0.0.1:* $url]}
 ::http::geturl $url -timeout 5000 -command ::scidb::test::classify::BrowserResponse
}
proc ::scidb::test::classify::BrowserResponse {h} {
 set location {}
 foreach {key val} [::http::meta $h] {if {[string equal -nocase $key Location]} {set location $val}}
 ::http::cleanup $h
 if {$location ne {}} {
  Assert {[regexp {^http://127\.0\.0\.1:[0-9]+/\?} $location]}
  if {$::scidb::test::classify::Failure eq "refused"} {Refuse}
  ::http::geturl $location -timeout 5000 -command ::scidb::test::classify::BrowserResponse
 }
}
proc ::scidb::test::classify::Expected {failure} {
 switch $failure {
  503 {return [format $::lichess::api::mc::Server 503]}
  429 {return [format $::lichess::api::mc::Limited 0]}
  refused {return $::lichess::api::mc::Network}
  default {return $::lichess::api::mc::SignIn}
 }
}
proc ::scidb::test::classify::Visible {expected name} {
 Assert {$::lichess::Priv(statusText) eq $expected}
 update
 set label $::lichess::Priv(widget:status)
 Assert {[$label cget -text] eq $expected}
 if {[::lichess::ViewExists]} {
  set label [set ::online::view::$::lichess::Priv(view)::V(status)]
 }
 Assert {[winfo ismapped $label] && [$label cget -text] eq $expected}
 exec import -window [winfo id .online] [file join $::scidb::test::classify::Out $name.png]
 puts "$name: <$expected>"
}
proc ::scidb::test::classify::Closed {callback response} {
 set ::scidb::test::classify::reply $response
 dict set response type closed
 {*}$callback $response
}
# The real OAuth browser redirect and POST are used, including credential-free
# 401 exchange failures (which must not be treated as session revocation).
namespace eval ::scidb::test::classify {
foreach failure {503 429 refused 400 401} {
 tcltest::test classify-oauth-$failure {OAuth exchange keeps transport classification and sign-in rejection text} -setup {Setup} -body {
  set Failure $failure
  if {$failure ne "refused"} {::lichess::fake::ForceNext /api/token $failure 0}
  ::lichess::open .application
  ::lichess::SignIn
  Wait {!$::lichess::Priv(signingIn) && $::lichess::Priv(statusText) eq [Expected $failure]}
  Visible [Expected $failure] oauth-$failure
  Assert {$::lichess::Priv(state) eq "offline" && ![::lichess::api::signedIn?] && $::lichess::api::Auth eq {}}
  if {$failure ne "refused"} {
   set hits 0
   foreach r [::lichess::fake::Requests] {if {[dict get $r path] eq "/api/token"} {incr hits; Assert {[dict get $r method] eq "POST"}}}
   Assert {$hits == 1}
  }
  return ok
 } -cleanup {Cleanup} -result ok
}
foreach kind {event game} {
 foreach failure {503 429 refused} {
  tcltest::test classify-$kind-$failure {final closed callback retains a real classified HTTP failure} -setup {Setup} -body {
   ::lichess::api::TokenStore [::lichess::testToken]
   ::lichess::open .application
   Wait {[llength $::lichess::fake::EventStreams] == 1}
   if {$kind eq "game"} {
    set id [::lichess::fake::CreateGame white ai 1 600 0]
    ::lichess::fake::AnnounceGame $id
    Wait {$::lichess::Priv(state) eq "playing"}
    set path /api/board/game/stream/$id
    set callback [list ::lichess::OnGame $::lichess::Priv(gameGen)]
   } else {
    set path /api/stream/event
    set callback ::lichess::OnEvent
   }
   if {$failure eq "refused"} {Refuse} else {::lichess::fake::ForceNext $path $failure 0}
   unset -nocomplain reply
   # 429 terminates actual streams. 5xx/network currently retain handles for
   # recovery, so send their real HTTP reply through the final callback too.
   set stream [expr {$failure eq "429"}]
   ::lichess::api::Request GET $path {} [list ::scidb::test::classify::Closed $callback] $stream
   Wait {[info exists reply]}
   Assert {![dict get $reply ok] && [dict get $reply error] eq [Expected $failure]}
   Visible [Expected $failure] $kind-$failure
   Assert {[::lichess::api::signedIn?]}
   return ok
  } -cleanup {Cleanup} -result ok
 }
 foreach terminal {eof missing-error stale-generation unauthorized} {
  tcltest::test classify-$kind-$terminal {ordinary close fallback, generation and 401 guards remain intact} -setup {Setup} -body {
   ::lichess::api::TokenStore [::lichess::testToken]
   ::lichess::open .application
   Wait {[llength $::lichess::fake::EventStreams] == 1}
   if {$kind eq "game"} {
    set id [::lichess::fake::CreateGame white ai 1 600 0]
    ::lichess::fake::AnnounceGame $id
    Wait {$::lichess::Priv(state) eq "playing"}
    set callback [list ::lichess::OnGame $::lichess::Priv(gameGen)]
    set expected $::lichess::mc::GameStreamClosed
   } else {set callback ::lichess::OnEvent; set expected $::lichess::mc::EventStreamClosed}
   set event [dict create type closed]
   switch $terminal {
    eof {dict set event ok 1; dict set event error $::lichess::api::mc::Closed}
    stale-generation {
     if {$kind eq "game"} {lset callback 1 [expr {$::lichess::Priv(gameGen)-1}]; set expected $::lichess::Priv(statusText)}
    }
    unauthorized {dict set event status 401; dict set event authenticated 1; set expected $::lichess::mc::SessionExpired}
   }
   {*}$callback $event
   Assert {$::lichess::Priv(statusText) eq $expected}
   if {$terminal eq "unauthorized"} {Assert {![::lichess::api::signedIn?] && $::lichess::Priv(state) eq "offline"}}
   return ok
  } -cleanup {Cleanup} -result ok
 }
}
}
tcltest::cleanupTests
