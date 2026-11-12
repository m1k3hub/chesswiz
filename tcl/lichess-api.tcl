# ======================================================================
# Asynchronous Lichess Board API. Credentials never enter options or logs.
# All public callbacks receive one dict; transport errors are local text,
# never untrusted response bodies (which can echo a bearer credential).
# ======================================================================

package require http 2.7
package require json

namespace eval ::lichess::api {
	variable Base https://lichess.org
	variable Serial 0
	variable Requests {}
	variable BackoffUntil 0
	variable Auth {}
	variable Epoch 0
	variable Mode board
	variable StallTimeout 20000
	variable ReconnectDelays {1000 3000 9000}
	variable RecoveryTimeout 30000
	variable Deliveries {}
	namespace eval mc {
		set Network "Could not complete the Lichess request."
		set Unauthorized "Lichess rejected the credential. Sign in again."
		set Limited "Lichess rate limit reached. Please wait %d seconds."
		set Server "Lichess server error (%d)"
		set Unexpected "Lichess unexpected response (%d)"
		set InvalidToken "Invalid Lichess token. Please check it and try again."
		set Reconnecting "Reconnecting to Lichess…"
		set Lost "Lichess connection lost."
		set ServerReconnecting "Lichess server error (%d) — reconnecting…"
		set ServerLost "Lichess server error (%d) — connection lost."
		set Retry "Retry"
		set Invalid "Lichess returned an invalid response."
		set Rejected "Lichess rejected the request."
	set Forbidden "Lichess refused: the sign-in lacks permission for this. Sign out and sign in again."
		set NoCloud "No cloud evaluation for this position."
		set Cancelled "Lichess request cancelled."
		set Closed "Lichess stream closed."
		set SignIn "Lichess sign in failed. You can use a personal token instead."
	}
}

# Windows and macOS keep the token in the OS credential store. Linux has
# none here, so it goes in a file only the user can read, like the AI keys
# (::application::ai::KeyFile).
proc ::lichess::api::OsStore {} {
	return [expr {$::tcl_platform(platform) eq "windows" || $::tcl_platform(os) eq "Darwin"}]
}
proc ::lichess::api::TokenFile {} {
	if {![info exists ::scidb::dir::user]} { error "no user directory" }
	return [file join $::scidb::dir::user config lichess-token]
}
proc ::lichess::api::TokenStore {tok} {
	if {[OsStore]} { return [::scidb::sys::credential set Chesswiz lichess $tok] }
	set file [TokenFile]
	file mkdir [file dirname $file]
	# created private before the token is written into it
	set f [::open $file {WRONLY CREAT TRUNC} 0600]
	try { puts -nonewline $f $tok } finally { ::close $f }
	catch { file attributes $file -permissions 0600 }
}
proc ::lichess::api::TokenLoad {} {
	if {[OsStore]} { return [::scidb::sys::credential get Chesswiz lichess] }
	set file [TokenFile]
	if {![file readable $file]} { return "" }
	set f [::open $file r]
	try { return [string trim [read $f]] } finally { ::close $f }
}
proc ::lichess::api::TokenDelete {} {
	if {[OsStore]} { return [::scidb::sys::credential delete Chesswiz lichess] }
	file delete [TokenFile]
}
# The URL is already query-encoded: ::web::open would escape each '&', and
# cmd.exe's start would split the query at it, so neither may see it.
proc ::lichess::api::OpenBrowser {url} {
	if {$::tcl_platform(platform) eq "windows"} {
		exec rundll32 url.dll,FileProtocolHandler $url &
	} elseif {$::tcl_platform(os) eq "Darwin"} {
		exec open $url &
	} else {
		exec xdg-open $url &
	}
}
proc ::lichess::api::token {} {
	if {[catch {TokenLoad} tok]} { return {} }
	return $tok
}
proc ::lichess::api::signedIn? {} { expr {[token] ne {}} }

proc ::lichess::api::Reply {cmd reply} {
	# A caller exception must not escape through http::Finish, whose error
	# options can contain request headers. Deliver outside the HTTP stack.
	after 0 [list ::lichess::api::Deliver $cmd $reply]
}
proc ::lichess::api::Deliver {cmd reply} {
	catch {uplevel #0 [list {*}$cmd $reply]}
}

proc ::lichess::api::signOut {} {
	variable Epoch
	variable Requests
	variable Auth
	incr Epoch
	if {$Auth ne {}} { AuthFinish [dict create ok 0 error $::lichess::api::mc::Cancelled] }
	foreach id [dict keys $Requests] { close $id }
	catch {TokenDelete}
}

# A handle exists before the asynchronous connection starts, so closing a
# queued request is safe, including while the global 429 cooldown is active.
proc ::lichess::api::Request {method path form cmd {stream 0} {bearer {}} {contentType application/x-www-form-urlencoded} {response json}} {
	variable Serial
	variable Requests
	variable Base
	set id request[incr Serial]
	variable Deliveries
	dict set Deliveries $id 0
	dict set Requests $id [dict create method $method url "[string trimright $Base /]$path" \
		form $form cmd $cmd stream $stream bearer $bearer contentType $contentType response $response http {} timer {} watchdog {} deadline {} lastActivity 0 lost 0 attempts 0 generation 0 authenticated 0 epoch 0 \
		validation [expr {[lindex $cmd 0] eq "::lichess::api::Validated"}] buffer {} wire {} chunk -1]
	dict set Requests $id timer [after 0 [list ::lichess::api::Start $id]]
	return $id
}

proc ::lichess::api::Start {id} {
	variable Requests
	variable BackoffUntil
	variable mc
	if {![dict exists $Requests $id]} { return }
	set delay [expr {$BackoffUntil - [clock milliseconds]}]
	if {$delay > 0} {
		dict set Requests $id timer [after $delay [list ::lichess::api::Start $id]]
		return
	}
	dict set Requests $id timer {}
	dict set Requests $id startedAt [clock milliseconds]
	set r [dict get $Requests $id]
	set url [dict get $r url]
	set opts [list -method [dict get $r method] -binary 1 -keepalive 0 \
		-command [list ::lichess::api::Done $id] -timeout 30000]
	set bearer [dict get $r bearer]
	if {$bearer eq {}} { set bearer [token] }
	set accept application/json
	if {[dict get $r response] in {text pgn}} { set accept application/x-chess-pgn }
	if {[dict get $r response] eq "ndjson" || [dict get $r stream] && [dict get $r response] ne "pgn"} { set accept application/x-ndjson }
	set headers [list Accept $accept]
	# signed out: public endpoints answer, an empty bearer would be refused
	if {$bearer ne {}} { lappend headers Authorization "Bearer $bearer" }
	dict set Requests $id authenticated [expr {$bearer ne {}}]
	dict set Requests $id epoch $::lichess::api::Epoch
	lappend opts -headers $headers
	if {[dict get $r method] eq "POST"} {
		lappend opts -type [dict get $r contentType] -query [encoding convertto utf-8 [dict get $r form]]
	}
	if {[dict get $r stream]} {
		if {[dict get $r attempts] == 0} { dict set Requests $id lastActivity [clock milliseconds] }
		lappend opts -handler [list ::lichess::api::Read $id] -timeout 0
	}
	if {[catch {
		if {[string match -nocase https://* $url]} { ::platform::sys::tlsRegister }
		set h [::http::geturl $url {*}$opts]
	}]} {
		if {[dict get $r stream]} { Reconnect $id } else { Finish $id [dict create ok 0 error $mc::Network status 0] }
		return
	}
	if {[dict exists $Requests $id]} {
		dict set Requests $id http $h
		if {[dict get $r stream]} {
			ArmWatchdog $id
		}
	}
}

# http's -handler provides raw body bytes, even for chunked replies.
# Buffer framing and UTF-8 bytes separately; decode only complete NDJSON
# lines, so a multi-byte character may span any number of socket reads.
proc ::lichess::api::Read {id sock h} {
	variable Requests
	set bytes [read $sock 65536]
	set count [string length $bytes]
	if {![dict exists $Requests $id]} { return $count }
	if {[::http::ncode $h] != 200} { return $count }
	if {$count > 0} { ArmWatchdog $id 1 }
	set chunked 0
	foreach {key value} [::http::meta $h] {
		if {[string equal -nocase $key Transfer-Encoding] && [string equal -nocase $value chunked]} {
			set chunked 1
		}
	}
	if {!$chunked} {
		Lines $id $bytes
		return $count
	}
	set wire [dict get $Requests $id wire]
	append wire $bytes
	dict set Requests $id wire $wire
	dict set Requests $id framed 1
	return [Dechunk $id $count]
}

proc ::lichess::api::Dechunk {id count} {
	variable Requests
	set r [dict get $Requests $id]
	set wire [dict get $r wire]
	if {[string length $wire] > 2097152} { error "Stream chunk too long" }
	set size [dict get $r chunk]
	set body {}
	while {1} {
		if {$size == -2} { break }
		if {$size == -1} {
			set end [string first "\r\n" $wire]
			if {$end < 0} { break }
			set line [string range $wire 0 [expr {$end - 1}]]
			if {![regexp {^([0-9a-fA-F]+)(;.*)?$} $line -> hex]} { error "Invalid stream framing" }
			scan $hex %x size
			set wire [string range $wire [expr {$end + 2}] end]
			if {$size == 0} { set size -2; break }
		}
		if {[string length $wire] < $size + 2} { break }
		if {[string range $wire $size [expr {$size + 1}]] ne "\r\n"} { error "Invalid stream framing" }
		append body [string range $wire 0 [expr {$size - 1}]]
		set wire [string range $wire [expr {$size + 2}] end]
		set size -1
	}
	dict set Requests $id wire $wire
	dict set Requests $id chunk $size
	Lines $id $body
	return $count
}

proc ::lichess::api::Lines {id bytes} {
	variable Requests
	if {[dict exists $Requests $id response] && [dict get $Requests $id response] eq "pgn"} {
		PgnLines $id $bytes
		return
	}
	set buffer [dict get $Requests $id buffer]
	append buffer $bytes
	while {[set end [string first \n $buffer]] >= 0} {
		set line [string trim [string range $buffer 0 [expr {$end - 1}]]]
		set buffer [string range $buffer [expr {$end + 1}] end]
		if {$line eq {}} { continue }
		if {[catch {ParseJson [encoding convertfrom utf-8 $line] object} event]} { error "Invalid stream response" }
		StreamReply $id $event
	}
	if {[string length $buffer] > 1048576} { error "Stream line too long" }
	dict set Requests $id buffer $buffer
}

proc ::lichess::api::Done {id h} {
	variable Requests
	variable BackoffUntil
	variable mc
	if {![dict exists $Requests $id]} { catch {::http::cleanup $h}; return }
	set code [::http::ncode $h]
	if {![string is integer -strict $code]} { set code 0 }
	set reply [dict create ok 0 error $mc::Network status $code]
	if {$code == 429} {
		set now [clock milliseconds]
		set until [expr {$now + 60000}]
		foreach {key value} [::http::meta $h] {
			if {![string equal -nocase $key Retry-After]} { continue }
			if {[regexp {^[0-9]+$} $value]} {
				set decimal [string trimleft $value 0]
				if {$decimal eq {}} { set decimal 0 }
				set until [expr {$now + $decimal * 1000}]
			} elseif {![catch {clock scan $value -format {%a, %d %b %Y %H:%M:%S GMT} -locale en -gmt 1} date]} {
				set until [expr {max($now, $date * 1000)}]
			}
		}
		set seconds [expr {($until - $now + 999) / 1000}]
		set BackoffUntil [expr {max($BackoffUntil, $until)}]
		dict set reply error [format $mc::Limited $seconds]
		Notice [dict get $reply error]
	} elseif {$code == 401} {
		dict set reply error [expr {[dict get $Requests $id validation] ? $mc::InvalidToken : $mc::Unauthorized}]
	} elseif {$code >= 200 && $code < 300 && [::http::status $h] eq "ok"} {
		if {[dict get $Requests $id stream]} {
			if {[dict exists $Requests $id framed] && [dict get $Requests $id chunk] != -2} {
				::http::cleanup $h
				Finish $id [dict create ok 0 status $code error $mc::Invalid]
				return
			}
			set tail [dict get $Requests $id buffer]
			if {[string trim $tail] ne {}} {
				if {[catch {
					if {[dict exists $Requests $id response] && [dict get $Requests $id response] eq "pgn"} { PgnLines $id {} 1 } else { Lines $id \n }
				}]} {
					::http::cleanup $h
					Finish $id [dict create ok 0 status $code error $mc::Invalid]
					return
				}
			}
			set reply [dict create ok 1 status $code error $mc::Closed]
		} elseif {[catch {
			set response json
			if {[dict exists $Requests $id response]} { set response [dict get $Requests $id response] }
			set body [encoding convertfrom utf-8 [::http::data $h]]
			switch $response {
				text { set data $body }
				ndjson {
					set data {}
					foreach line [split $body \n] {
						if {[string trim $line] eq {}} { continue }
						lappend data [ParseJson $line object]
					}
				}
				array { set data [ParseJson $body array] }
				default { set data [ParseJson $body object] }
			}
		} dataError]} {
			dict set reply error $mc::Invalid
		} else {
			set reply [dict create ok 1 data $data status $code]
		}
	} elseif {$code >= 500 && $code <= 599} {
		dict set reply error [format $mc::Server $code]
	} elseif {$code >= 300 && $code <= 399} {
		dict set reply error [format $mc::Unexpected $code]
	} elseif {$code >= 400} {
		dict set reply error [expr {$code == 403 ? $mc::Forbidden : $mc::Rejected}]
		if {$code == 404 && [dict exists $Requests $id url] && [string match */api/cloud-eval?* [dict get $Requests $id url]]} {
			dict set reply error $mc::NoCloud
		}
	}
	set r [dict get $Requests $id]
	::http::cleanup $h
	dict set Requests $id http {}
	# A successful HTTP response does not mean an open-ended feed is done.
	set eof [expr {[dict get $r stream] && [dict get $reply ok] && ![StreamComplete $id]}]
	if {$eof} {
		# Short connections may send valid data before every EOF. Keep their
		# recovery budget across those reads, otherwise they retry forever.
		if {![dict exists $r eofSince]} { dict set Requests $id eofSince [clock milliseconds] }
		set attempts [dict get $r attempts]
		if {[dict exists $r eofAttempts]} { set attempts [expr {max($attempts, [dict get $r eofAttempts])}] }
		dict set Requests $id attempts $attempts
		dict set Requests $id eofAttempts [expr {$attempts + 1}]
	}
	if {[dict get $r stream] && ($eof || $code == 0 || $code >= 500 && $code <= 599)} {
		if {$code >= 500} {
			dict set Requests $id serverError $code
		} else {
			dict unset Requests $id serverError
		}
		# Deliver the final complete events before advancing the generation.
		dict set Requests $id timer [after 0 [list ::lichess::api::Reconnect $id]]
		return
	}
	set expired [expr {$code == 401 && [dict get $r authenticated] && ![dict get $r validation]
		&& [dict get $r epoch] == $::lichess::api::Epoch}]
	if {$code == 401} { dict set reply authenticated [dict get $r authenticated] }
	Finish $id $reply
	if {$expired} {
		signOut
		if {[llength [info commands ::lichess::SessionExpired]]} {
			::lichess::SessionExpired [dict create status 401 sessionExpired 1]
		}
	}
}

proc ::lichess::api::Finish {id reply} {
	variable Requests
	if {![dict exists $Requests $id]} { return }
	set r [dict get $Requests $id]
	foreach key {timer watchdog deadline} { after cancel [dict get $r $key] }
	RecoveryNotice $id {}
	dict unset Requests $id
	if {[dict get $r stream]} {
		dict set reply type closed
	}
	Reply [dict get $r cmd] $reply
	after 0 [list ::lichess::api::ForgetDelivery $id]
}

# Handles stay stable across reconnects. Only this routine owns HTTP teardown.
proc ::lichess::api::DropTransport {id} {
	variable Requests
	if {![dict exists $Requests $id]} { return }
	foreach key {timer watchdog} { after cancel [dict get $Requests $id $key]; dict set Requests $id $key {} }
	set h [dict get $Requests $id http]
	dict set Requests $id http {}
	if {$h ne {}} {
		upvar #0 $h state
		unset -nocomplain state(-command)
		catch {::http::reset $h}
		catch {::http::cleanup $h}
	}
}
proc ::lichess::api::close {id} {
	ForgetDelivery $id
	DropTransport $id
	Finish $id [dict create ok 0 error $::lichess::api::mc::Cancelled status 0]
}
proc ::lichess::api::closeStreams {} {
	variable Requests
	dict for {id r} $Requests { if {[dict get $r stream]} { close $id } }
}
proc ::lichess::api::ArmWatchdog {id {activity 0}} {
	variable Requests
	variable StallTimeout
	if {![dict exists $Requests $id]} { return }
	if {$activity} {
		# A connection that stays active for a watchdog interval breaks the
		# sequence of short EOFs and starts a fresh future recovery budget.
		if {[dict exists $Requests $id startedAt] && [clock milliseconds] - [dict get $Requests $id startedAt] >= $StallTimeout} {
			dict unset Requests $id eofSince
			dict unset Requests $id eofAttempts
		}
		dict unset Requests $id serverError
		dict set Requests $id lastActivity [clock milliseconds]
		after cancel [dict get $Requests $id deadline]
		dict set Requests $id deadline {}
		dict set Requests $id attempts 0
		RecoveryNotice $id {}
	}
	after cancel [dict get $Requests $id watchdog]
	dict set Requests $id watchdog [after $StallTimeout [list ::lichess::api::Reconnect $id]]
}
proc ::lichess::api::ForgetDelivery {id} {
	variable Deliveries
	dict unset Deliveries $id
}
proc ::lichess::api::StreamReply {id event} {
	variable Requests
	TrackCompletion $id $event
	after 0 [list ::lichess::api::StreamDeliver $id [dict get $Requests $id generation] [dict get $Requests $id cmd] $event]
}
# Completion comes from protocol state, never from EOF alone. TV and event
# feeds remain open-ended even when a game mentioned by them has finished.
proc ::lichess::api::TrackCompletion {id event} {
	variable Requests
	if {![dict exists $Requests $id url]} { return }
	set url [dict get $Requests $id url]
	if {[regexp {/api/(board|bot)/game/stream/|/api/stream/game/} $url]} {
		set state $event
		if {[dict exists $event type] && [dict get $event type] eq "gameFull" && [dict exists $event state]} {
			set state [dict get $event state]
		}
		if {[dict exists $state status]} {
			set status [dict get $state status]
			if {[dict exists $status name]} { set status [dict get $status name] }
			dict set Requests $id terminal [expr {$status in {aborted mate resign stalemate timeout draw outoftime cheat noStart unknownFinish variantEnd}}]
		}
	} elseif {[string match */api/stream/broadcast/round/*.pgn $url] && [dict exists $event text]} {
		set text [dict get $event text]
		set key {}
		foreach tag {Site Board White Black} {
			set value {}
			regexp -line [format {^\[%s "([^"\n]*)"\]} $tag] $text -> value
			lappend key $value
		}
		set result *
		regexp -line {^\[Result "([^"\n]*)"\]} $text -> result
		dict set Requests $id pgnResults $key [expr {$result in {1-0 0-1 1/2-1/2}}]
	}
}
proc ::lichess::api::StreamComplete {id} {
	variable Requests
	set r [dict get $Requests $id]
	if {[dict exists $r terminal]} { return [dict get $r terminal] }
	if {[dict exists $r pgnResults]} {
		return [expr {0 ni [dict values [dict get $r pgnResults]]}]
	}
	# Seek's streaming response is a finite acknowledgement, not a feed.
	return [string match */api/board/seek [dict get $r url]]
}
proc ::lichess::api::StreamDeliver {id generation cmd event} {
	variable Deliveries
	if {![dict exists $Deliveries $id] || [dict get $Deliveries $id] != $generation} { return }
	Deliver $cmd $event
}
proc ::lichess::api::Reconnect {id} {
	variable Requests
	variable ReconnectDelays
	variable RecoveryTimeout
	if {![dict exists $Requests $id]} { return }
	DropTransport $id
	set r [dict get $Requests $id]
	set attempt [dict get $r attempts]
	if {$attempt >= [llength $ReconnectDelays]} { GiveUp $id; return }
	if {[dict get $r deadline] eq {}} {
		# Include the original silence in the 30-second recovery bound.
		set since [dict get $r lastActivity]
		if {[dict exists $r eofSince]} { set since [expr {min($since, [dict get $r eofSince])}] }
		set remaining [expr {max(0, $RecoveryTimeout - ([clock milliseconds] - $since))}]
		dict set Requests $id deadline [after $remaining [list ::lichess::api::GiveUp $id]]
	}
	dict set Requests $id generation [expr {[dict get $r generation] + 1}]
	variable Deliveries
	dict set Deliveries $id [dict get $Requests $id generation]
	foreach key {buffer wire} { dict set Requests $id $key {} }
	dict set Requests $id chunk -1
	dict unset Requests $id framed
	dict set Requests $id attempts [expr {$attempt + 1}]
	dict set Requests $id timer [after [lindex $ReconnectDelays $attempt] [list ::lichess::api::Start $id]]
	set text $::lichess::api::mc::Reconnecting
	if {[dict exists $r serverError]} { set text [format $::lichess::api::mc::ServerReconnecting [dict get $r serverError]] }
	RecoveryNotice $id $text
}
proc ::lichess::api::GiveUp {id} {
	variable Requests
	if {![dict exists $Requests $id]} { return }
	DropTransport $id
	after cancel [dict get $Requests $id deadline]
	dict set Requests $id deadline {}
	dict set Requests $id lost 1
	set text $::lichess::api::mc::Lost
	if {[dict exists $Requests $id serverError]} { set text [format $::lichess::api::mc::ServerLost [dict get $Requests $id serverError]] }
	RecoveryNotice $id $text 1
}
proc ::lichess::api::retry {id} {
	variable Requests
	if {![dict exists $Requests $id]} { return }
	DropTransport $id
	after cancel [dict get $Requests $id deadline]
	dict set Requests $id deadline {}
	dict set Requests $id lost 0
	dict unset Requests $id eofSince
	dict unset Requests $id eofAttempts
	dict unset Requests $id serverError
	dict set Requests $id attempts 0
	dict set Requests $id buffer {}
	dict set Requests $id wire {}
	dict set Requests $id chunk -1
	dict unset Requests $id framed
	RecoveryNotice $id {}
	dict set Requests $id timer [after 0 [list ::lichess::api::Start $id]]
}
# GUI hooks are optional: the API is also usable by standalone Tcl clients.
proc ::lichess::api::Notice {text} {
	if {[llength [info commands ::lichess::Status]]} { ::lichess::Status $text }
	if {[llength [info commands ::online::window::status]]} { ::online::window::status $text }
}
proc ::lichess::api::RecoveryNotice {id text {retry 0}} {
	if {[llength [info commands ::lichess::StreamStatus]]} { ::lichess::StreamStatus $id $text $retry }
}

proc ::lichess::api::AccountReply {cmd reply} {
	variable mc
	if {[dict get $reply ok]} {
		set d [dict get $reply data]
		if {![dict exists $d username] || ![dict exists $d id]} {
			set reply [dict create ok 0 error $mc::Invalid status 200]
		} else {
			set reply [dict create ok 1 username [dict get $d username] id [dict get $d id]]
			if {[dict exists $d title]} { dict set reply title [dict get $d title] }
		}
	}
	Reply $cmd $reply
}
proc ::lichess::api::account {cmd} {
	Request GET /api/account {} [list ::lichess::api::AccountReply $cmd]
}
proc ::lichess::api::useToken {tok cmd} {
	if {$tok eq {} || [regexp {[\r\n]} $tok]} {
		Reply $cmd [dict create ok 0 error $::lichess::api::mc::InvalidToken status 401]
		return
	}
	variable Epoch
	Request GET /api/account {} [list ::lichess::api::Validated $tok $cmd $Epoch] 0 $tok
}
proc ::lichess::api::Validated {tok cmd epoch reply} {
	variable Epoch
	variable mc
	if {$epoch != $Epoch} { Reply $cmd [dict create ok 0 error $mc::Cancelled]; return }
	if {[dict get $reply ok]} {
		set d [dict get $reply data]
		if {![dict exists $d username] || ![dict exists $d id]} {
			set reply [dict create ok 0 error $mc::Invalid status 200]
		} elseif {[catch {TokenStore $tok}]} {
			set reply [dict create ok 0 error "Could not store the Lichess credential."]
		} else {
			set reply [dict create ok 1 username [dict get $d username] id [dict get $d id]]
			if {[dict exists $d title]} { dict set reply title [dict get $d title] }
		}
	}
	Reply $cmd $reply
}
proc ::lichess::api::streamEvents {cmd} { Request GET /api/stream/event {} $cmd 1 }
proc ::lichess::api::streamGame {id cmd} {
	variable Mode
	Request GET /api/$Mode/game/stream/[Segment $id] {} $cmd 1
}
proc ::lichess::api::seek {minutes increment rated color cmd {variant standard} {days ""}} {
	set form [list rated [expr {$rated ? "true" : "false"}] color $color]
	if {$days eq {}} { set form [concat [list time $minutes increment $increment] $form] } else { lappend form days $days }
	if {$variant ne "standard"} { lappend form variant $variant }
	Request POST /api/board/seek [::http::formatQuery {*}$form] $cmd [expr {$days eq {}}]
}
proc ::lichess::api::challengeAi {level minutes increment color cmd} {
	Request POST /api/challenge/ai [::http::formatQuery level $level clock.limit [expr {int($minutes * 60)}] \
		clock.increment $increment color $color] [list ::lichess::api::ActionReply $cmd 1]
}
proc ::lichess::api::Segment {text} { string map {+ %20} [string range [::http::formatQuery x $text] 2 end] }
proc ::lichess::api::ActionReply {cmd ai reply} {
	if {[dict get $reply ok]} {
		if {$ai} {
			if {[dict exists $reply data id]} {
				set reply [dict create ok 1 id [dict get $reply data id]]
			} else { set reply [dict create ok 0 error $::lichess::api::mc::Invalid status 200] }
		} else { set reply [dict create ok 1] }
	}
	Reply $cmd $reply
}
proc ::lichess::api::Action {id action cmd} {
	variable Mode
	Request POST /api/$Mode/game/[Segment $id]/$action {} [list ::lichess::api::ActionReply $cmd 0]
}
proc ::lichess::api::move {id uci cmd} { Action $id move/[Segment $uci] $cmd }
proc ::lichess::api::resign {id cmd} { Action $id resign $cmd }
proc ::lichess::api::abort {id cmd} { Action $id abort $cmd }
proc ::lichess::api::draw {id answer cmd} { Action $id draw/[Segment $answer] $cmd }
proc ::lichess::api::claimVictory {id cmd} { Action $id claim-victory $cmd }
proc ::lichess::api::takeback {id answer cmd} { Action $id takeback/[Segment $answer] $cmd }
proc ::lichess::api::chat {id text cmd} {
	variable Mode
	Request POST /api/$Mode/game/[Segment $id]/chat [::http::formatQuery room player text $text] \
		[list ::lichess::api::ActionReply $cmd 0]
}

# Response shapes are explicit: JSON arrays and objects can have identical
# Tcl representations, so validate the wire container before decoding.
proc ::lichess::api::ParseJson {body shape} {
	set first [string index [string trimleft $body] 0]
	if {($shape eq "object" && $first ne "\{") || ($shape eq "array" && $first ne "\[")} { error "Invalid JSON container" }
	return [::json::json2dict $body]
}

proc ::lichess::api::PgnLines {id bytes {final 0}} {
	variable Requests
	set buffer [dict get $Requests $id buffer]
	append buffer [string map {\r {}} $bytes]
	while {1} {
		set end [string first "\n\n\n" $buffer]
		set skip 3
		if {[regexp -indices {\n\[Event } $buffer match]} {
			set next [lindex $match 0]
			if {$end < 0 || $next < $end} { set end $next; set skip 1 }
		}
		if {$end < 0} {
			# one game, no successor yet: headers, blank line, movetext, blank line
			set body [string trimleft $buffer \n]
			set lead [expr {[string length $buffer] - [string length $body]}]
			set tags [string first "\n\n" $body]
			if {$tags >= 0 && [string index $body 0] eq "\["} {
				set close [string first "\n\n" $body [expr {$tags + 2}]]
				if {$close >= 0} { set end [expr {$lead + $close}]; set skip 2 }
			}
		}
		if {$end < 0} { break }
		set text [string trim [string range $buffer 0 [expr {$end-1}]]]
		set buffer [string range $buffer [expr {$end+$skip}] end]
		if {$text ne {}} { StreamReply $id [dict create type pgn text [encoding convertfrom utf-8 $text]] }
	}
	if {$final && [string trim $buffer] ne {}} {
		StreamReply $id [dict create type pgn text [encoding convertfrom utf-8 [string trim $buffer]]]
		set buffer {}
	}
	if {[string length $buffer] > 2097152} { error "PGN too long" }
	dict set Requests $id buffer $buffer
}

proc ::lichess::api::mode {value} {
	variable Mode
	if {$value ni {board bot}} { error "mode must be board or bot" }
	set Mode $value
}
proc ::lichess::api::user {name cmd} {
	Request GET /api/user/[Segment $name] {} $cmd 0 {} application/x-www-form-urlencoded json
}
proc ::lichess::api::ratingHistory {name cmd} {
	Request GET /api/user/[Segment $name]/rating-history {} $cmd 0 {} application/x-www-form-urlencoded array
}
proc ::lichess::api::teamsOf {name cmd} {
	Request GET /api/team/of/[Segment $name] {} $cmd 0 {} application/x-www-form-urlencoded array
}
proc ::lichess::api::chatHistory {gameId cmd} {
	variable Mode
	Request GET /api/$Mode/game/[Segment $gameId]/chat {} $cmd 0 {} application/x-www-form-urlencoded array
}
proc ::lichess::api::tvChannels {cmd} {
	Request GET /api/tv/channels {} $cmd 0 {} application/x-www-form-urlencoded json
}
proc ::lichess::api::broadcastsTop {cmd} {
	Request GET /api/broadcast/top {} $cmd 0 {} application/x-www-form-urlencoded json
}
proc ::lichess::api::arenas {cmd} {
	Request GET /api/tournament {} $cmd 0 {} application/x-www-form-urlencoded json
}
proc ::lichess::api::arena {id cmd} {
	Request GET /api/tournament/[Segment $id] {} $cmd 0 {} application/x-www-form-urlencoded json
}
proc ::lichess::api::swissOfTeam {teamId cmd} {
	Request GET /api/team/[Segment $teamId]/swiss {} $cmd 0 {} application/x-www-form-urlencoded ndjson
}
proc ::lichess::api::simuls {cmd} {
	Request GET /api/simul {} $cmd 0 {} application/x-www-form-urlencoded json
}
proc ::lichess::api::puzzleDaily {cmd} {
	Request GET /api/puzzle/daily {} $cmd 0 {} application/x-www-form-urlencoded json
}
proc ::lichess::api::puzzleNext {angle difficulty cmd} {
	Request GET /api/puzzle/next?[::http::formatQuery angle $angle difficulty $difficulty] {} $cmd 0 {} application/x-www-form-urlencoded json
}
proc ::lichess::api::puzzle {id cmd} {
	Request GET /api/puzzle/[Segment $id] {} $cmd 0 {} application/x-www-form-urlencoded json
}
proc ::lichess::api::puzzleDashboard {days cmd} {
	Request GET /api/puzzle/dashboard/[Segment $days] {} $cmd 0 {} application/x-www-form-urlencoded json
}
proc ::lichess::api::puzzleActivity {max cmd} {
	Request GET /api/puzzle/activity?[::http::formatQuery max $max] {} $cmd 0 {} application/x-www-form-urlencoded ndjson
}
proc ::lichess::api::cloudEval {fen multiPv cmd} {
	Request GET /api/cloud-eval?[::http::formatQuery fen $fen multiPv $multiPv] {} $cmd 0 {} application/x-www-form-urlencoded json
}
proc ::lichess::api::gameExport {id cmd} {
	Request GET /game/export/[Segment $id]?evals=true&clocks=true&literate=true {} $cmd 0 {} application/x-www-form-urlencoded text
}
proc ::lichess::api::studiesOf {user cmd} {
	Request GET /api/study/by/[Segment $user] {} $cmd 0 {} application/x-www-form-urlencoded ndjson
}
proc ::lichess::api::joinTeam {teamId message cmd} {
	Request POST /api/team/[Segment $teamId]/join [::http::formatQuery message $message] $cmd
}
proc ::lichess::api::leaveTeam {teamId cmd} {
	Request POST /api/team/[Segment $teamId]/quit {} $cmd
}
proc ::lichess::api::sendMessage {user text cmd} {
	Request POST /api/inbox/[Segment $user] [::http::formatQuery text $text] $cmd
}
proc ::lichess::api::acceptChallenge {id cmd} {
	Request POST /api/challenge/[Segment $id]/accept {} $cmd
}
proc ::lichess::api::declineChallenge {id reason cmd} {
	Request POST /api/challenge/[Segment $id]/decline [::http::formatQuery reason $reason] $cmd
}
proc ::lichess::api::cancelChallenge {id cmd} {
	Request POST /api/challenge/[Segment $id]/cancel {} $cmd
}
proc ::lichess::api::botUpgrade {cmd} {
	Request POST /api/bot/account/upgrade {} $cmd
}
proc ::lichess::api::joinArena {id cmd} {
	Request POST /api/tournament/[Segment $id]/join {} $cmd
}
proc ::lichess::api::withdrawArena {id cmd} {
	Request POST /api/tournament/[Segment $id]/withdraw {} $cmd
}
proc ::lichess::api::joinSwiss {id cmd} {
	Request POST /api/swiss/[Segment $id]/join {} $cmd
}
proc ::lichess::api::withdrawSwiss {id cmd} {
	Request POST /api/swiss/[Segment $id]/withdraw {} $cmd
}
proc ::lichess::api::puzzleRace {cmd} {
	Request POST /api/racer {} $cmd
}
proc ::lichess::api::importGame {pgn cmd} {
	Request POST /api/import [::http::formatQuery pgn $pgn] $cmd
}
# bearer: a token other than the stored one (the study dialog keeps its own)
proc ::lichess::api::studyImportPgn {studyId name pgn orientation variant cmd {bearer {}}} {
	Request POST /api/study/[Segment $studyId]/import-pgn [::http::formatQuery name $name pgn $pgn orientation $orientation variant $variant] $cmd 0 $bearer
}
proc ::lichess::api::studyCreate {name visibility cmd} {
	Request POST /api/study [::http::formatQuery name $name visibility $visibility] $cmd
}
proc ::lichess::api::challengeUser {user minutes increment rated color variant days cmd} {
	set form [list rated [expr {$rated ? "true" : "false"}] color $color variant $variant]
	if {$days eq {}} { lappend form clock.limit [expr {int($minutes*60)}] clock.increment $increment } else { lappend form days $days }
	Request POST /api/challenge/[Segment $user] [::http::formatQuery {*}$form] $cmd
}
proc ::lichess::api::tvFeed {channel cmd} {
	set path /api/tv/feed
	if {$channel ne {}} { set path /api/tv/[Segment [TvChannelKey $channel]]/feed }
	Request GET $path {} $cmd 1
}
# "King of the Hill" -> kingOfTheHill, "UltraBullet" -> ultraBullet, "Top Rated" -> best
proc ::lichess::api::TvChannelKey {channel} {
	set key {}
	foreach word [regexp -all -inline {[^\s-]+} $channel] {
		append key [expr {$key eq {} ? "[string tolower [string index $word 0]][string range $word 1 end]" \
			: "[string toupper [string index $word 0]][string range $word 1 end]"}]
	}
	if {$key eq "topRated"} { set key best }
	return $key
}
proc ::lichess::api::streamGameMoves {gameId cmd} {
	Request GET /api/stream/game/[Segment $gameId] {} $cmd 1
}
proc ::lichess::api::broadcastRoundStream {roundId cmd} {
	Request GET /api/stream/broadcast/round/[Segment $roundId].pgn {} $cmd 1 {} application/x-www-form-urlencoded pgn
}
proc ::lichess::api::JsonString {value} {
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
# solutions is a Tcl list of dicts with id, win and rated fields.
proc ::lichess::api::puzzleBatchSolved {angle solutions cmd} {
	set items {}
	foreach solution $solutions {
		lappend items [format {{"id":%s,"win":%s,"rated":%s}} [JsonString [dict get $solution id]] \
			[expr {[dict get $solution win] ? "true" : "false"}] [expr {[dict get $solution rated] ? "true" : "false"}]]
	}
	Request POST /api/puzzle/batch/[Segment $angle] [format {{"solutions":[%s]}} [join $items ,]] $cmd 0 {} application/json
}
proc ::lichess::api::botStreamGame {id cmd} { Request GET /api/bot/game/stream/[Segment $id] {} $cmd 1 }
proc ::lichess::api::BotAction {id action cmd {form {}}} {
	Request POST /api/bot/game/[Segment $id]/$action $form [list ::lichess::api::ActionReply $cmd 0]
}
proc ::lichess::api::botMove {id uci cmd} { BotAction $id move/[Segment $uci] $cmd }
proc ::lichess::api::botResign {id cmd} { BotAction $id resign $cmd }
proc ::lichess::api::botAbort {id cmd} { BotAction $id abort $cmd }
proc ::lichess::api::botDraw {id answer cmd} { BotAction $id draw/[Segment $answer] $cmd }
proc ::lichess::api::botTakeback {id answer cmd} { BotAction $id takeback/[Segment $answer] $cmd }
proc ::lichess::api::botChat {id text cmd} { BotAction $id chat $cmd [::http::formatQuery room player text $text] }

# PKCE uses OS entropy, never Tcl's non-cryptographic rand(). A platform
# without an entropy source fails closed and offers personal-token sign in.
proc ::lichess::api::Random {} {
	set bytes [::scidb::sys::randomBytes 32]
	if {[string length $bytes] != 32} { error "No secure random source" }
	return [Base64 $bytes]
}
proc ::lichess::api::Base64 {bytes} {
	string map {+ - / _ = {} \n {} \r {}} [binary encode base64 -maxlen 0 $bytes]
}
proc ::lichess::api::Challenge {verifier} {
	if {![catch {package require sha256}]} {
		return [Base64 [::sha2::sha256 -bin $verifier]]
	}
	return [Base64 [Sha256 $verifier]]
}

# Portable SHA-256 fallback for bundles without tcllib sha256.
proc ::lichess::api::Rotate {x n} { expr {(($x >> $n) | ($x << (32-$n))) & 0xffffffff} }
proc ::lichess::api::Sha256 {text} {
	set k {0x428a2f98 0x71374491 0xb5c0fbcf 0xe9b5dba5 0x3956c25b 0x59f111f1 0x923f82a4 0xab1c5ed5 0xd807aa98 0x12835b01 0x243185be 0x550c7dc3 0x72be5d74 0x80deb1fe 0x9bdc06a7 0xc19bf174 0xe49b69c1 0xefbe4786 0x0fc19dc6 0x240ca1cc 0x2de92c6f 0x4a7484aa 0x5cb0a9dc 0x76f988da 0x983e5152 0xa831c66d 0xb00327c8 0xbf597fc7 0xc6e00bf3 0xd5a79147 0x06ca6351 0x14292967 0x27b70a85 0x2e1b2138 0x4d2c6dfc 0x53380d13 0x650a7354 0x766a0abb 0x81c2c92e 0x92722c85 0xa2bfe8a1 0xa81a664b 0xc24b8b70 0xc76c51a3 0xd192e819 0xd6990624 0xf40e3585 0x106aa070 0x19a4c116 0x1e376c08 0x2748774c 0x34b0bcb5 0x391c0cb3 0x4ed8aa4a 0x5b9cca4f 0x682e6ff3 0x748f82ee 0x78a5636f 0x84c87814 0x8cc70208 0x90befffa 0xa4506ceb 0xbef9a3f7 0xc67178f2}
	set h {0x6a09e667 0xbb67ae85 0x3c6ef372 0xa54ff53a 0x510e527f 0x9b05688c 0x1f83d9ab 0x5be0cd19}
	set data [encoding convertto utf-8 $text]
	set bits [expr {[string length $data]*8}]
	append data \x80
	while {[string length $data] % 64 != 56} { append data \x00 }
	append data [binary format II 0 $bits]
	for {set offset 0} {$offset < [string length $data]} {incr offset 64} {
		binary scan [string range $data $offset [expr {$offset+63}]] I16 w
		set w [lmap x $w {expr {$x & 0xffffffff}}]
		for {set i 16} {$i < 64} {incr i} {
			set x [lindex $w [expr {$i-15}]]; set y [lindex $w [expr {$i-2}]]
			set s0 [expr {[Rotate $x 7] ^ [Rotate $x 18] ^ ($x >> 3)}]
			set s1 [expr {[Rotate $y 17] ^ [Rotate $y 19] ^ ($y >> 10)}]
			lappend w [expr {([lindex $w [expr {$i-16}]]+$s0+[lindex $w [expr {$i-7}]]+$s1)&0xffffffff}]
		}
		lassign $h a b c d e f g hh
		for {set i 0} {$i < 64} {incr i} {
			set t1 [expr {($hh+([Rotate $e 6] ^ [Rotate $e 11] ^ [Rotate $e 25])+(($e & $f) ^ ((~$e) & $g))+[lindex $k $i]+[lindex $w $i]) & 0xffffffff}]
			set t2 [expr {(([Rotate $a 2] ^ [Rotate $a 13] ^ [Rotate $a 22])+(($a & $b) ^ ($a & $c) ^ ($b & $c))) & 0xffffffff}]
			lassign [list $g $f $e [expr {($d+$t1)&0xffffffff}] $c $b $a [expr {($t1+$t2)&0xffffffff}]] hh g f e d c b a
		}
		set h [lmap old $h new [list $a $b $c $d $e $f $g $hh] {expr {($old+$new)&0xffffffff}}]
	}
	return [binary format I* $h]
}

proc ::lichess::api::signIn {cmd} {
	variable Auth
	variable mc
	if {$Auth ne {}} { Reply $cmd [dict create ok 0 error "Lichess sign in is already pending."]; return }
	if {[catch {
		set verifier [Random]
		set state [Random]
		set challenge [Challenge $verifier]
		set listener [socket -server ::lichess::api::AuthAccept -myaddr 127.0.0.1 0]
	}]} { Reply $cmd [dict create ok 0 error $mc::SignIn]; return }
	set redirect "http://127.0.0.1:[lindex [fconfigure $listener -sockname] 2]/"
	set Auth [dict create cmd $cmd listener $listener clients {} verifier $verifier state $state redirect $redirect \
		timer [after 180000 [list ::lichess::api::AuthFinish [dict create ok 0 error $mc::SignIn]]]]
	variable Base
	set url "[string trimright $Base /]/oauth?[::http::formatQuery response_type code client_id chesswiz \
		redirect_uri $redirect code_challenge_method S256 code_challenge $challenge scope {board:play challenge:read challenge:write puzzle:read study:read study:write team:read team:write msg:write tournament:write bot:play preference:read} state $state]"
	if {[catch {OpenBrowser $url}]} { AuthFinish [dict create ok 0 error $mc::SignIn] }
}
proc ::lichess::api::AuthAccept {sock address port} {
	variable Auth
	if {$Auth eq {}} { ::close $sock; return }
	fconfigure $sock -blocking 0 -buffering none -translation binary
	dict set Auth clients $sock {}
	fileevent $sock readable [list ::lichess::api::AuthRead $sock]
}
proc ::lichess::api::Decode {text} {
	set text [string map {+ { }} $text]
	set bytes {}
	while {[regexp {^([^%]*)%([0-9a-fA-F]{2})(.*)$} $text -> prefix hex rest]} {
		append bytes $prefix [binary decode hex $hex]
		set text $rest
	}
	return [encoding convertfrom utf-8 $bytes$text]
}
proc ::lichess::api::AuthRead {sock} {
	variable Auth
	variable mc
	if {$Auth eq {} || ![dict exists $Auth clients $sock]} { return }
	if {[catch {read $sock 8192} bytes]} { set bytes {}; set ended 1 } else { set ended [eof $sock] }
	set buffer [dict get $Auth clients $sock]
	append buffer $bytes
	if {[string length $buffer] > 16384 || $ended} {
		catch {::close $sock}; dict unset Auth clients $sock; return
	}
	dict set Auth clients $sock $buffer
	if {[string first "\r\n\r\n" $buffer] < 0} { return }
	set query {}
	if {[regexp {^GET /\?([^ ]+) HTTP/1\.[01]\r\n} $buffer -> text]} {
		foreach pair [split $text &] {
			set eq [string first = $pair]
			if {$eq > 0} { dict set query [Decode [string range $pair 0 [expr {$eq-1}]]] [Decode [string range $pair [expr {$eq+1}] end]] }
		}
	}
	set valid [expr {[dict exists $query state] && [dict get $query state] eq [dict get $Auth state]}]
	set html "<html><body>You may return to Chesswiz.</body></html>"
	catch {puts -nonewline $sock "HTTP/1.1 [expr {$valid ? {200 OK} : {400 Bad Request}}]\r\nContent-Type: text/html\r\nContent-Length: [string length $html]\r\nConnection: close\r\n\r\n$html"}
	catch {::close $sock}
	dict unset Auth clients $sock
	if {!$valid} { return }
	if {[dict exists $query error] || ![dict exists $query code]} {
		AuthFinish [dict create ok 0 error $mc::SignIn]; return
	}
	set form [::http::formatQuery grant_type authorization_code code [dict get $query code] \
		code_verifier [dict get $Auth verifier] redirect_uri [dict get $Auth redirect] client_id chesswiz]
	set cmd [dict get $Auth cmd]
	AuthCleanup
	variable Epoch
	Request POST /api/token $form [list ::lichess::api::Exchanged $cmd $Epoch]
}
proc ::lichess::api::AuthCleanup {} {
	variable Auth
	if {$Auth eq {}} { return }
	after cancel [dict get $Auth timer]
	catch {::close [dict get $Auth listener]}
	foreach sock [dict keys [dict get $Auth clients]] { catch {::close $sock} }
	set Auth {}
}
proc ::lichess::api::AuthFinish {reply} {
	variable Auth
	if {$Auth eq {}} { return }
	set cmd [dict get $Auth cmd]
	AuthCleanup
	Reply $cmd $reply
}
proc ::lichess::api::Exchanged {cmd epoch reply} {
	variable Epoch
	if {$epoch != $Epoch} { Reply $cmd [dict create ok 0 error $::lichess::api::mc::Cancelled]; return }
	if {[dict get $reply ok] && [dict exists $reply data access_token] && [dict get $reply data access_token] ne {}} {
		useToken [dict get $reply data access_token] $cmd
	} else { Reply $cmd [dict create ok 0 error $::lichess::api::mc::SignIn] }
}

# vi:set ts=3 sw=3:
