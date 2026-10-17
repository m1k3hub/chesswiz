# ======================================================================
# Play a training game against an engine ("Play Against Engine...",
# Extras menu). One human, one engine, one board: the user moves on the
# board, the engine answers over a bidirectional UCI pipe (the analysis
# panes' ::scidb::engine layer has no play mode, so this module owns its
# own process, in the spirit of tcl/ai-engine.tcl: fileevent on the pipe,
# a watchdog instead of a hanging wait).
#
#   ::playengine::open .application        setup dialog -> game panel
#   ::playengine::StartGame $spec          the same, programmatically:
#       -engine <name> -color white|black|random
#       -minutes <n> -increment <s>        (0 minutes = no clock)
#       -movetime <ms>                     ("go movetime" without a clock)
#       -elo <n> | -skill <n>              (per the engine's features)
#
# The engine move request is ::playengine::RequestMove; the tests replace
# it (no engine needed), user moves are ::playengine::UserMove <san>.
# Clocks are a wall-clock ledger (ms), not a tick counter; each side's
# remaining time is sent with "go wtime/btime/winc/binc". Flag fall,
# mate, stalemate, repetition, fifty moves and insufficient material end
# the game and set the Result header, so the game saves like any game.
# Covered by tests/test_app_play_engine.tcl.
# ======================================================================

::util::source play-engine

package require Tcl 8.5
package require Tk 8.5

namespace eval ::playengine {
namespace eval mc {

set Title					"Play Against Engine"
set Engine					"Engine:"
set Color					"Play as:"
set White					"White"
set Black					"Black"
set Random					"Random"
set TimeControl			"Time control:"
set Clock					"Clock:"
set ClockDetail			"minutes each, plus seconds increment per move"
set NoClock				"No clock"
set NoClockDetail		"the engine thinks %s ms per move"
set Strength				"Strength:"
set StrengthElo			"Engine strength (Elo):"
set StrengthSkill		"Skill level:"
set StrengthFull		"full strength (this engine cannot be weakened)"
set Start					"Start"
set Cancel					"Cancel"
set NewGame				"New Game"
set Close					"Close"
set You					"You"
set Event					"Training game"
set Resign					"Resign"
set OfferDraw			"Offer Draw"
set Takeback				"Takeback"
set Thinking				"%s is thinking..."
set YourMove				"Your move."
set NotYourTurn			"Wait for %s's move."
set NotAtEnd				"Return to the end of the game to move."
set NoMoves				"No moves to take back."
set EngineGone				"%s stopped unexpectedly; the game is over."
set EngineSlow				"%s did not answer within %s; the game is over."
set IllegalMove			"%s played the illegal move %s; the game is over."
set NoSuchEngine			"no engine named '%s'"
set EngineMissing		"the program of %s is missing: %s"
set Declined				"%s declines the draw offer."
set DrawAccepted			"Draw agreed."
set Checkmate			"Checkmate"
set Stalemate			"Stalemate"
set FiftyMoves			"Draw by the fifty-move rule"
set Repetition			"Draw by threefold repetition"
set Material				"Draw: insufficient mating material"
set Flag					"Flag fall: %s wins on time"
set Resigned				"%s resigned"
set NoClockTime			"\u2014"
set Result(1-0)			"White wins"
set Result(0-1)			"Black wins"
set Result(1/2-1/2)	"Draw"
set GameOver				"Game over: %s (%s)"


} ;# namespace mc

# Persisted across sessions (WriteOptions below).
array set Options {
	engine		Stockfish
	color			white
	minutes		10
	increment	2
	movetime		1000
	elo			1600
	skill			5
}

variable MoveTimeout 2000			;# grace added to a move's clock, ms
variable TickInterval 250			;# clock display update, ms
variable DrawMinPly 60				;# draw offers only after move 30
variable DrawMaxCp 50				;# "near zero" in centipawns

array set Priv {
	dialog		{}
	active		0
	phase			idle
	pos			0
	engine		{}
	engineSide	b
	userSide		w
	noclock		0
	minutes		10
	increment	2
	movetime		1000
	clock:w		600000
	clock:b		600000
	color:user	w
	color:engine	b
	busy			0
	pipe			{}
	pipeState	off
	pending		0
	watchdog		{}
	tick			{}
	eval:cp		{}
	eval:mate	{}
}

} ;# namespace playengine


# ======================================================================
# The dialog
# ======================================================================

proc ::playengine::open {parent} {
	variable Priv
	variable Options
	variable mc

	set dlg $parent.playengine
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

	set top [ttk::frame $dlg.top]
	pack $top -fill both -expand yes -padx $::theme::padx -pady $::theme::pady

	### setup ##############################################################
	set f [ttk::frame $top.setup]

	set ef [ttk::frame $f.engine]
	ttk::label $ef.label -text $mc::Engine
	ttk::combobox $ef.engine -state readonly -width 22 \
		-textvariable [namespace current]::Priv(dlg:engine)
	pack $ef.label -side left
	pack $ef.engine -side left -padx [list $::theme::padx 0]
	bind $ef.engine <<ComboboxSelected>> [namespace code StrengthRows]
	pack $ef -fill x -pady [list 0 $::theme::pady]

	set cf [ttk::frame $f.color]
	ttk::label $cf.label -text $mc::Color
	pack $cf.label -side left
	foreach {value text} [list white $mc::White black $mc::Black random $mc::Random] {
		ttk::radiobutton $cf.$value -text $text -value $value \
			-variable [namespace current]::Priv(dlg:color)
		pack $cf.$value -side left -padx [list $::theme::padx 0]
	}
	pack $cf -anchor w -pady [list 0 $::theme::pady]

	set tf [ttk::frame $f.time]
	ttk::radiobutton $tf.clock -text $mc::Clock -value clock \
		-variable [namespace current]::Priv(dlg:clock)
	ttk::spinbox $tf.minutes -from 1 -to 180 -width 3 \
		-textvariable [namespace current]::Priv(dlg:minutes)
	ttk::label $tf.plus -text "+"
	ttk::spinbox $tf.increment -from 0 -to 60 -width 2 \
		-textvariable [namespace current]::Priv(dlg:increment)
	ttk::label $tf.s -text "s"
	ttk::label $tf.detail -text $mc::ClockDetail
	set noclock [ttk::frame $f.noclock]
	ttk::radiobutton $noclock.choice -text $mc::NoClock -value noclock \
		-variable [namespace current]::Priv(dlg:clock)
	ttk::label $noclock.detail -text [format $mc::NoClockDetail $Options(movetime)]
	pack $tf.clock $tf.minutes $tf.plus $tf.increment $tf.s -side left
	pack $tf.detail -side left -padx [list $::theme::padx 0]
	pack $noclock.choice -side left
	pack $noclock.detail -side left -padx [list $::theme::padx 0]
	pack $tf -anchor w
	pack $noclock -anchor w -pady [list 0 $::theme::pady]

	ttk::frame $f.strength
	pack $f.strength -fill x -pady [list 0 $::theme::pady]

	pack $f -fill x

	### the game panel (packed by ShowPanel) ############################
	set p [ttk::frame $top.play]
	set Priv(widget:play) $p

	set clocks [ttk::frame $p.clocks]
	ttk::label $clocks.you -width 16 -anchor w
	ttk::label $clocks.youclock -font $::font::text(text:normal) -width 8 -anchor e
	ttk::label $clocks.opp -width 16 -anchor w
	ttk::label $clocks.oppclock -font $::font::text(text:normal) -width 8 -anchor e
	grid $clocks.you -row 1 -column 1 -sticky w
	grid $clocks.youclock -row 1 -column 2 -sticky e
	grid $clocks.opp -row 2 -column 1 -sticky w
	grid $clocks.oppclock -row 2 -column 2 -sticky e
	grid columnconfigure $clocks 1 -weight 1
	pack $clocks -fill x

	ttk::label $p.status -wraplength 280 -justify left
	pack $p.status -fill x -pady [list $::theme::pady]
	set Priv(widget:status) $p.status

	set btns [ttk::frame $p.buttons]
	ttk::button $btns.resign -text $mc::Resign -command [namespace code Resign]
	ttk::button $btns.draw -text $mc::OfferDraw -command [namespace code OfferDraw]
	ttk::button $btns.takeback -text $mc::Takeback -command [namespace code Takeback]
	pack $btns.resign -side left
	pack $btns.draw -side left -padx $::theme::padx
	pack $btns.takeback -side left
	pack $btns -anchor w -pady [list 0 $::theme::pady]

	::widget::dialogButtons $dlg {ok cancel}
	$dlg.ok configure -text $mc::Start -command [namespace code Start]
	$dlg.cancel configure -text $mc::Cancel -command [namespace code Close]
	set Priv(widget:ok) $dlg.ok
	set Priv(widget:cancel) $dlg.cancel

	# persisted defaults
	set names [EngineNames]
	set name $Options(engine)
	if {$name ni $names} { set name [expr {[llength $names] ? [lindex $names 0] : ""}] }
	set Priv(dlg:engine) $name
	set Priv(dlg:color) $Options(color)
	set Priv(dlg:clock) [expr {$Options(minutes) > 0 ? "clock" : "noclock"}]
	set Priv(dlg:minutes) [expr {max(1, $Options(minutes))}]
	set Priv(dlg:increment) $Options(increment)
	$ef.engine configure -values $names
	StrengthRows

	# beside the board, never on it: the user plays on the board while the
	# dialog is open, and clicks on the board must reach the board
	if {![PlaceBesideBoard $dlg]} { ::util::place $dlg -parent $parent -position center }
	wm deiconify $dlg
	return $dlg
}


# The configured engines that speak UCI (the driver is a UCI pipe).
proc ::playengine::EngineNames {} {
	set names {}
	foreach e $::engine::Engines {
		set e [dict merge $::engine::EmptyEngine $e]
		if {"UCI" in [dict get $e Protocol]} { lappend names [dict get $e Name] }
	}
	return $names
}


# The strength rows follow the chosen engine: UCI_LimitStrength/UCI_Elo
# when both exist, else a Skill Level spin, else a plain "full strength".
proc ::playengine::StrengthRows {} {
	variable Priv
	variable Options
	variable mc

	set w $Priv(dialog)
	if {![winfo exists $w]} { return }
	set f $w.top.setup.strength
	foreach child [winfo children $f] { destroy $child }

	set name $Priv(dlg:engine)
	set features [EngineFeatures $name]
	set row [ttk::frame $f.row]
	if {[dict exists $features limitStrength]} {
		lassign [dict get $features limitStrength] min max
		if {$Options(elo) < $min} { set Options(elo) $min }
		if {$Options(elo) > $max} { set Options(elo) $max }
		ttk::label $row.label -text "$mc::StrengthElo ($min-$max)"
		ttk::spinbox $row.spin -from $min -to $max -increment 50 -width 5 \
			-textvariable [namespace current]::Options(elo)
	} elseif {[dict exists $features skillLevel]} {
		lassign [dict get $features skillLevel] min max
		if {$Options(skill) < $min} { set Options(skill) $min }
		if {$Options(skill) > $max} { set Options(skill) $max }
		ttk::label $row.label -text "$mc::StrengthSkill ($min-$max)"
		ttk::spinbox $row.spin -from $min -to $max -width 3 \
			-textvariable [namespace current]::Options(skill)
	} else {
		ttk::label $row.label -text "$mc::Strength $mc::StrengthFull"
	}
	pack $row -anchor w
}


# The feature dict of engine <name> ({} when unknown or the file is gone).
proc ::playengine::EngineFeatures {name} {
	set index [::engine::FindIndex $name]
	if {$index == -1} { return {} }
	set e [dict merge $::engine::EmptyEngine [lindex $::engine::Engines $index]]
	set protocol [expr {"UCI" in [dict get $e Protocol] ? "UCI" : "WB"}]
	return [dict get $e Features:$protocol]
}


# The Start button.
proc ::playengine::Start {} {
	variable Priv
	variable Options

	set name [string trim $Priv(dlg:engine)]
	if {$name eq ""} { return }
	foreach {key dflt low high} {minutes 10 1 180 increment 2 0 60} {
		set v $Priv(dlg:$key)
		if {![string is integer -strict $v]} { set v $dflt }
		set v [expr {max($low, min($high, $v))}]
		set Priv(dlg:$key) $v
	}
	set Options(engine) $name
	set Options(color) $Priv(dlg:color)
	set Options(increment) $Priv(dlg:increment)
	set Options(minutes) [expr {$Priv(dlg:clock) eq "clock" ? $Priv(dlg:minutes) : 0}]

	StartGame [list \
		-engine $name \
		-color $Priv(dlg:color) \
		-minutes $Options(minutes) \
		-increment $Priv(dlg:increment) \
		-movetime $Options(movetime) \
		-elo $Options(elo) \
		-skill $Options(skill) \
	]
}


# Put <dlg> next to the main board: right of it when the screen has room,
# else left of it, else below it, kept on the screen. Returns 0 when there
# is no board to place it by.
proc ::playengine::PlaceBesideBoard {dlg} {
	if {[catch { set board $::application::board::board }] || ![winfo exists $board]
		|| ![winfo ismapped $board]} {
		return 0
	}
	update idletasks
	set dw [winfo reqwidth $dlg]
	set dh [winfo reqheight $dlg]
	set bx [winfo rootx $board]
	set by [winfo rooty $board]
	set bw [winfo width $board]
	set bh [winfo height $board]
	set sw [winfo screenwidth $dlg]
	set sh [winfo screenheight $dlg]
	lassign [BesidePosition $bx $by $bw $bh $dw $dh $sw $sh] x y
	wm geometry $dlg +$x+$y
	return 1
}


# Screen position {x y} for a dialog of <dw>x<dh> next to a board at
# <bx>,<by> sized <bw>x<bh> on a <sw>x<sh> screen: right, else left, else
# below, clamped to the screen (allowing for the window frame).
proc ::playengine::BesidePosition {bx by bw bh dw dh sw sh} {
	set gap 12
	set fw 16
	set fh 40
	if {$bx + $bw + $gap + $dw + $fw <= $sw} {
		set x [expr {$bx + $bw + $gap}]
		set y $by
	} elseif {$bx - $gap - $dw - $fw >= 0} {
		set x [expr {$bx - $gap - $dw - $fw}]
		set y $by
	} else {
		set x $bx
		set y [expr {$by + $bh + $gap}]
	}
	list [expr {max(0, min($x, $sw - $dw - $fw))}] [expr {max(0, min($y, $sh - $dh - $fh))}]
}


# Close the dialog; the game on the board is untouched, a running session
# is aborted (declared over, but the result stays "*").
proc ::playengine::Close {} {
	variable Priv

	Finish
	if {[winfo exists $Priv(dialog)]} { destroy $Priv(dialog) }
	set Priv(dialog) {}
}


# ======================================================================
# The game
# ======================================================================

# Starts a training game from <spec> (see the header comment). Returns 1
# when the game is set up. The engine is started lazily, on its first
# move, so a spec with an unknown engine fails then, not here.
proc ::playengine::StartGame {spec} {
	variable Priv
	variable mc

	array set opts [list \
		-engine {} \
		-color white \
		-minutes 10 \
		-increment 2 \
		-movetime 1000 \
		-elo 1600 \
		-skill 5 \
	]
	array set opts $spec

	set name $opts(-engine)
	if {[::engine::FindIndex $name] == -1} { error [format $mc::NoSuchEngine $name] }
	set color $opts(-color)
	if {$color ni {white black}} { set color [expr {rand() < 0.5 ? "white" : "black"}] }

	Finish
	::menu::gameNew .application

	set pos [::scidb::game::current]
	set Priv(pos) $pos
	set Priv(engine) $name
	set Priv(userSide) [string index $color 0]
	set Priv(engineSide) [expr {$Priv(userSide) eq "w" ? "b" : "w"}]
	set Priv(color:user) $Priv(userSide)
	set Priv(color:engine) $Priv(engineSide)
	set Priv(minutes) [expr {max(0, $opts(-minutes))}]
	set Priv(noclock) [expr {$Priv(minutes) == 0}]
	set Priv(increment) [expr {max(0, $opts(-increment))}]
	set Priv(movetime) [expr {max(1, $opts(-movetime))}]
	set Priv(elo) $opts(-elo)
	set Priv(skill) $opts(-skill)
	set Priv(clock:w) [expr {$Priv(minutes) * 60 * 1000}]
	set Priv(clock:b) [expr {$Priv(minutes) * 60 * 1000}]
	set Priv(eval:cp) {}
	set Priv(eval:mate) {}
	set Priv(busy) 0
	set Priv(pending) 0

	# the headers (White/Black/Event/Date) go in through a headers-only
	# PGN: in-memory games have no tag setter, the import sets them
	set tags [list \
		[format {[Event "%s"]} $mc::Event] \
		{[Site "?"]} \
		[format {[Date "%s"]} [clock format [clock seconds] -format {%Y.%m.%d}]] \
		{[Round "?"]} \
		[format {[White "%s"]} [expr {$color eq "white" ? $mc::You : $name}]] \
		[format {[Black "%s"]} [expr {$color eq "white" ? $name : $mc::You}]] \
		{[Result "*"]} \
	]
	ImportGame $pos "[join $tags \n]\n\n*\n"

	::scidb::game::subscribe board $pos [namespace current]::Update
	::scidb::db::subscribe gameClose [namespace current]::GameClosed
	::scidb::db::subscribe gameSwitch [namespace current]::GameSwitched
	set Priv(active) 1

	ShowPanel
	if {$Priv(engineSide) eq "w"} {
		set Priv(phase) engine
		Status [format $mc::Thinking $name]
		BoardInput off
		RequestMove
	} else {
		set Priv(phase) user
		Status $mc::YourMove
		BoardInput on
		StartSegment user [clock milliseconds]
	}

	StartTick
	return 1
}


# Ends the session (not necessarily the game) and frees the engine.
proc ::playengine::Finish {} {
	variable Priv

	if {$Priv(active)} {
		catch { ::scidb::game::unsubscribe board $Priv(pos) [namespace current]::Update }
		catch { ::scidb::db::unsubscribe gameClose [namespace current]::GameClosed }
		catch { ::scidb::db::unsubscribe gameSwitch [namespace current]::GameSwitched }
	}
	after cancel $Priv(tick)
	after cancel $Priv(watchdog)
	set Priv(tick) {}
	set Priv(watchdog) {}
	unset -nocomplain Priv(side:user) Priv(side:engine)
	set Priv(active) 0
	set Priv(phase) idle
	Shutdown
	BoardInput on
}


# The game slot of the session closed or deselected: wrap up.
proc ::playengine::GameClosed {position} {
	variable Priv
	if {$Priv(active) && $position == $Priv(pos)} { Finish }
}


proc ::playengine::GameSwitched {oldPos newPos} {
	variable Priv
	if {$Priv(active) && $newPos != $Priv(pos)} { Finish }
}


# ----------------------------------------------------------------------
# Turns
# ----------------------------------------------------------------------

# Board subscription of the session's game. The engine's own moves and
# takebacks flow through too; Priv(busy) suppresses them.
proc ::playengine::Update {position cmd data promoted} {
	variable Priv
	variable mc

	if {!$Priv(active) || $Priv(busy) || $position != $Priv(pos)} { return }
	if {$cmd ne "move"} { return }
	if {[llength $data] && ![lindex $data end]} { return } ;# backward navigation

	if {$Priv(phase) eq "user"} {
		# a board move while the user side is to move: accept only appends
		# at the end of the mainline, everything else is rolled back
		if {![::scidb::game::position atEnd?] || ![::scidb::game::position isMainline?]} {
			RejectMove $mc::NotAtEnd
			return
		}
		AfterUserMove
	} elseif {$Priv(phase) eq "engine"} {
		RejectMove [format $mc::NotYourTurn $Priv(engine)]
	}
}


# A move via the keyboard/commands instead of the board, for tests and
# the assistant; like a drag on the board it answers whether it went in.
proc ::playengine::UserMove {san} {
	variable Priv
	variable mc

	if {!$Priv(active) || $Priv(phase) ne "user"} { return 0 }
	if {![::scidb::game::position atEnd?] || ![::scidb::game::position isMainline?]} {
		Status $mc::NotAtEnd
		return 0
	}
	set plies [::scidb::game::query length]
	::move::addMove menu $san
	return [expr {[::scidb::game::query length] > $plies}]
}


# The user's move is in: stop their clock segment, check the end, then
# hand over to the engine.
proc ::playengine::AfterUserMove {} {
	variable Priv
	variable mc

	SettleClock user [clock milliseconds]
	if {$Priv(phase) eq "over"} { return } ;# user's flag fell on the move
	if {[FinishIfOver]} { return }

	set Priv(phase) engine
	Status [format $mc::Thinking $Priv(engine)]
	DrawClocks
	BoardInput off
	RequestMove
}


# A move that appeared out of turn (the user dragged while the engine
# was thinking, or left the mainline): put the position back.
proc ::playengine::RejectMove {why} {
	variable Priv

	set Priv(busy) 1
	::scidb::game::go -1
	::scidb::game::strip truncate
	set Priv(busy) 0
	Status $why
}


# ======================================================================
# The engine pipe
# ======================================================================

# The seam the tests stub: asked once per engine turn, on the position
# the board shows after the user's move. The default implementation talks
# UCI; a stub calls [namespace code GotBestMove] with a uci move itself.
proc ::playengine::RequestMove {} {
	DriveMove
}


proc ::playengine::DriveMove {} {
	variable Priv
	variable mc
	variable MoveTimeout

	if {[Connect]} { return } ;# the handshake continues the move when ready
	if {$Priv(pipeState) ne "ready"} { return }

	set fen [::scidb::pos::fen]
	StartSegment engine [clock milliseconds]
	if {$Priv(noclock)} {
		set go [goLine "" "" "" $Priv(movetime)]
		set wait [expr {$Priv(movetime) + $MoveTimeout}]
	} else {
		set go [goLine $Priv(clock:w) $Priv(clock:b) [expr {$Priv(increment) * 1000}] ""]
		set wait [expr {$Priv(clock:$Priv(engineSide)) + $MoveTimeout}]
	}
	set Priv(pipeState) busy
	Send "position fen $fen"
	Send $go
	# the tournament's watchdog: an engine that misses its time budget
	# (plus the grace) counts as a flag fall / a crash
	set Priv(watchdog) [after $wait [namespace code OnTimeout]]
}


# The pipe handshake; returns 1 while the engine is still starting (the
# move is then sent by OnReadable once "readyok" arrives), 0 when the
# engine is already up.
proc ::playengine::Connect {} {
	variable Priv
	variable mc

	if {$Priv(pipe) ne ""} { return 0 }
	if {$Priv(pipeState) eq "starting"} { return 1 }

	set index [::engine::FindIndex $Priv(engine)]
	set e [dict merge $::engine::EmptyEngine [lindex $::engine::Engines $index]]
	set cmd [::engine::Command [dict get $e Command] [dict get $e Parameters]]
	if {$cmd eq "" || $cmd eq "no-wine"} {
		# an engine that cannot start decides the game before it began
		EngineDied [format $mc::EngineMissing $Priv(engine) [dict get $e Command]]
		return 1
	}

	if {[catch { set pipe [::open "|[list {*}$cmd]" r+] } err]} {
		EngineDied $err
		return 1
	}
	fconfigure $pipe -blocking 0 -buffering line
	set Priv(pipe) $pipe
	set Priv(pipeState) starting
	set Priv(pending) 1
	fileevent $pipe readable [namespace code OnReadable]
	Send uci
	return 1
}


proc ::playengine::Send {line} {
	variable Priv
	if {[catch { puts $Priv(pipe) $line; flush $Priv(pipe) }]} { EngineDied }
}


# Strength comes from the setting of the dialog (UCI_LimitStrength /
# UCI_Elo when the engine has it, else its Skill Level option).
proc ::playengine::SendOptions {} {
	variable Priv

	set features [EngineFeatures $Priv(engine)]
	if {[dict exists $features limitStrength]} {
		lassign [dict get $features limitStrength] min max
		Send "setoption name UCI_LimitStrength value true"
		Send "setoption name UCI_Elo value [expr {max($min, min($max, $Priv(elo)))}]"
	} elseif {[dict exists $features skillLevel]} {
		lassign [dict get $features skillLevel] min max
		Send "setoption name Skill Level value [expr {max($min, min($max, $Priv(skill)))}]"
	}
}


proc ::playengine::OnReadable {} {
	variable Priv

	if {[catch {
		while {[gets $Priv(pipe) line] >= 0} {
			if {$line ne ""} { OnEngineLine $line }
		}
	}]} { EngineDied; return }
	if {[catch { eof $Priv(pipe) } eof] || $eof} { EngineDied }
}


proc ::playengine::OnEngineLine {line} {
	variable Priv

	switch -glob -- $line {
		uciok {
			SendOptions
			Send "ucinewgame"
			Send "isready"
		}
		readyok {
			if {$Priv(pipeState) eq "starting"} {
				set Priv(pipeState) ready
				if {$Priv(pending)} {
					set Priv(pending) 0
					DriveMove
				}
			}
		}
		info* {
			lassign [infoScore $line] kind value
			if {$kind ne ""} {
				set Priv(eval:cp) [expr {$kind eq "cp" ? $value : ""}]
				set Priv(eval:mate) [expr {$kind eq "mate" ? $value : ""}]
			}
		}
		bestmove* {
			set move [lindex $line 1]
			GotBestMove $move
		}
	}
}


# The move the engine chose (uci string; also called by the stub engine
# in the tests). Applies the time spent to the engine's clock.
proc ::playengine::GotBestMove {move} {
	variable Priv
	variable mc

	after cancel $Priv(watchdog)
	set Priv(watchdog) {}
	if {!$Priv(active) || $Priv(phase) ne "engine"} { return } ;# stale answer
	set Priv(pipeState) ready

	if {$move eq "" || $move eq "(none)"} { return }
	if {![FinishIfOver]} { ApplyEngineMove $move }
}


proc ::playengine::ApplyEngineMove {move} {
	variable Priv
	variable mc

	set san [uciToSan $move]
	if {$san eq ""} {
		EndGame [expr {$Priv(userSide) eq "w" ? "1-0" : "0-1"}] \
			[format $mc::IllegalMove $Priv(engine) $move]
		return
	}
	set Priv(busy) 1
	catch { ::scidb::game::move $san; ::scidb::game::go 1 }
	set Priv(busy) 0
	SettleClock engine [clock milliseconds]
	if {$Priv(phase) eq "over"} { return } ;# the engine's flag fell on its move
	if {[FinishIfOver]} { return }
	set Priv(phase) user
	StartSegment user [clock milliseconds]
	Status $mc::YourMove
	BoardInput on
	DrawClocks
}


# The engine spent longer than its clock plus the grace: flag fall with
# a clock, else treat it as a crash (it is probably stuck).
proc ::playengine::OnTimeout {} {
	variable Priv
	variable mc

	set Priv(watchdog) {}
	if {$Priv(noclock)} {
		EngineDied $mc::EngineSlow
	} else {
		set Priv(clock:$Priv(engineSide)) 0
		EndGame [expr {$Priv(userSide) eq "w" ? "1-0" : "0-1"}] \
			[format $mc::Flag $mc::You]
	}
}


proc ::playengine::EngineDied {{why ""}} {
	variable Priv
	variable mc

	Shutdown
	if {!$Priv(active)} { return }
	if {$why eq ""} { set why [format $mc::EngineGone $Priv(engine)] }
	EndGame "*" $why
}


proc ::playengine::Shutdown {} {
	variable Priv

	if {$Priv(pipe) ne ""} {
		catch { fileevent $Priv(pipe) readable {} }
		catch { puts $Priv(pipe) "quit"; flush $Priv(pipe) }
		catch { close $Priv(pipe) }
		set Priv(pipe) {}
	}
	set Priv(pipeState) off
	set Priv(pending) 0
}


# ======================================================================
# Buttons
# ======================================================================

proc ::playengine::Resign {} {
	variable Priv
	variable mc

	if {!$Priv(active) || $Priv(phase) ni {user engine}} { return }
	EndGame [expr {$Priv(userSide) eq "w" ? "0-1" : "1-0"}] [format $mc::Resigned $mc::You]
}


# The engine accepts when its own score of the position is flat; before
# move 30 it always plays on.
proc ::playengine::OfferDraw {} {
	variable Priv
	variable mc

	if {!$Priv(active) || $Priv(phase) ni {user engine}} { return }
	set cp $Priv(eval:cp)
	set mate $Priv(eval:mate)
	if {[drawAccept [::scidb::game::query length] $cp $mate]} {
		EndGame 1/2-1/2 $mc::DrawAccepted
	} else {
		Status [format $mc::Declined $Priv(engine)]
	}
}


# Undo the last two plies (the user's move and the engine's reply); with
# a single ply only that one goes, and the engine moves again.
proc ::playengine::Takeback {} {
	variable Priv
	variable mc

	if {!$Priv(active) || $Priv(phase) ne "user"} { return }
	set plies [::scidb::game::query length]
	if {$plies == 0} {
		Status $mc::NoMoves
		return
	}
	set n [expr {min(2, $plies)}]
	set Priv(busy) 1
	::scidb::game::go -$n
	::scidb::game::strip truncate
	set Priv(busy) 0

	if {[::scidb::pos::stm] eq $Priv(engineSide)} {
		set Priv(phase) engine
		Status [format $mc::Thinking $Priv(engine)]
		BoardInput off
		RequestMove
		return
	}
	Status $mc::YourMove
	DrawClocks
}


# ======================================================================
# The clock: a wall-clock ledger; the display only renders it.
# ======================================================================

# The side to move starts thinking now (start of the game or after the
# other side's move): later settling charges the interval to its clock.
proc ::playengine::StartSegment {side now} {
	variable Priv
	set Priv(side:$side) $now
}


# <side> has just moved; charge the elapsed wall time, grant the
# increment, and detect the flag fall. Returns the remaining time (ms).
proc ::playengine::SettleClock {side now} {
	variable Priv

	if {$Priv(noclock) || ![info exists Priv(side:$side)]} { return 0 }
	set color $Priv(color:$side)
	set elapsed [expr {$now - $Priv(side:$side)}]
	set left [expr {$Priv(clock:$color) - $elapsed + $Priv(increment) * 1000}]
	set Priv(clock:$color) $left
	unset Priv(side:$side)
	DrawClocks
	if {$left <= 0} { FlagFall $color }
	return $left
}


# Remaining ms for <color> at time <now>; the running segment's charge is
# included. Pure with respect to time so the ticker and tests agree.
proc ::playengine::Remaining {color now} {
	variable Priv

	set ms $Priv(clock:$color)
	foreach side {user engine} {
		if {$Priv(color:$side) eq $color && [info exists Priv(side:$side)]} {
			set ms [expr {$ms - ($now - $Priv(side:$side))}]
		}
	}
	return $ms
}


# Time ran out for <color> (settled move or the ticker): it loses.
proc ::playengine::FlagFall {color} {
	variable Priv
	variable mc

	if {!$Priv(active) || $Priv(phase) ni {user engine}} { return }
	unset -nocomplain Priv(side:user) Priv(side:engine)
	set result [expr {$color eq "w" ? "0-1" : "1-0"}]
	set winner [expr {$color eq $Priv(userSide) ? $Priv(engine) : $mc::You}]
	EndGame $result [format $mc::Flag $winner]
}


proc ::playengine::StartTick {} {
	variable Priv
	variable TickInterval
	after cancel $Priv(tick)
	set Priv(tick) [after $TickInterval [namespace code Tick]]
}


proc ::playengine::Tick {} {
	variable Priv
	variable TickInterval

	set Priv(tick) {}
	if {!$Priv(active)} { return }
	set Priv(tick) [after $TickInterval [namespace code Tick]]
	DrawClocks
	if {$Priv(noclock) || $Priv(phase) ni {user engine}} { return }
	# the display catches the flag while a side is thinking; a settled
	# move catches it right away
	foreach side {user engine} {
		if {![info exists Priv(side:$side)]} { continue }
		set color $Priv(color:$side)
		if {[Remaining $color [clock milliseconds]] <= 0} { FlagFall $color }
	}
}


# ======================================================================
# End of the game
# ======================================================================

# {result reason} when the position ends the game, {} otherwise.
proc ::playengine::GameEnd {} {
	variable mc

	if {[catch { ::scidb::game::query over? } over] || !$over} {
		set fen [::scidb::pos::fen]
		if {![string length $fen]} { return {} }
		if {[fiftyMoves $fen]} { return [list 1/2-1/2 $mc::FiftyMoves] }
		if {[repetition]} { return [list 1/2-1/2 $mc::Repetition] }
		if {[insufficientMaterial $fen]} { return [list 1/2-1/2 $mc::Material] }
		return {}
	}
	if {[inCheck [::scidb::pos::fen]]} {
		# side to move has no move and is in check: the other side mates
		set result [expr {[::scidb::pos::stm] eq "w" ? "0-1" : "1-0"}]
		return [list $result $mc::Checkmate]
	}
	return [list 1/2-1/2 $mc::Stalemate]
}


# Ends the game after a move if the position is final; answer = 1.
proc ::playengine::FinishIfOver {} {
	set end [GameEnd]
	if {![llength $end]} { return 0 }
	EndGame {*}$end
	return 1
}


# The game is decided: clocks stop, the result header is set (the game
# goes to the normal save dialog with names/event intact), the panel
# reports the outcome.
proc ::playengine::EndGame {result reason} {
	variable Priv
	variable mc

	if {!$Priv(active) || $Priv(phase) eq "over"} { return }
	after cancel $Priv(tick)
	after cancel $Priv(watchdog)
	set Priv(tick) {}
	set Priv(watchdog) {}
	set Priv(phase) over
	unset -nocomplain Priv(side:user) Priv(side:engine)
	BoardInput on

	if {$result ne "*"} {
		catch { StoreResult $result }
		Status [format $mc::GameOver $mc::Result($result) $reason]
	} else {
		Status $reason
	}
	DrawClocks
	Busy off
	if {[DialogExists]} {
		set parent [winfo parent $Priv(dialog)]
		catch { ::dialog::info -parent $parent -message $reason }
	}
}


# In-memory games keep their tags only through the scratch base, so the
# result header is set by exporting the game, patching the Result tag and
# importing it back; the board is restored to the final position.
proc ::playengine::StoreResult {result} {
	variable Priv

	set pos $Priv(pos)
	set pgn [::scidb::game::toPGN modified -position $pos]
	if {![regsub {\[Result "[^"]*"\]} $pgn [format {[Result "%s"]} $result] pgn]} {
		# no Result tag at all: add it after the first header line
		set eol [string first \n $pgn]
		set pgn [string replace $pgn $eol $eol "\n[format {[Result "%s"]} $result]"]
	}
	# the movetext terminator matches the header
	regsub {\*\s*$} $pgn $result pgn
	set Priv(busy) 1
	ImportGame $pos $pgn
	set Priv(busy) 0
	::scidb::game::go end
	DrawClocks
}


# Import <pgn> into game slot <pos> without popping dialogs.
proc ::playengine::ImportGame {pos pgn} {
	::scidb::game::import $pos $pgn ::playengine::ImportLog {} -encoding utf-8
}


proc ::playengine::ImportLog {_ args} { return }


# ======================================================================
# The dialog as the game panel
# ======================================================================

proc ::playengine::ShowPanel {} {
	variable Priv
	variable mc

	if {![DialogExists]} { return }
	set top $Priv(dialog).top
	pack forget $top.setup
	pack $Priv(widget:play) -fill x
	$Priv(widget:ok) configure -text $mc::NewGame -command [namespace code NewGame]
	$Priv(widget:cancel) configure -text $mc::Close -command [namespace code Close]
	set p $Priv(widget:play)
	set names [expr {$Priv(userSide) eq "w" ? [list [set mc::You] $Priv(engine)] : [list $Priv(engine) [set mc::You]]}]
	$p.clocks.you configure -text "$mc::White: [lindex $names 0]"
	$p.clocks.opp configure -text "$mc::Black: [lindex $names 1]"
	DrawClocks
}


# "New Game" on the panel: back to the setup view.
proc ::playengine::NewGame {} {
	variable Priv
	variable mc

	Finish
	if {![DialogExists]} { return }
	set top $Priv(dialog).top
	pack forget $Priv(widget:play)
	pack $top.setup -fill x
	$Priv(widget:ok) configure -text $mc::Start -command [namespace code Start]
	StrengthRows
}


proc ::playengine::Status {text} {
	variable Priv
	if {[DialogExists]} {
		$Priv(widget:status) configure -text $text
	}
}


# The dialog widgets exist only between open and Close; a programmatic
# game (tests, the assistant) runs fine without them.  winfo on an
# empty path name is an error, so the length matters too.
proc ::playengine::DialogExists {} {
	variable Priv
	return [expr {[string length $Priv(dialog)] && [winfo exists $Priv(dialog)]}]
}


# Board input is off while the engine is to move (out-of-turn drags that
# slip past are rolled back by Update); move::disable is the front line.
proc ::playengine::BoardInput {on} {
	if {$on eq "on"} { ::move::enable } else { ::move::disable }
}


proc ::playengine::Busy {on} {
	variable Priv
	set Priv(busy) [expr {$on eq "on" ? 1 : 0}]
}


# Render both clocks; the side thinking gets its time counted down live.
proc ::playengine::DrawClocks {} {
	variable Priv
	variable mc

	if {![DialogExists]} { return }
	set p $Priv(widget:play)
	if {[winfo manager $p] ne "pack"} { return }
	if {$Priv(noclock)} {
		$p.clocks.youclock configure -text $mc::NoClockTime
		$p.clocks.oppclock configure -text $mc::NoClockTime
		return
	}
	set now [clock milliseconds]
	foreach {color wclock} {w youclock b oppclock} {
		set w $p.clocks.$wclock
		$w configure -text [FormatClock [expr {max(0, [Remaining $color $now])}]]
		set active 0
		if {$Priv(active) && $Priv(phase) ni {over idle} && !$Priv(noclock)} {
			foreach side {user engine} {
				if {[info exists Priv(side:$side)]} { set thinking $side }
			}
			if {[info exists thinking] && $Priv(color:$thinking) eq $color} { set active 1 }
		}
		$w configure -font $::font::text([expr {$active ? "text:bold" : "text:normal"}])
	}
}


proc ::playengine::WriteOptions {chan} {
	::options::writeItem $chan [namespace current]::Options
}

::options::hookWriter ::playengine::WriteOptions


# ======================================================================
# Pure helpers (covered by tests/test_app_play_engine.tcl)
# ======================================================================

# The "go" command: remaining ms and increments with a clock, else
# "go movetime <ms>".
proc ::playengine::goLine {wtMs btMs incMs movetimeMs} {
	if {$movetimeMs ne ""} { return "go movetime $movetimeMs" }
	return "go wtime $wtMs btime $btMs winc $incMs binc $incMs"
}


# A remaining time in ms as m:ss (h:mm:ss beyond an hour; 0.1s accuracy
# below 10 s so a running clock visibly ticks).
proc ::playengine::FormatClock {ms} {
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


# uci move ("e2e4", "e7e8q") to SAN, "" when illegal in the current
# position.
proc ::playengine::uciToSan {uci} {
	if {![regexp {^([a-h][1-8])([a-h][1-8])([qrbnkQRBNK])?$} $uci -> from to promo]} { return "" }
	if {$promo eq ""} {
		return [::scidb::pos::san $from $to]
	}
	return [::scidb::pos::san $from $to $promo]
}


# {kind value} of an "info ... score cp|mate N ..." line, "" when the
# line carries no score.
proc ::playengine::infoScore {line} {
	if {![regexp {\mscore (cp|mate) (-?\d+)} $line _ kind value]} { return {} }
	return [list $kind $value]
}


# Draw-offer rule: the engine accepts a flat position, and only after
# move 30 (<plies> is the mainline length in plies).
proc ::playengine::drawAccept {plies cp mate} {
	if {$plies < [set ::playengine::DrawMinPly]} { return 0 }
	if {$cp eq ""} { return [expr {$mate ne "" && $mate == 0}] }
	if {$mate ne "" && $mate != 0} { return 0 }
	return [expr {abs($cp) <= [set ::playengine::DrawMaxCp]}]
}


# Half-move clock >= 100: the automatic end of the fifty-move rule.
proc ::playengine::fiftyMoves {fen} {
	set clock [lindex $fen 4]
	return [expr {[string is integer -strict $clock] && $clock >= 100}]
}


# Occurrence count of the current position (placement, side, castling and
# ep squares all match) across the game; the third is the repetition.
proc ::playengine::repetition {} {
	if {[catch { ::scidb::game::query mainline } plies]} { return 0 }
	set key [repKey [::scidb::pos::fen]]
	set count 1
	foreach ply $plies {
		if {[repKey [lindex $ply 2]] eq $key} { incr count }
	}
	return [expr {$count >= 3}]
}


proc ::playengine::repKey {fen} {
	return [join [lrange $fen 0 3] " "]
}


# No side can mate: no queens, rooks or pawns, and at most one minor
# piece per side (kb-vs-kb draws only when the bishops share a colour).
proc ::playengine::insufficientMaterial {fen} {
	set board [lindex $fen 0]
	if {[regexp {[qQrRpP]} $board]} { return 0 }
	set bishops {}
	set minors 0
	set y 7
	set n 0
	foreach ch [split $board {}] {
		if {[string is digit -strict $ch]} {
			incr n $ch
			continue
		}
		if {$ch eq "/"} { incr y -1; set n 0; continue }
		set x $n
		incr n
		if {$ch in {B b N n}} {
			incr minors
			if {$ch in {B b}} { lappend bishops [expr {($x + $y) % 2}] }
		}
	}
	if {$minors <= 1} { return 1 }
	return [expr {[llength $bishops] == 2 && [lindex $bishops 0] == [lindex $bishops 1]}]
}


# Is the side to move of <fen> in check? (game::query over? does not
# distinguish mate from stalemate; Board::checkState is not exposed.)
proc ::playengine::inCheck {fen} {
	lassign $fen board stm
	set squares {}
	set y 7
	set n 0
	foreach ch [split $board {}] {
		if {[string is digit -strict $ch]} {
			incr n $ch
			continue
		}
		if {$ch eq "/"} { incr y -1; set n 0; continue }
		lappend squares $ch $n $y
		incr n
	}
	set own [expr {$stm eq "b" ? "k" : "K"}]
	array set grid {}
	set kx -1
	set ky -1
	foreach {piece x y} $squares {
		set grid($x,$y) $piece
		if {$piece eq $own} { set kx $x; set ky $y }
	}
	if {$kx < 0} { return 0 }
	# opponent's pieces are uppercase when the side to move is black
	set opp [expr {$stm eq "b" ? 1 : 0}]

	foreach {piece x y} $squares {
		set white [string is upper -strict $piece]
		if {$white != $opp} { continue }
		set dx [expr {$kx - $x}]
		set dy [expr {$ky - $y}]
		switch -- [string toupper $piece] {
			P {
				# white pawns attack the rank ahead, black pawns behind
				set fwd [expr {$white ? 1 : -1}]
				if {abs($dx) == 1 && $dy == $fwd} { return 1 }
			}
			N {
				if {(abs($dx) == 1 && abs($dy) == 2) || (abs($dx) == 2 && abs($dy) == 1)} { return 1 }
			}
			K {
				if {max(abs($dx), abs($dy)) == 1} { return 1 }
			}
			B - R - Q {
				if {[Step grid $piece $x $y $dx $dy]} { return 1 }
			}
		}
	}
	return 0
}


# Sliders only: does <piece> at x,y run along the clear diagonal/line
# to the offset dx,dy? <gridArr> is the caller's board array name.
proc ::playengine::Step {gridArr piece x y dx dy} {
	upvar $gridArr grid

	switch -- [string toupper $piece] {
		B { if {abs($dx) != abs($dy) || $dx == 0} { return 0 } }
		R { if {$dx != 0 && $dy != 0} { return 0 } }
		Q { if {abs($dx) != abs($dy) && $dx != 0 && $dy != 0} { return 0 } }
		default { return 0 }
	}
	if {$dx == 0 && $dy == 0} { return 0 }
	set stepx [expr {$dx == 0 ? 0 : $dx / abs($dx)}]
	set stepy [expr {$dy == 0 ? 0 : $dy / abs($dy)}]
	set nx [expr {$x + $stepx}]
	set ny [expr {$y + $stepy}]
	while {$nx != $x + $dx || $ny != $y + $dy} {
		if {[info exists grid($nx,$ny)]} { return 0 }
		incr nx $stepx
		incr ny $stepy
	}
	return 1
}

# vi:set ts=3 sw=3:
