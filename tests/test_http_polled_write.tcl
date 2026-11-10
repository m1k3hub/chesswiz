# HTTP request bodies on Windows (review finding NET-10): the writer that
# works around tcltls's missing writable events must never block, so a
# peer that stops reading ends in the request's timeout; and it must still
# deliver a large body over a channel that raises no writable events.
# Headless, local sockets only. Each case runs in a child tclsh with a
# hard time limit, so a writer that blocks fails instead of hanging.
#   tclsh tests/test_http_polled_write.tcl
package require tcltest 2.5
namespace import ::tcltest::*
set root [file normalize [file join [file dirname [info script]] ..]]

if {[lindex $argv 0] eq "child"} {
	source $root/tcl/contrib/http.tcl
	source $root/tcl/sys-platform.tcl
	::platform::sys::PolledHttpWrite

	# A channel like tcltls on Windows: once its 64 KB of room is full it
	# refuses writes and never raises a writable event again.
	namespace eval mock {
		variable sock; variable stalled
		proc open {args} {
			variable sock; variable stalled
			set s [socket [lindex $args end-1] [lindex $args end]]
			fconfigure $s -blocking 0 -translation binary -buffering none
			set c [chan create {read write} ::mock::handler]
			set sock($c) $s
			set stalled($c) 0
			return $c
		}
		proc handler {cmd c args} {
			variable sock; variable stalled
			switch $cmd {
				initialize { return {initialize finalize watch read write cget cgetall} }
				cget { return [fconfigure $sock($c) [lindex $args 0]] }
				cgetall { return [list -error [fconfigure $sock($c) -error]] }
				finalize { catch { close $sock($c) }; unset sock($c) }
				watch {
					set events [lindex $args 0]
					if {"read" in $events} {
						fileevent $sock($c) readable [list ::mock::readable $c]
					} else {
						fileevent $sock($c) readable {}
					}
					if {"write" in $events && !$stalled($c)} {
						after 0 [list catch [list chan postevent $c write]]
					}
				}
				read {
					set data [read $sock($c) [lindex $args 0]]
					if {$data eq "" && ![eof $sock($c)]} { return -code error EAGAIN }
					return $data
				}
				write {
					if {[chan pending output $sock($c)] > 65536} {
						set stalled($c) 1
						return -code error EAGAIN
					}
					set data [lindex $args 0]
					puts -nonewline $sock($c) $data
					return [string length $data]
				}
			}
		}
		proc readable {c} { catch { chan postevent $c read } }
	}

	# replies with the number of body bytes it received
	proc accept {s args} {
		fconfigure $s -blocking 0 -translation binary
		set ::buf($s) ""
		fileevent $s readable [list collect $s]
	}
	proc collect {s} {
		append ::buf($s) [read $s]
		set head [string first "\r\n\r\n" $::buf($s)]
		if {$head < 0} { if {[eof $s]} { close $s }; return }
		regexp -nocase {content-length: *([0-9]+)} $::buf($s) -> want
		set got [expr {[string length $::buf($s)] - $head - 4}]
		if {$got < $want} { if {[eof $s]} { close $s }; return }
		puts -nonewline $s "HTTP/1.0 200 OK\r\nContent-Length: [string length $got]\r\n\r\n$got"
		close $s
	}
	proc ignore {s args} { set ::idle $s } ;# accepts and never reads

	proc post {url body timeout {block 8192}} {
		set ::tick 0
		proc beat {} { incr ::tick; after 50 beat }
		beat
		set tok [::http::geturl $url -query $body -timeout $timeout -queryblocksize $block \
			-type application/octet-stream -command [list set ::done]]
		vwait ::done
		set r [list [::http::status $tok] [::http::data $tok] [expr {$::tick > 5}]]
		::http::cleanup $tok
		return $r
	}

	switch [lindex $argv 1] {
		stalled-peer {
			set srv [socket -server ignore -myaddr 127.0.0.1 0]
			set port [lindex [fconfigure $srv -sockname] 2]
			# far more than the kernel buffers hold, in blocks larger than
			# their room: a blocking write of one block cannot finish
			set r [post http://127.0.0.1:$port/ [string repeat x 64000000] 1500 4000000]
			puts [lrange $r 0 0][lrange $r 2 2]
		}
		no-write-events {
			set srv [socket -server accept -myaddr 127.0.0.1 0]
			set port [lindex [fconfigure $srv -sockname] 2]
			::http::register mock 80 ::mock::open
			puts [post mock://127.0.0.1:$port/ [string repeat y 300000] 10000]
		}
	}
	exit 0
}

proc child {case} {
	set rc [catch {
		exec timeout 30 [info nameofexecutable] [info script] child $case 2>@1
	} out]
	if {$rc} { return "child failed: $out" }
	return $out
}

test http-polled-write-timeout {a peer that stops reading ends in the timeout; the event loop keeps running} -body {
	child stalled-peer
} -result {timeout1}

test http-polled-write-no-events {a large body is delivered over a channel without writable events} -body {
	child no-write-events
} -result {ok 300000 1}

cleanupTests
