# Real Tk game controls and real API against the loopback fake; no live calls.
package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
source [file join [file dirname [info script]] lichess_fake_server.tcl]
::scidb::test::wait::ready
namespace eval ::scidb::test::bot {
 variable Out [file normalize tests/tmp-app/lichess-hardening/E-bot]
 file mkdir $Out
}
proc ::scidb::test::bot::Browser {url} {
	::http::geturl $url -timeout 5000 -command ::scidb::test::bot::BrowserResponse
}
proc ::scidb::test::bot::BrowserResponse {h} {
	set location {}
	foreach {key val} [::http::meta $h] {
		if {[string equal -nocase $key Location]} { set location $val }
	}
	::http::cleanup $h
	if {$location ne {}} {
		# Redirects in this fixture must stay on the client's loopback server.
		if {![regexp {^http://127\.0\.0\.1:[0-9]+/\?} $location]} { error "non-loopback OAuth redirect" }
		::http::geturl $location -timeout 5000 -command ::scidb::test::bot::BrowserResponse
	}
}
proc ::scidb::test::bot::Setup {{bot 1}} {
	variable SavedBase
	variable SavedOptions
	variable Credential
	set SavedBase $::lichess::api::Base
	set SavedOptions [array get ::lichess::Options]
	set Credential {}
	foreach name {TokenStore TokenLoad TokenDelete OpenBrowser} {
		rename ::lichess::api::$name ::scidb::test::bot::Original$name
	}
	proc ::lichess::api::TokenStore {tok} { set ::scidb::test::bot::Credential $tok }
	proc ::lichess::api::TokenLoad {} { return $::scidb::test::bot::Credential }
	proc ::lichess::api::TokenDelete {} { set ::scidb::test::bot::Credential {} }
	proc ::lichess::api::OpenBrowser {url} { ::scidb::test::bot::Browser $url }
	set ::lichess::api::Base [::lichess::fake::Start]
	set ::lichess::api::BackoffUntil 0
	::lichess::fake::Set botAccount $bot
	::lichess::fake::Set autoAcceptDraw 0
	::lichess::ToggleBotMode 0
	::lichess::fake::Set pairDelay 30
	::lichess::fake::Set replyDelay 30
	::lichess::open .application
	::lichess::SignIn
	::scidb::test::wait::until {!$::lichess::Priv(signingIn)}
	if {$::lichess::Priv(state) ne "lobby"} { error "loopback sign-in failed" }
	::scidb::test::wait::until {[llength $::lichess::fake::EventStreams] > 0}
}
proc ::scidb::test::bot::Cleanup {} {
	variable SavedBase
	variable SavedOptions
	catch {::lichess::Close}
	::lichess::api::signOut
	::lichess::fake::Stop
	update
	foreach name {TokenStore TokenLoad TokenDelete OpenBrowser} {
		if {[llength [info commands ::scidb::test::bot::Original$name]]} {
			rename ::lichess::api::$name {}
			rename ::scidb::test::bot::Original$name ::lichess::api::$name
		}
	}
	set ::lichess::api::Base $SavedBase
	array set ::lichess::Options $SavedOptions
}
proc ::scidb::test::bot::Ai {color replies} {
	::lichess::fake::ScriptNextGame $replies
	set ::lichess::Priv(dlg:aiLevel) 3
	set ::lichess::Priv(dlg:aiMinutes) 5
	set ::lichess::Priv(dlg:aiIncrement) 2
	set ::lichess::Priv(dlg:aiColor) [::lichess::ColourLabel $color]
	::lichess::ChallengeAi
	::scidb::test::wait::until {$::lichess::Priv(state) eq "playing"}
	return $::lichess::Priv(gameId)
}

proc ::scidb::test::bot::Paths {} {
 lmap r [::lichess::fake::Requests] {dict get $r path}
}
proc ::scidb::test::bot::AssertPath {name script path} {
 variable Out
 ::lichess::fake::ClearRequests
 uplevel 1 $script
 ::scidb::test::wait::until {$path in [::scidb::test::bot::Paths]}
 set request [lindex [::lichess::fake::Requests] [lsearch -exact [Paths] $path]]
 set f [open [file join $Out actions.log] a]
 puts $f "$name: [dict get $request method] [dict get $request path]"
 close $f
 set other [expr {[string match /api/bot/* $path] ? "board" : "bot"}]
 if {[lsearch -glob [Paths] /api/$other/game/*] >= 0} {error "action used opposite protocol"}
 if {[string match */chat $path] && [dict get $request method] eq "POST"} {
  if {[dict get $request form] ne {room player text {Hello from bot}}} {error "incorrect chat form"}
 }
 return [dict get $request method]
}
proc ::scidb::test::bot::Button {key} {
 set w $::lichess::Priv(view)
 set button [set ::online::view::${w}::V(button:$key)]
 if {[$button instate disabled]} {error "disabled $key"}
 if {$key eq "resign"} {after 100 ::scidb::test::bot::Confirm}
 $button invoke
}
proc ::scidb::test::bot::FindYes {w} {
 if {[string match *.bt-yes $w]} {$w invoke; return 1}
 foreach child [winfo children $w] {if {[FindYes $child]} {return 1}}
 return 0
}
proc ::scidb::test::bot::Confirm {} {
 if {![FindYes .]} {after 100 ::scidb::test::bot::Confirm}
}
proc ::scidb::test::bot::Offer {id kind answer} {
 variable mode
 ::lichess::fake::OpponentOffer $id $kind
 ::scidb::test::wait::until {[set ::lichess::Priv(${kind}Offer)]}
 set bar [set ::online::view::$::lichess::Priv(view)::V(offer)]
 update
 if {![winfo ismapped $bar] || ![string length [$bar.text cget -text]]} {error "offer not visible"}
 Shot $mode-$kind-$answer-offer
 $bar.$answer invoke
}
proc ::scidb::test::bot::Shot {name} {
 variable Out
 update
 exec import -window [winfo id .online] [file join $Out $name.png]
}
namespace eval ::scidb::test::bot {
 close [open [file join $Out actions.log] w]
 foreach mode {bot board} {
  tcltest::test lichess-$mode-stream-move {account title selects protocol for real board moves and stream} -setup {
   Setup [expr {$mode eq "bot"}]
  } -body {
   set selected $::lichess::Priv(botMode)
   set id [Ai white {e7e5}]
   set stream [expr {"/api/$mode/game/stream/$id" in [Paths]}]
   set other [expr {$mode eq "bot" ? "board" : "bot"}]
   if {[lsearch -glob [Paths] /api/$other/game/*] >= 0} {error "wrong game protocol"}
   set history [expr {"/api/$mode/game/$id/chat" in [Paths]}]
   set f [open [file join $Out $mode-requests.log] w]
   foreach r [::lichess::fake::Requests] {puts $f "[dict get $r method] [dict get $r path]"}
   close $f
   AssertPath $mode-move {::lichess::UserMove e4} /api/$mode/game/$id/move/e2e4
   ::scidb::test::wait::until {$::lichess::Priv(serverMoves) eq {e2e4 e7e5} && $::lichess::Priv(pendingMove) eq ""}
   Shot $mode-game
   set f [open [file join $Out $mode-requests.log] a]
   foreach r [::lichess::fake::Requests] {puts $f "[dict get $r method] [dict get $r path]"}
   close $f
   list [expr {$selected == ($mode eq "bot")}] $stream $history
  } -cleanup {Cleanup} -result {1 1 1}
 }
 foreach mode {bot board} {
 foreach {name kind answer suffix} {
  resign {} {} resign
  abort {} {} abort
  offer-draw {} {} draw/yes
  accept-draw draw accept draw/yes
  decline-draw draw decline draw/no
  propose-takeback {} {} takeback/yes
  accept-takeback takeback accept takeback/yes
  decline-takeback takeback decline takeback/no
  send-chat {} {} chat
 } {
  tcltest::test lichess-$mode-$name {visible game action calls matching account endpoint} -setup {Setup [expr {$mode eq "bot"}]} -body {
   set id [Ai white {e7e5}]
   # Draw/takeback controls are exercised in a game with actual moves.
   if {$name ne "abort"} {
    if {![::lichess::UserMove e4]} {error "opening move rejected"}
    ::scidb::test::wait::until {$::lichess::Priv(serverMoves) eq {e2e4 e7e5} && $::lichess::Priv(pendingMove) eq ""}
   }
   switch $name {
    resign - abort {set script [list Button $name]}
    offer-draw {set script {Button draw}}
    propose-takeback {set script {Button takeback}}
    send-chat {
     set w $::lichess::Priv(view)
     set ::online::view::${w}::V(chat) {Hello from bot}
     set script [list $w.side.chat.send invoke]
    }
    default {set script [list Offer $id $kind $answer]}
   }
   set method [AssertPath $mode-$name $script /api/$mode/game/$id/$suffix]
   if {$kind ne ""} {Shot $mode-$name}
   set method
  } -cleanup {Cleanup} -result POST
 }
 }
 tcltest::test lichess-bot-upgrade {successful real upgrade enables bot stream without BOT title} -setup {Setup 0} -body {
  AssertPath upgrade {::lichess::UpgradeToBot 1} /api/bot/account/upgrade
  ::scidb::test::wait::until {$::lichess::Priv(botMode)}
  set id [Ai white {}]
  expr {"/api/bot/game/stream/$id" in [Paths]}
 } -cleanup {Cleanup} -result 1
 tcltest::test lichess-bot-account-refresh {account lookup detects BOT and clears stale bot preference for non-bot} -setup {Setup 0} -body {
  ::lichess::fake::Set botAccount 1
  ::lichess::api::account ::lichess::AccountResult
  ::scidb::test::wait::until {$::lichess::Priv(botMode)}
  ::lichess::fake::Set botAccount 0
  ::lichess::api::account ::lichess::AccountResult
  ::scidb::test::wait::until {!$::lichess::Priv(botMode)}
  set ::lichess::api::Mode
 } -cleanup {Cleanup} -result board
}
tcltest::cleanupTests
