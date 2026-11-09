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
	namespace eval mc {
		set Network "Could not complete the Lichess request."
		set Unauthorized "Lichess rejected the credential. Sign in again."
		set Limited "Lichess rate limit reached. Please wait one minute."
		set Invalid "Lichess returned an invalid response."
		set Rejected "Lichess rejected the request."
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
proc ::lichess::api::Request {method path form cmd {stream 0} {bearer {}}} {
	variable Serial
	variable Requests
	variable Base
	set id request[incr Serial]
	dict set Requests $id [dict create method $method url "[string trimright $Base /]$path" \
		form $form cmd $cmd stream $stream bearer $bearer http {} timer {} buffer {} wire {} chunk -1]
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
	set r [dict get $Requests $id]
	set url [dict get $r url]
	set opts [list -method [dict get $r method] -binary 1 -keepalive 0 \
		-command [list ::lichess::api::Done $id] -timeout 30000]
	set bearer [dict get $r bearer]
	if {$bearer eq {}} { set bearer [token] }
	lappend opts -headers [list Authorization "Bearer $bearer" Accept application/json]
	if {[dict get $r method] eq "POST"} {
		lappend opts -type application/x-www-form-urlencoded -query [dict get $r form]
	}
	if {[dict get $r stream]} {
		lappend opts -handler [list ::lichess::api::Read $id] -timeout 0
	}
	if {[catch {
		if {[string match -nocase https://* $url]} { ::platform::sys::tlsRegister }
		set h [::http::geturl $url {*}$opts]
	}]} {
		Finish $id [dict create ok 0 error $mc::Network status 0]
		return
	}
	if {[dict exists $Requests $id]} { dict set Requests $id http $h }
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
	set buffer [dict get $Requests $id buffer]
	append buffer $bytes
	while {[set end [string first \n $buffer]] >= 0} {
		set line [string trim [string range $buffer 0 [expr {$end - 1}]]]
		set buffer [string range $buffer [expr {$end + 1}] end]
		if {$line eq {}} { continue }
		if {[catch {::json::json2dict [encoding convertfrom utf-8 $line]} event]
		 || [catch {dict size $event}]} { error "Invalid stream response" }
		Reply [dict get $Requests $id cmd] $event
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
		set BackoffUntil [expr {[clock milliseconds] + 60000}]
		dict set reply error $mc::Limited
	} elseif {$code == 401} {
		dict set reply error $mc::Unauthorized
	} elseif {$code >= 200 && $code < 300 && [::http::status $h] eq "ok"} {
		if {[dict get $Requests $id stream]} {
			if {[dict exists $Requests $id framed] && [dict get $Requests $id chunk] != -2} {
				::http::cleanup $h
				Finish $id [dict create ok 0 status $code error $mc::Invalid]
				return
			}
			set tail [dict get $Requests $id buffer]
			if {[string trim $tail] ne {}} {
				if {[catch {Lines $id \n}]} {
					::http::cleanup $h
					Finish $id [dict create ok 0 status $code error $mc::Invalid]
					return
				}
			}
			set reply [dict create ok 1 status $code error $mc::Closed]
		} elseif {[catch {::json::json2dict [encoding convertfrom utf-8 [::http::data $h]]} data]
		 || [catch {dict size $data}]} {
			dict set reply error $mc::Invalid
		} else {
			set reply [dict create ok 1 data $data status $code]
		}
	} elseif {$code >= 400} {
		dict set reply error $mc::Rejected
	}
	::http::cleanup $h
	Finish $id $reply
}

proc ::lichess::api::Finish {id reply} {
	variable Requests
	if {![dict exists $Requests $id]} { return }
	set r [dict get $Requests $id]
	after cancel [dict get $r timer]
	dict unset Requests $id
	if {[dict get $r stream]} {
		dict set reply type closed
	}
	Reply [dict get $r cmd] $reply
}

proc ::lichess::api::close {id} {
	variable Requests
	variable mc
	if {![dict exists $Requests $id]} { return }
	set h [dict get $Requests $id http]
	if {$h ne {}} {
		# Detach before reset: reset invokes the completion synchronously.
		upvar #0 $h state
		unset -nocomplain state(-command)
		catch {::http::reset $h}
		catch {::http::cleanup $h}
	}
	Finish $id [dict create ok 0 error $mc::Cancelled status 0]
}

proc ::lichess::api::AccountReply {cmd reply} {
	variable mc
	if {[dict get $reply ok]} {
		set d [dict get $reply data]
		if {![dict exists $d username] || ![dict exists $d id]} {
			set reply [dict create ok 0 error $mc::Invalid status 200]
		} else {
			set reply [dict create ok 1 username [dict get $d username] id [dict get $d id]]
		}
	}
	Reply $cmd $reply
}
proc ::lichess::api::account {cmd} {
	Request GET /api/account {} [list ::lichess::api::AccountReply $cmd]
}
proc ::lichess::api::useToken {tok cmd} {
	if {$tok eq {} || [regexp {[\r\n]} $tok]} {
		Reply $cmd [dict create ok 0 error $::lichess::api::mc::Unauthorized status 401]
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
		}
	}
	Reply $cmd $reply
}
proc ::lichess::api::streamEvents {cmd} { Request GET /api/stream/event {} $cmd 1 }
proc ::lichess::api::streamGame {id cmd} { Request GET /api/board/game/stream/[Segment $id] {} $cmd 1 }
proc ::lichess::api::seek {minutes increment rated color cmd} {
	Request POST /api/board/seek [::http::formatQuery time $minutes increment $increment rated [expr {$rated ? "true" : "false"}] color $color] $cmd 1
}
proc ::lichess::api::challengeAi {level minutes increment color cmd} {
	Request POST /api/challenge/ai [::http::formatQuery level $level clock.limit [expr {int($minutes * 60)}] \
		clock.increment $increment color $color] [list ::lichess::api::ActionReply $cmd 1]
}
proc ::lichess::api::Segment {text} { string range [::http::formatQuery x $text] 2 end }
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
	Request POST /api/board/game/[Segment $id]/$action {} [list ::lichess::api::ActionReply $cmd 0]
}
proc ::lichess::api::move {id uci cmd} { Action $id move/[Segment $uci] $cmd }
proc ::lichess::api::resign {id cmd} { Action $id resign $cmd }
proc ::lichess::api::abort {id cmd} { Action $id abort $cmd }
proc ::lichess::api::draw {id answer cmd} { Action $id draw/[Segment $answer] $cmd }
proc ::lichess::api::claimVictory {id cmd} { Action $id claim-victory $cmd }

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
		redirect_uri $redirect code_challenge_method S256 code_challenge $challenge scope board:play state $state]"
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
