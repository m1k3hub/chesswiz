# Standalone loopback-only phase-two API contract tests.
package require tcltest 2.5
if {[catch {package require json}]} {
	foreach dir [glob -nocomplain /usr/share/tcltk/tcllib*] { lappend auto_path $dir }
	package require json
}
source [file join [file dirname [info script]] .. tcl lichess-api.tcl]
source [file join [file dirname [info script]] lichess_fake_server.tcl]

namespace eval ::lichess::phase2 {
	variable Events {}
	variable Replies {}
}
foreach name {TokenStore TokenLoad TokenDelete} {
	rename ::lichess::api::$name ::lichess::phase2::Original$name
}
proc ::lichess::api::TokenLoad {} { return $::lichess::fake::Token }
proc ::lichess::api::TokenStore {value} { set ::lichess::fake::Token $value }
proc ::lichess::api::TokenDelete {} { set ::lichess::fake::Token {} }
proc ::lichess::phase2::Wait {condition} {
	set deadline [expr {[clock milliseconds]+3000}]
	while {![uplevel 1 [list expr $condition]]} {
		if {[clock milliseconds] >= $deadline} { error "phase-two API test timed out" }
		after 5 [list set ::lichess::phase2::Tick 1]
		vwait ::lichess::phase2::Tick
	}
}
proc ::lichess::phase2::Start {} {
	variable Events
	variable Replies
	set Events {}
	set Replies {}
	set ::lichess::api::Base [::lichess::fake::Start]
	set ::lichess::fake::Token [::lichess::testToken]
	set ::lichess::api::BackoffUntil 0
	::lichess::api::mode board
}
proc ::lichess::phase2::Stop {} {
	foreach id [dict keys $::lichess::api::Requests] { ::lichess::api::close $id }
	update
	::lichess::fake::Stop
	::lichess::api::mode board
	set ::lichess::api::BackoffUntil 0
	set ::lichess::api::ReconnectDelays {1000 3000 9000}
}
proc ::lichess::phase2::Reply {value} { lappend ::lichess::phase2::Replies $value }
proc ::lichess::phase2::Event {value} { lappend ::lichess::phase2::Events $value }
proc ::lichess::phase2::Call {args} {
	variable Replies
	set Replies {}
	::lichess::api::[lindex $args 0] {*}[lrange $args 1 end] ::lichess::phase2::Reply
	Wait {[llength $Replies] > 0}
	update
	if {[llength $Replies] != 1} { error "callback delivered more than once" }
	return [lindex $Replies 0]
}
proc ::lichess::phase2::Check {actual expected} {
	if {$actual ne $expected} { error "expected <$expected>, received <$actual>" }
}
proc ::lichess::phase2::Last {} { lindex [::lichess::fake::Requests] end }

namespace eval ::lichess::phase2 {
	# Each row independently checks method/path and meaningful response fields.
	set gets {
		{user {Alice} /api/user/Alice {id} alice}
		{ratingHistory {Alice} /api/user/Alice/rating-history {0 name} Rapid}
		{teamsOf {Alice} /api/team/of/Alice {0 id} team1}
		{chatHistory {g1} /api/board/game/g1/chat {0 text} {Good luck!}}
		{tvChannels {} /api/tv/channels {Best gameId} tv1}
		{broadcastsTop {} /api/broadcast/top {active 0 round id} round1}
		{arenas {} /api/tournament {created 0 id} arena1}
		{arena {arena1} /api/tournament/arena1 {nbPlayers} 2}
		{swissOfTeam {team1} /api/team/team1/swiss {1 id} swiss2}
		{simuls {} /api/simul {created 0 id} simul1}
		{puzzleDaily {} /api/puzzle/daily {puzzle solution 1} e7e5}
		{puzzleNext {mate easier} /api/puzzle/next {puzzle id} puzzle1}
		{puzzle {puzzle1} /api/puzzle/puzzle1 {puzzle rating} 1500}
		{puzzleDashboard {30} /api/puzzle/dashboard/30 {global nb} 10}
		{puzzleActivity {2} /api/puzzle/activity {1 win} false}
		{cloudEval {{position & /?} 2} /api/cloud-eval {pvs 0 cp} 25}
		{studiesOf {Alice} /api/study/by/Alice {1 name} {Study two}}
	}
	# Mixed dict/list traversal follows the explicit response schema.
	proc Field {value keys} {
		foreach key $keys {
			if {[string is integer -strict $key]} { set value [lindex $value $key] } else { set value [dict get $value $key] }
		}
		return $value
	}
	foreach row $gets {
		lassign $row name args expectedPath keys expected
		tcltest::test phase2-get-$name "$name method, URL and parsed reply" -setup { Start } -body {
			set reply [Call $name {*}$args]
			Check [dict get $reply ok] 1
			Check [Field [dict get $reply data] $keys] $expected
			Check [dict get [Last] method] GET
			Check [dict get [Last] path] $expectedPath
			Check [dict get [Last] authorized] 1
			if {$name eq "puzzleNext"} { Check [dict get [Last] query] {angle mate difficulty easier} }
			if {$name eq "puzzleActivity"} { Check [dict get [Last] query] {max 2} }
			if {$name eq "cloudEval"} { Check [dict get [Last] query] {fen {position & /?} multiPv 2} }
			set result ok
		} -cleanup { Stop } -result ok
	}

	set posts {
		{joinTeam {team1 {Hello & welcome}} /api/team/team1/join {message {Hello & welcome}}}
		{leaveTeam {team1} /api/team/team1/quit {}}
		{sendMessage {Alice {Hi é & ?}} /api/inbox/Alice {text {Hi é & ?}}}
		{acceptChallenge {c1} /api/challenge/c1/accept {}}
		{declineChallenge {c1 later} /api/challenge/c1/decline {reason later}}
		{cancelChallenge {c1} /api/challenge/c1/cancel {}}
		{botUpgrade {} /api/bot/account/upgrade {}}
		{joinArena {arena1} /api/tournament/arena1/join {}}
		{withdrawArena {arena1} /api/tournament/arena1/withdraw {}}
		{joinSwiss {swiss1} /api/swiss/swiss1/join {}}
		{withdrawSwiss {swiss1} /api/swiss/swiss1/withdraw {}}
		{puzzleRace {} /api/racer {}}
		{importGame {{1. e4 e5 *}} /api/import {pgn {1. e4 e5 *}}}
		{studyImportPgn {study1 Chapter {1. e4 *} black chess960} /api/study/study1/import-pgn {name Chapter pgn {1. e4 *} orientation black variant chess960}}
		{studyCreate {{New study} private} /api/study {name {New study} visibility private}}
	}
	foreach row $posts {
		lassign $row name args expectedPath form
		tcltest::test phase2-post-$name "$name form body and parsed reply" -setup { Start } -body {
			set reply [Call $name {*}$args]
			Check [dict get $reply ok] 1
			Check [dict get [Last] method] POST
			Check [dict get [Last] path] $expectedPath
			Check [dict get [Last] form] $form
			# http omits the type of an empty body
			if {$form ne {}} { Check [dict get [Last] contentType] application/x-www-form-urlencoded }
			switch $name {
				puzzleRace { Check [dict get $reply data id] race1 }
				importGame { Check [dict get $reply data id] import1 }
				studyCreate { Check [dict get $reply data name] {New study} }
				default { Check [dict get $reply data ok] true }
			}
			set result ok
		} -cleanup { Stop } -result ok
	}

	tcltest::test phase2-challenge {real-time and correspondence challenge forms} -setup { Start } -body {
		set r [Call challengeUser {A/B ?} 3 2 true white chess960 {}]
		Check [dict get $r data id] challenge1
		Check [dict get [Last] path] /api/challenge/A%2FB%20%3F
		Check [dict get [Last] form] {rated true color white variant chess960 clock.limit 180 clock.increment 2}
		Call challengeUser Alice 0 0 false random atomic 3
		Check [dict get [Last] form] {rated false color random variant atomic days 3}
		set result ok
	} -cleanup { Stop } -result ok

	tcltest::test phase2-seek {optional variant and correspondence nonstream response} -setup { Start } -body {
		::lichess::api::seek 10 2 true white ::lichess::phase2::Event chess960
		Wait {[llength [::lichess::fake::Requests]] == 1}
		Check [dict get [Last] form] {time 10 increment 2 rated true color white variant chess960}
		set Replies {}
		::lichess::api::seek 0 0 false random ::lichess::phase2::Reply atomic 2
		Wait {[llength $Replies] == 1}
		Check [dict get [Last] form] {rated false color random days 2 variant atomic}
		Check [dict get [lindex $Replies 0] ok] 1
		Check [dict exists [lindex $Replies 0] type] 0
		set result ok
	} -cleanup { Stop } -result ok

	tcltest::test phase2-json {batch JSON strings, booleans and content type} -setup { Start } -body {
		set solutions [list [dict create id "p\"é\\\n" win true rated false] [dict create id p2 win 0 rated 1]]
		Check [dict get [Call puzzleBatchSolved {mate/one} $solutions] data ok] true
		Check [dict get [Last] contentType] application/json
		Check [dict get [Last] path] /api/puzzle/batch/mate%2Fone
		set sent [dict get [Last] json solutions]
		Check [dict get [lindex $sent 0] id] "p\"é\\\n"
		Check [dict get [lindex $sent 0] win] true
		Check [dict get [lindex $sent 0] rated] false
		Check [dict get [lindex $sent 1] win] false
		Check [dict get [lindex $sent 1] rated] true
		Check [dict get [Call puzzleBatchSolved mix {}] ok] 1
		Check [dict get [Last] json solutions] {}
		set result ok
	} -cleanup { Stop } -result ok

	tcltest::test phase2-export {raw PGN, Accept and query parameters} -setup { Start } -body {
		set r [Call gameExport g1]
		Check [dict get $r data] "\[Event \"Fixture\"\]\n\n1. e4 e5 *\n"
		Check [dict get [Last] accept] application/x-chess-pgn
		Check [dict get [Last] query] {evals true clocks true literate true}
		set result ok
	} -cleanup { Stop } -result ok

	foreach row {{tvFeed {}} {tvFeed Best} {streamGameMoves tv1} {broadcastRoundStream round1}} {
		lassign $row name arg
		tcltest::test phase2-stream-$name-$arg {live delivery and exactly one close} -setup { Start } -body {
			set h [::lichess::api::$name $arg ::lichess::phase2::Event]
			Wait {[llength [::lichess::fake::Requests]] == 1}
			set path [dict get [Last] path]
			switch $name {
				tvFeed {
					Check $path [expr {$arg eq {} ? "/api/tv/feed" : "/api/tv/[::lichess::api::TvChannelKey $arg]/feed"}]
					Wait {[llength $Events] == 1}
					Check [dict get [lindex $Events 0] t] featured
					::lichess::fake::EmitTv [dict create t fen d [dict create fen position lm e2e4 wc 10 bc 20]]
					Wait {[llength $Events] == 2}
					Check [dict get [lindex $Events 1] d lm] e2e4
				}
				streamGameMoves {
					Check $path /api/stream/game/tv1
					Wait {[llength $Events] == 1}
					::lichess::fake::EmitTv [dict create fen position lm e2e4 wc 10 bc 20]
					Wait {[llength $Events] == 2}
					Check [dict get [lindex $Events 1] lm] e2e4
				}
				broadcastRoundStream {
					Check $path /api/stream/broadcast/round/round1.pgn
					Check [dict get [Last] accept] application/x-chess-pgn
					::lichess::fake::EmitBroadcastPgn round1 "\[Event \"Bób\"\]\n\n1. e4 *"
					Wait {[llength $Events] == 1}
					Check [dict get [lindex $Events 0] type] pgn
					Check [dict get [lindex $Events 0] text] "\[Event \"Bób\"\]\n\n1. e4 *"
				}
			}
			set count [llength $Events]
			::lichess::api::close $h
			::lichess::api::close $h
			Wait {[llength $Events] == $count+1}
			Check [dict get [lindex $Events end] type] closed
			Check [dict exists $::lichess::api::Requests $h] 0
			set result ok
		} -cleanup { Stop } -result ok
	}

	tcltest::test phase2-bot {explicit bot family and mode switching for all game operations} -setup { Start } -body {
		foreach family {board bot explicit} {
			::lichess::api::mode [expr {$family eq "bot" ? "bot" : "board"}]
			set id [::lichess::fake::CreateGame white ai 1 600 0]
			set Events {}
			set stream [expr {$family eq "explicit" ? "botStreamGame" : "streamGame"}]
			set h [::lichess::api::$stream $id ::lichess::phase2::Event]
			Wait {[llength $Events] == 1}
			set prefix [expr {$family eq "board" ? "board" : "bot"}]
			Check [dict get [Last] path] /api/$prefix/game/stream/$id
			foreach operation {{move e2e4} {chat {Hello & é}} {takeback yes} {takeback no} {draw no} {draw yes} {resign} {abort}} {
				set id [::lichess::fake::CreateGame white ai 1 600 0]
				set name [lindex $operation 0]
				set arg [lrange $operation 1 end]
				set method $name
				if {$family eq "explicit"} { set method bot[string totitle $name] }
				Check [dict get [Call $method $id {*}$arg] ok] 1
				set suffix $name
				if {$name in {move takeback draw}} { append suffix /[lindex $arg 0] }
				Check [dict get [Last] path] /api/$prefix/game/$id/$suffix
				Check [dict get [Last] method] POST
				if {$name eq "chat"} { Check [dict get [Last] form] {room player text {Hello & é}} }
			}
			::lichess::api::close $h
			update
		}
		Check [catch {::lichess::api::mode invalid}] 1
		set result ok
	} -cleanup { Stop } -result ok

	tcltest::test phase2-events {challenge and chat helpers preserve nested event data} -setup { Start } -body {
		set h [::lichess::api::streamEvents ::lichess::phase2::Event]
		Wait {[llength $::lichess::fake::EventStreams] == 1}
		::lichess::fake::EmitChallenge [dict create id c1 status created]
		Wait {[llength $Events] == 1}
		Check [dict get [lindex $Events 0] challenge id] c1
		set Events {}
		set id [::lichess::fake::CreateGame white ai 1 600 0]
		::lichess::api::streamGame $id ::lichess::phase2::Event
		Wait {[llength $Events] == 1}
		::lichess::fake::EmitChat $id Alice {Good game é}
		Wait {[llength $Events] == 2}
		Check [dict get [lindex $Events 1] type] chatLine
		Check [dict get [lindex $Events 1] text] {Good game é}
		set result ok
	} -cleanup { Stop } -result ok

	# Every finite endpoint exercises the same transport error contract.
	foreach row [concat $gets $posts {{challengeUser {Alice 5 2 false white standard {}} /api/challenge/Alice} {puzzleBatchSolved {mix {}} /api/puzzle/batch/mix} {gameExport g1 /game/export/g1}
		{botMove {g1 e2e4} /api/bot/game/g1/move/e2e4}
		{botResign g1 /api/bot/game/g1/resign}
		{botAbort g1 /api/bot/game/g1/abort}
		{botDraw {g1 yes} /api/bot/game/g1/draw/yes}
		{botTakeback {g1 no} /api/bot/game/g1/takeback/no}
		{botChat {g1 hello} /api/bot/game/g1/chat}}] {
		lassign $row name args expectedPath
		foreach status {400 401 404 429 500} {
			tcltest::test phase2-error-$name-$status {local error with HTTP status and one callback} -setup { Start } -body {
				::lichess::fake::ForceNext $expectedPath $status
				set r [Call $name {*}$args]
				Check [dict get $r ok] 0
				Check [dict get $r status] $status
				if {$status == 404 && $name eq "cloudEval"} { Check [dict get $r error] {No cloud evaluation for this position.} }
				if {$status == 429} { Check [expr {$::lichess::api::BackoffUntil > [clock milliseconds]+59000}] 1 }
				Check [expr {[string first [::lichess::testToken] [dict get $r error]] < 0}] 1
				set result ok
			} -cleanup { Stop } -result ok
		}
	}

	foreach row {{tvFeed Best /api/tv/best/feed} {streamGameMoves tv1 /api/stream/game/tv1} {broadcastRoundStream round1 /api/stream/broadcast/round/round1.pgn} {botStreamGame missing /api/bot/game/stream/missing}} {
		lassign $row name arg expectedPath
		foreach status {401 404 429 500} {
			tcltest::test phase2-stream-error-$name-$status {stream HTTP failures close once; server failures use bounded reconnect} -setup { Start } -body {
				if {$status == 500} {
					::lichess::fake::Control $expectedPath 500
					set ::lichess::api::ReconnectDelays {10 30 90}
				} else {
					::lichess::fake::ForceNext $expectedPath $status
				}
				set h [::lichess::api::$name $arg ::lichess::phase2::Event]
				if {$status == 500} {
					Wait {[dict get $::lichess::api::Requests $h lost]}
					Check [llength [::lichess::fake::Requests]] 4
					Check [dict get $::lichess::api::Requests $h attempts] 3
					Check [llength $Events] 0
				} else {
					Wait {[llength $Events] == 1}
					Check [dict get [lindex $Events 0] type] closed
					Check [dict get [lindex $Events 0] status] $status
					Check [dict get [lindex $Events 0] ok] 0
				}
				::lichess::api::close $h
				update
				Check [llength $Events] 1
				set result ok
			} -cleanup { Stop } -result ok
		}
	}
	tcltest::test phase2-broadcast-eof {finished-round EOF flushes the last PGN before closed} -setup { Start } -body {
		::lichess::api::broadcastRoundStream round1 ::lichess::phase2::Event
		Wait {[llength [::lichess::fake::Requests]] == 1}
		foreach {chan connection} $::lichess::fake::Connections {
			if {[dict get $connection kind] eq "broadcast"} {
				::lichess::fake::WriteRaw $chan "\[Event \"Last\"\]\n\[Result \"1-0\"\]\n\n1. d4 1-0"
				::lichess::fake::Disconnect $chan
			}
		}
		Wait {[llength $Events] == 2}
		Check [dict get [lindex $Events 0] text] "\[Event \"Last\"\]\n\[Result \"1-0\"\]\n\n1. d4 1-0"
		Check [dict get [lindex $Events 1] type] closed
		set result ok
	} -cleanup { Stop } -result ok

	# Parser tests run even where the execution sandbox forbids sockets.
	tcltest::test phase2-pgn-bytes {UTF-8, adjacent Event headers and final unterminated PGN} -body {
		set Events {}
		dict set ::lichess::api::Requests pure [dict create cmd ::lichess::phase2::Event stream 1 response pgn buffer {} timer {} watchdog {} deadline {} generation 0]
		dict set ::lichess::api::Deliveries pure 0
		set bytes [encoding convertto utf-8 "\[Event \"Bób\"\]\n\n1. e4 *\n\[Event \"Two\"\]\n\n1. d4 *\n\n\n\[Event \"Tail\"\]\n*"]
		foreach byte [split $bytes {}] { ::lichess::api::Lines pure $byte }
		::lichess::api::PgnLines pure {} 1
		::lichess::api::Finish pure [dict create ok 1]
		update
		list [llength $Events] [dict get [lindex $Events 0] text] [dict get [lindex $Events 3] type]
	} -cleanup { catch {dict unset ::lichess::api::Requests pure}; ::lichess::api::ForgetDelivery pure } -result [list 4 "\[Event \"Bób\"\]\n\n1. e4 *" closed]

	tcltest::test phase2-pgn-single {a lone game is delivered without waiting for the next one} -body {
		set Events {}
		dict set ::lichess::api::Requests pure [dict create cmd ::lichess::phase2::Event stream 1 response pgn buffer {} timer {} watchdog {} deadline {} generation 0]
		dict set ::lichess::api::Deliveries pure 0
		foreach byte [split "\[Event \"One\"\]\r\n\[White \"A\"\]\r\n\r\n1. e4 e5 *\r\n\r\n" {}] { ::lichess::api::Lines pure $byte }
		update
		list [llength $Events] [dict get [lindex $Events 0] text]
	} -cleanup { catch {dict unset ::lichess::api::Requests pure}; ::lichess::api::ForgetDelivery pure } -result [list 1 "\[Event \"One\"\]\n\[White \"A\"\]\n\n1. e4 e5 *"]

	tcltest::test phase2-tv-channel-key {channel names become the camel-case keys of the feed address} -body {
		lmap name {Best best {Top Rated} {King of the Hill} UltraBullet Three-check {Racing Kings} Chess960 kingOfTheHill} {
			::lichess::api::TvChannelKey $name
		}
	} -result {best best best kingOfTheHill ultraBullet threeCheck racingKings chess960 kingOfTheHill}

	tcltest::test phase2-path-segment {a space in a path segment is %20, never +} -body {
		::lichess::api::Segment {a b+c/d}
	} -result {a%20b%2Bc%2Fd}

	tcltest::test phase2-shapes {JSON container checks distinguish arrays from objects} -body {
		list [::lichess::api::ParseJson {[]} array] [::lichess::api::ParseJson {{}} object] \
			[catch {::lichess::api::ParseJson {[]} object}] [catch {::lichess::api::ParseJson {{}} array}]
	} -result {{} {} 1 1}
}
foreach name {TokenStore TokenLoad TokenDelete} {
	rename ::lichess::api::$name {}
	rename ::lichess::phase2::Original$name ::lichess::api::$name
}
set failed $::tcltest::numTests(Failed)
::tcltest::cleanupTests
if {$failed} { exit 1 }
