# ======================================================================
# Loopback Lichess Board API server for app tests.
#
# No request headers or token-form values are retained.  In particular the
# request journal contains only an authorized boolean, never a bearer token.
# ======================================================================

package require http 2.7
package require json

namespace eval ::lichess::fake {
	variable Listener {}
	variable Port 0
	variable Serial 0
	variable Token {}
	variable Connections {}
	variable Requests {}
	variable AuthCodes {}
	variable Games {}
	variable EventStreams {}
	variable EventQueue {}
	variable GameStreams {}
	variable Timers {}
	variable Forced {}
	variable NextReplies {}
	variable SeekCancellations 0
	variable Options
}

proc ::lichess::fake::Start {} {
	variable Listener
	variable Port
	if {$Listener ne {}} { Stop }
	ClearState
	set Listener [socket -server ::lichess::fake::Accept -myaddr 127.0.0.1 0]
	set Port [lindex [fconfigure $Listener -sockname] 2]
	return "http://127.0.0.1:$Port"
}

proc ::lichess::fake::Base {} {
	variable Port
	return "http://127.0.0.1:$Port"
}

proc ::lichess::fake::ClearState {} {
	variable Serial
	variable Token
	variable Connections
	variable Requests
	variable AuthCodes
	variable Games
	variable EventStreams
	variable EventQueue
	variable GameStreams
	variable Timers
	variable Forced
	variable NextReplies
	variable SeekCancellations
	variable Options
	set Serial 0
	set Token {}
	set Connections {}
	set Requests {}
	set AuthCodes {}
	set Games {}
	set EventStreams {}
	set EventQueue {}
	set GameStreams {}
	set Timers {}
	set Forced {}
	set NextReplies {}
	set SeekCancellations 0
	array set Options {
		pairDelay 60
		replyDelay 30
		seekCloseDelay 100
		keepAlive 200
		oauthDeny 0
		autoAcceptDraw 1
	}
}

proc ::lichess::fake::Stop {} {
	variable Listener
	variable Port
	variable Connections
	variable Timers
	foreach timer [dict keys $Timers] { catch {after cancel $timer} }
	foreach {chan connection} $Connections {
		if {[dict exists $connection timer]} {
			catch {after cancel [dict get $connection timer]}
		}
		catch {fileevent $chan readable {}}
		catch {close $chan}
	}
	if {$Listener ne {}} { catch {close $Listener} }
	set Listener {}
	set Port 0
	ClearState
}

proc ::lichess::fake::Set {name value} {
	variable Options
	if {![info exists Options($name)]} { error "unknown fake-server option: $name" }
	set Options($name) $value
}

proc ::lichess::fake::DenyNextOAuth {} {
	variable Options
	set Options(oauthDeny) 1
}

# Force one response.  pattern is a glob matched against the URL path.
proc ::lichess::fake::ForceNext {pattern status} {
	variable Forced
	lappend Forced [dict create pattern $pattern status $status]
}

# Replies are UCI moves made by the opponent of the next created game.
proc ::lichess::fake::ScriptNextGame {replies} {
	variable NextReplies
	set NextReplies $replies
}

proc ::lichess::fake::SetGameReplies {gameId replies} {
	variable Games
	if {![dict exists $Games $gameId]} { error "unknown fake game: $gameId" }
	dict set Games $gameId replies $replies
	dict set Games $gameId replyIndex 0
}

proc ::lichess::fake::RejectNextMove {gameId} {
	variable Games
	if {![dict exists $Games $gameId]} { error "unknown fake game: $gameId" }
	dict set Games $gameId rejectNext 1
}

proc ::lichess::fake::OpponentGone {gameId {seconds 0}} {
	variable Games
	if {![dict exists $Games $gameId]} { error "unknown fake game: $gameId" }
	dict set Games $gameId claimable 1
	EmitGame $gameId [dict create type opponentGone gone true claimWinInSeconds $seconds]
}

proc ::lichess::fake::Requests {} {
	variable Requests
	return $Requests
}

proc ::lichess::fake::ClearRequests {} {
	variable Requests
	set Requests {}
}

proc ::lichess::fake::SeekCancellations {} {
	variable SeekCancellations
	return $SeekCancellations
}

proc ::lichess::fake::Game {gameId} {
	variable Games
	if {![dict exists $Games $gameId]} { error "unknown fake game: $gameId" }
	return [dict get $Games $gameId]
}

proc ::lichess::fake::Accept {chan address port} {
	variable Connections
	fconfigure $chan -blocking 0 -buffering none -translation binary -encoding binary
	dict set Connections $chan [dict create buffer {} address $address kind request]
	fileevent $chan readable [list ::lichess::fake::Read $chan]
}

proc ::lichess::fake::Read {chan} {
	variable Connections
	if {![dict exists $Connections $chan]} { return }
	set incoming [read $chan]
	if {[string length $incoming]} {
		set buffer [dict get $Connections $chan buffer]
		append buffer $incoming
		dict set Connections $chan buffer $buffer
	}
	if {[eof $chan]} {
		Disconnect $chan
		return
	}
	set connection [dict get $Connections $chan]
	if {[dict get $connection kind] ne "request"} { return }
	if {![dict exists $connection headersDone]} {
		set buffer [dict get $connection buffer]
		set end [string first "\r\n\r\n" $buffer]
		set separator 4
		if {$end < 0} {
			set end [string first "\n\n" $buffer]
			set separator 2
		}
		if {$end < 0} { return }
		set head [string range $buffer 0 [expr {$end - 1}]]
		set buffer [string range $buffer [expr {$end + $separator}] end]
		set lines [split $head "\n"]
		set requestLine [string trimright [lindex $lines 0] "\r"]
		if {[llength $requestLine] < 2} {
			Disconnect $chan
			return
		}
		set method [lindex $requestLine 0]
		set target [lindex $requestLine 1]
		set headers {}
		foreach line [lrange $lines 1 end] {
			set line [string trimright $line "\r"]
			set colon [string first ":" $line]
			if {$colon < 1} { continue }
			set name [string tolower [string trim [string range $line 0 [expr {$colon - 1}]]]]
			set value [string trim [string range $line [expr {$colon + 1}] end]]
			dict set headers $name $value
		}
		dict set connection headersDone 1
		dict set connection method $method
		dict set connection target $target
		dict set connection headers $headers
		dict set connection buffer $buffer
		dict set Connections $chan $connection
	}
	set length 0
	if {[dict exists $connection headers content-length]} {
		set length [dict get $connection headers content-length]
	}
	if {[string length [dict get $connection buffer]] < $length} { return }
	dict set connection body [string range [dict get $connection buffer] 0 [expr {$length - 1}]]
	dict set Connections $chan $connection
	fileevent $chan readable {}
	Handle $chan
	if {[dict exists $Connections $chan]} {
		set kind [dict get $Connections $chan kind]
		if {$kind ne "request"} {
			fileevent $chan readable [list ::lichess::fake::Read $chan]
		}
	}
}

proc ::lichess::fake::Disconnect {chan} {
	variable Connections
	variable EventStreams
	variable GameStreams
	variable SeekCancellations
	if {![dict exists $Connections $chan]} { return }
	set connection [dict get $Connections $chan]
	if {[dict exists $connection timer]} { catch {after cancel [dict get $connection timer]} }
	if {[dict exists $connection pairTimer]} { catch {after cancel [dict get $connection pairTimer]} }
	if {[dict get $connection kind] eq "seek"
	 && (![dict exists $connection paired] || ![dict get $connection paired])} {
		incr SeekCancellations
	}
	set index [lsearch -exact $EventStreams $chan]
	if {$index >= 0} { set EventStreams [lreplace $EventStreams $index $index] }
	if {[dict exists $connection gameId]} {
		set gameId [dict get $connection gameId]
		if {[dict exists $GameStreams $gameId]} {
			set streams [dict get $GameStreams $gameId]
			set index [lsearch -exact $streams $chan]
			if {$index >= 0} {
				set streams [lreplace $streams $index $index]
				dict set GameStreams $gameId $streams
			}
		}
	}
	dict unset Connections $chan
	catch {fileevent $chan readable {}}
	catch {close $chan}
}

proc ::lichess::fake::Handle {chan} {
	variable Connections
	variable Requests
	variable Token
	variable Forced
	variable Options
	if {![dict exists $Connections $chan]} { return }
	set connection [dict get $Connections $chan]
	set method [dict get $connection method]
	set target [dict get $connection target]
	set queryAt [string first "?" $target]
	if {$queryAt >= 0} {
		set path [string range $target 0 [expr {$queryAt - 1}]]
		set query [ParseQuery [string range $target [expr {$queryAt + 1}] end]]
	} else {
		set path $target
		set query {}
	}
	set form {}
	if {$method eq "POST"} { set form [ParseQuery [dict get $connection body]] }
	set authorization {}
	if {[dict exists $connection headers authorization]} {
		set authorization [dict get $connection headers authorization]
	}
	set authorized [expr {$Token ne {} && $authorization eq "Bearer $Token"}]
	set journalQuery $query
	set journalForm $form
	if {$path eq "/api/token"} {
		foreach name {code code_verifier} {
			if {[dict exists $journalForm $name]} { dict set journalForm $name <redacted> }
		}
	}
	lappend Requests [dict create \
		method $method path $path query $journalQuery form $journalForm authorized $authorized]

	set forcedIndex -1
	set forcedStatus 0
	for {set i 0} {$i < [llength $Forced]} {incr i} {
		set rule [lindex $Forced $i]
		if {[string match [dict get $rule pattern] $path]} {
			set forcedIndex $i
			set forcedStatus [dict get $rule status]
			break
		}
	}
	if {$forcedIndex >= 0} {
		set Forced [lreplace $Forced $forcedIndex $forcedIndex]
		if {$forcedStatus == 429} {
			Respond $chan 429 {{"error":"Too many requests"}} application/json {Retry-After 60}
		} else {
			Respond $chan $forcedStatus {{"error":"Request failed"}} application/json
		}
		return
	}

	if {$path eq "/oauth" && $method eq "GET"} {
		OAuth $chan $query
		return
	}
	if {$path eq "/api/token" && $method eq "POST"} {
		TokenRequest $chan $form
		return
	}
	if {!$authorized} {
		Respond $chan 401 {{"error":"Unauthorized"}} application/json {WWW-Authenticate Bearer}
		return
	}

	if {$path eq "/api/account" && $method eq "GET"} {
		RespondJson $chan 200 [dict create id bob username Bob perfs [dict create rapid [dict create games 0 rating 1500]]]
	} elseif {$path eq "/api/stream/event" && $method eq "GET"} {
		StartEventStream $chan
	} elseif {$path eq "/api/board/seek" && $method eq "POST"} {
		StartSeek $chan $form
	} elseif {$path eq "/api/challenge/ai" && $method eq "POST"} {
		set color [DictGet $form color random]
		if {$color eq "random"} { set color white }
		set limit [DictGet $form clock.limit 600]
		set increment [DictGet $form clock.increment 0]
		set level [DictGet $form level 1]
		set gameId [CreateGame $color ai $level $limit $increment]
		RespondJson $chan 200 [dict create id $gameId]
		Later $Options(pairDelay) [list ::lichess::fake::AnnounceGame $gameId]
	} elseif {[regexp {^/api/board/game/stream/([^/]+)$} $path -> gameId] && $method eq "GET"} {
		StartGameStream $chan $gameId
	} elseif {[regexp {^/api/board/game/([^/]+)/move/([^/]+)$} $path -> gameId uci] && $method eq "POST"} {
		Move $chan $gameId [UrlDecode $uci]
	} elseif {[regexp {^/api/board/game/([^/]+)/(resign|abort|claim-victory)$} $path -> gameId action] && $method eq "POST"} {
		GameAction $chan $gameId $action
	} elseif {[regexp {^/api/board/game/([^/]+)/draw/(yes|no)$} $path -> gameId answer] && $method eq "POST"} {
		Draw $chan $gameId $answer
	} else {
		Respond $chan 404 {{"error":"Not found"}} application/json
	}
}

proc ::lichess::fake::DictGet {dict name fallback} {
	if {[dict exists $dict $name]} { return [dict get $dict $name] }
	return $fallback
}

proc ::lichess::fake::ParseQuery {text} {
	set result {}
	foreach part [split $text "&"] {
		if {$part eq {}} { continue }
		set equals [string first "=" $part]
		if {$equals < 0} {
			dict set result [UrlDecode $part] {}
		} else {
			dict set result [UrlDecode [string range $part 0 [expr {$equals - 1}]]] \
				[UrlDecode [string range $part [expr {$equals + 1}] end]]
		}
	}
	return $result
}

proc ::lichess::fake::UrlDecode {text} {
	set text [string map [list + " "] $text]
	set result {}
	while {[regexp {^([^%]*)%([0-9A-Fa-f]{2})(.*)$} $text -> prefix hex rest]} {
		append result $prefix [binary decode hex $hex]
		set text $rest
	}
	append result $text
	return [encoding convertfrom utf-8 $result]
}

# The fixture owns the wire schema: Tcl dict2json expects pre-encoded values.
# Never infer JSON object/string types from a Tcl value's list representation.
proc ::lichess::fake::JsonString {value} {
	set result {"}
	foreach char [split $value {}] {
		scan $char %c code
		if {$char eq {"}} { append result {\"}
		} elseif {$code == 92} { append result {\\}
		} elseif {$code < 32} { append result [format {\u%04x} $code]
		} else { append result $char }
	}
	append result {"}
	return $result
}

proc ::lichess::fake::Json {value} {
	set pairs {}
	foreach {key val} $value {
		if {$key in {game opponent perfs rapid clock white black state}} {
			set encoded [Json $val]
		} elseif {$key in {rated isMyTurn wdraw bdraw gone}} {
			set encoded [expr {$val ? "true" : "false"}]
		} elseif {$key in {ai aiLevel rating games secondsLeft initial increment wtime btime winc binc claimWinInSeconds expires_in}} {
			if {$val ne "null" && ![string is integer -strict $val]} { error "invalid numeric fixture field" }
			set encoded $val
		} else { set encoded [JsonString $val] }
		lappend pairs "[JsonString $key]:$encoded"
	}
	return "\{[join $pairs ,]\}"
}

proc ::lichess::fake::RespondJson {chan status body} {
	Respond $chan $status [encoding convertto utf-8 [::lichess::fake::Json $body]] application/json
}

proc ::lichess::fake::Respond {chan status body {contentType text/plain} {extraHeaders {}}} {
	set reasons [list 200 OK 302 Found 400 {Bad Request} 401 Unauthorized 404 {Not Found} 429 {Too Many Requests} 500 {Internal Server Error}]
	set reason [DictGet $reasons $status Error]
	set head "HTTP/1.1 $status $reason\r\n"
	append head "Content-Type: $contentType\r\n"
	append head "Content-Length: [string length $body]\r\n"
	append head "Connection: close\r\n"
	foreach {name value} $extraHeaders { append head "$name: $value\r\n" }
	append head "\r\n"
	WriteRaw $chan "$head$body"
	Disconnect $chan
}

proc ::lichess::fake::Redirect {chan location} {
	set head "HTTP/1.1 302 Found\r\nLocation: $location\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
	WriteRaw $chan $head
	Disconnect $chan
}

proc ::lichess::fake::WriteRaw {chan text} {
	variable Connections
	if {![dict exists $Connections $chan]} { return 0 }
	if {[catch {puts -nonewline $chan $text; flush $chan}]} {
		Disconnect $chan
		return 0
	}
	return 1
}

proc ::lichess::fake::OAuth {chan query} {
	variable Options
	variable AuthCodes
	variable Serial
	set redirect [DictGet $query redirect_uri {}]
	set state [DictGet $query state {}]
	set separator [expr {[string first "?" $redirect] >= 0 ? "&" : "?"}]
	if {$Options(oauthDeny)} {
		set Options(oauthDeny) 0
		Redirect $chan "${redirect}${separator}[::http::formatQuery error access_denied state $state]"
		return
	}
	if {[DictGet $query response_type {}] ne "code"
	 || [DictGet $query client_id {}] ne "chesswiz"
	 || [DictGet $query code_challenge_method {}] ne "S256"
	 || $redirect eq {} || $state eq {}} {
		Respond $chan 400 {{"error":"invalid_request"}} application/json
		return
	}
	incr Serial
	set code "fake-code-$Serial"
	dict set AuthCodes $code [dict create \
		challenge [DictGet $query code_challenge {}] redirect $redirect state $state]
	Redirect $chan "${redirect}${separator}[::http::formatQuery code $code state $state]"
}

proc ::lichess::fake::PkceChallenge {verifier} {
	catch {package require sha256}
	if {![llength [info commands ::sha2::sha256]]} { catch {package require sha2} }
	set digest {}
	foreach command {::sha2::sha256 ::sha256::sha256} {
		if {[llength [info commands $command]]} {
			if {![catch {$command -bin -- $verifier} digest]} { break }
			if {![catch {$command -bin $verifier} digest]} { break }
		}
	}
	# the app bundles on Windows and macOS have no tcllib sha256: use the
	# client's own pure-Tcl digest (checked against RFC 7636 in its tests)
	if {$digest eq {} && [llength [info commands ::lichess::api::Sha256]]} {
		set digest [::lichess::api::Sha256 $verifier]
	}
	if {$digest eq {}} { error "a SHA-256 command is required" }
	set encoded [binary encode base64 -maxlen 0 $digest]
	return [string map [list + - / _ = {} \r {} \n {}] $encoded]
}

proc ::lichess::fake::TokenRequest {chan form} {
	variable AuthCodes
	variable Token
	variable Serial
	set code [DictGet $form code {}]
	if {![dict exists $AuthCodes $code]
	 || [DictGet $form grant_type {}] ne "authorization_code"
	 || [DictGet $form client_id {}] ne "chesswiz"} {
		Respond $chan 400 {{"error":"invalid_grant"}} application/json
		return
	}
	set grant [dict get $AuthCodes $code]
	set verifier [DictGet $form code_verifier {}]
	set valid [expr {$verifier ne {} && ![catch {PkceChallenge $verifier} challenge] && $challenge eq [dict get $grant challenge]}]
	if {!$valid || [DictGet $form redirect_uri {}] ne [dict get $grant redirect]} {
		Respond $chan 400 {{"error":"invalid_grant"}} application/json
		return
	}
	incr Serial
	set Token "lio_fake_[pid]_$Serial"
	dict unset AuthCodes $code
	RespondJson $chan 200 [dict create token_type Bearer access_token $Token expires_in 3600]
}

proc ::lichess::fake::Later {milliseconds command} {
	variable Timers
	set timer [after $milliseconds $command]
	dict set Timers $timer 1
	return $timer
}

proc ::lichess::fake::StartEventStream {chan} {
	variable Connections
	variable EventStreams
	variable EventQueue
	set connection [dict get $Connections $chan]
	dict set connection kind event
	dict set Connections $chan $connection
	lappend EventStreams $chan
	StartStream $chan
	foreach event $EventQueue { SendJson $chan $event }
	set EventQueue {}
}

proc ::lichess::fake::StartGameStream {chan gameId} {
	variable Connections
	variable GameStreams
	variable Games
	if {![dict exists $Games $gameId]} {
		Respond $chan 404 {{"error":"Not found"}} application/json
		return
	}
	set connection [dict get $Connections $chan]
	dict set connection kind game
	dict set connection gameId $gameId
	dict set Connections $chan $connection
	dict lappend GameStreams $gameId $chan
	StartStream $chan
	SendJson $chan [GameFull $gameId]
	set game [dict get $Games $gameId]
	if {[dict get $game color] eq "black" && [llength [dict get $game moves]] == 0} {
		ScheduleOpponent $gameId
	}
}

proc ::lichess::fake::StartSeek {chan form} {
	variable Connections
	variable Options
	set connection [dict get $Connections $chan]
	dict set connection kind seek
	dict set connection paired 0
	dict set connection seekForm $form
	dict set Connections $chan $connection
	StartStream $chan
	set timer [Later $Options(pairDelay) [list ::lichess::fake::PairSeek $chan]]
	dict set Connections $chan pairTimer $timer
}

proc ::lichess::fake::StartStream {chan} {
	variable Options
	set head "HTTP/1.1 200 OK\r\nContent-Type: application/x-ndjson\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
	WriteRaw $chan $head
	WriteRaw $chan "\n"
	set timer [Later $Options(keepAlive) [list ::lichess::fake::KeepAlive $chan]]
	dict set Connections $chan timer $timer
}

proc ::lichess::fake::KeepAlive {chan} {
	variable Connections
	variable Options
	if {![dict exists $Connections $chan]} { return }
	if {![WriteRaw $chan "\n"]} { return }
	set timer [Later $Options(keepAlive) [list ::lichess::fake::KeepAlive $chan]]
	dict set Connections $chan timer $timer
}

proc ::lichess::fake::SendJson {chan value} {
	return [WriteRaw $chan "[encoding convertto utf-8 [::lichess::fake::Json $value]]\n"]
}

proc ::lichess::fake::EmitEvent {event} {
	variable EventStreams
	variable EventQueue
	if {[llength $EventStreams] == 0} {
		lappend EventQueue $event
		return
	}
	foreach chan $EventStreams { SendJson $chan $event }
}

proc ::lichess::fake::EmitGame {gameId event} {
	variable GameStreams
	if {![dict exists $GameStreams $gameId]} { return }
	foreach chan [dict get $GameStreams $gameId] { SendJson $chan $event }
}

proc ::lichess::fake::PairSeek {chan} {
	variable Connections
	variable Options
	if {![dict exists $Connections $chan]} { return }
	set connection [dict get $Connections $chan]
	if {[dict get $connection kind] ne "seek" || [dict get $connection paired]} { return }
	set form [dict get $connection seekForm]
	set color [DictGet $form color random]
	if {$color eq "random"} { set color white }
	set minutes [DictGet $form time 10]
	set increment [DictGet $form increment 0]
	set gameId [CreateGame $color lobby 0 [expr {$minutes * 60}] $increment]
	dict set connection paired 1
	dict set connection gameId $gameId
	dict set Connections $chan $connection
	AnnounceGame $gameId
	Later $Options(seekCloseDelay) [list ::lichess::fake::Disconnect $chan]
}

proc ::lichess::fake::CreateGame {color source level limit increment} {
	variable Games
	variable Serial
	variable NextReplies
	incr Serial
	set gameId [format "cw%06d" $Serial]
	set opponent [dict create id ada username Ada rating 1500 ai null]
	set white [dict create id bob name Bob rating 1500]
	set black [dict create id ada name Ada rating 1500]
	if {$source eq "ai"} {
		set opponent [dict create id stockfish username Stockfish rating 1500 ai $level]
		if {$color eq "white"} {
			set black [dict create aiLevel $level]
		} else {
			set white [dict create aiLevel $level]
		}
	}
	if {$color eq "black"} {
		if {$source ne "ai"} { set white [dict create id ada name Ada rating 1500] }
		set black [dict create id bob name Bob rating 1500]
	}
	set initial [expr {$limit * 1000}]
	set inc [expr {$increment * 1000}]
	set replies $NextReplies
	set NextReplies {}
	set game [dict create \
		id $gameId fullId ${gameId}local color $color fen startpos source $source \
		opponent $opponent speed [expr {$limit < 480 ? "blitz" : "rapid"}] rated false \
		secondsLeft $limit initial $initial increment $inc white $white black $black \
		moves {} status started winner {} wtime $initial btime $initial winc $inc binc $inc \
		wdraw 0 bdraw 0 replies $replies replyIndex 0 rejectNext 0 claimable 0 timer {}]
	dict set Games $gameId $game
	return $gameId
}

proc ::lichess::fake::AnnounceGame {gameId} {
	variable Games
	if {![dict exists $Games $gameId]} { return }
	set game [dict get $Games $gameId]
	set descriptor [dict create \
		gameId $gameId fullId [dict get $game fullId] color [dict get $game color] \
		fen startpos isMyTurn [expr {[dict get $game color] eq "white"}] \
		opponent [dict get $game opponent] speed [dict get $game speed] \
		rated [dict get $game rated] secondsLeft [dict get $game secondsLeft] \
		source [dict get $game source]]
	EmitEvent [dict create type gameStart game $descriptor]
}

proc ::lichess::fake::GameState {gameId} {
	variable Games
	set game [dict get $Games $gameId]
	set state [dict create type gameState moves [join [dict get $game moves] " "] \
		wtime [dict get $game wtime] btime [dict get $game btime] \
		winc [dict get $game winc] binc [dict get $game binc] status [dict get $game status]]
	if {[dict get $game winner] ne {}} { dict set state winner [dict get $game winner] }
	if {[dict get $game wdraw]} { dict set state wdraw true }
	if {[dict get $game bdraw]} { dict set state bdraw true }
	return $state
}

proc ::lichess::fake::GameFull {gameId} {
	variable Games
	set game [dict get $Games $gameId]
	return [dict create type gameFull id $gameId rated [dict get $game rated] \
		speed [dict get $game speed] initialFen startpos \
		clock [dict create initial [dict get $game initial] increment [dict get $game increment]] \
		white [dict get $game white] black [dict get $game black] state [GameState $gameId]]
}

proc ::lichess::fake::Move {chan gameId uci} {
	variable Games
	variable Options
	if {![dict exists $Games $gameId]} {
		Respond $chan 404 {{"error":"Not found"}} application/json
		return
	}
	set game [dict get $Games $gameId]
	if {[dict get $game status] ne "started"} {
		Respond $chan 400 {{"error":"Not your turn, or game already over"}} application/json
		return
	}
	if {[dict get $game rejectNext]} {
		dict set Games $gameId rejectNext 0
		Respond $chan 400 {{"error":"Not your turn, or game already over"}} application/json
		return
	}
	set whiteTurn [expr {[llength [dict get $game moves]] % 2 == 0}]
	set myTurn [expr {([dict get $game color] eq "white") == $whiteTurn}]
	if {!$myTurn || ![regexp {^[a-h][1-8][a-h][1-8][qrbn]?$} $uci]} {
		Respond $chan 400 {{"error":"Not your turn, or game already over"}} application/json
		return
	}
	set moves [dict get $Games $gameId moves]
	lappend moves $uci
	dict set Games $gameId moves $moves
	if {$whiteTurn} {
		dict set Games $gameId wtime [expr {[dict get $game wtime] - 1000 + [dict get $game winc]}]
	} else {
		dict set Games $gameId btime [expr {[dict get $game btime] - 1000 + [dict get $game binc]}]
	}
	RespondJson $chan 200 [dict create ok true]
	EmitGame $gameId [GameState $gameId]
	ScheduleOpponent $gameId
}

proc ::lichess::fake::ScheduleOpponent {gameId} {
	variable Games
	variable Options
	if {![dict exists $Games $gameId]} { return }
	set game [dict get $Games $gameId]
	if {[dict get $game status] ne "started" || [dict get $game timer] ne {}} { return }
	if {[dict get $game replyIndex] >= [llength [dict get $game replies]]} { return }
	set timer [Later $Options(replyDelay) [list ::lichess::fake::OpponentMove $gameId]]
	dict set Games $gameId timer $timer
}

proc ::lichess::fake::OpponentMove {gameId} {
	variable Games
	if {![dict exists $Games $gameId]} { return }
	set game [dict get $Games $gameId]
	dict set Games $gameId timer {}
	if {[dict get $game status] ne "started"} { return }
	set index [dict get $game replyIndex]
	if {$index >= [llength [dict get $game replies]]} { return }
	set uci [lindex [dict get $game replies] $index]
	set moves [dict get $Games $gameId moves]
	lappend moves $uci
	dict set Games $gameId moves $moves
	dict set Games $gameId replyIndex [incr index]
	if {[llength [dict get $game moves]] % 2} {
		dict set Games $gameId wtime [expr {[dict get $game wtime] - 1000 + [dict get $game winc]}]
	} else {
		dict set Games $gameId btime [expr {[dict get $game btime] - 1000 + [dict get $game binc]}]
	}
	EmitGame $gameId [GameState $gameId]
}

proc ::lichess::fake::GameAction {chan gameId action} {
	variable Games
	if {![dict exists $Games $gameId]} {
		Respond $chan 404 {{"error":"Not found"}} application/json
		return
	}
	set game [dict get $Games $gameId]
	if {[dict get $game status] ne "started"} {
		Respond $chan 400 {{"error":"Game already over"}} application/json
		return
	}
	switch -- $action {
		resign {
			RespondJson $chan 200 [dict create ok true]
			Finish $gameId resign [expr {[dict get $game color] eq "white" ? "black" : "white"}]
		}
		abort {
			RespondJson $chan 200 [dict create ok true]
			Finish $gameId aborted {}
		}
		claim-victory {
			if {![dict get $game claimable]} {
				Respond $chan 400 {{"error":"No victory to claim"}} application/json
				return
			}
			RespondJson $chan 200 [dict create ok true]
			Finish $gameId timeout [dict get $game color]
		}
	}
}

proc ::lichess::fake::Draw {chan gameId answer} {
	variable Games
	variable Options
	if {![dict exists $Games $gameId]} {
		Respond $chan 404 {{"error":"Not found"}} application/json
		return
	}
	set game [dict get $Games $gameId]
	if {[dict get $game status] ne "started"} {
		Respond $chan 400 {{"error":"Game already over"}} application/json
		return
	}
	set field [expr {[dict get $game color] eq "white" ? "wdraw" : "bdraw"}]
	dict set Games $gameId $field [expr {$answer eq "yes"}]
	RespondJson $chan 200 [dict create ok true]
	EmitGame $gameId [GameState $gameId]
	if {$answer eq "yes" && $Options(autoAcceptDraw)} {
		Later $Options(replyDelay) [list ::lichess::fake::Finish $gameId draw {}]
	}
}

proc ::lichess::fake::Finish {gameId status winner} {
	variable Games
	if {![dict exists $Games $gameId]} { return }
	set game [dict get $Games $gameId]
	if {[dict get $game status] ne "started"} { return }
	if {[dict get $game timer] ne {}} { catch {after cancel [dict get $game timer]} }
	dict set Games $gameId timer {}
	dict set Games $gameId status $status
	dict set Games $gameId winner $winner
	EmitGame $gameId [GameState $gameId]
	set game [dict get $Games $gameId]
	set descriptor [dict create gameId $gameId fullId [dict get $game fullId] \
		color [dict get $game color] fen startpos isMyTurn false opponent [dict get $game opponent] \
		speed [dict get $game speed] rated [dict get $game rated] secondsLeft [dict get $game secondsLeft] \
		source [dict get $game source]]
	EmitEvent [dict create type gameFinish game $descriptor]
}

# vi:set ts=3 sw=3:
