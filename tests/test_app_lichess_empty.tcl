# Real API + Tk regressions for empty states. No live service is contacted.
package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
source [file join [file dirname [info script]] lichess_fake_server.tcl]
::scidb::test::wait::ready
namespace eval ::scidb::test::empty {
 variable Out [file normalize tests/tmp-app/lichess-hardening/D-empty]
 file mkdir $Out
 set ::env(SCIDB_ERROR_LOG) [file join $Out errors.log]
 close [open $::env(SCIDB_ERROR_LOG) w]
}
proc ::scidb::test::empty::Setup {} {
 variable Base $::lichess::api::Base
 foreach name {TokenStore TokenLoad TokenDelete} { rename ::lichess::api::$name ::scidb::test::empty::Saved$name }
 proc ::lichess::api::TokenStore {value} {set ::scidb::test::empty::Credential $value}
 proc ::lichess::api::TokenLoad {} {return $::scidb::test::empty::Credential}
 proc ::lichess::api::TokenDelete {} {set ::scidb::test::empty::Credential {}}
 set ::lichess::api::Base [::lichess::fake::Start]
 set ::scidb::test::empty::Credential [::lichess::testToken]
 set ::lichess::fake::Token $::scidb::test::empty::Credential
 set ::lichess::api::BackoffUntil 0
 set ::lichess::api::Mode board
}
proc ::scidb::test::empty::Wait {} {
 ::scidb::test::wait::until {[dict size $::lichess::api::Requests] == 0}
 update
}
proc ::scidb::test::empty::Shot {name} {
 variable Out
 update
 exec import -window [winfo id .online] [file join $Out $name.png]
}
proc ::scidb::test::empty::Cleanup {} {
 foreach id [dict keys $::lichess::api::Requests] {::lichess::api::close $id}
 foreach tab {lichess-social lichess-tv lichess-events lichess-puzzles lichess} {catch {::online::window::closeTab $tab}}
 ::lichess::fake::Stop
 update
 foreach name {TokenStore TokenLoad TokenDelete} {
  rename ::lichess::api::$name {}
  rename ::scidb::test::empty::Saved$name ::lichess::api::$name
 }
 set ::lichess::api::Base $::scidb::test::empty::Base
}
# Assert the actual visible label and tree, not just model state. Every view
# is seeded with rows before empty/error and restored to populated afterward.
foreach {name ns key path refresh empty} {
 teams social teams /api/team/of/alice {::lichess::social::Lookup alice} {This player has no teams.}
 channels tv channels /api/tv/channels ::lichess::tv::RefreshChannels {No TV channels available.}
 broadcasts tv broadcasts /api/broadcast/top ::lichess::tv::RefreshBroadcasts {No live broadcasts available.}
 arenas events arenas /api/tournament ::lichess::events::RefreshArenas {No arena tournaments available.}
 swiss events swiss /api/team/team1/swiss {::lichess::events::LoadTeamSwiss team1} {No Swiss tournaments for this team.}
 simuls events simuls /api/simul ::lichess::events::RefreshSimuls {No simultaneous exhibitions available.}
 activity puzzles activity /api/puzzle/activity ::lichess::puzzles::RefreshStats {No puzzle activity yet.}
} {
 tcltest::test empty-$name {visible list has distinct empty and HTTP error states and recovers} -setup {
  ::scidb::test::empty::Setup
 } -body {
  ::lichess::${ns}::open
  eval $refresh
  ::scidb::test::empty::Wait
  set tree [set ::lichess::${ns}::Priv(widget:$key)]
  set populated [expr {[llength [$tree children {}]] > 0}]
  ::lichess::fake::Control $path empty
  eval $refresh
  ::scidb::test::empty::Wait
  set label ${tree}Message
  set blank [expr {[$label cget -text] eq $empty && ![llength [$tree children {}]] && [winfo ismapped $label]}]
  ::scidb::test::empty::Shot $name-empty
  ::lichess::fake::Control $path 503
  eval $refresh
  ::scidb::test::empty::Wait
  set failed [expr {[$label cget -text] eq [format $::lichess::api::mc::Server 503] && ![llength [$tree children {}]]}]
  ::scidb::test::empty::Shot $name-503
  ::lichess::fake::ClearControl $path
  eval $refresh
  ::scidb::test::empty::Wait
  list $populated $blank $failed [expr {[$label cget -text] eq "" && [llength [$tree children {}]] > 0}]
 } -cleanup {::scidb::test::empty::Cleanup} -result {1 1 1 1}
}
foreach {name ns path refresh field empty} {
 history social /api/user/alice/rating-history {::lichess::social::Lookup alice} ratingHistory {No rating history available.}
 dashboard puzzles /api/puzzle/dashboard/30 ::lichess::puzzles::RefreshStats dashboardText {No puzzles played yet.}
 incoming social /api/challenge ::lichess::social::RefreshChallenges challenges:in {No incoming challenges.}
 outgoing social /api/challenge ::lichess::social::RefreshChallenges challenges:out {No outgoing challenges.}
 playing {} /api/account/playing ::lichess::RefreshPlaying playingText {No ongoing games.}
} {
 tcltest::test empty-$name {empty and error text appears on real rendered view} -setup {::scidb::test::empty::Setup} -body {
  if {$ns eq ""} {
   ::lichess::open .application
   ::lichess::ShowView lobby
   # This test does not need the account event stream.
   ::lichess::api::closeStreams
  } else { ::lichess::${ns}::open }
  if {$name eq "playing"} {::lichess::fake::CreateGame white ai 1 600 0}
  eval $refresh
  ::scidb::test::empty::Wait
  set checks {}
  foreach mode {empty 503} {
   ::lichess::fake::Control $path $mode
   eval $refresh
   ::scidb::test::empty::Wait
   if {$name eq "history"} {
    set c $::lichess::social::Priv(widget:canvas)
    set text [$c itemcget [lindex [$c find withtag [expr {$mode eq "empty" ? "empty" : "error"}]] 0] -text]
   } else {
    set scope [expr {$ns eq "" ? "::lichess" : "::lichess::$ns"}]
    switch $name {
     dashboard {set label $::lichess::puzzles::Priv(widget:top).left.stats.summary}
     incoming {set label $::lichess::social::Priv(widget:top).right.lists.in}
     outgoing {set label $::lichess::social::Priv(widget:top).right.lists.out}
     playing {set label $::lichess::Priv(widget:lobby).playing.list}
    }
    if {![winfo ismapped $label]} {error "message label is hidden"}
    set text [set [$label cget -textvariable]]
   }
   lappend checks [expr {$text eq ($mode eq "empty" ? $empty : [format $::lichess::api::mc::Server 503])}]
   ::scidb::test::empty::Shot $name-$mode
  }
  ::lichess::fake::ClearControl $path
  eval $refresh
  ::scidb::test::empty::Wait
  if {$name eq "history"} {lappend checks [expr {[llength [$c find withtag point]] > 0}]} else {
   lappend checks [expr {[set ${scope}::Priv($field)] ne $empty && ![string match *server* [set ${scope}::Priv($field)]]}]
  }
  set checks
 } -cleanup {::scidb::test::empty::Cleanup} -result {1 1 1}
}
tcltest::test empty-player-404 {unknown player removes previous profile, teams and history} -setup {::scidb::test::empty::Setup} -body {
 ::lichess::social::open
 ::lichess::social::Lookup alice
 ::scidb::test::empty::Wait
 set populated [expr {$::lichess::social::Priv(userData) ne "" && $::lichess::social::Priv(teams) ne ""}]
 ::lichess::fake::Control /api/user/missing 404
 ::lichess::social::Lookup missing
 ::scidb::test::empty::Wait
 ::scidb::test::empty::Shot player-404
 list $populated $::lichess::social::Priv(profileText) $::lichess::social::Priv(userData) $::lichess::social::Priv(teams) $::lichess::social::Priv(ratingHistory) [$::lichess::social::Priv(widget:teams) children {}]
} -cleanup {::scidb::test::empty::Cleanup} -result {1 {Player not found: missing.} {} {} {} {}}
tcltest::test empty-tabs-mc {tab buttons use mc English defaults in source and render unchanged} -setup {::scidb::test::empty::Setup} -body {
 ::lichess::open .application
 ::lichess::api::closeStreams
 ::lichess::ShowView lobby
 set bar $::lichess::Priv(widget:lobby).tabsBar
 set labels {}
 foreach w {social tv events puzzles} {lappend labels [$bar.$w cget -text]}
 ::scidb::test::empty::Shot tabs-english
 set f [open tcl/lichess.tcl]; set source [read $f]; close $f
 set wrapped 1
 foreach w {social tv events puzzles} key {Players TV Events Puzzles} {
  if {[string first [format {$tabsBar.%s -text $mc::%sTab} $w $key] $source] < 0} {set wrapped 0}
 }
 list $wrapped $labels
} -cleanup {::scidb::test::empty::Cleanup} -result {1 {{Lichess players} {Lichess TV} {Lichess tournaments} {Lichess puzzles}}}

tcltest::test empty-error-log {no Tcl background errors} -body {file size $::env(SCIDB_ERROR_LOG)} -result 0
tcltest::cleanupTests
