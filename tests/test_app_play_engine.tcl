# ======================================================================
# Scidb App Test — play a training game against an engine
# (tcl/play-engine.tcl)
# ======================================================================
# No engine process is started: the tests stub ::playengine::RequestMove
# (the move-request seam) with a queue of UCI replies, answered through
# ::playengine::GotBestMove — the same entry the pipe reader uses. The
# clock ledger procs take their "now" as an argument, so clock arithmetic
# is tested without waiting.
# ======================================================================

package require tcltest 2.5

namespace eval ::scidb::test::pe {}


# A UCI engine entry in the configured list, and RequestMove replaced by
# a queue reader: each engine turn pops one UCI move; an empty queue
# leaves the engine "thinking" (for the out-of-turn tests).
proc ::scidb::test::pe::stub {replies} {
	variable engines

	catch { rename ::scidb::test::pe::realRequest {} }
	set engines $::engine::Engines
	set ::engine::Engines [list [dict merge $::engine::EmptyEngine [list \
		Name			StubEngine \
		Command		/bin/true \
		Protocol		{UCI} \
		Features:UCI	{limitStrength {1320 3190} skillLevel {0 20}} \
	]]]
	rename ::playengine::RequestMove ::scidb::test::pe::realRequest
	proc ::playengine::RequestMove {} {
		set replies $::scidb::test::pe::replies
		if {![llength $replies]} { return }
		set ::scidb::test::pe::replies [lrange $replies 1 end]
		::playengine::GotBestMove [lindex $replies 0]
	}
	set ::scidb::test::pe::replies $replies
}


proc ::scidb::test::pe::unstub {} {
	variable engines

	set pos $::playengine::Priv(pos)
	catch { ::playengine::Finish }
	catch { rename ::playengine::RequestMove {} }
	catch { rename ::scidb::test::pe::realRequest ::playengine::RequestMove }
	if {[info exists engines]} { set ::engine::Engines $engines }
	# free the session's game slot, or the many games of this file run
	# into the app's slot limit (game:max is 9)
	catch { ::application::pgn::release $pos }
	catch { ::game::release $pos }
}


# The session game's PGN (headers and movetext as they would be saved).
proc ::scidb::test::pe::pgn {} {
	return [::scidb::game::toPGN modified -position [::scidb::game::current]]
}


# ----------------------------------------------------------------------
# Pure helpers
# ----------------------------------------------------------------------

tcltest::test playengine-goline {the go command, with a clock and with movetime} -body {
	list \
		[::playengine::goLine 60000 30000 2000 ""] \
		[::playengine::goLine "" "" "" 1000]
} -result {{go wtime 60000 btime 30000 winc 2000 binc 2000} {go movetime 1000}}

tcltest::test playengine-formatclock {m:ss, h:mm:ss, tenths below 10 s, negatives} -body {
	list \
		[::playengine::FormatClock 600000] \
		[::playengine::FormatClock 59500] \
		[::playengine::FormatClock 9500] \
		[::playengine::FormatClock 3723000] \
		[::playengine::FormatClock -1500]
} -result {10:00 0:59 0:09.5 1:02:03 -0:01.5}

tcltest::test playengine-infoscore {score parsing of info lines} -body {
	list \
		[::playengine::infoScore {info depth 12 seldepth 18 score cp 34 nodes 1000 pv e2e4}] \
		[::playengine::infoScore {info depth 10 score mate -3 nodes 500}] \
		[::playengine::infoScore {info depth 10 nodes 500}] \
		[::playengine::infoScore {bestmove e2e4}]
} -result {{cp 34} {mate -3} {} {}}

tcltest::test playengine-drawaccept {a flat position after move 30 is accepted} -body {
	list \
		[::playengine::drawAccept 59 0 {}] \
		[::playengine::drawAccept 61 30 {}] \
		[::playengine::drawAccept 61 -50 {}] \
		[::playengine::drawAccept 61 51 {}] \
		[::playengine::drawAccept 61 {} 0] \
		[::playengine::drawAccept 61 {} 2] \
		[::playengine::drawAccept 61 10 3]
} -result {0 1 1 0 1 0 0}

tcltest::test playengine-incheck {attack detection on bare FENs} -body {
	list \
		[::playengine::inCheck {4k3/8/8/8/8/8/4R3/4K3 b - - 0 1}] \
		[::playengine::inCheck {7k/5Q2/6K1/8/8/8/8/8 b - - 0 1}] \
		[::playengine::inCheck {8/k7/1P6/8/8/8/8/K7 b - - 0 1}] \
		[::playengine::inCheck {8/8/8/8/1p6/K7/8/8 w - - 0 1}] \
		[::playengine::inCheck {8/8/5k2/3N4/8/8/8/4K3 b - - 0 1}] \
		[::playengine::inCheck {4r3/4b3/8/8/8/8/8/4K3 w - - 0 1}] \
		[::playengine::inCheck {4r3/8/8/8/8/8/8/4K3 w - - 0 1}] \
		[::playengine::inCheck {7k/6Q1/6K1/8/8/8/8/8 b - - 0 1}]
} -result {1 0 1 1 1 0 1 1}

tcltest::test playengine-material {insufficient mating material} -body {
	list \
		[::playengine::insufficientMaterial {8/8/8/8/8/8/8/K6k w - - 0 1}] \
		[::playengine::insufficientMaterial {8/8/8/8/8/8/8/KB5k w - - 0 1}] \
		[::playengine::insufficientMaterial {8/8/8/8/8/8/8/KN5k w - - 0 1}] \
		[::playengine::insufficientMaterial {8/8/8/8/2b5/8/8/KB5k w - - 0 1}] \
		[::playengine::insufficientMaterial {8/8/8/8/3b4/8/8/KB5k w - - 0 1}] \
		[::playengine::insufficientMaterial {8/8/8/8/8/8/8/KB4nk w - - 0 1}] \
		[::playengine::insufficientMaterial {8/8/8/8/8/8/P7/K6k w - - 0 1}]
} -result {1 1 1 1 0 0 0}

tcltest::test playengine-fiftymoves {half-move clock at 100} -body {
	list \
		[::playengine::fiftyMoves {8/8/8/8/8/8/8/K6k w - - 99 50}] \
		[::playengine::fiftyMoves {8/8/8/8/8/8/8/K6k w - - 100 50}]
} -result {0 1}

tcltest::test playengine-clock {the ledger: elapsed charged, increment granted} -body {
	array set ::playengine::Priv {noclock 0 increment 2 clock:w 60000 clock:b 60000 color:user w color:engine b}
	unset -nocomplain ::playengine::Priv(side:user) ::playengine::Priv(side:engine)
	::playengine::StartSegment user 100000
	set running [::playengine::Remaining w 101500]
	set settled [::playengine::SettleClock user 103000]
	::playengine::StartSegment engine 200000
	set erunning [::playengine::Remaining b 202500]
	list $running $settled $erunning $::playengine::Priv(clock:w) $::playengine::Priv(clock:b)
} -cleanup {
	unset -nocomplain ::playengine::Priv(side:user) ::playengine::Priv(side:engine)
} -result {58500 59000 57500 59000 60000}

# ----------------------------------------------------------------------
# A game against the stub engine
# ----------------------------------------------------------------------

tcltest::test playengine-game {engine replies are played; headers name the players} -setup {
	::scidb::test::pe::stub {e7e5 g8f6}
} -body {
	::playengine::StartGame {-engine StubEngine -color white -minutes 10 -increment 2}
	set r1 [::playengine::UserMove e4]
	set r2 [::playengine::UserMove Nf3]
	set pgn [::scidb::test::pe::pgn]
	list \
		$r1 $r2 \
		[::scidb::game::query length] \
		[string match {*e4 e5*} $pgn] \
		[string match {*Nf3 Nf6*} $pgn] \
		[expr {[string first {[White "You"]} $pgn] >= 0}] \
		[expr {[string first {[Black "StubEngine"]} $pgn] >= 0}] \
		[expr {[string first {[Event "Training game"]} $pgn] >= 0}] \
		[expr {[string first {[Result "*"]} $pgn] >= 0}] \
		$::playengine::Priv(phase)
} -cleanup {
	::scidb::test::pe::unstub
} -result {1 1 4 1 1 1 1 1 1 user}


tcltest::test playengine-engine-white {the engine opens when the user is black} -setup {
	::scidb::test::pe::stub {d2d4}
} -body {
	::playengine::StartGame {-engine StubEngine -color black -minutes 0 -movetime 1000}
	set pgn [::scidb::test::pe::pgn]
	list \
		[::scidb::game::query length] \
		[string match {*d4*} $pgn] \
		[expr {[string first {[White "StubEngine"]} $pgn] >= 0}] \
		[expr {[string first {[Black "You"]} $pgn] >= 0}] \
		$::playengine::Priv(phase) \
		$::playengine::Priv(noclock)
} -cleanup {
	::scidb::test::pe::unstub
} -result {1 1 1 1 user 1}


tcltest::test playengine-not-your-turn {user moves are refused while the engine is to move} -setup {
	::scidb::test::pe::stub {}
} -body {
	::playengine::StartGame {-engine StubEngine -color white -minutes 10 -increment 2}
	::playengine::UserMove e4
	# the stub stays silent: the engine is "thinking", the user is off turn
	set refused [::playengine::UserMove d5]
	# a move dragged onto the board anyway is rolled back by the subscription
	::move::addMove menu d5
	list $refused [::scidb::game::query length] $::playengine::Priv(phase)
} -cleanup {
	::scidb::test::pe::unstub
} -result {0 1 engine}


tcltest::test playengine-takeback {two plies go; a single ply makes the engine move again} -setup {
	::scidb::test::pe::stub {e7e5 d2d4 e2e4}
} -body {
	::playengine::StartGame {-engine StubEngine -color white -minutes 10 -increment 2}
	::playengine::UserMove e4
	# 1. e4 e5 is on the board; the takeback removes both plies
	::playengine::Takeback
	set pliesAfterPair [::scidb::game::query length]
	set stmAfterPair [::scidb::pos::stm]
	# user black: the engine's single opening ply is taken back and replaced
	::playengine::StartGame {-engine StubEngine -color black -minutes 0 -movetime 1000}
	set opened [::scidb::game::query length]
	::playengine::Takeback
	set pgn [::scidb::test::pe::pgn]
	list $pliesAfterPair $stmAfterPair $opened \
		[::scidb::game::query length] \
		[string match {*e4*} $pgn] \
		[string match {*d4*} $pgn] \
		$::playengine::Priv(phase)
} -cleanup {
	::scidb::test::pe::unstub
} -result {0 w 1 1 1 0 user}


tcltest::test playengine-mate {a mating move ends the game with the result} -setup {
	::scidb::test::pe::stub {}
} -body {
	::playengine::StartGame {-engine StubEngine -color white -minutes 10 -increment 2}
	::scidb::pos::setup {6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1}
	set ok [::playengine::UserMove Ra8+]
	set pgn [::scidb::test::pe::pgn]
	list $ok $::playengine::Priv(phase) \
		[expr {[string first {[Result "1-0"]} $pgn] >= 0}] \
		[expr {[string first {[Result "*"]} $pgn] >= 0}]
} -cleanup {
	::scidb::test::pe::unstub
} -result {1 over 1 0}


tcltest::test playengine-stalemate {a stalemate move is a draw, not a win} -setup {
	::scidb::test::pe::stub {}
} -body {
	::playengine::StartGame {-engine StubEngine -color white -minutes 10 -increment 2}
	::scidb::pos::setup {k7/8/8/8/8/8/1Q6/K7 w - - 0 1}
	set ok [::playengine::UserMove Qb6]
	set pgn [::scidb::test::pe::pgn]
	list $ok $::playengine::Priv(phase) \
		[expr {[string first {[Result "1/2-1/2"]} $pgn] >= 0}]
} -cleanup {
	::scidb::test::pe::unstub
} -result {1 over 1}


tcltest::test playengine-repetition {the third repetition is a draw} -setup {
	::scidb::test::pe::stub {g8f6 f6g8 g8f6 f6g8}
} -body {
	::playengine::StartGame {-engine StubEngine -color white -minutes 10 -increment 2}
	::playengine::UserMove Nf3
	::playengine::UserMove Ng1
	::playengine::UserMove Nf3
	::playengine::UserMove Ng1
	# 4...Ng8 repeats the initial position for the third time
	set pgn [::scidb::test::pe::pgn]
	list [::scidb::game::query length] $::playengine::Priv(phase) \
		[expr {[string first {[Result "1/2-1/2"]} $pgn] >= 0}]
} -cleanup {
	::scidb::test::pe::unstub
} -result {8 over 1}


tcltest::test playengine-offer-draw {declined when the engine is better, accepted when flat} -setup {
	::scidb::test::pe::stub {e7e5}
	set drawMinPly $::playengine::DrawMinPly
	set ::playengine::DrawMinPly 2
} -body {
	::playengine::StartGame {-engine StubEngine -color white -minutes 10 -increment 2}
	::playengine::UserMove e4
	set ::playengine::Priv(eval:cp) 300
	::playengine::OfferDraw
	set declined $::playengine::Priv(phase)
	set ::playengine::Priv(eval:cp) 20
	::playengine::OfferDraw
	set pgn [::scidb::test::pe::pgn]
	list $declined $::playengine::Priv(phase) \
		[expr {[string first {[Result "1/2-1/2"]} $pgn] >= 0}]
} -cleanup {
	set ::playengine::DrawMinPly $drawMinPly
	::scidb::test::pe::unstub
} -result {user over 1}


tcltest::test playengine-resign {resignation ends the game} -setup {
	::scidb::test::pe::stub {}
} -body {
	::playengine::StartGame {-engine StubEngine -color white -minutes 10 -increment 2}
	::playengine::Resign
	set pgn [::scidb::test::pe::pgn]
	list $::playengine::Priv(phase) \
		[expr {[string first {[Result "0-1"]} $pgn] >= 0}]
} -cleanup {
	::scidb::test::pe::unstub
} -result {over 1}


tcltest::test playengine-dialog {the setup dialog lists engines; Start turns it into the game panel} -setup {
	::scidb::test::pe::stub {}
} -body {
	set dlg [::playengine::open .application]
	update
	set engines [$dlg.top.setup.engine.engine cget -values]
	set strength [$dlg.top.setup.strength.row.label cget -text]
	$dlg.ok invoke
	update
	set status [$dlg.top.play.status cget -text]
	set panel [expr {[winfo manager $dlg.top.play] eq "pack"}]
	::playengine::Close
	list $engines [string match {*Elo*} $strength] $panel $status \
		$::playengine::Priv(active) [winfo exists $dlg]
} -cleanup {
	::scidb::test::pe::unstub
} -result {StubEngine 1 1 {Your move.} 0 0}


tcltest::test playengine-flag {a side out of time loses on the ticker} -setup {
	::scidb::test::pe::stub {}
} -body {
	::playengine::StartGame {-engine StubEngine -color white -minutes 1 -increment 0}
	set ::playengine::Priv(clock:w) 60
	after 600 {set ::scidb::test::pe::flagged 1}
	vwait ::scidb::test::pe::flagged
	set pgn [::scidb::test::pe::pgn]
	list $::playengine::Priv(phase) \
		[expr {[string first {[Result "0-1"]} $pgn] >= 0}]
} -cleanup {
	::scidb::test::pe::unstub
} -result {over 1}


# Inside namespace ::playengine a bare "open" is ::playengine::open {parent}
# (the dialog), so the engine pipe must use the global ::open. A real
# engine is never started here, so check the call itself.
tcltest::test playengine-pipe-open {Connect opens the engine pipe with the global open} -body {
	regexp {\[::open "\|} [info body ::playengine::Connect]
} -result 1


tcltest::cleanupTests
