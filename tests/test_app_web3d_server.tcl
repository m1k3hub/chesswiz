package require tcltest 2.5

namespace eval ::web3dTest {
	variable response {}
	variable done 0
}

proc ::web3dTest::receive {sock} {
	variable response
	variable done
	append response [read $sock]
	if {[eof $sock]} { set done 1 }
}

proc ::web3dTest::request {port method path {body {}}} {
	variable response
	variable done
	set response {}
	set done 0
	set sock [socket 127.0.0.1 $port]
	fconfigure $sock -translation binary -encoding binary -blocking 0 -buffering none
	fileevent $sock readable [list ::web3dTest::receive $sock]
	set bytes [encoding convertto utf-8 $body]
	set timer [after 5000 {set ::web3dTest::done timeout}]
	try {
		puts -nonewline $sock "$method $path HTTP/1.1\r\nHost: localhost\r\nContent-Length: [string length $bytes]\r\nConnection: close\r\n\r\n"
		# Exercise a request body arriving after its headers.
		if {$bytes ne ""} { after 10 [list puts -nonewline $sock $bytes] }
		vwait ::web3dTest::done
		if {$done eq "timeout"} { error "HTTP request timed out" }
		return $response
	} finally {
		after cancel $timer
		close $sock
	}
}

proc ::web3dTest::start {} {
	::board3d::webserver::start [file join $::board3d::LibRoot web3d]
}

tcltest::test web3d-static {index and JavaScript are served intact with HTTP headers} -setup {
	set port [::web3dTest::start]
} -body {
	set index [::web3dTest::request $port GET /index.html]
	set js [::web3dTest::request $port GET /three.min.js]
	set file [open [file join $::board3d::LibRoot web3d three.min.js] rb]
	set expected [read $file]
	close $file
	list [string match {HTTP/1.1 200*} $index] \
		[string match {*Content-Type: text/html*} $index] \
		[string match {*Connection: close*} $index] \
		[string match {*Content-Type: application/javascript*} $js] \
		[expr {[string range $js [expr {[string first "\r\n\r\n" $js]+4}] end] eq $expected}]
} -cleanup {
	::board3d::webserver::stop
} -result {1 1 1 1 1}

tcltest::test web3d-board {direct updates and fragmented JSON POST reach the polling API} -setup {
	set port [::web3dTest::start]
} -body {
	::board3d::webserver::setBoard direct
	set first [::web3dTest::request $port GET /api/board]
	set post [::web3dTest::request $port POST /api/board {{"board":"posted"}}]
	set second [::web3dTest::request $port GET /api/board]
	list [string match {*"board": "direct"*} $first] \
		[string match {*{"status":"ok"}} $post] \
		[string match {*"board": "posted"*} $second]
} -cleanup {
	::board3d::webserver::stop
} -result {1 1 1}

tcltest::test web3d-paths {traversal and absolute filesystem paths return 404} -setup {
	set port [::web3dTest::start]
} -body {
	set results {}
	foreach path {/../tcl/board-3d.tcl /%2e%2e/tcl/board-3d.tcl //etc/passwd /C:/Windows/win.ini /missing.js} {
		lappend results [string match {HTTP/1.1 404*} [::web3dTest::request $port GET $path]]
	}
	set results
} -cleanup {
	::board3d::webserver::stop
} -result {1 1 1 1 1}

tcltest::test web3d-stop {stop closes the listener and incomplete requests; restart works} -body {
	set port [::web3dTest::start]
	set sock [socket 127.0.0.1 $port]
	fconfigure $sock -blocking 0
	update
	::board3d::webserver::stop
	set stopped [catch {socket 127.0.0.1 $port} other]
	if {!$stopped} { close $other }
	set next [::web3dTest::start]
	list $stopped [array size ::board3d::webserver::clients] [expr {$next > 0}]
} -cleanup {
	catch {close $sock}
	::board3d::webserver::stop
} -result {1 0 1}

tcltest::cleanupTests
