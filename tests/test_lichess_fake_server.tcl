# VAL-LICHESS-FAKE-001: real loopback transport through ::lichess::api.
# Standalone: tclsh tests/test_lichess_fake_server.tcl -verbose bpse
package require tcltest 2.5
if {[catch {package require json}]} {
	foreach dir [glob -nocomplain /usr/share/tcltk/tcllib*] { lappend auto_path $dir }
	package require json
}
if {![llength [info commands ::lichess::api::Request]]} {
	source [file join [file dirname [info script]] .. tcl lichess-api.tcl]
}
source [file join [file dirname [info script]] lichess_fake_server.tcl]
namespace eval ::lichess::faketest { variable Replies {}; variable Events {} }
namespace eval ::lichess::faketest {
	proc Wait {condition} {
		set deadline [expr {[clock milliseconds] + 3000}]
		while {![uplevel 1 [list expr $condition]]} {
			if {[clock milliseconds] >= $deadline} { error "fake-server test timed out: $condition" }
			after 5 [list set [namespace current]::tick 1]
			vwait [namespace current]::tick
		}
	}
	proc Check {actual expected} {
		if {$actual ne $expected} { error "expected <$expected>, got <$actual>" }
	}
	proc Reply {r} { lappend ::lichess::faketest::Replies $r }
	proc Event {e} { lappend ::lichess::faketest::Events $e }
	proc SignIn {} {
		# Keep the server's accepted token separate from the client's store:
		# an authenticated 401 must clear only the client credential.
		set ::lichess::fake::Token loopback-only-fixture
		::lichess::api::TokenStore $::lichess::fake::Token
		Check [::lichess::api::signedIn?] 1
	}
	proc Start {} {
		variable Replies {}; variable Events {}
		variable Credential {}
		variable SavedBase $::lichess::api::Base
		variable SavedMode $::lichess::api::Mode
		foreach name {TokenLoad TokenStore TokenDelete} {
			rename ::lichess::api::$name [namespace current]::Original$name
		}
		proc ::lichess::api::TokenLoad {} { return $::lichess::faketest::Credential }
		proc ::lichess::api::TokenStore {token} { set ::lichess::faketest::Credential $token }
		proc ::lichess::api::TokenDelete {} { set ::lichess::faketest::Credential {} }
		set ::lichess::api::Base [::lichess::fake::Start]
		SignIn
		set ::lichess::api::BackoffUntil 0
		::lichess::api::mode board
	}
	proc Stop {} {
		::lichess::api::signOut
		update
		::lichess::fake::Stop
		foreach name {TokenLoad TokenStore TokenDelete} {
			rename ::lichess::api::$name {}
			rename [namespace current]::Original$name ::lichess::api::$name
		}
		set ::lichess::api::Base $::lichess::faketest::SavedBase
		::lichess::api::mode $::lichess::faketest::SavedMode
		set ::lichess::api::BackoffUntil 0
	}
	proc Call {method path {form {}} {shape json}} {
		variable Replies {}
		::lichess::api::Request $method $path $form [namespace current]::Reply 0 {} application/x-www-form-urlencoded $shape
		Wait {[llength $Replies] == 1}
		return [lindex $Replies 0]
	}
	proc Data {path {shape json}} {
		set r [Call GET $path {} $shape]
		Check [dict get $r ok] 1
		return [dict get $r data]
	}
	proc Stream {path} {
		variable Events {}
		set h [::lichess::api::Request GET $path {} [namespace current]::Event 1]
		Wait {[llength [::lichess::fake::Requests]] > 0}
		return $h
	}
	proc Pause {} { after 100 [list set [namespace current]::tick 1]; vwait [namespace current]::tick }

	tcltest::test fake-account-bot {bot account control adds and removes BOT title} -setup Start -body {
		Check [dict exists [Data /api/account] title] 0
		::lichess::fake::Set botAccount 1
		Check [dict get [Data /api/account] title] BOT
		::lichess::fake::Set botAccount 0
		Check [dict exists [Data /api/account] title] 0
		set result ok
	} -cleanup Stop -result ok

	foreach family {board bot} {
		tcltest::test fake-chat-$family {GET history and POST chat; original family in request and close journals} -setup Start -body {
			set id [::lichess::fake::CreateGame white lobby 0 600 0]
			set h [Stream /api/$family/game/stream/$id]
			Wait {[llength $Events] == 1}
			set path /api/$family/game/$id/chat
			Check [dict get [lindex [Data $path array] 0] text] {Good luck!}
			Check [dict get [Call POST $path [::http::formatQuery room player text {Hi é & ?}]] data ok] true
			Wait {[llength $Events] == 2}
			Check [dict get [lindex $Events end] text] {Hi é & ?}
			Check [dict get [lindex $Events end] room] player
			Check [dict get [lindex [::lichess::fake::Requests] end] path] $path
			Check [dict get [lindex [::lichess::fake::Closes] end] path] $path
			::lichess::api::close $h
			Wait {[llength [::lichess::fake::Closes]] == 3}
			Check [dict get [lindex [::lichess::fake::Closes] end] path] /api/$family/game/stream/$id
			Check [dict get [lindex [::lichess::fake::Closes] end] reason] eof
			set requestIds [lmap r [::lichess::fake::Requests] { dict get $r id }]
			set closeIds [lmap c [::lichess::fake::Closes] { dict get $c id }]
			Check [lsort $requestIds] [lsort -unique $closeIds]
			set result ok
		} -cleanup Stop -result ok
		foreach color {white black} {
			tcltest::test fake-offers-$family-$color {opponent draw and takeback flags reach game stream; takeback endpoints respond} -setup Start -body {
				set id [::lichess::fake::CreateGame $color lobby 0 600 0]
				set h [Stream /api/$family/game/stream/$id]
				Wait {[llength $Events] == 1}
				Check [dict get [lindex $Events 0] type] gameFull
				set side [expr {$color eq "white" ? "b" : "w"}]
				foreach kind {draw takeback} {
					foreach offered {1 0} {
						set count [llength $Events]
						::lichess::fake::OpponentOffer $id $kind $offered
						Wait {[llength $Events] == $count+1}
						set state [lindex $Events end]
						Check [dict get $state type] gameState
						Check [::lichess::fake::DictGet $state $side$kind false] [expr {$offered ? "true" : "false"}]
					}
				}
				foreach answer {yes no} {
					Check [dict get [Call POST /api/$family/game/$id/takeback/$answer] data ok] true
				}
				set result ok
			} -cleanup Stop -result ok
		}
	}

	tcltest::test fake-challenges {list, create and all challenge actions through API} -setup Start -body {
		Check [dict get [lindex [dict get [Data /api/challenge] in] 0] challenger id] ada
		Check [dict get [lindex [dict get [Data /api/challenge] out] 0] id] challenge1
		Check [dict get [Call POST /api/challenge/Alice [::http::formatQuery rated false clock.limit 600 clock.increment 0]] data id] challenge1
		foreach action {accept decline cancel} {
			Check [dict get [Call POST /api/challenge/challenge1/$action] data ok] true
		}
		set result ok
	} -cleanup Stop -result ok

	tcltest::test fake-playing {active games have documented fields; finished games disappear} -setup Start -body {
		Check [dict get [Data /api/account/playing] nowPlaying] {}
		set id [::lichess::fake::CreateGame white lobby 0 600 2]
		set game [lindex [dict get [Data /api/account/playing] nowPlaying] 0]
		Check [dict get $game gameId] $id
		Check [dict get $game opponent id] ada
		Check [dict get $game secondsLeft] 600
		Check [dict get $game variant key] standard
		Check [dict get $game hasMoved] false
		Check [dict get [Data /api/account/playing] nbMyTurn] 1
		Check [dict get $game isMyTurn] true
		::lichess::fake::Finish $id resign black
		Check [dict get [Data /api/account/playing] nowPlaying] {}
		set result ok
	} -cleanup Stop -result ok

	tcltest::test fake-tv-feed {channel NDJSON includes featured event and live clock update} -setup Start -body {
		set h [Stream /api/tv/best/feed]
		Wait {[llength $Events] == 1}
		Check [dict get [lindex $Events 0] t] featured
		Check [dict get [lindex $Events 0] d id] tv1
		::lichess::fake::EmitTv [dict create t fen d [dict create fen startpos lm e2e4 wc 60 bc 59]]
		Wait {[llength $Events] == 2}
		Check [dict get [lindex $Events end] d wc] 60
		set result ok
	} -cleanup Stop -result ok

	tcltest::test fake-storm {Storm fixture served via puzzleNext; normal fixture restored} -setup Start -body {
		::lichess::fake::Set stormPuzzle 1
		set p [Data /api/puzzle/next]
		Check [dict get $p puzzle id] storm1
		Check [dict get $p puzzle solution] {e2e4 e7e5}
		Check [dict get $p puzzle rating] 800
		Check [dict get $p game pgn] {1. e4 e5 *}
		::lichess::fake::Set stormPuzzle 0
		Check [dict get [Data /api/puzzle/next] puzzle id] puzzle1
		set result ok
	} -cleanup Stop -result ok

	tcltest::test fake-drop-listings {TV channel and broadcast round can disappear and return} -setup Start -body {
		Check [dict get [Data /api/tv/channels] Best gameId] tv1
		Check [dict get [lindex [dict get [Data /api/broadcast/top] active] 0] round id] round1
		::lichess::fake::Set dropTvChannel Best
		::lichess::fake::Set dropBroadcastRound round1
		Check [Data /api/tv/channels] {}
		Check [dict get [Data /api/broadcast/top] active] {}
		::lichess::fake::Set dropTvChannel {}
		::lichess::fake::Set dropBroadcastRound {}
		Check [dict exists [Data /api/tv/channels] Best] 1
		Check [llength [dict get [Data /api/broadcast/top] active]] 1
		set result ok
	} -cleanup Stop -result ok

	foreach status {401 404 429 302 503} {
		tcltest::test fake-status-$status {persistent original-path HTTP control and one-shot override} -setup Start -body {
			::lichess::fake::Control /api/bot/game/* $status 7
			foreach n {1 2} {
				set r [Call GET /api/bot/game/missing/chat]
				Check [dict get $r status] $status
				Check [dict get $r ok] 0
				set ::lichess::api::BackoffUntil 0
				if {$status == 401} {
					Check [::lichess::api::signedIn?] 0
					SignIn
				}
			}
			::lichess::fake::ForceNext /api/bot/game/* 500
			Check [dict get [Call GET /api/bot/game/missing/chat] status] 500
			::lichess::fake::ClearControl /api/bot/game/*
			Check [dict get [lindex [Data /api/bot/game/missing/chat array] 0] user] Alice
			set result ok
		} -cleanup Stop -result ok
	}

	tcltest::test fake-retry-after {Retry-After is configurable on the wire through API transport} -setup Start -body {
		::lichess::fake::Control /api/account 429 7
		set h [::lichess::api::Request GET /api/account {} ::lichess::faketest::Reply]
		# Observe the actual response headers before Done cleans up http state.
		rename ::lichess::api::Done ::lichess::api::FakeTestOriginalDone
		proc ::lichess::api::Done {id h} {
			set ::lichess::faketest::Headers [::http::meta $h]
			::lichess::api::FakeTestOriginalDone $id $h
		}
		Wait {[llength $Replies] == 1}
		Check [dict get $::lichess::faketest::Headers Retry-After] 7
		::lichess::fake::ForceNext /api/account 429 11
		set ::lichess::api::BackoffUntil 0
		Check [dict get [Call GET /api/account] status] 429
		Check [dict get $::lichess::faketest::Headers Retry-After] 11
		set result ok
	} -cleanup {
		rename ::lichess::api::Done {}
		rename ::lichess::api::FakeTestOriginalDone ::lichess::api::Done
		Stop
	} -result ok

	foreach mode {stall keepalive} {
		tcltest::test fake-$mode {stream stays open without events; unrelated path works; client close is journaled} -setup Start -body {
			::lichess::fake::Set keepAlive 10
			::lichess::fake::Control /api/tv/best/feed $mode
			set h [Stream /api/tv/best/feed]
			Pause
			Check $Events {}
			Check [llength [::lichess::fake::Closes]] 0
			set connection [lindex [dict values $::lichess::fake::Connections] 0]
			Check [dict get $connection kind] $mode
			if {$mode eq "keepalive"} {
				set http [dict get $::lichess::api::Requests $h http]
				Check [::http::ncode $http] 200
				Check [expr {[::http::size $http] > 2}] 1
			}
			Check [dict get [Data /api/account] id] bob
			::lichess::api::close $h
			Wait {[llength [::lichess::fake::Closes]] == 2}
			Check [dict get [lindex [::lichess::fake::Closes] end] path] /api/tv/best/feed
			set result ok
		} -cleanup Stop -result ok
	}

	foreach row {
		{/api/account/playing json nowPlaying}
		{/api/challenge json in}
		{/api/tv/channels json {}}
		{/api/broadcast/top json active}
		{/api/tournament json created}
		{/api/simul json created}
		{/api/team/team1/swiss ndjson {}}
		{/api/team/of/Alice array {}}
		{/api/puzzle/activity ndjson {}}
		{/api/puzzle/next json {}}
		{/api/board/game/g1/chat array {}}
		{/api/bot/game/g1/chat array {}}
	} {
		lassign $row path shape key
		tcltest::test fake-empty-$path {empty per-path response preserves container shape} -setup Start -body {
			::lichess::fake::Control $path empty
			set d [Data $path $shape]
			if {$key ne {}} { set d [dict get $d $key] }
			Check $d {}
			::lichess::fake::ClearControl $path
			Check [dict get [Data /api/account] id] bob
			set result ok
		} -cleanup Stop -result ok
	}

	tcltest::test fake-stop-closes {Stop closes all accepted connections once and retains journals until Start} -setup Start -body {
		set h [Stream /api/tv/best/feed]
		Wait {[llength $Events] == 1}
		Data /api/account
		::lichess::fake::Stop
		Check [llength [::lichess::fake::Closes]] 2
		Check [dict get [lindex [::lichess::fake::Closes] end] reason] stop
		Check [llength [::lichess::fake::Requests]] 2
		::lichess::fake::Stop
		Check [llength [::lichess::fake::Closes]] 2
		::lichess::fake::Start
		Check [::lichess::fake::Closes] {}
		Check [::lichess::fake::Requests] {}
		set result ok
	} -cleanup Stop -result ok
}
set failed $::tcltest::numTests(Failed)
::tcltest::cleanupTests
if {$failed} { exit 1 }
