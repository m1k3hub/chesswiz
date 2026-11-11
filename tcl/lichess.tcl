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
set SignInExplain			"Play on Lichess with your own Lichess account.\n\nSigning in opens lichess.org in your web browser, once. Log in there and allow Chesswiz to play games for you. Chesswiz never sees your Lichess password.\n\nAfter that, every game is played here in Chesswiz. The sign-in stays saved on this computer (%s) until you sign out. Chesswiz has no server of its own: it talks only to lichess.org."
set SavedKeychain			"in the system keychain"
set SavedFile				"in a file only your user account can read"
set TokenDetail				"Advanced: instead of signing in, paste a personal token created on lichess.org with the permission \"Play games with the board API\". It is saved the same way."
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
set TakebackOffered		"Your opponent asks to take back the last move."
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
set Variant					"Variant:"
set CorrespondenceDays		"Correspondence days:"
set BotGroup				"Bot API & analysis tools"
set BotMode					"Use Bot API mode"
set BotUpgrade				"Upgrade to Bot account…"
set BotUpgradeWarning		"Upgrading this Lichess account to a Bot account is permanent and irreversible. Only accounts that have played 0 games can be upgraded. Continue?"
set BotUpgraded				"Account upgraded to a Lichess Bot account."
set CloudEval				"Cloud eval"
set CloudEvalNone			"No cloud evaluation for this position."
set AnalyseOnLichess		"Analyse on Lichess"
set AnalyseOpened			"Opened Lichess analysis: %s"
set AnalyseNoGame			"There is no game to analyse."

} ;# namespace mc

variable Variants {
	standard chess960 crazyhouse antichess atomic
	horde kingOfTheHill racingKings threeCheck fromPosition
}

# There is deliberately no token entry here. Only ordinary game defaults
# survive through the options writer; credentials belong to the API.
array set Options {
	minutes			10
	increment		0
	rated			0
	color			random
	variant			standard
	days			{}
	botMode			0
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
	gameGen			0
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
	takebackOffer	0
	opponentGone	0
	botMode			0
	cloudEvalText	{}
	exportedPgn		{}
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
	variable Variants
	variable mc

	foreach number [::application::analysis::Running] {
		::application::analysis::stopEngine $number
	}

	# The lobby is a tab of the Chesswiz Online window.
	set dlg [::online::window::tab lichess Lichess]
	::online::window::select lichess
	if {[info exists Priv(widget:signin)] && [winfo exists $Priv(widget:signin)]} {
		return $dlg
	}
	set Priv(dialog) $dlg

	set top [ttk::frame $dlg.top]
	pack $top -fill both -expand yes

	### sign in ############################################################
	set s [ttk::frame $top.signin]
	set Priv(widget:signin) $s
	set saved [expr {[::lichess::api::OsStore] ? $mc::SavedKeychain : $mc::SavedFile}]
	grid [ttk::label $s.explain -text [format $mc::SignInExplain $saved] -wraplength 380 -justify left] \
		-row 0 -column 0 -columnspan 2 -sticky w -pady [list 0 $::theme::pady]
	grid [ttk::label $s.tokenLabel -text $mc::Token] -row 2 -column 0 -sticky w \
		-pady [list $::theme::pady 0]
	grid [ttk::entry $s.token -width 28 -show * \
		-textvariable [namespace current]::Priv(dlg:token)] -row 2 -column 1 -sticky ew \
		-padx [list $::theme::padx 0] -pady [list $::theme::pady 0]
	grid [ttk::button $s.useToken -text $mc::UseToken -command [namespace code UseToken]] \
		-row 3 -column 1 -sticky w -padx [list $::theme::padx 0]
	grid [ttk::label $s.detail -text $mc::TokenDetail -wraplength 340 -justify left] \
		-row 4 -column 0 -columnspan 2 -sticky w -pady [list $::theme::pady 0]
	grid [ttk::button $s.signout -text $mc::SignOut -command [namespace code SignOut]] \
		-row 5 -column 0 -sticky w -pady [list $::theme::pady 0]
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
	grid [ttk::label $sf.variantLabel -text $mc::Variant] -row 4 -column 0 -sticky w
	grid [ttk::combobox $sf.variant -state readonly -width 14 \
		-values $Variants \
		-textvariable [namespace current]::Priv(dlg:variant)] -row 4 -column 1 -sticky w \
		-padx [list $::theme::padx 0]
	grid [ttk::label $sf.daysLabel -text $mc::CorrespondenceDays] -row 5 -column 0 -sticky w
	grid [ttk::combobox $sf.days -width 6 \
		-values {{} 1 2 3 5 7 10 14} \
		-textvariable [namespace current]::Priv(dlg:days)] -row 5 -column 1 -sticky w \
		-padx [list $::theme::padx 0]
	grid [ttk::label $sf.rule -text $mc::SeekRule -wraplength 340 -justify left] \
		-row 6 -column 0 -columnspan 2 -sticky w -pady [list $::theme::pady 0]
	grid [ttk::button $sf.seek -text $mc::Seek -command [namespace code Seek]] \
		-row 7 -column 0 -sticky w
	grid [ttk::button $sf.cancel -text $mc::CancelSeek -command [namespace code CancelSeek]] \
		-row 7 -column 1 -sticky w -padx [list $::theme::padx 0]
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

	set bf [ttk::labelframe $l.bot -text $mc::BotGroup]
	grid [ttk::checkbutton $bf.mode -text $mc::BotMode \
		-variable [namespace current]::Priv(botMode) \
		-command [namespace code ToggleBotMode]] -row 0 -column 0 -sticky w
	grid [ttk::button $bf.upgrade -text $mc::BotUpgrade \
		-command [namespace code UpgradeToBot]] -row 0 -column 1 -sticky w \
		-padx [list $::theme::padx 0]
	grid [ttk::button $bf.cloudEval -text $mc::CloudEval \
		-command [namespace code RequestCloudEval]] -row 1 -column 0 -sticky w \
		-pady [list $::theme::pady 0]
	grid [ttk::button $bf.analyseLichess -text $mc::AnalyseOnLichess \
		-command [namespace code AnalyseOnLichess]] -row 1 -column 1 -sticky w \
		-padx [list $::theme::padx 0] -pady [list $::theme::pady 0]
	grid [ttk::label $bf.evalText -anchor w -justify left -wraplength 360 \
		-textvariable [namespace current]::Priv(cloudEvalText)] \
		-row 2 -column 0 -columnspan 2 -sticky ew -pady [list $::theme::pady 0]
	grid columnconfigure $bf 1 -weight 1
	pack $bf -fill x -pady [list $::theme::pady 0]

	set tabsBar [ttk::frame $l.tabsBar]
	ttk::button $tabsBar.social -text "Lichess players" \
		-command {::lichess::social::open .application}
	ttk::button $tabsBar.tv -text "Lichess TV" \
		-command {::lichess::tv::open .application}
	ttk::button $tabsBar.events -text "Lichess tournaments" \
		-command {::lichess::events::open .application}
	ttk::button $tabsBar.puzzles -text "Lichess puzzles" \
		-command {::lichess::puzzles::open .application}
	pack $tabsBar.social $tabsBar.tv $tabsBar.events $tabsBar.puzzles \
		-side left -padx [list 0 $::theme::padx]
	pack $tabsBar -fill x -pady [list $::theme::pady 0]

	ttk::button $l.signout -text $mc::SignOut -command [namespace code SignOut]
	pack $l.signout -anchor w

	set buttons [ttk::frame $dlg.buttons]
	ttk::button $buttons.ok
	ttk::button $buttons.cancel -text $mc::Close -command [namespace code Close]
	pack $buttons.ok $buttons.cancel -side left -padx [list 0 $::theme::padx]
	pack $buttons -side bottom -anchor w -pady [list $::theme::pady 0]
	ttk::label $dlg.status -wraplength 600 -justify left
	pack $dlg.status -side bottom -fill x -pady [list $::theme::pady 0]
	set Priv(widget:status) $dlg.status
	set ok $buttons.ok
	set cancel $buttons.cancel
	set Priv(widget:ok) $ok
	set Priv(widget:cancel) $cancel
	set Priv(widget:back) $ok

	set Priv(dlg:token) {}
	foreach {key option} {minutes minutes increment increment rated rated \
		variant variant days days aiLevel aiLevel \
		aiMinutes aiMinutes aiIncrement aiIncrement} {
		set Priv(dlg:$key) $Options($option)
	}
	set Priv(botMode) $Options(botMode)
	# the saved choice must reach the API, not only the checkbox
	ToggleBotMode
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
	# A game runs in its own tab; the lobby stays usable meanwhile.
	if {$view eq "game"} { set view lobby }
	foreach name {signin lobby} {
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
	if {[ViewExists]} { ::online::view::status $Priv(view) $text }
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
		challenge - challengeCanceled - challengeDeclined {
			if {[llength [info commands ::lichess::social::OnEvent]]} {
				::lichess::social::OnEvent $event
			}
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
	# events of an older stream (its "closed" comes after this one opens)
	# carry an older generation and are dropped
	set Priv(gameHandle) [::lichess::api::streamGame $id \
		[namespace code [list OnGame [incr Priv(gameGen)]]]]
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
	if {[ViewExists]} { ::online::window::closeTab lichess:$Priv(gameId) }
	::online::window::closeTab lichess
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
		set variant [expr {[info exists Priv(dlg:variant)] && $Priv(dlg:variant) ne "" ? $Priv(dlg:variant) : "standard"}]
		set days [expr {[info exists Priv(dlg:days)] ? [string trim $Priv(dlg:days)] : ""}]
	} else {
		set minutes $Options(minutes)
		set increment $Options(increment)
		set rated $Options(rated)
		set colour $Options(color)
		set variant [expr {[info exists Options(variant)] && $Options(variant) ne "" ? $Options(variant) : "standard"}]
		set days [expr {[info exists Options(days)] ? [string trim $Options(days)] : ""}]
	}
	set minutes [Integer $minutes 10 0 180]
	set increment [Integer $increment 0 0 60]
	if {$days eq "" && $minutes * 60 + 40 * $increment < 480} {
		Status $mc::SeekTooFast
		return 0
	}
	set rated [expr {$rated ? 1 : 0}]
	set Options(minutes) $minutes
	set Options(increment) $increment
	set Options(rated) $rated
	set Options(color) $colour
	set Options(variant) $variant
	set Options(days) $days
	Status $mc::Seeking
	if {$variant eq "standard" && $days eq ""} {
		set Priv(seekHandle) [::lichess::api::seek $minutes $increment $rated $colour \
			[namespace code SeekClosed]]
	} else {
		set Priv(seekHandle) [::lichess::api::seek $minutes $increment $rated $colour \
			[namespace code SeekClosed] $variant $days]
	}
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

proc ::lichess::OnGame {gen event} {
	variable Priv
	variable mc
	if {$gen != $Priv(gameGen)} { return }
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
		chatLine {
			if {[dict exists $event username] && [dict exists $event text]} {
				if {[ViewExists]} {
					::online::view::chat $Priv(view) [dict get $event username] [dict get $event text]
				}
			}
		}
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
			}
		}
	}
}


proc ::lichess::StartBoard {full} {
	variable Priv
	variable mc

	FinishBoard
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

	# Each game has its own tab in the Online window, with its own board.
	set Priv(view) [::online::window::gameTab lichess:$Priv(gameId) \
		"Lichess: [OpponentName]" [namespace code ViewAction] $Priv(userSide)]
	::online::view::setGame $Priv(view) [Card white] [Card black] $Priv(initialFen) {}
	set Priv(active) 1
	set Priv(state) playing
	set Priv(serverMoves) {}
	set Priv(pendingMove) {}
	set Priv(drawOffer) 0
	set Priv(takebackOffer) 0
	set Priv(opponentGone) 0
	set Priv(finalPgn) {}
	ShowView game
	if {[llength [info commands ::lichess::api::chatHistory]] && $Priv(gameId) ne ""} {
		::lichess::api::chatHistory $Priv(gameId) \
			[namespace code [list OnChatHistory $Priv(gameId)]]
	}
	if {[dict exists $full state]} {
		SyncState [dict get $full state]
	} else {
		StatusForTurn
	}
	return 1
}


proc ::lichess::OnChatHistory {gameId reply} {
	variable Priv
	if {!$Priv(active) || $gameId ne $Priv(gameId) || ![ViewExists]} { return }
	if {![dict exists $reply ok] || ![dict get $reply ok]} { return }
	set lines [expr {[dict exists $reply data] ? [dict get $reply data] : {}}]
	foreach item $lines {
		if {[catch {dict size $item}]} { continue }
		set who [expr {[dict exists $item user] ? [dict get $item user] : \
			[dict exists $item username] ? [dict get $item username] : "?"}]
		set text [expr {[dict exists $item text] ? [dict get $item text] : ""}]
		if {$text ne ""} {
			::online::view::chat $Priv(view) $who $text
		}
	}
}


# A player card for the game view: name, title and rating.
proc ::lichess::Card {key} {
	variable Priv
	set card [dict create name ?]
	if {[dict exists $Priv(gameInfo) $key]} {
		set player [dict get $Priv(gameInfo) $key]
		dict set card name [PlayerName $player]
		foreach field {title rating} {
			if {[dict exists $player $field]} { dict set card $field [dict get $player $field] }
		}
	}
	return $card
}


proc ::lichess::ViewExists {} {
	variable Priv
	return [expr {[info exists Priv(view)] && [::online::view::exists $Priv(view)]}]
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


proc ::lichess::Moves {state} {
	if {![dict exists $state moves]} { return {} }
	return [regexp -all -inline {\S+} [dict get $state moves]]
}


proc ::lichess::SyncState {state} {
	variable Priv
	variable mc
	if {!$Priv(active) || ![ViewExists]} { return }
	set moves [Moves $state]
	set have [::online::view::ucis $Priv(view)]
	if {$moves ne $have} {
		if {[llength $moves] == [llength $have] + 1 && [lrange $moves 0 end-1] eq $have} {
			::online::view::addMove $Priv(view) [lindex $moves end]
		} elseif {[::online::view::pending $Priv(view)] ne "" && [lrange $have 0 end-1] eq $moves} {
			# Our move is still on its way; the server has not seen it yet.
		} else {
			# A jump, a takeback, or a rejected move: adopt the server's game.
			::online::view::setGame $Priv(view) [Card white] [Card black] $Priv(initialFen) $moves
		}
	} elseif {[::online::view::pending $Priv(view)] ne ""} {
		::online::view::addMove $Priv(view) [lindex $moves end]
	}
	set Priv(serverMoves) $moves
	if {[::online::view::pending $Priv(view)] eq ""} { set Priv(pendingMove) {} }
	SetClocks $state

	set Priv(drawOffer) 0
	set opponent [expr {$Priv(userSide) eq "w" ? "bdraw" : "wdraw"}]
	if {[dict exists $state $opponent] && [dict get $state $opponent]} { set Priv(drawOffer) 1 }
	set Priv(takebackOffer) 0
	set opponent [expr {$Priv(userSide) eq "w" ? "btakeback" : "wtakeback"}]
	if {[dict exists $state $opponent] && [dict get $state $opponent]} { set Priv(takebackOffer) 1 }

	set status [expr {[dict exists $state status] ? [dict get $state status] : "started"}]
	set result [ResultForState $state]
	if {$status ni {started created}} {
		EndGame $result $status
		return
	}
	UpdateGameButtons
	if {$Priv(drawOffer)} {
		::online::view::offer $Priv(view) $mc::DrawOffered
	} elseif {$Priv(takebackOffer)} {
		::online::view::offer $Priv(view) $mc::TakebackOffered
	} else {
		::online::view::offer $Priv(view) {}
	}
	StatusForTurn
}

proc ::lichess::BoardPly {} {
	variable Priv
	if {![ViewExists]} { return 0 }
	return [llength [::online::view::ucis $Priv(view)]]
}

proc ::lichess::UserMove {move} {
	variable Priv
	if {!$Priv(active) || $Priv(state) ne "playing" || $Priv(pendingMove) ne "" || ![MyTurn]} {
		return 0
	}
	return [::online::view::play $Priv(view) $move]
}


# The game view sends the user's moves and button presses here.
proc ::lichess::ViewAction {action args} {
	variable Priv
	variable mc
	switch -- $action {
		move {
			lassign $args uci san
			if {!$Priv(active) || $Priv(state) ne "playing" || $Priv(gameHandle) eq ""} {
				::online::view::rejectMove $Priv(view) $mc::NotYourTurn
				return
			}
			set gameId $Priv(gameId)
			# The view has already shown the move: ply counts it.
			set ply [BoardPly]
			set Priv(pendingMove) $uci
			Status [format $mc::WaitingMove [OpponentName]]
			if {[catch {
				::lichess::api::move $gameId $uci [namespace code [list MoveResult $gameId $uci $ply]]
			} err]} {
				MoveResult $gameId $uci $ply [dict create ok 0 error $err]
			}
		}
		resign	{ Resign }
		draw		{ OfferDraw }
		abort		{ Abort }
		claim		{ ClaimVictory }
		accept	{ if {$Priv(takebackOffer)} { Takeback yes } else { AcceptDraw } }
		decline	{ if {$Priv(takebackOffer)} { Takeback no } else { DeclineDraw } }
		takeback	{ Takeback yes }
		chat {
			if {$Priv(gameId) ne ""} {
				::lichess::api::chat $Priv(gameId) [lindex $args 0] [namespace code ActionResult]
				::online::view::chat $Priv(view) $Priv(username) [lindex $args 0]
			}
		}
		analyse	{ Analyse }
		close {
			if {$Priv(active) && $Priv(state) eq "playing"} { return }
			BackToLobby
			::online::window::closeTab lichess:$Priv(gameId)
			::online::window::select lichess
		}
	}
}


# Open the finished game on the main board for analysis.
proc ::lichess::Analyse {} {
	variable Priv
	if {$Priv(finalPgn) eq ""} { return }
	::menu::gameNew .application
	ImportGame [::scidb::game::current] $Priv(finalPgn)
	::scidb::game::go end
	raise .application
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
	set Priv(pendingMove) {}
	if {[ViewExists]} { ::online::view::rejectMove $Priv(view) $why }
	Status $why
}

proc ::lichess::MyTurn {} {
	variable Priv
	if {$Priv(userSide) ni {w b} || ![ViewExists]} { return 0 }
	return [expr {[lindex [::online::view::fen $Priv(view)] 1] eq $Priv(userSide)}]
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
	after cancel $Priv(tick)
	set Priv(tick) {}
	set Priv(active) 0
	set Priv(ticking) 0
	set Priv(pendingMove) {}
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
	UpdateGameButtons
	Status [format $mc::GameOver $result $reason]
	if {[ViewExists]} { ::online::view::result $Priv(view) [format $mc::GameOver $result $reason] }
	ShowView lobby
}


proc ::lichess::StoreResult {result} {
	variable Priv
	if {![ViewExists]} { return }
	set pgn [BoardPgn $Priv(gameInfo) $result]
	set tags [string range $pgn 0 [string first "\n\n" $pgn]]
	set moves [::online::view::pgn $Priv(view) {} $result]
	regsub -all -line {^\[.*\]\n} $moves {} moves
	set Priv(finalPgn) "$tags[string trimleft $moves \n]"
}

proc ::lichess::UpdateGameButtons {} {
	variable Priv
	if {![ViewExists]} { return }
	set playing [expr {$Priv(active) && $Priv(state) eq "playing"}]
	::online::view::actions $Priv(view) [dict create resign $playing draw $playing \
		takeback $playing abort $playing claim [expr {$playing && $Priv(opponentGone)}]]
}

proc ::lichess::Takeback {answer} {
	variable Priv
	if {$Priv(active) && $Priv(state) eq "playing"} {
		::lichess::api::takeback $Priv(gameId) $answer [namespace code ActionResult]
	}
}


proc ::lichess::OfferTakeback {} {
	Takeback yes
}


proc ::lichess::AcceptTakeback {} {
	Takeback yes
}


proc ::lichess::DeclineTakeback {} {
	Takeback no
}


proc ::lichess::SendChat {text} {
	variable Priv
	set text [string trim $text]
	if {$text eq "" || $Priv(gameId) eq ""} { return 0 }
	::lichess::api::chat $Priv(gameId) $text [namespace code ActionResult]
	if {[ViewExists]} {
		::online::view::chat $Priv(view) $Priv(username) $text
	}
	return 1
}


# ======================================================================
# Bot mode, Cloud eval, Analyse on Lichess, and Game export
# ======================================================================

proc ::lichess::ToggleBotMode {{on ""}} {
	variable Priv
	variable Options
	if {$on ne ""} { set Priv(botMode) [expr {$on ? 1 : 0}] }
	set Options(botMode) [expr {$Priv(botMode) ? 1 : 0}]
	set mode [expr {$Options(botMode) ? "bot" : "board"}]
	if {[llength [info commands ::lichess::api::mode]]} {
		::lichess::api::mode $mode
	}
	return $mode
}


proc ::lichess::UpgradeToBot {{confirm 0}} {
	variable Priv
	variable mc
	if {!$confirm} {
		set parent [expr {[DialogExists] ? $Priv(dialog) : ".application"}]
		if {[::dialog::question -parent $parent -message $mc::BotUpgradeWarning] ne "yes"} {
			return 0
		}
	}
	::lichess::api::botUpgrade [namespace code OnBotUpgraded]
	return 1
}


proc ::lichess::OnBotUpgraded {reply} {
	variable Priv
	variable mc
	if {[dict exists $reply ok] && [dict get $reply ok]} {
		ToggleBotMode 1
		Status $mc::BotUpgraded
	} else {
		Status [expr {[dict exists $reply error] ? [dict get $reply error] : "Could not upgrade to Bot account."}]
	}
}


proc ::lichess::CurrentFen {} {
	variable Priv
	if {[ViewExists]} { return [::online::view::fen $Priv(view)] }
	if {![catch { ::scidb::pos::fen } fen] && $fen ne ""} { return $fen }
	return "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
}


proc ::lichess::RequestCloudEval {{fen ""} {multiPv 3}} {
	variable Priv
	if {$fen eq ""} { set fen [CurrentFen] }
	::lichess::api::cloudEval $fen $multiPv [namespace code OnCloudEval]
	return 1
}


proc ::lichess::OnCloudEval {reply} {
	variable Priv
	variable mc
	if {![dict exists $reply ok] || ![dict get $reply ok]} {
		set msg [expr {[dict exists $reply error] && [dict get $reply error] ne "" ? \
			[dict get $reply error] : $mc::CloudEvalNone}]
		set Priv(cloudEvalText) $msg
		Status $msg
		return
	}
	set d [expr {[dict exists $reply data] ? [dict get $reply data] : $reply}]
	set depth [expr {[dict exists $d depth] ? [dict get $d depth] : "?"}]
	set knodes [expr {[dict exists $d knodes] ? [dict get $d knodes] : 0}]
	set lines {}
	if {[dict exists $d pvs]} {
		foreach pv [dict get $d pvs] {
			if {[catch {dict size $pv}]} { continue }
			if {[dict exists $pv mate]} {
				set score "#[dict get $pv mate]"
			} elseif {[dict exists $pv cp]} {
				set score [format "%+.2f" [expr {[dict get $pv cp] / 100.0}]]
			} else {
				set score "0.00"
			}
			set moves [expr {[dict exists $pv moves] ? [dict get $pv moves] : ""}]
			lappend lines "$score: $moves"
		}
	}
	set text "Depth $depth (${knodes}k nodes): [join $lines { | }]"
	set Priv(cloudEvalText) $text
	Status $text
}


proc ::lichess::AnalyseOnLichess {{pgn ""}} {
	variable Priv
	if {$pgn eq ""} {
		if {[info exists Priv(finalPgn)] && $Priv(finalPgn) ne ""} {
			set pgn $Priv(finalPgn)
		} elseif {[ViewExists]} {
			set pgn [::online::view::pgn $Priv(view) [dict create Event "Lichess game"] *]
		} elseif {![catch { ::scidb::game::toPGN original } g] && [string trim $g] ne ""} {
			set pgn $g
		} else {
			# nothing to analyse: never post a made-up game to the account
			Status $mc::AnalyseNoGame
			return 0
		}
	}
	::lichess::api::importGame $pgn [namespace code OnGameImported]
	return 1
}


proc ::lichess::OnGameImported {reply} {
	variable Priv
	variable mc
	if {![dict exists $reply ok] || ![dict get $reply ok]} {
		Status [expr {[dict exists $reply error] ? [dict get $reply error] : "Could not import game to Lichess."}]
		return
	}
	set d [expr {[dict exists $reply data] ? [dict get $reply data] : $reply}]
	set id [expr {[dict exists $d id] ? [dict get $d id] : ""}]
	set base [expr {[info exists ::lichess::api::Base] ? [string trimright $::lichess::api::Base /] : "https://lichess.org"}]
	# only a Lichess address is handed to the browser
	set url "$base/[::lichess::api::Segment $id]"
	if {[dict exists $d url] && [string match "$base/*" [dict get $d url]]} { set url [dict get $d url] }
	catch { ::lichess::api::OpenBrowser $url }
	Status [format $mc::AnalyseOpened $url]
}


proc ::lichess::ExportGamePgn {id} {
	::lichess::api::gameExport $id [namespace code [list OnGameExported $id]]
	return 1
}


proc ::lichess::OnGameExported {id reply} {
	variable Priv
	if {![dict exists $reply ok] || ![dict get $reply ok]} {
		Status [expr {[dict exists $reply error] ? [dict get $reply error] : "Could not export game."}]
		return
	}
	set pgn [expr {[dict exists $reply data] ? [dict get $reply data] : ""}]
	set Priv(exportedPgn) $pgn
	Status "Exported game $id."
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
	if {[ViewExists]} { set Priv(clockStm) [lindex [::online::view::fen $Priv(view)] 1] }
	set status [expr {[dict exists $state status] ? [dict get $state status] : "started"}]
	set Priv(ticking) [expr {$Priv(active) && $status in {started created} && $Priv(state) ne "over"}]
	set Priv(clockAt) [clock milliseconds]
	if {[ViewExists]} {
		::online::view::clocks $Priv(view) $Priv(clock:w) $Priv(clock:b) $Priv(clockStm) $Priv(ticking)
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
