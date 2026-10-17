# ======================================================================
# Guess the Move -- replay the game on the board and guess each move of
# one side; Chesswiz scores the guesses.
#
# The board's context menu ("Guess the Move...") or the Extras menu
# starts a round on the game currently on the board, from the current
# position. While a round is active a small training window shows the
# score, the verdict of the last guess and the buttons Hint (flashes the
# from-square of the game move for two seconds), Show Move (counts as a
# miss) and Stop. The notation keeps the moves already played visible;
# the following ones stay hidden because the round's own stepping is the
# only way the position advances. At the end of the game or after Stop
# the window shows the final score.
#
# Moves played on the board never reach the game while a round runs:
# ::move::addMove passes them to ::guessmove::guessed instead (the hook
# checks $::guessmove::active). A right guess scores one point; either
# way the game is stepped over the real move and over the opponent's
# reply, so it is the user's turn again.
#
#   ::guessmove::start ?side?    side is white|black|auto (side to move)
#   ::guessmove::stop
#
# tests/test_app_guess_move.tcl drives a round with stubbed guesses.
# ======================================================================

::util::source guess-move

namespace eval ::guessmove {
namespace eval mc {

set Title			"Guess the Move"
set GuessTheMove	"Guess the Move..."
set SideGuessing	"You are guessing the moves of %s."
set White			"White"
set Black			"Black"
set Score			"Score: %d of %d"
set Correct			"Correct"
set NotTheGameMove	"Not the game move (%s)"
set MoveWas			"The move was %s"
set Summary			"%d of %d moves guessed (%d%%)"
set Hint			"Hint"
set ShowMove		"Show Move"
set Stop			"Stop"
set Close			"Close"
set NoMoves			"Load a game and step back from its end before starting Guess the Move."

} ;# namespace mc

variable active 0
variable HintTime 2000

array set Priv {
	side			white
	score			0
	total			0
	last			{}
	summary			{}
	dialog			{}
	hint			{}
	hintSquare		-1
}

} ;# namespace guessmove


# Start a round on the board's game from the current position; <side> is
# white, black or auto (the side to move). Returns whether the round
# started.
proc ::guessmove::start {{side auto}} {
	variable Priv
	variable active
	variable mc

	if {$active} { stop }
	if {[::application::pgn::empty?] || [::scidb::game::position atEnd?]} {
		::dialog::info -parent .application -message $mc::NoMoves
		return 0
	}
	switch -- $side {
		white	{ set side white }
		black	{ set side black }
		auto	{ set side [::scidb::game::query stm] }
		default	{ error "usage: ::guessmove::start ?white|black|auto?" }
	}

	array set Priv [list \
		side		$side \
		score		0 \
		total		0 \
		last		{} \
		summary		{} \
		hint		{} \
		hintSquare	-1 \
	]
	set active 1
	::application::switchTab board
	BuildWindow .application
	Advance
	return 1
}


# End the round; the window stays up with the final score until Close.
proc ::guessmove::stop {} {
	variable Priv
	variable active

	if {$active} {
		Finish
	} elseif {[winfo exists $Priv(dialog)]} {
		destroy $Priv(dialog)
	}
}


# The ::move::addMove hook: the played move is a guess on the game move of
# the user's side; the game itself is not changed. The round's stepping
# always leaves the position on the user's turn (or at the end of the
# game), so anything played while another side is to move is ignored.
proc ::guessmove::guessed {san} {
	variable Priv
	variable active
	variable mc

	if {!$active} { return "" }
	if {[::scidb::game::query stm] ne $Priv(side)} { return "" }
	set move [GameMove]
	if {$move eq ""} { Finish; return "" }
	ClearHint
	incr Priv(total)
	if {$san eq $move} {
		incr Priv(score)
		set Priv(last) $mc::Correct
	} else {
		set Priv(last) [format $mc::NotTheGameMove $move]
	}
	::application::board::goto +1
	Advance
	return ""
}


# Flash the from-square of the game move for HintTime milliseconds.
proc ::guessmove::hint {} {
	variable Priv
	variable active
	variable HintTime

	if {!$active} { return }
	set move [GameMove]
	if {$move eq ""} { return }
	set square [fromSquare $move]
	if {$square < 0} { return }
	ClearHint
	::board::diagram::hilite $::application::board::board $square suggested
	set Priv(hintSquare) $square
	set Priv(hint) [after $HintTime [namespace code ClearHint]]
}


# Reveal the game move; it counts as a miss.
proc ::guessmove::showMove {} {
	variable Priv
	variable active
	variable mc

	if {!$active} { return }
	set move [GameMove]
	if {$move eq ""} { return }
	ClearHint
	incr Priv(total)
	set Priv(last) [format $mc::MoveWas $move]
	::application::board::goto +1
	Advance
}


# The from-square (0..63) of the legal move whose SAN is <san>; -1 if the
# SAN cannot be found (an unusual promotion, for instance).
proc ::guessmove::fromSquare {san} {
	for {set from 0} {$from < 64} {incr from} {
		for {set to 0} {$to < 64} {incr to} {
			if {$from == $to} { continue }
			if {![::scidb::pos::legal? $from $to no]} { continue }
			set s [::scidb::pos::san $from $to]
			if {$s eq $san} { return $from }
			# promotions: san tried the queen, match the other pieces too
			if {[string first = $s] >= 0} {
				foreach p {r b n} {
					if {[::scidb::pos::san $from $to $p] eq $san} { return $from }
				}
			}
		}
	}
	return -1
}


# ----------------------------------------------------------------------
# Internals.
# ----------------------------------------------------------------------

# The SAN of the next move on the current line; "" at the end of it.
proc ::guessmove::GameMove {} {
	if {[::scidb::game::position atEnd?]} { return "" }
	return [::scidb::game::next move -ascii]
}


# Step over the opponent's moves until the user is to move again; at the
# end of the game the round is finished.
proc ::guessmove::Advance {} {
	variable Priv

	while {	![::scidb::game::position atEnd?]
		&& [::scidb::game::query stm] ne $Priv(side)} {
		::application::board::goto +1
	}
	if {[::scidb::game::position atEnd?]} { Finish } else { Refresh }
}


# End of the game or Stop: lock the score and show the summary.
proc ::guessmove::Finish {} {
	variable Priv
	variable active
	variable mc

	set active 0
	ClearHint
	set pct [expr {$Priv(total) ? int(round(100.0 * $Priv(score) / $Priv(total))) : 0}]
	set Priv(summary) [format $mc::Summary $Priv(score) $Priv(total) $pct]

	set dlg $Priv(dialog)
	if {![winfo exists $dlg]} { return }
	$dlg.top.score configure -text [ScoreText]
	$dlg.top.last configure -text $Priv(summary)
	$dlg.top.buttons.hint configure -state disabled
	$dlg.top.buttons.show configure -state disabled
	$dlg.top.buttons.stop configure \
		-text $mc::Close \
		-command [list destroy $dlg] \
		;
}


proc ::guessmove::Refresh {} {
	variable Priv

	set dlg $Priv(dialog)
	if {![winfo exists $dlg]} { return }
	$dlg.top.score configure -text [ScoreText]
	$dlg.top.last configure -text $Priv(last)
}


proc ::guessmove::ScoreText {} {
	variable Priv
	variable mc

	return [format $mc::Score $Priv(score) $Priv(total)]
}


proc ::guessmove::ClearHint {} {
	variable Priv

	after cancel $Priv(hint)
	set Priv(hint) {}
	if {$Priv(hintSquare) != -1} {
		catch { ::board::diagram::hilite $::application::board::board $Priv(hintSquare) off }
		set Priv(hintSquare) -1
	}
}


proc ::guessmove::BuildWindow {parent} {
	variable Priv
	variable mc

	set dlg $parent.__guessmove__
	if {[winfo exists $dlg]} { destroy $dlg }
	toplevel $dlg -class Scidb
	wm title $dlg $mc::Title
	wm transient $dlg [winfo toplevel $parent]
	wm withdraw $dlg
	wm protocol $dlg WM_DELETE_WINDOW [namespace code stop]
	bind $dlg <Escape> [namespace code stop]

	set top [ttk::frame $dlg.top]
	pack $top -fill both -expand yes -padx $::theme::padx -pady $::theme::pady

	set side $mc::White
	if {$Priv(side) eq "black"} { set side $mc::Black }
	ttk::label $top.side -text [format $mc::SideGuessing $side]
	ttk::label $top.score -text [ScoreText]
	ttk::label $top.last -wraplength 320 -justify left

	set buttons [ttk::frame $top.buttons]
	ttk::button $buttons.hint -text $mc::Hint -command [namespace code hint]
	ttk::button $buttons.show -text $mc::ShowMove -command [namespace code showMove]
	ttk::button $buttons.stop -text $mc::Stop -command [namespace code stop]
	pack $buttons.hint $buttons.show $buttons.stop -side left -padx [list 0 $::theme::padx]

	pack $top.side -anchor w
	pack $top.score -anchor w -pady [list $::theme::pady 0]
	pack $top.last -anchor w -pady [list $::theme::pady 0]
	pack $buttons -anchor e -pady [list $::theme::pady 0]

	set Priv(dialog) $dlg
	::util::place $dlg -parent $parent -position center
	wm deiconify $dlg
	return $dlg
}

# vi:set ts=3 sw=3:
