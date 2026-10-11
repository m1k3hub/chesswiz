# Tiny loopback HTTP server for the browser's 400 ms board polling.
namespace eval ::board3d::webserver {
	variable listener {}
	variable port 0
	variable root {}
	variable board rnbqkbnrpppppppp................................PPPPPPPPRNBQKBNR
	variable clients
	array set clients {}
}

proc ::board3d::webserver::start {directory {requestedPort 0}} {
	variable listener
	variable port
	variable root
	if {$listener ne ""} { return $port }
	set root [file normalize $directory]
	if {![file isfile [file join $root index.html]]} { error "web3d/index.html not found below '$directory'" }
	set listener [socket -server [namespace code Accept] -myaddr 127.0.0.1 $requestedPort]
	set port [lindex [fconfigure $listener -sockname] end]
	return $port
}

proc ::board3d::webserver::stop {} {
	variable listener
	variable port
	variable clients
	if {$listener ne ""} { catch {close $listener} }
	set listener {}
	set port 0
	foreach sock [array names clients] { Close $sock }
}

proc ::board3d::webserver::setBoard {value} {
	variable board
	set board $value
}

proc ::board3d::webserver::BoardJson {} {
	variable board
	set escaped {}
	foreach char [split $board {}] {
		scan $char %c code
		if {$char eq "\"" || $char eq "\\"} {
			append escaped \\ $char
		} elseif {$code < 32} {
			append escaped [format {\u%04x} $code]
		} else {
			append escaped $char
		}
	}
	return "{\"board\": \"$escaped\"}"
}

proc ::board3d::webserver::Accept {sock address remotePort} {
	variable clients
	fconfigure $sock -blocking 0 -translation binary -encoding binary -buffering none
	set clients($sock) [dict create input {} timer [after 10000 [namespace code [list Close $sock]]]]
	fileevent $sock readable [namespace code [list Read $sock]]
}

proc ::board3d::webserver::Close {sock} {
	variable clients
	if {![info exists clients($sock)]} { return }
	after cancel [dict get $clients($sock) timer]
	catch {close $sock}
	unset clients($sock)
}

proc ::board3d::webserver::Read {sock} {
	variable clients
	if {[catch {ReadRequest $sock}]} { Close $sock }
}

proc ::board3d::webserver::ReadRequest {sock} {
	variable clients
	dict append clients($sock) input [read $sock 65536]
	set input [dict get $clients($sock) input]
	set end [string first "\r\n\r\n" $input]
	if {$end < 0} {
		if {[string length $input] > 16384 || [eof $sock]} { Close $sock }
		return
	}
	if {$end > 16384} { Reply $sock 400 text/plain {Bad request}; return }
	set lines [split [string range $input 0 [expr {$end-1}]] \n]
	if {![regexp {^(GET|POST) ([^ ]+) HTTP/1\.[01]\r?$} [lindex $lines 0] -> method target]} {
		Reply $sock 400 text/plain {Bad request}; return
	}
	set length 0
	set seenLength 0
	foreach line [lrange $lines 1 end] {
		if {[regexp -nocase {^Content-Length:\s*(.*?)\r?$} $line -> value]} {
			set value [string trim $value]
			if {$seenLength || ![regexp {^[0-9]+$} $value] || [string length $value] > 7} {
				Reply $sock 400 text/plain {Bad request}; return
			}
			set length [scan $value %d]
			set seenLength 1
		}
		if {[regexp -nocase {^Transfer-Encoding:} $line]} {
			Reply $sock 400 text/plain {Bad request}; return
		}
	}
	if {$length > 1048576} { Reply $sock 413 text/plain {Body too large}; return }
	set body [string range $input [expr {$end+4}] end]
	if {[string length $body] < $length} {
		if {[eof $sock]} { Close $sock }
		return
	}
	if {$target eq "/api/board"} {
		if {$method eq "POST"} {
			# Match the old helper: malformed JSON leaves the position alone.
			catch {
				set data [ParseBoardJson [encoding convertfrom utf-8 [string range $body 0 [expr {$length-1}]]]]
				if {[dict exists $data board]} { setBoard [dict get $data board] }
			}
			Reply $sock 200 application/json {{"status":"ok"}}
		} else {
			Reply $sock 200 application/json [BoardJson]
		}
		return
	}
	if {$method ne "GET"} { Reply $sock 404 text/plain {Not found}; return }
	ServeFile $sock $target
}

# The board API accepts a JSON object of string fields. Decode JSON strings
# ourselves so this small server does not introduce a tcllib dependency.
proc ::board3d::webserver::ParseBoardJson {text} {
	set text [string trim $text]
	if {[string index $text 0] ne "\{" || [string index $text end] ne "\}"} { error "Expected JSON object" }
	set text [string trim [string range $text 1 end-1]]
	set data {}
	while {$text ne ""} {
		set key [JsonString text]
		set text [string trimleft $text]
		if {[string index $text 0] ne ":"} { error "Expected colon" }
		set text [string trimleft [string range $text 1 end]]
		set value [JsonString text]
		dict set data $key $value
		set text [string trimleft $text]
		if {$text eq ""} { break }
		if {[string index $text 0] ne ","} { error "Expected comma" }
		set text [string trimleft [string range $text 1 end]]
		if {$text eq ""} { error "Trailing comma" }
	}
	return $data
}

proc ::board3d::webserver::JsonString {textVar} {
	upvar 1 $textVar text
	if {![regexp {^"((?:[^"\\\x00-\x1f]|\\(?:["\\/bfnrt]|u[0-9a-fA-F]{4}))*)"} $text token value]} {
		error "Expected JSON string"
	}
	set text [string range $text [string length $token] end]
	set decoded {}
	while {[regexp -indices {\\(?:u[0-9a-fA-F]{4}|.)} $value match]} {
		lassign $match first last
		append decoded [string range $value 0 [expr {$first-1}]]
		set escape [string range $value [expr {$first+1}] $last]
		if {[string index $escape 0] eq "u"} {
			append decoded [format %c [scan [string range $escape 1 end] %x]]
		} else {
			append decoded [string map [list b \b f \f n \n r \r t \t] $escape]
		}
		set value [string range $value [expr {$last+1}] end]
	}
	append decoded $value
	return $decoded
}

proc ::board3d::webserver::ServeFile {sock target} {
	variable root
	# Remove the URL's required slash, then reject filesystem absolute paths
	# and traversal, including percent-encoded spellings and Windows slashes.
	set path [lindex [split $target ?] 0]
	if {![string match {/*} $path]} { Reply $sock 404 text/plain {Not found}; return }
	set decoded {}
	while {[regexp -indices {%[0-9a-fA-F]{2}} $path match]} {
		lassign $match first last
		append decoded [string range $path 0 [expr {$first-1}]]
		append decoded [format %c [scan [string range $path [expr {$first+1}] $last] %x]]
		set path [string range $path [expr {$last+1}] end]
	}
	append decoded $path
	set path [string range $decoded 1 end]
	if {$path eq ""} { set path index.html }
	if {[string first .. $path] >= 0 || [string first \\ $path] >= 0
		|| [string first : $path] >= 0 || [string first \x00 $path] >= 0
		|| [file pathtype $path] ne "relative"} {
		Reply $sock 404 text/plain {Not found}; return
	}
	set filename [file normalize [file join $root $path]]
	if {[string first "$root/" $filename] != 0 || ![file isfile $filename]} {
		Reply $sock 404 text/plain {Not found}; return
	}
	if {[catch {open $filename rb} file]} { Reply $sock 404 text/plain {Not found}; return }
	fconfigure $file -translation binary -encoding binary
	try {
		set body [read $file]
	} finally {
		close $file
	}
	switch [string tolower [file extension $filename]] {
		.html { set type text/html }
		.js { set type application/javascript }
		.css { set type text/css }
		.json { set type application/json }
		default { set type application/octet-stream }
	}
	Reply $sock 200 $type $body 1
}

proc ::board3d::webserver::Reply {sock status type body {binary 0}} {
	variable clients
	fileevent $sock readable {}
	if {!$binary} { set body [encoding convertto utf-8 $body] }
	switch $status {
		200 { set reason OK }
		404 { set reason {Not Found} }
		413 { set reason {Payload Too Large} }
		default { set reason {Bad Request} }
	}
	set header "HTTP/1.1 $status $reason\r\nContent-Type: $type\r\nContent-Length: [string length $body]\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n"
	if {[catch {puts -nonewline $sock $header$body}]} { Close $sock; return }
	# Tcl queues nonblocking output; do not close until every byte is sent.
	fileevent $sock writable [namespace code [list Drain $sock]]
}

proc ::board3d::webserver::Drain {sock} {
	if {[catch {flush $sock}] || [chan pending output $sock] == 0} { Close $sock }
}

# vi:set ts=3 sw=3:
