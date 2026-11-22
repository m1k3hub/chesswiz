# ======================================================================
# Scidb App Test — Lichess phase 2 UI tabs and extras
# (tcl/lichess-social.tcl, tcl/lichess-tv.tcl, tcl/lichess-events.tcl,
#  tcl/lichess-puzzles.tcl, tcl/lichess.tcl, tcl/app-lichess-study.tcl)
#
# All tests below use local stubs for ::lichess::api commands. The real
# lichess.org is never contacted and no browser is launched.
# ======================================================================

package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

namespace eval ::scidb::test::lichess2 {
	variable calls {}
	variable signedIn 1
	variable tokenValue {}
	variable nextHandle 0
	variable savedProcs {}
	variable browserUrls {}

	variable accountCmd {}
	variable eventCmd {}
	variable seekCmd {}
	variable gameCmd {}
	variable chatHistoryCmd {}
	variable actionCmds {}
	variable modeValue board
	variable botUpgradeCmd {}
	variable cloudEvalCmd {}
	variable importGameCmd {}
	variable gameExportCmd {}

	variable userCmd {}
	variable ratingHistoryCmd {}
	variable teamsOfCmd {}
	variable joinTeamCmd {}
	variable leaveTeamCmd {}
	variable sendMessageCmd {}
	variable challengeUserCmd {}
	variable acceptChallengeCmd {}
	variable declineChallengeCmd {}
	variable cancelChallengeCmd {}

	variable tvChannelsCmd {}
	variable tvFeedCmd {}
	variable streamGameMovesCmd {}
	variable broadcastsTopCmd {}
	variable broadcastRoundStreamCmd {}

	variable arenasCmd {}
	variable arenaCmd {}
	variable joinArenaCmd {}
	variable withdrawArenaCmd {}
	variable swissOfTeamCmd {}
	variable joinSwissCmd {}
	variable withdrawSwissCmd {}
	variable simulsCmd {}

	variable puzzleDailyCmd {}
	variable puzzleNextCmd {}
	variable puzzleCmd {}
	variable puzzleDashboardCmd {}
	variable puzzleActivityCmd {}
	variable puzzleRaceCmd {}
	variable puzzleBatchSolvedCmd {}

	variable studiesOfCmd {}
	variable studyCreateCmd {}
	variable studyImportPgnCmd {}
}

proc ::scidb::test::lichess2::AllApiNames {} {
	return {
		token signedIn? signIn useToken signOut account Request
		streamEvents streamGame close seek challengeAi
		move resign abort draw claimVictory takeback chat chatHistory
		mode botUpgrade botStreamGame botMove botResign botAbort botDraw botTakeback botChat
		user ratingHistory teamsOf joinTeam leaveTeam sendMessage
		challengeUser acceptChallenge declineChallenge cancelChallenge
		tvChannels tvFeed streamGameMoves
		broadcastsTop broadcastRoundStream
		arenas arena joinArena withdrawArena
		swissOfTeam joinSwiss withdrawSwiss
		simuls
		puzzleDaily puzzleNext puzzle puzzleDashboard puzzleActivity puzzleRace puzzleBatchSolved
		cloudEval importGame gameExport
		studiesOf studyCreate studyImportPgn
		OpenBrowser
	}
}

proc ::scidb::test::lichess2::Stub {} {
	variable calls {}
	variable signedIn 1
	variable tokenValue {}
	variable nextHandle 0
	variable savedProcs {}
	variable browserUrls {}
	variable modeValue board
	variable actionCmds {}

	namespace eval ::lichess::api {
		variable Base "https://lichess.org"
	}
	foreach name [AllApiNames] {
		set fq "::lichess::api::$name"
		set backup "::scidb::test::lichess2::orig_$name"
		catch { rename $backup {} }
		if {[llength [info commands $fq]]} {
			rename $fq $backup
			lappend savedProcs $name
		}
	}

	proc ::lichess::api::OpenBrowser {url} {
		lappend ::scidb::test::lichess2::calls [list OpenBrowser $url]
		lappend ::scidb::test::lichess2::browserUrls $url
	}
	proc ::lichess::api::token {} {
		return $::scidb::test::lichess2::tokenValue
	}
	proc ::lichess::api::signedIn? {} {
		return $::scidb::test::lichess2::signedIn
	}
	proc ::lichess::api::signOut {} {
		lappend ::scidb::test::lichess2::calls [list signOut]
		set ::scidb::test::lichess2::signedIn 0
	}
	# Automatic lobby refresh must stay inside this suite's offline API fixture.
	proc ::lichess::api::Request {method path form cmd args} {
		if {$method ne "GET" || $path ne "/api/account/playing"} {error "unexpected stub request: $method $path"}
		uplevel #0 [list {*}$cmd {ok 1 data {nowPlaying {}}}]
		return playing-stub
	}
	proc ::lichess::api::account {cmd} {
		lappend ::scidb::test::lichess2::calls [list account]
		set ::scidb::test::lichess2::accountCmd $cmd
	}
	proc ::lichess::api::streamEvents {cmd} {
		set h "ev-[incr ::scidb::test::lichess2::nextHandle]"
		lappend ::scidb::test::lichess2::calls [list streamEvents $h]
		set ::scidb::test::lichess2::eventCmd $cmd
		return $h
	}
	proc ::lichess::api::streamGame {gameId cmd} {
		set h "gm-[incr ::scidb::test::lichess2::nextHandle]"
		lappend ::scidb::test::lichess2::calls [list streamGame $gameId $h]
		set ::scidb::test::lichess2::gameCmd $cmd
		return $h
	}
	proc ::lichess::api::close {handle} {
		lappend ::scidb::test::lichess2::calls [list close $handle]
	}
	proc ::lichess::api::seek {minutes increment rated color cmd {variant standard} {days ""}} {
		set h "sk-[incr ::scidb::test::lichess2::nextHandle]"
		lappend ::scidb::test::lichess2::calls [list seek $minutes $increment $rated $color $variant $days $h]
		set ::scidb::test::lichess2::seekCmd $cmd
		return $h
	}
	proc ::lichess::api::takeback {gameId yesno cmd} {
		lappend ::scidb::test::lichess2::calls [list takeback $gameId $yesno]
		lappend ::scidb::test::lichess2::actionCmds $cmd
	}
	proc ::lichess::api::chat {gameId text cmd} {
		lappend ::scidb::test::lichess2::calls [list chat $gameId $text]
		lappend ::scidb::test::lichess2::actionCmds $cmd
	}
	proc ::lichess::api::chatHistory {gameId cmd} {
		lappend ::scidb::test::lichess2::calls [list chatHistory $gameId]
		set ::scidb::test::lichess2::chatHistoryCmd $cmd
	}
	proc ::lichess::api::mode {{m ""}} {
		if {$m ne ""} {
			set ::scidb::test::lichess2::modeValue $m
			lappend ::scidb::test::lichess2::calls [list mode $m]
		}
		return $::scidb::test::lichess2::modeValue
	}
	proc ::lichess::api::botUpgrade {cmd} {
		lappend ::scidb::test::lichess2::calls [list botUpgrade]
		set ::scidb::test::lichess2::botUpgradeCmd $cmd
	}
	proc ::lichess::api::cloudEval {fen multiPv cmd} {
		lappend ::scidb::test::lichess2::calls [list cloudEval $fen $multiPv]
		set ::scidb::test::lichess2::cloudEvalCmd $cmd
	}
	proc ::lichess::api::importGame {pgn cmd} {
		lappend ::scidb::test::lichess2::calls [list importGame $pgn]
		set ::scidb::test::lichess2::importGameCmd $cmd
	}
	proc ::lichess::api::gameExport {id cmd} {
		lappend ::scidb::test::lichess2::calls [list gameExport $id]
		set ::scidb::test::lichess2::gameExportCmd $cmd
	}

	# Social & Challenges
	proc ::lichess::api::user {name cmd} {
		lappend ::scidb::test::lichess2::calls [list user $name]
		set ::scidb::test::lichess2::userCmd $cmd
	}
	proc ::lichess::api::ratingHistory {name cmd} {
		lappend ::scidb::test::lichess2::calls [list ratingHistory $name]
		set ::scidb::test::lichess2::ratingHistoryCmd $cmd
	}
	proc ::lichess::api::teamsOf {name cmd} {
		lappend ::scidb::test::lichess2::calls [list teamsOf $name]
		set ::scidb::test::lichess2::teamsOfCmd $cmd
	}
	proc ::lichess::api::joinTeam {teamId message cmd} {
		lappend ::scidb::test::lichess2::calls [list joinTeam $teamId $message]
		set ::scidb::test::lichess2::joinTeamCmd $cmd
	}
	proc ::lichess::api::leaveTeam {teamId cmd} {
		lappend ::scidb::test::lichess2::calls [list leaveTeam $teamId]
		set ::scidb::test::lichess2::leaveTeamCmd $cmd
	}
	proc ::lichess::api::sendMessage {user text cmd} {
		lappend ::scidb::test::lichess2::calls [list sendMessage $user $text]
		set ::scidb::test::lichess2::sendMessageCmd $cmd
	}
	proc ::lichess::api::challengeUser {user minutes increment rated color variant days cmd} {
		lappend ::scidb::test::lichess2::calls [list challengeUser $user $minutes $increment $rated $color $variant $days]
		set ::scidb::test::lichess2::challengeUserCmd $cmd
	}
	proc ::lichess::api::acceptChallenge {id cmd} {
		lappend ::scidb::test::lichess2::calls [list acceptChallenge $id]
		set ::scidb::test::lichess2::acceptChallengeCmd $cmd
	}
	proc ::lichess::api::declineChallenge {id reason cmd} {
		lappend ::scidb::test::lichess2::calls [list declineChallenge $id $reason]
		set ::scidb::test::lichess2::declineChallengeCmd $cmd
	}
	proc ::lichess::api::cancelChallenge {id cmd} {
		lappend ::scidb::test::lichess2::calls [list cancelChallenge $id]
		set ::scidb::test::lichess2::cancelChallengeCmd $cmd
	}

	# TV & Broadcasts
	proc ::lichess::api::tvChannels {cmd} {
		lappend ::scidb::test::lichess2::calls [list tvChannels]
		set ::scidb::test::lichess2::tvChannelsCmd $cmd
	}
	proc ::lichess::api::tvFeed {channel cmd} {
		set h "tv-[incr ::scidb::test::lichess2::nextHandle]"
		lappend ::scidb::test::lichess2::calls [list tvFeed $channel $h]
		set ::scidb::test::lichess2::tvFeedCmd $cmd
		return $h
	}
	proc ::lichess::api::streamGameMoves {gameId cmd} {
		set h "mv-[incr ::scidb::test::lichess2::nextHandle]"
		lappend ::scidb::test::lichess2::calls [list streamGameMoves $gameId $h]
		set ::scidb::test::lichess2::streamGameMovesCmd $cmd
		return $h
	}
	proc ::lichess::api::broadcastsTop {cmd} {
		lappend ::scidb::test::lichess2::calls [list broadcastsTop]
		set ::scidb::test::lichess2::broadcastsTopCmd $cmd
	}
	proc ::lichess::api::broadcastRoundStream {roundId cmd} {
		set h "br-[incr ::scidb::test::lichess2::nextHandle]"
		lappend ::scidb::test::lichess2::calls [list broadcastRoundStream $roundId $h]
		set ::scidb::test::lichess2::broadcastRoundStreamCmd $cmd
		return $h
	}

	# Tournaments & Simuls
	proc ::lichess::api::arenas {cmd} {
		lappend ::scidb::test::lichess2::calls [list arenas]
		set ::scidb::test::lichess2::arenasCmd $cmd
	}
	proc ::lichess::api::arena {id cmd} {
		lappend ::scidb::test::lichess2::calls [list arena $id]
		set ::scidb::test::lichess2::arenaCmd $cmd
	}
	proc ::lichess::api::joinArena {id cmd} {
		lappend ::scidb::test::lichess2::calls [list joinArena $id]
		set ::scidb::test::lichess2::joinArenaCmd $cmd
	}
	proc ::lichess::api::withdrawArena {id cmd} {
		lappend ::scidb::test::lichess2::calls [list withdrawArena $id]
		set ::scidb::test::lichess2::withdrawArenaCmd $cmd
	}
	proc ::lichess::api::swissOfTeam {teamId cmd} {
		lappend ::scidb::test::lichess2::calls [list swissOfTeam $teamId]
		set ::scidb::test::lichess2::swissOfTeamCmd $cmd
	}
	proc ::lichess::api::joinSwiss {id cmd} {
		lappend ::scidb::test::lichess2::calls [list joinSwiss $id]
		set ::scidb::test::lichess2::joinSwissCmd $cmd
	}
	proc ::lichess::api::withdrawSwiss {id cmd} {
		lappend ::scidb::test::lichess2::calls [list withdrawSwiss $id]
		set ::scidb::test::lichess2::withdrawSwissCmd $cmd
	}
	proc ::lichess::api::simuls {cmd} {
		lappend ::scidb::test::lichess2::calls [list simuls]
		set ::scidb::test::lichess2::simulsCmd $cmd
	}

	# Puzzles
	proc ::lichess::api::puzzleDaily {cmd} {
		lappend ::scidb::test::lichess2::calls [list puzzleDaily]
		set ::scidb::test::lichess2::puzzleDailyCmd $cmd
	}
	proc ::lichess::api::puzzleNext {angle difficulty cmd} {
		lappend ::scidb::test::lichess2::calls [list puzzleNext $angle $difficulty]
		set ::scidb::test::lichess2::puzzleNextCmd $cmd
	}
	proc ::lichess::api::puzzle {id cmd} {
		lappend ::scidb::test::lichess2::calls [list puzzle $id]
		set ::scidb::test::lichess2::puzzleCmd $cmd
	}
	proc ::lichess::api::puzzleDashboard {days cmd} {
		lappend ::scidb::test::lichess2::calls [list puzzleDashboard $days]
		set ::scidb::test::lichess2::puzzleDashboardCmd $cmd
	}
	proc ::lichess::api::puzzleActivity {max cmd} {
		lappend ::scidb::test::lichess2::calls [list puzzleActivity $max]
		set ::scidb::test::lichess2::puzzleActivityCmd $cmd
	}
	proc ::lichess::api::puzzleRace {cmd} {
		lappend ::scidb::test::lichess2::calls [list puzzleRace]
		set ::scidb::test::lichess2::puzzleRaceCmd $cmd
	}
	proc ::lichess::api::puzzleBatchSolved {angle solutions cmd} {
		lappend ::scidb::test::lichess2::calls [list puzzleBatchSolved $angle $solutions]
		set ::scidb::test::lichess2::puzzleBatchSolvedCmd $cmd
	}

	# Studies
	proc ::lichess::api::studiesOf {user cmd} {
		lappend ::scidb::test::lichess2::calls [list studiesOf $user]
		set ::scidb::test::lichess2::studiesOfCmd $cmd
	}
	proc ::lichess::api::studyCreate {name visibility cmd} {
		lappend ::scidb::test::lichess2::calls [list studyCreate $name $visibility]
		set ::scidb::test::lichess2::studyCreateCmd $cmd
	}
	proc ::lichess::api::studyImportPgn {studyId name pgn orientation variant cmd {bearer {}}} {
		lappend ::scidb::test::lichess2::calls [list studyImportPgn $studyId $name $pgn $orientation $variant]
		set ::scidb::test::lichess2::studyImportPgnCmd $cmd
	}
}

proc ::scidb::test::lichess2::Unstub {} {
	variable savedProcs
	catch { ::lichess::puzzles::StopStorm }
	catch { ::lichess::tv::StopStream }
	catch { ::application::lichess::study::Close }
	catch { ::lichess::Close }
	foreach t {lichess-social lichess-tv lichess-events lichess-puzzles} {
		catch { ::online::window::closeTab $t }
	}
	foreach name [AllApiNames] {
		set fq "::lichess::api::$name"
		set backup "::scidb::test::lichess2::orig_$name"
		catch { rename $fq {} }
		if {$name in $savedProcs && [llength [info commands $backup]]} {
			rename $backup $fq
		}
	}
	set savedProcs {}
}

# ----------------------------------------------------------------------
# 1. Social tab (::lichess::social): lookup, rating chart, teams,
#    challenge (real-time + correspondence), incoming challenge banner,
#    and private message
# ----------------------------------------------------------------------

tcltest::test lichess-phase2-social {user lookup, rating history canvas chart, teams join/leave, challenge, incoming challenge banner, and messaging} -setup {
	::scidb::test::lichess2::Stub
} -body {
	set tab [::lichess::social::open .application]
	update

	# Look up user "Magnus"
	::lichess::social::Lookup "Magnus"
	uplevel #0 [list {*}$::scidb::test::lichess2::userCmd [dict create ok 1 data [dict create \
		username Magnus title GM perfs [dict create blitz [dict create rating 2850] rapid [dict create rating 2810]] \
		profile [dict create bio "World Champion"]]]]
	uplevel #0 [list {*}$::scidb::test::lichess2::ratingHistoryCmd [dict create ok 1 data [list \
		[dict create name Blitz points {{2026 0 1 2800} {2026 1 1 2825} {2026 2 1 2850}}]]]]
	uplevel #0 [list {*}$::scidb::test::lichess2::teamsOfCmd [dict create ok 1 data [list \
		[dict create id team-norway name "Team Norway" nbMembers 420]]]]
	update

	set c $::lichess::social::Priv(widget:canvas)
	set chartLines [llength [$c find withtag chartLine]]
	set chartPoints [llength [$c find withtag point]]
	set teamItems [$::lichess::social::Priv(widget:teams) children {}]

	# Join and leave team
	::lichess::social::JoinTeam "team-norway" "Hello!"
	uplevel #0 [list {*}$::scidb::test::lichess2::joinTeamCmd {ok 1}]
	set joinedStatus $::lichess::social::Priv(statusText)

	::lichess::social::LeaveTeam "team-norway"
	uplevel #0 [list {*}$::scidb::test::lichess2::leaveTeamCmd {ok 1}]
	set leftStatus $::lichess::social::Priv(statusText)

	# Challenge user (correspondence 3 days, chess960, white, rated)
	set ::lichess::social::Priv(chMinutes) 10
	set ::lichess::social::Priv(chIncrement) 5
	set ::lichess::social::Priv(chDays) 3
	set ::lichess::social::Priv(chVariant) chess960
	set ::lichess::social::Priv(chColor) white
	set ::lichess::social::Priv(chRated) 1
	::lichess::social::Challenge "Magnus"
	uplevel #0 [list {*}$::scidb::test::lichess2::challengeUserCmd [dict create ok 1 data [dict create id chOut99]]]
	set outId $::lichess::social::Priv(outgoingId)

	# Cancel outgoing challenge
	::lichess::social::CancelChallenge
	uplevel #0 [list {*}$::scidb::test::lichess2::cancelChallengeCmd {ok 1}]
	set outAfterCancel $::lichess::social::Priv(outgoingId)

	# Incoming challenge via ::lichess::OnEvent -> banner shown -> accept & decline
	::lichess::OnEvent [dict create type challenge challenge [dict create \
		id chIn101 challenger [dict create name Hikaru id hikaru] \
		variant [dict create name Standard] timeControl [dict create show "10+0"] rated 1]]
	update
	set bannerShown [expr {[llength [grid info $::lichess::social::Priv(widget:incoming)]] > 0}]
	::lichess::social::AcceptIncoming
	uplevel #0 [list {*}$::scidb::test::lichess2::acceptChallengeCmd {ok 1}]
	set bannerAfterAccept [expr {[llength [grid info $::lichess::social::Priv(widget:incoming)]] > 0}]

	# Second incoming challenge -> decline with reason "tooFast"
	::lichess::OnEvent [dict create type challenge challenge [dict create \
		id chIn102 challenger [dict create name Alireza id alireza] \
		variant [dict create name Blitz] speed blitz rated 0]]
	set ::lichess::social::Priv(declineReason) tooFast
	::lichess::social::DeclineIncoming
	uplevel #0 [list {*}$::scidb::test::lichess2::declineChallengeCmd {ok 1}]

	# Send private message
	::lichess::social::SendMessage "Magnus" "Good game!"
	uplevel #0 [list {*}$::scidb::test::lichess2::sendMessageCmd {ok 1}]
	set msgStatus $::lichess::social::Priv(statusText)

	list \
		[::capability::present lichess_social] \
		[string match "*GM Magnus*" $::lichess::social::Priv(profileText)] \
		[string match "*2850*" $::lichess::social::Priv(profileText)] \
		$chartLines $chartPoints $teamItems \
		$joinedStatus $leftStatus \
		$outId $outAfterCancel \
		$bannerShown $bannerAfterAccept \
		$msgStatus \
		$::scidb::test::lichess2::calls
} -cleanup {
	::scidb::test::lichess2::Unstub
} -result {1 1 1 1 3 team-norway {Joined team team-norway.} {Left team team-norway.} chOut99 {} 1 0 {Message sent to Magnus.} {{user Magnus} {ratingHistory Magnus} {teamsOf Magnus} {joinTeam team-norway Hello!} {leaveTeam team-norway} {challengeUser Magnus 10 5 1 white chess960 3} {cancelChallenge chOut99} {acceptChallenge chIn101} {declineChallenge chIn102 tooFast} {sendMessage Magnus {Good game!}}}}

# ----------------------------------------------------------------------
# 2. TV & Broadcasts tab (::lichess::tv): channels, tvFeed, streamGameMoves,
#    broadcastsTop, and broadcastRoundStream (pgnStream)
# ----------------------------------------------------------------------

tcltest::test lichess-phase2-tv {TV channels, tvFeed featured/fen updates, streamGameMoves, top broadcasts, and live broadcast round PGN stream} -setup {
	::scidb::test::lichess2::Stub
} -body {
	set tab [::lichess::tv::open .application]
	update

	# Reply to initial RefreshChannels and RefreshBroadcasts
	uplevel #0 [list {*}$::scidb::test::lichess2::tvChannelsCmd [dict create ok 1 data [dict create \
		Rapid [dict create user [dict create name Ding title GM] rating 2780 gameId tvGame01]]]]
	uplevel #0 [list {*}$::scidb::test::lichess2::broadcastsTopCmd [dict create ok 1 data [dict create \
		active [list [dict create tour [dict create name "Candidates 2026"] \
			round [dict create id rnd01 name "Round 1"]]]]]]
	update

	set chItems [$::lichess::tv::Priv(widget:channels) children {}]
	set brItems [$::lichess::tv::Priv(widget:broadcasts) children {}]

	# Watch channel "Rapid" -> tvFeed featured + fen event
	set hTv [::lichess::tv::WatchSelectedChannel "Rapid"]
	uplevel #0 [list {*}$::scidb::test::lichess2::tvFeedCmd [dict create t featured d [dict create \
		id tvGame01 orientation white fen "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1" \
		players [list \
			[dict create color white user [dict create name Ding title GM] rating 2780] \
			[dict create color black user [dict create name Gukesh title GM] rating 2775]]]]]
	uplevel #0 [list {*}$::scidb::test::lichess2::tvFeedCmd [dict create t fen d [dict create \
		fen "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1" lm e2e4 wc 595 bc 600]]]
	set fenAfterTv [lindex [::online::view::fen $::lichess::tv::Priv(view)] 0]

	# Watch specific game by ID -> streamGameMoves
	set hGm [::lichess::tv::WatchGame "watchG99"]
	uplevel #0 [list {*}$::scidb::test::lichess2::streamGameMovesCmd [dict create \
		id watchG99 initialFen startpos moves "d2d4 d7d5" \
		players [dict create \
			white [dict create user [dict create name Fabi] rating 2800] \
			black [dict create user [dict create name Nepo] rating 2790]]]]
	set fenAfterWatch [lindex [::online::view::fen $::lichess::tv::Priv(view)] 0]

	# Follow live broadcast round -> broadcastRoundStream pgnStream
	set hBr [::lichess::tv::FollowBroadcastRound "rnd01"]
	set samplePgn "\[Event \"Candidates\"\]\n\[White \"Caruana\"\]\n\[Black \"Nakamura\"\]\n\[Result \"*\"\]\n\n1. e4 e5 2. Nf3 Nc6 *"
	uplevel #0 [list {*}$::scidb::test::lichess2::broadcastRoundStreamCmd [dict create \
		type pgn text $samplePgn]]
	set roundGameCount [llength $::lichess::tv::Priv(roundGames)]
	set fenAfterBr [lindex [::online::view::fen $::lichess::tv::Priv(view)] 0]
	::lichess::tv::StopStream

	list \
		[::capability::present lichess_tv] \
		$chItems $brItems \
		$fenAfterTv \
		$fenAfterWatch \
		$roundGameCount $fenAfterBr \
		$::scidb::test::lichess2::calls
} -cleanup {
	::scidb::test::lichess2::Unstub
} -result {1 Rapid rnd01 rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR rnbqkbnr/ppp1pppp/8/3p4/3P4/8/PPP1PPPP/RNBQKBNR 1 r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R {tvChannels broadcastsTop {tvFeed Rapid tv-1} {close tv-1} {streamGameMoves watchG99 mv-2} {close mv-2} {broadcastRoundStream rnd01 br-3} {close br-3}}}

# ----------------------------------------------------------------------
# 3. Tournaments & Simuls tab (::lichess::events): arenas, arena details,
#    join/withdraw arena, team swiss, join/withdraw swiss, simuls + browser
# ----------------------------------------------------------------------

tcltest::test lichess-phase2-events {arenas, arena details, join/withdraw arena, team swiss list + join/withdraw, and simuls open in browser} -setup {
	::scidb::test::lichess2::Stub
} -body {
	set tab [::lichess::events::open .application]
	update

	uplevel #0 [list {*}$::scidb::test::lichess2::arenasCmd [dict create ok 1 data [dict create \
		started [list [dict create id arena01 fullName "Titled Arena" nbPlayers 350 variant [dict create name Rapid]]] \
		created [list [dict create id arena02 fullName "Weekly Classical" nbPlayers 90 variant [dict create name Classical]]]]]]
	uplevel #0 [list {*}$::scidb::test::lichess2::simulsCmd [dict create ok 1 data [dict create \
		started [list [dict create id sim01 name "GM Simul" host [dict create name Judit title GM] \
			variants [list [dict create name Standard]]]]]]]
	update

	set arenaRows [$::lichess::events::Priv(widget:arenas) children {}]
	set simulRows [$::lichess::events::Priv(widget:simuls) children {}]

	# Inspect, join, and withdraw arena
	::lichess::events::InspectArena "arena01"
	uplevel #0 [list {*}$::scidb::test::lichess2::arenaCmd [dict create ok 1 data [dict create \
		id arena01 fullName "Titled Arena" nbPlayers 350 minutes 120]]]
	set detailText $::lichess::events::Priv(arenaDetailText)

	::lichess::events::JoinArena "arena01"
	uplevel #0 [list {*}$::scidb::test::lichess2::joinArenaCmd {ok 1}]
	set joinArenaStatus $::lichess::events::Priv(statusText)

	::lichess::events::WithdrawArena "arena01"
	uplevel #0 [list {*}$::scidb::test::lichess2::withdrawArenaCmd {ok 1}]
	set withdrawArenaStatus $::lichess::events::Priv(statusText)

	# Load team Swiss, join and withdraw
	::lichess::events::LoadTeamSwiss "chesswiz-club"
	uplevel #0 [list {*}$::scidb::test::lichess2::swissOfTeamCmd [dict create ok 1 data [list \
		[dict create id sw01 name "Club Swiss" status created round 1 nbPlayers 48]]]]
	set swissRows [$::lichess::events::Priv(widget:swiss) children {}]

	::lichess::events::JoinSwiss "sw01"
	uplevel #0 [list {*}$::scidb::test::lichess2::joinSwissCmd {ok 1}]
	set joinSwissStatus $::lichess::events::Priv(statusText)

	::lichess::events::WithdrawSwiss "sw01"
	uplevel #0 [list {*}$::scidb::test::lichess2::withdrawSwissCmd {ok 1}]
	set withdrawSwissStatus $::lichess::events::Priv(statusText)

	# Open simul in browser
	::lichess::events::OpenSimulInBrowser "sim01"

	list \
		[::capability::present lichess_events] \
		$arenaRows $simulRows \
		$detailText $joinArenaStatus $withdrawArenaStatus \
		$swissRows $joinSwissStatus $withdrawSwissStatus \
		$::scidb::test::lichess2::browserUrls \
		$::scidb::test::lichess2::calls
} -cleanup {
	::scidb::test::lichess2::Unstub
} -result {1 {arena01 arena02} sim01 {Titled Arena (arena01) — 350 players, 120 min} {Joined arena arena01.} {Withdrew from arena arena01.} sw01 {Joined Swiss tournament sw01.} {Withdrew from Swiss tournament sw01.} https://lichess.org/simul/sim01 {arenas simuls {arena arena01} {joinArena arena01} {withdrawArena arena01} {swissOfTeam chesswiz-club} {joinSwiss sw01} {withdrawSwiss sw01} {OpenBrowser https://lichess.org/simul/sim01}}}

# ----------------------------------------------------------------------
# 4. Puzzles tab (::lichess::puzzles): daily, next, by ID, interactive
#    solving + auto-reply + puzzleBatchSolved, dashboard & activity,
#    local 3-minute Storm, and Puzzle Racer
# ----------------------------------------------------------------------

tcltest::test lichess-phase2-puzzles {daily/next/by-id fetch, interactive solving with opponent reply, puzzleBatchSolved reporting, dashboard/activity, local Storm, and Racer} -setup {
	::scidb::test::lichess2::Stub
} -body {
	set tab [::lichess::puzzles::open .application]
	update

	set samplePuzzle [dict create \
		game [dict create id gPuz1 pgn "1. e4 e5 2. Nf3 Nc6"] \
		puzzle [dict create id puz001 rating 1620 initialPly 3 \
			themes {fork middlegame} solution {f1b5 a7a6 b5c6}]]

	# 1. Fetch daily puzzle and solve cleanly on first try
	::lichess::puzzles::FetchDaily
	uplevel #0 [list {*}$::scidb::test::lichess2::puzzleDailyCmd [dict create ok 1 data $samplePuzzle]]
	set startFen1 [lindex $::lichess::puzzles::Priv(currentFen) 0]

	# First user move f1b5 -> auto-plays opponent's reply a7a6
	set step1 [::lichess::puzzles::PlayMove "Bb5"]
	set remAfterStep1 $::lichess::puzzles::Priv(remaining)
	# Final user move b5c6 -> marks solved and calls puzzleBatchSolved with win=1
	set step2 [::lichess::puzzles::PlayMove "Bxc6"]
	set stateAfterSolve $::lichess::puzzles::Priv(state)

	# 2. Fetch by ID, make a wrong move (reports win=0), then Retry and solve
	::lichess::puzzles::FetchById "puz002"
	set samplePuzzle2 [dict create \
		game [dict create id gPuz2 pgn "1. e4 e5"] \
		puzzle [dict create id puz002 rating 1400 initialPly 1 \
			themes {opening} solution {g1f3}]]
	uplevel #0 [list {*}$::scidb::test::lichess2::puzzleCmd [dict create ok 1 data $samplePuzzle2]]
	set wrongRes [::lichess::puzzles::PlayMove "a3"]
	set stateAfterWrong $::lichess::puzzles::Priv(state)
	::lichess::puzzles::Retry
	set retryOk [::lichess::puzzles::PlayMove "Nf3"]

	# 3. Dashboard and activity
	::lichess::puzzles::RefreshStats 30 10
	uplevel #0 [list {*}$::scidb::test::lichess2::puzzleDashboardCmd [dict create ok 1 data [dict create \
		days 30 global [dict create nb 50 firstWins 41 performance 1820]]]]
	uplevel #0 [list {*}$::scidb::test::lichess2::puzzleActivityCmd [dict create ok 1 data [list \
		[dict create id puz001 puzzleRating 1620 win 1]]]]
	set dashText $::lichess::puzzles::Priv(dashboardText)
	set actRows [$::lichess::puzzles::Priv(widget:activity) children {}]

	# 4. Local 3-minute Storm: start, solve one puzzle -> increments stormScore and fetches next, then stop
	set ::lichess::puzzles::Priv(angle) mateIn1
	set ::lichess::puzzles::Priv(difficulty) normal
	::lichess::puzzles::StartStorm
	uplevel #0 [list {*}$::scidb::test::lichess2::puzzleNextCmd [dict create ok 1 data $samplePuzzle2]]
	::lichess::puzzles::PlayMove "Nf3"
	set stormScore [::lichess::puzzles::StopStorm]

	# 5. Puzzle Racer -> opens URL in browser
	::lichess::puzzles::StartRacer
	uplevel #0 [list {*}$::scidb::test::lichess2::puzzleRaceCmd [dict create ok 1 data [dict create \
		id race77 url "https://lichess.org/racer/race77"]]]

	list \
		[::capability::present lichess_puzzles] \
		$startFen1 $step1 $remAfterStep1 $step2 $stateAfterSolve \
		$wrongRes $stateAfterWrong $retryOk \
		$dashText $actRows \
		$stormScore \
		$::scidb::test::lichess2::browserUrls \
		$::scidb::test::lichess2::calls
} -cleanup {
	::scidb::test::lichess2::Unstub
} -result {1 r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R 1 b5c6 1 solved 0 wrong 1 {Last 30 days: 50 puzzles, 41 first-try wins, performance 1820} puz001 1 https://lichess.org/racer/race77 {puzzleDaily {puzzleBatchSolved mix {{id puz001 win 1 rated 1}}} {puzzle puz002} {puzzleBatchSolved mix {{id puz002 win 0 rated 1}}} {puzzleDashboard 30} {puzzleActivity 10} {puzzleNext mateIn1 normal} {puzzleBatchSolved mateIn1 {{id puz002 win 1 rated 1}}} {puzzleNext mateIn1 normal} puzzleRace {OpenBrowser https://lichess.org/racer/race77}}}

# ----------------------------------------------------------------------
# 5. Game panel & lobby extras in ::lichess (correspondence/variant seek,
#    chatHistory + SendChat, takeback offer/accept/decline, bot mode +
#    botUpgrade, Cloud eval, Analyse on Lichess, ExportGamePgn)
# ----------------------------------------------------------------------

tcltest::test lichess-phase2-game-and-lobby-extras {correspondence/variant seek, chatHistory, takeback offer/accept/decline, bot mode + upgrade, cloud eval, importGame + browser, and gameExport} -setup {
	set savedOpts [array get ::lichess::Options]
	::scidb::test::lichess2::Stub
} -body {
	set dlg [::lichess::open .application]
	update
	uplevel #0 [list {*}$::scidb::test::lichess2::accountCmd {ok 1 username Alice id alice}]
	update
	set ::scidb::test::lichess2::calls {}

	# 1. Correspondence + variant seek
	set ::lichess::Priv(dlg:minutes) 10
	set ::lichess::Priv(dlg:increment) 0
	set ::lichess::Priv(dlg:rated) 1
	set ::lichess::Priv(dlg:color) $::lichess::mc::White
	set ::lichess::Priv(dlg:variant) chess960
	set ::lichess::Priv(dlg:days) 3
	set seekH [::lichess::Seek]
	::lichess::CancelSeek

	# 2. Bot mode toggle & botUpgrade
	set modeBot [::lichess::ToggleBotMode 1]
	::lichess::UpgradeToBot 1
	uplevel #0 [list {*}$::scidb::test::lichess2::botUpgradeCmd {ok 1}]
	set botStatus $::lichess::Priv(statusText)
	set modeBoard [::lichess::ToggleBotMode 0]

	# 3. Start a game -> fetches chatHistory, handles incoming takeback & chat
	::lichess::OnEvent [dict create type gameStart game [dict create \
		gameId gExtra1 color white speed rapid rated 0]]
	uplevel #0 [list {*}$::scidb::test::lichess2::gameCmd [dict create \
		type gameFull id gExtra1 rated 0 speed rapid initialFen startpos \
		white {id alice name Alice rating 1700} \
		black {id bob name Bob rating 1720} \
		state {type gameState moves "e2e4 e7e5" wtime 600000 btime 600000 status started btakeback 1}]]
	uplevel #0 [list {*}$::scidb::test::lichess2::chatHistoryCmd [dict create ok 1 data [list \
		[dict create user Bob text "Hello from history!"]]]]
	update

	set tbOffered $::lichess::Priv(takebackOffer)
	::lichess::Takeback yes
	::lichess::Takeback yes
	::lichess::Takeback no
	::lichess::SendChat "Good luck!"

	# 4. Cloud eval (200 with PVs, then 404)
	::lichess::RequestCloudEval "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1" 2
	uplevel #0 [list {*}$::scidb::test::lichess2::cloudEvalCmd [dict create ok 1 data [dict create \
		depth 36 knodes 45000 pvs [list \
			[dict create cp 25 moves "e7e5 g1f3"] \
			[dict create cp 30 moves "c7c5 g1f3"]]]]]
	set eval200 $::lichess::Priv(cloudEvalText)

	::lichess::RequestCloudEval "8/8/8/8/8/8/8/4K2k w - - 0 1" 1
	uplevel #0 [list {*}$::scidb::test::lichess2::cloudEvalCmd [dict create \
		ok 0 status 404 error "No cloud evaluation for this position."]]
	set eval404 $::lichess::Priv(cloudEvalText)

	# 5. Analyse on Lichess (importGame -> OpenBrowser) and ExportGamePgn
	::lichess::AnalyseOnLichess "1. e4 e5 2. Nf3 Nc6 *"
	uplevel #0 [list {*}$::scidb::test::lichess2::importGameCmd [dict create ok 1 data [dict create \
		id imp12345 url "https://lichess.org/imp12345"]]]
	::lichess::ExportGamePgn "gExtra1"
	uplevel #0 [list {*}$::scidb::test::lichess2::gameExportCmd [dict create ok 1 data "\[Event \"Rated\"\]\n\n1. e4 e5 *\n"]]

	list \
		[expr {$seekH ne ""}] $modeBot $botStatus $modeBoard \
		$tbOffered \
		$eval200 $eval404 \
		$::lichess::Priv(exportedPgn) \
		$::scidb::test::lichess2::browserUrls \
		$::scidb::test::lichess2::calls
} -cleanup {
	::scidb::test::lichess2::Unstub
	array set ::lichess::Options $savedOpts
} -result {1 bot {Account upgraded to a Lichess Bot account.} board 1 {Depth 36 (45000k nodes): +0.25: e7e5 g1f3 | +0.30: c7c5 g1f3} {No cloud evaluation for this position.} {[Event "Rated"]

1. e4 e5 *
} https://lichess.org/imp12345 {{seek 10 0 1 white chess960 3 sk-2} {close sk-2} {mode bot} botUpgrade {mode bot} {mode board} {streamGame gExtra1 gm-3} {chatHistory gExtra1} {takeback gExtra1 yes} {takeback gExtra1 yes} {takeback gExtra1 no} {chat gExtra1 {Good luck!}} {cloudEval {rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1} 2} {cloudEval {8/8/8/8/8/8/8/4K2k w - - 0 1} 1} {importGame {1. e4 e5 2. Nf3 Nc6 *}} {OpenBrowser https://lichess.org/imp12345} {gameExport gExtra1}}}

# ----------------------------------------------------------------------
# 6. Send to Lichess study (::application::lichess::study): studiesOf,
#    studyCreate, and studyImportPgn
# ----------------------------------------------------------------------

tcltest::test lichess-phase2-studies {list user studies via studiesOf, create new study via studyCreate, and send PGN via studyImportPgn} -setup {
	::scidb::test::lichess2::Stub
} -body {
	set ::lichess::Priv(username) "Alice"
	set dlg [::application::lichess::study::open .application -kind game]
	update

	# Reply to initial LoadStudies for Alice
	uplevel #0 [list {*}$::scidb::test::lichess2::studiesOfCmd [dict create ok 1 data [list \
		[dict create id stdy0001 name "My Repertoire"]]]]
	set studyRows [$::application::lichess::study::Priv(widget:studies) children {}]
	set selectedStudy $::application::lichess::study::Priv(study)

	# Create a new study
	::application::lichess::study::CreateStudy "Endgame Notes" "unlisted"
	uplevel #0 [list {*}$::scidb::test::lichess2::studyCreateCmd [dict create ok 1 data [dict create \
		id stdy0002 name "Endgame Notes"]]]
	set afterCreateStudy $::application::lichess::study::Priv(study)
	set rowsAfterCreate [$::application::lichess::study::Priv(widget:studies) children {}]

	# Send PGN to study via studyImportPgn
	::application::lichess::study::SendPgnToStudy "stdy0002" "Rook Ending" "1. e4 e5 *" "black" "standard"
	uplevel #0 [list {*}$::scidb::test::lichess2::studyImportPgnCmd [dict create ok 1 data [dict create \
		chapters [list [dict create id chp99999 name "Rook Ending"]]]]]
	set uploadStatus $::application::lichess::study::Priv(statusText)

	::application::lichess::study::Close

	list \
		$studyRows $selectedStudy \
		$afterCreateStudy $rowsAfterCreate \
		$uploadStatus \
		$::scidb::test::lichess2::calls
} -cleanup {
	::scidb::test::lichess2::Unstub
} -result {stdy0001 stdy0001 stdy0002 {stdy0001 stdy0002} {Uploaded: https://lichess.org/study/stdy0002/chp99999} {{studiesOf Alice} {studyCreate {Endgame Notes} unlisted} {studyImportPgn stdy0002 {Rook Ending} {1. e4 e5 *} black standard}}}

tcltest::cleanupTests
