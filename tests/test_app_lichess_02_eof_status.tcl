package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

# Real HTTP/NDJSON/PGN responder: deliberately completes 200 streams, rather
# than simulating Done or injecting a status message into the UI.
namespace eval ::scidb::test::eof {
 variable Out [file normalize tests/tmp-app/lichess-hardening/T-gaps4]
 file mkdir $Out
 variable Mode eof
 variable Body {}
 variable Hits {}
 variable Sockets {}
 variable Timers {}
 variable Events {}
}
proc ::scidb::test::eof::Wait {condition} {uplevel 1 [list ::scidb::test::wait::until $condition 5000]}
proc ::scidb::test::eof::Pause {ms} {after $ms {set ::scidb::test::eof::tick 1}; vwait ::scidb::test::eof::tick}
proc ::scidb::test::eof::Accept {s a p} {
 variable Sockets
 lappend Sockets $s
 fconfigure $s -blocking 0 -buffering none -translation binary
 fileevent $s readable [list ::scidb::test::eof::Serve $s]
}
proc ::scidb::test::eof::Serve {s} {
 variable Hits; variable Body; variable Mode; variable Timers
 set data [read $s]
 if {[eof $s]} {catch {close $s}; return}
 if {![regexp {^[A-Z]+ ([^ ]+) HTTP/} $data -> path]} {return}
 fileevent $s readable {}
 if {$path eq "/api/tv/channels" || $path eq "/api/broadcast/top"} {
  puts -nonewline $s "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n\{\}"
  close $s
  return
 }
 lappend Hits [list $path [clock milliseconds]]
 if {$Mode eq "503"} {
  puts -nonewline $s "HTTP/1.1 503 Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
  close $s
  return
 }
 puts -nonewline $s "HTTP/1.1 200 OK\r\nContent-Type: application/x-ndjson\r\nConnection: close\r\n\r\n"
 if {$Mode ne "stall"} {puts -nonewline $s "$Body\n"}
 if {$Mode eq "eof"} {lappend Timers [after 40 [list catch [list close $s]]]}
 if {$Mode eq "hold"} {lappend Timers [after 60 [list ::scidb::test::eof::Heartbeat $s]]}
}
proc ::scidb::test::eof::Heartbeat {s} {
 variable Timers
 if {[catch {puts -nonewline $s "\n"}]} {return}
 lappend Timers [after 60 [list ::scidb::test::eof::Heartbeat $s]]
}
proc ::scidb::test::eof::Observe {event} {lappend ::scidb::test::eof::Events $event}
proc ::scidb::test::eof::Setup {} {
 variable Saved [list $::lichess::api::Base $::lichess::api::StallTimeout $::lichess::api::ReconnectDelays $::lichess::api::RecoveryTimeout]
 ::lichess::Close
 ::lichess::api::signOut
 update
 variable Hits {}; variable Events {}; variable Sockets {}; variable Timers {}
 set ::lichess::tv::Priv(gameId) {}
 variable Mode eof
 variable Body {{"t":"featured","d":{"id":"eof-tv","fen":"startpos","players":[]}}}
 variable Listener [socket -server ::scidb::test::eof::Accept -myaddr 127.0.0.1 0]
 set ::lichess::api::Base http://127.0.0.1:[lindex [fconfigure $Listener -sockname] 2]
 set ::lichess::api::BackoffUntil 0
 set ::lichess::api::StallTimeout 300
 set ::lichess::api::ReconnectDelays {80 240 640}
 set ::lichess::api::RecoveryTimeout 2000
 ::lichess::tv::open
 Wait {[dict size $::lichess::api::Requests] == 0}
 Pause 300
}
proc ::scidb::test::eof::Cleanup {} {
 variable Saved; variable Listener; variable Sockets; variable Timers
 ::lichess::tv::StopStream
 ::lichess::Close
 foreach id [dict keys $::lichess::api::Requests] {::lichess::api::close $id}
 foreach timer $Timers {after cancel $timer}
 foreach s $Sockets {catch {close $s}}
 catch {close $Listener}
 update
 lassign $Saved ::lichess::api::Base ::lichess::api::StallTimeout ::lichess::api::ReconnectDelays ::lichess::api::RecoveryTimeout
 catch {::online::window::closeTab lichess-tv}
}
proc ::scidb::test::eof::Check {actual expected} {if {$actual ne $expected} {error "expected <$expected>, got <$actual>"}}
# The retry/recovery has really completed when its new HTTP attempt has
# received the feed body again: the request is connected, its attempts were
# reset by that activity, and OnTvEvent repopulated the game id. The id is
# cleared before the hold switch so the original body cannot satisfy this.
proc ::scidb::test::eof::StreamLive {h} {
    expr {[dict exists $::lichess::api::Requests $h]
        && ![dict get $::lichess::api::Requests $h lost]
        && [dict get $::lichess::api::Requests $h attempts] == 0
        && [dict get $::lichess::api::Requests $h http] ne {}
        && $::lichess::tv::Priv(gameId) eq "eof-tv"}
}
proc ::scidb::test::eof::Journal {name} {
 variable Out; variable Hits; variable Events
 set f [open [file join $Out $name.txt] w]
 puts $f "Server requests (path, milliseconds): $Hits"
 puts $f "Delivered events: $Events"
 puts $f "Shared status: [.online.status cget -text]"
 close $f
}
proc ::scidb::test::eof::Shot {name} {
 update
 exec import -window [winfo id .online] [file join $::scidb::test::eof::Out $name.png]
}

namespace eval ::scidb::test::eof {
 foreach {kind call body} {
  tv {tvFeed Best} {{"t":"fen","d":{"fen":"startpos"}}}
  event streamEvents {{"type":"challengeCanceled","challenge":{"id":"example"}}}
  board {streamGame example} {{"type":"gameFull","state":{"status":"started","moves":""}}}
  bot {botStreamGame example} {{"type":"gameState","status":"started","moves":""}}
  watch {streamGameMoves example} {{"fen":"startpos","status":{"id":20,"name":"started"}}}
  broadcast {broadcastRoundStream round1} {[Event "Example"]
[White "A"]
[Black "B"]
[Result "*"]

*}
 } {
  ::tcltest::test eof-$kind {200 plus one event plus EOF reconnects with a stable handle and bounded retries} -setup {
   ::scidb::test::eof::Setup
  } -body {
   set ::scidb::test::eof::Body $::scidb::test::eof::body
   set h [::lichess::api::[lindex $::scidb::test::eof::call 0] {*}[lrange $::scidb::test::eof::call 1 end] ::scidb::test::eof::Observe]
   ::scidb::test::eof::Wait {[dict exists $::lichess::api::Requests $h lost] && [dict get $::lichess::api::Requests $h lost]}
   ::scidb::test::eof::Pause 250
   ::scidb::test::eof::Journal eof-$::scidb::test::eof::kind
   ::scidb::test::eof::Check [llength $::scidb::test::eof::Hits] 4
   ::scidb::test::eof::Check [.online.$h.message cget -text] $::lichess::api::mc::Lost
   set times [lmap hit $::scidb::test::eof::Hits {lindex $hit 1}]
   lassign $times a b c d
   ::scidb::test::eof::Check [expr {$b-$a < $c-$b && $c-$b < $d-$c}] 1
   ::scidb::test::eof::Check [expr {[llength $::scidb::test::eof::Events] >= 1}] 1
   set ::scidb::test::eof::Mode hold
   .online.$h.retry invoke
   ::scidb::test::eof::Wait {[llength $::scidb::test::eof::Hits] == 5 && ![winfo exists .online.$h]}
   list [dict exists $::lichess::api::Requests $h] [.online.status cget -text]
  } -cleanup {::scidb::test::eof::Cleanup} -result {1 {}}
 }
}

namespace eval ::scidb::test::eof {
 foreach {kind call body} {
  full {streamGame example} {{"type":"gameFull","state":{"status":"mate","moves":""}}}
  state {botStreamGame example} {{"type":"gameState","status":"resign","moves":""}}
  watch {streamGameMoves example} {{"status":{"id":30,"name":"mate"}}}
  broadcast {broadcastRoundStream round1} {[Event "Example"]
[White "A"]
[Black "B"]
[Result "1-0"]

1-0}
  request {Request GET /api/account {} ::scidb::test::eof::Observe} {{"id":"example","username":"Example"}}
 } {
  ::tcltest::test eof-finished-$kind {finished streams and ordinary requests end without reconnecting} -setup {
   ::scidb::test::eof::Setup
  } -body {
   set ::scidb::test::eof::Body $::scidb::test::eof::body
   if {$::scidb::test::eof::kind eq "request"} {
    set h [::lichess::api::Request GET /api/account {} ::scidb::test::eof::Observe]
   } else {
    set h [::lichess::api::[lindex $::scidb::test::eof::call 0] {*}[lrange $::scidb::test::eof::call 1 end] ::scidb::test::eof::Observe]
   }
   ::scidb::test::eof::Wait {![dict exists $::lichess::api::Requests $h] && [llength $::scidb::test::eof::Events] > 0}
   ::scidb::test::eof::Pause 400
   ::scidb::test::eof::Journal finished-$::scidb::test::eof::kind
   list [llength $::scidb::test::eof::Hits] [dict get [lindex $::scidb::test::eof::Events end] ok]
  } -cleanup {::scidb::test::eof::Cleanup} -result {1 1}
 }
}

tcltest::test eof-user-close {user close cancels EOF recovery and queued retries} -setup {
 ::scidb::test::eof::Setup
} -body {
 set h [::lichess::tv::WatchSelectedChannel Best]
 ::scidb::test::eof::Wait {[llength $::scidb::test::eof::Hits] == 1}
 ::lichess::tv::StopStream
 ::scidb::test::eof::Pause 600
 ::scidb::test::eof::Journal user-close
 list [llength $::scidb::test::eof::Hits] [dict exists $::lichess::api::Requests $h] $::lichess::tv::Priv(streamHandle)
} -cleanup {::scidb::test::eof::Cleanup} -result {1 0 {}}

tcltest::test eof-close-pending {user close during an EOF retry delay prevents another connection} -setup {
 ::scidb::test::eof::Setup
} -body {
 set h [::lichess::tv::WatchSelectedChannel Best]
 ::scidb::test::eof::Wait {[dict exists $::lichess::api::Requests $h] && [dict get $::lichess::api::Requests $h attempts] == 1}
 ::lichess::tv::StopStream
 ::scidb::test::eof::Pause 600
 list [llength $::scidb::test::eof::Hits] [dict exists $::lichess::api::Requests $h] [winfo exists .online.$h]
} -cleanup {::scidb::test::eof::Cleanup} -result {1 0 0}

tcltest::test eof-initial-refused {initial connection refusal uses bounded recovery rather than an expired zero activity clock} -setup {
 ::scidb::test::eof::Setup
} -body {
 close $::scidb::test::eof::Listener
 set h [::lichess::api::tvFeed Best ::scidb::test::eof::Observe]
 ::scidb::test::eof::Wait {[dict get $::lichess::api::Requests $h lost]}
 list [dict get $::lichess::api::Requests $h attempts] [.online.$h.message cget -text]
} -cleanup {::scidb::test::eof::Cleanup} -result {3 {Lichess connection lost.}}

tcltest::test eof-broadcast-mixed {a finished board does not end a round that still contains an unfinished board} -setup {
 ::scidb::test::eof::Setup
} -body {
 set ::scidb::test::eof::Body {[Event "Example"]
[White "A"]
[Black "B"]
[Result "*"]

*

[Event "Example"]
[White "C"]
[Black "D"]
[Result "1-0"]

1-0}
 set h [::lichess::api::broadcastRoundStream round1 ::scidb::test::eof::Observe]
 ::scidb::test::eof::Wait {[dict exists $::lichess::api::Requests $h lost] && [dict get $::lichess::api::Requests $h lost]}
 list [llength $::scidb::test::eof::Hits] [winfo exists .online.$h.retry]
} -cleanup {::scidb::test::eof::Cleanup} -result {4 1}

tcltest::test eof-broadcast-final-update {the latest result replaces a board's earlier ongoing snapshot} -setup {
 ::scidb::test::eof::Setup
} -body {
 set ::scidb::test::eof::Body {[Event "Example"]
[White "A"]
[Black "B"]
[Result "*"]

*

[Event "Example"]
[White "A"]
[Black "B"]
[Result "1/2-1/2"]

1/2-1/2}
 set h [::lichess::api::broadcastRoundStream round1 ::scidb::test::eof::Observe]
 ::scidb::test::eof::Wait {![dict exists $::lichess::api::Requests $h] && [llength $::scidb::test::eof::Events] == 3}
 ::scidb::test::eof::Pause 400
 list [llength $::scidb::test::eof::Hits] [dict get [lindex $::scidb::test::eof::Events end] type]
} -cleanup {::scidb::test::eof::Cleanup} -result {1 closed}

namespace eval ::scidb::test::eof {
 foreach recovery {manual automatic server newer} {
  ::tcltest::test status-$recovery {real recovery clears its own shared error and preserves newer unrelated status} -setup {
   ::scidb::test::eof::Setup
  } -body {
   set ::scidb::test::eof::Mode [expr {$::scidb::test::eof::recovery eq "server" ? "503" : "stall"}]
   set h [::lichess::tv::WatchSelectedChannel Best]
   if {$::scidb::test::eof::recovery in {manual newer}} {
    ::scidb::test::eof::Wait {[dict get $::lichess::api::Requests $h lost]}
   } else {
    ::scidb::test::eof::Wait {[dict get $::lichess::api::Requests $h attempts] > 0}
   }
   set error [.online.status cget -text]
   ::scidb::test::eof::Check [expr {[string match *Lichess* $error]}] 1
   if {$::scidb::test::eof::recovery eq "newer"} {::online::window::status "A newer status"}
   # The recovery was triggered by the shortened probe interval above. The
   # recovered stream then runs at the product's real interval: this server
   # shares the event loop, so a loaded loop cannot send its 60 ms heartbeat
   # and would falsely stall a live stream. The status assertion is still
   # made after the real body arrives, not after an elapsed timer.
   set ::lichess::api::StallTimeout [lindex $::scidb::test::eof::Saved 1]
   set ::scidb::test::eof::Mode hold
   set ::lichess::tv::Priv(gameId) {}
   if {$::scidb::test::eof::recovery in {manual newer}} {.online.$h.retry invoke}
   ::scidb::test::eof::Wait {[::scidb::test::eof::StreamLive $h] && ![winfo exists .online.$h]}
   # Sample the status before Journal/Shot: the screenshot is evidence, while
   # execing it blocks the event loop and must not decide the assertion.
   set actual [.online.status cget -text]
   ::scidb::test::eof::Journal status-$::scidb::test::eof::recovery
   ::scidb::test::eof::Shot status-$::scidb::test::eof::recovery
   set expected [expr {$::scidb::test::eof::recovery eq "newer" ? "A newer status" : ""}]
   list [expr {$actual eq $expected}] [dict get $::lichess::api::Requests $h lost] [expr {$::lichess::tv::Priv(streamHandle) eq $h}]
  } -cleanup {::scidb::test::eof::Cleanup} -result {1 0 1}
 }
}
tcltest::cleanupTests
