# ======================================================================
# test_ai_batch.tcl -- the System One batch helper (tcl/ai-batch.tcl).
#
#   xvfb-run -a ./src/tkchesswiz tests/test_ai_batch.tcl
#
# Covers the contract in docs/ai/SYSTEM_ONE_FEATURES.md §3.3: a concurrency cap,
# de-duplication by state, resume from the sidecar cache, progress, and a
# silent drop to the per-item fallback when the classifier is off or a
# request fails. A mock /v1/systemone answers a choice question by echoing
# the state, so routing can be checked without a model.
# ======================================================================

package require Tcl 8.5

set failures 0

proc check {name cond} {
	global failures
	if {$cond} {
		puts "PASS: $name"
	} else {
		puts "FAIL: $name"
		incr failures
	}
}

set root [file join [file dirname [file normalize [info script]]] ..]
source [file join $root tcl ai-provider.tcl]
source [file join $root tcl ai-systemone.tcl]
source [file join $root tcl ai-batch.tcl]

# --- a mock /v1/systemone ---------------------------------------------
namespace eval ::scidb::test::b {
	variable Server {}
	variable Port 0
	variable Requests {}
	variable Active 0
	variable MaxActive 0
	variable Replies {}
	variable Buffer
	variable Result {}
	variable Flag 0
	variable Progress {}
}

proc ::scidb::test::b::start {{replies {}}} {
	variable Server
	variable Port
	variable Requests
	variable Active
	variable MaxActive
	variable Replies
	set Requests {}
	set Active 0
	set MaxActive 0
	set Replies $replies
	set Server [socket -server ::scidb::test::b::Accept -myaddr 127.0.0.1 0]
	set Port [lindex [fconfigure $Server -sockname] 2]
	::ai::systemone::configure -backend kev -endpoint http://127.0.0.1:$Port/v1/systemone -apiKey ""
	return
}

proc ::scidb::test::b::stop {} {
	variable Server
	catch { close $Server }
	set Server {}
	::ai::systemone::configure -backend off
	return
}

proc ::scidb::test::b::Accept {chan addr port} {
	variable Active
	variable MaxActive
	variable Buffer
	incr Active
	if {$Active > $MaxActive} { set MaxActive $Active }
	set Buffer($chan) ""
	fconfigure $chan -translation binary -blocking 0
	fileevent $chan readable [list ::scidb::test::b::Serve $chan]
	return
}

proc ::scidb::test::b::Done {chan} {
	variable Active
	variable Buffer
	if {[info exists Buffer($chan)]} { unset Buffer($chan) }
	if {$Active > 0} { incr Active -1 }
	return
}

proc ::scidb::test::b::Serve {chan} {
	variable Buffer
	append Buffer($chan) [::read $chan]
	set end [string first "\r\n\r\n" $Buffer($chan)]
	if {$end < 0} {
		if {[eof $chan]} { catch { close $chan }; Done $chan }
		return
	}
	set head [string range $Buffer($chan) 0 [expr {$end - 1}]]
	set body [string range $Buffer($chan) [expr {$end + 4}] end]
	set length 0
	foreach line [split $head \n] {
		if {[regexp -nocase {^content-length:\s*(\d+)} [string trim $line] -> n]} { set length $n }
	}
	if {[string length $body] < $length} { return }

	unset Buffer($chan)
	fileevent $chan readable {}
	::scidb::test::b::Reply $chan $body
	return
}

proc ::scidb::test::b::Reply {chan body} {
	variable Requests
	variable Replies
	lappend Requests $body
	lassign [Next $body] code reply
	set reply [encoding convertto utf-8 $reply]
	fconfigure $chan -blocking 1
	catch {
		puts -nonewline $chan "HTTP/1.1 $code X\r\nContent-Type: application/json\r\nContent-Length: [string length $reply]\r\nConnection: close\r\n\r\n$reply"
	}
	catch { close $chan }
	Done $chan
	return
}

# A queued {code body} wins; otherwise echo the state as the choice.
proc ::scidb::test::b::Next {body} {
	variable Replies
	if {[llength $Replies]} {
		set r [lindex $Replies 0]
		set Replies [lrange $Replies 1 end]
		return $r
	}
	set state ""
	regexp {"state":"([^"]*)"} $body -> state
	return [list 200 "{\"model\":\"kev-latest\",\"answers\":{\"q\":{\"type\":\"choice\",\"choice\":\"$state\",\"confidence\":0.9,\"probabilities\":{\"$state\":0.9}}},\"latency_ms\":1}"]
}

# --- result plumbing ---------------------------------------------------
proc ::scidb::test::b::deliver {result} {
	set ::scidb::test::b::Result $result
	set ::scidb::test::b::Flag 1
	return
}

proc ::scidb::test::b::note {done total} {
	lappend ::scidb::test::b::Progress [list $done $total]
	return
}

# Run and block until the batch resolves (or 5 s).
proc ::scidb::test::b::collect {items question args} {
	variable Result
	variable Flag
	variable Progress
	set Result {}
	set Flag 0
	set Progress {}
	set id [::ai::batch::run $items $question ::scidb::test::b::deliver {*}$args]
	set timer [after 5000 [list set ::scidb::test::b::Flag timeout]]
	vwait ::scidb::test::b::Flag
	after cancel $timer
	return $Result
}

set Q {type choice instructions "Which state?" criteria {s1 "one" s2 "two" s3 "three" s4 "four"}}

# --- basic: one request per distinct state -----------------------------
::scidb::test::b::start
set r [::scidb::test::b::collect {{k1 s1} {k2 s2} {k3 s3}} $Q -concurrency 1]
set res [dict get $r results]
check "basic: three answers" [expr {[dict size $res] == 3}]
check "basic: keys route to their state" [expr {
	[dict get $res k1 answer choice] eq "s1"
	&& [dict get $res k2 answer choice] eq "s2"
	&& [dict get $res k3 answer choice] eq "s3"
}]
check "basic: three requests" [expr {[llength $::scidb::test::b::Requests] == 3}]
::scidb::test::b::stop

# --- a bare (unpaired) item is refused, never split into key and state ---
check "bare item: refused" [catch {::ai::batch::run {"a fine quiet move"} $Q {} } msg]

# --- dedupe: identical states share one request ------------------------
::scidb::test::b::start
set r [::scidb::test::b::collect {{k1 s1} {k2 s1} {k3 s2}} $Q -concurrency 1]
set res [dict get $r results]
check "dedupe: three keys" [expr {[dict size $res] == 3}]
check "dedupe: two requests" [expr {[llength $::scidb::test::b::Requests] == 2}]
check "dedupe: shared state answers both keys" [expr {
	[dict get $res k1 answer choice] eq "s1" && [dict get $res k2 answer choice] eq "s1"
}]
::scidb::test::b::stop

# --- concurrency cap ---------------------------------------------------
::scidb::test::b::start
set r [::scidb::test::b::collect {{k1 s1} {k2 s2} {k3 s3} {k4 s4}} $Q -concurrency 2]
check "concurrency: all four answered" [expr {[dict size [dict get $r results]] == 4}]
check "concurrency: cap respected" [expr {$::scidb::test::b::MaxActive <= 2}]
check "concurrency: cap actually reached" [expr {$::scidb::test::b::MaxActive == 2}]
::scidb::test::b::stop

# --- progress ----------------------------------------------------------
::scidb::test::b::start
set r [::scidb::test::b::collect {{k1 s1} {k2 s2} {k3 s3}} $Q -concurrency 1 -progress ::scidb::test::b::note]
set progress $::scidb::test::b::Progress
check "progress: called once per state" [expr {[llength $progress] == 3}]
check "progress: final done==total" [expr {[lindex $progress end] eq {3 3}}]
::scidb::test::b::stop

# --- resume from the cache --------------------------------------------
set cache [file join [file dirname [file normalize [info script]]] tmp-app batch-cache-[pid].txt]
catch { file delete $cache }
::scidb::test::b::start
set first [::scidb::test::b::collect {{k1 s1} {k2 s2}} $Q -concurrency 1 -cache $cache]
check "cache: first run sends two requests" [expr {[llength $::scidb::test::b::Requests] == 2}]
set ::scidb::test::b::Requests {}
set second [::scidb::test::b::collect {{k1 s1} {k2 s2}} $Q -concurrency 1 -cache $cache]
check "cache: second run sends no requests" [expr {[llength $::scidb::test::b::Requests] == 0}]
check "cache: answers survive" [expr {
	[dict get $second results k1 answer choice] eq [dict get $first results k1 answer choice]
	&& [dict get $second results k2 answer choice] eq [dict get $first results k2 answer choice]
}]
check "cache: served from cache" [expr {[dict get $second results k1 source] eq "cache"}]
::scidb::test::b::stop
catch { file delete $cache }

# --- classifier off: every item falls back -----------------------------
::scidb::test::b::start
::ai::systemone::configure -backend off
set r [::scidb::test::b::collect {{k1 s1} {k2 s2}} $Q -concurrency 1]
::scidb::test::b::stop
check "off: no requests" [expr {[llength $::scidb::test::b::Requests] == 0}]
check "off: every item has an error" [expr {
	![dict get [dict get $r results k1] ok] && ![dict get [dict get $r results k2] ok]
}]

# --- one state fails; the rest still answer ----------------------------
::scidb::test::b::start [list [list 500 "{\"error\":\"boom\"}"]]
set r [::scidb::test::b::collect {{k1 s1} {k2 s2} {k3 s3}} $Q -concurrency 1]
set res [dict get $r results]
check "error: the failing state falls back" [expr {![dict get $res k1 ok]}]
check "error: the rest answer" [expr {
	[dict get $res k2 ok] && [dict get $res k3 ok]
}]
::scidb::test::b::stop

puts "AI-BATCH-FAILURES: $failures"
exit $failures
