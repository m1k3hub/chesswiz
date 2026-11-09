# Loopback-only API tests, independent of job C's fixture.
package require tcltest 2.5
package require json
if {[info exists ::application::Vars(ready)]} {
	source [file join [file dirname [info script]] app_wait.tcl]
	::scidb::test::wait::ready
}
if {![llength [info commands ::lichess::api::signIn]]} {
	source [file join [file dirname [info script]] .. tcl lichess-api.tcl]
}
namespace eval ::lichess::apitest {
	variable Stored {}
	variable Seen {}
	variable Connections {}
	variable Events {}
	variable Status 200
	variable Mode normal
	variable Timers {}
}
foreach name {TokenStore TokenLoad TokenDelete OpenBrowser} {
	rename ::lichess::api::$name ::lichess::apitest::Original$name
}
proc ::lichess::api::TokenStore {tok} { set ::lichess::apitest::Stored $tok }
proc ::lichess::api::TokenLoad {} { return $::lichess::apitest::Stored }
proc ::lichess::api::TokenDelete {} { set ::lichess::apitest::Stored {} }

proc ::lichess::apitest::Wait {condition {timeout 5000}} {
	set deadline [expr {[clock milliseconds]+$timeout}]
	while {![uplevel 1 [list expr $condition]]} {
		if {[clock milliseconds] >= $deadline} { error "API test timed out" }
		after 5 [list set ::lichess::apitest::Tick 1]
		vwait ::lichess::apitest::Tick
	}
}
proc ::lichess::apitest::Call {args} {
	unset -nocomplain ::lichess::apitest::Result
	::lichess::api::[lindex $args 0] {*}[lrange $args 1 end] [list set ::lichess::apitest::Result]
	Wait {[info exists ::lichess::apitest::Result]}
	return $::lichess::apitest::Result
}
proc ::lichess::apitest::Start {} {
	variable Listener
	variable Seen
	variable Events
	variable Status
	variable Mode
	set Seen {}; set Events {}; set Status 200; set Mode normal
	set Listener [socket -server ::lichess::apitest::Accept -myaddr 127.0.0.1 0]
	set ::lichess::api::Base http://127.0.0.1:[lindex [fconfigure $Listener -sockname] 2]
	set ::lichess::api::BackoffUntil 0
}
proc ::lichess::apitest::Stop {} {
	variable Listener
	variable Connections
	variable Timers
	::lichess::api::signOut
	foreach t $Timers { after cancel $t }
	set Timers {}
	foreach ch [dict keys $Connections] { catch {::close $ch} }
	set Connections {}
	catch {::close $Listener}
	set ::lichess::api::Base https://lichess.org
	set ::lichess::api::BackoffUntil 0
}
proc ::lichess::apitest::Accept {ch address port} {
	variable Connections
	fconfigure $ch -blocking 0 -buffering none -translation binary -encoding binary
	dict set Connections $ch {}
	fileevent $ch readable [list ::lichess::apitest::Read $ch]
}
proc ::lichess::apitest::Read {ch} {
	variable Connections
	variable Seen
	variable Status
	variable Mode
	set buffer [dict get $Connections $ch]
	append buffer [read $ch]
	dict set Connections $ch $buffer
	if {[eof $ch]} { catch {::close $ch}; dict unset Connections $ch; return }
	set end [string first "\r\n\r\n" $buffer]
	if {$end < 0} { return }
	set head [string range $buffer 0 [expr {$end-1}]]
	set body [string range $buffer [expr {$end+4}] end]
	set length 0
	regexp -nocase {Content-Length: ([0-9]+)} $head -> length
	if {[string length $body] < $length} { return }
	fileevent $ch readable {}
	regexp {^(\S+) (\S+)} $head -> method path
	set authorized [expr {[string first {Authorization: Bearer test-secret} $head] >= 0}]
	# Never retain authorization or token-exchange data in the journal.
	if {$path eq "/api/token"} { set recorded <redacted> } else { set recorded $body }
	lappend Seen [list $method $path $recorded $authorized]
	if {$path eq "/api/token"} {
		set form [Query $body]
		set ::lichess::apitest::ExchangeValid [expr {
			[dict get $form code] eq "local-code" && [dict get $form client_id] eq "chesswiz" &&
			[dict get $form grant_type] eq "authorization_code" &&
			[::lichess::api::Challenge [dict get $form code_verifier]] eq $::lichess::apitest::Challenge &&
			[dict get $form redirect_uri] eq $::lichess::apitest::Redirect}]
		Respond $ch 200 {{"token_type":"Bearer","access_token":"test-secret"}}
	} elseif {$Status != 200} {
		set code $Status; set Status 200
		Respond $ch $code {{"error":"test-secret echoed by server"}}
	} elseif {!$authorized} {
		Respond $ch 401 {{"error":"invalid credential"}}
	} elseif {[string match */stream/* $path]} {
		puts -nonewline $ch "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n"
		# Both HTTP chunk framing and NDJSON/UTF-8 characters are split.
		set bytes [encoding convertto utf-8 "\n\r\n{\"type\":\"test\",\"name\":\"Bób\"}\n{\"type\":\"second\"}\n"]
		set raw "[format %x [string length $bytes]];x=y\r\n$bytes\r\n0\r\n\r\n"
		set ::lichess::apitest::Stream $ch
		SendParts $ch $raw
	} elseif {$path eq "/api/account"} {
		Respond $ch 200 {{"id":"bob","username":"Bob"}}
	} elseif {$path eq "/api/challenge/ai"} {
		Respond $ch 200 {{"id":"game1234"}}
	} elseif {$path eq "/api/board/seek"} {
		puts -nonewline $ch "HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n\n"
		set ::lichess::apitest::Stream $ch
		fileevent $ch readable [list ::lichess::apitest::Read $ch]
	} else { Respond $ch 200 {{"ok":true}} }
}
proc ::lichess::apitest::SendParts {ch raw} {
	variable Mode
	variable Timers
	if {$raw eq {}} {
		if {$Mode ne "hold"} { catch {::close $ch}; catch {dict unset ::lichess::apitest::Connections $ch} }
		return
	}
	if {[catch {puts -nonewline $ch [string index $raw 0]}]} { return }
	lappend Timers [after 1 [list ::lichess::apitest::SendParts $ch [string range $raw 1 end]]]
}
proc ::lichess::apitest::Respond {ch code body} {
	puts -nonewline $ch "HTTP/1.1 $code Reply\r\nContent-Type: application/json\r\nContent-Length: [string length $body]\r\nConnection: close\r\n\r\n$body"
	::close $ch
	dict unset ::lichess::apitest::Connections $ch
}
proc ::lichess::apitest::Query {text} {
	set d {}
	foreach part [split $text &] {
		set i [string first = $part]
		dict set d [::lichess::api::Decode [string range $part 0 [expr {$i-1}]]] [::lichess::api::Decode [string range $part [expr {$i+1}] end]]
	}
	return $d
}
proc ::lichess::api::OpenBrowser {url} {
	set q [::lichess::apitest::Query [string range $url [expr {[string first ? $url]+1}] end]]
	set ::lichess::apitest::Challenge [dict get $q code_challenge]
	set ::lichess::apitest::Redirect [dict get $q redirect_uri]
	set ::lichess::apitest::OAuthValid [expr {[dict get $q scope] eq "board:play" &&
		[dict get $q response_type] eq "code" && [dict get $q code_challenge_method] eq "S256"}]
	set redirect [dict get $q redirect_uri]
	set state [dict get $q state]
	set param [expr {$::lichess::apitest::Mode eq "deny" ? {error access_denied} : {code local-code}}]
	if {$::lichess::apitest::Mode eq "badstate"} { set state wrong }
	::http::geturl "$redirect?[::http::formatQuery {*}$param state $state]" -command ::lichess::apitest::BrowserDone
}
proc ::lichess::apitest::BrowserDone {h} { ::http::cleanup $h; set ::lichess::apitest::BrowserVisited 1 }
proc ::lichess::apitest::Event {d} { lappend ::lichess::apitest::Events $d }

namespace eval ::lichess::apitest {
	tcltest::test lichess-api-pkce-vector {RFC 7636 and pure Tcl fallback agree} -body {
		set verifier dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk
		list [::lichess::api::Challenge $verifier] [::lichess::api::Base64 [::lichess::api::Sha256 $verifier]] \
			[expr {[string length [::lichess::api::Random]] == 43}]
	} -result {E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM 1}

	tcltest::test lichess-api-pure-stream {framing and line parser accept every possible byte boundary} -body {
		set Events {}
		dict set ::lichess::api::Requests pure [dict create cmd ::lichess::apitest::Event stream 1 timer {} buffer {} wire {} chunk -1]
		set bytes [encoding convertto utf-8 "\n\r\n{\"type\":\"test\",\"name\":\"Bób\"}\n{\"type\":\"second\"}\n"]
		set raw "[format %x [string length $bytes]];x=y\r\n$bytes\r\n0\r\n\r\n"
		foreach byte [split $raw {}] {
			set wire [dict get $::lichess::api::Requests pure wire]
			append wire $byte
			dict set ::lichess::api::Requests pure wire $wire
			::lichess::api::Dechunk pure 1
		}
		update
		set chunk [dict get $::lichess::api::Requests pure chunk]
		::lichess::api::Finish pure [dict create ok 1 error closed]
		update
		list [dict get [lindex $Events 0] name] [dict get [lindex $Events 1] type] \
			[dict get [lindex $Events 2] type] $chunk
	} -cleanup {
		catch {dict unset ::lichess::api::Requests pure}
	} -result {Bób second closed -2}

	tcltest::test lichess-api-pure-errors {HTTP status/JSON errors are local messages and never echo credentials} -body {
		set outcomes {}
		foreach code {200 400 401 429} {
			set Events {}
			dict set ::lichess::api::Requests pure [dict create cmd ::lichess::apitest::Event stream 0 timer {}]
			array set ::http::lichessTest [list http "HTTP/1.1 $code Reply" status ok body {not json: test-secret}]
			::lichess::api::Done pure ::http::lichessTest
			update
			set r [lindex $Events 0]
			lappend outcomes [dict get $r ok] [dict get $r status] [expr {[string first test-secret [dict get $r error]] < 0}]
		}
		set outcomes
	} -cleanup {
		set ::lichess::api::BackoffUntil 0
		catch {unset ::http::lichessTest}
	} -result {0 200 1 0 400 1 0 401 1 0 429 1}

	tcltest::test lichess-api-auth {real loopback PKCE and account, credential store seams} -setup { Start } -body {
		set auth [Call signIn]
		set account [Call account]
		set bad [Call useToken invalid]
		list [dict get $auth ok] [dict get $auth username] $ExchangeValid $OAuthValid \
			[dict get $account id] [dict get $bad status] [expr {$Stored eq "test-secret"}] \
			[::lichess::api::signedIn?]
	} -cleanup { Stop } -result {1 Bob 1 1 bob 401 1 1}

	tcltest::test lichess-api-denied {OAuth denial completes once and closes the listener} -setup { Start; set Mode deny } -body {
		set r [Call signIn]
		list [dict get $r ok] [expr {$::lichess::api::Auth eq {}}] [::lichess::api::signedIn?]
	} -cleanup { Stop } -result {0 1 0}

	tcltest::test lichess-api-state {wrong state does not exchange a code; signOut cancels pending auth} -setup { Start; set Mode badstate } -body {
		unset -nocomplain Result
		set BrowserVisited 0
		::lichess::api::signIn [list set ::lichess::apitest::Result]
		Wait {$BrowserVisited && [llength [dict get $::lichess::api::Auth clients]] == 0}
		::lichess::api::signOut
		Wait {[info exists Result]}
		list [dict get $Result ok] [llength $Seen] [::lichess::api::signedIn?]
	} -cleanup { Stop } -result {0 0 0}

	tcltest::test lichess-api-stream {NDJSON, split HTTP chunks and UTF-8, keep-alives, EOF} -setup { Start; set Stored test-secret } -body {
		set h [::lichess::api::streamEvents ::lichess::apitest::Event]
		Wait {[llength $Events] == 3}
		list [dict get [lindex $Events 0] type] [dict get [lindex $Events 0] name] \
			[dict get [lindex $Events 1] type] [dict get [lindex $Events 2] type] \
			[dict exists $::lichess::api::Requests $h]
	} -cleanup { Stop } -result {test Bób second closed 0}

	tcltest::test lichess-api-close {closing game/seek handles is idempotent and signals closure} -setup { Start; set Stored test-secret; set Mode hold } -body {
		set h [::lichess::api::streamGame game1234 ::lichess::apitest::Event]
		Wait {[llength $Events] == 2}
		::lichess::api::close $h
		::lichess::api::close $h
		Wait {[llength $Events] == 3}
		set s [::lichess::api::seek 10 2 false black ::lichess::apitest::Event]
		Wait {[llength $Seen] == 2}
		::lichess::api::close $s
		Wait {[llength $Events] == 4}
		list [dict get [lindex $Events 2] type] [dict get [lindex $Events 3] type] \
			[lindex $Seen 0 1] [lindex $Seen 1 2]
	} -cleanup { Stop } -result {closed closed /api/board/game/stream/game1234 time=10&increment=2&rated=false&color=black}

	tcltest::test lichess-api-actions {AI form and every board POST path, no response token in errors} -setup { Start; set Stored test-secret } -body {
		set ai [Call challengeAi 3 5 2 white]
		set oks {}
		foreach args {{move game1234 e2e4} {resign game1234} {abort game1234} {draw game1234 yes} {draw game1234 no} {claimVictory game1234}} {
			lappend oks [dict get [Call {*}$args] ok]
		}
		set Status 400
		set bad [Call move game1234 e2e4]
		set paths [lmap r [lrange $Seen 1 6] {lindex $r 1}]
		list [dict get $ai id] [lindex $Seen 0 2] $oks $paths [dict get $bad status] \
			[expr {[string first $Stored [dict get $bad error]] < 0}]
	} -cleanup { Stop } -result {game1234 level=3&clock.limit=300&clock.increment=2&color=white {1 1 1 1 1 1} {/api/board/game/game1234/move/e2e4 /api/board/game/game1234/resign /api/board/game/game1234/abort /api/board/game/game1234/draw/yes /api/board/game/game1234/draw/no /api/board/game/game1234/claim-victory} 400 1}

	tcltest::test lichess-api-429 {global one-minute cooldown delays new requests and allows cancellation} -setup { Start; set Stored test-secret } -body {
		set Status 429
		set limited [Call account]
		set remaining [expr {$::lichess::api::BackoffUntil-[clock milliseconds]}]
		set h [::lichess::api::streamEvents ::lichess::apitest::Event]
		update
		set noRequest [expr {[llength $Seen] == 1}]
		::lichess::api::close $h
		Wait {[llength $Events] == 1}
		# Move the clock seam forward; no one-minute sleep in the suite.
		set ::lichess::api::BackoffUntil 0
		set account [Call account]
		list [dict get $limited status] [expr {$remaining > 59000 && $remaining <= 60000}] \
			$noRequest [dict get $account ok] [expr {[string first $Stored [dict get $limited error]] < 0}]
	} -cleanup { Stop } -result {429 1 1 1 1}
}

::lichess::api::signOut
foreach name {TokenStore TokenLoad TokenDelete OpenBrowser} {
	rename ::lichess::api::$name {}
	rename ::lichess::apitest::Original$name ::lichess::api::$name
}
tcltest::cleanupTests
