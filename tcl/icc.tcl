# ======================================================================
# Play on the Internet Chess Club (Training > Play Online (ICC)).
# A nonblocking socket owns the login dialogue, live seek list and style
# 12 board stream. Games use separate tabs in the Online window.
#
#   ::icc::open .application       connect -> lobby -> game panel
#   ::icc::Connect ?password?      programmatic connect using Options
#   ::icc::UserMove <san>          board move entry point used by tests
#
# Passwords are transient entry values: they are neither options nor log
# lines. Protocol parsers are pure and covered by tests/test_icc_protocol.tcl;
# its socket server is loopback-only. No test connects to chessclub.com.
# ======================================================================

::util::source icc

package require Tcl 8.5
package require Tk 8.5

namespace eval ::icc {
namespace eval mc {

set Title					"Play Online (ICC)"
set Handle					"Handle:"
set Password				"Password:"
set Server					"Server:"
set Port					"Port:"
set GuestDetail				"ICC (chessclub.com) supports guest and registered accounts. Port 23 is an alternative to 5000. Leave the handle empty to play as a guest, or enter the handle and password of your own ICC account. Chesswiz connects straight to chessclub.com; it has no server of its own."
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
set DrawOffered			"Your opponent offers a draw."
set TakebackOffered		"Your opponent asks to take back the last move."
set GameOver				"Game over: %s (%s)."
set ImportFailed			"Could not put the server position on the board: %s"
set NoClockTime				"\u2014"


} ;# namespace mc

# The password deliberately has no entry here. Host, port, handle and the
# seek defaults survive through the ordinary options writer.
array set Options {
	host			chessclub.com
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
	offer			{}
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

} ;# namespace icc


# ======================================================================
# The dialog
# ======================================================================

proc ::icc::open {parent} {
	variable Priv
	variable Options
	variable mc

	foreach number [::application::analysis::Running] {
		::application::analysis::stopEngine $number
	}

	# The lobby and server console are a tab of the Chesswiz Online window.
	set dlg [::online::window::tab icc ICC]
	::online::window::select icc
	if {[info exists Priv(widget:connect)] && [winfo exists $Priv(widget:connect)]} {
		return $dlg
	}
	set Priv(dialog) $dlg

	set top [ttk::frame $dlg.top]
	pack $top -fill both -expand yes

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

    set extra [ttk::frame $l.icc]
    set row 0
    foreach {name label} {
        target {User / game / channel:} message {Message:}
    } {
        ttk::label $extra.${name}Label -text $label
        ttk::entry $extra.$name -textvariable [namespace current]::Priv(dlg:$name)
        grid $extra.${name}Label -row $row -column 0 -sticky w
        grid $extra.$name -row $row -column 1 -sticky ew
        incr row
        set Priv(dlg:$name) {}
    }
    set row 4
    set column 0
    foreach {name label callback} {
        match Challenge ChallengeDialog accept {Accept match} AcceptMatch
        decline {Decline match} DeclineMatch observe Observe ObserveDialog
        tell Tell TellDialog channel {Channel tell} ChannelDialog
        adjourn Adjourn Adjourn examine Examine Examine
    } {
        ttk::button $extra.$name -text $label -command [namespace code $callback]
        grid $extra.$name -row $row -column $column -sticky ew
        if {[incr column] == 2} { set column 0; incr row }
    }
    pack $extra -fill x

	set buttons [ttk::frame $dlg.buttons]
	ttk::button $buttons.ok
	ttk::button $buttons.cancel -text $mc::Close -command [namespace code Close]
	pack $buttons.ok $buttons.cancel -side left -padx [list 0 $::theme::padx]
	pack $buttons -side bottom -anchor w -pady [list $::theme::pady 0]
	ttk::label $dlg.status -wraplength 600 -justify left
	pack $dlg.status -side bottom -fill x -pady [list $::theme::pady 0]
	set Priv(widget:status) $dlg.status
	set Priv(widget:ok) $buttons.ok
	set Priv(widget:cancel) $buttons.cancel
	set Priv(widget:back) $buttons.ok

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
	return $dlg
}


proc ::icc::ShowView {view} {
	variable Priv
	variable mc

	if {![DialogExists]} { return }
	# Games run in their own tabs; the lobby stays usable meanwhile.
	if {$view eq "game"} { set view lobby }
	foreach name {connect lobby} {
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
	}
	Status $Priv(statusText)
}


proc ::icc::ConnectFromDialog {} {
	variable Priv
	Connect $Priv(dlg:password)
}


proc ::icc::DialogExists {} {
	variable Priv
	return [expr {[string length $Priv(dialog)] && [winfo exists $Priv(dialog)]}]
}


proc ::icc::Status {text} {
	variable Priv
	set Priv(statusText) $text
	if {[ViewExists]} { ::online::view::status $Priv(view) $text }
	if {[DialogExists] && [info exists Priv(widget:status)]} {
		$Priv(widget:status) configure -text $text
	}
}


# ======================================================================
# Socket and login
# ======================================================================

proc ::icc::Connect {{password ""}} {
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
	if {[regexp {[\r\n ]} $handle] || $host eq "" || ![string is integer -strict $port] || $port < 1 || $port > 65535} {
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
    set Priv(refreshPending) 0
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


proc ::icc::Connected {} {
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


proc ::icc::OnConnectTimeout {} {
	variable Priv
	variable mc
	set Priv(connectTimer) {}
	if {!$Priv(loggedIn)} { Disconnect $mc::ConnectTimeout }
}


proc ::icc::Disconnect {{why ""}} {
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
	if {[info exists Priv(drain)] && $Priv(drain) ne ""} {
		after cancel $Priv(drain)
		set Priv(drain) {}
	}
	set Priv(loggedIn) 0
	set Priv(state) offline
	set Priv(handle) {}
	set Priv(loginPassword) {}
	if {[info exists Priv(dlg:password)]} { set Priv(dlg:password) {} }
	set Seeks [dict create]
    set ::icc::Matches {}
    set Priv(match) {}
	FinishBoard
	if {$why ne ""} { Status $why }
	if {[DialogExists]} { ShowView connect }
}


proc ::icc::Close {} {
	variable Priv
	variable mc

	if {$Priv(socket) ne ""} { Send quit }
	Disconnect
	set Priv(loginPassword) {}
	if {[info exists Priv(dlg:password)]} { set Priv(dlg:password) {} }
	::online::window::closeTab icc
	set Priv(dialog) {}
}


# Send a complete command. Never pass outgoing lines to LogText or debuglog:
# during login the line can be the password.
proc ::icc::Send {line} {
	variable Priv
	if {$Priv(socket) eq "" || [regexp {[\r\n]} $line]} { return 0 }
	if {[catch {
		# a bare newline: chessclub.com reads "\r\n" at the guest prompt as
		# two answers and then waits for ever at "Press return"
		puts -nonewline $Priv(socket) [encoding convertto utf-8 "$line\n"]
		flush $Priv(socket)
	} err]} {
		Disconnect $err
		return 0
	}
	return 1
}


# Input is read in bounded batches and at most MaxLines lines are handled
# per event (the rest goes on from the event loop, so clocks and redraws
# keep up with a burst); a line longer than MaxLine is dropped.
namespace eval ::icc {
	variable MaxRead 65536
	variable MaxLines 200
	variable MaxLine 65536
}

proc ::icc::OnReadable {} {
	variable Priv
	variable MaxRead

	set sock $Priv(socket)
	if {$sock eq ""} { return }
	if {[catch {
		append Priv(buffer) [read $sock $MaxRead]
		Drain $sock
	} err]} {
		catch { ::debuglog::log ics "socket processing failed: $err" }
		Disconnect $err
	}
}


proc ::icc::Resume {sock} {
	variable Priv

	set Priv(drain) {}
	if {$Priv(socket) ne $sock} { return }
	if {[catch { Drain $sock } err]} {
		catch { ::debuglog::log ics "socket processing failed: $err" }
		Disconnect $err
	}
}


proc ::icc::Drain {sock} {
    variable Priv
    variable MaxLines
    set events [extractFrames Priv(buffer) $MaxLines]
    foreach event $events {
        lassign $event kind payload
        switch -- $kind {
            datagram { HandleDatagram $payload }
            reply { LogText [::ics::cleanLine $payload] }
            text { ProcessLine [::ics::cleanLine $payload] }
        }
        if {$Priv(socket) ne $sock} { return }
    }
    if {[llength $events] == $MaxLines} {
        set Priv(drain) [after 0 [namespace code [list Resume $sock]]]
    } else { ProcessPrompt }
    if {[string length $Priv(buffer)] > 131072} { Disconnect "ICC input exceeds limit"; return }
    if {$Priv(socket) eq $sock && [eof $sock]} { Disconnect $::icc::mc::Disconnected }
}


proc ::icc::ProcessPrompt {} {
	variable Priv
	variable mc

	if {$Priv(state) ni {connecting login} || $Priv(buffer) eq "" || [string first "\x19" $Priv(buffer)] >= 0} { return }
	if {[AnswerPrompt [::ics::cleanLine $Priv(buffer)]]} { set Priv(buffer) {} }
}


# Answers a login prompt ending <text>; whether it was one.
proc ::icc::AnswerPrompt {text} {
    variable Priv
    if {[regexp -nocase {login:\s*$} $text]} {
        Send "level2settings=[settings] [expr {$Priv(guest) ? "guest" : $Priv(loginHandle)}]"
        return 1
    }
    if {[regexp -nocase {password:\s*$} $text]} {
        set password $Priv(loginPassword)
        set Priv(loginPassword) {}
        if {[info exists Priv(dlg:password)]} { set Priv(dlg:password) {} }
        Send $password
        return 1
    }
    return 0
}


proc ::icc::ProcessLine {line} {
    variable Priv
    variable mc
    if {$line eq ""} { return }
    if {$Priv(state) in {connecting login} && [AnswerPrompt $line]} { return }
    if {[string match -nocase {*invalid password*} $line]} {
        Disconnect $mc::InvalidPassword
        return
    }
    if {[string match {<12> *} $line]} {
        set Priv(refreshPending) 0
        HandleStyle12 [::ics::parseStyle12 $line]
        return
    }
    LogText $line
}


proc ::icc::StandardSeek {seek} {
	return [expr {[dict get $seek type] in {blitz lightning standard untimed}}]
}


proc ::icc::RefreshSeeks {} {
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


proc ::icc::PlaySelected {} {
	variable Priv
	if {![DialogExists]} { return }
	set selection [$Priv(widget:tree) selection]
	if {[llength $selection]} { Play [lindex $selection 0] }
}


proc ::icc::Play {{index ""}} {
	variable Priv
	variable Seeks
	if {$index eq "" || ![dict exists $Seeks $index]} { return 0 }
	return [Send "play $index"]
}


proc ::icc::Seek {} {
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
	set command "seek $minutes $increment [expr {$rated ? "rated" : "unrated"}]"
	if {$colour in {white black}} { append command " $colour" }
	return [Send $command]
}


proc ::icc::Unseek {} { return [::icc::Send unseek] }
proc ::icc::Watch {} { return [::icc::Send games] }


proc ::icc::GuestControls {} {
	variable Priv
	if {![DialogExists] || ![info exists Priv(widget:rated)]} { return }
	if {$Priv(guest)} {
		set Priv(dlg:rated) 0
		$Priv(widget:rated) state disabled
	} else {
		$Priv(widget:rated) state !disabled
	}
}


proc ::icc::SendRaw {} {
	variable Priv
	if {![DialogExists]} { return 0 }
	set line [string trim $Priv(dlg:raw)]
	set Priv(dlg:raw) {}
	if {$line eq ""} { return 0 }
	return [Send $line]
}


proc ::icc::LogText {line} {
	variable Priv
	if {[string trim $line] eq ""} { return }
	lappend Priv(textLines) $line
	if {[llength $Priv(textLines)] > 200} {
		set Priv(textLines) [lrange $Priv(textLines) end-199 end]
	}
	RestoreText
}


proc ::icc::RestoreText {} {
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

proc ::icc::HandleStyle12 {style} {
	variable Priv
	variable mc

	if {$style eq ""} { return }
	set number [dict get $style game]
	if {!$Priv(active) || $number != $Priv(gameNumber) || ![ViewExists]} {
		if {[catch { StartBoard $style } err]} {
			catch { ::debuglog::log ics "game start failed: $err" }
			FinishBoard
			Status [format $mc::ImportFailed $err]
			return
		}
	}
	if {!$Priv(active)} { return }

	set before [BoardPly]
	set serverPly [dict get $style ply]
	set delta [expr {$serverPly - $before}]
	set san [dict get $style san]
	set ok 1
	if {$delta == 1 || ($delta == 0 && [::online::view::pending $Priv(view)] ne "")} {
		# A new move, or the echo of ours.
		if {$san eq "" || $san eq "none"} {
			set ok 0
		} else {
			regsub {[+#!?]+$} $san {} san
			set ok [::online::view::addMove $Priv(view) $san]
		}
	} elseif {$delta != 0} {
		set ok 0
	}
	# Every snapshot must match the board; anything else adopts the server's.
	if {!$ok || [lindex [::online::view::fen $Priv(view)] 0] ne [dict get $style board]} {
		Resync $style
	}
	set Priv(serverPly) $serverPly
	set Priv(relation) [dict get $style relation]
	set Priv(pendingMove) {}
	SetClocks $style
	UpdateGameButtons
	StatusForTurn
}

proc ::icc::StartBoard {style} {
	variable Priv
	variable mc

	FinishBoard
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
	set Priv(startFen) [dict get $style fen]
	set Priv(finalPgn) {}

	# Each game, played or watched, has its own tab with its own board.
	set title [expr {$Priv(observing) \
		? "ICC: [dict get $info white] - [dict get $info black]" : "ICC: [OpponentName]"}]
	set Priv(view) [::online::window::gameTab icc:$Priv(gameNumber) $title \
		[namespace code ViewAction] $Priv(userSide)]
	::online::view::setGame $Priv(view) [Card white] [Card black] $Priv(startFen) {}
	set Priv(active) 1
	set Priv(pendingMove) {}
	set Priv(offer) {}
	set Priv(state) [expr {$Priv(observing) ? "observing" : "playing"}]
	SetClocks $style
	ShowView game
	UpdateGameButtons
	StatusForTurn
}


proc ::icc::Card {key} {
	variable Priv
	set card [dict create name [dict get $Priv(gameInfo) $key]]
	if {[dict exists $Priv(gameInfo) ${key}Rating]} {
		dict set card rating [dict get $Priv(gameInfo) ${key}Rating]
	}
	return $card
}


proc ::icc::ViewExists {} {
	variable Priv
	return [expr {[info exists Priv(view)] && [::online::view::exists $Priv(view)]}]
}


# The game view sends the user's moves and button presses here.
proc ::icc::ViewAction {action args} {
	variable Priv
	variable mc
	switch -- $action {
		move {
			lassign $args uci san
			if {!$Priv(active) || $Priv(observing) || $Priv(relation) != 1 || $Priv(state) ne "playing"} {
				::online::view::rejectMove $Priv(view) $mc::NotYourTurn
				return
			}
			regsub {[+#!?]+$} $san {} san
			set Priv(pendingMove) $san
			set Priv(relation) -1
			Status [format $mc::WaitingMove [OpponentName]]
			Send $san
		}
		resign	{ Resign }
		draw		{ OfferDraw }
		abort		{ Abort }
		takeback	{ if {$Priv(active) && !$Priv(observing) && $Priv(state) eq "playing"} { Send "takeback 1" } }
		accept	{ if {$Priv(offer) ne ""} { Send accept; set Priv(offer) {}; UpdateGameButtons } }
		decline	{ if {$Priv(offer) ne ""} { Send decline; set Priv(offer) {}; UpdateGameButtons } }
		chat {
			set text [lindex $args 0]
			# Players talk with "say"; observers kibitz to the game.
			Send "[expr {$Priv(observing) ? "kibitz" : "say"}] $text"
			::online::view::chat $Priv(view) $Priv(handle) $text
		}
		analyse	{ Analyse }
		close {
			if {$Priv(active) && $Priv(state) eq "playing"} { return }
			set number $Priv(gameNumber)
			BackToLobby
			::online::window::closeTab icc:$number
			::online::window::select icc
		}
	}
}


proc ::icc::Analyse {} {
	variable Priv
    if {![ViewExists]} { return }
	if {$Priv(finalPgn) eq ""} { StoreResult * }
	if {$Priv(finalPgn) eq ""} { return }
	::menu::gameNew .application
	ImportGame [::scidb::game::current] $Priv(finalPgn)
	::scidb::game::go end
	raise .application
}

# gameNew/import has idle board setup which can re-enable input after the
# first snapshot. Reassert the mode once that setup has settled; Update is
# still the rollback guard throughout the transient.
# A headers-only import is also the tag setter for an in-memory game. A
# mid-game observation gets SetUp/FEN and an empty movetext; its base ply is
# kept separately because mainline length alone then starts at zero.
proc ::icc::BoardPgn {info style setup result} {
	set tags [list \
		[format {[Event "%s"]} [PgnTag "ICC [dict get $info rated] [dict get $info type] game"]] \
		{[Site "chessclub.com"]} \
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


proc ::icc::PgnTag {value} {
	return [string map [list \\ \\\\ \" \\\"] $value]
}


proc ::icc::ImportGame {pos pgn} {
	::scidb::game::import $pos $pgn ::icc::ImportLog {} -encoding utf-8
}


proc ::icc::ImportLog {_ args} { return }


proc ::icc::Resync {style} {
	variable Priv
	if {!$Priv(active) || ![ViewExists]} { return }
	set Priv(startFen) [dict get $style fen]
	::online::view::setGame $Priv(view) [Card white] [Card black] $Priv(startFen) {}
	set Priv(basePly) [dict get $style ply]
	set Priv(serverPly) [dict get $style ply]
	set Priv(pendingMove) {}
	set Priv(relation) [dict get $style relation]
}

proc ::icc::BoardPly {} {
	variable Priv
	if {![ViewExists]} { return $Priv(basePly) }
	return [expr {$Priv(basePly) + [llength [::online::view::ucis $Priv(view)]]}]
}

proc ::icc::UserMove {move} {
	variable Priv
	if {!$Priv(active) || $Priv(observing) || $Priv(relation) != 1 || $Priv(state) ne "playing"} {
		return 0
	}
	return [::online::view::play $Priv(view) $move]
}

proc ::icc::RejectMove {why myMoveAgain} {
	variable Priv
	set Priv(pendingMove) {}
	if {$myMoveAgain && !$Priv(observing)} { set Priv(relation) 1 }
	if {[ViewExists]} { ::online::view::rejectMove $Priv(view) $why }
	Status $why
}

proc ::icc::OpponentName {} {
	variable Priv
	if {$Priv(userSide) eq "w"} { return [dict get $Priv(gameInfo) black] }
	return [dict get $Priv(gameInfo) white]
}


proc ::icc::StatusForTurn {} {
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


proc ::icc::LeaveBoard {} {
	variable Priv
	if {$Priv(active) && !$Priv(observing) && $Priv(state) eq "playing"} { Send resign }
	FinishBoard
	if {$Priv(loggedIn)} {
		set Priv(state) lobby
		ShowView lobby
	}
}


proc ::icc::FinishBoard {} {
	variable Priv
    if {[ViewExists]} {
        ::online::view::clocks $Priv(view) $Priv(clock:w) $Priv(clock:b) $Priv(clockStm) 0
    }
	set Priv(active) 0
	set Priv(ticking) 0
	set Priv(pendingMove) {}
}

# ======================================================================
# Game commands and result
# ======================================================================

proc ::icc::Resign {} {
	variable Priv
	if {$Priv(active) && !$Priv(observing) && $Priv(state) eq "playing"} { Send resign }
}


proc ::icc::OfferDraw {} {
	variable Priv
	if {$Priv(active) && !$Priv(observing) && $Priv(state) eq "playing"} { Send draw }
}


proc ::icc::Abort {} {
	variable Priv
	if {$Priv(active) && !$Priv(observing) && $Priv(state) eq "playing"} { Send abort }
}


proc ::icc::EndGame {result reason} {
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
	UpdateGameButtons
	Status [format $mc::GameOver $result $reason]
	if {[ViewExists]} {
		::online::view::clocks $Priv(view) $Priv(clock:w) $Priv(clock:b) $Priv(clockStm) 0
		::online::view::result $Priv(view) [format $mc::GameOver $result $reason]
	}
}


proc ::icc::StoreResult {result} {
	variable Priv
	if {![ViewExists]} { return }
	set setup [expr {$Priv(startFen) ne "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"}]
	set pgn [BoardPgn $Priv(gameInfo) [dict create fen $Priv(startFen)] $setup $result]
	set tags [string range $pgn 0 [string first "\n\n" $pgn]]
	set moves [::online::view::pgn $Priv(view) {} $result]
	regsub -all -line {^\[.*\]\n} $moves {} moves
	set Priv(finalPgn) "$tags[string trimleft $moves \n]"
}

proc ::icc::UpdateGameButtons {} {
	variable Priv
	variable mc
	if {![ViewExists]} { return }
	set playing [expr {$Priv(active) && !$Priv(observing) && $Priv(state) eq "playing"}]
	::online::view::actions $Priv(view) [dict create resign $playing draw $playing \
		takeback $playing abort $playing]
	set text ""
	if {$playing && $Priv(offer) eq "draw"} {
		set text $mc::DrawOffered
	} elseif {$playing && $Priv(offer) eq "takeback"} {
		set text $mc::TakebackOffered
	} elseif {$playing && $Priv(offer) in {abort adjourn}} {
        set text "Your opponent offers to $Priv(offer) the game."
    }
	::online::view::offer $Priv(view) $text
}

proc ::icc::BackToLobby {} {
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

proc ::icc::SetClocks {style} {
	variable Priv
	set Priv(clock:w) [dict get $style whiteClock]
	set Priv(clock:b) [dict get $style blackClock]
	set Priv(clockStm) [dict get $style stm]
	set Priv(ticking) [expr {[dict get $style ticking] && $Priv(state) ni {over offline}}]
	set Priv(clockAt) [clock milliseconds]
	if {[ViewExists]} {
		::online::view::clocks $Priv(view) $Priv(clock:w) $Priv(clock:b) $Priv(clockStm) $Priv(ticking)
	}
}


proc ::icc::FormatClock {ms} {
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


proc ::icc::WriteOptions {chan} {
	::options::writeItem $chan [namespace current]::Options
}

::options::hookWriter ::icc::WriteOptions


# ICC level-2 framing is a byte protocol. Never run Tcl's list parser or
# subst/eval on server data. These pure helpers also run in standalone tclsh.
proc ::icc::settings {} {
    # 33 selects algebraic fields in DG_SEND_MOVES; 43 is isolated board.
    set enabled {0 15 16 17 18 19 20 24 25 26 27 28 29 30 31 33 34 36 43 50 51 56 101}
    set bits {}
    for {set i 0} {$i <= 101} {incr i} { append bits [expr {$i in $enabled ? 1 : 0}] }
    return $bits
}

# Consume complete text lines, datagrams and level-1 replies, preserving an
# incomplete frame (including a lone control-Y) for the next socket read.
proc ::icc::extractFrames {bufferName {limit 200}} {
    upvar 1 $bufferName buffer
    set events {}
    while {[llength $events] < $limit && $buffer ne ""} {
        set control [string first "\x19" $buffer]
        set newline [string first "\n" $buffer]
        if {$newline >= 0 && ($control < 0 || $newline < $control)} {
            lappend events [list text [string range $buffer 0 [expr {$newline-1}]]]
            set buffer [string range $buffer [expr {$newline+1}] end]
            continue
        }
        if {$control < 0} { break }
        if {$control > 0} {
            lappend events [list text [string range $buffer 0 [expr {$control-1}]]]
            set buffer [string range $buffer $control end]
            continue
        }
        if {[string length $buffer] < 2} { break }
        set opener [string index $buffer 1]
        if {$opener eq "("} {
            set close "\x19)"
            set kind datagram
        } elseif {$opener eq "\["} {
            set close "\x19\]"
            set kind reply
        } else {
            set buffer [string range $buffer 1 end]
            continue
        }
        set end [string first $close $buffer 2]
        if {$end < 0} { break }
        lappend events [list $kind [string range $buffer 2 [expr {$end-1}]]]
        set buffer [string range $buffer [expr {$end+2}] end]
    }
    return $events
}

proc ::icc::fields {payload} {
    set result {}
    set n [string length $payload]
    set i 0
    while {$i < $n} {
        while {$i < $n && [string is space [string index $payload $i]]} { incr i }
        if {$i == $n} { break }
        set ch [string index $payload $i]
        set quoted [expr {[string range $payload $i [expr {$i+1}]] eq "\x19\{"}]
        if {$ch eq "\{" || $quoted} {
            incr i [expr {$quoted ? 2 : 1}]
            set start $i
            set end [string first [expr {$quoted ? "\x19\}" : "\}"}] $payload $i]
            if {$end < 0} { error "unterminated ICC string" }
            lappend result [::ics::cleanUtf8 [string range $payload $start [expr {$end-1}]]]
            set i [expr {$end + ($quoted ? 2 : 1)}]
            if {$i < $n && ![string is space [string index $payload $i]]} { error "missing ICC field separator" }
        } else {
            set start $i
            while {$i < $n && ![string is space [string index $payload $i]]} { incr i }
            lappend result [::ics::cleanUtf8 [string range $payload $start [expr {$i-1}]]]
        }
    }
    return $result
}

proc ::icc::parseSeek {f} {
    # DG_SEEK: index name titles rating provisional wild rating-type time inc
    # rated color min-rating max-rating auto-accept formula fancy-time-control.
    if {[llength $f] < 16} { return {} }
    foreach i {0 3 4 5 7 8 9 11 12 13 14} {
        if {![string is integer -strict [lindex $f $i]]} { return {} }
    }
    if {[lindex $f 5] != 0} { return {} }
    return [dict create index [lindex $f 0] name [lindex $f 1] \
        rating [lindex $f 3] computer [expr {[string first C [lindex $f 2]] >= 0}] \
        time [lindex $f 7] inc [lindex $f 8] rated [expr {[lindex $f 9] ? "r" : "u"}] \
        type [lindex $f 6] color [lindex $f 10]]
}

proc ::icc::LoggedIn {name} {
    variable Priv
    variable mc
    set Priv(handle) $name
    if {$Priv(loggedIn)} { return }
    set Priv(loggedIn) 1
    set Priv(state) lobby
    set Priv(loginPassword) {}
    if {[info exists Priv(dlg:password)]} { set Priv(dlg:password) {} }
    after cancel $Priv(connectTimer)
    set Priv(connectTimer) {}
    ShowView lobby
    Status [format $mc::ConnectedAs $name]
    foreach command {{set level1 1} {set style 12} {set bell 0} {set interface Chesswiz} {set seek 1}} { Send $command }
}

proc ::icc::HandleDatagram {payload} {
    variable Priv
    variable Seeks
    if {[catch { fields $payload } parts] || ![llength $parts]} { return }
    set id [lindex $parts 0]
    set f [lrange $parts 1 end]
    # Optional fields are intentionally ignored. Malformed/truncated input
    # must never escape the socket callback or alter a different game.
    if {[catch { DispatchDatagram $id $f } error]} {
        LogText "Malformed ICC datagram $id"
    }
}

proc ::icc::DispatchDatagram {id f} {
    variable Priv
    variable Seeks
    variable Matches
    switch -- $id {
        0 { if {[llength $f] >= 2} { LoggedIn [lindex $f 0] } }
        50 {
            set seek [parseSeek $f]
            if {$seek ne ""} { dict set Seeks [dict get $seek index] $seek; RefreshSeeks }
        }
        51 { foreach index $f { catch { dict unset Seeks $index } }; RefreshSeeks }
        15 - 18 {
            if {[llength $f] < 10} { return }
            lassign $f game white black wild type rated wt wi bt bi
            if {$wild != 0} { LogText "Unsupported ICC variant $wild"; return }
            set Priv(gameInfo) [dict create game $game white $white black $black \
                type $type rated [expr {$rated ? "rated" : "unrated"}] \
                minutes $wt increment $wi observing [expr {$id == 18}]]
            foreach {index key} {13 whiteRating 14 blackRating} {
                if {[llength $f] > $index && [string is integer -strict [lindex $f $index]]} {
                    dict set Priv(gameInfo) $key [lindex $f $index]
                }
            }
            # Style 12 is authoritative for board state, orientation and ply.
            RequestSnapshot
        }
        16 {
            # game-number become-examined result-code score description
            if {[llength $f] < 5 || [lindex $f 0] ne $Priv(gameNumber)} { return }
            set score [lindex $f 3]
            if {$score in {1-0 0-1 1/2-1/2 *}} { EndGame $score [lindex $f 4] }
        }
        17 - 19 {
            if {[lindex $f 0] eq $Priv(gameNumber) && $Priv(active)} {
                if {$id == 17 && $Priv(state) ne "over"} { EndGame * "Game ended" }
                if {$id == 19} { FinishBoard; set Priv(state) lobby; ShowView lobby }
            }
        }
        26 {
            # game-number move reason
            if {[llength $f] >= 3 && [lindex $f 0] eq $Priv(gameNumber)} {
                RejectMove [lindex $f 2] 1
            }
        }
        56 {
            # game-number color milliseconds running
            lassign $f game color ms running
            if {$game ne $Priv(gameNumber) || !$Priv(active) || $color ni {W B} \
                || ![string is integer -strict $ms] || $running ni {0 1}} { return }
            set side [string tolower $color]
            set Priv(clock:$side) $ms
            set Priv(clockAt) [clock milliseconds]
            if {$running} {
                set Priv(clockStm) $side
                set Priv(ticking) [expr {$Priv(state) ne "over"}]
            } elseif {$Priv(clockStm) eq $side} { set Priv(ticking) 0 }
            if {[ViewExists]} { ::online::view::clocks $Priv(view) $Priv(clock:w) $Priv(clock:b) $Priv(clockStm) $Priv(ticking) }
        }
        31 {
            # name titles message tell-type
            if {[llength $f] < 4} { return }
            Chat [lindex $f 0] [lindex $f 2]
        }
        28 {
            # channel name titles message tell-type
            if {[llength $f] < 5} { return }
            Chat "[lindex $f 1]([lindex $f 0])" [lindex $f 3]
        }
        29 {
            # challenger rating titles receiver rating titles wild rating-type
            # rated adjourned white-time white-inc black-time black-inc color ...
            if {[llength $f] < 15} { return }
            set who [lindex $f 0]
            dict set Matches $who $f
            set Priv(match) $who
            LogText "Challenge from $who: [lindex $f 10]+[lindex $f 11]"
        }
        30 {
            set who [lindex $f 0]
            catch { dict unset Matches $who }
            if {[info exists Priv(match)] && $Priv(match) eq $who} { set Priv(match) {} }
        }
        34 {
            # game white-draw black-draw white-abort black-abort
            # white-adjourn black-adjourn white-takeback black-takeback
            if {[llength $f] < 9 || [lindex $f 0] ne $Priv(gameNumber)} { return }
            set opponent [expr {$Priv(userSide) eq "w" ? 2 : 1}]
            set Priv(offer) {}
            foreach {offset offer} {0 draw 2 abort 4 adjourn 6 takeback} {
                if {[lindex $f [expr {$offset+$opponent}]] > 0} { set Priv(offer) $offer }
            }
            UpdateGameButtons
        }
        24 - 25 - 36 {
            # ICC's optional move encodings and position variants depend on
            # negotiated settings. Ask for the style-12 snapshot instead of
            # guessing a FEN or passing unchecked SAN to the chess engine.
            if {$Priv(loggedIn)} { RequestSnapshot }
        }
        43 - 101 {
            # A server snapshot is already in progress. Its companion style
            # 12 line is authoritative; requesting refresh here would loop.
            return
        }
        27 {
            # game-number relation symbol: server style-12 snapshots carry
            # the authoritative side-to-move relation used by board input.
            if {[lindex $f 0] eq $Priv(gameNumber) && [lindex $f 1] eq "O"} {
                set Priv(observing) 1
            }
        }
        default { return }
    }
}

namespace eval ::icc { variable Matches {}; variable Priv; set Priv(match) {}; set Priv(refreshPending) 0 }
proc ::icc::RequestSnapshot {} {
    variable Priv
    if {!$Priv(refreshPending)} {
        set Priv(refreshPending) 1
        Send refresh
    }
}
proc ::icc::Chat {who message} {
    variable Priv
    LogText "$who: $message"
    if {[ViewExists]} { ::online::view::chat $Priv(view) $who $message }
}
proc ::icc::Challenge {who {minutes 5} {increment 0} {rated unrated} {color {}}} {
    if {![regexp {^[A-Za-z][A-Za-z0-9_-]*$} $who] || ![string is integer -strict $minutes] \
        || ![string is integer -strict $increment] || $rated ni {rated unrated} || $color ni {{} white black}} { return 0 }
    return [Send [string trim "match $who $minutes $increment $rated $color"]]
}
proc ::icc::AcceptMatch {} { variable Priv; if {$Priv(match) ne ""} { Send "accept $Priv(match)" } }
proc ::icc::DeclineMatch {} { variable Priv; if {$Priv(match) ne ""} { Send "decline $Priv(match)" } }
proc ::icc::ChallengeDialog {} { variable Priv; Challenge $Priv(dlg:target) }
proc ::icc::Observe {number} {
    if {![string is integer -strict $number] || $number < 0} { return 0 }
    return [Send "observe $number"]
}
proc ::icc::ObserveDialog {} { variable Priv; Observe $Priv(dlg:target) }
proc ::icc::Tell {target message} {
    if {![regexp {^[A-Za-z0-9_-]+$} $target]} { return 0 }
    return [Send "tell $target $message"]
}
proc ::icc::TellDialog {} { variable Priv; Tell $Priv(dlg:target) $Priv(dlg:message) }
proc ::icc::ChannelDialog {} {
    variable Priv
    if {[string is integer -strict $Priv(dlg:target)]} { TellDialog }
}
proc ::icc::Adjourn {} { variable Priv; if {$Priv(active) && !$Priv(observing)} { Send adjourn } }
proc ::icc::Examine {} { Send examine; Analyse }
