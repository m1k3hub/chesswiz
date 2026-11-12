# Terminal-review regressions through the real Tk client and loopback HTTP.
package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
source [file join [file dirname [info script]] lichess_fake_server.tcl]
::scidb::test::wait::ready
namespace eval ::scidb::test::gaps {
 variable Out [file normalize tests/tmp-app/lichess-hardening/T-gaps]
 file mkdir $Out
}
proc ::scidb::test::gaps::Wait {condition} {uplevel 1 [list ::scidb::test::wait::until $condition 10000]}
proc ::scidb::test::gaps::Setup {} {
 variable Saved
 foreach key {Base BackoffUntil StallTimeout ReconnectDelays RecoveryTimeout} {dict set Saved $key [set ::lichess::api::$key]}
 ::lichess::api::signOut
 set ::lichess::api::Base [::lichess::fake::Start]
 set ::lichess::api::BackoffUntil 0
 set ::lichess::fake::Token [::lichess::testToken]
 ::lichess::api::TokenStore [::lichess::testToken]
 set ::lichess::api::Mode board
}
proc ::scidb::test::gaps::Cleanup {} {
 ::lichess::Close
 ::lichess::api::signOut
 ::lichess::fake::Stop
 foreach tab {lichess-social lichess-puzzles lichess-events lichess-tv} {catch {::online::window::closeTab $tab}}
 dict for {key value} $::scidb::test::gaps::Saved {set ::lichess::api::$key $value}
 update
}
proc ::scidb::test::gaps::Shot {name} {
 update
 exec import -window [winfo id .online] [file join $::scidb::test::gaps::Out $name.png]
}
proc ::scidb::test::gaps::Text {w} {
 set v [$w cget -textvariable]
 if {$v ne {}} {return [set $v]}
 return [$w cget -text]
}
proc ::scidb::test::gaps::CheckLabel {w text} {
 update
 if {![winfo ismapped $w] || [Text $w] ne $text} {error "Missing visible prompt at $w"}
 return 1
}

namespace eval ::scidb::test::gaps {
tcltest::test gaps-initial-players {first-open profile, chart, teams and challenges explain how to load them} -setup {
 ::scidb::test::gaps::Setup
} -body {
 ::lichess::social::open
 set top $::lichess::social::Priv(widget:top)
 set checks {}
 foreach w [list $top.left.lookup.profile $top.left.teams.treeMessage] {
  lappend checks [::scidb::test::gaps::CheckLabel $w $::lichess::social::mc::LookupPrompt]
 }
 set c $::lichess::social::Priv(widget:canvas)
 lappend checks [expr {[$c itemcget [lindex [$c find withtag initial] 0] -text] eq $::lichess::social::mc::LookupPrompt}]
 foreach kind {in out} {lappend checks [::scidb::test::gaps::CheckLabel $top.right.lists.$kind $::lichess::social::mc::ChallengesPrompt]}
 ::scidb::test::gaps::Shot initial-players
 set checks
} -cleanup {::scidb::test::gaps::Cleanup} -result {1 1 1 1 1}

tcltest::test gaps-initial-puzzles {first-open puzzle info, dashboard and activity contain prompts} -setup {
 ::scidb::test::gaps::Setup
} -body {
 ::lichess::puzzles::open
 set left $::lichess::puzzles::Priv(widget:top).left
 set checks [list [::scidb::test::gaps::CheckLabel $left.solve.info $::lichess::puzzles::mc::PuzzlePrompt]]
 foreach w [list $left.stats.summary $left.stats.treeMessage] {lappend checks [::scidb::test::gaps::CheckLabel $w $::lichess::puzzles::mc::StatsPrompt]}
 ::scidb::test::gaps::Shot initial-puzzles
 set checks
} -cleanup {::scidb::test::gaps::Cleanup} -result {1 1 1}

foreach {ns key prompt} {events swiss SwissPrompt tv roundGames RoundPrompt} {
 tcltest::test gaps-initial-$ns {unloaded list explains which action loads it} -setup {
  ::scidb::test::gaps::Setup
 } -body {
  ::lichess::${ns}::open
  set tree [set ::lichess::${ns}::Priv(widget:$key)]
  set result [::scidb::test::gaps::CheckLabel ${tree}Message [set ::lichess::${ns}::mc::$prompt]]
  ::scidb::test::gaps::Shot initial-$ns
  set result
 } -cleanup {::scidb::test::gaps::Cleanup} -result 1
}

foreach {name offset expected} {future 3 3 past -10 60 uncapped 7200 7200 garbage garbage 60} {
 tcltest::test gaps-date-$name {HTTP-date backoff queues a real request until the absolute deadline} -setup {
  ::scidb::test::gaps::Setup
 } -body {
  # Align to the start of a second so the future date is three seconds away.
  set wait [expr {1000 - [clock milliseconds] % 1000}]
  after $wait {set ::scidb::test::gaps::aligned 1}
  vwait ::scidb::test::gaps::aligned
  set now [clock milliseconds]
  set date [expr {$offset eq "garbage" ? "garbage" : [clock format [expr {[clock seconds]+$offset}] -gmt 1 -locale en -format {%a, %d %b %Y %H:%M:%S GMT}]}]
  ::lichess::fake::ForceNext /api/tv/channels 429 $date
  unset -nocomplain ::scidb::test::gaps::reply
  ::lichess::api::tvChannels {set ::scidb::test::gaps::reply}
  ::scidb::test::gaps::Wait {[info exists ::scidb::test::gaps::reply]}
  set delta [expr {$::lichess::api::BackoffUntil-$now}]
  if {abs($delta-$expected*1000) > 150} {error "Bad backoff: $delta ms"}
  if {$name eq "future"} {
   unset -nocomplain ::scidb::test::gaps::queued
   ::lichess::api::user alice {set ::scidb::test::gaps::queued}
   ::scidb::test::gaps::Wait {[info exists ::scidb::test::gaps::queued]}
   set elapsed [expr {[clock milliseconds]-$now}]
   if {$elapsed < 3000 || $elapsed >= 5000} {error "Queued delivery at $elapsed ms"}
   puts "HTTP-date +3s queued resend: $elapsed ms"
  }
  puts "HTTP-date $name: backoff=$delta ms"
  dict get $::scidb::test::gaps::reply status
 } -cleanup {::scidb::test::gaps::Cleanup} -result 429
}

proc ::scidb::test::gaps::Notice {command op} {lappend ::scidb::test::gaps::Notices [lrange $command 1 end]}
foreach mode {503 stall} {
 tcltest::test gaps-stream-$mode {reconnect and final notices retain server classification; Retry stays visible with retained game} -setup {
  ::scidb::test::gaps::Setup
  set ::scidb::test::gaps::Notices {}
  trace add execution ::lichess::StreamStatus enter ::scidb::test::gaps::Notice
 } -body {
  # Retain a real finished game, whose board raises the notebook's request size.
  set gid [::lichess::fake::CreateGame white ai 1 600 0]
  ::lichess::OpenGame [dict create id $gid color white]
  ::scidb::test::gaps::Wait {$::lichess::Priv(active)}
  ::lichess::api::resign $gid {set ::scidb::test::gaps::resigned}
  ::scidb::test::gaps::Wait {$::lichess::Priv(state) eq "over"}
  ::lichess::api::close $::lichess::Priv(gameHandle)
  set ::lichess::Priv(gameHandle) {}
  ::lichess::tv::open
  set ::lichess::api::StallTimeout 120
  set ::lichess::api::ReconnectDelays {40 60 80}
  ::lichess::fake::Control /api/tv/best/feed $mode
  set h [::lichess::tv::WatchSelectedChannel Best]
  ::scidb::test::gaps::Wait {[dict get $::lichess::api::Requests $h lost]}
  update
  set final [.online.$h.message cget -text]
  set expected [expr {$mode eq "503" ? "Lichess server error (503) — connection lost." : "Lichess connection lost."}]
  if {$final ne $expected} {error "Wrong final status: $final"}
  if {$mode eq "503" && [lsearch -exact $::scidb::test::gaps::Notices [list $h {Lichess server error (503) — reconnecting…} 0]] < 0} {error "No classified reconnect notice"}
  set f [open [file join $::scidb::test::gaps::Out notices-$mode.txt] w]
  puts $f $::scidb::test::gaps::Notices
  close $f
  wm geometry .online 1200x900+0+0
  update
  set b .online.$h.retry
  if {![winfo ismapped $b] || [winfo rooty $b]+[winfo height $b] > 900} {error "Retry squeezed out"}
  puts "Retry mapped=[winfo ismapped $b], screen=[winfo screenwidth .online]x[winfo screenheight .online], geometry=[wm geometry .online]"
  ::scidb::test::gaps::Shot retry-$mode-[winfo screenwidth .online]
  ::lichess::fake::ClearControl /api/tv/best/feed
  # Generate an actual pointer click at the rendered Retry button.
  event generate $b <Enter>
  event generate $b <ButtonPress-1> -x 8 -y 8
  event generate $b <ButtonRelease-1> -x 8 -y 8
  ::scidb::test::gaps::Wait {$::lichess::tv::Priv(gameId) eq "tv1" && ![winfo exists .online.$h]}
  list $final [dict exists $::lichess::api::Requests $h]
 } -cleanup {
  trace remove execution ::lichess::StreamStatus enter ::scidb::test::gaps::Notice
  ::scidb::test::gaps::Cleanup
 } -result [list [expr {$mode eq "503" ? "Lichess server error (503) — connection lost." : "Lichess connection lost."}] 1]
}
}
tcltest::cleanupTests
