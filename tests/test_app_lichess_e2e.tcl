# ======================================================================
# Scidb App Test — Lichess API and dialog against a loopback fake server.
# No test in this file contacts lichess.org or uses the OS credential store.
# ======================================================================

package require tcltest 2.5
package require json
source [file join [file dirname [info script]] app_wait.tcl]
source [file join [file dirname [info script]] lichess_fake_server.tcl]
if {[info exists ::application::Vars(ready)]} { ::scidb::test::wait::ready }

namespace eval ::scidb::test::lichess {
	variable RawChannels {}
	variable RawData {}
}

# Synchronous HTTP is used only to test the server fixture itself.  The real
# API tests below always enter through ::lichess::api's asynchronous methods.
proc ::scidb::test::lichess::Http {url args} {
	set token [::http::geturl $url -timeout 5000 {*}$args]
	set meta {}
	foreach {name value} [::http::meta $token] { dict set meta [string tolower $name] $value }
	set result [dict create status [::http::status $token] code [::http::ncode $token] \
		meta $meta data [::http::data $token]]
	::http::cleanup $token
	return $result
}

proc ::scidb::test::lichess::RawOpen {method path bearer {body {}}} {
	variable RawChannels
	variable RawData
	set port [lindex [split $::lichess::fake::Port :] end]
	set chan [socket 127.0.0.1 $port]
	fconfigure $chan -blocking 0 -buffering none -translation binary -encoding binary
	dict set RawChannels $chan 1
	dict set RawData $chan {}
	fileevent $chan readable [list ::scidb::test::lichess::RawRead $chan]
	set request "$method $path HTTP/1.1\r\nHost: 127.0.0.1:$port\r\n"
	append request "Authorization: Bearer $bearer\r\nConnection: keep-alive\r\n"
	if {$method eq "POST"} {
		append request "Content-Type: application/x-www-form-urlencoded\r\nContent-Length: [string length $body]\r\n"
	}
	append request "\r\n$body"
	puts -nonewline $chan $request
	flush $chan
	return $chan
}

proc ::scidb::test::lichess::RawRead {chan} {
	variable RawChannels
	variable RawData
	if {![dict exists $RawChannels $chan]} { return }
	append data [read $chan]
	dict append RawData $chan $data
	if {[eof $chan]} {
		catch {close $chan}
		dict unset RawChannels $chan
	}
}

proc ::scidb::test::lichess::RawText {chan} {
	variable RawData
	return [dict get $RawData $chan]
}

proc ::scidb::test::lichess::RawClose {chan} {
	variable RawChannels
	variable RawData
	catch {fileevent $chan readable {}}
	catch {close $chan}
	dict unset RawChannels $chan
	dict unset RawData $chan
}

proc ::scidb::test::lichess::RawCleanup {} {
	variable RawChannels
	variable RawData
	foreach chan [dict keys $RawChannels] {
		catch {fileevent $chan readable {}}
		catch {close $chan}
	}
	set RawChannels {}
	set RawData {}
}

proc ::scidb::test::lichess::OAuthUrl {verifier state} {
	return "[::lichess::fake::Base]/oauth?[::http::formatQuery \
		response_type code client_id chesswiz redirect_uri http://127.0.0.1:1/ \
		code_challenge_method S256 code_challenge [::lichess::fake::PkceChallenge $verifier] \
		scope board:play state $state]"
}

proc ::scidb::test::lichess::TokenForm {code verifier} {
	return [::http::formatQuery grant_type authorization_code code $code code_verifier $verifier \
		redirect_uri http://127.0.0.1:1/ client_id chesswiz]
}

proc ::scidb::test::lichess::RedirectQuery {response} {
	set location [dict get $response meta location]
	set question [string first "?" $location]
	return [::lichess::fake::ParseQuery [string range $location [expr {$question + 1}] end]]
}

proc ::scidb::test::lichess::FakeSignIn {} {
	set verifier "fake-server-test-verifier"
	set oauth [Http [OAuthUrl $verifier fake-state]]
	if {[dict get $oauth code] != 302} { error "fake OAuth did not redirect" }
	set query [RedirectQuery $oauth]
	set response [Http "[::lichess::fake::Base]/api/token" -method POST \
		-query [TokenForm [dict get $query code] $verifier]]
	if {[dict get $response code] != 200} { error "fake PKCE exchange failed" }
	return [dict get [::json::json2dict [dict get $response data]] access_token]
}

# ----------------------------------------------------------------------
# The fixture's own protocol tests.  Returned results never contain tokens.
# ----------------------------------------------------------------------

namespace eval ::scidb::test::lichess {

tcltest::test lichess-fake-oauth-account {OAuth S256, denial, bearer checks, redaction and forced statuses} -setup {
	::lichess::fake::Start
} -body {
	set verifier "correct-horse-fake-verifier"
	set oauth [Http [OAuthUrl $verifier expected-state]]
	set oauthCode [dict get $oauth code]
	set query [RedirectQuery $oauth]
	set wrong [Http "[::lichess::fake::Base]/api/token" -method POST \
		-query [TokenForm [dict get $query code] wrong-verifier]]
	set granted [Http "[::lichess::fake::Base]/api/token" -method POST \
		-query [TokenForm [dict get $query code] $verifier]]
	set bearer [dict get [::json::json2dict [dict get $granted data]] access_token]
	set account [Http "[::lichess::fake::Base]/api/account" -headers [list Authorization "Bearer $bearer"]]
	set bad [Http "[::lichess::fake::Base]/api/account" -headers [list Authorization "Bearer invalid"]]
	::lichess::fake::ForceNext /api/account 401
	set forced401 [Http "[::lichess::fake::Base]/api/account" -headers [list Authorization "Bearer $bearer"]]
	::lichess::fake::ForceNext /api/account 429
	set forced429 [Http "[::lichess::fake::Base]/api/account" -headers [list Authorization "Bearer $bearer"]]
	::lichess::fake::DenyNextOAuth
	set denied [Http [OAuthUrl $verifier expected-state]]
	set deniedQuery [RedirectQuery $denied]
	set journal [join [::lichess::fake::Requests] "\n"]
	list $oauthCode [dict get $query state] [dict get $wrong code] [dict get $granted code] \
		[dict get $account code] [dict get [::json::json2dict [dict get $account data]] username] \
		[dict get $bad code] [dict get $forced401 code] [dict get $forced429 code] \
		[dict get $forced429 meta retry-after] [dict get $deniedQuery error] \
		[expr {[string first $bearer $journal] < 0}] \
		[expr {[string first $verifier $journal] < 0}]
} -cleanup {
	::lichess::fake::Stop
} -result {302 expected-state 400 200 200 Bob 401 401 429 60 access_denied 1 1}

tcltest::test lichess-fake-streams-games-seeks {NDJSON keep-alives, scripted games, rejected moves and seek lifecycle} -setup {
	::lichess::fake::Start
	::lichess::fake::Set pairDelay 40
	::lichess::fake::Set replyDelay 20
	::lichess::fake::Set keepAlive 20
} -body {
	set bearer [FakeSignIn]
	set events [RawOpen GET /api/stream/event $bearer]
	::scidb::test::wait::until {[string first "application/x-ndjson" [RawText $events]] >= 0}
	set initialKeepAlive [expr {[string first "\r\n\r\n\n" [RawText $events]] >= 0}]
	::lichess::fake::ScriptNextGame {e7e5 b8c6}
	set challenge [Http "[::lichess::fake::Base]/api/challenge/ai" -method POST \
		-headers [list Authorization "Bearer $bearer"] \
		-query [::http::formatQuery level 3 clock.limit 300 clock.increment 2 color white]]
	set gameId [dict get [::json::json2dict [dict get $challenge data]] id]
	::scidb::test::wait::until {[string first "gameStart" [RawText $events]] >= 0}
	set game [RawOpen GET /api/board/game/stream/$gameId $bearer]
	::scidb::test::wait::until {[string first "gameFull" [RawText $game]] >= 0}
	set move [Http "[::lichess::fake::Base]/api/board/game/$gameId/move/e2e4" -method POST \
		-headers [list Authorization "Bearer $bearer"]]
	::scidb::test::wait::until {[dict get [::lichess::fake::Game $gameId] moves] eq {e2e4 e7e5}}
	::lichess::fake::RejectNextMove $gameId
	set rejected [Http "[::lichess::fake::Base]/api/board/game/$gameId/move/g1f3" -method POST \
		-headers [list Authorization "Bearer $bearer"]]
	set afterReject [dict get [::lichess::fake::Game $gameId] moves]
	::lichess::fake::Set pairDelay 500
	set cancelled [RawOpen POST /api/board/seek $bearer [::http::formatQuery time 10 increment 0 rated false color white]]
	::scidb::test::wait::until {[string first "200 OK" [RawText $cancelled]] >= 0}
	RawClose $cancelled
	::scidb::test::wait::until {[::lichess::fake::SeekCancellations] == 1}
	::lichess::fake::Set pairDelay 40
	::lichess::fake::ScriptNextGame {e7e5}
	set paired [RawOpen POST /api/board/seek $bearer [::http::formatQuery time 10 increment 0 rated false color black]]
	::scidb::test::wait::until {[string first {"source":"lobby"} [RawText $events]] >= 0}
	set seekGameCount [expr {[llength [::lichess::fake::Requests]] > 0}]
	set gameMoves [dict get [::lichess::fake::Game $gameId] moves]
	list $initialKeepAlive [dict get $challenge code] [dict get $move code] \
		[dict get $rejected code] $afterReject $gameMoves [::lichess::fake::SeekCancellations] $seekGameCount
} -cleanup {
	RawCleanup
	::lichess::fake::Stop
} -result {1 200 200 400 {e2e4 e7e5} {e2e4 e7e5} 1 1}



} ;# namespace eval

# ----------------------------------------------------------------------
# Real API + real dialog. Only browser launching and credential persistence
# are replaced; all HTTP requests and board moves go through product code.
# ----------------------------------------------------------------------
proc ::scidb::test::lichess::Browser {url} {
	::http::geturl $url -timeout 5000 -command ::scidb::test::lichess::BrowserResponse
}
proc ::scidb::test::lichess::BrowserResponse {h} {
	set location {}
	foreach {key val} [::http::meta $h] {
		if {[string equal -nocase $key Location]} { set location $val }
	}
	::http::cleanup $h
	if {$location ne {}} {
		# Redirects in this fixture must stay on the client's loopback server.
		if {![regexp {^http://127\.0\.0\.1:[0-9]+/\?} $location]} { error "non-loopback OAuth redirect" }
		::http::geturl $location -timeout 5000 -command ::scidb::test::lichess::BrowserResponse
	}
}
proc ::scidb::test::lichess::Setup {} {
	variable SavedBase
	variable SavedOptions
	variable Credential
	variable Positions
	set SavedBase $::lichess::api::Base
	set SavedOptions [array get ::lichess::Options]
	set Credential {}; set Positions {}
	foreach name {TokenStore TokenLoad TokenDelete OpenBrowser} {
		rename ::lichess::api::$name ::scidb::test::lichess::Original$name
	}
	proc ::lichess::api::TokenStore {tok} { set ::scidb::test::lichess::Credential $tok }
	proc ::lichess::api::TokenLoad {} { return $::scidb::test::lichess::Credential }
	proc ::lichess::api::TokenDelete {} { set ::scidb::test::lichess::Credential {} }
	proc ::lichess::api::OpenBrowser {url} { ::scidb::test::lichess::Browser $url }
	set ::lichess::api::Base [::lichess::fake::Start]
	set ::lichess::api::BackoffUntil 0
	::lichess::fake::Set pairDelay 30
	::lichess::fake::Set replyDelay 30
	::lichess::open .application
	::lichess::SignIn
	::scidb::test::wait::until {!$::lichess::Priv(signingIn)}
	if {$::lichess::Priv(state) ne "lobby"} { error "loopback sign-in failed" }
	::scidb::test::wait::until {[llength $::lichess::fake::EventStreams] > 0}
}
proc ::scidb::test::lichess::Cleanup {} {
	variable Positions
	variable SavedBase
	variable SavedOptions
	catch {::lichess::Close}
	::lichess::api::signOut
	::lichess::fake::Stop
	update
	foreach pos [lsort -unique $Positions] {
		catch {::application::pgn::release $pos}
		catch {::game::release $pos}
	}
	foreach name {TokenStore TokenLoad TokenDelete OpenBrowser} {
		if {[llength [info commands ::scidb::test::lichess::Original$name]]} {
			rename ::lichess::api::$name {}
			rename ::scidb::test::lichess::Original$name ::lichess::api::$name
		}
	}
	set ::lichess::api::Base $SavedBase
	array set ::lichess::Options $SavedOptions
}
proc ::scidb::test::lichess::Ai {color replies} {
	variable Positions
	::lichess::fake::ScriptNextGame $replies
	set ::lichess::Priv(dlg:aiLevel) 3
	set ::lichess::Priv(dlg:aiMinutes) 5
	set ::lichess::Priv(dlg:aiIncrement) 2
	set ::lichess::Priv(dlg:aiColor) [::lichess::ColourLabel $color]
	::lichess::ChallengeAi
	::scidb::test::wait::until {$::lichess::Priv(state) eq "playing"}
	lappend Positions $::lichess::Priv(pos)
	return $::lichess::Priv(gameId)
}
proc ::scidb::test::lichess::MovesAre {moves} {
	::scidb::test::wait::until {$::lichess::Priv(serverMoves) eq $moves && $::lichess::Priv(pendingMove) eq {}}
}
proc ::scidb::test::lichess::ResultIs {result} {
	::scidb::test::wait::until {$::lichess::Priv(state) eq "over"}
	set tags [::scidb::game::tags]
	return [expr {[lsearch -exact $tags [list Result $result]] >= 0}]
}

namespace eval ::scidb::test::lichess {
	tcltest::test lichess-e2e-ai-white {sign in, white moves, rejection rollback, resign and PGN headers} -setup {
		Setup
	} -body {
		set id [Ai white {e7e5 b8c6}]
		set tags [::scidb::game::tags]
		set first [::lichess::UserMove e4]
		MovesAre {e2e4 e7e5}
		::lichess::fake::RejectNextMove $id
		set rejected [::lichess::UserMove Nf3]
		::scidb::test::wait::until {$::lichess::Priv(pendingMove) eq {} && [::lichess::BoardPly] == 2}
		set restored [expr {[::lichess::MyTurn] && [dict get [::lichess::fake::Game $id] moves] eq {e2e4 e7e5}}]
		set retry [::lichess::UserMove Nf3]
		MovesAre {e2e4 e7e5 g1f3 b8c6}
		::lichess::Resign
		set result [ResultIs 0-1]
		set pgn [::scidb::game::toPGN modified -position $::lichess::Priv(pos)]
		list $first $rejected $restored $retry $result \
			[expr {[lsearch -exact $tags {White Bob}] >= 0}] \
			[expr {[lsearch -exact $tags {Black {Stockfish level 3}}] >= 0}] \
			[expr {[lsearch -exact $tags {TimeControl 300+2}] >= 0}] \
			[expr {[lsearch -exact $tags [list Site https://lichess.org/$id]] >= 0}] \
			[expr {[lsearch -exact $tags {Event {Lichess casual blitz game}}] >= 0}] \
			[expr {[string first "1.e4 e5 2.Nf3 Nc6" $pgn] >= 0}] \
			[expr {[string first $Credential $pgn] < 0}]
	} -cleanup { Cleanup } -result {1 1 1 1 1 1 1 1 1 1 1 1}

	tcltest::test lichess-e2e-ai-black-draw {black moves and a draw by agreement} -setup { Setup } -body {
		Ai black {d2d4 c2c4}
		MovesAre d2d4
		set side $::lichess::Priv(userSide)
		set moved [::lichess::UserMove d5]
		MovesAre {d2d4 d7d5 c2c4}
		set second [::lichess::UserMove e6]
		MovesAre {d2d4 d7d5 c2c4 e7e6}
		::lichess::OfferDraw
		list $side $moved $second [ResultIs 1/2-1/2]
	} -cleanup { Cleanup } -result {b 1 1 1}

	tcltest::test lichess-e2e-seek-claim {rapid restriction, cancelled seek, pairing and opponent timeout claim} -setup { Setup } -body {
		set ::lichess::Priv(dlg:minutes) 1
		set ::lichess::Priv(dlg:increment) 0
		set ::lichess::Priv(dlg:rated) 0
		set ::lichess::Priv(dlg:color) [::lichess::ColourLabel white]
		set refused [::lichess::Seek]
		set ::lichess::Priv(dlg:minutes) 10
		::lichess::fake::Set pairDelay 10000
		::lichess::Seek
		# Wait for the actual seek request, rather than merely its client handle.
		::scidb::test::wait::until {[lsearch -glob [::lichess::fake::Requests] {*path /api/board/seek*}] >= 0}
		::lichess::CancelSeek
		::scidb::test::wait::until {[::lichess::fake::SeekCancellations] == 1}
		::lichess::fake::Set pairDelay 30
		::lichess::Seek
		::scidb::test::wait::until {$::lichess::Priv(state) eq "playing"}
		lappend Positions $::lichess::Priv(pos)
		set id $::lichess::Priv(gameId)
		::lichess::fake::OpponentGone $id
		::scidb::test::wait::until {$::lichess::Priv(opponentGone)}
		::lichess::ClaimVictory
		list $refused [::lichess::fake::SeekCancellations] [ResultIs 1-0]
	} -cleanup { Cleanup } -result {0 1 1}

	tcltest::test lichess-e2e-account-401 {account authentication failure returns the dialog to sign-in} -setup { Setup } -body {
		::lichess::fake::ForceNext /api/account 401
		::lichess::api::account ::lichess::AccountResult
		::scidb::test::wait::until {$::lichess::Priv(state) eq "offline"}
		list [::lichess::api::signedIn?] [winfo manager $::lichess::Priv(widget:signin)]
	} -cleanup { Cleanup } -result {0 pack}

	tcltest::test lichess-e2e-stream-401 {revoked credential on reconnect returns to sign-in} -setup { Setup } -body {
		::lichess::ReleaseStreams
		update
		::lichess::fake::ForceNext /api/stream/event 401
		::lichess::StartEvents
		::scidb::test::wait::until {$::lichess::Priv(state) eq "offline"}
		list [::lichess::api::signedIn?] [winfo manager $::lichess::Priv(widget:signin)]
	} -cleanup { Cleanup } -result {0 pack}
}

namespace eval ::scidb::test::lichess {
	tcltest::test lichess-fake-pure-games {scripted moves, rejection, resign, draw and claim retain coherent game dicts} -setup {
		::lichess::fake::ClearState
		rename ::lichess::fake::Respond ::lichess::fake::OriginalRespond
		proc ::lichess::fake::Respond {ch status args} { set ::scidb::test::lichess::FakeStatus $status }
	} -body {
		::lichess::fake::ScriptNextGame {e7e5 b8c6}
		set id [::lichess::fake::CreateGame white ai 3 300 2]
		::lichess::fake::Move unused $id e2e4
		::lichess::fake::OpponentMove $id
		set first [dict get [::lichess::fake::Game $id] moves]
		::lichess::fake::RejectNextMove $id
		::lichess::fake::Move unused $id g1f3
		set rejected $FakeStatus
		set unchanged [expr {[dict get [::lichess::fake::Game $id] moves] eq $first}]
		::lichess::fake::Move unused $id g1f3
		::lichess::fake::OpponentMove $id
		set moves [dict get [::lichess::fake::Game $id] moves]
		::lichess::fake::GameAction unused $id resign
		set result [::lichess::fake::GameState $id]
		set drawn [::lichess::fake::CreateGame black lobby 0 600 0]
		::lichess::fake::Draw unused $drawn yes
		::lichess::fake::Finish $drawn draw {}
		set claim [::lichess::fake::CreateGame black lobby 0 600 0]
		::lichess::fake::OpponentGone $claim
		::lichess::fake::GameAction unused $claim claim-victory
		set won [::lichess::fake::GameState $claim]
		list $first $rejected $unchanged $moves [dict get $result status] [dict get $result winner] \
			[dict get [::lichess::fake::GameState $drawn] status] [dict get $won status] [dict get $won winner]
	} -cleanup {
		rename ::lichess::fake::Respond {}
		rename ::lichess::fake::OriginalRespond ::lichess::fake::Respond
		::lichess::fake::Stop
	} -result {{e2e4 e7e5} 400 1 {e2e4 e7e5 g1f3 b8c6} resign black draw timeout black}

	tcltest::test lichess-fake-pure-schema {fixture emits typed nested JSON and escapes strings} -body {
		::lichess::fake::ClearState
		::lichess::fake::ScriptNextGame {e7e5 b8c6}
		set id [::lichess::fake::CreateGame white ai 3 300 2]
		set full [::json::json2dict [::lichess::fake::Json [::lichess::fake::GameFull $id]]]
		set escaped [::json::json2dict [::lichess::fake::Json [dict create name "Bób\n\"quoted\"\\end"]]]
		list [dict get $full type] [dict get $full black aiLevel] [dict get $full clock initial] \
			[dict get $full state status] [dict get $full rated] \
			[expr {[dict get $escaped name] eq "Bób\n\"quoted\"\\end"}]
	} -cleanup { ::lichess::fake::ClearState } -result {gameFull 3 300000 started false 1}
}

tcltest::cleanupTests
