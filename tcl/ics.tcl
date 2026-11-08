# ======================================================================
# Play on the Free Internet Chess Server (Training > Play Online (FICS)).
# A nonblocking socket owns the login dialogue, live seek list and style
# 12 board stream. Games use the main board, as in tcl/play-engine.tcl.
#
#   ::ics::open .application       connect -> lobby -> game panel
#   ::ics::Connect ?password?      programmatic connect using Options
#   ::ics::UserMove <san>          board move entry point used by tests
#
# Passwords are transient entry values: they are neither options nor log
# lines. Protocol parsers are pure and covered by tests/test_app_ics.tcl;
# its socket server is loopback-only. No test connects to freechess.org.
# ======================================================================

::util::source ics

package require Tcl 8.5
package require Tk 8.5

namespace eval ::ics {
namespace eval mc {

set Title					"Play Online (FICS)"
set Handle					"Handle:"
set Password				"Password:"
set Server					"Server:"
set Port					"Port:"
set GuestDetail				"Leave the handle empty to play as a guest."
set Connect					"Connect"
set Connecting				"Connecting to %s:%s..."
set WaitingLogin			"Connected. Waiting for the login prompt."
set ConnectedAs				"Logged in as %s."
set InvalidPassword			"The server rejected the password."
set InvalidServer			"Enter a server name and a port from 1 to 65535."
set ConnectTimeout			"The server did not answer the connection attempt."
set Disconnected			"Disconnected from the server."
set Close					"Close"
set Cancel					"Cancel"
set Play					"Play"
set Seek					"Seek"
set Unseek					"Unseek"
set Watch					"Watch a game"
set Send					"Send"
set Rating					"Rating"
set Name					"Name"
set Time					"Time"
set Increment				"Inc"
set Rated					"Rated"
set RatedSeek				"rated"
set UnratedSeek				"unrated"
set Type					"Type"
set Minutes					"Minutes:"
set IncrementSeconds		"Increment (seconds):"
set RatedGame				"Rated game"
set Colour					"Colour:"
set Auto					"auto"
set White					"white"
set Black					"black"
set ServerText				"Server messages"
set RawCommand				"Command:"
set WhiteClock				"White"
set BlackClock				"Black"
set YourMove				"Your move."
set WaitingMove				"Waiting for %s's move."
set Observing				"Observing %s versus %s. The board is read-only."
set Resign					"Resign"
set OfferDraw				"Offer draw"
set Abort					"Abort"
set BackToLobby				"Back to lobby"
set ObservationEnded		"Observation ended."
set IllegalMove				"The server rejected %s; the move was taken back."
set NotYourTurn				"Wait for the opponent's move."
set ReadOnly				"An observed game is read-only."
set NotAtEnd				"Return to the end of the game to move."
set GameOver				"Game over: %s (%s)."
set ImportFailed			"Could not put the server position on the board: %s"
set NoClockTime				"\u2014"


} ;# namespace mc

# The password deliberately has no entry here. Host, port, handle and the
# seek defaults survive through the ordinary options writer.
array set Options {
	host			freechess.org
	port			5000
	handle			{}
	minutes			5
	increment		0
	rated			0
	color			auto
}

variable ConnectTimeout 10000
variable TickInterval 250

array set Priv {
	dialog			{}
	socket			{}
	buffer			{}
	state			offline
	loggedIn		0
	handle			{}
	loginHandle		{}
	loginPassword	{}
	guest			1
	statusText		{}
	active			0
	busy			0
	pos				0
	gameNumber		-1
	basePly			0
	serverPly		0
	relation		0
	userSide		{}
	observing		0
	pendingMove		{}
	gameInfo		{}
	clock:w			0
	clock:b			0
	clockAt			0
	clockStm		w
	ticking			0
	tick			{}
	inputAfter		{}
	connectTimer	{}
	textLines		{}
}

variable Seeks [dict create]

} ;# namespace ics


# ======================================================================
# The dialog
# ======================================================================

proc ::ics::open {parent} {
	variable Priv
	variable Options
	variable mc

	foreach number [::application::analysis::Running] {
		::application::analysis::stopEngine $number
	}

	set dlg $parent.ics
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

	### connect ############################################################
	set f [ttk::frame $top.connect]
	set Priv(widget:connect) $f
	grid [ttk::label $f.handleLabel -text $mc::Handle] -row 0 -column 0 -sticky w
	grid [ttk::entry $f.handle -width 22 -textvariable [namespace current]::Priv(dlg:handle)] \
		-row 0 -column 1 -sticky ew -padx [list $::theme::padx 0]
	grid [ttk::label $f.passwordLabel -text $mc::Password] -row 1 -column 0 -sticky w
	grid [ttk::entry $f.password -width 22 -show * -textvariable [namespace current]::Priv(dlg:password)] \
		-row 1 -column 1 -sticky ew -padx [list $::theme::padx 0]
	grid [ttk::label $f.guest -text $mc::GuestDetail -wraplength 300 -justify left] \
		-row 2 -column 0 -columnspan 2 -sticky w -pady [list 0 $::theme::pady]
	grid [ttk::label $f.serverLabel -text $mc::Server] -row 3 -column 0 -sticky w
	grid [ttk::entry $f.server -width 22 -textvariable [namespace current]::Priv(dlg:host)] \
		-row 3 -column 1 -sticky ew -padx [list $::theme::padx 0]
	grid [ttk::label $f.portLabel -text $mc::Port] -row 4 -column 0 -sticky w
	grid [ttk::spinbox $f.port -from 1 -to 65535 -width 7 -textvariable [namespace current]::Priv(dlg:port)] \
		-row 4 -column 1 -sticky w -padx [list $::theme::padx 0]
	grid columnconfigure $f 1 -weight 1

	### lobby ##############################################################
	set l [ttk::frame $top.lobby]
	set Priv(widget:lobby) $l
	set treeFrame [ttk::frame $l.tree]
	set tree [ttk::treeview $treeFrame.seeks -height 6 -selectmode browse \
		-columns {rating name time inc rated type} -displaycolumns #all]
	$tree heading #0 -text "#"
	$tree column #0 -width 42 -stretch 0 -anchor e
	foreach {column label width} {
		rating Rating 62 name Name 105 time Time 45 inc Increment 40 rated Rated 65 type Type 70
	} {
		$tree heading $column -text [set mc::$label]
		$tree column $column -width $width -stretch [expr {$column eq "name"}] -anchor w
	}
	$tree column rating -anchor e
	$tree column time -anchor e
	$tree column inc -anchor e
	set scroll [ttk::scrollbar $treeFrame.scroll -orient vertical -command [list $tree yview]]
	$tree configure -yscrollcommand [list $scroll set]
	grid $tree -row 0 -column 0 -sticky nsew
	grid $scroll -row 0 -column 1 -sticky ns
	grid columnconfigure $treeFrame 0 -weight 1
	grid rowconfigure $treeFrame 0 -weight 1
	pack $treeFrame -fill both -expand yes
	bind $tree <Double-1> [namespace code PlaySelected]
	set Priv(widget:tree) $tree

	set sf [ttk::frame $l.seek]
	grid [ttk::label $sf.minutesLabel -text $mc::Minutes] -row 0 -column 0 -sticky w
	grid [ttk::spinbox $sf.minutes -from 0 -to 180 -width 4 -textvariable [namespace current]::Priv(dlg:minutes)] \
		-row 0 -column 1 -sticky w -padx [list $::theme::padx 0]
	grid [ttk::label $sf.incLabel -text $mc::IncrementSeconds] -row 1 -column 0 -sticky w
	grid [ttk::spinbox $sf.increment -from 0 -to 60 -width 4 -textvariable [namespace current]::Priv(dlg:increment)] \
		-row 1 -column 1 -sticky w -padx [list $::theme::padx 0]
	grid [ttk::checkbutton $sf.rated -text $mc::RatedGame -variable [namespace current]::Priv(dlg:rated)] \
		-row 2 -column 0 -columnspan 2 -sticky w
	grid [ttk::label $sf.colorLabel -text $mc::Colour] -row 3 -column 0 -sticky w
	grid [ttk::combobox $sf.color -state readonly -width 8 \
		-values [list $mc::Auto $mc::White $mc::Black] -textvariable [namespace current]::Priv(dlg:color)] \
		-row 3 -column 1 -sticky w -padx [list $::theme::padx 0]
	grid [ttk::button $sf.seek -text $mc::Seek -command [namespace code Seek]] \
		-row 4 -column 0 -sticky w -pady [list $::theme::pady 0]
	grid [ttk::button $sf.unseek -text $mc::Unseek -command [namespace code Unseek]] \
		-row 4 -column 1 -sticky w -padx [list $::theme::padx 0] -pady [list $::theme::pady 0]
	pack $sf -fill x -pady [list $::theme::pady]
	set Priv(widget:rated) $sf.rated

	set actions [ttk::frame $l.actions]
	ttk::button $actions.play -text $mc::Play -command [namespace code PlaySelected]
	ttk::button $actions.watch -text $mc::Watch -command [namespace code Watch]
	pack $actions.play -side left
	pack $actions.watch -side left -padx [list $::theme::padx 0]
	pack $actions -anchor w

	ttk::label $l.messagesLabel -text $mc::ServerText
	pack $l.messagesLabel -anchor w -pady [list $::theme::pady 0]
	set messages [ttk::frame $l.messages]
	set text [text $messages.text -width 44 -height 7 -wrap word -state disabled \
		-borderwidth 0 -highlightthickness 0]
	set textScroll [ttk::scrollbar $messages.scroll -orient vertical -command [list $text yview]]
	$text configure -yscrollcommand [list $textScroll set]
	grid $text -row 0 -column 0 -sticky nsew
	grid $textScroll -row 0 -column 1 -sticky ns
	grid columnconfigure $messages 0 -weight 1
	grid rowconfigure $messages 0 -weight 1
	pack $messages -fill both -expand yes
	set Priv(widget:text) $text

	set raw [ttk::frame $l.raw]
	ttk::label $raw.label -text $mc::RawCommand
	ttk::entry $raw.entry -textvariable [namespace current]::Priv(dlg:raw)
	ttk::button $raw.send -text $mc::Send -command [namespace code SendRaw]
	pack $raw.label -side left
	pack $raw.entry -side left -fill x -expand yes -padx $::theme::padx
	pack $raw.send -side left
	bind $raw.entry <Return> [namespace code SendRaw]
	pack $raw -fill x -pady [list $::theme::pady 0]

	### game ###############################################################
	set g [ttk::frame $top.game]
	set Priv(widget:game) $g
	set clocks [ttk::frame $g.clocks]
	ttk::label $clocks.white -width 25 -anchor w
	ttk::label $clocks.whiteclock -font $::font::text(text:normal) -width 9 -anchor e
	ttk::label $clocks.black -width 25 -anchor w
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
	ttk::button $buttons.abort -text $mc::Abort -command [namespace code Abort]
	pack $buttons.resign -side left
	pack $buttons.draw -side left -padx $::theme::padx
	pack $buttons.abort -side left
	pack $buttons -anchor w -pady [list $::theme::pady]
	set Priv(widget:resign) $buttons.resign
	set Priv(widget:draw) $buttons.draw
	set Priv(widget:abort) $buttons.abort

	# the right pad keeps the text clear of the Pin box in the corner
	ttk::label $top.status -wraplength 300 -justify left
	pack $top.status -fill x -pady [list $::theme::pady 0] -padx [list 0 40]
	set Priv(widget:status) $top.status

	::util::place::playingButtons $dlg {ok cancel}
	set ok [::util::place::playingBody $dlg].ok
	set cancel [::util::place::playingBody $dlg].cancel
	$cancel configure -text $mc::Close -command [namespace code Close]
	set Priv(widget:ok) $ok
	set Priv(widget:cancel) $cancel
	# in the game view the dialog's own button is "Back to lobby"
	set Priv(widget:back) $ok

	set Priv(dlg:handle) $Options(handle)
	set Priv(dlg:password) {}
	set Priv(dlg:host) $Options(host)
	set Priv(dlg:port) $Options(port)
	set Priv(dlg:minutes) $Options(minutes)
	set Priv(dlg:increment) $Options(increment)
	set Priv(dlg:rated) $Options(rated)
	set Priv(dlg:color) [set mc::[expr {$Options(color) eq "auto" ? "Auto" : \
		$Options(color) eq "white" ? "White" : "Black"}]]
	set Priv(dlg:raw) {}
	ShowView [expr {$Priv(loggedIn) ? "lobby" : "connect"}]
	RestoreText

	::util::place::besideBoard $dlg $parent
	wm deiconify $dlg
	return $dlg
}


proc ::ics::ShowView {view} {
	variable Priv
	variable mc

	if {![DialogExists]} { return }
	foreach name {connect lobby game} {
		pack forget $Priv(widget:$name)
	}
	pack $Priv(widget:$view) -fill both -expand yes
	switch -- $view {
		connect {
			$Priv(widget:ok) configure -text $mc::Connect -command [namespace code ConnectFromDialog]
			$Priv(widget:ok) state !disabled
		}
		lobby {
			$Priv(widget:ok) configure -text $mc::Play -command [namespace code PlaySelected]
			$Priv(widget:ok) state !disabled
			GuestControls
			RefreshSeeks
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


proc ::ics::ConnectFromDialog {} {
	variable Priv
	Connect $Priv(dlg:password)
}


proc ::ics::DialogExists {} {
	variable Priv
	return [expr {[string length $Priv(dialog)] && [winfo exists $Priv(dialog)]}]
}


proc ::ics::Status {text} {
	variable Priv
	set Priv(statusText) $text
	if {[DialogExists] && [info exists Priv(widget:status)]} {
		$Priv(widget:status) configure -text $text
	}
}


# ======================================================================
# Socket and login
# ======================================================================

proc ::ics::Connect {{password ""}} {
	variable Priv
	variable Options
	variable Seeks
	variable mc
	variable ConnectTimeout

	if {$Priv(socket) ne ""} { return 1 }
	if {[DialogExists] && [info exists Priv(dlg:host)]} {
		set host [string trim $Priv(dlg:host)]
		set port $Priv(dlg:port)
		set handle [string trim $Priv(dlg:handle)]
	} else {
		set host [string trim $Options(host)]
		set port $Options(port)
		set handle [string trim $Options(handle)]
	}
	if {$host eq "" || ![string is integer -strict $port] || $port < 1 || $port > 65535} {
		Status $mc::InvalidServer
		return 0
	}

	FinishBoard
	set Options(host) $host
	set Options(port) $port
	set Options(handle) $handle
	set Priv(loginHandle) $handle
	set Priv(loginPassword) $password
	set Priv(guest) [expr {$handle eq "" || [string tolower $handle] eq "guest"}]
	set Priv(handle) {}
	set Priv(loggedIn) 0
	set Priv(buffer) {}
	set Priv(textLines) {}
	set Seeks [dict create]
	Status [format $mc::Connecting $host $port]

	if {[catch { set sock [::socket -async $host $port] } err]} {
		set Priv(loginPassword) {}
		Status $err
		return 0
	}
	set Priv(socket) $sock
	fconfigure $sock -blocking 0 -buffering none -translation binary -encoding binary
	fileevent $sock writable [namespace code Connected]
	fileevent $sock readable [namespace code OnReadable]
	set Priv(connectTimer) [after $ConnectTimeout [namespace code OnConnectTimeout]]
	set Priv(state) connecting
	return 1
}


proc ::ics::Connected {} {
	variable Priv
	variable mc

	set sock $Priv(socket)
	fileevent $sock writable {}
	if {[catch { fconfigure $sock -error } err] || $err ne ""} {
		Disconnect $err
		return
	}
	set Priv(state) login
	Status $mc::WaitingLogin
}


proc ::ics::OnConnectTimeout {} {
	variable Priv
	variable mc
	set Priv(connectTimer) {}
	if {!$Priv(loggedIn)} { Disconnect $mc::ConnectTimeout }
}


proc ::ics::Disconnect {{why ""}} {
	variable Priv
	variable Seeks

	after cancel $Priv(connectTimer)
	set Priv(connectTimer) {}
	if {$Priv(socket) ne ""} {
		catch { fileevent $Priv(socket) readable {} }
		catch { fileevent $Priv(socket) writable {} }
		catch { close $Priv(socket) }
	}
	set Priv(socket) {}
	set Priv(buffer) {}
	set Priv(loggedIn) 0
	set Priv(state) offline
	set Priv(handle) {}
	set Priv(loginPassword) {}
	if {[info exists Priv(dlg:password)]} { set Priv(dlg:password) {} }
	set Seeks [dict create]
	FinishBoard
	if {$why ne ""} { Status $why }
	if {[DialogExists]} { ShowView connect }
}


proc ::ics::Close {} {
	variable Priv
	variable mc

	if {$Priv(socket) ne ""} { Send quit }
	Disconnect
	set Priv(loginPassword) {}
	if {[info exists Priv(dlg:password)]} { set Priv(dlg:password) {} }
	if {[string length $Priv(dialog)] && [winfo exists $Priv(dialog)]} { destroy $Priv(dialog) }
	set Priv(dialog) {}
}


# Send a complete command. Never pass outgoing lines to LogText or debuglog:
# during login the line can be the password.
proc ::ics::Send {line} {
	variable Priv
	if {$Priv(socket) eq ""} { return 0 }
	if {[catch {
		# a bare newline: freechess.org reads "\r\n" at the guest prompt as
		# two answers and then waits for ever at "Press return"
		puts -nonewline $Priv(socket) "$line\n"
		flush $Priv(socket)
	} err]} {
		Disconnect $err
		return 0
	}
	return 1
}


proc ::ics::OnReadable {} {
	variable Priv

	set sock $Priv(socket)
	if {$sock eq ""} { return }
	if {[catch {
		append Priv(buffer) [read $sock]
		while {[set end [string first "\n" $Priv(buffer)]] >= 0} {
			set line [string range $Priv(buffer) 0 [expr {$end - 1}]]
			set Priv(buffer) [string range $Priv(buffer) [expr {$end + 1}] end]
			ProcessLine [cleanLine $line]
			if {$Priv(socket) ne $sock} { return }
		}
		ProcessPrompt
		if {$Priv(socket) ne $sock} { return }
		if {[eof $sock]} {
			if {$Priv(buffer) ne ""} {
				ProcessLine [cleanLine $Priv(buffer)]
				set Priv(buffer) {}
			}
			Disconnect $::ics::mc::Disconnected
		}
	} err]} {
		catch { ::debuglog::log ics "socket processing failed: $err" }
		Disconnect $err
	}
}


# Login prompts are not newline terminated. Consuming a recognised prompt
# also prevents another readable event from answering it a second time.
proc ::ics::ProcessPrompt {} {
	variable Priv
	variable mc

	if {$Priv(state) ni {connecting login} || $Priv(buffer) eq ""} { return }
	if {[AnswerPrompt [cleanLine $Priv(buffer)]]} { set Priv(buffer) {} }
}


# Answers a login prompt ending <text>; whether it was one.
proc ::ics::AnswerPrompt {text} {
	variable Priv

	if {[regexp {login:\s*$} $text]} {
		Send [expr {$Priv(guest) ? "guest" : $Priv(loginHandle)}]
		return 1
	}
	if {[regexp -nocase {password:\s*$} $text]} {
		set password $Priv(loginPassword)
		set Priv(loginPassword) {}
		if {[info exists Priv(dlg:password)]} { set Priv(dlg:password) {} }
		Send $password
		return 1
	}
	if {[regexp {Press return to enter the server as .*:\s*$} $text]} {
		Send ""
		return 1
	}
	return 0
}


proc ::ics::ProcessLine {line} {
	variable Priv
	variable Options
	variable Seeks
	variable mc

	if {$line eq ""} { return }
	# a login prompt can also arrive with its newline: answer it the same way
	if {$Priv(state) in {connecting login} && [AnswerPrompt $line]} { return }
	if {[regexp {\*\*\*\* Starting FICS session as ([^ (]+)} $line -> name]} {
		set Priv(handle) $name
		set Priv(loggedIn) 1
		set Priv(state) lobby
		set Priv(loginPassword) {}
		after cancel $Priv(connectTimer)
		set Priv(connectTimer) {}
		ShowView lobby
		Status [format $mc::ConnectedAs $name]
		foreach command {
			{iset nowrap 1}
			{iset ms 1}
			{iset seekinfo 1}
			{iset seekremove 1}
			{set style 12}
			{set bell 0}
			{set interface Chesswiz}
		} {
			Send $command
		}
		return
	}
	if {[string match {**** Invalid password! *****} $line]} {
		Disconnect
		Status $mc::InvalidPassword
		LogText $line
		return
	}
	if {$line eq "<sc>"} {
		set Seeks [dict create]
		RefreshSeeks
		return
	}
	if {[regexp {^<sr>\s+([0-9 ]+)$} $line -> indexes]} {
		foreach index $indexes {
			catch { dict unset Seeks $index }
		}
		RefreshSeeks
		return
	}
	if {[string match {<s> *} $line]} {
		set seek [parseSeek $line]
		if {$seek eq ""} { return }
		set index [dict get $seek index]
		if {[StandardSeek $seek]} {
			dict set Seeks $index $seek
		} else {
			catch { dict unset Seeks $index }
		}
		RefreshSeeks
		return
	}
	if {[string match {<12> *} $line]} {
		HandleStyle12 [parseStyle12 $line]
		return
	}

	set end [parseGameEnd $line]
	if {$end ne ""} {
		if {$Priv(active) && ($Priv(gameNumber) < 0 || [dict get $end game] == $Priv(gameNumber))} {
			EndGame [dict get $end result] [dict get $end reason]
		}
		LogText $line
		return
	}
	set start [parseGameStart $line]
	if {$start ne ""} {
		if {([dict exists $start observing] && [dict get $start observing]) || [string match {Creating:*} $line]} {
			set Priv(gameInfo) {}
		}
		set Priv(gameInfo) [dict merge $Priv(gameInfo) $start]
		LogText $line
		return
	}
	if {[regexp {You are now observing game ([0-9]+)\.} $line -> number]} {
		set Priv(gameInfo) [dict create game $number observing 1]
		LogText $line
		return
	}
	if {[regexp {Removing game ([0-9]+) from observation list\.} $line -> number]} {
		if {$Priv(active) && $Priv(observing) && $number == $Priv(gameNumber)} {
			FinishBoard
			set Priv(state) lobby
			ShowView lobby
			Status $mc::ObservationEnded
		}
		LogText $line
		return
	}
	if {[string match -nocase {*Illegal move*} $line] && $Priv(pendingMove) ne ""} {
		RejectMove [format $mc::IllegalMove $Priv(pendingMove)] 1
	}
	LogText $line
}


# ======================================================================
# Lobby
# ======================================================================

# Standard chess only; computer opponents stay listed, marked "(C)".
proc ::ics::StandardSeek {seek} {
	return [expr {[dict get $seek type] in {blitz lightning standard untimed}}]
}


proc ::ics::RefreshSeeks {} {
	variable Priv
	variable Seeks
	variable mc

	if {![DialogExists] || ![info exists Priv(widget:tree)]} { return }
	set tree $Priv(widget:tree)
	foreach item [$tree children {}] { $tree delete $item }
	foreach index [lsort -integer [dict keys $Seeks]] {
		set seek [dict get $Seeks $index]
		set rated [expr {[dict get $seek rated] eq "r" ? $mc::RatedSeek : $mc::UnratedSeek}]
		set name [dict get $seek name]
		if {[dict get $seek computer]} { append name " (C)" }
		$tree insert {} end -id $index -text $index -values [list \
			[dict get $seek rating] $name [dict get $seek time] \
			[dict get $seek inc] $rated [dict get $seek type]]
	}
}


proc ::ics::PlaySelected {} {
	variable Priv
	if {![DialogExists]} { return }
	set selection [$Priv(widget:tree) selection]
	if {[llength $selection]} { Play [lindex $selection 0] }
}


proc ::ics::Play {{index ""}} {
	variable Priv
	variable Seeks
	if {$index eq "" || ![dict exists $Seeks $index]} { return 0 }
	return [Send "play $index"]
}


proc ::ics::Seek {} {
	variable Priv
	variable Options
	variable mc

	if {!$Priv(loggedIn)} { return 0 }
	if {[DialogExists]} {
		set minutes $Priv(dlg:minutes)
		set increment $Priv(dlg:increment)
		set rated $Priv(dlg:rated)
		set colourIndex [lsearch -exact [list $mc::Auto $mc::White $mc::Black] $Priv(dlg:color)]
		if {$colourIndex < 0} { set colourIndex 0 }
		set colour [lindex {auto white black} $colourIndex]
	} else {
		set minutes $Options(minutes)
		set increment $Options(increment)
		set rated $Options(rated)
		set colour $Options(color)
	}
	if {![string is integer -strict $minutes]} { set minutes 5 }
	if {![string is integer -strict $increment]} { set increment 0 }
	set minutes [expr {max(0, min(180, $minutes))}]
	set increment [expr {max(0, min(60, $increment))}]
	if {$Priv(guest)} { set rated 0 }
	set Options(minutes) $minutes
	set Options(increment) $increment
	set Options(rated) [expr {$rated ? 1 : 0}]
	set Options(color) $colour
	set command "seek $minutes $increment [expr {$rated ? "r" : "u"}]"
	if {$colour in {white black}} { append command " [string index $colour 0]" }
	return [Send $command]
}


proc ::ics::Unseek {} { return [::ics::Send unseek] }
proc ::ics::Watch {} { return [::ics::Send {observe /b}] }


proc ::ics::GuestControls {} {
	variable Priv
	if {![DialogExists] || ![info exists Priv(widget:rated)]} { return }
	if {$Priv(guest)} {
		set Priv(dlg:rated) 0
		$Priv(widget:rated) state disabled
	} else {
		$Priv(widget:rated) state !disabled
	}
}


proc ::ics::SendRaw {} {
	variable Priv
	if {![DialogExists]} { return 0 }
	set line [string trim $Priv(dlg:raw)]
	set Priv(dlg:raw) {}
	if {$line eq ""} { return 0 }
	return [Send $line]
}


proc ::ics::LogText {line} {
	variable Priv
	if {[string trim $line] eq ""} { return }
	lappend Priv(textLines) $line
	if {[llength $Priv(textLines)] > 200} {
		set Priv(textLines) [lrange $Priv(textLines) end-199 end]
	}
	RestoreText
}


proc ::ics::RestoreText {} {
	variable Priv
	if {![DialogExists] || ![info exists Priv(widget:text)]} { return }
	set text $Priv(widget:text)
	$text configure -state normal
	$text delete 1.0 end
	if {[llength $Priv(textLines)]} {
		$text insert end "[join $Priv(textLines) \n]\n"
	}
	$text configure -state disabled
	$text see end
}


# ======================================================================
# The board and the style 12 stream
# ======================================================================

proc ::ics::HandleStyle12 {style} {
	variable Priv
	variable mc

	if {$style eq ""} { return }
	set number [dict get $style game]
	if {!$Priv(active) || $number != $Priv(gameNumber)} {
		if {[catch { StartBoard $style } err]} {
			catch { ::debuglog::log ics "game import failed: $err" }
			FinishBoard
			Status [format $mc::ImportFailed $err]
			return
		}
	}
	if {!$Priv(active)} { return }
	SetClocks $style

	set before [BoardPly]
	set serverPly [dict get $style ply]
	set delta [expr {$serverPly - $before}]
	if {$delta == 1} {
		set san [dict get $style san]
		if {$san eq "" || $san eq "none"} {
			Resync $style
			return
		}
		Busy on
		set code [catch { ::scidb::game::move $san; ::scidb::game::go 1 } err]
		Busy off
		if {$code || [BoardPly] != $before + 1} {
			Resync $style
			return
		}
	} elseif {$delta != 0} {
		# +0 is the normal echo of a move entered locally. Any other jump,
		# and every placement mismatch including that echo, needs a snapshot.
		Resync $style
		return
	}

	if {[catch { ::scidb::pos::fen } fen] || [lindex $fen 0] ne [dict get $style board]} {
		Resync $style
		return
	}
	set Priv(serverPly) $serverPly
	set Priv(relation) [dict get $style relation]
	# the board matches the server: a move sent earlier was accepted, so a
	# later "Illegal move" (e.g. to a typed command) must not take it back
	set Priv(pendingMove) {}
	UpdateGameButtons
	UpdateBoardInput
	DrawNames
	DrawClocks
	StatusForTurn
	StartTick
}


proc ::ics::StartBoard {style} {
	variable Priv
	variable Options
	variable mc

	FinishBoard
	::menu::gameNew .application
	set Priv(pos) [::scidb::game::current]
	set Priv(gameNumber) [dict get $style game]
	set Priv(basePly) [dict get $style ply]
	set Priv(serverPly) [dict get $style ply]
	set Priv(relation) [dict get $style relation]
	set Priv(observing) [expr {[dict get $style relation] == 0}]
	if {[dict exists $Priv(gameInfo) observing] && [dict get $Priv(gameInfo) observing]} {
		set Priv(observing) 1
	}
	if {$Priv(relation) == 1} {
		set Priv(userSide) [dict get $style stm]
	} elseif {$Priv(relation) == -1} {
		set Priv(userSide) [expr {[dict get $style stm] eq "w" ? "b" : "w"}]
	} else {
		set Priv(userSide) {}
		set Priv(observing) 1
	}

	set info $Priv(gameInfo)
	dict set info game $Priv(gameNumber)
	dict set info white [dict get $style white]
	dict set info black [dict get $style black]
	dict set info minutes [dict get $style minutes]
	dict set info increment [dict get $style increment]
	if {![dict exists $info rated]} { dict set info rated unrated }
	if {![dict exists $info type]} { dict set info type blitz }
	set Priv(gameInfo) $info

	set setup [expr {$Priv(basePly) > 0 || [dict get $style fen] ne \
		"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"}]
	set pgn [BoardPgn $info $style $setup *]
	set Priv(busy) 1
	set code [catch { ImportGame $Priv(pos) $pgn } err]
	set Priv(busy) 0
	if {$code} { return -code error $err }
	::scidb::game::go end
	# the user's side at the bottom; FinishBoard turns it back
	set Priv(rotated) 0
	if {$Priv(userSide) ne "" && [catch { ::application::board::rotated? } rotated] == 0
	 && $rotated != ($Priv(userSide) eq "b")} {
		RotateBoard
		set Priv(rotated) 1
	}
	::scidb::game::subscribe board $Priv(pos) [namespace current]::Update
	::scidb::db::subscribe gameClose [namespace current]::GameClosed
	::scidb::db::subscribe gameSwitch [namespace current]::GameSwitched
	set Priv(active) 1
	set Priv(pendingMove) {}
	set Priv(state) [expr {$Priv(observing) ? "observing" : "playing"}]
	SetClocks $style
	ShowView game
	UpdateGameButtons
	UpdateBoardInput
	DrawNames
	StatusForTurn
	after cancel $Priv(inputAfter)
	set Priv(inputAfter) [after idle [namespace code [list SettledBoardInput $Priv(pos)]]]
	StartTick
}


# gameNew/import has idle board setup which can re-enable input after the
# first snapshot. Reassert the mode once that setup has settled; Update is
# still the rollback guard throughout the transient.
proc ::ics::SettledBoardInput {position} {
	variable Priv
	set Priv(inputAfter) {}
	if {$Priv(active) && $position == $Priv(pos)} { UpdateBoardInput }
}


# A headers-only import is also the tag setter for an in-memory game. A
# mid-game observation gets SetUp/FEN and an empty movetext; its base ply is
# kept separately because mainline length alone then starts at zero.
proc ::ics::BoardPgn {info style setup result} {
	set tags [list \
		[format {[Event "%s"]} [PgnTag "FICS [dict get $info rated] [dict get $info type] game"]] \
		{[Site "freechess.org"]} \
		[format {[Date "%s"]} [clock format [clock seconds] -format {%Y.%m.%d}]] \
		{[Round "?"]} \
		[format {[White "%s"]} [PgnTag [dict get $info white]]] \
		[format {[Black "%s"]} [PgnTag [dict get $info black]]] \
	]
	foreach {key tag} {whiteRating WhiteElo blackRating BlackElo} {
		if {[dict exists $info $key] && [string is digit -strict [dict get $info $key]]} {
			lappend tags [format {[%s "%s"]} $tag [dict get $info $key]]
		}
	}
	lappend tags [format {[TimeControl "%d+%d"]} \
		[expr {[dict get $info minutes] * 60}] [dict get $info increment]]
	if {$setup} {
		lappend tags {[SetUp "1"]} [format {[FEN "%s"]} [dict get $style fen]]
	}
	lappend tags [format {[Result "%s"]} $result]
	return "[join $tags \n]\n\n$result\n"
}


proc ::ics::PgnTag {value} {
	return [string map [list \\ \\\\ \" \\\"] $value]
}


proc ::ics::ImportGame {pos pgn} {
	::scidb::game::import $pos $pgn ::ics::ImportLog {} -encoding utf-8
}


proc ::ics::ImportLog {_ args} { return }


proc ::ics::Resync {style} {
	variable Priv
	if {!$Priv(active)} { return }
	set info $Priv(gameInfo)
	set pgn [BoardPgn $info $style 1 *]
	set Priv(busy) 1
	set code [catch { ImportGame $Priv(pos) $pgn } err]
	set Priv(busy) 0
	if {$code} {
		catch { ::debuglog::log ics "resync import failed: $err" }
		return
	}
	::scidb::game::go end
	set Priv(basePly) [dict get $style ply]
	set Priv(serverPly) [dict get $style ply]
	set Priv(pendingMove) {}
	set Priv(relation) [dict get $style relation]
	SetClocks $style
	UpdateBoardInput
	DrawNames
	DrawClocks
	StatusForTurn
}


proc ::ics::BoardPly {} {
	variable Priv
	if {[catch { ::scidb::game::query mainline } plies]} { return $Priv(basePly) }
	return [expr {$Priv(basePly) + [llength $plies]}]
}


proc ::ics::Update {position cmd data promoted} {
	variable Priv
	variable mc

	if {!$Priv(active) || $Priv(busy) || $position != $Priv(pos)} { return }
	if {$cmd ne "move"} { return }
	if {[llength $data] && ![lindex $data end]} { return }
	if {![::scidb::game::position atEnd?] || ![::scidb::game::position isMainline?]} {
		RejectMove $mc::NotAtEnd 0
		return
	}
	if {$Priv(observing)} {
		RejectMove $mc::ReadOnly 0
		return
	}
	if {$Priv(relation) != 1 || $Priv(state) ne "playing"} {
		RejectMove $mc::NotYourTurn 0
		return
	}

	set san [::scidb::game::query move]
	regsub {[+#!?]+$} $san {} san
	if {$san eq ""} {
		RejectMove $mc::NotAtEnd 0
		return
	}
	set Priv(pendingMove) $san
	set Priv(relation) -1
	UpdateBoardInput
	Status [format $mc::WaitingMove [OpponentName]]
	Send $san
}


proc ::ics::UserMove {san} {
	variable Priv
	if {!$Priv(active) || $Priv(observing) || $Priv(relation) != 1 || $Priv(state) ne "playing"} {
		return 0
	}
	if {![::scidb::game::position atEnd?] || ![::scidb::game::position isMainline?]} { return 0 }
	set before [BoardPly]
	::move::addMove menu $san
	return [expr {[BoardPly] > $before}]
}


proc ::ics::RejectMove {why myMoveAgain} {
	variable Priv
	variable mc

	Busy on
	catch { ::scidb::game::go -1; ::scidb::game::strip truncate }
	Busy off
	set Priv(pendingMove) {}
	if {$myMoveAgain && !$Priv(observing)} { set Priv(relation) 1 }
	UpdateBoardInput
	Status $why
}


proc ::ics::OpponentName {} {
	variable Priv
	if {$Priv(userSide) eq "w"} { return [dict get $Priv(gameInfo) black] }
	return [dict get $Priv(gameInfo) white]
}


proc ::ics::StatusForTurn {} {
	variable Priv
	variable mc
	if {!$Priv(active) || $Priv(state) eq "over"} { return }
	if {$Priv(observing)} {
		Status [format $mc::Observing [dict get $Priv(gameInfo) white] [dict get $Priv(gameInfo) black]]
	} elseif {$Priv(relation) == 1} {
		Status $mc::YourMove
	} else {
		Status [format $mc::WaitingMove [OpponentName]]
	}
}


proc ::ics::BoardInput {on} {
	if {$on eq "on"} { ::move::enable } else { ::move::disable }
}


proc ::ics::UpdateBoardInput {} {
	variable Priv
	if {$Priv(active) && ($Priv(observing) || ($Priv(relation) != 1 && $Priv(state) ne "over"))} {
		BoardInput off
	} else {
		BoardInput on
	}
}


proc ::ics::Busy {on} {
	variable Priv
	set Priv(busy) [expr {$on eq "on" ? 1 : 0}]
}


proc ::ics::GameClosed {position} {
	variable Priv
	if {$Priv(active) && $position == $Priv(pos)} { LeaveBoard }
}


proc ::ics::GameSwitched {oldPos newPos} {
	variable Priv
	if {$Priv(active) && $newPos != $Priv(pos)} { LeaveBoard }
}


proc ::ics::LeaveBoard {} {
	variable Priv
	if {$Priv(active) && !$Priv(observing) && $Priv(state) eq "playing"} { Send resign }
	FinishBoard
	if {$Priv(loggedIn)} {
		set Priv(state) lobby
		ShowView lobby
	}
}


proc ::ics::FinishBoard {} {
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
	if {[info exists Priv(rotated)] && $Priv(rotated)} {
		RotateBoard
		set Priv(rotated) 0
	}
	BoardInput on
}


proc ::ics::RotateBoard {} {
	catch { ::application::board::Rotate $::application::board::Vars(widget:frame) }
}


# ======================================================================
# Game commands and result
# ======================================================================

proc ::ics::Resign {} {
	variable Priv
	if {$Priv(active) && !$Priv(observing) && $Priv(state) eq "playing"} { Send resign }
}


proc ::ics::OfferDraw {} {
	variable Priv
	if {$Priv(active) && !$Priv(observing) && $Priv(state) eq "playing"} { Send draw }
}


proc ::ics::Abort {} {
	variable Priv
	if {$Priv(active) && !$Priv(observing) && $Priv(state) eq "playing"} { Send abort }
}


proc ::ics::EndGame {result reason} {
	variable Priv
	variable mc
	if {!$Priv(active) || $Priv(state) eq "over"} { return }
	set Priv(state) over
	set Priv(ticking) 0
	after cancel $Priv(tick)
	set Priv(tick) {}
	if {[catch { StoreResult $result } err]} {
		catch { ::debuglog::log ics "StoreResult $result failed: $err" }
	}
	UpdateBoardInput
	UpdateGameButtons
	DrawClocks
	Status [format $mc::GameOver $result $reason]
}


proc ::ics::StoreResult {result} {
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


proc ::ics::UpdateGameButtons {} {
	variable Priv
	if {![DialogExists] || ![info exists Priv(widget:resign)]} { return }
	if {$Priv(observing) || $Priv(state) ne "playing"} {
		foreach key {resign draw abort} { $Priv(widget:$key) state disabled }
	} else {
		foreach key {resign draw abort} { $Priv(widget:$key) state !disabled }
	}
	if {$Priv(state) eq "over" || $Priv(observing)} {
		$Priv(widget:back) state !disabled
		$Priv(widget:ok) state !disabled
	} else {
		$Priv(widget:back) state disabled
		$Priv(widget:ok) state disabled
	}
}


proc ::ics::BackToLobby {} {
	variable Priv
	if {!$Priv(loggedIn)} { ShowView connect; return }
	if {$Priv(active) && $Priv(observing) && $Priv(state) ne "over"} { Send unobserve }
	FinishBoard
	set Priv(state) lobby
	ShowView lobby
}


# ======================================================================
# Clocks: server snapshots plus local countdown for the side to move
# ======================================================================

proc ::ics::SetClocks {style} {
	variable Priv
	set Priv(clock:w) [dict get $style whiteClock]
	set Priv(clock:b) [dict get $style blackClock]
	set Priv(clockStm) [dict get $style stm]
	set Priv(ticking) [expr {[dict get $style ticking] && $Priv(state) ni {over offline}}]
	set Priv(clockAt) [clock milliseconds]
}


proc ::ics::Remaining {colour now} {
	variable Priv
	set ms $Priv(clock:$colour)
	if {$Priv(ticking) && $Priv(clockStm) eq $colour} {
		set ms [expr {$ms - ($now - $Priv(clockAt))}]
	}
	return $ms
}


proc ::ics::StartTick {} {
	variable Priv
	variable TickInterval
	after cancel $Priv(tick)
	if {$Priv(active) && $Priv(state) ne "over"} {
		set Priv(tick) [after $TickInterval [namespace code Tick]]
	}
}


proc ::ics::Tick {} {
	variable Priv
	variable TickInterval
	set Priv(tick) {}
	if {!$Priv(active) || $Priv(state) eq "over"} { return }
	DrawClocks
	set Priv(tick) [after $TickInterval [namespace code Tick]]
}


proc ::ics::DrawNames {} {
	variable Priv
	variable mc
	if {![DialogExists] || ![info exists Priv(widget:white)]} { return }
	foreach {colour key widget} {w white white b black black} {
		set name [dict get $Priv(gameInfo) $key]
		set ratingKey ${key}Rating
		if {[dict exists $Priv(gameInfo) $ratingKey] && [dict get $Priv(gameInfo) $ratingKey] ne ""} {
			append name " ([dict get $Priv(gameInfo) $ratingKey])"
		}
		$Priv(widget:$widget) configure -text "[set mc::[expr {$key eq "white" ? "WhiteClock" : "BlackClock"}]]: $name"
	}
}


proc ::ics::DrawClocks {} {
	variable Priv
	variable mc
	if {![DialogExists] || ![info exists Priv(widget:whiteclock)]} { return }
	set now [clock milliseconds]
	foreach colour {w b} {
		set widget [expr {$colour eq "w" ? "whiteclock" : "blackclock"}]
		$Priv(widget:$widget) configure -text [FormatClock [expr {max(0, [Remaining $colour $now])}]]
		set active [expr {$Priv(ticking) && $Priv(clockStm) eq $colour}]
		$Priv(widget:$widget) configure -font $::font::text([expr {$active ? "text:bold" : "text:normal"}])
	}
}


proc ::ics::FormatClock {ms} {
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


proc ::ics::WriteOptions {chan} {
	::options::writeItem $chan [namespace current]::Options
}

::options::hookWriter ::ics::WriteOptions


# ======================================================================
# Pure protocol parsers
# ======================================================================

# Remove CR, a run of FICS prompts, telnet option triplets and bytes which
# are not valid UTF-8. Valid non-ASCII names and server messages survive.
proc ::ics::cleanLine {line} {
	regsub -all "\xff(\xfb|\xfc|\xfd|\xfe)." $line {} line
	regsub -all "\r" $line {} line
	set line [cleanUtf8 $line]
	while {[string first {fics% } $line] == 0} {
		set line [string range $line 6 end]
	}
	return $line
}


proc ::ics::cleanUtf8 {line} {
	set out {}
	set length [string length $line]
	for {set i 0} {$i < $length} {incr i} {
		set ch [string index $line $i]
		scan $ch %c code
		if {$code < 128} {
			# Telnet's option byte is ASCII 1 after its IAC/command bytes.
			if {$code == 9 || $code >= 32} { append out $ch }
			continue
		}
		if {$code >= 0xc2 && $code <= 0xdf} {
			set count 2
		} elseif {$code >= 0xe0 && $code <= 0xef} {
			set count 3
		} elseif {$code >= 0xf0 && $code <= 0xf4} {
			set count 4
		} else {
			continue
		}
		if {$i + $count > $length} { continue }
		set valid 1
		set second -1
		for {set j 1} {$j < $count} {incr j} {
			scan [string index $line [expr {$i + $j}]] %c next
			if {$j == 1} { set second $next }
			if {$next < 0x80 || $next > 0xbf} { set valid 0; break }
		}
		if {!$valid} { continue }
		if {($code == 0xe0 && $second < 0xa0) || ($code == 0xed && $second > 0x9f)
			|| ($code == 0xf0 && $second < 0x90) || ($code == 0xf4 && $second > 0x8f)} {
			continue
		}
		set bytes [string range $line $i [expr {$i + $count - 1}]]
		append out [encoding convertfrom utf-8 $bytes]
		incr i [expr {$count - 1}]
	}
	return $out
}


# Parse one style 12 snapshot into named fields plus FEN and absolute ply.
proc ::ics::parseStyle12 {line} {
	set line [cleanLine $line]
	if {[lindex $line 0] eq "<12>"} { set line [lrange $line 1 end] }
	set f [split $line]
	if {[llength $f] < 32} { return {} }
	for {set rank 0} {$rank < 8} {incr rank} {
		if {![regexp {^[-prnbqkPRNBQK]{8}$} [lindex $f $rank]]} { return {} }
	}
	foreach index {9 10 11 12 13 14 15 18 19 20 21 22 23 24 25 29 30 31} {
		if {![string is integer -strict [lindex $f $index]]} { return {} }
	}
	if {[lindex $f 8] ni {W B}} { return {} }
	set stm [expr {[lindex $f 8] eq "B" ? "b" : "w"}]
	set castling {}
	foreach {index letter} {10 K 11 Q 12 k 13 q} {
		if {[lindex $f $index]} { append castling $letter }
	}
	if {$castling eq ""} { set castling - }
	set epfile [lindex $f 9]
	if {$epfile >= 0 && $epfile <= 7} {
		set ep [format "%c%s" [expr {97 + $epfile}] [expr {$stm eq "b" ? 3 : 6}]]
	} else {
		set ep -
	}
	set board [styleBoard [lrange $f 0 7]]
	set moveNumber [lindex $f 25]
	if {$moveNumber < 1} { return {} }

	set style [dict create \
		board $board \
		stm $stm \
		doublePawn $epfile \
		castling $castling \
		enPassant $ep \
		halfmove [lindex $f 14] \
		game [lindex $f 15] \
		white [lindex $f 16] \
		black [lindex $f 17] \
		relation [lindex $f 18] \
		minutes [lindex $f 19] \
		increment [lindex $f 20] \
		whiteMaterial [lindex $f 21] \
		blackMaterial [lindex $f 22] \
		whiteClock [lindex $f 23] \
		blackClock [lindex $f 24] \
		moveNumber $moveNumber \
		verbose [lindex $f 26] \
		timeTaken [lindex $f 27] \
		san [lindex $f 28] \
		flip [lindex $f 29] \
		ticking [lindex $f 30] \
		lag [lindex $f 31] \
	]
	dict set style fen [list $board $stm $castling $ep [lindex $f 14] $moveNumber]
	dict set style ply [expr {2 * ($moveNumber - 1) + ($stm eq "b")}]
	return $style
}


proc ::ics::styleBoard {ranks} {
	set out {}
	foreach rank $ranks {
		set converted {}
		set empty 0
		foreach ch [split $rank {}] {
			if {$ch eq "-"} {
				incr empty
			} else {
				if {$empty} { append converted $empty; set empty 0 }
				append converted $ch
			}
		}
		if {$empty} { append converted $empty }
		lappend out $converted
	}
	return [join $out /]
}


proc ::ics::parseSeek {line} {
	set line [cleanLine $line]
	if {![regexp {^<s>\s+([0-9]+)\s+(.*)$} $line -> index fields]} { return {} }
	set values [dict create]
	foreach field [split $fields] {
		if {[regexp {^([^=]+)=(.*)$} $field -> key value]} { dict set values $key $value }
	}
	foreach key {w ti rt t i r tp c rr a f} {
		if {![dict exists $values $key]} { return {} }
	}
	if {[catch { scan [dict get $values ti] %x flags }]} { set flags 0 }
	return [dict create \
		index $index \
		name [dict get $values w] \
		title [dict get $values ti] \
		computer [expr {($flags & 0x02) != 0}] \
		rating [dict get $values rt] \
		time [dict get $values t] \
		minutes [dict get $values t] \
		inc [dict get $values i] \
		increment [dict get $values i] \
		rated [dict get $values r] \
		type [dict get $values tp] \
		color [dict get $values c] \
		range [dict get $values rr] \
		automatic [dict get $values a] \
		formula [dict get $values f] \
	]
}


proc ::ics::parseGameStart {line} {
	set line [cleanLine $line]
	if {[regexp {^Creating: (\S+) \(([^)]*)\) (\S+) \(([^)]*)\) (rated|unrated) (\S+) ([0-9]+) ([0-9]+)$} \
		$line -> white whiteRating black blackRating rated type minutes increment]} {
		return [dict create game -1 white $white whiteRating $whiteRating black $black \
			blackRating $blackRating rated $rated type $type minutes $minutes increment $increment observing 0]
	}
	if {[regexp {^\{Game ([0-9]+) \((\S+) vs\. (\S+)\) Creating (rated|unrated) (\S+) match\.\}$} \
		$line -> game white black rated type]} {
		return [dict create game $game white $white black $black rated $rated type $type observing 0]
	}
	if {[regexp {^Game ([0-9]+): (\S+) \(([^)]*)\) (\S+) \(([^)]*)\) (rated|unrated) (\S+) ([0-9]+) ([0-9]+)$} \
		$line -> game white whiteRating black blackRating rated type minutes increment]} {
		return [dict create game $game white $white whiteRating $whiteRating black $black \
			blackRating $blackRating rated $rated type $type minutes $minutes increment $increment observing 1]
	}
	return {}
}


proc ::ics::parseGameEnd {line} {
	set line [cleanLine $line]
	if {![regexp {^\{Game ([0-9]+) \((\S+) vs\. (\S+)\) (.*)\}\s+(\*|1-0|0-1|1/2-1/2)$} \
		$line -> game white black reason result]} {
		return {}
	}
	return [dict create game $game white $white black $black reason $reason result $result]
}

# vi:set ts=3 sw=3:
