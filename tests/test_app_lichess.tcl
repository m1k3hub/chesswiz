# ======================================================================
# Scidb App Test — Lichess client (tcl/lichess.tcl)
# All tests below use local stubs for ::lichess::api commands. The real
# lichess.org is never contacted.
# ======================================================================

package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

namespace eval ::scidb::test::lichess {
	variable calls {}
	variable signedIn 0
	variable tokenValue {}
	variable signInCmd {}
	variable useTokenCmd {}
	variable accountCmd {}
	variable eventCmd {}
	variable seekCmd {}
	variable challengeCmd {}
	variable gameCmd {}
	variable moveCmds {}
	variable actionCmds {}
	variable nextHandle 0
	variable savedProcs {}
}

proc ::scidb::test::lichess::Stub {} {
	variable calls {}
	variable signedIn 0
	variable tokenValue {}
	variable signInCmd {}
	variable useTokenCmd {}
	variable accountCmd {}
	variable eventCmd {}
	variable seekCmd {}
	variable challengeCmd {}
	variable gameCmd {}
	variable moveCmds {}
	variable actionCmds {}
	variable nextHandle 0
	variable savedProcs {}

	namespace eval ::lichess::api {}
	foreach name {
		token signedIn? signIn useToken signOut account
		streamEvents streamGame close seek challengeAi
		move resign abort draw claimVictory
	} {
		set fq "::lichess::api::$name"
		set backup "::scidb::test::lichess::orig_$name"
		catch { rename $backup {} }
		if {[llength [info commands $fq]]} {
			rename $fq $backup
			lappend savedProcs $name
		}
	}

	proc ::lichess::api::token {} {
		return $::scidb::test::lichess::tokenValue
	}
	proc ::lichess::api::signedIn? {} {
		return $::scidb::test::lichess::signedIn
	}
	proc ::lichess::api::signIn {cmd} {
		lappend ::scidb::test::lichess::calls [list signIn]
		set ::scidb::test::lichess::signInCmd $cmd
	}
	proc ::lichess::api::useToken {tok cmd} {
		lappend ::scidb::test::lichess::calls [list useToken $tok]
		set ::scidb::test::lichess::useTokenCmd $cmd
	}
	proc ::lichess::api::signOut {} {
		lappend ::scidb::test::lichess::calls [list signOut]
		set ::scidb::test::lichess::signedIn 0
		set ::scidb::test::lichess::tokenValue {}
	}
	proc ::lichess::api::account {cmd} {
		lappend ::scidb::test::lichess::calls [list account]
		set ::scidb::test::lichess::accountCmd $cmd
	}
	proc ::lichess::api::streamEvents {cmd} {
		set h "ev-[incr ::scidb::test::lichess::nextHandle]"
		lappend ::scidb::test::lichess::calls [list streamEvents $h]
		set ::scidb::test::lichess::eventCmd $cmd
		return $h
	}
	proc ::lichess::api::streamGame {gameId cmd} {
		set h "gm-[incr ::scidb::test::lichess::nextHandle]"
		lappend ::scidb::test::lichess::calls [list streamGame $gameId $h]
		set ::scidb::test::lichess::gameCmd $cmd
		return $h
	}
	proc ::lichess::api::close {handle} {
		lappend ::scidb::test::lichess::calls [list close $handle]
	}
	proc ::lichess::api::seek {minutes increment rated color cmd} {
		set h "sk-[incr ::scidb::test::lichess::nextHandle]"
		lappend ::scidb::test::lichess::calls [list seek $minutes $increment $rated $color $h]
		set ::scidb::test::lichess::seekCmd $cmd
		return $h
	}
	proc ::lichess::api::challengeAi {level minutes increment color cmd} {
		lappend ::scidb::test::lichess::calls [list challengeAi $level $minutes $increment $color]
		set ::scidb::test::lichess::challengeCmd $cmd
	}
	proc ::lichess::api::move {gameId uci cmd} {
		lappend ::scidb::test::lichess::calls [list move $gameId $uci]
		lappend ::scidb::test::lichess::moveCmds $cmd
	}
	proc ::lichess::api::resign {gameId cmd} {
		lappend ::scidb::test::lichess::calls [list resign $gameId]
		lappend ::scidb::test::lichess::actionCmds $cmd
	}
	proc ::lichess::api::abort {gameId cmd} {
		lappend ::scidb::test::lichess::calls [list abort $gameId]
		lappend ::scidb::test::lichess::actionCmds $cmd
	}
	proc ::lichess::api::draw {gameId yesno cmd} {
		lappend ::scidb::test::lichess::calls [list draw $gameId $yesno]
		lappend ::scidb::test::lichess::actionCmds $cmd
	}
	proc ::lichess::api::claimVictory {gameId cmd} {
		lappend ::scidb::test::lichess::calls [list claimVictory $gameId]
		lappend ::scidb::test::lichess::actionCmds $cmd
	}
}

proc ::scidb::test::lichess::Unstub {} {
	variable savedProcs
	set pos $::lichess::Priv(pos)
	catch { ::lichess::Close }
	if {$pos > 0} {
		catch { ::application::pgn::release $pos }
		catch { ::game::release $pos }
	}
	foreach name {
		token signedIn? signIn useToken signOut account
		streamEvents streamGame close seek challengeAi
		move resign abort draw claimVictory
	} {
		set fq "::lichess::api::$name"
		set backup "::scidb::test::lichess::orig_$name"
		catch { rename $fq {} }
		if {$name in $savedProcs && [llength [info commands $backup]]} {
			rename $backup $fq
		}
	}
	set savedProcs {}
}

proc ::scidb::test::lichess::EmitEvent {dict} {
	variable eventCmd
	uplevel #0 [list {*}$eventCmd $dict]
}

proc ::scidb::test::lichess::EmitGame {dict} {
	variable gameCmd
	uplevel #0 [list {*}$gameCmd $dict]
}

proc ::scidb::test::lichess::ReplyMove {dict} {
	variable moveCmds
	set cmd [lindex $moveCmds end]
	uplevel #0 [list {*}$cmd $dict]
}

proc ::scidb::test::lichess::ReplyAction {dict} {
	variable actionCmds
	set cmd [lindex $actionCmds end]
	uplevel #0 [list {*}$cmd $dict]
}

# ----------------------------------------------------------------------
# Pure UCI helpers
# ----------------------------------------------------------------------

tcltest::test lichess-uci-from-fens {normal, capture, castling both sides/colours, en passant, promotion and under-promotion} -body {
	list \
		[::lichess::uciFromFens \
			"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1" \
			"rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1"] \
		[::lichess::uciFromFens \
			"rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2" \
			"rnbqkbnr/ppp1pppp/8/3P4/8/8/PPPP1PPP/RNBQKBNR b KQkq - 0 2"] \
		[::lichess::uciFromFens \
			"r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1" \
			"r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R4RK1 b kq - 1 1"] \
		[::lichess::uciFromFens \
			"r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1" \
			"r3k2r/pppppppp/8/8/8/8/PPPPPPPP/2KR3R b kq - 1 1"] \
		[::lichess::uciFromFens \
			"r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R b KQkq - 0 1" \
			"r4rk1/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQ - 1 2"] \
		[::lichess::uciFromFens \
			"r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R b KQkq - 0 1" \
			"2kr3r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQ - 1 2"] \
		[::lichess::uciFromFens \
			"rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3" \
			"rnbqkbnr/ppp1p1pp/5P2/3p4/8/8/PPPP1PPP/RNBQKBNR b KQkq - 0 3"] \
		[::lichess::uciFromFens \
			"rnbqkbnr/pppp1ppp/8/8/3pP3/8/PPP2PPP/RNBQKBNR b KQkq e3 0 3" \
			"rnbqkbnr/pppp1ppp/8/8/8/4p3/PPP2PPP/RNBQKBNR w KQkq - 0 4"] \
		[::lichess::uciFromFens \
			"4k3/P7/8/8/8/8/8/4K3 w - - 0 1" \
			"Q3k3/8/8/8/8/8/8/4K3 b - - 0 1"] \
		[::lichess::uciFromFens \
			"4k3/P7/8/8/8/8/8/4K3 w - - 0 1" \
			"N3k3/8/8/8/8/8/8/4K3 b - - 0 1"] \
		[::lichess::uciFromFens \
			"1r2k3/P7/8/8/8/8/8/4K3 w - - 0 1" \
			"1R2k3/8/8/8/8/8/8/4K3 b - - 0 1"] \
		[::lichess::uciFromFens \
			"4k3/8/8/8/8/8/p7/1B2K3 b - - 0 1" \
			"4k3/8/8/8/8/8/8/1b2K3 w - - 0 2"]
} -result {e2e4 e4d5 e1g1 e1c1 e8g8 e8c8 e5f6 d4e3 a7a8q a7a8n a7b8r a2b1b}

tcltest::test lichess-clock-countdown {only the ticking side to move counts down between snapshots} -setup {
	set saved [array get ::lichess::Priv]
	array set ::lichess::Priv {clock:w 15000 clock:b 12000 clockAt 50000 clockStm b ticking 1}
} -body {
	list [::lichess::Remaining w 50400] [::lichess::Remaining b 50400] [::lichess::Remaining b 51250]
} -cleanup {
	array set ::lichess::Priv $saved
} -result {15000 11600 10750}

# ----------------------------------------------------------------------
# Sign-in states, token privacy, seek speed rule, AI challenge
# ----------------------------------------------------------------------

tcltest::test lichess-signin-and-privacy {OAuth sign-in, token sign-in, account pre-signed-in, sign-out and token never saved to options} -setup {
	set savedOpts [array get ::lichess::Options]
	::scidb::test::lichess::Stub
} -body {
	set dlg [::lichess::open .application]
	update
	set initialState $::lichess::Priv(state)
	set tokenShow [$::lichess::Priv(widget:signin).token cget -show]

	# 1. Sign in via browser (PKCE)
	::lichess::SignIn
	set waitingStatus $::lichess::Priv(statusText)
	uplevel #0 [list {*}$::scidb::test::lichess::signInCmd {ok 1 username Alice id alice}]
	update
	set afterOAuth [list $::lichess::Priv(state) $::lichess::Priv(username) $::lichess::Priv(userId) \
		$::lichess::Priv(statusText) [expr {$::lichess::Priv(eventHandle) ne ""}]]

	# 2. Sign out
	::lichess::SignOut
	update
	set afterSignOut [list $::lichess::Priv(state) $::lichess::Priv(username) $::lichess::Priv(eventHandle)]

	# 3. Paste a personal token (never saved in Options or Priv)
	set secret "lio_secret_token_do_not_save"
	set ::lichess::Priv(dlg:token) $secret
	::lichess::UseToken
	set clearedEntry $::lichess::Priv(dlg:token)
	uplevel #0 [list {*}$::scidb::test::lichess::useTokenCmd {ok 1 username Bob}]
	update
	set afterToken [list $::lichess::Priv(state) $::lichess::Priv(username) $::lichess::Priv(userId)]

	set file [file join $::env(HOME) lichess-options.tcl]
	set out [open $file w]
	::lichess::WriteOptions $out
	close $out
	set in [open $file r]
	set savedText [read $in]
	close $in
	set tokenInOptions [expr {[string first $secret $savedText] >= 0}]
	set tokenInPriv [expr {[string first $secret [array get ::lichess::Priv]] >= 0}]

	# 4. Reopen when already signedIn? -> calls account and streamEvents
	::lichess::Close
	set ::scidb::test::lichess::signedIn 1
	set dlg2 [::lichess::open .application]
	update
	uplevel #0 [list {*}$::scidb::test::lichess::accountCmd {ok 1 username Carol id carol}]
	update
	set afterAccount [list $::lichess::Priv(state) $::lichess::Priv(username) $::lichess::Priv(userId)]

	list \
		[::capability::present lichess] \
		$initialState $tokenShow $waitingStatus \
		$afterOAuth $afterSignOut \
		$clearedEntry $afterToken $tokenInOptions $tokenInPriv \
		$afterAccount
} -cleanup {
	::scidb::test::lichess::Unstub
	array set ::lichess::Options $savedOpts
} -result {1 offline * {Waiting for the browser…} {lobby Alice alice {Signed in as Alice.} 1} {offline {} {}} {} {lobby Bob bob} 0 0 {lobby Carol carol}}

tcltest::test lichess-seek-and-ai {Rapid-or-slower seek rule, seek cancel, and AI challenge call} -setup {
	set savedOpts [array get ::lichess::Options]
	::scidb::test::lichess::Stub
	set ::scidb::test::lichess::signedIn 1
} -body {
	set dlg [::lichess::open .application]
	update
	uplevel #0 [list {*}$::scidb::test::lichess::accountCmd {ok 1 username Alice id alice}]
	update
	set ::scidb::test::lichess::calls {}

	# Faster than Rapid (5+0 = 300 < 480, and 5+3 = 420 < 480) refused before sending
	set ::lichess::Priv(dlg:minutes) 5
	set ::lichess::Priv(dlg:increment) 3
	set ::lichess::Priv(dlg:rated) 0
	set ::lichess::Priv(dlg:color) $::lichess::mc::White
	set fastRes [::lichess::Seek]
	set fastStatus $::lichess::Priv(statusText)
	set callsAfterFast $::scidb::test::lichess::calls

	# Rapid boundary (5+5 = 500 >= 480, or 8+0 = 480 >= 480) accepted
	set ::lichess::Priv(dlg:minutes) 8
	set ::lichess::Priv(dlg:increment) 0
	set ::lichess::Priv(dlg:rated) 1
	set ::lichess::Priv(dlg:color) $::lichess::mc::Black
	set seekHandle [::lichess::Seek]
	set seekStatus $::lichess::Priv(statusText)
	set cancelOk [::lichess::CancelSeek]
	set cancelStatus $::lichess::Priv(statusText)

	# AI challenge allows Blitz (3+2, level 4, white)
	set ::lichess::Priv(dlg:aiLevel) 4
	set ::lichess::Priv(dlg:aiMinutes) 3
	set ::lichess::Priv(dlg:aiIncrement) 2
	set ::lichess::Priv(dlg:aiColor) $::lichess::mc::White
	set aiOk [::lichess::ChallengeAi]
	uplevel #0 [list {*}$::scidb::test::lichess::challengeCmd {ok 1 id aiGame01}]

	list \
		$fastRes [expr {$fastStatus eq $::lichess::mc::SeekTooFast}] $callsAfterFast \
		[expr {$seekHandle ne ""}] [expr {$seekStatus eq $::lichess::mc::Seeking}] \
		$cancelOk [expr {$cancelStatus eq $::lichess::mc::SeekCancelled}] \
		$aiOk $::scidb::test::lichess::calls
} -cleanup {
	::scidb::test::lichess::Unstub
	array set ::lichess::Options $savedOpts
} -result {0 1 {} 1 1 1 1 1 {{seek 8 0 1 black sk-2} {close sk-2} {challengeAi 4 3 2 white}}}

# ----------------------------------------------------------------------
# Full game both colours: moves, echo, resync, reject, draw, opponentGone
# ----------------------------------------------------------------------

tcltest::test lichess-game-white {full game as White: moves both ways, echo ignored, resync on jump, rejected move rollback, draw offer, opponentGone + claim} -setup {
	set savedOpts [array get ::lichess::Options]
	::scidb::test::lichess::Stub
	set ::scidb::test::lichess::signedIn 1
} -body {
	set dlg [::lichess::open .application]
	update
	uplevel #0 [list {*}$::scidb::test::lichess::accountCmd {ok 1 username Alice id alice}]
	update
	set ::scidb::test::lichess::calls {}

	# Event stream gameStart opens the game stream
	::scidb::test::lichess::EmitEvent [dict create type gameStart game [dict create \
		gameId gameW123 color white speed rapid rated 1]]
	::scidb::test::lichess::EmitGame [dict create \
		type gameFull id gameW123 rated 1 speed rapid initialFen startpos \
		clock {initial 600000 increment 5000} \
		white {id alice name Alice rating 1650} \
		black {id bob name Bob rating 1700} \
		state {type gameState moves "" wtime 600000 btime 600000 winc 5000 binc 5000 status started}]
	update

	set initialTags [::scidb::game::tags]

	# User plays 1. e4 -> sends e2e4
	set m1 [::lichess::UserMove e4]
	::scidb::test::lichess::ReplyMove {ok 1}
	set plyAfterUser [::lichess::BoardPly]

	# Server echoes e2e4 -> equal length, ignored (no duplicate move)
	::scidb::test::lichess::EmitGame [dict create \
		type gameState moves "e2e4" wtime 599000 btime 600000 status started]
	set plyAfterEcho [::lichess::BoardPly]

	# Opponent plays 1... e5 -> delta == 1, played via uciToSan
	::scidb::test::lichess::EmitGame [dict create \
		type gameState moves "e2e4 e7e5" wtime 599000 btime 598000 status started]
	set plyAfterOpp [::lichess::BoardPly]
	set fenAfterOpp [lindex [::scidb::pos::fen] 0]

	# User plays 2. Nf3, server rejects with {ok 0} -> rolled back to ply 2
	set m2 [::lichess::UserMove Nf3]
	set plyBeforeReject [::lichess::BoardPly]
	::scidb::test::lichess::ReplyMove {ok 0 error "Not your turn"}
	set plyAfterReject [::lichess::BoardPly]
	set fenAfterReject [lindex [::scidb::pos::fen] 0]

	# Server jumps ahead by 3 plies -> triggers Resync (re-imports initialFen + all moves)
	::scidb::test::lichess::EmitGame [dict create \
		type gameState moves "e2e4 e7e5 g1f3 b8c6 f1b5" wtime 595000 btime 594000 status started]
	set plyAfterJump [::lichess::BoardPly]
	set fenAfterJump [lindex [::scidb::pos::fen] 0]

	# Opponent plays 3... a6 with a draw offer (bdraw 1)
	::scidb::test::lichess::EmitGame [dict create \
		type gameState moves "e2e4 e7e5 g1f3 b8c6 f1b5 a7a6" \
		wtime 595000 btime 590000 status started bdraw 1]
	set drawOffered [list $::lichess::Priv(drawOffer) \
		[$::lichess::Priv(widget:accept) instate !disabled] \
		[$::lichess::Priv(widget:decline) instate !disabled]]
	::lichess::OfferDraw
	::scidb::test::lichess::ReplyAction {ok 1}
	::lichess::DeclineDraw
	::scidb::test::lichess::ReplyAction {ok 1}

	# Opponent leaves -> opponentGone enables Claim victory
	::scidb::test::lichess::EmitGame [dict create \
		type opponentGone gone 1 claimWinInSeconds 10]
	set goneState [list $::lichess::Priv(opponentGone) \
		[$::lichess::Priv(widget:claim) instate !disabled]]
	::lichess::ClaimVictory
	::scidb::test::lichess::ReplyAction {ok 1}

	# Server ends game by resign (winner white)
	::scidb::test::lichess::EmitGame [dict create \
		type gameState moves "e2e4 e7e5 g1f3 b8c6 f1b5 a7a6" \
		wtime 595000 btime 590000 status resign winner white]
	set finalTags [::scidb::game::tags]
	set backEnabled [$::lichess::Priv(widget:back) instate !disabled]
	set posW $::lichess::Priv(pos)
	set backOk [::lichess::BackToLobby]
	catch { ::application::pgn::release $posW }
	catch { ::game::release $posW }

	list \
		[expr {[lsearch -exact $initialTags {Event {Lichess rated rapid game}}] >= 0}] \
		[expr {[lsearch -exact $initialTags {Site https://lichess.org/gameW123}] >= 0}] \
		[expr {[lsearch -exact $initialTags {White Alice}] >= 0}] \
		[expr {[lsearch -exact $initialTags {Black Bob}] >= 0}] \
		[expr {[lsearch -exact $initialTags {WhiteElo 1650}] >= 0}] \
		[expr {[lsearch -exact $initialTags {BlackElo 1700}] >= 0}] \
		[expr {[lsearch -exact $initialTags {TimeControl 600+5}] >= 0}] \
		$m1 $plyAfterUser $plyAfterEcho $plyAfterOpp $fenAfterOpp \
		$m2 $plyBeforeReject $plyAfterReject $fenAfterReject \
		$plyAfterJump $fenAfterJump \
		$drawOffered $goneState \
		[expr {[lsearch -exact $finalTags {Result 1-0}] >= 0}] \
		$backEnabled $backOk $::lichess::Priv(state) \
		$::scidb::test::lichess::calls
} -cleanup {
	::scidb::test::lichess::Unstub
	array set ::lichess::Options $savedOpts
} -result {1 1 1 1 1 1 1 1 1 1 2 rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR 1 3 2 rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR 5 r1bqkbnr/pppp1ppp/2n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQK2R {1 1 1} {1 1} 1 1 1 lobby {{streamGame gameW123 gm-2} {move gameW123 e2e4} {move gameW123 g1f3} {draw gameW123 yes} {draw gameW123 no} {claimVictory gameW123} {close gm-2}}}

tcltest::test lichess-game-black-and-results {full game as Black against AI (board rotated, AI name, wdraw accept) and result headers for mate, resign, draw and abort} -setup {
	set savedOpts [array get ::lichess::Options]
	::scidb::test::lichess::Stub
	set ::scidb::test::lichess::signedIn 1
} -body {
	set dlg [::lichess::open .application]
	update
	uplevel #0 [list {*}$::scidb::test::lichess::accountCmd {ok 1 username Alice id alice}]
	update
	set ::scidb::test::lichess::calls {}

	# Start game as Black vs Stockfish level 5 (no numeric Elo for AI)
	::scidb::test::lichess::EmitEvent [dict create type gameStart game [dict create \
		gameId gameB456 color black speed blitz rated 0]]
	::scidb::test::lichess::EmitGame [dict create \
		type gameFull id gameB456 rated 0 speed blitz initialFen startpos \
		clock {initial 180000 increment 2000} \
		white {aiLevel 5} \
		black {id alice name Alice rating 1650} \
		state {type gameState moves "d2d4" wtime 180000 btime 180000 winc 2000 binc 2000 status started}]
	update

	set rotated $::lichess::Priv(rotated)
	set tagsB [::scidb::game::tags]
	set whiteLabel [$::lichess::Priv(widget:white) cget -text]

	# Black replies 1... d5 -> sends d7d5
	set mBlack [::lichess::UserMove d5]
	::scidb::test::lichess::ReplyMove {ok 1}

	# White plays 2. c4 and offers a draw (wdraw 1); Black accepts
	::scidb::test::lichess::EmitGame [dict create \
		type gameState moves "d2d4 d7d5 c2c4" wtime 179000 btime 179000 status started wdraw 1]
	set drawOfferB $::lichess::Priv(drawOffer)
	::lichess::AcceptDraw
	::scidb::test::lichess::ReplyAction {ok 1}

	# Check mate result header (Black wins by mate -> 0-1)
	::scidb::test::lichess::EmitGame [dict create \
		type gameState moves "d2d4 d7d5 c2c4" wtime 179000 btime 179000 status mate winner black]
	set mateResult [lsearch -inline [::scidb::game::tags] {Result *}]
	set posB $::lichess::Priv(pos)
	::lichess::BackToLobby
	catch { ::application::pgn::release $posB }
	catch { ::game::release $posB }

	# Check draw and abort result headers on fresh games
	set results {}
	foreach {gid stateDict} {
		gDraw  {type gameState moves "e2e4 e7e5" wtime 60000 btime 60000 status draw}
		gStale {type gameState moves "e2e4 e7e5" wtime 60000 btime 60000 status stalemate}
		gAbort {type gameState moves "" wtime 60000 btime 60000 status aborted}
	} {
		::scidb::test::lichess::EmitEvent [dict create type gameStart game [dict create \
			gameId $gid color white speed rapid rated 0]]
		::scidb::test::lichess::EmitGame [dict create \
			type gameFull id $gid rated 0 speed rapid initialFen startpos \
			white {id alice name Alice} black {id bob name Bob} \
			state $stateDict]
		set pgn [::scidb::game::toPGN modified -position $::lichess::Priv(pos)]
		regexp {\[Result "([^"]+)"\]} $pgn -> resTag
		lappend results $gid $resTag
		set pos $::lichess::Priv(pos)
		::lichess::BackToLobby
		catch { ::application::pgn::release $pos }
		catch { ::game::release $pos }
	}

	list \
		$rotated \
		[expr {[lsearch -exact $tagsB {Event {Lichess casual blitz game}}] >= 0}] \
		[expr {[lsearch -exact $tagsB {White {Stockfish level 5}}] >= 0}] \
		[expr {[lsearch -exact $tagsB {Black Alice}] >= 0}] \
		[expr {[lsearch -glob $tagsB {WhiteElo *}] < 0}] \
		[expr {[lsearch -exact $tagsB {BlackElo 1650}] >= 0}] \
		[expr {[lsearch -exact $tagsB {TimeControl 180+2}] >= 0}] \
		$whiteLabel $mBlack $drawOfferB $mateResult $results
} -cleanup {
	::scidb::test::lichess::Unstub
	array set ::lichess::Options $savedOpts
} -result {1 1 1 1 1 1 1 {White: Stockfish level 5} 1 1 {Result 0-1} {gDraw 1/2-1/2 gStale 1/2-1/2 gAbort *}}

tcltest::cleanupTests
