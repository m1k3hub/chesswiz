package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
source [file join [file dirname [info script]] lichess_fake_server.tcl]
::scidb::test::wait::ready
namespace eval ::scidb::test::ls {
 variable Out [file normalize tests/tmp-app/lichess-hardening/stream-errors]
 file mkdir $Out
}
proc ::scidb::test::ls::Wait {condition {ms 10000}} { uplevel 1 [list ::scidb::test::wait::until $condition $ms] }
proc ::scidb::test::ls::Pause {ms} { after $ms {set ::scidb::test::ls::paused 1}; vwait ::scidb::test::ls::paused }
proc ::scidb::test::ls::Setup {} {
 variable Base $::lichess::api::Base
 variable OpenTimes {}
 rename ::lichess::fake::Handle ::lichess::fake::HandleWithoutJournal
 proc ::lichess::fake::Handle {chan} {
  set c [dict get $::lichess::fake::Connections $chan]
  lappend ::scidb::test::ls::OpenTimes [dict create path [lindex [split [dict get $c target] ?] 0] id [dict get $c id] time [clock milliseconds]]
  ::lichess::fake::HandleWithoutJournal $chan
 }
 ::lichess::api::signOut
 set ::lichess::api::Base [::lichess::fake::Start]
 set ::lichess::api::BackoffUntil 0
 set ::lichess::fake::Token [::lichess::testToken]
 ::lichess::api::TokenStore $::lichess::fake::Token
 set ::lichess::Priv(state) offline
 set ::lichess::tv::Priv(gameId) {}
 catch {destroy .online.sessionExpired}
 set ::lichess::api::StallTimeout 20000
 set ::lichess::api::ReconnectDelays {1000 3000 9000}
}
proc ::scidb::test::ls::Cleanup {} {
 ::lichess::tv::StopStream
 ::lichess::Close
 ::lichess::api::signOut
 foreach id [dict keys $::lichess::api::Requests] { ::lichess::api::close $id }
 update
 ::lichess::fake::Stop
 rename ::lichess::fake::Handle {}
 rename ::lichess::fake::HandleWithoutJournal ::lichess::fake::Handle
 set ::lichess::api::StallTimeout 20000
 set ::lichess::api::ReconnectDelays {1000 3000 9000}
 set ::lichess::api::Base $::scidb::test::ls::Base
 catch {::online::window::closeTab lichess-tv}
}
proc ::scidb::test::ls::Paths {} { lmap r [::lichess::fake::Requests] {dict get $r path} }
proc ::scidb::test::ls::Closed {} { lmap r [::lichess::fake::Closes] {dict get $r path} }
proc ::scidb::test::ls::Shot {name} {
 update
 exec import -window [winfo id .online] [file join $::scidb::test::ls::Out $name.png]
}
proc ::scidb::test::ls::Journal {name} {
 set f [open [file join $::scidb::test::ls::Out $name.txt] w]
 puts $f "Requests size: [dict size $::lichess::api::Requests]"
 puts $f "Server open times: $::scidb::test::ls::OpenTimes"
 puts $f "Server requests: [::lichess::fake::Requests]"
 puts $f "Server closes: [::lichess::fake::Closes]"
 close $f
}

tcltest::test stream-001 {stop, switch, and tab close release TV streams; stopped board cannot move} -setup {
 ::scidb::test::ls::Setup
} -body {
 ::lichess::tv::open
 ::lichess::tv::WatchSelectedChannel Best
 ::scidb::test::ls::Wait {$::lichess::tv::Priv(gameId) eq "tv1"}
 set before [dict size $::lichess::api::Requests]
 set fen $::lichess::tv::Priv(currentFen)
 $::lichess::tv::Priv(widget:top).left.channels.btns.stop invoke
 ::scidb::test::ls::Wait {"/api/tv/best/feed" in [::scidb::test::ls::Closed]}
 ::lichess::fake::EmitTv [dict create t fen d [dict create fen {8/8/8/8/8/8/8/K6k w - - 0 1}]]
 ::scidb::test::ls::Pause 100
 set stopped [expr {$fen eq $::lichess::tv::Priv(currentFen)}]
 set after [dict size $::lichess::api::Requests]
 ::scidb::test::ls::Shot stream-001-stop
 ::lichess::tv::WatchSelectedChannel Best
 ::scidb::test::ls::Wait {"/api/tv/best/feed" in [::scidb::test::ls::Paths] && [dict size $::lichess::api::Requests] == 1}
 ::lichess::tv::WatchSelectedChannel Blitz
 ::scidb::test::ls::Wait {"/api/tv/blitz/feed" in [::scidb::test::ls::Paths]}
 set active 0
 dict for {s c} $::lichess::fake::Connections {if {[dict get $c kind] eq "tv"} {incr active}}
 ::online::window::closeTab lichess-tv
 ::scidb::test::ls::Wait {[dict size $::lichess::api::Requests] == 0 && "/api/tv/blitz/feed" in [::scidb::test::ls::Closed]}
 ::scidb::test::ls::Journal stream-001
 puts "STREAM-001 Requests before=$before after-stop=$after after-tab=[dict size $::lichess::api::Requests], active-after-switch=$active, FEN-unchanged=$stopped"
 list $stopped $after [expr {$active <= 1}]
} -cleanup {::scidb::test::ls::Cleanup} -result {1 0 1}

tcltest::test stream-002 {unfollow and closing Online release broadcast, TV, event and game streams} -setup {
 ::scidb::test::ls::Setup
} -body {
 ::lichess::open .application
 ::lichess::tv::open
 ::lichess::tv::FollowBroadcastRound round1
 ::scidb::test::ls::Wait {"/api/stream/broadcast/round/round1.pgn" in [::scidb::test::ls::Paths]}
 ::lichess::tv::StopStream
 ::scidb::test::ls::Wait {"/api/stream/broadcast/round/round1.pgn" in [::scidb::test::ls::Closed]}
 ::lichess::tv::FollowBroadcastRound round1
 set event [::lichess::api::streamEvents {apply {{r} {}}}]
 set gid [::lichess::fake::CreateGame white ai 1 600 0]
 set game [::lichess::api::streamGame $gid {apply {{r} {}}}]
 set tv [::lichess::api::tvFeed Best {apply {{r} {}}}]
 ::scidb::test::ls::Wait {[llength [::scidb::test::ls::Paths]] >= 6}
 uplevel #0 [wm protocol .online WM_DELETE_WINDOW]
 ::scidb::test::ls::Pause 150
 ::scidb::test::ls::Wait {"/api/stream/event" in [::scidb::test::ls::Closed] && "/api/board/game/stream/$gid" in [::scidb::test::ls::Closed] && "/api/tv/best/feed" in [::scidb::test::ls::Closed]}
 ::scidb::test::ls::Journal stream-002
 set errors 0
 if {[file exists $::env(SCIDB_ERROR_LOG)]} {set errors [file size $::env(SCIDB_ERROR_LOG)]}
 list [dict size $::lichess::api::Requests] $errors
} -cleanup {::scidb::test::ls::Cleanup} -result {0 0}



proc ::scidb::test::ls::Call {args} {
 unset -nocomplain ::scidb::test::ls::reply
 ::lichess::api::[lindex $args 0] {*}[lrange $args 1 end] [list set ::scidb::test::ls::reply]
 Wait {[info exists ::scidb::test::ls::reply]}
 return $::scidb::test::ls::reply
}
proc ::scidb::test::ls::Times {path} {lmap r $::scidb::test::ls::OpenTimes {if {[dict get $r path] ne $path} continue; dict get $r time}}
proc ::scidb::test::ls::Hits {path} {llength [lsearch -all -exact [Paths] $path]}
proc ::scidb::test::ls::Check {actual expected} {if {$actual ne $expected} {error "expected <$expected>, got <$actual>"}}

foreach code {500 502 503 302 304} {
 tcltest::test errors-$code {HTTP errors are distinct and a follow-up request works} -setup {
  ::scidb::test::ls::Setup
 } -body {
  ::lichess::fake::ForceNext /api/tv/channels $code
  set r [::scidb::test::ls::Call tvChannels]
  set expected [expr {$code >= 500 ? "Lichess server error ($code)" : "Lichess unexpected response ($code)"}]
  ::scidb::test::ls::Check [dict get $r error] $expected
  ::lichess::open .application
  ::lichess::Status [dict get $r error]
  ::scidb::test::ls::Shot errors-$code
  puts "HTTP $code: [dict get $r error]"
  dict get [::scidb::test::ls::Call tvChannels] ok
 } -cleanup {::scidb::test::ls::Cleanup} -result 1
}

tcltest::test errors-refused {refused connection is a network error; following request works} -setup {
 ::scidb::test::ls::Setup
} -body {
 set listener [socket -server {apply {{args} {}}} -myaddr 127.0.0.1 0]
 set port [lindex [fconfigure $listener -sockname] 2]
 close $listener
 set base $::lichess::api::Base
 set ::lichess::api::Base http://127.0.0.1:$port
 set r [::scidb::test::ls::Call tvChannels]
 set ::lichess::api::Base $base
 puts "Refused: [dict get $r error]"
 list [dict get $r error] [dict get [::scidb::test::ls::Call tvChannels] ok]
} -cleanup {::scidb::test::ls::Cleanup} -result {{Could not complete the Lichess request.} 1}

tcltest::test errors-401-request {authenticated 401 deletes the real token file, closes streams and offers sign-in once} -setup {
 ::scidb::test::ls::Setup
} -body {
 ::lichess::open .application
 ::lichess::tv::open
 ::lichess::tv::WatchSelectedChannel Best
 ::scidb::test::ls::Wait {$::lichess::tv::Priv(gameId) eq "tv1"}
 ::lichess::fake::ForceNext /api/user/alice 401
 set r [::scidb::test::ls::Call user alice]
 ::scidb::test::ls::Wait {[dict size $::lichess::api::Requests] == 0}
 ::scidb::test::ls::Wait {"/api/tv/best/feed" in [::scidb::test::ls::Closed]}
 ::scidb::test::ls::Check [file exists [::lichess::api::TokenFile]] 0
 ::scidb::test::ls::Check $::lichess::Priv(state) offline
 ::scidb::test::ls::Check [winfo exists .online.sessionExpired.signin] 1
 set panel .online.sessionExpired
 ::lichess::fake::ForceNext /api/user/alice 401
 ::scidb::test::ls::Call user alice
 ::scidb::test::ls::Check [llength [lsearch -all -exact [winfo children .online] $panel]] 1
 ::scidb::test::ls::Shot errors-401-session
 ::scidb::test::ls::Journal errors-401-request
 puts "401: token-file absent; offline; streams=0; session-message-count=1"
 dict get $r status
} -cleanup {::scidb::test::ls::Cleanup} -result 401

tcltest::test errors-401-validation {invalid useToken stores nothing and does not expire a session} -setup {
 ::scidb::test::ls::Setup
} -body {
 ::lichess::api::TokenDelete
 ::lichess::fake::ForceNext /api/account 401
 set r [::scidb::test::ls::Call useToken invalid-fixture]
 list [dict get $r error] [file exists [::lichess::api::TokenFile]] [winfo exists .online.sessionExpired]
} -cleanup {::scidb::test::ls::Cleanup} -result {{Invalid Lichess token. Please check it and try again.} 0 0}

tcltest::test errors-401-anonymous {anonymous 401 never signs out or creates an expired-session message} -setup {
 ::scidb::test::ls::Setup
} -body {
 ::lichess::api::TokenDelete
 set epoch $::lichess::api::Epoch
 ::lichess::fake::ForceNext /api/tv/channels 401
 set r [::scidb::test::ls::Call tvChannels]
 list [expr {$epoch == $::lichess::api::Epoch}] [winfo exists .online.sessionExpired] [dict get $r status]
} -cleanup {::scidb::test::ls::Cleanup} -result {1 0 401}

foreach endpoint {tv event game broadcast} {
 tcltest::test errors-401-stream-$endpoint {401 on each stream type expires the session and closes every stream} -setup {
  ::scidb::test::ls::Setup
 } -body {
  ::lichess::open .application
  ::lichess::tv::open
  ::lichess::tv::WatchSelectedChannel Best
  ::scidb::test::ls::Pause 80
  switch $endpoint {
   tv {set path /api/tv/blitz/feed; set call {tvFeed Blitz}}
   event {set path /api/stream/event; set call {streamEvents}}
   game {set gid [::lichess::fake::CreateGame white ai 1 600 0]; set path /api/board/game/stream/$gid; set call [list streamGame $gid]}
   broadcast {set path /api/stream/broadcast/round/round1.pgn; set call {broadcastRoundStream round1}}
  }
  ::lichess::fake::ForceNext $path 401
  set r [::scidb::test::ls::Call {*}$call]
  ::scidb::test::ls::Pause 80
  ::scidb::test::ls::Journal errors-401-stream-$endpoint
  list [file exists [::lichess::api::TokenFile]] [dict size $::lichess::api::Requests] $::lichess::Priv(state)
 } -cleanup {::scidb::test::ls::Cleanup} -result {0 0 offline}
}

foreach value {{} 0 -1 banana {Wed, 21 Oct 2015 07:28:00 GMT} 7200} {
 tcltest::test errors-429-value-[string map {{ } _ , {}} $value] {Retry-After fallback and cap} -setup {
  ::scidb::test::ls::Setup
 } -body {
  ::lichess::fake::ForceNext /api/tv/channels 429 $value
  set now [clock milliseconds]
  set r [::scidb::test::ls::Call tvChannels]
  set n [expr {$value eq "7200" ? 3600 : 60}]
  set delta [expr {$::lichess::api::BackoffUntil-$now}]
  ::scidb::test::ls::Check [dict get $r error] "Lichess rate limit reached. Please wait $n seconds."
  puts "Retry-After <$value>: delay=$delta ms, message=[dict get $r error]"
  expr {abs($delta-$n*1000) <= 2000}
 } -cleanup {::scidb::test::ls::Cleanup} -result 1
}

tcltest::test errors-429-queue {two-second backoff sends queued requests once and leaves open streams alive} -setup {
 ::scidb::test::ls::Setup
} -body {
 ::lichess::tv::open
 ::lichess::tv::WatchSelectedChannel Best
 ::scidb::test::ls::Wait {$::lichess::tv::Priv(gameId) eq "tv1"}
 set h $::lichess::tv::Priv(streamHandle)
 ::lichess::fake::ForceNext /api/tv/channels 429 2
 set r [::scidb::test::ls::Call tvChannels]
 set at [expr {$::lichess::api::BackoffUntil - 2000}]
 set ::scidb::test::ls::queued 0
 ::lichess::api::user alice {apply {{r} {incr ::scidb::test::ls::queued}}}
 ::lichess::api::user bob {apply {{r} {incr ::scidb::test::ls::queued}}}
 ::lichess::Status [dict get $r error]
 ::scidb::test::ls::Shot errors-429
 ::scidb::test::ls::Pause 500
 ::scidb::test::ls::Check [::scidb::test::ls::Hits /api/user/alice] 0
 ::scidb::test::ls::Wait {$::scidb::test::ls::queued == 2}
 set elapsed [expr {[clock milliseconds]-$at}]
 ::lichess::fake::EmitTv [dict create t fen d [dict create fen {8/8/8/8/8/8/8/K6k w - - 0 1}]]
 ::scidb::test::ls::Wait {$::lichess::tv::Priv(currentFen) eq "8/8/8/8/8/8/8/K6k w - - 0 1"}
 puts "429 N=2 queued delivery elapsed=$elapsed ms; hits alice=[::scidb::test::ls::Hits /api/user/alice] bob=[::scidb::test::ls::Hits /api/user/bob], stream-still-active=[dict exists $::lichess::api::Requests $h]"
 list [expr {$elapsed >= 2000 && $elapsed < 4000}] [::scidb::test::ls::Hits /api/user/alice] [::scidb::test::ls::Hits /api/user/bob] [dict exists $::lichess::api::Requests $h]
} -cleanup {::scidb::test::ls::Cleanup} -result {1 1 1 1}

foreach kind {tv event game broadcast} {
 tcltest::test stall-$kind {silent streams reconnect three times with increasing delays, give up and offer functional Retry} -setup {
  ::scidb::test::ls::Setup
 } -body {
  ::lichess::tv::open
  set ::lichess::api::StallTimeout 120
  set ::lichess::api::ReconnectDelays {50 150 450}
  switch $kind {
   tv {set path /api/tv/blitz/feed; set call {tvFeed Blitz}}
   event {set path /api/stream/event; set call {streamEvents}}
   game {set gid [::lichess::fake::CreateGame white ai 1 600 0]; set path /api/board/game/stream/$gid; set call [list streamGame $gid]}
   broadcast {set path /api/stream/broadcast/round/round1.pgn; set call {broadcastRoundStream round1}}
  }
  ::lichess::fake::Control $path stall
  set h [::lichess::api::[lindex $call 0] {*}[lrange $call 1 end] {apply {{r} {}}}]
  set times {}
  for {set n 1} {$n <= 4} {incr n} {
   ::scidb::test::ls::Wait {[::scidb::test::ls::Hits $path] == $n}
   lappend times [clock milliseconds]
  }
  ::scidb::test::ls::Wait {[winfo ismapped .online.$h.retry]}
  set status [.online.$h.message cget -text]
  ::scidb::test::ls::Pause 250
  ::scidb::test::ls::Check [::scidb::test::ls::Hits $path] 4
  set times [::scidb::test::ls::Times $path]
  set intervals {}
  foreach a [lrange $times 0 end-1] b [lrange $times 1 end] {lappend intervals [expr {$b-$a}]}
  lassign $intervals d1 d2 d3
  ::scidb::test::ls::Shot stall-$kind
  ::lichess::fake::ClearControl $path
  .online.$h.retry invoke
  ::scidb::test::ls::Wait {[::scidb::test::ls::Hits $path] == 5}
  ::scidb::test::ls::Journal stall-$kind
  puts "STALL $kind opens=$times intervals=$intervals status=<$status> Retry opens fifth connection"
  list [expr {$d1 < $d2 && $d2 < $d3}] $status [expr {[llength [::lichess::fake::Closes]] >= 4}]
 } -cleanup {::scidb::test::ls::Cleanup} -result {1 {Lichess connection lost.} 1}
}

tcltest::test stall-keepalive {blank keepalives alone reset the watchdog} -setup {
 ::scidb::test::ls::Setup
} -body {
 ::lichess::fake::Set keepAlive 40
 set ::lichess::api::StallTimeout 140
 ::lichess::fake::Control /api/tv/best/feed keepalive
 set h [::lichess::api::tvFeed Best {apply {{r} {}}}]
 ::scidb::test::ls::Pause 800
 list [::scidb::test::ls::Hits /api/tv/best/feed] [dict get $::lichess::api::Requests $h attempts]
} -cleanup {::scidb::test::ls::Cleanup} -result {1 0}

tcltest::test stall-5xx {stream 503 uses reconnect and recovers on the next successful response} -setup {
 ::scidb::test::ls::Setup
} -body {
 ::lichess::tv::open
 set ::lichess::api::ReconnectDelays {50 150 450}
 ::lichess::fake::ForceNext /api/tv/best/feed 503
 ::lichess::tv::WatchSelectedChannel Best
 ::scidb::test::ls::Wait {[::scidb::test::ls::Hits /api/tv/best/feed] == 2 && $::lichess::tv::Priv(gameId) eq "tv1"}
 set h $::lichess::tv::Priv(streamHandle)
 ::scidb::test::ls::Journal stall-5xx
 list [dict exists $::lichess::api::Requests $h] [winfo exists .online.$h]
} -cleanup {::scidb::test::ls::Cleanup} -result {1 0}

tcltest::test stall-game-resync {replayed gameFull after reconnect adopts server moves without applying them twice} -setup {
 ::scidb::test::ls::Setup
} -body {
 ::lichess::open .application
 set ::lichess::api::ReconnectDelays {50 150 450}
 set ::lichess::api::StallTimeout 300
 set gid [::lichess::fake::CreateGame white ai 1 600 0]
 ::lichess::OpenGame [dict create id $gid color white]
 ::scidb::test::ls::Wait {$::lichess::Priv(active)}
 dict set ::lichess::fake::Games $gid moves {e2e4 e7e5}
 ::lichess::fake::EmitGame $gid [::lichess::fake::GameState $gid]
 ::scidb::test::ls::Wait {[::online::view::ucis $::lichess::Priv(view)] eq "e2e4 e7e5"}
 set fen [::online::view::fen $::lichess::Priv(view)]
 dict for {sock conn} $::lichess::fake::Connections {
  if {[dict get $conn kind] eq "game"} {after cancel [dict get $conn timer]}
 }
 ::scidb::test::ls::Wait {[::scidb::test::ls::Hits /api/board/game/stream/$gid] == 2}
 ::scidb::test::ls::Pause 100
 set same [expr {$fen eq [::online::view::fen $::lichess::Priv(view)]}]
 puts "Game reconnect: server moves=[dict get [::lichess::fake::Game $gid] moves]; FEN=$fen; unchanged=$same"
 list $same [::online::view::ucis $::lichess::Priv(view)]
} -cleanup {::scidb::test::ls::Cleanup} -result {1 {e2e4 e7e5}}

# A separate loopback responder omits Retry-After entirely; the shared fake
# deliberately sends the header even for its empty-value control.
proc ::scidb::test::ls::MissingAccept {sock address port} {
 fconfigure $sock -blocking 0 -buffering none -translation binary
 fileevent $sock readable [list ::scidb::test::ls::MissingRead $sock]
}
proc ::scidb::test::ls::MissingRead {sock} {
 read $sock
 puts -nonewline $sock "HTTP/1.1 429 Limited\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
 close $sock
}
tcltest::test errors-429-missing {absent Retry-After uses sixty seconds} -setup {
 ::scidb::test::ls::Setup
} -body {
 set listener [socket -server ::scidb::test::ls::MissingAccept -myaddr 127.0.0.1 0]
 set ::lichess::api::Base http://127.0.0.1:[lindex [fconfigure $listener -sockname] 2]
 set now [clock milliseconds]
 set r [::scidb::test::ls::Call tvChannels]
 close $listener
 set delta [expr {$::lichess::api::BackoffUntil-$now}]
 puts "Retry-After absent: delay=$delta ms"
 list [dict get $r error] [expr {abs($delta-60000) < 2000}]
} -cleanup {catch {close $listener}; ::scidb::test::ls::Cleanup} -result {{Lichess rate limit reached. Please wait 60 seconds.} 1}

tcltest::test stall-deadline {a stream cannot stay in automatic recovery beyond the recovery budget} -setup {
 ::scidb::test::ls::Setup
} -body {
 ::lichess::tv::open
 set ::lichess::api::StallTimeout 120
 set ::lichess::api::ReconnectDelays {50 150 450}
 set ::lichess::api::RecoveryTimeout 500
 ::lichess::fake::Control /api/tv/blitz/feed stall
 set h [::lichess::api::tvFeed Blitz {apply {{r} {}}}]
 ::scidb::test::ls::Wait {[dict get $::lichess::api::Requests $h attempts] > 0}
 set at [lindex [::scidb::test::ls::Times /api/tv/blitz/feed] 0]
 ::scidb::test::ls::Wait {[dict get $::lichess::api::Requests $h lost]}
 set elapsed [expr {[clock milliseconds]-$at}]
 puts "Recovery deadline: lost after $elapsed ms (500 ms test budget)"
 expr {$elapsed <= 700 && [::scidb::test::ls::Hits /api/tv/blitz/feed] <= 4}
} -cleanup {set ::lichess::api::RecoveryTimeout 30000; ::scidb::test::ls::Cleanup} -result 1

tcltest::test stall-close-cancels-reconnect {window close cancels a pending reopen as well as its watchdog and status row} -setup {
 ::scidb::test::ls::Setup
} -body {
 ::lichess::tv::open
 set ::lichess::api::StallTimeout 100
 set ::lichess::api::ReconnectDelays {500 1500 4500}
 ::lichess::fake::Control /api/tv/best/feed stall
 set h [::lichess::tv::WatchSelectedChannel Best]
 ::scidb::test::ls::Wait {[dict get $::lichess::api::Requests $h attempts] == 1}
 uplevel #0 [wm protocol .online WM_DELETE_WINDOW]
 ::scidb::test::ls::Pause 700
 list [dict size $::lichess::api::Requests] [::scidb::test::ls::Hits /api/tv/best/feed] [winfo exists .online.$h]
} -cleanup {::scidb::test::ls::Cleanup} -result {0 1 0}

tcltest::test errors-tcl {no Tcl background errors from teardown or reconnect} -body {
 update
 set target [file join $::scidb::test::ls::Out SCIDB_ERROR_LOG.log]
 if {[file exists $::env(SCIDB_ERROR_LOG)]} {
  file copy -force $::env(SCIDB_ERROR_LOG) $target
 } else {
  close [open $target w]
 }
 file size $target
} -result 0

tcltest::cleanupTests
