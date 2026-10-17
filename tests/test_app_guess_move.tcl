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
proc ::scidb::test::guess::newGame {} {
	::menu::gameNew .application
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

tcltest::cleanupTests
