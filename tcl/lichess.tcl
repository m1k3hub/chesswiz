# ======================================================================
# Play on Lichess (Training > Play Online (Lichess)).
# tcl/lichess-api.tcl owns transport and credentials; this file owns the
# dialogue, the main-board game and its clocks. All API callbacks are
# asynchronous, and tests replace them with local stubs.
#
#   ::lichess::open .application       sign in -> lobby -> game panel
#   ::lichess::UserMove <san>          board move entry point used by tests
#
# A pasted token is a transient entry value. It is never an option, status
# message or debug-log line; only the API's credential store retains it.
# ======================================================================

::util::source lichess

package require Tcl 8.5
package require Tk 8.5

namespace eval ::lichess {
namespace eval mc {

set Title					"Play Online (Lichess)"
set SignIn					"Sign in with Lichess"
set UseToken				"Use a personal token"
set Token					"Personal token:"
set TokenDetail				"A personal token needs the board:play scope. It is stored only in the Chesswiz credential store."
set WaitingBrowser			"Waiting for the browser…"
set SignedInAs				"Signed in as %s."
set SignedOut				"Signed out of Lichess."
set SessionExpired			"Lichess no longer accepts this sign-in. Sign in again."
set LoadingAccount			"Reading the Lichess account…"
set SignOut					"Sign out"
set Close					"Close"
set Seek					"Seek a game"
set CancelSeek				"Cancel seek"
set Seeking					"Seeking a game…"
set SeekCancelled			"Seek cancelled."
set SeekRule				"Real-time seeks must be Rapid or slower: minutes × 60 + 40 × increment must be at least 480 seconds."
set SeekTooFast				"That seek is faster than Rapid. Increase the minutes or increment so that minutes × 60 + 40 × increment is at least 480 seconds."
set PlayComputer			"Play the computer"
set ComputerDetail			"Lichess Stockfish, level 1–8. Blitz and faster games are allowed against the computer."
set ComputerWaiting			"Waiting for the computer game to start…"
set Level					"Stockfish level:"
set Minutes					"Minutes:"
set IncrementSeconds		"Increment (seconds):"
set RatedGame				"Rated game"
set Colour					"Colour:"
set Random					"random"
set White					"white"
set Black					"black"
set OpeningGame				"Opening the game…"
set EventStreamClosed		"The Lichess event stream closed."
set GameStreamClosed		"The Lichess game stream closed."
set WhiteClock				"White"
set BlackClock				"Black"
set YourMove				"Your move."
set WaitingMove				"Waiting for %s's move."
set MoveRejected			"Lichess rejected %s; the move was taken back."
set InvalidMove				"That move could not be sent to Lichess; it was taken back."
set NotYourTurn				"Wait for the opponent's move."
set NotAtEnd				"Return to the end of the game to move."
set GameOver				"Game over: %s (%s)."
set ImportFailed			"Could not put the Lichess position on the board: %s"
set Resign					"Resign"
set OfferDraw				"Offer draw"
set AcceptDraw				"Accept draw"
set DeclineDraw				"Decline draw"
set DrawOffered				"Your opponent offers a draw."
set Abort					"Abort"
set ClaimVictory			"Claim victory"
set OpponentGone			"Your opponent has left. You can claim victory."
set BackToLobby				"Back to lobby"
set NoClockTime				"\u2014"

} ;# namespace mc

# There is deliberately no token entry here. Only ordinary game defaults
# survive through the options writer; credentials belong to the API.
array set Options {
	minutes			10
	increment		0
	rated			0
	color			random
	aiLevel			3
	aiMinutes		5
	aiIncrement		3
	aiColor			random
}

variable TickInterval 250

array set Priv {
	dialog			{}
	state			offline
	username		{}
	userId			{}
	signingIn		0
	statusText		{}
	eventHandle		{}
	seekHandle		{}
	gameHandle		{}
	active			0
	busy			0
	pos				0
	gameId			{}
	gameInfo		{}
	initialFen		{}
	userSide		{}
	serverMoves		{}
	pendingMove		{}
	drawOffer		0
	opponentGone	0
	clock:w			0
	clock:b			0
	clockAt			0
	clockStm		w
	ticking			0
	tick			{}
	inputAfter		{}
	rotated			0
}

} ;# namespace lichess


# ======================================================================
# The dialog
# ======================================================================

proc ::lichess::open {parent} {
	variable Priv
	variable Options
	variable mc

	foreach number [::application::analysis::Running] {
		::application::analysis::stopEngine $number
	}

	set dlg $parent.lichess
	if {[winfo exists $dlg]} {
		raise $dlg
		return $dlg
	}
	set Priv(dialog) $dlg

	toplevel $dlg -class Scidb
	wm title $dlg $mc::Title
	wm transient $dlg [winfo toplevel $parent]
	wm withdraw $dlg
	wm protocol $dlg WM_DELETE_WINDOW [namespace code Close]
	bind $dlg <Escape> [namespace code Close]

	set top [ttk::frame [::util::place::playingBody $dlg].top]
	pack $top -fill both -expand yes -padx $::theme::padx -pady $::theme::pady

	### sign in ############################################################
	set s [ttk::frame $top.signin]
	set Priv(widget:signin) $s
	grid [ttk::button $s.signin -text $mc::SignIn -command [namespace code SignIn]] \
		-row 0 -column 0 -columnspan 2 -sticky w
	grid [ttk::label $s.tokenLabel -text $mc::Token] -row 1 -column 0 -sticky w \
		-pady [list $::theme::pady 0]
	grid [ttk::entry $s.token -width 28 -show * \
		-textvariable [namespace current]::Priv(dlg:token)] -row 1 -column 1 -sticky ew \
		-padx [list $::theme::padx 0] -pady [list $::theme::pady 0]
	grid [ttk::button $s.useToken -text $mc::UseToken -command [namespace code UseToken]] \
		-row 2 -column 1 -sticky w -padx [list $::theme::padx 0]
	grid [ttk::label $s.detail -text $mc::TokenDetail -wraplength 340 -justify left] \
		-row 3 -column 0 -columnspan 2 -sticky w -pady [list $::theme::pady 0]
	grid [ttk::button $s.signout -text $mc::SignOut -command [namespace code SignOut]] \
		-row 4 -column 0 -sticky w -pady [list $::theme::pady 0]
	grid columnconfigure $s 1 -weight 1

	### lobby ##############################################################
	set l [ttk::frame $top.lobby]
	set Priv(widget:lobby) $l
	ttk::label $l.account -anchor w -justify left
	pack $l.account -fill x
	set Priv(widget:account) $l.account

	set sf [ttk::labelframe $l.seek -text $mc::Seek]
	grid [ttk::label $sf.minutesLabel -text $mc::Minutes] -row 0 -column 0 -sticky w
	grid [ttk::spinbox $sf.minutes -from 0 -to 180 -width 4 \
		-textvariable [namespace current]::Priv(dlg:minutes)] -row 0 -column 1 -sticky w \
		-padx [list $::theme::padx 0]
	grid [ttk::label $sf.incLabel -text $mc::IncrementSeconds] -row 1 -column 0 -sticky w
	grid [ttk::spinbox $sf.increment -from 0 -to 60 -width 4 \
		-textvariable [namespace current]::Priv(dlg:increment)] -row 1 -column 1 -sticky w \
		-padx [list $::theme::padx 0]
	grid [ttk::checkbutton $sf.rated -text $mc::RatedGame \
		-variable [namespace current]::Priv(dlg:rated)] -row 2 -column 0 -columnspan 2 -sticky w
	grid [ttk::label $sf.colorLabel -text $mc::Colour] -row 3 -column 0 -sticky w
	grid [ttk::combobox $sf.color -state readonly -width 8 \
		-values [list $mc::Random $mc::White $mc::Black] \
		-textvariable [namespace current]::Priv(dlg:color)] -row 3 -column 1 -sticky w \
		-padx [list $::theme::padx 0]
	grid [ttk::label $sf.rule -text $mc::SeekRule -wraplength 340 -justify left] \
		-row 4 -column 0 -columnspan 2 -sticky w -pady [list $::theme::pady 0]
	grid [ttk::button $sf.seek -text $mc::Seek -command [namespace code Seek]] \
		-row 5 -column 0 -sticky w
	grid [ttk::button $sf.cancel -text $mc::CancelSeek -command [namespace code CancelSeek]] \
		-row 5 -column 1 -sticky w -padx [list $::theme::padx 0]
	grid columnconfigure $sf 1 -weight 1
	pack $sf -fill x -pady [list $::theme::pady 0]

	set af [ttk::labelframe $l.ai -text $mc::PlayComputer]
	grid [ttk::label $af.levelLabel -text $mc::Level] -row 0 -column 0 -sticky w
	grid [ttk::spinbox $af.level -from 1 -to 8 -width 4 \
		-textvariable [namespace current]::Priv(dlg:aiLevel)] -row 0 -column 1 -sticky w \
		-padx [list $::theme::padx 0]
	grid [ttk::label $af.minutesLabel -text $mc::Minutes] -row 1 -column 0 -sticky w
	grid [ttk::spinbox $af.minutes -from 0 -to 180 -width 4 \
		-textvariable [namespace current]::Priv(dlg:aiMinutes)] -row 1 -column 1 -sticky w \
		-padx [list $::theme::padx 0]
	grid [ttk::label $af.incLabel -text $mc::IncrementSeconds] -row 2 -column 0 -sticky w
	grid [ttk::spinbox $af.increment -from 0 -to 60 -width 4 \
		-textvariable [namespace current]::Priv(dlg:aiIncrement)] -row 2 -column 1 -sticky w \
		-padx [list $::theme::padx 0]
	grid [ttk::label $af.colorLabel -text $mc::Colour] -row 3 -column 0 -sticky w
	grid [ttk::combobox $af.color -state readonly -width 8 \
		-values [list $mc::Random $mc::White $mc::Black] \
		-textvariable [namespace current]::Priv(dlg:aiColor)] -row 3 -column 1 -sticky w \
		-padx [list $::theme::padx 0]
	grid [ttk::label $af.detail -text $mc::ComputerDetail -wraplength 340 -justify left] \
		-row 4 -column 0 -columnspan 2 -sticky w -pady [list $::theme::pady 0]
	grid [ttk::button $af.play -text $mc::PlayComputer -command [namespace code ChallengeAi]] \
		-row 5 -column 0 -columnspan 2 -sticky w
	grid columnconfigure $af 1 -weight 1
	pack $af -fill x -pady [list $::theme::pady 0]
	ttk::button $l.signout -text $mc::SignOut -command [namespace code SignOut]
	pack $l.signout -anchor w

	### game ###############################################################
	set g [ttk::frame $top.game]
	set Priv(widget:game) $g
	set clocks [ttk::frame $g.clocks]
	ttk::label $clocks.white -width 29 -anchor w
	ttk::label $clocks.whiteclock -font $::font::text(text:normal) -width 9 -anchor e
	ttk::label $clocks.black -width 29 -anchor w
	ttk::label $clocks.blackclock -font $::font::text(text:normal) -width 9 -anchor e
	grid $clocks.white -row 0 -column 0 -sticky w
	grid $clocks.whiteclock -row 0 -column 1 -sticky e
	grid $clocks.black -row 1 -column 0 -sticky w
	grid $clocks.blackclock -row 1 -column 1 -sticky e
	grid columnconfigure $clocks 0 -weight 1
	pack $clocks -fill x
	set Priv(widget:white) $clocks.white
	set Priv(widget:black) $clocks.black
	set Priv(widget:whiteclock) $clocks.whiteclock
	set Priv(widget:blackclock) $clocks.blackclock

	set buttons [ttk::frame $g.buttons]
	ttk::button $buttons.resign -text $mc::Resign -command [namespace code Resign]
	ttk::button $buttons.draw -text $mc::OfferDraw -command [namespace code OfferDraw]
	ttk::button $buttons.accept -text $mc::AcceptDraw -command [namespace code AcceptDraw]
	ttk::button $buttons.decline -text $mc::DeclineDraw -command [namespace code DeclineDraw]
	ttk::button $buttons.abort -text $mc::Abort -command [namespace code Abort]
	ttk::button $buttons.claim -text $mc::ClaimVictory -command [namespace code ClaimVictory]
	pack $buttons.resign -side left
	pack $buttons.draw -side left -padx [list $::theme::padx 0]
	pack $buttons.accept -side left -padx [list $::theme::padx 0]
	pack $buttons.decline -side left -padx [list $::theme::padx 0]
	pack $buttons.abort -side left -padx [list $::theme::padx 0]
	pack $buttons.claim -side left
	pack $buttons -anchor w -pady [list $::theme::pady]
	foreach key {resign draw accept decline abort claim} {
		set Priv(widget:$key) $buttons.$key
	}

	# The right pad keeps the status text clear of the Pin box.
	ttk::label $top.status -wraplength 330 -justify left
	pack $top.status -fill x -pady [list $::theme::pady 0] -padx [list 0 40]
	set Priv(widget:status) $top.status

	::util::place::playingButtons $dlg {ok cancel}
	set ok [::util::place::playingBody $dlg].ok
	set cancel [::util::place::playingBody $dlg].cancel
	$cancel configure -text $mc::Close -command [namespace code Close]
	set Priv(widget:ok) $ok
	set Priv(widget:cancel) $cancel
	set Priv(widget:back) $ok

	set Priv(dlg:token) {}
	foreach {key option} {minutes minutes increment increment rated rated aiLevel aiLevel \
		aiMinutes aiMinutes aiIncrement aiIncrement} {
		set Priv(dlg:$key) $Options($option)
	}
	set Priv(dlg:color) [ColourLabel $Options(color)]
	set Priv(dlg:aiColor) [ColourLabel $Options(aiColor)]

	if {[::lichess::api::signedIn?]} {
		set Priv(state) lobby
		ShowView lobby
		Status $mc::LoadingAccount
		StartEvents
		::lichess::api::account [namespace code AccountResult]
	} else {
		set Priv(state) offline
		ShowView signin
		Status {}
	}

	::util::place::besideBoard $dlg $parent
	wm deiconify $dlg
	return $dlg
}


proc ::lichess::ColourLabel {colour} {
	variable mc
	switch -- $colour {
		white { return $mc::White }
		black { return $mc::Black }
		default { return $mc::Random }
	}
}


proc ::lichess::ColourValue {label} {
	variable mc
	if {$label eq $mc::White} { return white }
	if {$label eq $mc::Black} { return black }
	return random
}


proc ::lichess::ShowView {view} {
	variable Priv
	variable mc

	if {![DialogExists]} { return }
	foreach name {signin lobby game} {
		if {[info exists Priv(widget:$name)]} { pack forget $Priv(widget:$name) }
	}
	pack $Priv(widget:$view) -fill both -expand yes
	switch -- $view {
		signin {
			$Priv(widget:ok) configure -text $mc::SignIn -command [namespace code SignIn]
			$Priv(widget:ok) state !disabled
		}
		lobby {
			$Priv(widget:ok) configure -text $mc::Seek -command [namespace code Seek]
			$Priv(widget:ok) state !disabled
			if {$Priv(username) ne ""} {
				$Priv(widget:account) configure -text [format $mc::SignedInAs $Priv(username)]
			} else {
				$Priv(widget:account) configure -text {}
			}
		}
		game {
			$Priv(widget:ok) configure -text $mc::BackToLobby -command [namespace code BackToLobby]
			UpdateGameButtons
			DrawNames
			DrawClocks
		}
	}
	Status $Priv(statusText)
}


proc ::lichess::DialogExists {} {
	variable Priv
	return [expr {[string length $Priv(dialog)] && [winfo exists $Priv(dialog)]}]
}


proc ::lichess::Status {text} {
	variable Priv
	set Priv(statusText) $text
	if {[DialogExists] && [info exists Priv(widget:status)]} {
		$Priv(widget:status) configure -text $text
	}
}


# ======================================================================
# Sign-in, account and event stream
# ======================================================================

proc ::lichess::SignIn {} {
	variable Priv
	variable mc
	if {$Priv(signingIn)} { return 0 }
	set Priv(signingIn) 1
	Status $mc::WaitingBrowser
	::lichess::api::signIn [namespace code SignedIn]
	return 1
}


proc ::lichess::UseToken {} {
	variable Priv
	if {$Priv(signingIn) || ![DialogExists]} { return 0 }
	set token [string trim $Priv(dlg:token)]
	set Priv(dlg:token) {}
	if {$token eq ""} { return 0 }
	set Priv(signingIn) 1
	# Do not log or copy the token into Options/Priv. The API validates it
	# and is the sole owner of persistent credential storage.
	::lichess::api::useToken $token [namespace code SignedIn]
	return 1
}


proc ::lichess::SignedIn {reply} {
	variable Priv
	variable mc
	set Priv(signingIn) 0
	if {[info exists Priv(dlg:token)]} { set Priv(dlg:token) {} }
	if {![dict exists $reply ok] || ![dict get $reply ok]} {
		set Priv(state) offline
		ShowView signin
		Status [expr {[dict exists $reply error] ? [dict get $reply error] : "Sign in failed."}]
		return
	}
	set Priv(username) [expr {[dict exists $reply username] ? [dict get $reply username] : "Lichess user"}]
	if {[dict exists $reply id] && [dict get $reply id] ne ""} {
		set Priv(userId) [dict get $reply id]
	} else {
		set Priv(userId) [string tolower $Priv(username)]
	}
	set Priv(state) lobby
	StartEvents
	ShowView lobby
	Status [format $mc::SignedInAs $Priv(username)]
}


# A 401 anywhere means the token was revoked or expired: back to sign-in.
# Whether it was one.
proc ::lichess::SessionExpired {reply} {
	variable mc
	if {![dict exists $reply status] || [dict get $reply status] != 401} { return 0 }
	SignOut
	Status $mc::SessionExpired
	return 1
}


proc ::lichess::AccountResult {reply} {
	variable Priv
	variable mc
	if {$Priv(state) ne "lobby"} { return }
	if {[dict exists $reply ok] && [dict get $reply ok]} {
		set Priv(username) [dict get $reply username]
		set Priv(userId) [dict get $reply id]
		ShowView lobby
		Status [format $mc::SignedInAs $Priv(username)]
	} else {
		set why [expr {[dict exists $reply error] ? [dict get $reply error] : "Account lookup failed."}]
		SignOut
		Status $why
	}
}


proc ::lichess::StartEvents {} {
	variable Priv
	if {$Priv(eventHandle) ne "" || $Priv(state) eq "offline"} { return }
	set Priv(eventHandle) [::lichess::api::streamEvents [namespace code OnEvent]]
}


proc ::lichess::OnEvent {event} {
	variable Priv
	variable mc
	if {![dict exists $event type]} { return }
	switch -- [dict get $event type] {
		gameStart {
			if {[dict exists $event game]} { OpenGame [dict get $event game] }
		}
		closed {
			set Priv(eventHandle) {}
			if {[SessionExpired $event]} { return }
			if {$Priv(state) ne "offline"} { Status $mc::EventStreamClosed }
		}
	}
}


proc ::lichess::OpenGame {game} {
	variable Priv
	variable mc
	set id [expr {[dict exists $game gameId] ? [dict get $game gameId] : \
		[dict exists $game id] ? [dict get $game id] : ""}]
	if {$id eq "" || ($Priv(active) && $id eq $Priv(gameId))} { return }
	if {$Priv(seekHandle) ne ""} {
		set handle $Priv(seekHandle)
		set Priv(seekHandle) {}
		catch { ::lichess::api::close $handle }
	}
	if {$Priv(gameHandle) ne ""} { catch { ::lichess::api::close $Priv(gameHandle) } }
	FinishBoard
	set Priv(gameId) $id
	set Priv(gameInfo) $game
	set Priv(userSide) {}
	if {[dict exists $game color]} {
		set Priv(userSide) [string index [dict get $game color] 0]
	}
	Status $mc::OpeningGame
	set Priv(gameHandle) [::lichess::api::streamGame $id [namespace code OnGame]]
}


proc ::lichess::SignOut {} {
	variable Priv
	variable mc
	ReleaseStreams
	FinishBoard
	::lichess::api::signOut
	set Priv(state) offline
	set Priv(username) {}
	set Priv(userId) {}
	set Priv(signingIn) 0
	if {[info exists Priv(dlg:token)]} { set Priv(dlg:token) {} }
	ShowView signin
	Status $mc::SignedOut
}


proc ::lichess::ReleaseStreams {} {
	variable Priv
	foreach key {seekHandle gameHandle eventHandle} {
		if {$Priv($key) ne ""} {
			set handle $Priv($key)
			set Priv($key) {}
			catch { ::lichess::api::close $handle }
		}
	}
}


proc ::lichess::Close {} {
	variable Priv
	ReleaseStreams
	FinishBoard
	if {[info exists Priv(dlg:token)]} { set Priv(dlg:token) {} }
	if {[string length $Priv(dialog)] && [winfo exists $Priv(dialog)]} { destroy $Priv(dialog) }
	set Priv(dialog) {}
}


# ======================================================================
# Lobby
# ======================================================================

proc ::lichess::Integer {value default minimum maximum} {
	if {![string is integer -strict $value]} { set value $default }
	return [expr {max($minimum, min($maximum, $value))}]
}


proc ::lichess::Seek {} {
	variable Priv
	variable Options
	variable mc
	if {$Priv(state) ne "lobby" || $Priv(seekHandle) ne ""} { return 0 }

	if {[DialogExists] && [info exists Priv(dlg:minutes)]} {
		set minutes $Priv(dlg:minutes)
		set increment $Priv(dlg:increment)
		set rated $Priv(dlg:rated)
		set colour [ColourValue $Priv(dlg:color)]
	} else {
		set minutes $Options(minutes)
		set increment $Options(increment)
		set rated $Options(rated)
		set colour $Options(color)
	}
	set minutes [Integer $minutes 10 0 180]
	set increment [Integer $increment 0 0 60]
	if {$minutes * 60 + 40 * $increment < 480} {
		Status $mc::SeekTooFast
		return 0
	}
	set rated [expr {$rated ? 1 : 0}]
	set Options(minutes) $minutes
	set Options(increment) $increment
	set Options(rated) $rated
	set Options(color) $colour
	Status $mc::Seeking
	set Priv(seekHandle) [::lichess::api::seek $minutes $increment $rated $colour \
		[namespace code SeekClosed]]
	return $Priv(seekHandle)
}


proc ::lichess::SeekClosed {reply} {
	variable Priv
	set Priv(seekHandle) {}
	if {$Priv(state) eq "lobby" && [dict exists $reply error] && [dict get $reply error] ne ""} {
		Status [dict get $reply error]
	}
}


proc ::lichess::CancelSeek {} {
	variable Priv
	variable mc
	if {$Priv(seekHandle) eq ""} { return 0 }
	set handle $Priv(seekHandle)
	set Priv(seekHandle) {}
	::lichess::api::close $handle
	Status $mc::SeekCancelled
	return 1
}


proc ::lichess::ChallengeAi {} {
	variable Priv
	variable Options
	variable mc
	if {$Priv(state) ne "lobby"} { return 0 }
	if {[DialogExists] && [info exists Priv(dlg:aiLevel)]} {
		set level $Priv(dlg:aiLevel)
		set minutes $Priv(dlg:aiMinutes)
		set increment $Priv(dlg:aiIncrement)
		set colour [ColourValue $Priv(dlg:aiColor)]
	} else {
		set level $Options(aiLevel)
		set minutes $Options(aiMinutes)
		set increment $Options(aiIncrement)
		set colour $Options(aiColor)
	}
	set level [Integer $level 3 1 8]
	set minutes [Integer $minutes 5 0 180]
	set increment [Integer $increment 3 0 60]
	set Options(aiLevel) $level
	set Options(aiMinutes) $minutes
	set Options(aiIncrement) $increment
	set Options(aiColor) $colour
	Status $mc::ComputerWaiting
	::lichess::api::challengeAi $level $minutes $increment $colour [namespace code ChallengeResult]
	return 1
}


proc ::lichess::ChallengeResult {reply} {
	variable Priv
	if {![dict exists $reply ok] || ![dict get $reply ok]} {
		Status [expr {[dict exists $reply error] ? [dict get $reply error] : "The computer challenge failed."}]
	}
}


# ======================================================================
# Game stream and board synchronisation
# ======================================================================

proc ::lichess::OnGame {event} {
	variable Priv
	variable mc
	if {![dict exists $event type]} { return }
	switch -- [dict get $event type] {
		gameFull {
			if {[dict exists $event id] && $Priv(gameId) ne "" && [dict get $event id] ne $Priv(gameId)} {
				return
			}
			if {!$Priv(active)} {
				if {[catch { StartBoard $event } err]} {
					catch { ::debuglog::log lichess "game import failed: $err" }
					FinishBoard
					Status [format $mc::ImportFailed $err]
				}
			} elseif {[dict exists $event state]} {
				SyncState [dict get $event state]
			}
		}
		gameState { if {$Priv(active)} { SyncState $event } }
		opponentGone {
			if {!$Priv(active)} { return }
			set Priv(opponentGone) [expr {[dict exists $event gone] && [dict get $event gone] ? 1 : 0}]
			UpdateGameButtons
			if {$Priv(opponentGone)} { Status $mc::OpponentGone }
		}
		closed {
			set Priv(gameHandle) {}
			if {[SessionExpired $event]} { return }
			if {$Priv(active) && $Priv(state) eq "playing"} {
				Status $mc::GameStreamClosed
				UpdateBoardInput
			}
		}
	}
}


proc ::lichess::StartBoard {full} {
	variable Priv
	variable mc

	FinishBoard
	::menu::gameNew .application
	set Priv(pos) [::scidb::game::current]
	set Priv(gameInfo) [dict merge $Priv(gameInfo) $full]
	if {[dict exists $full id]} { set Priv(gameId) [dict get $full id] }
	set Priv(initialFen) [InitialFen $full]
	if {$Priv(userSide) eq ""} {
		foreach {colour key} {w white b black} {
			if {![dict exists $full $key]} { continue }
			set player [dict get $full $key]
			foreach {field value} [list id $Priv(userId) name $Priv(username) username $Priv(username)] {
				if {$value ne "" && [dict exists $player $field] \
				 && [string equal -nocase [dict get $player $field] $value]} {
					set Priv(userSide) $colour
				}
			}
		}
	}
	if {$Priv(userSide) ni {w b}} { set Priv(userSide) w }

	set pgn [BoardPgn $Priv(gameInfo) *]
	set Priv(busy) 1
	set code [catch { ImportGame $Priv(pos) $pgn } err]
	set Priv(busy) 0
	if {$code} { return -code error $err }
	::scidb::game::go end

	# The user's side is at the bottom; FinishBoard restores the rotation.
	set Priv(rotated) 0
	if {[catch { ::application::board::rotated? } rotated] == 0
	 && $rotated != ($Priv(userSide) eq "b")} {
		RotateBoard
		set Priv(rotated) 1
	}
	::scidb::game::subscribe board $Priv(pos) [namespace current]::Update
	::scidb::db::subscribe gameClose [namespace current]::GameClosed
	::scidb::db::subscribe gameSwitch [namespace current]::GameSwitched
	set Priv(active) 1
	set Priv(state) playing
	set Priv(serverMoves) {}
	set Priv(pendingMove) {}
	set Priv(drawOffer) 0
	set Priv(opponentGone) 0
	ShowView game
	if {[dict exists $full state]} {
		SyncState [dict get $full state]
	} else {
		UpdateBoardInput
		StatusForTurn
		StartTick
	}
	after cancel $Priv(inputAfter)
	set Priv(inputAfter) [after idle [namespace code [list SettledBoardInput $Priv(pos)]]]
	return 1
}


proc ::lichess::SettledBoardInput {position} {
	variable Priv
	set Priv(inputAfter) {}
	if {$Priv(active) && $position == $Priv(pos)} { UpdateBoardInput }
}


proc ::lichess::InitialFen {full} {
	if {[dict exists $full initialFen] && [dict get $full initialFen] ne "" \
	 && [dict get $full initialFen] ne "startpos"} {
		return [dict get $full initialFen]
	}
	return "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
}


proc ::lichess::PlayerName {player} {
	foreach {key prefix} {aiLevel "Stockfish level " ai "Stockfish level "} {
		if {[dict exists $player $key] && [dict get $player $key] ne "" \
		 && [dict get $player $key] ne "null"} {
			return "$prefix[dict get $player $key]"
		}
	}
	foreach key {name username id} {
		if {[dict exists $player $key] && [dict get $player $key] ne ""} {
			return [dict get $player $key]
		}
	}
	return "?"
}


proc ::lichess::BoardPgn {info result} {
	set rated [expr {[dict exists $info rated] && [dict get $info rated] ? "rated" : "casual"}]
	set speed [expr {[dict exists $info speed] ? [dict get $info speed] : "rapid"}]
	set id [expr {[dict exists $info id] ? [dict get $info id] : \
		[dict exists $info gameId] ? [dict get $info gameId] : "?"}]
	set white [expr {[dict exists $info white] ? [PlayerName [dict get $info white]] : "?"}]
	set black [expr {[dict exists $info black] ? [PlayerName [dict get $info black]] : "?"}]
	set tags [list \
		[format {[Event "%s"]} [PgnTag "Lichess $rated $speed game"]] \
		[format {[Site "https://lichess.org/%s"]} [PgnTag $id]] \
		[format {[Date "%s"]} [clock format [clock seconds] -format {%Y.%m.%d}]] \
		{[Round "?"]} \
		[format {[White "%s"]} [PgnTag $white]] \
		[format {[Black "%s"]} [PgnTag $black]] \
	]
	foreach {key tag} {white WhiteElo black BlackElo} {
		if {[dict exists $info $key]} {
			set player [dict get $info $key]
			if {[dict exists $player rating] && [string is digit -strict [dict get $player rating]]} {
				lappend tags [format {[%s "%s"]} $tag [dict get $player rating]]
			}
		}
	}
	if {[dict exists $info clock]} {
		set clock [dict get $info clock]
		set initial [dict get $clock initial]
		set increment [dict get $clock increment]
		lappend tags [format {[TimeControl "%d+%d"]} [expr {$initial / 1000}] [expr {$increment / 1000}]]
	}
	set initialFen [InitialFen $info]
	if {[dict exists $info initialFen] && [dict get $info initialFen] ne "startpos"} {
		lappend tags {[SetUp "1"]} [format {[FEN "%s"]} [PgnTag $initialFen]]
	}
	lappend tags [format {[Result "%s"]} $result]
	return "[join $tags \n]\n\n$result\n"
}


proc ::lichess::PgnTag {value} {
	return [string map [list \\ \\\\ \" \\\"] $value]
}


proc ::lichess::ImportGame {pos pgn} {
	::scidb::game::import $pos $pgn ::lichess::ImportLog {} -encoding utf-8
}


proc ::lichess::ImportLog {_ args} { return }


proc ::lichess::ApplyMoves {moves} {
	foreach uci $moves {
		set san [uciToSan $uci]
		if {$san eq ""} { return -code error "illegal UCI move $uci" }
		::scidb::game::move $san
		::scidb::game::go 1
	}
}


proc ::lichess::Moves {state} {
	if {![dict exists $state moves]} { return {} }
	return [regexp -all -inline {\S+} [dict get $state moves]]
}


proc ::lichess::SyncState {state} {
	variable Priv
	variable mc
	if {!$Priv(active)} { return }
	set moves [Moves $state]
	set before [BoardPly]
	set count [llength $moves]
	set delta [expr {$count - $before}]
	set failed 0

	if {$delta == 1} {
		set san [uciToSan [lindex $moves end]]
		if {$san eq ""} {
			set failed 1
		} else {
			Busy on
			set code [catch { ::scidb::game::move $san; ::scidb::game::go 1 } err]
			Busy off
			if {$code || [BoardPly] != $before + 1} { set failed 1 }
		}
	} elseif {$delta != 0} {
		set failed 1
	}
	# Zero is the ordinary echo of a locally entered move. A jump, a
	# negative delta, or a failed single move all need a complete snapshot.
	if {$failed && ![Resync $state $moves]} { return }
	set Priv(serverMoves) $moves
	set Priv(pendingMove) {}
	SetClocks $state

	set Priv(drawOffer) 0
	set opponent [expr {$Priv(userSide) eq "w" ? "bdraw" : "wdraw"}]
	if {[dict exists $state $opponent] && [dict get $state $opponent]} { set Priv(drawOffer) 1 }

	set status [expr {[dict exists $state status] ? [dict get $state status] : "started"}]
	set result [ResultForState $state]
	if {$status ni {started created}} {
		EndGame $result $status
		return
	}
	UpdateGameButtons
	UpdateBoardInput
	DrawNames
	DrawClocks
	if {$Priv(drawOffer)} {
		Status $mc::DrawOffered
	} else {
		StatusForTurn
	}
	StartTick
}


proc ::lichess::Resync {state moves} {
	variable Priv
	variable mc
	if {!$Priv(active)} { return 0 }
	set pgn [BoardPgn $Priv(gameInfo) *]
	set Priv(busy) 1
	set code [catch {
		ImportGame $Priv(pos) $pgn
		ApplyMoves $moves
		::scidb::game::go end
	} err]
	set Priv(busy) 0
	if {$code} {
		catch { ::debuglog::log lichess "resync import failed: $err" }
		Status [format $mc::ImportFailed $err]
		return 0
	}
	set Priv(pendingMove) {}
	return 1
}


proc ::lichess::BoardPly {} {
	variable Priv
	if {[catch { ::scidb::game::query mainline } plies]} { return 0 }
	return [llength $plies]
}


proc ::lichess::Update {position cmd data promoted} {
	variable Priv
	variable mc
	if {!$Priv(active) || $Priv(busy) || $position != $Priv(pos)} { return }
	if {$cmd ne "move"} { return }
	if {[llength $data] && ![lindex $data end]} { return }
	if {![::scidb::game::position atEnd?] || ![::scidb::game::position isMainline?]} {
		RejectMove $mc::NotAtEnd
		return
	}

	set plies [::scidb::game::query mainline]
	if {![llength $plies]} {
		RejectMove $mc::InvalidMove
		return
	}
	set fenBefore [lindex $plies end 2]
	if {$Priv(state) ne "playing" || $Priv(pendingMove) ne "" || ![WasMyTurn $fenBefore]} {
		RejectMove $mc::NotYourTurn
		return
	}
	set fenAfter [::scidb::pos::fen]
	set uci [uciFromFens $fenBefore $fenAfter]
	if {$uci eq ""} {
		RejectMove $mc::InvalidMove
		return
	}
	set gameId $Priv(gameId)
	set ply [BoardPly]
	set Priv(pendingMove) $uci
	SettleClock
	UpdateBoardInput
	Status [format $mc::WaitingMove [OpponentName]]
	if {[catch {
		::lichess::api::move $gameId $uci [namespace code [list MoveResult $gameId $uci $ply]]
	} err]} {
		MoveResult $gameId $uci $ply [dict create ok 0 error $err]
	}
}


proc ::lichess::UserMove {san} {
	variable Priv
	variable mc
	if {!$Priv(active) || $Priv(state) ne "playing" || $Priv(pendingMove) ne "" || ![MyTurn]} {
		return 0
	}
	if {![::scidb::game::position atEnd?] || ![::scidb::game::position isMainline?]} {
		Status $mc::NotAtEnd
		return 0
	}
	set before [BoardPly]
	::move::addMove menu $san
	return [expr {[BoardPly] > $before}]
}


proc ::lichess::MoveResult {gameId uci ply reply} {
	variable Priv
	variable mc
	if {!$Priv(active) || $gameId ne $Priv(gameId) || $uci ne $Priv(pendingMove)} { return }
	if {[dict exists $reply ok] && [dict get $reply ok]} { return }
	if {[SessionExpired $reply]} { return }
	# A later stream echo has already accepted this move; an old failure
	# callback must not take back a position which has moved on.
	if {[BoardPly] != $ply} { return }
	RejectMove [format $mc::MoveRejected $uci]
}


proc ::lichess::RejectMove {why} {
	variable Priv
	Busy on
	catch { ::scidb::game::go -1; ::scidb::game::strip truncate }
	Busy off
	set Priv(pendingMove) {}
	UpdateBoardInput
	Status $why
}


proc ::lichess::MyTurn {} {
	variable Priv
	if {$Priv(userSide) ni {w b} || [catch { ::scidb::pos::fen } fen]} { return 0 }
	return [expr {[lindex $fen 1] eq $Priv(userSide)}]
}

proc ::lichess::WasMyTurn {fenBefore} {
	variable Priv
	if {$Priv(userSide) ni {w b}} { return 0 }
	return [expr {[lindex $fenBefore 1] eq $Priv(userSide)}]
}


proc ::lichess::OpponentName {} {
	variable Priv
	set key [expr {$Priv(userSide) eq "w" ? "black" : "white"}]
	if {[dict exists $Priv(gameInfo) $key]} { return [PlayerName [dict get $Priv(gameInfo) $key]] }
	return "?"
}


proc ::lichess::StatusForTurn {} {
	variable Priv
	variable mc
	if {!$Priv(active) || $Priv(state) eq "over"} { return }
	if {$Priv(pendingMove) eq "" && [MyTurn]} {
		Status $mc::YourMove
	} else {
		Status [format $mc::WaitingMove [OpponentName]]
	}
}


proc ::lichess::BoardInput {on} {
	if {$on eq "on"} { ::move::enable } else { ::move::disable }
}


proc ::lichess::UpdateBoardInput {} {
	variable Priv
	if {$Priv(active) && $Priv(state) eq "playing"
	 && ($Priv(pendingMove) ne "" || $Priv(gameHandle) eq "" || ![MyTurn])} {
		BoardInput off
	} else {
		BoardInput on
	}
}


proc ::lichess::Busy {on} {
	variable Priv
	set Priv(busy) [expr {$on eq "on" ? 1 : 0}]
}


proc ::lichess::GameClosed {position} {
	variable Priv
	if {$Priv(active) && $position == $Priv(pos)} { LeaveBoard }
}


proc ::lichess::GameSwitched {oldPos newPos} {
	variable Priv
	if {$Priv(active) && $newPos != $Priv(pos)} { LeaveBoard }
}


proc ::lichess::LeaveBoard {} {
	variable Priv
	if {$Priv(active) && $Priv(state) eq "playing"} {
		catch { ::lichess::api::resign $Priv(gameId) [namespace code ActionResult] }
	}
	FinishBoard
	if {$Priv(state) ne "offline"} {
		set Priv(state) lobby
		ShowView lobby
	}
}


proc ::lichess::FinishBoard {} {
	variable Priv
	if {$Priv(active)} {
		catch { ::scidb::game::unsubscribe board $Priv(pos) [namespace current]::Update }
		catch { ::scidb::db::unsubscribe gameClose [namespace current]::GameClosed }
		catch { ::scidb::db::unsubscribe gameSwitch [namespace current]::GameSwitched }
	}
	after cancel $Priv(tick)
	after cancel $Priv(inputAfter)
	set Priv(tick) {}
	set Priv(inputAfter) {}
	set Priv(active) 0
	set Priv(ticking) 0
	set Priv(pendingMove) {}
	if {$Priv(rotated)} {
		RotateBoard
		set Priv(rotated) 0
	}
	BoardInput on
}


proc ::lichess::RotateBoard {} {
	catch { ::application::board::Rotate $::application::board::Vars(widget:frame) }
}


# ======================================================================
# Game commands and result
# ======================================================================

proc ::lichess::Resign {} {
	variable Priv
	if {$Priv(active) && $Priv(state) eq "playing"} {
		::lichess::api::resign $Priv(gameId) [namespace code ActionResult]
	}
}


proc ::lichess::OfferDraw {} {
	variable Priv
	if {$Priv(active) && $Priv(state) eq "playing"} {
		::lichess::api::draw $Priv(gameId) yes [namespace code ActionResult]
	}
}


proc ::lichess::AcceptDraw {} {
	variable Priv
	if {$Priv(active) && $Priv(state) eq "playing" && $Priv(drawOffer)} {
		::lichess::api::draw $Priv(gameId) yes [namespace code ActionResult]
	}
}


proc ::lichess::DeclineDraw {} {
	variable Priv
	if {$Priv(active) && $Priv(state) eq "playing" && $Priv(drawOffer)} {
		::lichess::api::draw $Priv(gameId) no [namespace code ActionResult]
	}
}


proc ::lichess::Abort {} {
	variable Priv
	if {$Priv(active) && $Priv(state) eq "playing"} {
		::lichess::api::abort $Priv(gameId) [namespace code ActionResult]
	}
}


proc ::lichess::ClaimVictory {} {
	variable Priv
	if {$Priv(active) && $Priv(state) eq "playing" && $Priv(opponentGone)} {
		::lichess::api::claimVictory $Priv(gameId) [namespace code ActionResult]
	}
}


proc ::lichess::ActionResult {reply} {
	variable Priv
	if {[SessionExpired $reply]} { return }
	if {![dict exists $reply ok] || ![dict get $reply ok]} {
		Status [expr {[dict exists $reply error] ? [dict get $reply error] : "Lichess rejected the request."}]
	}
}


proc ::lichess::ResultForState {state} {
	set status [expr {[dict exists $state status] ? [dict get $state status] : "started"}]
	if {$status in {started created aborted noStart}} { return "*" }
	if {$status in {draw stalemate}} { return "1/2-1/2" }
	if {[dict exists $state winner]} {
		switch -- [dict get $state winner] {
			white { return "1-0" }
			black { return "0-1" }
		}
	}
	if {$status in {timeout outoftime variantEnd}} { return "1/2-1/2" }
	return "*"
}


proc ::lichess::EndGame {result reason} {
	variable Priv
	variable mc
	if {!$Priv(active) || $Priv(state) eq "over"} { return }
	set Priv(state) over
	set Priv(ticking) 0
	after cancel $Priv(tick)
	set Priv(tick) {}
	if {[catch { StoreResult $result } err]} {
		catch { ::debuglog::log lichess "StoreResult $result failed: $err" }
	}
	UpdateBoardInput
	UpdateGameButtons
	DrawClocks
	Status [format $mc::GameOver $result $reason]
}


proc ::lichess::StoreResult {result} {
	variable Priv
	set pos $Priv(pos)
	set pgn [::scidb::game::toPGN modified -position $pos]
	if {![regsub -- {\[Result "[^"]*"\]} $pgn [format {[Result "%s"]} $result] pgn]} {
		set gap [string first "\n\n" $pgn]
		if {$gap < 0} { set gap [string length $pgn]; append pgn "\n" }
		set pgn [string replace $pgn $gap $gap "\n[format {[Result "%s"]} $result]"]
	}
	if {![regsub -- {(\*|1-0|0-1|1/2-1/2)\s*$} $pgn $result pgn]} {
		set pgn "[string trimright $pgn]\n$result\n"
	}
	set Priv(busy) 1
	ImportGame $pos $pgn
	set Priv(busy) 0
	::scidb::game::go end
}


proc ::lichess::UpdateGameButtons {} {
	variable Priv
	if {![DialogExists] || ![info exists Priv(widget:resign)]} { return }
	set playing [expr {$Priv(active) && $Priv(state) eq "playing"}]
	foreach key {resign draw abort} {
		$Priv(widget:$key) state [expr {$playing ? "!disabled" : "disabled"}]
	}
	foreach key {accept decline} {
		$Priv(widget:$key) state [expr {$playing && $Priv(drawOffer) ? "!disabled" : "disabled"}]
	}
	$Priv(widget:claim) state [expr {$playing && $Priv(opponentGone) ? "!disabled" : "disabled"}]
	$Priv(widget:back) state [expr {$Priv(active) && $Priv(state) eq "over" ? "!disabled" : "disabled"}]
}


proc ::lichess::BackToLobby {} {
	variable Priv
	if {$Priv(state) eq "offline"} { ShowView signin; return }
	if {$Priv(active) && $Priv(state) ne "over"} { return 0 }
	if {$Priv(gameHandle) ne ""} {
		set handle $Priv(gameHandle)
		set Priv(gameHandle) {}
		catch { ::lichess::api::close $handle }
	}
	FinishBoard
	set Priv(state) lobby
	ShowView lobby
	return 1
}


# ======================================================================
# Clocks: server snapshots plus local countdown for the side to move
# ======================================================================

proc ::lichess::SetClocks {state} {
	variable Priv
	if {[dict exists $state wtime]} { set Priv(clock:w) [dict get $state wtime] }
	if {[dict exists $state btime]} { set Priv(clock:b) [dict get $state btime] }
	if {![catch { ::scidb::pos::fen } fen]} { set Priv(clockStm) [lindex $fen 1] }
	set status [expr {[dict exists $state status] ? [dict get $state status] : "started"}]
	set Priv(ticking) [expr {$Priv(active) && $status in {started created} && $Priv(state) ne "over"}]
	set Priv(clockAt) [clock milliseconds]
}


proc ::lichess::SettleClock {} {
	variable Priv
	set now [clock milliseconds]
	if {$Priv(clockStm) in {w b}} {
		set Priv(clock:$Priv(clockStm)) [Remaining $Priv(clockStm) $now]
	}
	if {![catch { ::scidb::pos::fen } fen]} { set Priv(clockStm) [lindex $fen 1] }
	set Priv(clockAt) $now
}


proc ::lichess::Remaining {colour now} {
	variable Priv
	set ms $Priv(clock:$colour)
	if {$Priv(ticking) && $Priv(clockStm) eq $colour} {
		set ms [expr {$ms - ($now - $Priv(clockAt))}]
	}
	return $ms
}


proc ::lichess::StartTick {} {
	variable Priv
	variable TickInterval
	after cancel $Priv(tick)
	if {$Priv(active) && $Priv(state) ne "over"} {
		set Priv(tick) [after $TickInterval [namespace code Tick]]
	}
}


proc ::lichess::Tick {} {
	variable Priv
	variable TickInterval
	set Priv(tick) {}
	if {!$Priv(active) || $Priv(state) eq "over"} { return }
	DrawClocks
	set Priv(tick) [after $TickInterval [namespace code Tick]]
}


proc ::lichess::DrawNames {} {
	variable Priv
	variable mc
	if {![DialogExists] || ![info exists Priv(widget:white)]} { return }
	foreach {key widget label} {white white WhiteClock black black BlackClock} {
		if {![dict exists $Priv(gameInfo) $key]} { continue }
		set player [dict get $Priv(gameInfo) $key]
		set name [PlayerName $player]
		if {[dict exists $player rating] && [dict get $player rating] ne ""} {
			append name " ([dict get $player rating])"
		}
		$Priv(widget:$widget) configure -text "[set mc::$label]: $name"
	}
}


proc ::lichess::DrawClocks {} {
	variable Priv
	if {![DialogExists] || ![info exists Priv(widget:whiteclock)]} { return }
	set now [clock milliseconds]
	foreach colour {w b} {
		set widget [expr {$colour eq "w" ? "whiteclock" : "blackclock"}]
		$Priv(widget:$widget) configure -text [FormatClock [expr {max(0, [Remaining $colour $now])}]]
		set active [expr {$Priv(ticking) && $Priv(clockStm) eq $colour}]
		$Priv(widget:$widget) configure -font $::font::text([expr {$active ? "text:bold" : "text:normal"}])
	}
}


proc ::lichess::FormatClock {ms} {
	set sign [expr {$ms < 0 ? "-" : ""}]
	set ms [expr {abs($ms)}]
	set tenths [expr {($ms % 1000) / 100}]
	set s [expr {$ms / 1000}]
	set h [expr {$s / 3600}]
	set m [expr {($s % 3600) / 60}]
	set s [expr {$s % 60}]
	if {$h} { return [format "%s%d:%02d:%02d" $sign $h $m $s] }
	if {$ms < 10000} { return [format "%s%d:%02d.%d" $sign $m $s $tenths] }
	return [format "%s%d:%02d" $sign $m $s]
}


proc ::lichess::WriteOptions {chan} {
	::options::writeItem $chan [namespace current]::Options
}

::options::hookWriter ::lichess::WriteOptions


# ======================================================================
# Pure UCI helpers
# ======================================================================

# Difference of two FEN placements. The mover is the side to move in the
# first FEN. King castling is recognised before the rook's two changed
# squares can make the source/destination pair ambiguous. En passant's
# removed opposing pawn does not participate in the mover's pair.
proc ::lichess::uciFromFens {fenBefore fenAfter} {
	if {[catch {
		set before [Placement $fenBefore]
		set after [Placement $fenAfter]
	} err]} { return "" }
	set white [expr {[lindex $fenBefore 1] eq "w"}]
	set kingFrom [expr {$white ? "e1" : "e8"}]
	set king [expr {$white ? "K" : "k"}]
	if {[dict exists $before $kingFrom] && [dict get $before $kingFrom] eq $king} {
		foreach kingTo [expr {$white ? {g1 c1} : {g8 c8}}] {
			if {[dict exists $after $kingTo] && [dict get $after $kingTo] eq $king} {
				return "$kingFrom$kingTo"
			}
		}
	}

	set froms {}
	set tos {}
	foreach {square piece} $before {
		set isOwn [expr {$white ? [string match {[A-Z]} $piece] : [string match {[a-z]} $piece]}]
		if {!$isOwn} { continue }
		set new [expr {[dict exists $after $square] ? [dict get $after $square] : ""}]
		if {$new ne $piece} { lappend froms $square }
	}
	foreach {square piece} $after {
		set isOwn [expr {$white ? [string match {[A-Z]} $piece] : [string match {[a-z]} $piece]}]
		if {!$isOwn} { continue }
		set old [expr {[dict exists $before $square] ? [dict get $before $square] : ""}]
		if {$old ne $piece} { lappend tos $square }
	}

	set answer {}
	set count 0
	foreach from $froms {
		set old [dict get $before $from]
		foreach to $tos {
			set new [dict get $after $to]
			set promotion {}
			if {$new eq $old} {
				# ordinary move, capture, or en passant
			} elseif {$old in {P p} && $new ni {P p} &&
				($white ? [string match {[A-Z]} $new] : [string match {[a-z]} $new])} {
				set promotion [string tolower $new]
			} else {
				continue
			}
			set answer "$from$to$promotion"
			incr count
		}
	}
	return [expr {$count == 1 ? $answer : ""}]
}


proc ::lichess::Placement {fen} {
	set board [dict create]
	set rank 8
	foreach row [split [lindex $fen 0] /] {
		if {$rank < 1} { return -code error "invalid FEN placement" }
		set file 0
		foreach ch [split $row {}] {
			if {[string is digit -strict $ch]} {
				incr file $ch
			} else {
				if {$file >= 8 || $ch ni {p n b r q k P N B R Q K}} {
					return -code error "invalid FEN placement"
				}
				dict set board [format "%c%d" [expr {97 + $file}] $rank] $ch
				incr file
			}
		}
		if {$file != 8} { return -code error "invalid FEN placement" }
		incr rank -1
	}
	if {$rank != 0} { return -code error "invalid FEN placement" }
	return $board
}


proc ::lichess::uciToSan {uci} {
	return [::playengine::uciToSan $uci]
}

# vi:set ts=3 sw=3:
