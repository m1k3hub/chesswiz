# ======================================================================
# Scidb App Test — Guess the Move (tcl/guess-move.tcl)
# ======================================================================
# A game is built with ::move::addMove, the board goes back to the start
# and a round is driven through the same ::move::addMove entry point a
# board move uses (the hook hands the SAN to ::guessmove::guessed).
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::guess {}

# A new game with the Ruy Lopez moves, positioned at the start.
# The current game is reset rather than a new one opened: there are only
# nine game slots, and earlier test files may have used them up.
proc ::scidb::test::guess::newGame {} {
	::scidb::game::clear {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}
	update
	foreach san {e4 e5 Nf3 Nc6 Bb5 a6} { ::move::addMove menu $san }
	::scidb::game::go -1 start
	update
}

# The mainline SAN list of the board's game, read by stepping through it;
# the board is left at the start again.
proc ::scidb::test::guess::line {} {
	::scidb::game::go -1 start
	set moves {}
	while {![::scidb::game::position atEnd?]} {
		lappend moves [::scidb::game::next move -ascii]
		::scidb::game::go -1 +1
	}
	::scidb::game::go -1 start
	return $moves
}

proc ::scidb::test::guess::cleanup {} {
	catch { ::guessmove::stop }
	catch { destroy $::guessmove::Priv(dialog) }
	set ::guessmove::active 0
}

tcltest::test guess-right {the right SAN scores one point and advances two plies} -setup {
	::scidb::test::guess::newGame
} -body {
	::guessmove::start white
	set r1 [list $::guessmove::active [::scidb::game::query stm] [::scidb::game::query length]]
	::move::addMove menu e4
	list $r1 $::guessmove::Priv(score) $::guessmove::Priv(total) $::guessmove::Priv(last) \
		[::scidb::game::query stm] [::scidb::game::next move -ascii] \
		[$::guessmove::Priv(dialog).top.score cget -text]
} -cleanup {
	::scidb::test::guess::cleanup
} -result {{1 white 6} 1 1 Correct white Nf3 {Score: 1 of 1}}

tcltest::test guess-wrong {a wrong guess scores zero, names the game move and still advances} -setup {
	::scidb::test::guess::newGame
} -body {
	::guessmove::start auto
	::move::addMove menu d4
	list $::guessmove::Priv(score) $::guessmove::Priv(total) $::guessmove::Priv(last) \
		[::scidb::game::next move -ascii] [::scidb::game::query stm]
} -cleanup {
	::scidb::test::guess::cleanup
} -result {0 1 {Not the game move (e4)} Nf3 white}

tcltest::test guess-black {guessing the black moves steps over white's first} -setup {
	::scidb::test::guess::newGame
} -body {
	::guessmove::start black
	set first [list [::scidb::game::query stm] [::scidb::game::next move -ascii]]
	::move::addMove menu e5
	list $first $::guessmove::Priv(score) [::scidb::game::query stm] [::scidb::game::next move -ascii]
} -cleanup {
	::scidb::test::guess::cleanup
} -result {{black e5} 1 black Nc6}

tcltest::test guess-summary {the end of the game shows the summary and releases the board} -setup {
	::scidb::test::guess::newGame
} -body {
	::guessmove::start white
	::move::addMove menu e4
	::move::addMove menu d4
	::move::addMove menu Bb5
	list $::guessmove::active $::guessmove::Priv(summary) \
		[$::guessmove::Priv(dialog).top.last cget -text]
} -cleanup {
	::scidb::test::guess::cleanup
} -result {0 {2 of 3 moves guessed (67%)} {2 of 3 moves guessed (67%)}}

tcltest::test guess-stop {Stop summarises the guesses made so far} -setup {
	::scidb::test::guess::newGame
} -body {
	::guessmove::start white
	::move::addMove menu e4
	::guessmove::stop
	list $::guessmove::active $::guessmove::Priv(summary)
} -cleanup {
	::scidb::test::guess::cleanup
} -result {0 {1 of 1 moves guessed (100%)}}

tcltest::test guess-show-move {Show Move counts as a miss} -setup {
	::scidb::test::guess::newGame
} -body {
	::guessmove::start white
	::guessmove::showMove
	list $::guessmove::Priv(score) $::guessmove::Priv(total) $::guessmove::Priv(last) \
		[::scidb::game::next move -ascii]
} -cleanup {
	::scidb::test::guess::cleanup
} -result {0 1 {The move was e4} Nf3}

tcltest::test guess-hint {Hint marks the from-square of the game move and clears it again} -setup {
	::scidb::test::guess::newGame
	set ::guessmove::HintTime 50
} -body {
	::guessmove::start white
	::guessmove::hint
	set during $::guessmove::Priv(hintSquare)
	after 150 {set ::scidb::test::guess::w 1}; vwait ::scidb::test::guess::w
	list $during $::guessmove::Priv(hintSquare)
} -cleanup {
	::scidb::test::guess::cleanup
	set ::guessmove::HintTime 2000
} -result {12 -1}

tcltest::test guess-game-unchanged {the game has the same moves after training} -setup {
	::scidb::test::guess::newGame
} -body {
	set before [::scidb::test::guess::line]
	::guessmove::start white
	::move::addMove menu e4
	::move::addMove menu d4
	::move::addMove menu Qh5
	::guessmove::stop
	list $before [::scidb::test::guess::line]
} -cleanup {
	::scidb::test::guess::cleanup
} -result {{e4 e5 Nf3 Nc6 Bb5 a6} {e4 e5 Nf3 Nc6 Bb5 a6}}

tcltest::test guess-inactive {without a round moves still change the game} -setup {
	::menu::gameNew .application
	update
} -body {
	::move::addMove menu d4
	list $::guessmove::active [::scidb::test::guess::line]
} -cleanup {
	::scidb::test::guess::cleanup
} -result {0 d4}

tcltest::test guess-menus {the board context menu and the Extras menu start a round} -body {
	list [string match *::guessmove::start* [info body ::application::board::PopupMenu]] \
		[string match *::guessmove::start* [info body ::menu::build]] \
		$::guessmove::mc::GuessTheMove
} -result {1 1 {Guess the Move...}}

# ----------------------------------------------------------------------
# System One (Jev) and engine-first tests (stubbed ::ai::engine::evaluate
# and ::ai::systemone::evaluateAsync)
# ----------------------------------------------------------------------

namespace eval ::scidb::test::guess {
	variable Calls {}
	variable StubReply {}
	variable EngineCalls {}
	variable EngineReplies {}
}

proc ::scidb::test::guess::stubStart {reply} {
	variable Calls {}
	variable StubReply $reply
	if {[llength [info commands ::scidb::test::guess::realEvaluateAsync]] == 0} {
		rename ::ai::systemone::evaluateAsync ::scidb::test::guess::realEvaluateAsync
	}
	proc ::ai::systemone::evaluateAsync {state questions script} {
		lappend ::scidb::test::guess::Calls [list $state $questions]
		set r $::scidb::test::guess::StubReply
		if {[llength $r] > 1 && [lindex $r 0] eq "queue"} {
			set next [lindex $r 1]
			if {[llength $r] > 2} {
				set ::scidb::test::guess::StubReply [concat queue [lrange $r 2 end]]
			} else {
				set ::scidb::test::guess::StubReply [list queue $next]
			}
			set r $next
		}
		after 0 [list {*}$script $r]
	}
	::ai::systemone::configure -backend typesafe -apiKey stub-key
}

proc ::scidb::test::guess::stubStop {} {
	if {[llength [info commands ::scidb::test::guess::realEvaluateAsync]]} {
		catch { rename ::ai::systemone::evaluateAsync {} }
		rename ::scidb::test::guess::realEvaluateAsync ::ai::systemone::evaluateAsync
	}
	::ai::systemone::configure -backend off
}

proc ::scidb::test::guess::stubEngineStart {replies} {
	variable EngineCalls {}
	variable EngineReplies $replies
	if {[llength [info commands ::scidb::test::guess::realEngineEvaluate]] == 0} {
		rename ::ai::engine::evaluate ::scidb::test::guess::realEngineEvaluate
	}
	proc ::ai::engine::evaluate {fen args} {
		lappend ::scidb::test::guess::EngineCalls [list $fen $args]
		set r $::scidb::test::guess::EngineReplies
		if {$r eq "error"} {
			error "no UCI engine"
		}
		set item [lindex $r 0]
		if {[llength $r] > 1} {
			set ::scidb::test::guess::EngineReplies [lrange $r 1 end]
		}
		return $item
	}
}

proc ::scidb::test::guess::stubEngineStop {} {
	if {[llength [info commands ::scidb::test::guess::realEngineEvaluate]]} {
		catch { rename ::ai::engine::evaluate {} }
		rename ::scidb::test::guess::realEngineEvaluate ::ai::engine::evaluate
	}
}

proc ::scidb::test::guess::flushAsync {} {
	after 30 { set ::scidb::test::guess::done 1 }
	vwait ::scidb::test::guess::done
	update
}

tcltest::test guess-jev-rules {deterministic rules classify hint themes, engine verdicts, feedback themes and round reviews} -body {
	set start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
	set castlePos "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4"
	set matePos "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4"
	set endPos "8/4k3/8/4P3/4K3/8/8/8 w - - 0 1"
	list \
		[::guessmove::hintRule $start e4] \
		[::guessmove::hintRule $start Nf3] \
		[::guessmove::hintRule $castlePos O-O] \
		[::guessmove::hintRule $matePos Qxf7#] \
		[::guessmove::hintRule $endPos Kd5] \
		[::guessmove::engineVerdict 1.5] \
		[::guessmove::engineVerdict 8.0] \
		[::guessmove::engineVerdict 22.0] \
		[::guessmove::feedbackRule $start d4 e4] \
		[::guessmove::feedbackRule $start h3 Nf3] \
		[::guessmove::feedbackRule $castlePos h3 O-O] \
		[::guessmove::feedbackRule $matePos Nc3 Qxf7#] \
		[::guessmove::feedbackRule $castlePos Bxf7+ O-O] \
		[::guessmove::reviewRule {score 3 total 3 hints 0 reveals 0 misses {material 0 tactics 0}}] \
		[::guessmove::reviewRule {score 2 total 3 hints 0 reveals 0 misses {material 0 tactics 0}}] \
		[::guessmove::reviewRule {score 2 total 4 hints 0 reveals 1 misses {material 0 tactics 0}}] \
		[::guessmove::reviewRule {score 0 total 3 hints 2 reveals 1 misses {material 1 tactics 1}}]
} -result {structure development king_safety tactics endgame close_alternative slightly_worse worse structure development king_safety tactics material master_like sharp steady needs_study}

tcltest::test guess-jev-hint-classifier {Hint asks guess_hint via evaluateAsync, keeps the board square highlight and shows the coaching cue} -setup {
	::scidb::test::guess::newGame
	::scidb::test::guess::stubStart [list ok 1 answers [dict create \
		guess_hint [dict create type choice choice structure confidence 0.88]]]
} -body {
	::guessmove::start white
	::guessmove::hint
	set sq $::guessmove::Priv(hintSquare)
	::scidb::test::guess::flushAsync
	lassign [lindex $::scidb::test::guess::Calls 0] state questions
	list $sq \
		$::guessmove::Priv(hintKind) \
		$::guessmove::Priv(hintSource) \
		$::guessmove::Priv(note) \
		[$::guessmove::Priv(dialog).top.note cget -text] \
		[dict exists $questions guess_hint] \
		[string match "*fen=*" $state] \
		[expr {[string first "e4" $state] < 0}]
} -cleanup {
	::scidb::test::guess::stubStop
	::scidb::test::guess::cleanup
} -result {12 structure classifier {Hint: fight for the centre, open files, or better pawn structure.} {Hint: fight for the centre, open files, or better pawn structure.} 1 1 1}

tcltest::test guess-jev-hint-fallback {Hint falls back to hintRule and leaves the note blank on low confidence or error} -setup {
	::scidb::test::guess::newGame
	::scidb::test::guess::stubStart [list ok 1 answers [dict create \
		guess_hint [dict create type choice choice endgame confidence 0.25]]]
} -body {
	::guessmove::start white
	::guessmove::hint
	::scidb::test::guess::flushAsync
	set low [list $::guessmove::Priv(hintKind) $::guessmove::Priv(hintSource) $::guessmove::Priv(note)]
	::scidb::test::guess::stubStop
	::move::addMove menu e4
	::guessmove::hint
	::scidb::test::guess::flushAsync
	set off [list $::guessmove::Priv(hintKind) $::guessmove::Priv(hintSource) $::guessmove::Priv(note)]
	list $low $off
} -cleanup {
	::scidb::test::guess::stubStop
	::scidb::test::guess::cleanup
} -result {{structure rules {}} {development rules {}}}

tcltest::test guess-jev-feedback-engine-first {evaluateFeedback computes win-probability loss, deterministic verdict, and gates tactics/material themes by engine and C++ facts} -body {
	set start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
	set castlePos "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4"

	# 1. loss <= 3 -> close_alternative; tactics and material excluded
	::scidb::test::guess::stubEngineStart [list \
		[dict create kind cp value -25 cpl -25 bestMove d7d5 pv {d7d5}] \
		[dict create kind cp value -30 cpl -30 bestMove e7e5 pv {e7e5}]]
	set efClose [::guessmove::evaluateFeedback $start d4 e4]

	# 2. 3 < loss < 15 -> slightly_worse with quiet 1-move PV and no C++ material loss
	::scidb::test::guess::stubEngineStart [list \
		[dict create kind cp value 40 cpl 40 bestMove e7e5 pv {e7e5}] \
		[dict create kind cp value -30 cpl -30 bestMove e7e5 pv {e7e5}]]
	set efSlightly [::guessmove::evaluateFeedback $start h3 Nf3]

	# 3. loss >= 15 -> worse with C++ material loss and tactical PV
	::scidb::test::guess::stubEngineStart [list \
		[dict create kind cp value 300 cpl 300 bestMove e8f7 pv {e8f7 f3e5}] \
		[dict create kind cp value -40 cpl -40 bestMove d7d6 pv {d7d6 d2d3}]]
	set efWorse [::guessmove::evaluateFeedback $castlePos Bxf7+ O-O]

	list \
		[dict get $efClose verdict] [dict get $efClose themes] \
		[dict get $efSlightly verdict] [dict get $efSlightly themes] \
		[dict get $efWorse verdict] [dict get $efWorse themes] \
		[::guessmove::feedbackRule $castlePos Bxf7+ O-O $efWorse]
} -cleanup {
	::scidb::test::guess::stubEngineStop
} -result {close_alternative {development king_safety structure} slightly_worse {king_safety development structure} worse {tactics material king_safety development structure} material}

tcltest::test guess-jev-feedback-classifier {a wrong guess evaluates both resulting positions with ::ai::engine::evaluate, locks the engine verdict, and lets Jev choose only a consistent theme} -setup {
	::scidb::test::guess::newGame
	::scidb::test::guess::stubEngineStart [list \
		[dict create kind cp value -25 cpl -25 bestMove d7d5 pv {d7d5}] \
		[dict create kind cp value -30 cpl -30 bestMove e7e5 pv {e7e5}] \
		[dict create kind cp value 300 cpl 300 bestMove f6e4 pv {f6e4 d2d4}] \
		[dict create kind cp value -30 cpl -30 bestMove b8c6 pv {b8c6 f1b5}] \
		[dict create kind cp value -20 cpl -20 bestMove a7a6 pv {a7a6}] \
		[dict create kind cp value -25 cpl -25 bestMove a7a6 pv {a7a6}]]
	::scidb::test::guess::stubStart [list queue \
		[list ok 1 answers [dict create \
			guess_feedback [dict create type choice choice structure confidence 0.91]]] \
		[list ok 1 answers [dict create \
			guess_feedback [dict create type choice choice tactics confidence 0.89]]] \
		[list ok 1 answers [dict create \
			guess_feedback [dict create type choice choice tactics confidence 0.95]]]]
} -body {
	::guessmove::start white

	# Move 1: d4 vs e4 -> engine says close_alternative (loss <= 3), Jev words it as structure
	::move::addMove menu d4
	::scidb::test::guess::flushAsync
	lassign [lindex $::scidb::test::guess::Calls 0] state1 questions1
	set rClose [list \
		$::guessmove::Priv(score) \
		$::guessmove::Priv(verdict) \
		$::guessmove::Priv(feedback) \
		$::guessmove::Priv(feedbackSource) \
		$::guessmove::Priv(note) \
		[dict keys [dict get $questions1 guess_feedback criteria]] \
		[string match "*engine: verdict=close_alternative*" $state1]]

	# Move 2: h3 vs Nf3 -> engine says worse (loss >= 15), Jev words it as tactics
	::move::addMove menu h3
	::scidb::test::guess::flushAsync
	lassign [lindex $::scidb::test::guess::Calls 1] state2 questions2
	set rWorse [list \
		$::guessmove::Priv(verdict) \
		$::guessmove::Priv(feedback) \
		$::guessmove::Priv(feedbackSource) \
		$::guessmove::Priv(note) \
		[dict keys [dict get $questions2 guess_feedback criteria]] \
		[string match "*engine: verdict=worse*" $state2]]

	# Move 3: Bc4 vs Bb5 -> engine says close_alternative, Jev tries to claim tactics (rejected by firewall)
	::move::addMove menu Bc4
	::scidb::test::guess::flushAsync
	set rFirewall [list \
		$::guessmove::Priv(verdict) \
		$::guessmove::Priv(feedback) \
		$::guessmove::Priv(feedbackSource) \
		[llength $::scidb::test::guess::EngineCalls]]

	list $rClose $rWorse $rFirewall
} -cleanup {
	::scidb::test::guess::stubStop
	::scidb::test::guess::stubEngineStop
	::scidb::test::guess::cleanup
} -result {{0 close_alternative structure classifier {d4 is about as good as e4 (a close positional alternative).} {development king_safety structure} 1} {worse tactics classifier {h3 is worse than Nf3 and misses a tactical blow.} {tactics material king_safety development structure} 1} {close_alternative structure rules 6}}

tcltest::test guess-jev-feedback-fallback {a wrong guess falls back when the classifier errors or when no engine is available} -setup {
	::scidb::test::guess::newGame
	::scidb::test::guess::stubEngineStart [list \
		[dict create kind cp value 40 cpl 40 bestMove e7e5 pv {e7e5}] \
		[dict create kind cp value -30 cpl -30 bestMove e7e5 pv {e7e5}]]
	::scidb::test::guess::stubStart [list ok 0 error "unreachable"]
} -body {
	::guessmove::start white
	::move::addMove menu d4
	::scidb::test::guess::flushAsync
	set withEngine [list \
		$::guessmove::Priv(score) \
		$::guessmove::Priv(total) \
		$::guessmove::Priv(last) \
		$::guessmove::Priv(verdict) \
		$::guessmove::Priv(feedback) \
		$::guessmove::Priv(feedbackSource) \
		$::guessmove::Priv(note)]

	# Now simulate no engine available: skips Jev and falls back to feedbackRule
	set ::scidb::test::guess::Calls {}
	::scidb::test::guess::stubEngineStart error
	::move::addMove menu h3
	::scidb::test::guess::flushAsync
	set noEngine [list \
		$::guessmove::Priv(verdict) \
		$::guessmove::Priv(feedback) \
		$::guessmove::Priv(feedbackSource) \
		$::guessmove::Priv(note) \
		[llength $::scidb::test::guess::Calls]]

	list $withEngine $noEngine
} -cleanup {
	::scidb::test::guess::stubStop
	::scidb::test::guess::stubEngineStop
	::scidb::test::guess::cleanup
} -result {{0 1 {Not the game move (e4)} slightly_worse structure rules {}} {{} development rules {} 0}}

tcltest::test guess-jev-review-classifier {the end of a round asks guess_review (score) and shows the assessment note} -setup {
	::scidb::test::guess::newGame
	::scidb::test::guess::stubStart [list ok 1 answers [dict create \
		guess_review [dict create type score score 0.72 confidence 0.85]]]
} -body {
	::guessmove::start white
	::move::addMove menu e4
	::move::addMove menu Nf3
	::guessmove::stop
	::scidb::test::guess::flushAsync
	lassign [lindex $::scidb::test::guess::Calls end] state questions
	list $::guessmove::Priv(summary) \
		$::guessmove::Priv(review) \
		$::guessmove::Priv(reviewSource) \
		$::guessmove::Priv(note) \
		[$::guessmove::Priv(dialog).top.last cget -text] \
		[$::guessmove::Priv(dialog).top.note cget -text] \
		[dict get $questions guess_review type] \
		[string match "*score=2 total=2*" $state]
} -cleanup {
	::scidb::test::guess::stubStop
	::scidb::test::guess::cleanup
} -result {{2 of 2 moves guessed (100%)} sharp classifier {Assessment: sharp round -- found most of the game's critical moves.} {2 of 2 moves guessed (100%)} {Assessment: sharp round -- found most of the game's critical moves.} score 1}

tcltest::test guess-jev-review-fallback {the round review falls back to reviewRule when confidence is below threshold} -setup {
	::scidb::test::guess::newGame
	::scidb::test::guess::stubStart [list ok 1 answers [dict create \
		guess_review [dict create type score score 0.10 confidence 0.30]]]
} -body {
	::guessmove::start white
	::move::addMove menu e4
	::move::addMove menu Nf3
	::guessmove::stop
	::scidb::test::guess::flushAsync
	list $::guessmove::Priv(summary) \
		$::guessmove::Priv(review) \
		$::guessmove::Priv(reviewSource) \
		$::guessmove::Priv(note)
} -cleanup {
	::scidb::test::guess::stubStop
	::scidb::test::guess::cleanup
} -result {{2 of 2 moves guessed (100%)} master_like rules {}}

tcltest::testConstraint typesafeLive [expr {
	[info exists ::env(TYPESAFE_API_KEY)] && [string length $::env(TYPESAFE_API_KEY)] > 0
}]

tcltest::test guess-jev-live {live TypeSafe check for guess_hint when TYPESAFE_API_KEY is set} -constraints typesafeLive -setup {
	::ai::systemone::configure -backend typesafe
} -body {
	set fen "r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4"
	set ::scidb::test::guess::liveDecision {}
	::guessmove::decideHint $fen O-O {set ::scidb::test::guess::liveDecision}
	set timer [after 15000 {set ::scidb::test::guess::liveDecision {ok 0}}]
	vwait ::scidb::test::guess::liveDecision
	after cancel $timer
	set d $::scidb::test::guess::liveDecision
	expr {[dict get $d ok] && [dict get $d label] in [dict keys $::guessmove::HintCriteria]}
} -cleanup {
	::ai::systemone::configure -backend off
} -result 1

tcltest::cleanupTests
