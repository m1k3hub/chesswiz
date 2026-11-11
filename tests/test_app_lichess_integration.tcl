# ======================================================================
# Scidb App Test — the phase-2 Lichess tabs driven through the real
# ::lichess::api against the loopback fake server (test_app_lichess_phase2
# stubs the API instead). No test in this file contacts lichess.org.
# ======================================================================

package require tcltest 2.5
package require json
source [file join [file dirname [info script]] app_wait.tcl]
source [file join [file dirname [info script]] lichess_fake_server.tcl]
::scidb::test::wait::ready

namespace eval ::scidb::test::lint {
	variable Credential {}
	variable Opened {}
}

proc ::scidb::test::lint::Setup {} {
	variable Credential
	variable Opened
	variable SavedBase $::lichess::api::Base
	set Credential lio_integration
	set Opened {}
	foreach name {TokenStore TokenLoad TokenDelete OpenBrowser} {
		rename ::lichess::api::$name ::scidb::test::lint::Original$name
	}
	proc ::lichess::api::TokenStore {tok} { set ::scidb::test::lint::Credential $tok }
	proc ::lichess::api::TokenLoad {} { return $::scidb::test::lint::Credential }
	proc ::lichess::api::TokenDelete {} { set ::scidb::test::lint::Credential {} }
	proc ::lichess::api::OpenBrowser {url} { lappend ::scidb::test::lint::Opened $url }
	set ::lichess::api::Base [::lichess::fake::Start]
	set ::lichess::api::BackoffUntil 0
	# the fake accepts only the token it issued
	set ::lichess::fake::Token $Credential
	::lichess::fake::ClearRequests
}

proc ::scidb::test::lint::Cleanup {} {
	variable SavedBase
	foreach ns {social tv events puzzles} {
		catch { ::online::window::closeTab lichess-$ns }
		catch { ::lichess::tv::StopStream }
	}
	::lichess::fake::Stop
	update
	foreach name {TokenStore TokenLoad TokenDelete OpenBrowser} {
		rename ::lichess::api::$name {}
		rename ::scidb::test::lint::Original$name ::lichess::api::$name
	}
	set ::lichess::api::Base $SavedBase
}

# The paths the fake server saw, in order.
proc ::scidb::test::lint::Paths {} {
	lmap r [::lichess::fake::Requests] { dict get $r path }
}

proc ::scidb::test::lint::Saw {path} {
	expr {$path in [Paths]}
}

tcltest::test lichess-int-social {player lookup fills profile, history and teams; a challenge is sent} -setup {
	::scidb::test::lint::Setup
} -body {
	::lichess::social::open .application
	::lichess::social::Lookup alice
	::scidb::test::wait::until {[llength $::lichess::social::Priv(teams)] > 0
		&& [llength $::lichess::social::Priv(ratingHistory)] > 0}
	set profile [string match *Alice* $::lichess::social::Priv(profileText)]
	set ::lichess::social::Priv(chMinutes) 10
	set ::lichess::social::Priv(chIncrement) 5
	::lichess::social::Challenge alice
	::scidb::test::wait::until {[::scidb::test::lint::Saw /api/challenge/alice]}
	::scidb::test::wait::until {$::lichess::social::Priv(outgoingId) eq "challenge1"}
	::lichess::social::SendMessage alice "Hello"
	::scidb::test::wait::until {[::scidb::test::lint::Saw /api/inbox/alice]}
	list $profile [::scidb::test::lint::Saw /api/user/alice/rating-history] [::scidb::test::lint::Saw /api/team/of/alice]
} -cleanup { ::scidb::test::lint::Cleanup } -result {1 1 1}

tcltest::test lichess-int-tv {TV channels load and watching a channel puts the featured game on a board} -setup {
	::scidb::test::lint::Setup
} -body {
	::lichess::tv::open .application
	::lichess::tv::RefreshChannels
	::scidb::test::wait::until {[llength $::lichess::tv::Priv(channels)] > 0}
	::lichess::tv::WatchSelectedChannel Best
	::scidb::test::wait::until {$::lichess::tv::Priv(gameId) eq "tv1"}
	::lichess::tv::RefreshBroadcasts
	::scidb::test::wait::until {[llength $::lichess::tv::Priv(broadcasts)] > 0}
	list [string match /api/tv/* [lsearch -inline -glob [::scidb::test::lint::Paths] */feed]] \
		[expr {$::lichess::tv::Priv(streamHandle) ne ""}]
} -cleanup { ::scidb::test::lint::Cleanup } -result {1 1}

tcltest::test lichess-int-broadcast {following a live round lists its games from the PGN stream} -setup {
	::scidb::test::lint::Setup
} -body {
	::lichess::tv::open .application
	::lichess::tv::FollowBroadcastRound round1
	::scidb::test::wait::until {[::scidb::test::lint::Saw /api/stream/broadcast/round/round1.pgn]}
	::lichess::fake::EmitBroadcastPgn round1 "\[Event \"Live\"\]\n\[White \"Ann\"\]\n\[Black \"Bob\"\]\n\n1. d4 d5 *\n"
	::scidb::test::wait::until {[llength $::lichess::tv::Priv(roundGames)] > 0}
	llength $::lichess::tv::Priv(roundGames)
} -cleanup { ::scidb::test::lint::Cleanup } -result 1

tcltest::test lichess-int-events {arenas, team swiss and simuls load; join and withdraw reach the server} -setup {
	::scidb::test::lint::Setup
} -body {
	::lichess::events::open .application
	::lichess::events::RefreshArenas
	::scidb::test::wait::until {[llength $::lichess::events::Priv(arenas)] > 0}
	::lichess::events::JoinArena arena1
	::scidb::test::wait::until {[::scidb::test::lint::Saw /api/tournament/arena1/join]}
	::lichess::events::WithdrawArena arena1
	::scidb::test::wait::until {[::scidb::test::lint::Saw /api/tournament/arena1/withdraw]}
	::lichess::events::LoadTeamSwiss team1
	::scidb::test::wait::until {[llength $::lichess::events::Priv(swissList)] == 2}
	::lichess::events::JoinSwiss swiss1
	::scidb::test::wait::until {[::scidb::test::lint::Saw /api/swiss/swiss1/join]}
	::lichess::events::RefreshSimuls
	::scidb::test::wait::until {[llength $::lichess::events::Priv(simuls)] > 0}
	::lichess::events::OpenSimulInBrowser simul1
	string match */simul/simul1 [lindex $::scidb::test::lint::Opened end]
} -cleanup { ::scidb::test::lint::Cleanup } -result 1

tcltest::test lichess-int-puzzle {the daily puzzle loads onto a board and solving it reports the result} -setup {
	::scidb::test::lint::Setup
} -body {
	::lichess::puzzles::open .application
	::lichess::puzzles::FetchDaily
	::scidb::test::wait::until {$::lichess::puzzles::Priv(puzzleId) eq "puzzle1"}
	set solution $::lichess::puzzles::Priv(solution)
	list [llength $solution] [expr {$::lichess::puzzles::Priv(startFen) ne ""}]
} -cleanup { ::scidb::test::lint::Cleanup } -result {2 1}

tcltest::test lichess-int-stream-switch {switching streams keeps the new one: the old stream's late close is ignored} -setup {
	::scidb::test::lint::Setup
} -body {
	::lichess::tv::open .application
	::lichess::tv::WatchSelectedChannel Best
	::scidb::test::wait::until {$::lichess::tv::Priv(gameId) eq "tv1"}
	::lichess::tv::FollowBroadcastRound round1
	::scidb::test::wait::until {[::scidb::test::lint::Saw /api/stream/broadcast/round/round1.pgn]}
	# let the first stream's close be delivered
	after 300 {set ::scidb::test::lint::paused 1}; vwait ::scidb::test::lint::paused
	set kept [expr {$::lichess::tv::Priv(streamHandle) ne "" && $::lichess::tv::Priv(streamKind) eq "broadcastRound"}]
	::lichess::fake::EmitBroadcastPgn round1 "\[Event \"Live\"\]\n\[White \"Ann\"\]\n\[Black \"Bob\"\]\n\n1. d4 d5 *\n"
	::lichess::fake::EmitBroadcastPgn round1 "\[Event \"Live\"\]\n\[White \"Cy\"\]\n\[Black \"Di\"\]\n\n1. e4 *\n"
	::scidb::test::wait::until {[llength $::lichess::tv::Priv(roundGames)] == 2}
	# the board stays on the first game while another game moves
	set follow $::lichess::tv::Priv(followKey)
	::lichess::tv::StopStream
	list $kept $follow $::lichess::tv::Priv(streamHandle) [::scidb::test::lint::Saw /api/tv/best/feed]
} -cleanup { ::scidb::test::lint::Cleanup } -result {1 Ann|Bob {} 1}

tcltest::test lichess-int-tab-close {closing the TV tab ends its stream} -setup {
	::scidb::test::lint::Setup
} -body {
	::lichess::tv::open .application
	::lichess::tv::WatchSelectedChannel Best
	::scidb::test::wait::until {$::lichess::tv::Priv(gameId) eq "tv1"}
	::online::window::closeTab lichess-tv
	update
	set ::lichess::tv::Priv(streamHandle)
} -cleanup { ::scidb::test::lint::Cleanup } -result {}

tcltest::test lichess-int-puzzle-mate {any mating move solves a puzzle, not only the listed one} -setup {
	::scidb::test::lint::Setup
} -body {
	::lichess::puzzles::open .application
	array set ::lichess::puzzles::Priv {
		puzzleId mateTwoWays state solving failedOnce 0 reported 1 stormActive 0
		currentFen {6k1/5ppp/8/8/8/8/8/R3R1K1 w - - 0 1}
	}
	set ::lichess::puzzles::Priv(remaining) {a1a8}
	set solved [::lichess::puzzles::CheckUserMove e1e8 0]
	set ::lichess::puzzles::Priv(state) solving
	set ::lichess::puzzles::Priv(remaining) {a1a8}
	set ::lichess::puzzles::Priv(currentFen) {6k1/5ppp/8/8/8/8/8/R3R1K1 w - - 0 1}
	list $solved [::lichess::puzzles::CheckUserMove a1a7 0] $::lichess::puzzles::Priv(state)
} -cleanup { ::scidb::test::lint::Cleanup } -result {1 0 wrong}

tcltest::cleanupTests
