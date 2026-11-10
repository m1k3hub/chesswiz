# ======================================================================
# Scidb App Test — ::web::downloadURL (review findings NET-12, NET-13):
# the default save path gets its -filetypes, and each attempt uses its
# own request timeout. A local HTTP server stands in for the web.
# ======================================================================

package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

namespace eval ::scidb::test::web {
	variable Server {}
	variable Port 0
	variable Mode ok
	variable Requests 0
	variable Saved {}
	variable Done 0
}

# <mode>: ok answers at once; silent never answers the first <n> requests
proc ::scidb::test::web::Start {mode} {
	variable Server
	variable Port
	variable Mode $mode
	variable Requests 0
	set Server [socket -server ::scidb::test::web::Accept -myaddr 127.0.0.1 0]
	set Port [lindex [fconfigure $Server -sockname] 2]
}

proc ::scidb::test::web::Stop {} {
	variable Server
	catch { close $Server }
}

proc ::scidb::test::web::Accept {chan addr port} {
	variable Mode
	variable Requests
	incr Requests
	fconfigure $chan -blocking 0 -translation binary
	if {$Mode eq "silent" && $Requests <= 1} { return }
	fileevent $chan readable [list ::scidb::test::web::Answer $chan]
}

proc ::scidb::test::web::Answer {chan} {
	if {[gets $chan line] < 0 && ![eof $chan]} { return }
	if {[string trim $line] ne "" && ![eof $chan]} { return }
	fileevent $chan readable {}
	puts -nonewline $chan "HTTP/1.0 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nhello"
	close $chan
}

tcltest::test web-download-default-save {the default save dialog gets the -filetypes} -setup {
	::scidb::test::web::Start ok
	rename ::dialog::saveFile ::scidb::test::web::realSaveFile
	proc ::dialog::saveFile {args} {
		set ::scidb::test::web::Saved [dict get $args -filetypes]
		set ::scidb::test::web::Done 1
		return ""
	}
	set ::scidb::test::web::Done 0
} -body {
	::web::downloadURL . http://127.0.0.1:$::scidb::test::web::Port/x.txt \
		-filetypes {{Text .txt}}
	::scidb::test::wait::until {$::scidb::test::web::Done} 5000
	set ::scidb::test::web::Saved
} -cleanup {
	rename ::dialog::saveFile {}
	rename ::scidb::test::web::realSaveFile ::dialog::saveFile
	::scidb::test::web::Stop
} -result {{Text .txt}}

tcltest::test web-download-retry-timeout {a retry after a timeout gets the second request timeout} -setup {
	::scidb::test::web::Start silent
	set ::scidb::test::web::Done 0
	proc ::scidb::test::web::Got {parent url data} {
		set ::scidb::test::web::Done [list [clock milliseconds] $data]
	}
} -body {
	set t0 [clock milliseconds]
	# first request times out after 300 ms, the retry has 4000 ms (the
	# old code used the 4000 as the pause and gave the retry only 5000's
	# fallback after skipping it)
	::web::downloadURL . http://127.0.0.1:$::scidb::test::web::Port/x.txt \
		-timeouts {300 4000} -retrydelay 100 -successcmd ::scidb::test::web::Got
	::scidb::test::wait::until {$::scidb::test::web::Done ne "0"} 10000
	lassign $::scidb::test::web::Done t data
	list $data [expr {$t - $t0 < 2000}] $::scidb::test::web::Requests
} -cleanup {
	::scidb::test::web::Stop
} -result {hello 1 2}

tcltest::cleanupTests
