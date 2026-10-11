# ======================================================================
# Author : $Author$
# Version: $Revision: 1527 $
# Date   : $Date: 2018-10-26 08:11:06 -0400 (Fri, 26 Oct 2018) $
# Url    : $URL$
# ======================================================================

# ======================================================================
#    _/|            __
#   // o\         /    )           ,        /    /
#   || ._)    ----\---------__----------__-/----/__-
#   //__\          \      /   '  /    /   /    /   )
#   )___(     _(____/____(___ __/____(___/____(___/_
# ======================================================================

# ======================================================================
# Copyright: (C) 2009-2018 Gregor Cramer
# ======================================================================

# ======================================================================
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# ======================================================================

::util::source board-pane

namespace eval application {
namespace eval board {
namespace eval mc {

set ShowCrosstable			"Show tournament table for this game"
set StartEngine				"Start chess analysis engine in new window"
set InsertNullMove			"Insert null move"
set SelectStartPosition		"Select Start Position"
set LoadRandomGame			"Load random game"
set AddNewGame					"Add New Game..."
set SlidingVarPanePosition	"Sliding variation pane position"
set ShowVariationArrows		"Show variation arrows"
set ShowAnnotation			"Show annotation glyph"
set ShowAnnotationTimeout	"Timeout for annotation glyph"
set None							"None"

set MarkPromotedPiece		"Use mark for promoted pieces"
set PromoSign(none)			"None"
set PromoSign(bullet)		"Bullet"
set PromoSign(star)			"Star"
set PromoSign(disk)			"Disk"

set Tools						"Tools"
set Control						"Control"
set Database					"Database"
set GoIntoNextVar				"Go into next variation"
set GoIntPrevVar				"Go into previous variation"

set LoadGame(next)			"Load next game"
set LoadGame(prev)			"Load previous game"
set LoadGame(first)			"Load first game"
set LoadGame(last)			"Load last game"
set LoadFirstLast(next)		"End of list reached, continue with first game?"
set LoadFirstLast(prev)		"Start of list reached, continue with last game?"

set SwitchView(base)			"Switch to database view"
set SwitchView(list)			"Switch to game list view"

set Accel(edit-annotation)	"A"
set Accel(edit-comment)		"C"
set Accel(edit-marks)		"M"
set Accel(add-new-game)		"S"
set Accel(replace-game)		"R"
set Accel(replace-moves)	"V"
set Accel(trial-mode)		"T"
set Accel(export-game)		"E"
set Accel(import-game)		"I"

} ;# namespace mc

namespace import ::tcl::mathfunc::max
namespace import ::tcl::mathfunc::min
namespace import ::tcl::mathfunc::abs

variable board {}

variable Vars
variable Dim
variable Layouts {Normal ThreeCheck Crazyhouse}

set Defaults(coords-font-family) [font configure TkDefaultFont -family]

array set Options {
	variations:arrows		0
	show:annotation		0
	annotation:timeout	1500
	promoted:mark			bullet
}


proc build {w width height} {
	variable Dim
	variable Vars
	variable Options
	variable Layouts
	variable board

	set Vars(variant) Normal
	set Vars(layout) Normal
	set Vars(initialized) 0
	set Vars(afterid:switched) {}

	pack [set canv [tk::canvas $w.c -takefocus 1 -borderwidth 0]] -fill both -expand yes
	$canv xview moveto 0
	$canv yview moveto 0
	SetBackground $canv window $width $height
	set border [tk::canvas $canv.border -takefocus 0 -borderwidth 0]
	$border xview moveto 0
	$border yview moveto 0
	Preload $width [expr {$height - [[winfo parent $w] get $w Extent 74]}]
	set board [::board::diagram::new $border.diagram $Dim(squaresize:Normal) \
		-bordersize $Dim(edgethickness) \
		-bordertype lines \
		-promosign $Options(promoted:mark) \
		-targets [list $border $canv] \
	]
	set boardc [::board::diagram::canvas $board]
	::variation::build $canv [namespace code SelectAlternative]

	set family [font configure TkTextFont -family]
	set size [font configure TkTextFont -size]
	if {$size < 0} { incr size -6 } else { incr size 6 }
	set Vars(annotation) ""
	tk::label $canv.annotation \
		-textvar [namespace current]::Vars(annotation) \
		-takefocus 0 \
		-borderwidth 1 \
		-relief solid \
		-background yellow \
		-foreground darkred \
		-font [list $family $size normal] \
		;
	$canv create window 0 0 -anchor ne -window $canv.annotation -state hidden -tags annotation

	set targets [list $boardc $border $canv]
	foreach color {w b} {
		set Vars(holding:$color) \
			[::board::holding::new $canv.holding-$color $color $Dim(squaresize:Normal) \
			-targets $targets \
			-dragcursor hand2 \
		]
	}
	::bind $Vars(holding:w) <<InHandSelection>> { ::move::inHandSelected %W %d }
	::bind $Vars(holding:b) <<InHandSelection>> { ::move::inHandSelected %W %d }
	::bind $Vars(holding:w) <<InHandPieceDrop>> { ::move::inHandPieceDrop %W %x %y %s %d }
	::bind $Vars(holding:b) <<InHandPieceDrop>> { ::move::inHandPieceDrop %W %x %y %s %d }
	::bind $Vars(holding:w) <<InHandDropPosition>> { ::move::inHandDropPosition %W %x %y %s %d }
	::bind $Vars(holding:b) <<InHandDropPosition>> { ::move::inHandDropPosition %W %x %y %s %d }
	$canv create window 0 0 -window $border -anchor nw -tag board
	$border create window 0 0 -window $board -anchor nw -tag board
	set Vars(widget:border) $border
	set Vars(widget:frame) $canv
	set Vars(3d) 0
	set Vars(3dwin) {}
	set Vars(autoplay) 0
	set Vars(active) 0
	set Vars(material) {}
	set Vars(registered:0) {}
	set Vars(registered:1) {}
	set Vars(subscribe:list) {}
	set Vars(subscribe:info) {}
	set Vars(current:game) {}
	set Vars(load:method) base
	set Vars(select-var-is-pending) 0
	set Vars(width) $width
	set Vars(height) $height
	set Vars(dimensions) ${width}x${height}
	foreach layout $Layouts {
		set Vars(inuse:$layout) {}
		set Vars(registered:$layout) 0
		set Vars(registered:$layout) 0
	}

	$board configure -cursor crosshair
	::bind $canv <Configure> [namespace code { ConfigureWindow %W %w %h }]
	::bind $canv <Destroy> [namespace code [list activate $w 0]]
	::bind $canv <FocusIn> [namespace code { GotFocus %W }]
	::bind $canv <FocusOut> [namespace code LostFocus]
	::bind $canv <Any-Button> { ::variation::hide; ::move::cancelVariation }
	::bind $canv <<FontSizeChanged>> [list after idle [namespace code Redraw]]

	foreach {bind canvas} [list ::bind $canv ::bind $border ::board::diagram::bind $board] {
		if {[tk windowingsystem] eq "x11"} {
			$bind $canvas <Button-4> [namespace code [list goto -1]]
			$bind $canvas <Button-5> [namespace code [list goto +1]]
		} else {
			$bind $canvas <MouseWheel> "[namespace code goto] \[expr {%D < 0 ? +1 : -1}\]"
		}
	}

	::board::diagram::bind $board all <Enter>					{ ::move::enterSquare %q }
	::board::diagram::bind $board all <Leave>					{ ::move::leaveSquare %q }
	::board::diagram::bind $board all <ButtonPress-1>		{ ::move::pressSquare %q %s }
	::board::diagram::bind $board all <ButtonPress-1>		{+::focus %W }
	::board::diagram::bind $board all <ButtonPress-2>		{ ::move::nextGuess %X %Y }
	::board::diagram::bind $board all <ButtonRelease-1>	{ ::move::releaseSquare %X %Y %s }
	::board::diagram::bind $board all <Button1-Motion>		{ ::move::dragPiece %X %Y %s }

	::board::diagram::bind $board all <Control-ButtonPress-1>	{ ::marks::pressSquare %X %Y }
	::board::diagram::bind $board all <Control-ButtonPress-1>	{+::move::disable }
	::board::diagram::bind $board all <Control-ButtonRelease-1>	{ ::marks::unpressSquare }

	::bind .application <<ControlOn>>	{ ::move::disable }
	::bind .application <<ControlOff>>	{ ::move::enable %X %Y }
	::bind .application <<ControlOff>>	{+::marks::releaseSquare }
	::bind .application <FocusOut>		{ ::move::enable }
	::bind .application <FocusOut>		{+::marks::releaseSquare }
	::bind .application <FocusOut>		+[namespace code LostFocus]

	::board::diagram::update $board standard
	::board::unregisterSize $Dim(squaresize:Normal)

	::toolbar::setup $w -id board -layout board
	set tbTools		[::toolbar::toolbar $w \
							-hide 1 \
							-id board-tools \
							-tooltipvar [namespace current]::mc::Tools \
						]
	set tbLayout	[::toolbar::toolbar $w \
							-hide 1 \
							-id board-layout \
							-tooltipvar ::mc::Layout \
						]
	set tbControl	[::toolbar::toolbar $w \
							-hide 1 \
							-id board-control \
							-tooltipvar [namespace current]::mc::Control \
							-side bottom \
							-alignment center \
						]
	set tbDatabase	[::toolbar::toolbar $w \
							-hide 1 \
							-id board-database \
							-tooltipvar [namespace current]::mc::Database \
							-side top \
						]

#	::toolbar::add $tbTools button -image $::icon::toolbarGameList			-command {}
#	::toolbar::add $tbTools button -image $::icon::toolbarGameNotation	-command {}
#	::toolbar::add $tbTools button -image $::icon::toolbarMaintenance		-command {}
#	::toolbar::add $tbTools button -image $::icon::toolbarEcoBrowser		-command {}
#	::toolbar::add $tbTools button -image $::icon::toolbarTreeWindow		-command {}

#	set Vars(crossTable) [::toolbar::add $tbTools button \
#		-image $::icon::toolbarCrossTable \
#		-command [namespace code [list ShowCrossTable [winfo toplevel $board]]] \
#		-tooltipvar [namespace current]::mc::ShowCrosstable \
#	]
	::toolbar::add $tbTools button \
		-image $::icon::toolbarEngine \
		-command [list ::engine::openSetup .application] \
		-tooltipvar [namespace current]::mc::StartEngine \
		;

	::toolbar::add $tbLayout button \
		-image $::icon::toolbarRotateBoard \
		-tooltipvar ::overview::mc::RotateBoard \
		-command [namespace code [list Rotate $canv]]
		;
	::toolbar::add $tbLayout checkbutton \
		-image $::icon::toolbarSuggestion \
		-variable ::board::hilite(show-suggested) \
		-tooltipvar ::board::options::mc::ShowSuggestedMove \
		;
	::toolbar::add $tbLayout checkbutton \
		-image $::icon::toolbarSideToMove \
		-variable ::board::layout(side-to-move) \
		-tooltipvar ::board::options::mc::ShowSideToMove \
		-command [namespace code Apply] \
		;

	set Vars(game:prev) [::toolbar::add $tbDatabase button \
		-image $::icon::toolbarPrev \
		-command [namespace code [list LoadGame(any) $w prev]] \
		-state disabled \
	]
	set Vars(game:next) [::toolbar::add $tbDatabase button \
		-image $::icon::toolbarNext \
		-command [namespace code [list LoadGame(any) $w next]] \
		-state disabled \
	]
	set Vars(game:first) [::toolbar::add $tbDatabase button \
		-image $::icon::toolbarFront \
		-command [namespace code [list LoadGame(any) $w first]] \
		-state disabled \
	]
	set Vars(game:last) [::toolbar::add $tbDatabase button \
		-image $::icon::toolbarBack \
		-command [namespace code [list LoadGame(any) $w last]] \
		-state disabled \
	]
	set Vars(game:view) [::toolbar::add $tbDatabase button \
		-image $::icon::toolbarDatabase \
		-command [namespace code SwitchGameButtons] \
		-tooltipvar [namespace current]::mc::SwitchView(list) \
	]
	set Vars(game:random) [::toolbar::add $tbDatabase button \
		-image $::icon::toolbarDiceGreen \
		-command [namespace code [list LoadGame(any) $w random]] \
		-tooltipvar [namespace current]::mc::LoadRandomGame \
		-state disabled \
	]
	::toolbar::addSeparator $tbDatabase
	set Vars(game:replace) [::toolbar::add $tbDatabase button \
		-image $::icon::toolbarSave \
		-command [namespace code [list SaveGame replace]] \
		-state disabled \
	]
	set Vars(game:save) [::toolbar::add $tbDatabase dropdownbutton \
		-image $::icon::toolbarSaveAs \
		-command [namespace code [list SaveGame add]] \
		-arrowttipvar [namespace current]::mc::AddNewGame \
		-state disabled \
		-menucmd ::gamebar::addDestinationsForSaveToMenu \
	]

	foreach {action key} {	GotoStart start
									FastBack  -10
									Back      -1
									Fwd       +1
									FastFwd   +10
									GotoEnd   end} {
		set Vars(control:[string tolower $action 0]) \
			[::toolbar::add $tbControl button \
				-state disabled \
				-image [set ::icon::toolbarCtrl${action}] \
				-command [namespace code [list Goto $key]] \
			]
	}

	::toolbar::addSeparator $tbControl
	set Vars(control:enterVar) [::toolbar::add $tbControl button \
		-state disabled \
		-image [set ::icon::toolbarCtrlEnterVar] \
		-command [namespace code { Goto down }]]
	set Vars(control:leaveVar) [::toolbar::add $tbControl button \
		-state disabled \
		-image [set ::icon::toolbarCtrlLeaveVar] \
		-command [namespace code { Goto up }]]

	needBinding $Vars(widget:border)
	needBinding $Vars(widget:frame)
	needBinding $Vars(holding:w)
	needBinding $Vars(holding:b)
	needBinding [::board::diagram::canvas $board]

	foreach w $Vars(need-binding) {
		::font::addChangeFontSizeBindings editor $w ::application::pgn::fontSizeChanged
	}
	
	bind <Key-space>				::move::nextGuess
	bind <Left>						[namespace code { Goto -1 }]
	bind <Right>					[namespace code { Goto +1 }]
	bind <Prior>					[namespace code { Goto -10 }]
	bind <Next>						[namespace code { Goto +10 }]
	bind <Home>						[namespace code { Goto start }]
	bind <End>						[namespace code { Goto end }]
	bind <Down>						[namespace code { Goto down }]
	bind <Up>						[namespace code { Goto up }]
	bind <Control-Down>			[namespace code [list LoadGame(any) $w next]]
	bind <Control-Up>				[namespace code [list LoadGame(any) $w prev]]
	bind <Control-Home>			[namespace code [list LoadGame(any) $w first]]
	bind <Control-End>			[namespace code [list LoadGame(any) $w last]]
	bind <Shift-Up>				[list [namespace parent]::pgn::scroll -1 units]
	bind <Shift-Down>				[list [namespace parent]::pgn::scroll +1 units]
	bind <Shift-Prior>			[list [namespace parent]::pgn::scroll -1 pages]
	bind <Shift-Next>				[list [namespace parent]::pgn::scroll +1 pages]
	bind <Shift-Home>				[list [namespace parent]::pgn::scroll -9999 pages]
	bind <Shift-End>				[list [namespace parent]::pgn::scroll +9999 pages]
	bind <Control-0>				[namespace code InsertNullMove]
	bind <<Undo>>					[namespace parent]::pgn::undo
	bind <<Redo>>					[namespace parent]::pgn::redo
	bind <BackSpace>				[namespace parent]::pgn::undoLastMove
	bind <Delete>					[list ::scidb::game::strip truncate]
	bind <ButtonPress-3>			[namespace code { PopupMenu %W }]
	bind <<LanguageChanged>>	[namespace code LanguageChanged]
	bind <F1>						[list ::help::open .application]
	bind <F5>						[list ::move::nextVariation]

	set tl [winfo toplevel $w]

	# the Alt-Key binding isn't working, so do it by hand
	set cmd [list tk::AltKeyInDialog $tl %A]
	for {set i 0} {$i < 26} {incr i} {
		set c [::util::intToChar $i]
		bind <Alt-Key-$c> $cmd
		bind <Alt-Key-[string tolower $c]> $cmd
	}

	bind <Alt-Key-s> [list ::application::pgn::showDiagram %W %K %s]
	bind <Alt-Key-S> [list ::application::pgn::showDiagram %W %K %s]

	# for sliding pane
	foreach key {Escape Return Shift-Left Shift-Right} { bind <$key> {} }

	# for sliding pane
	for {set i 0} {$i <= 35} {incr i} {
		if {$i < 10} {
			bind <Key-$i> {}
			bind <Key-KP_$i> {}
		} else {
			set k [::util::intToChar [expr {$i - 10}]]
			bind <Key-$k> {}
			bind <Key-[string tolower $k]> {}
		}
	}

	for {set i 1} {$i <= 9} {incr i} {
		bind <Control-Key-$i>    [namespace code [list [namespace parent]::pgn::selectAt [expr {$i - 1}]]]
		# NOTE: the working of the following depends on actual keyboard bindings!
		bind <Control-Key-KP_$i> [namespace code [list [namespace parent]::pgn::selectAt [expr {$i - 1}]]]
	}

	set Vars(after) {}

	BuildBoard $canv
	ConfigureBoard $canv
	SetupToolbar

	::scidb::db::subscribe gameSwitch [namespace current]::GameSwitched
	::scidb::db::subscribe gameClose [namespace current]::GameClosed
	::scidb::db::subscribe databaseSwitch [namespace current]::DatabaseSwitched
	::scidb::db::subscribe dbInfo [namespace current]::UpdateInfo
}


proc activate {w flag} {
	variable Vars

	if {![winfo exists $w]} { return }

	set Vars(active) $flag
	::toolbar::activate $w $flag

	if {$flag} {
		# while the hardware 3D view is embedded it holds the focus, so
		# plain keys are forwarded to the (hidden) 2D board
		if {$Vars(3d)
			&& $Vars(3dwin) ne "" && [winfo exists $Vars(3dwin)]
			&& $::board3d::Priv(embed,togl) ne ""
			&& [winfo exists $::board3d::Priv(embed,togl)]} {
			focus $::board3d::Priv(embed,togl)
		} else {
			focus $Vars(widget:frame)
		}
	}

	[namespace parent]::pgn::activate $w $flag
	if {$flag && $Vars(initialized) == 0} {
		set Vars(initialized) 1
		after idle [namespace code [list RebuildBoard $Vars(widget:frame) $Vars(width) $Vars(height) true]]
	} elseif {$Vars(initialized) == 0} {
		set Vars(initialized) 1
	}
}


# Switch the board pane between the 2D diagram and the embedded hardware
# 3D view.  Returns 1 on success; 0 when the 3D view could not be set up
# (in which case the pane stays on the 2D board).

# Swap presentations in the same layout slot, retaining docking padding,
# expansion and sibling order in either direction.
proc ReplaceBoardView {from to} {
	if {[winfo manager $from] eq "pack"} {
		pack $to {*}[pack info $from] -before $from
		pack forget $from
	} else {
		pack $to -fill both -expand yes
	}
}

proc show3D {flag} {
	variable Vars

	if {$flag} {
		if {![llength [info commands ::board3d::embed]]} { return 0 }
		if {$Vars(3dwin) eq "" || ![winfo exists $Vars(3dwin)]} {
			set Vars(3dwin) [::board3d::embed $Vars(widget:frame)]
			if {$Vars(3dwin) eq ""} {
				if {[llength [info commands tk_messageBox]]} {
					catch {
						tk_messageBox -parent .application -icon warning -type ok \
							-title "Chesswiz" \
							-message "3D in the main window is unavailable.\n\n$::board3d::Priv(embed,error)"
					}
				}
				return 0
			}
		}
		ReplaceBoardView $Vars(widget:frame) $Vars(3dwin)
		set Vars(3d) 1
		::board3d::refresh
	} else {
		if {$Vars(3dwin) ne "" && [winfo exists $Vars(3dwin)]} {
			ReplaceBoardView $Vars(3dwin) $Vars(widget:frame)
		}
		set Vars(3d) 0
	}
	return 1
}


proc closed {w} {
	# should only happen after shutdown
}


proc setActive {flag} {
	variable Vars

	::move::enable ;# required here because <<ControlOff>> might fail
	::marks::releaseSquare

#	if {$flag && $Vars(active) && [focus] ne $Vars(widget:frame)} {
#		setFocus
#	}
}


proc setFocus {} {
	focus [set [namespace current]::Vars(widget:frame)]
}


proc active? {} {
	return [set [namespace current]::Vars(active)]
}


proc setCursor {{type crosshair}} {
	variable board

	if {[$board cget -cursor] ne $type} {
		$board configure -cursor $type
	}
}


proc ToggleAutoPlay {} {
	variable Vars
	if {[info exists ::application::media::Priv(inprocess)]
		&& $::application::media::Priv(inprocess)} {
		# The media clock advances the board at the commentary timestamps.
		after cancel $Vars(afterid)
		set Vars(autoplay) 0
		::application::media::TogglePlayback
		return
	}
	set Vars(autoplay) [expr {!$Vars(autoplay)}]
	if {$Vars(autoplay)} {
		goto +1
	} else {
		after cancel $Vars(afterid)
	}
}

proc goto {step} {
	variable Vars

	set Vars(select-var-is-pending) 0
	::variation::hide
	::move::cancelVariation
	::scidb::game::go -1 $step

	if {$Vars(autoplay)} {
		if {[::scidb::game::position -1 atEnd?]} {
			ToggleAutoPlay
		} else {
			variable ::browser::Options
			after cancel $Vars(afterid)
			set Vars(afterid) [after $Options(autoplayDelay) [namespace code { goto +1 }]]
		}
	}
}


proc deselectInHandPiece {} {
	variable Vars

	::board::holding::deselect $Vars(holding:w)
	::board::holding::deselect $Vars(holding:b)
}


proc finishDrop {} {
	variable Vars

	set color [::scidb::game::query stm]
	::board::holding::finishDrop $Vars(holding:[string index $color 0])
}


proc update {position cmd data promoted} {
	variable ::board::layout
	variable board
	variable Vars

	switch $cmd {
		set	{ ::board::diagram::update $board $data $promoted }
		move	{ ::board::diagram::move $board $data }
	}

	set Vars(select-var-is-pending) 0
	::board::diagram::clearMarks $board
	UpdateSideToMove $Vars(widget:frame)
	DrawMaterialValues $Vars(widget:frame)
	DrawChecks $Vars(widget:frame)
	UpdateControls
	::variation::hide 0
	::move::cancelVariation

	# media panel coupling: position-keyed playback + follow-mode reseek
	# (no-ops unless a lesson/media is loaded; ::media::sync::driving?
	# filters notifications produced by the follow tick itself)
	if {[namespace which ::application::media::BoardUpdated] ne ""} {
		::application::media::BoardUpdated $position
	}

	# 3D board view mirrors the position (no-op unless the viewer is open)
	if {[llength [info commands ::board3d::PositionChanged]]} {
		::board3d::PositionChanged [::board::diagram::data $board]
	}
}


proc updateMarks {marks} {
	variable board
	variable Vars

	if {[[namespace parent]::pgn::showMarkers]} {
		::board::diagram::updateMarks $board $marks
		# 3D board views mirror the game marks (no-op unless loaded)
		if {[llength [info commands ::board3d::setMarks]]} {
			::board3d::setMarks $marks
		}
		if {!$Vars(autoplay)} {
			::move::leaveSquare
			::move::enterSquare
		}
	}
}


proc toggleShowMarkers {flag} {
	variable board

	if {[[namespace parent]::pgn::showMarkers]} {
		::scidb::game::go current
	} else {
		::board::diagram::clearMarks $board
		if {[llength [info commands ::board3d::setMarks]]} {
			::board3d::setMarks {}
		}
	}
}


proc rotated? {} {
	variable board
	return [::board::diagram::rotated? $board]
}


proc bind {key cmd} {
	variable Vars

	foreach w $Vars(need-binding) {
		::bind $w $key [namespace code [list FilterKey %K %s $cmd]]
		::bind $w $key {+ break }
	}
}


proc unbindGameControls {position base variant} {
	variable Vars

	Unsubscribe $position
	set Vars(current:game) {}
	UpdateGameButtonState(list) $position
}


proc needBinding {w} {
	variable Vars
	lappend Vars(need-binding) $w
}


proc bindKeys {} {
	variable Vars
	variable mc::Accel

	if {![info exists Vars(cmd:export-game)]} {
		foreach key [array names Accel] { set Vars(key:$key) $Accel($key) }

		set Vars(cmd:edit-annotation)		[namespace parent]::pgn::editAnnotation
		set Vars(cmd:edit-comment)			[list [namespace parent]::pgn::editComment after]
		set Vars(cmd:shift:edit-comment)	[list [namespace parent]::pgn::editComment before]
		set Vars(cmd:edit-marks)			[namespace parent]::pgn::openMarksPalette
		set Vars(cmd:add-new-game)			[namespace code [list SaveGame add]]
		set Vars(cmd:replace-game)			[namespace code [list SaveGame replace]]
		set Vars(cmd:replace-moves)		[namespace code [list SaveGame moves]]
		set Vars(cmd:trial-mode)			[namespace parent]::pgn::flipTrialMode
		set Vars(cmd:import-game)			[list [namespace parent]::pgn::importGame no]
		set Vars(cmd:shift:import-game)	[list [namespace parent]::pgn::importGame yes]
		set Vars(cmd:export-game)			[list ::gamebar::exportGame .application]
	}

	foreach key [array names Accel] {
		bind <Control-[string tolower $Vars(key:$key)]> {}
		bind <Control-[string toupper $Vars(key:$key)]> {}
	}

	bind <Control-Shift-[string tolower $Vars(key:edit-comment)]> {}
	bind <Control-Shift-[string toupper $Vars(key:edit-comment)]> {}
	bind <Control-Shift-[string tolower $Vars(key:import-game)]> {}
	bind <Control-Shift-[string toupper $Vars(key:import-game)]> {}

	foreach key [array names Accel] {
		bind <Control-[string tolower $Accel($key)]> $Vars(cmd:$key)
		bind <Control-[string toupper $Accel($key)]> $Vars(cmd:$key)
		set Vars(key:$key) $Accel($key)
	}

	bind <Control-Shift-[string tolower $Accel(edit-comment)]> $Vars(cmd:shift:edit-comment)
	bind <Control-Shift-[string toupper $Accel(edit-comment)]> $Vars(cmd:shift:edit-comment)

	bind <Control-Shift-[string tolower $Accel(import-game)]> $Vars(cmd:shift:import-game)
	bind <Control-Shift-[string toupper $Accel(import-game)]> $Vars(cmd:shift:import-game)
}


proc SetupToolbar {} {
	variable Vars

	foreach {action key tipvar} {	GotoStart	Home	GotoStartOfGame
											FastBack		Prior	GoBackFast
											Back			Left	GoBackward
											Fwd			Right	GoForward
											FastFwd		Next	GoForwardFast
											GotoEnd		End	GotoEndOfGame} {
		set tip "[set ::browser::mc::$tipvar] ($::mc::Key($key))"
		::toolbar::childconfigure $Vars(control:[string tolower $action 0]) -tooltip $tip
	}

	foreach {action key tipvar} {	EnterVar		Down	GoIntoNextVar
											LeaveVar		Up		GoIntPrevVar} {
		set tip "[set mc::$tipvar] ($::mc::Key($key))"
		::toolbar::childconfigure $Vars(control:[string tolower $action 0]) -tooltip $tip
	}

	foreach {action key} {next Down prev Up first Home last End} {
		set tip $mc::LoadGame($action)
		append tip " (" $::mc::Key(Ctrl) "-" $::mc::Key($key) ")"
		::toolbar::childconfigure $Vars(game:$action) -tooltip $tip
	}
}


proc FilterKey {key state cmd} {
	variable Vars

	switch [::variation::handle $key $state] {
		0 {
			::variation::hide
			::move::cancelVariation
			if {[llength $cmd]} { {*}$cmd }
		}

		1 {
			set Vars(select-var-is-pending) 0
		}

		2 {
			set Vars(select-var-is-pending) 0
			if {[llength $cmd]} {
				if {[string match {* Goto +1 *} $cmd]} {
					goto +1
				} else {
					{*}$cmd
				}
			}
		}
	}
}


proc Goto {step} {
	variable Options
	variable Vars
	variable board

	if {	$step == +1
		&& !$Vars(select-var-is-pending)
		&& ([::variation::use?] || $Options(variations:arrows))
		&& [llength [set vars [::scidb::pos::nextMoves]]] > 1} {
		set rvars [list {*}[lrange $vars 1 end] [lindex $vars 0]]
		if {$Options(variations:arrows)} {
			# draw main line last, a variation should not overlap the main line
			set Vars(select-var-is-pending) 1
			set i 1
			foreach entry $rvars {
				lassign $entry _ from to
				if {$i == 0} { set color yellow } else { set color greenyellow }
				set cmd [namespace code [list SelectAlternative $i]]
				::board::diagram::drawAlternative $board $from $to $color $cmd
				if {[incr i] == [llength $vars]} { set i 0 }
			}
		}
		if {[::variation::use?]} {
			$Vars(widget:frame) itemconfigure annotation -state hidden
			set moves {}
			foreach entry $vars { lappend moves [::font::translate [lindex $entry 0]] }
			::variation::show $moves
			return
		}
		::move::cancelVariation
	} else {
		set Vars(select-var-is-pending) 0
		goto $step
	}

	if {$step == +1 && $Options(show:annotation)} {
		ShowAnnotation
	}
}


proc ShowAnnotation {} {
	variable Vars
	variable Options

	set text ""
	lassign [::scidb::game::query annotation] prf inf suf

	foreach list {prf inf suf} {
		foreach nag [set $list] {
			set nag [string range $nag 1 end]
			set t [::font::mapNagToUtfSymbol $nag]
			if {$nag != $t && [string length $text] == 0} {
				set text $t
			}
		}
	}

	if {[string length $text]} {
		set Vars(annotation) $text
		$Vars(widget:frame) itemconfigure annotation -state normal
		if {$Options(annotation:timeout) > 0} {
			after $Options(annotation:timeout) \
				[list $Vars(widget:frame) itemconfigure annotation -state hidden]
		}
	} else {
		$Vars(widget:frame) itemconfigure annotation -state hidden
	}
}


proc SelectAlternative {index} {
	variable Options

	if {$index >= 0 && $index <= [::scidb::game::count variations]} {
		if {$index > 0} { ::scidb::game::go variation [expr {$index - 1}] }
		::scidb::game::go +1
		if {$Options(show:annotation)} { ShowAnnotation }
	}
}


proc LoadGame(any) {w incr} {
	LoadGame([set [namespace current]::Vars(load:method)]) $w $incr
}


proc LoadGame(list) {w incr} {
	variable Vars

	if {[llength $Vars(current:game)] > 1} {
#		::widget::busyCursor on
		set number [LoadGame(all) $w {*}$Vars(current:game) $incr]
		lset Vars(current:game) 4 $number
		UpdateGameButtonState(list) [lindex $Vars(current:game) 0]
#		::widget::busyCursor off
	}
}


proc LoadGame(base) {w incr} {
#	::widget::busyCursor on
	set position [::scidb::game::current]
	lassign [::scidb::game::link? $position] base variant index
	set variant [::util::toMainVariant $variant]
	set currentBase [::scidb::db::get name]
	set currentVariant [::scidb::app::variant]

	if {$index >= 0 && $currentBase eq $base && $currentVariant eq $variant} {
		set number [::scidb::db::get gameNumber $base $variant $index -1]
	} else {
		set number -1
	}

	set n [LoadGame(all) $w $position $currentBase $currentVariant -1 $number $incr]
	UpdateGameButtonState(base) $currentBase $currentVariant
#	::widget::busyCursor off
}


proc LoadGame(all) {w position base variant view number incr} {
	variable Vars

	set numGames [scidb::view::count games $base $variant $view]
	if {$numGames == 0} { return }

	if {$view >= 0} {
		set prevNumber $number
		set number [scidb::game::view $position $incr]
		if {$number == -1} {
			set number [::scidb::db::get gameNumber $base $variant 0 $view]
			if {$prevNumber == $number} {
				set number [::scidb::db::get gameNumber $base $variant [expr {$numGames - 1}] $view]
			}
			return [LoadFirstLastGame $w $base $variant $view $number $incr]
		}
	} else {
		if {$incr eq "random"} {
			if {$numGames == 1} {
				set index 0
			} elseif {$number == -1} {
				set index [expr {min($numGames - 1, int(rand()*$numGames))}]
			} else {
				set index [::scidb::db::get gameIndex $number $view $base $variant]
				do { set i [expr {min($numGames - 1, int(rand()*$numGames))}] } while {$i == $index}
				set index $i
			}
		} elseif {$number == -1} {
			switch $incr {
				next - first	{ set index 0 }
				prev - last		{ set index [expr {$numGames - 1}] }
			}
		} else {
			if {$numGames <= 1} { return }
			set index [::scidb::db::get gameIndex $number $view $base $variant]
			if {$index == -1} { return }

			switch $incr {
				next	{ incr index +1 }
				prev	{ incr index -1 }
				first { set index 0 }
				last  { set index [expr {$numGames - 1}] }
			}

			if {$index < 0 || $numGames <= $index} {
				if {$index < 0} { set index [expr {$numGames - 1}] } else { set index 0 }
				set number [::scidb::db::get gameNumber $base $variant $index $view]
				return [LoadFirstLastGame $w $base $variant $view $number $incr]
			}
		}

		set number [::scidb::db::get gameNumber $base $variant $index $view]
	}

	return [LoadGame(single) $w $base $variant $view $number]
}


proc LoadGame(single) {w base variant view number} {
	if {[::scidb::tree::isRefBase? $base] && $view == [::scidb::tree::view]} {
		set fen [::scidb::tree::position]
	} else {
		set fen ""
	}
	::game::new .application -base $base -variant $variant -view $view -number $number -fen $fen
	return $number
}


proc LoadFirstLastGame {w base variant view number incr} {
	if {[::dialog::question \
			-parent $w \
			-message [set [namespace current]::mc::LoadFirstLast($incr)]] eq "yes"} {
		return [LoadGame(single) $w $base $variant $view $number]
	}
}


proc SwitchView {view} {
	variable Vars

	if {$Vars(load:method) ne $view} {
		set v $Vars(load:method)
		set Vars(load:method) $view
		::toolbar::childconfigure $Vars(game:view) -tooltipvar [namespace current]::mc::SwitchView($v)

		switch $view {
			list {
				UpdateGameButtonState(list) [::scidb::game::current]
				::toolbar::childconfigure $Vars(game:view) -image $::icon::toolbarList
			}
			base {
				UpdateGameButtonState(base) [::scidb::db::get name] [::scidb::app::variant]
				::toolbar::childconfigure $Vars(game:view) -image $::icon::toolbarDatabase
			}
		}
	}
}


proc SwitchGameButtons {} {
	variable Vars

	if {$Vars(load:method) eq "list"} { set view base } else { set view list }
	SwitchView $view
}


proc GotFocus {w} {
	variable Vars

	# we have to skip the focus if no game is open
	if {[::application::pgn::empty?]} { focus [::tk_focusNext $w] }
	set Vars(select-var-is-pending) 0
	::variation::hide 0
	::move::cancelVariation
	::move::enable
}


proc LostFocus {} {
	variable Vars

	set Vars(select-var-is-pending) 0
	::variation::hide 0
	::move::cancelVariation
}


proc Preload {width height} {
	variable ::board::layout
	variable Attr
	variable Dim

	set Dim(bordersize) 0
	set Dim(fontsize) 0
	ComputeLayout $width $height

	::board::registerSize $Dim(squaresize:Normal)
	::board::setupSquares $Dim(squaresize:Normal)
	::board::setupPieces $Dim(squaresize:Normal)
	::board::pieceset::registerFigurines $Dim(piece:size) $layout(material-bar)
	::board::pieceset::registerFigurines $Dim(piece:size) 0
}


proc ConfigureWindow {w width height} {
	variable Vars

	if {$width <= 1 || $height <= 1} { return }

	set Vars(width) $width
	set Vars(height) $height

	if {[::twm::frozen?]} {
		if {$Vars(initialized)} { SetBackground $Vars(widget:frame) window $width $height }
		return
	}

	if {$Vars(initialized)} {
		set parent [winfo parent $w]
		[winfo parent $parent] set $parent Extent [expr {[winfo height $parent] - $height}]
		after cancel $Vars(after)
		if {$Vars(initialized) == 1} {
			set timeout 300
			set Vars(initialized) 2
		} else {
			set timeout 100
		}
		set Vars(after) [after $timeout [namespace code [list RebuildBoard $w $width $height]]]
	}
}


proc afterTWM {} {
	variable Vars

	if !{[winfo exists $Vars(widget:frame)]} { return }
	ConfigureWindow $Vars(widget:frame) $Vars(width) $Vars(height)
}


proc SetBackground {canv which {width 0} {height 0}} {
	variable ::board::colors

	if {[llength $colors(hint,background-color)]} {
		$canv configure -background $colors(hint,background-color)
	} else {
		::theme::configureBackground $canv
	}
	::board::setBackground $canv window $width $height
}


proc PopupMenu {w} {
	variable Options
	variable Vars
	variable board

	set m $w.popup_menu
	if {[winfo exists $m]} { destroy $m }
	menu $m -tearoff false
	catch { wm attributes $m -type popup_menu }

	if {[llength [info commands ::application::assistant::offers::AskAboutBoard]]} {
		$m add command \
			-compound left \
			-image $::icon::16x16::none \
			-label " $::application::assistant::offers::mc::AskAbout" \
			-command ::application::assistant::offers::AskAboutBoard \
			;
		$m add separator
	}

	$m add command \
		-compound left \
		-image $::icon::16x16::rotateBoard \
		-label " $::overview::mc::RotateBoard" \
		-command [namespace code [list Rotate $Vars(widget:frame)]] \
		;
	set pos [menu $m.pos -tearoff false]
	$pos add command \
		-label " $::setup::board::mc::StandardPosition" \
		-image $::icon::16x16::home \
		-compound left \
		-command [list ::application::pgn::Shuffle Normal] \
		;
	foreach variant {Chess960 Symm960 Shuffle} {
		$pos add command \
			-label " $::setup::mc::Position($variant)" \
			-image $::icon::16x16::dice \
			-compound left \
			-command [list ::application::pgn::Shuffle $variant] \
			;
	}
	if {[::scidb::game::query variant?] eq "Normal"} {
		$pos add separator
		::setup::setupPositionMenu ::application::pgn $pos
	}
	$m add cascade \
		-menu $pos \
		-compound left \
		-image $::icon::16x16::checker \
		-label " $mc::SelectStartPosition" \
		;
	$m add command \
		-compound left \
		-image $::icon::16x16::checker \
		-label " $::setup::board::mc::SetStartBoard..." \
		-command [namespace code [list SetStartBoard $Vars(widget:frame)]] \
		;
	$m add command \
		-compound left \
		-image $::icon::16x16::checker \
		-label " $::setup::position::mc::SetStartPosition..." \
		-command [namespace code [list SetStartPosition $Vars(widget:frame)]] \
		;
	
	if {![::application::pgn::empty?] && ![::scidb::game::query over]} {
		$m add separator

		$m add command \
			-label " $mc::InsertNullMove" \
			-command { ::move::addMove dialog -- } \
			-accelerator "$::mc::Key(Ctrl)-0" \
			;
	}

	$m add separator

	$m add checkbutton \
		-label $::board::options::mc::ShowSideToMove \
		-variable ::board::layout(side-to-move) \
		-command [namespace code Apply] \
		;
	::theme::configureCheckEntry $m
	$m add checkbutton \
		-label $::board::options::mc::ShowMaterialValues \
		-variable ::board::layout(material-values) \
		-command [namespace code Apply] \
		;
	::theme::configureCheckEntry $m
	$m add checkbutton \
		-label $::board::options::mc::ShowMaterialBar \
		-variable ::board::layout(material-bar) \
		-state [expr {$::board::layout(material-values) ? "normal" : "disabled"}] \
		-command [namespace code Apply] \
		;
	::theme::configureCheckEntry $m
	$m add checkbutton \
		-label $::board::options::mc::ShowBorder \
		-variable ::board::layout(border) \
		-command [namespace code Apply] \
		;
	::theme::configureCheckEntry $m
	$m add checkbutton \
		-label $::board::options::mc::ShowCoordinates \
		-variable ::board::layout(coordinates) \
		-command [namespace code Redraw] \
		;
	::theme::configureCheckEntry $m
	$m add checkbutton \
		-label "$::board::options::mc::UseSmallLetters" \
		-variable ::board::layout(coords-small) \
		-command [namespace code RedrawCoordinates] \
		-state [expr {$::board::layout(coordinates) ? "normal" : "disabled"}] \
		;
	::theme::configureCheckEntry $m
	$m add checkbutton \
		-label $::board::options::mc::ShowSuggestedMove \
		-variable ::board::hilite(show-suggested) \
		-command [namespace code Apply] \
		;
	::theme::configureCheckEntry $m
	$m add checkbutton \
		-label $mc::ShowVariationArrows \
		-variable [namespace current]::Options(variations:arrows) \
		;
	::theme::configureCheckEntry $m
	$m add checkbutton \
		-label $mc::ShowAnnotation \
		-variable [namespace current]::Options(show:annotation) \
		;
	::theme::configureCheckEntry $m

	$m add separator
	if {[::board::options::isOpen]} { set state disabled } else { set state normal }
	$m add command \
		-compound left \
		-image $::icon::16x16::setup \
		-label " $::board::options::mc::BoardSetup..." \
		-command [list ::board::options::openConfigDialog $w [namespace current]::Redraw] \
		-state $state \
		;
	set slider [menu $m.slider -tearoff false]
	$m add cascade \
		-menu $slider \
		-compound left \
		-image $::icon::16x16::none \
		-label " $mc::SlidingVarPanePosition" \
		;
	::variation::addToMenu $slider
	set timeout [menu $m.timeout -tearoff false]
	$m add cascade \
		-menu $timeout \
		-compound left \
		-image $::icon::16x16::none \
		-label " $mc::ShowAnnotationTimeout" \
		;
	foreach s {1500 2000 2500 3000 3500 4000 4500 5000 0} {
		if {$s == 0} { set txt $mc::None } else { set txt $s }
		$timeout add radiobutton \
			-label $txt \
			-variable [namespace current]::Options(annotation:timeout) \
			-value $s \
			-command [list $Vars(widget:frame) itemconfigure annotation -state hidden] \
			;
		::theme::configureRadioEntry $timeout
	}
	if {[::scidb::game::query variant?] in {Crazyhouse}} {
		menu $m.promo
		$m add cascade \
			-menu $m.promo \
			-compound left \
			-image $::icon::16x16::none \
			-label " $mc::MarkPromotedPiece" \
			;
		foreach mark {none bullet star disk} {
			$m.promo add radiobutton \
				-label $mc::PromoSign($mark) \
				-variable [namespace current]::Options(promoted:mark) \
				-value $mark \
				-command [list ::board::diagram::setPromoSign $board $mark] \
				;
			::theme::configureRadioEntry $m.promo
		}
	}

	tk_popup $m {*}[winfo pointerxy $w]
}


proc InsertNullMove {} {
	if {![::application::pgn::empty?] && ![::scidb::game::query over]} {
		::move::addMove dialog --
	}
}


proc Apply {} {
	variable Vars

	if {$Vars(initialized) && [[namespace parent]::ready?]} {
		RebuildBoard $Vars(widget:frame) $Vars(width) $Vars(height) true
	}
}


proc Redraw {} {
	Apply
	RedrawCoordinates
}


proc RedrawCoordinates {} {
	variable ::board::layout
	variable Vars

	if {!$layout(coordinates)} { return }
	set border $Vars(widget:border)
	set canv $Vars(widget:frame)

	if {[llength [$border find withtag coords]] > 0} {
		foreach w [list $canv $border] {
			foreach c {A B C D E F G H} {
				set letter $c
				if {$layout(coords-small)} { set letter [string tolower $c] }
				$w itemconfigure cc$c -text $letter
			}
		}
	}
}


proc RebuildBoard {canv width height {force false}} {
	variable ::board::layout
	variable Layouts
	variable Dim
	variable Vars
	variable board

	set dimensions ${width}x${height}
	if {!$force && $dimensions eq $Vars(dimensions)} { return }
	set Vars(dimensions) $dimensions
	set sqsize squaresize:$Vars(layout)

	if {[info exists Dim($sqsize)]} {
		set squareSize $Dim($sqsize)
	} else {
		set squareSize $Dim(squaresize:Normal)
	}
	set edgeThickness $Dim(edgethickness)
	ComputeLayout $width $height $Dim(bordersize)
	SetBackground $canv window $width $height
	$canv coords board $Dim(border:x1) $Dim(border:y1)
	$canv coords annotation [expr {$Dim(border:x1) - 10}] [expr {$Dim(border:y1) + $Dim(borderthickness)}]
	$Vars(widget:border) coords board $Dim(borderthickness) $Dim(borderthickness)
	set bordersize [expr {$Dim(bordersize) + $Dim(border:gap)}]
	$Vars(widget:border) configure -width $bordersize -height $bordersize

	if {$Dim(border:gap) > 0} {
		$Vars(widget:border) configure -background black
	} else {
		$Vars(widget:border) configure -background [$canv cget -background]
	}

	set inuse(0) 0
	set inuse(1) 0
	if {$Vars(layout) eq "Normal" || $Vars(layout) eq "ThreeCheck"} {
		set pieceSize $Dim(piece:size)
		catch { set inuse(0) [image inuse photo_Piece(figurine,0,wq,$pieceSize)] }
		catch { set inuse(1) [image inuse photo_Piece(figurine,1,wq,$pieceSize)] }
		if {!$inuse($layout(material-bar))} {
			::board::pieceset::registerFigurines $pieceSize $layout(material-bar)
			set Vars(registered:$layout(material-bar)) [list $pieceSize $layout(material-bar)]
		}
		if {!$inuse(0)} {
			::board::pieceset::registerFigurines $pieceSize 0
			set Vars(registered:0) [list $pieceSize $layout(material-bar)]
		}
	}
	if {!$inuse(0) && [llength $Vars(registered:0)]} {
		::board::pieceset::unregisterFigurines {*}$Vars(registered:0)
	}
	if {!$inuse(1) && [llength $Vars(registered:1)]} {
		::board::pieceset::unregisterFigurines {*}$Vars(registered:1)
	}

	if {$squareSize != $Dim($sqsize) || $edgeThickness != $Dim(edgethickness)} {
		::update idletasks
		foreach l $Layouts {
			if {$l ne $Vars(layout) && [llength $Vars(inuse:$l)] && !$Vars(registered:$l)} {
				::board::registerSize $Vars(inuse:$l)
				set Vars(registered:$l) 1
			}
		}
		::board::diagram::resize $board $Dim($sqsize) -bordersize $Dim(edgethickness)
		if {$Vars(registered:$Vars(layout))} {
			::board::unregisterSize $Vars(inuse:$Vars(layout))
			set Vars(registered:$Vars(layout)) 0
		}
		set Vars(inuse:$Vars(layout)) $Dim($sqsize)
	} else {
		::board::diagram::rebuild $board
	}

	if {$Vars(layout) eq "Crazyhouse"} {
		::board::holding::resize $Vars(holding:w) $Dim($sqsize)
		::board::holding::resize $Vars(holding:b) $Dim($sqsize)
	}

	BuildBoard $canv
	ConfigureBoard $canv
	DrawMaterialValues $canv
	DrawChecks $canv
}


proc DrawMaterialValues {canv} {
	variable ::board::layout
	variable Vars

	if {$Vars(layout) eq "Normal" || $Vars(layout) eq "ThreeCheck"} {
		if {$layout(material-values)} {
			set material [::scidb::game::material]
			if {[string equal $material $Vars(material)]} { return }

			$canv delete material
			lassign $material p n b r q k

			if {$Vars(variant) ne "Crazyhouse"} {
				# match knights and bishops
				for {} {$n < 0 && $b > 0} {incr b -1} {incr n}
				for {} {$b < 0 && $n > 0} {incr n -1} {incr b}
			}

			set sum [expr {abs($p) + abs($n) + abs($b) + abs($r) + abs($q) + abs($k)}]
			set rank 0

			switch $Vars(variant) {
				Suicide - Giveaway	{ set pieces {k r n q p b} }
				default					{ set pieces {k q r b n p} }
			}

			foreach piece $pieces {
				AddMaterial [set $piece] $piece $canv $rank $sum; incr rank [abs [set $piece]]
			}
		} elseif {[string length $Vars(material)]} {
			$canv delete material
			set Vars(material) {}
		}
	} else {
		lassign [::scidb::pos::inHand?] matw matb
		::board::holding::update $Vars(holding:w) $matw
		::board::holding::update $Vars(holding:b) $matb
	}
}


proc DrawChecks {canv} {
	variable Vars

	lassign [::scidb::pos::checks] w b
	$canv itemconfigure checks -state hidden

	for {set i 1} {$i <= $w} {incr i} {
		$canv itemconfigure chb-$i -state normal
	}
	for {set i 1} {$i <= $b} {incr i} {
		$canv itemconfigure chw-$i -state normal
	}
}


proc AddMaterial {count piece canv rank sum} {
	variable ::board::layout
	variable Vars
	variable Dim

	if {$count == 0} { return }

	set dist	[expr {$Dim(piece)/8}]
	set gap	[expr {$Dim(piece)/4}]
	set offs	[expr {$Dim(piece) + $gap}]
	set size	[expr {$sum*$Dim(piece) + ($sum - 1)*$gap}]
	set x		[expr {$Dim(border:x2) + $Dim(gap:x) + ($Dim(stm) - $Dim(piece) - $dist)/2 + 1}]
	set y		[expr {$Dim(mid:y) - $size/2 + $rank*$offs}]
	set res	${Dim(piece)}x${Dim(piece)}

	if {$count < 0} {
		set color "b"
		set count [abs $count]
	} else {
		set color "w"
	}

	if {$Vars(variant) ne "Normal"} {
		if {$color eq "w"} { set color "b" } else { set color "w" }
	}

	set img photo_Piece(figurine,$layout(material-bar),${color}${piece},$Dim(piece:size))

	for {set i 0} {$i < $count} {incr i} {
		set n [expr {$i + $rank}]
		$canv create image $x $y -image $img -tags [list material mv$n] -anchor nw
		incr y $offs
	}
}


proc ComputeLayout {canvWidth canvHeight {bordersize -1}} {
	variable ::board::layout
	variable Dim
	variable Vars

	if {$bordersize > 0} {
		::update idletasks
	}

	set distance	[expr {max(1, min($canvWidth, $canvHeight)/150)}]
	set width		[expr {$canvWidth - 2*$distance}]
	set height		[expr {$canvHeight - 2*$distance}]
	set sqsize		squaresize:$Vars(layout)
	set stmsize		0

	if {$layout(side-to-move) || ($layout(material-values) && $Vars(layout) ne "Crazyhouse")} {
		if {$layout(side-to-move)} { set minsize 64 } else { set minsize 34 }
		set Dim(stm) [expr {max(18, min($minsize, (min($canvWidth, $canvHeight) - 19)/24 + 5))}]
		set Dim(gap:x) [expr {max(7, $Dim(stm)/3)}]
		set Dim(gap:y) $Dim(gap:x)
	} else {
		set Dim(stm) 0
		set Dim(gap:x) 0
		set Dim(gap:y) 0
	}

	if {$Vars(layout) ne "Crazyhouse"} {
		set stmsize [expr {$Dim(gap:x) + $Dim(stm)}]
	}

	if {$layout(border) && $layout(coordinates)} {
		set Dim(borderthickness) [expr {min(36, max(16, int(min($width, $height)/24.0 + 0.5)))}]
		set Dim(offset) $Dim(borderthickness)
	} elseif {$layout(border)} {
		set Dim(borderthickness) 12
		set Dim(offset) 12
	} elseif {$layout(coordinates)} {
		set Dim(borderthickness) 0
		set Dim(offset) [expr {min(36, max(16, int(min($width, $height)/20.0 + 0.5)))}]
	} else {
		set Dim(borderthickness) 0
		set Dim(offset) 0
	}

	if {$layout(border) && $layout(coordinates)} {
		set Dim(borderthickness) [expr {int([::font::scaleFactor]*$Dim(borderthickness) + 0.5)}]
		set Dim(offset) [expr {int([::font::scaleFactor]*$Dim(offset) + 0.5)}]
	}

	if {	$Vars(layout) eq "ThreeCheck"
		&& $layout(coordinates)
		&& !$layout(border)
		&& ($layout(side-to-move) || $layout(material-values))} {
		set Dim(offset:coords) $Dim(offset)
	} else {
		set Dim(offset:coords) 0
	}

	if {$Vars(layout) eq "Crazyhouse" && $layout(coordinates) && !$layout(border)} {
		set Dim(offset:coords) [expr {(2*$Dim(offset))/3}]
	}

	if {$layout(border)} {
		set width [expr {$width - 2*$Dim(borderthickness) - 2*$stmsize}]
	} else {
		set width [expr {$width - 2*max($Dim(offset), $stmsize)}]
	}

	set height [expr {$height - 2*$Dim(offset)}]

	if {$Vars(layout) eq "Crazyhouse" && ($layout(border) || !$layout(coordinates))} {
		set width [expr {$width - min($width, $height)/24}]
	}

	set boardsize				[expr {min($width, $height)}]
	set Dim(edgethickness)	[expr {$Dim(borderthickness) ? 0 : ($boardsize/8 < 45 ? 1 : 2)}]

	if {$Vars(layout) eq "Crazyhouse"} {
		set squaresize		[expr {($boardsize - 2*$Dim(edgethickness) - 4)/10.3333}]
		set Dim(distance)	[expr {round($squaresize/3.0)}]
		if {$layout(side-to-move)} { set Dim(gap:x) $Dim(distance) }

		set width			[expr {$width - 2*$Dim(distance) - 4}]
		set squaresize1	[expr {($width - 2*$Dim(edgethickness))/10}]
		set squaresize2	[expr {($height - 2*$Dim(edgethickness))/8}]
		set Dim($sqsize)	[expr {min($squaresize1, $squaresize2)}]
		set width			[expr {$width - 2*$Dim($sqsize)}]
	} else {
		set Dim($sqsize)	[expr {($boardsize - 2*$Dim(edgethickness))/8}]
	}

	set Dim(border:gap) [::board::computeGap $Dim($sqsize)]

	if {$Dim(border:gap) > 0} {
		if {[::board::borderlineGap] > 0 || $layout(border)} {
			set Dim(border:gap)		0
		} else {
			set height					[expr {$height - $Dim(border:gap)}]
			set width					[expr {$width - $Dim(border:gap)}]
			set boardsize				[expr {min($width, $height)}]
			set Dim($sqsize)			[expr {$boardsize/8}]
			set Dim(edgethickness)	0
		}
	}

	set Dim(boardsize)	[expr {8*$Dim($sqsize) + 2*$Dim(edgethickness)}]
	set Dim(bordersize)	[expr {$Dim(boardsize) + 2*$Dim(borderthickness)}]
	set Dim(border:x1)	[expr {($canvWidth - $Dim(bordersize) + $Dim(offset:coords))/2}]
	set Dim(border:y1)	[expr {($canvHeight - $Dim(bordersize))/2}]
	set Dim(border:x2)	[expr {$Dim(border:x1) + $Dim(bordersize)}]
	set Dim(border:y2)	[expr {$Dim(border:y1) + $Dim(bordersize)}]
	set Dim(mid:y)			[expr {$Dim(border:y1) + $Dim(bordersize)/2}]

	if {$bordersize != -1 && $Dim(bordersize) != $bordersize} {
		$Vars(widget:frame) delete stm
		$Vars(widget:frame) delete checks
		$Vars(widget:border) delete shadow
		$Vars(widget:border) delete mvbar
		$Vars(widget:border) delete holdingbar
	}

	if {$layout(material-bar)} {
		set Dim(piece) [expr {$Dim(stm) - 2}]
		set Dim(piece:size) [expr {$Dim(stm) - 3}]
	} else {
		set Dim(piece) $Dim(stm)
		set Dim(piece:size) $Dim(stm)
	}
}


proc ConfigureBoard {canv} {
	variable ::board::layout
	variable ::board::colors
	variable Dim
	variable Vars
	variable board

	set border $Vars(widget:border)
	set sqsize squaresize:$Vars(layout)

	# configure border #############################
	set state hidden
	if {$layout(border)} { set state normal }
	$border itemconfigure -state $state

	# configure side to move #######################
	if {$layout(side-to-move)} {
		if {[rotated?]} {
			set stmw stmb
			set stmb stmw
		} else {
			set stmw stmw
			set stmb stmb
		}
		set x [expr {$Dim(border:x2) + $Dim(gap:x)}]
		set y [expr {$Dim(border:y1) + $Dim(gap:y)}]
		$canv coords $stmb $x $y
		set y [expr {$Dim(border:y2) - $Dim(stm) - $Dim(gap:y)}]
		$canv coords $stmw $x $y
		$canv raise stm
	}
	$canv itemconfigure stmb -state hidden
	$canv itemconfigure stmw -state hidden
	UpdateSideToMove $canv

	# configure material bar #######################
	$canv delete material

	if {$Vars(layout) ne "Crazyhouse"} {
		set state hidden
		if {$layout(material-values) && $layout(material-bar)} {
			set size $Dim(piece)
			set dist [expr {$size/8}]
			set x3 [expr {$Dim(border:x2) + $Dim(gap:x) + ($Dim(stm) - $size - $dist)/2}]
			set x4 [expr {$x3 + $size + $dist}]

			if {$layout(side-to-move)} {
				set y3 [expr {$Dim(border:y1) + $Dim(stm) + 2*$Dim(gap:y) + 1}]
				set y4 [expr {$Dim(border:y2) - $Dim(stm) - 2*$Dim(gap:y) - 1}]
			} else {
				set y3 [expr {$Dim(border:y1) + $Dim(edgethickness)}]
				set y4 [expr {$Dim(border:y2) - $Dim(edgethickness)}]
			}

			$canv coords mvbar-1 $x3 $y3 $x4 $y4
			incr x3; incr y3
			$canv coords mvbar-2 $x3 $y3 $x4 $y4
			incr x4 -1; incr y4 -1
			$canv coords mvbar-3 $x3 $y3 $x4 $y4

			$canv raise mvbar
			set state normal
		}
		$canv itemconfigure mvbar-1 -state $state
		$canv itemconfigure mvbar-2 -state $state
		$canv itemconfigure mvbar-3 -state $state
	}

	# configure check counts #######################
	if {$Vars(layout) eq "ThreeCheck" && ($layout(side-to-move) || $layout(material-values))} {
		set size $Dim(piece)
		set dist [expr {max($Dim(gap:x), ($Dim(stm) + $Dim(gap:x) - $size)/2)}]
		set dist [expr {$Dim(stm) + $Dim(gap:x) + $Dim(offset:coords) - $size}]
		set x0 [expr {$Dim(border:x1) - $size - $dist}]
		set y1 [expr {$Dim(border:y1) + $Dim(gap:y) + $Dim(borderthickness)}]
		set y2 [expr {$y1 + $size + $Dim(gap:y)}]
		set y3 [expr {$y2 + $size + $Dim(gap:y)}]
		set z1 [expr {$Dim(border:y2) - $Dim(borderthickness) - $Dim(gap:y) - $size}]
		set z2 [expr {$z1 - $size - $Dim(gap:y)}]
		set z3 [expr {$z2 - $size - $Dim(gap:y)}]

		if {[rotated?]} {
			set t1 $y1; set y1 $z1; set z1 $t1
			set t2 $y2; set y2 $z2; set z2 $t2
			set t3 $y3; set y3 $z3; set z3 $t3
		}

		$canv coords chw-1 $x0 $y1; $canv coords chw-2 $x0 $y2; $canv coords chw-3 $x0 $y3
		$canv coords chb-1 $x0 $z1; $canv coords chb-2 $x0 $z2; $canv coords chb-3 $x0 $z3
	} else {
		$canv delete checks
	}

	# configure in-hand bars #######################
	if {$Vars(layout) eq "Crazyhouse"} {
		set wd [::board::holding::width $Vars(holding:w)]
		set ht [::board::holding::height $Vars(holding:w)]
		set distance $Dim(distance)
		if {$layout(side-to-move)} {
			set yincr [expr {2*$Dim(gap:y) + $Dim(stm) + $Dim(edgethickness)}]
		} else {
			set yincr $Dim(edgethickness)
		}
		set xw [expr {$Dim(border:x2) + $distance}]
		set yw [expr {$Dim(border:y2) - $ht - $yincr}]
		set xb [expr {$Dim(border:x1) - $distance - $Dim(offset:coords) - $wd}]
		set yb [expr {$Dim(border:y1) + $yincr}]
		if {[rotated?]} { lassign {b w} w b } else { lassign {w b} w b }
		$canv coords holdingbar-w [set x$w] [set y$w]
		$canv coords holdingbar-b [set x$b] [set y$b]
		$canv raise holdingbar-w
		$canv raise holdingbar-b
	}

	# configure coordinates ########################
	if {$layout(coordinates)} {
		if {$layout(border)} { set w $border } else { set w $canv }
		$w itemconfigure ncoords -state normal
		set size $Dim(offset)
		if {$layout(border)} { incr size -4 }
		set font [ComputeCoordFont $w $size]
	}
	$canv itemconfigure coords -state hidden
	$border itemconfigure coords -state hidden
	if {$layout(coordinates)} {
		if {$layout(border)} { set w $border } else { set w $canv }
		if {$layout(border)} { set which border } else { set which background }
		$w itemconfigure ncoords -state normal -fill $colors(hint,${which}-coords)
		$w itemconfigure coords -font $font
		if {$layout(coords-embossed)} {
			scan $colors(hint,${which}-coords) "\#%2x%2x%2x" r g b
			set luma	[expr {$r*0.2125 + $g*0.7154 + $b*0.0721}]
			if {$luma >= 128} { $w itemconfigure bcoords -state normal -fill black }
			if {$luma <  128} { $w itemconfigure wcoords -state normal -fill white }
		} else {
			$w itemconfigure bcoords -state normal -fill gray48
		}
		if {$layout(border)} {
			set x [expr {$Dim(offset)/2 + 1}]
			set y [expr {$Dim(offset) + $Dim($sqsize)/2}]
		} else {
			set x [expr {$Dim(border:x1) - $Dim(offset)/2 - $Dim(edgethickness)}]
			set y [expr {$Dim(border:y1) + $Dim(edgethickness) + $Dim($sqsize)/2}]
		}
		set columns {8 7 6 5 4 3 2 1}
		set rows {A B C D E F G H}
		if {[rotated?]} {
			set columns [lreverse $columns]
			set rows [lreverse $rows]
		}
		foreach r $columns {
			foreach {k offs} {w -1 b 1 {} 0} {
				$w coords ${k}coord${r} [expr {$x + $offs}] [expr {$y + $offs}]
			}
			incr y $Dim($sqsize)
		}
		if {$layout(border)} {
			set x [expr {$Dim(offset) + $Dim($sqsize)/2}]
			set y [expr {$Dim(bordersize) - $Dim(offset)/2 - 2}]
		} else {
			set x [expr {$Dim(border:x1) + $Dim(edgethickness) + $Dim($sqsize)/2}]
			set y [expr {$Dim(border:y2) + $Dim(edgethickness) + $Dim(offset)/2}]
		}
		foreach c $rows {
			foreach {k offs} {w -1 b 1 {} 0} {
				$w coords ${k}coord${c} [expr {$x + $offs}] [expr {$y + $offs}]
			}
			incr x $Dim($sqsize)
		}
	}
}


proc ComputeCoordFont {w size} {
	variable ::board::layout
	variable Defaults
	variable Dim

	set factor [::font::scaleFactor]
	set size [expr {max(6, int($factor*$size + 0.5))}]
	if {$Dim(fontsize) == $size} { return $Dim(font) }
	set delta [expr {min(6, int(($size - 10)/3.0 + 0.5) + 2)}]
	set Dim(fontsize) $size

	while {$size >= 6} {
		set Dim(font) [list $Defaults(coords-font-family) $size]
		$w itemconfigure coordA -font $Dim(font)
		lassign [$w bbox coordA] x1 y1 x2 y2
		set width [expr {$x2 - $x1}]
		set height [expr {$y2 - $y1}]
		set dx [expr {$Dim(offset) - $width - $delta}]
		set dy [expr {$Dim(offset) - $height - $delta}]
		if {$dx >= 0 && $dy >= 0} { return $Dim(font) }
		incr size [expr {min(-1, min($dx, $dy)/2)}]
	}

	return $Dim(font)
}


proc BuildBoard {canv} {
	variable ::board::layout
	variable ::board::colors
	variable ::board::square::style
	variable stmWhite
	variable stmBlack
	variable Dim
	variable Vars

	set border $Vars(widget:border)

	# border #######################################
	if {$layout(border)} {
		::board::setBackground $border border
		if {[llength $colors(hint,border-color)]} {
			$border configure -background $colors(hint,border-color)
		}
		if {[llength [$border find withtag shadow]] == 0} {
			::board::diagram::drawBorderlines $border $Dim(bordersize)
		}
	}

	# side to move #################################
	if {$layout(side-to-move) && [llength [$canv find withtag stm]] == 0} {
		catch { image delete [namespace current]::Stm(white) }
		catch { image delete [namespace current]::Stm(black) }
		image create photo [namespace current]::Stm(white) -width $Dim(stm) -height $Dim(stm)
		image create photo [namespace current]::Stm(black) -width $Dim(stm) -height $Dim(stm)
		::scidb::tk::image copy $stmWhite [namespace current]::Stm(white)
		::scidb::tk::image copy $stmBlack [namespace current]::Stm(black)
		$canv create image 0 0 -image [namespace current]::Stm(black) -tags {stm stmb} -anchor nw
		$canv create image 0 0 -image [namespace current]::Stm(white) -tags {stm stmw} -anchor nw
	}

	# material bar #################################
	if {$Vars(layout) eq "Crazyhouse" || !$layout(material-values) || !$layout(material-bar)} {
		$canv delete mvbar
	} elseif {[llength [$canv find withtag mvbar]] == 0} {
		$canv create rectangle 0 0 0 0 -fill white -width 0 -tags {mvbar mvbar-1}
		$canv create rectangle 0 0 0 0 -fill black -width 0 -tags {mvbar mvbar-2}
		$canv create rectangle 0 0 0 0  -fill #e6e6e6 -width 0 -tags {mvbar mvbar-3}
	}

	# check counts #################################
	if {$Vars(layout) eq "Crazyhouse" || !$layout(side-to-move) && !$layout(material-values)} {
		$canv delete checks
	} elseif {[llength [$canv find withtag checks]] == 0} {
		set wk photo_Piece(figurine,0,wk,$Dim(piece:size))
		set bk photo_Piece(figurine,0,bk,$Dim(piece:size))
		for {set i 1} {$i <= 3} {incr i} {
			$canv create image 0 0 -image $wk -tags [list checks chw-$i] -anchor nw -state hidden
			$canv create image 0 0 -image $bk -tags [list checks chb-$i] -anchor nw -state hidden
		}
	}

	# in-hand bars #################################
	if {$Vars(layout) ne "Crazyhouse"} {
		$canv delete holdingbar
	} elseif {[llength [$canv find withtag holdingbar]] == 0} {
		$canv create window 0 0 -anchor nw -tags {holdingbar holdingbar-w} -window $Vars(holding:w)
		$canv create window 0 0 -anchor nw -tags {holdingbar holdingbar-b} -window $Vars(holding:b)
	}

	# coordinates ##################################
	if {$layout(coordinates) && [llength [$border find withtag coords]] == 0} {
		foreach w [list $canv $border] {
			foreach r {1 2 3 4 5 6 7 8} {
				$w create text 0 0 -justify right -text $r -tags [list coords wcoords wcoord$r]
				$w create text 0 0 -justify right -text $r -tags [list coords bcoords bcoord$r]
				$w create text 0 0 -justify right -text $r -tags [list coords ncoords coord$r]
			}
			foreach c {A B C D E F G H} {
				set letter $c
				if {$layout(coords-small)} { set letter [string tolower $c] }
				$w create text 0 0 -text $letter -tags [list coords wcoords cc$c wcoord$c]
				$w create text 0 0 -text $letter -tags [list coords bcoords cc$c bcoord$c]
				$w create text 0 0 -text $letter -tags [list coords ncoords cc$c coord$c]
			}
		}
	}
}


proc Rotate {canv} {
	variable board
	variable Vars

	::board::diagram::rotate $board
	# the 3D views follow the 2D orientation when on a white/black preset
	if {[llength [info commands ::board3d::syncOrientation]]} {
		catch { ::board3d::syncOrientation [::board::diagram::rotated? $board] }
	}
	ConfigureBoard $canv
	DrawMaterialValues $Vars(widget:frame)
	DrawChecks $Vars(widget:frame)
}


proc SetStartBoard {canv} {
	::setup::board::open [winfo toplevel $canv]
}


proc SetStartPosition {canv} {
	::setup::position::open [winfo toplevel $canv]
}


proc UpdateSideToMove {canv} {
	variable ::board::layout
	variable Vars

	if {$layout(side-to-move)} {
		if {[::scidb::game::ply] % 2} { set color b } else { set color w }
		if {$color eq "w"} { set other b} else { set other w }
		$canv itemconfigure stm$color -state normal
		$canv itemconfigure stm$other -state hidden
	}
}


proc UpdateControls {} {
	variable Vars

	set level [::scidb::game::level]

	if {[::scidb::game::position -1 atStart?]} { set state disabled } else { set state normal }
	::toolbar::childconfigure $Vars(control:back) -state $state
	::toolbar::childconfigure $Vars(control:fastBack) -state $state
	if {$level} { set state normal }
	::toolbar::childconfigure $Vars(control:gotoStart) -state $state

	if {[::scidb::game::position -1 atEnd?]} { set state disabled } else { set state normal }
	::toolbar::childconfigure $Vars(control:fwd) -state $state
	::toolbar::childconfigure $Vars(control:fastFwd) -state $state
	if {$level} { set state normal }
	::toolbar::childconfigure $Vars(control:gotoEnd) -state $state

	if {$level == 0} { set state disabled } else { set state normal }
	::toolbar::childconfigure $Vars(control:leaveVar) -state $state

	if {[::scidb::game::variation count]} { set state normal } else { set state disabled }
	::toolbar::childconfigure $Vars(control:enterVar) -state $state
}


proc GameSwitched {oldPos newPos} {
	variable Vars

	after cancel $Vars(afterid:switched)
	set Vars(afterid:switched) [after 1 [namespace code [list GameSwitched2 $newPos]]]
}


proc GameSwitched2 {position} {
	variable Vars
	variable board

	# reset if position is 9 (all games closed)

	set variant [::scidb::game::query $position mainvariant?]
	set base [lindex [::scidb::game::link? $position] 0]
	set Vars(variant) $variant

	set view [::scidb::game::view $position id]
	if {$view >= 0} {
		Unsubscribe $position
		set Vars(current:game) [list $position $base $variant $view 0]
		SwitchView list
		Subscribe $position $base $variant
	}

#	UpdateCrossTableButton
	UpdateGameControls $position
	UpdateGameButtonState(list) $position
	UpdateGameButtonState(base) [::scidb::db::get name] [::scidb::app::variant]
	UpdateSaveButton

	set layout [expr {$variant eq "Crazyhouse" || $variant eq "ThreeCheck" ? $variant : "Normal"}]
	if {$layout ne $Vars(layout)} {
		::board::diagram::showPromoted $board [expr {$variant eq "Crazyhouse"}]
		set Vars(layout) $layout
		Apply
	}
}


proc GameClosed {position} {
	if {$position < 9} {
		Unsubscribe $position
	}
}


proc UpdateInfo {base variant} {
	if {$base eq [::scidb::db::get name]} {
		DatabaseSwitched $base $variant
	}
}


proc DatabaseSwitched {base variant} {
	UpdateGameButtonState(list) [::scidb::game::current]
	UpdateGameButtonState(base) $base $variant
	UpdateSaveButton
#	UpdateCrossTableButton
}


#proc UpdateCrossTableButton {} {
#	variable ::scidb::scratchbaseName
#	variable Vars
#
#	set base [lindex [::scidb::game::sink?] 0]
#	if {$base eq $scratchbaseName} { set state disabled } else { set state normal }
#	::toolbar::childconfigure $Vars(crossTable) -state $state
#}


proc UpdateSaveButton {} {
	variable ::scidb::scratchbaseName
	variable ::scidb::clipbaseName
	variable Vars

	set position [::scidb::game::current]

	if {$position == 9} {
		::toolbar::childconfigure $Vars(game:replace) -state disabled
		::toolbar::childconfigure $Vars(game:save) -state disabled
	} elseif {$position >= 0} {
		set actual [lindex [::scidb::game::link?] 0]
		set variant [::scidb::game::variant?]
		set current [::scidb::db::get name]
		set tip(replace) ""
		set tip(save) ""
		set state(replace) normal
		set state(save) normal
		if {$actual ne $scratchbaseName} {
			set tip(replace) [format $::gamebar::mc::ReplaceGame [::util::databaseName $actual]]
		}
		if {	$actual eq $scratchbaseName
			|| ![::scidb::db::get open? $actual]
			|| [::scidb::db::get readonly? $actual]
			|| $Vars(variant) ni [::scidb::db::get variants $actual]} {
			set state(replace) disabled
			set tip(replace) ""
		}
		if {	$Vars(variant) in [::scidb::db::get variants $current]
			&& ![::scidb::db::get readonly? $current $Vars(variant)]} {
			set tip(save) [format $::gamebar::mc::AddNewGame [::util::databaseName $current]]
		} else {
			set state(save) disabled
		}
		::toolbar::childconfigure $Vars(game:replace) \
			-state $state(replace) \
			-tooltip $tip(replace) \
			;
		set arrowState [::makeState [expr {$Vars(variant) eq $variant}]]
		::toolbar::childconfigure $Vars(game:save) \
			-state $state(save) \
			-arrowstate $arrowState \
			-tooltip $tip(save) \
			;
	}
}


proc UpdateGameControls {position} {
	variable Vars

	if {$Vars(load:method) eq "base" || $position >= 9} { return }

	Unsubscribe $position
	set Vars(current:game) {}
	set info [::game::getSourceInfo $position]

	if {[llength $info]} {
		lassign $info base variant view number
		if {$view >= 0} {
			set variant [::util::toMainVariant $variant]
			set Vars(current:game) [list $position $base $variant $view $number]
			Subscribe $position $base $variant
			SwitchView list
		} else {
			set Vars(current:game) {}
		}
	}
}


proc UpdateGameButtonState(list) {position} {
	variable Vars

	if {$Vars(load:method) eq "base"} { return }
	array set state { random disabled prev disabled next disabled first disabled last disabled }

	if {[llength $Vars(current:game)] > 1 && $position < 9} {
		lassign $Vars(current:game) position base variant view number
		if {[::scidb::db::get open? $base $variant]} {
			if {[::scidb::view::open? games $base $variant $view]} {
				if {[scidb::view::count games $base $variant $view] > 1} {
					if {[::scidb::game::view $position next] >= 0} {
						array set state { next normal last normal }
						set state(random) normal
					}
					if {[::scidb::game::view $position prev] >= 0} {
						array set state { prev normal first normal }
						set state(random) normal
					}
				}
			}
		}
	}

	foreach action [array names state] {
		::toolbar::childconfigure $Vars(game:$action) -state $state($action)
	}
}


proc UpdateGameButtonState(base) {base variant} {
	variable Vars

	if {$Vars(load:method) eq "list"} { return }

	set position [::scidb::game::current]
	set numGames [scidb::view::count games $base $variant 0]
	array set state { random disabled prev disabled next disabled first disabled last disabled }

	if {$numGames > 0} {
		set state(random) normal
		if {$position < 9} {
			lassign [::scidb::game::link? $position] myBase myVariant index
			set myVariant [::util::toMainVariant $myVariant]
			if {$myBase eq $base && $myVariant eq $variant} {
				if {$index > 0} { array set state { prev normal first normal } }
				if {$index + 1 < $numGames} { array set state { next normal last normal } }
			}
		} else {
			array set state { prev normal next normal first normal last normal }
		}
	}

	foreach action {next prev first last random} {
		::toolbar::childconfigure $Vars(game:$action) -state $state($action)
	}
}


proc UpdateGameList {position id base variant {view -1} {index -1}} {
	variable Vars

	if {[llength $Vars(current:game)] <= 1} {
		UpdateGameButtonState(list) $position
	} else {
		lassign $Vars(current:game) currPos currBase currVariant currView currNumber

		if {$currBase eq $base && $variant eq $currVariant && ($currView == $view || $currView == 0)} {
			UpdateGameButtonState(list) $position
		}
	}
}


proc UpdateGameInfo {position id} {
	variable Vars

	if {$position == $id && [llength $Vars(current:game)]} {
		if {[lindex $Vars(current:game) 0] == $position} {
			Unsubscribe $position
			set Vars(current:game) {}
			#SwitchView base ;# not required
		}
	}
}


proc Subscribe {position base variant} {
	variable Vars

	set cmd [list [namespace current]::UpdateGameList $position]
	after idle [list ::scidb::db::subscribe gameList $cmd]
	set Vars(subscribe:list) $cmd

	set cmd [list [namespace current]::UpdateGameInfo $position]
	after idle [list ::scidb::db::subscribe gameInfo $cmd]
	set Vars(subscribe:info) $cmd
}


proc Unsubscribe {position} {
	variable Vars

	if {[llength $Vars(subscribe:list)]} {
		after idle [list ::scidb::db::unsubscribe gameList $Vars(subscribe:list)]
		after idle [list ::scidb::db::unsubscribe gameInfo $Vars(subscribe:info)]
		set Vars(subscribe:list) {}
		set Vars(subscribe:info) {}
	}
}


#proc ShowCrossTable {parent} {
#	set base [::scidb::game::query database]
#	set variant [::scidb::app::variant]
#	set index [::scidb::game::index]
#	::crosstable::open .application $base $variant $index -1 game
#}


proc SaveGame {{mode ""}} {
	variable ::scidb::scratchbaseName
	variable ::scidb::clipbaseName
	variable Vars

	::tooltip::hide
	set position [::scidb::game::current]

	if {0 <= $position && $position < 9} {
		if {[string length $mode] == 0} {
			if {[lindex [::scidb::game::link? $position] 0] eq $scratchbaseName} {
				set mode add
			} else {
				set mode replace
			}
		}
		[namespace parent]::pgn::saveGame $mode
	}
}


proc LanguageChanged {} {
	bindKeys
	SetupToolbar
	UpdateSaveButton
}


proc WriteOptions {chan} {
	::options::writeItem $chan [namespace current]::Options
}
::options::hookWriter [namespace current]::WriteOptions


# 80x80
set stmWhite [image create photo -data {
	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
}]

set stmBlack [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAAFAAAABQCAYAAACOEfKtAAAAR3RFWHRMaWNlbnNlAE9yaWdpbmFs
	IENoZXNzd2l6IGFydHdvcmssIDIwMjYuIEdQTC0yLjAtb3ItbGF0ZXI7IHNlZSBDT1BZSU5HLoC6
	vgkAABTySURBVHic7V17cF1Hef99u+ec+35IsklkyUG2kliGYaiDoTgPLNl0pqQk0BK5TnAAd0La
	hD+gD0gHGGxTwsS0GSBtHk3S4ibkZVECJCnTTuwr54EppAkdhkhO/MSSlcTWvVf3de557G7/OOdc
	3Xsl+aFYfqj8Zu7Y3rPnnN3f+Xb3+7799jPwO5zfUErRJqWYUopnMhlNKaVlMkpTSvH6n1+m+XW4
	8u6hs93+swKlFMsoj6TT8CyuvGex09G2U4V2pl6klGKDg2B9feQSkQQg/XJ9LGcusi2rm4Evkcrt
	JEZtpJBUgAEABNiKUCDQMSg1KgkHCXTg6AWpw0Tk1L8nk1Faby+k/445x5wPge3bFe/vh6rv0JFj
	1XcxUldJJXuFEJcBanE4HI7ohgHOAKUAqQCoyVYyAogAIQDHcVCtmhZAhzjnL4PheUg+uGhB+NXg
	HUopNjAAWreOxFz2b84I3L59O//Nb/rVli0ecW/mzW4p1HVCuH+ilFqZTCaZUoBlWXAcG0IICY8y
	BQBEjU1TKmATBIA450zXDYRCIRADioWiIEYvM8afZIwGLkhH9vr30cDAAFu3bt2cEHnaCdy0aRN7
	9+bNtI68Lz921OyTyr0VhD9KJOIR23ZQqVSgpBTwSCIARM2MnQDKY1QBUAQoEGmRaBQhQ0exUKyC
	6BkG3N2+MJHx67PNmzdjy5Ytp3Von1YClVKcfOIOj+V6Nd24jWv8D3XDQKlYhJTSBcB8smZ8d520
	NTb2+Bwrn1TJGNPiiQQc24YQ4r9cW96xuL1GZK2NpwOnhUBfnSAikgfGcl1hw/g7RmyDHjJQmJgI
	5j82nZQppSDlpFAwxmq/ekgpa7/6utORGhCplGLJZIocx4ZU8lHLsr/a1d5ywF+xFRFN/6VOAW+b
	wPoveuRo4c+J8W9Go9HWiXxeKq+RU1QVKSWUUmCMwTC8eYxzBiEkLMuCaZqwbQdCeILCOYdh6IhE
	IlPq2rYNKSWIaArpfvsEAZRKp1mlUskJKb7cuTB5X3PbZ4u3pcZkMkojInd4dHRBIpy6LxaNfaJc
	LiOfz7tEpDV/HSEEiAiRSBjhcBjVqoXDh0cwPLwHQ8N7sH/fAYyNvYH8xATK5TIcxwUA6LqOWCyK
	dCqF9vYLsbR7CZb3LENPzzJ0dnYgEvGeZZomlFLgfPKbBR8wl8sJ3dBbEvHEvWPjlbUT1dwtRHQs
	k1FaXx+5s+Vg1hKYUUrrI3L3Hjq6Mp6IPRqNRi7J5fIuAN48VIUQYIwhEY9DQWFoaA927hzEc8+9
	iFeHhjE+Pg7HccEYA+cMnPOG4RkMcyEEhPCGsa7raG1twfLly9Db+yGs6VuNnp5lYIxQLJYgpWwg
	0n+OAiDSLWmtUjFfLxfLN1z8zoUvBX2ZDQ+zIlApT/L2jxy9NhqLP8IZj1fKJZcYa5DoYL5KJhOw
	LRuZXc/j8ccH8OKLu5HN5qDrGsLhMDRNayCr/s9aQ/3r9fVc10W1WoXjuGhtTePyy1dh/frr0Ne7
	GoZhoFgsAsCUoa2kdKOxuCakKFUqpQ1LOxb+OOjTqXJxygQGLzp4JLshEgk/JIQkx3FE81wnhEAk
	EoGua3j22Qzuve8B7N7935BSIhaLQdM0KKVqv9mAiGo/13VRLpfBGMMHP/gB3HrLzfjwh/vgOC5M
	05xOGoWu65xzrsql0qeXLl748GxIPFXdq0ZeLBZ/2LKrUrgCRMTq6kBKiZaWNPbu3Y87tv4Dnn76
	p1BKIR6Pg4ggpcAsOTsuOOdQSqFUKoMI+OhHP4LbvvTXuOSSbuRyE2CMGlZtpZTknCMUDrNyqXRj
	16LW758qiSdtgGcyGW/YHjp6bSQSeciyqtJ1XKonT0oJxhjS6RQefXQ7rv1YP5780VOIxWJIJOK1
	eWwuyAM8qZdSIh6PIRaL4cknn8LHPt6PRx7djlQqCcZYgxpERMx1XbKqVRmJRB7aN3L0GiJyM5nM
	SS+uJyWBSilGRPLg6FuXRaLx54Qroo7rqnryhBAIh0MQQmLzltuxbdvDiEajCBkGXDGn5uiM0DQO
	y7JRrlSw8dM3Ysvmr4BxhmrVahjSSimpaxpxziuVinXVks6WV4I+n+gdJyQwUJIPT0ykucN/aRjG
	0kql0jDnCSEQjUaQnyjgc7d+ATt2ZtDW1lbT984mAv1wfHwca9b04p57vot0KolKxWwmUUSjUW7b
	9n5hivcvXpzK4ySU7RMO4cHBQU5EUlbkv8QT8aWVctmdSl4Ux45lsWHDRmQGd2HBggX+UD275AHe
	nCyEwIIFCzA4+Dw2bNiIY8eyiEYjNUUd8PTFSqXsJhLxpUqTDxKRHBwcPKG/8kTGJScicXA099mW
	tvT9+ZynIAfXpZQIhQwUiyV8csOf4Vev/C/SLWm47qz10jmFpmnI5fJYseK9+P7D/4pkMg7LshvU
	HKWU29KS1rL5/Ge7Lmx58ETWyvEMegZAjWaznSSNXxNRwieG+dc9m5UIn954MzKZXWhra4PjODM9
	8pyArmsYH8+ht/dDeGjb/ZC+1lC3OktfxSoqy35PR0frCHw7f7rnHW8IExEpp0p/H0/EU7Ztq/r6
	gT63acvt2LFjEG1trec8eQDgOC7a2lqwY0cGmzbfjng81rAyA2C2bat4Ip5yGW3158AZBW3aC4HY
	jr5ZuEIL6S/YVUsooDYfuK5Aa2sajzz6BD7/+b9BOp1umE/OB3DOkc/ncdd378QNN6xDNpuHptXb
	0BCGEWKmbV/ZdUHqZzMN5ZkkUAGALdyv67oOWbcYSCkRjYbx+uv7cPvtWxGNRpu/4HkBrx9R3H77
	Vuzdux/RaLihH1Iq6IZBSoiv+0XTrohTCPSZlofeyl4Vi0bXFAsl2Wym6bqOrd+6E2++dRSGYZwT
	q+2pQimFUMjAG2++hTu23gldNxoYIiJeLBRkLBpde+jNwpVEJKfbRZxOAr3nCHzBMAwQofZZhBBI
	JBJ49tkMnn76p0inUufd0K2H6wqk0yk8/fR/4NkdGaQSiWbVRhqGAUj3L/2iKZLSQGDN4hjLLeFc
	u7pYLCnUsc4Yg2PbuPfeB6CUwqntYpybIPKk8d5774flTFFpeLFYUpxrV4+NmV2+FDZw1iyBDAA4
	aH0ylQhL6XtAEUhfHJnB57D7579APB6Ht5F2fkMIiXg8jt27f4HBweeRSEz2i4hISiGSyUTYhrXe
	v+W4BIpNmxRTwCdsy0G9Y9Tzoig8/sRAs9503sPrm8Tjjw1AysaRRURk2w4U1Cd8s7ZhzqpVDYbv
	gSOF5bqGX0sped01hMNhvP76Xnz8j/8UruvOKwIBr4+apuFHP3oCl1x8MarVal0fCZyRazt4z5KO
	5HC9o6FeAr3hy+WaRCLBlVI1e0xKiXA4hJ07B5HN5qBpZywi5IzBM/NyyOzchXA41KDSKCXdeCKh
	cZJr/KIab/UE+r50rPYWiEkJY4zBNKsY3PUCdF07L9WWEyGQwF27nke1aqHOUwcigoKChFodVA+u
	BXYtEZF46SWlK6VWWJYd2MJQSsEwDIyMjGJ4aBjhcHjeEhgOh/Hq0B4cHhlBKDSp3yqlmGXZIMKK
	l156SSciEYTWBTQTAHR05zuIaLHj2LUyz+MSwvDwHoxns7W9jPmGQALHx8exZ/g1hEINw5gc2wYR
	XdTW0d0RlAFNBFoWuiORaEgIIetXYM45hob2wHHm3+JRDyKC47gYGtrTvLdMQggZiURCGrA0KAZ8
	AgcH/X8odOmGhmbXjRAC+/cfmHbnf76BMcK+/funWFhEJHVDhwK6gDrOAKC316+lVCdn1DBEGWOw
	LAtH3nijtus1XxFENYyNvQHLspqtEnAvSLETmOTMl8BBAAAx3lbPT+A0NU0TE/k8OGeYwSkxb+C5
	uSZgmlUwxtDIB6CgFgCTnPkS2Ku8CjIpFaaoMLbtoFyugDE+Z1uS5wI8geEoVyqwa3ax12EiglQA
	gRLAJGeNzgTAmE7AhBD+AjLXXTj7IAKcusiwBihAKRWqLzqFVWEei97bQLME2tM5+TnnMHR9Xg/f
	AEop6LoOjU+zo0kAEVn1RcEi4gUrEwqM6iOjPC+FYeiIxmKYDGuenwi8MrFYFIZh+Ir0ZDQY8/5a
	ACY5CxYR7wGgY42uHM8SiUQiSKVSvp9sHjMIb75Pp1OIhMO+227yGhEAKceBSc4CRdqDUqNCNDoS
	AlOuvf3CWoTpfAURQQiB9vZ2GI2mnHfNU1FGgEnOAkVaAYAkHHQcB81ua845uruXnJe7b6cKKRW6
	ly6ZLp6QObYDCRwEJjkLiFIAEFLYZ5qmxTlnqs7kEEJgeU/PvHVlBQgWkOXLexrUGKWU4pwz06xY
	Rii0LygGmggcvTA9KqU8rOvGZAXflOvpuRRtba3z0hsNoBbl2tbWimU9lzabcko3DCiF3x7Z/+qR
	oAzwCSQipZTiK4kcIvZKKGTUHApEBMuysXhxB5Yv72lydc8fEBHMahXvWt6DxZ2L4Pn/anHZ0uOE
	vbxy5UrH3zufYokE5652ETU6FJSSCIfDWL36KjjzWAKF62L16it9p3HdfK8UCARFaldQPbhUT6AE
	AK6xHcViUdSHsTHmRXWu6VuN1paWczZ87e3AdV20tLZgzZpeVKvVRtcdMa1YLLrSdTJ+SY3dWi1/
	05ju/6fEa0K4v4pGo4C/hUdEME0TPT3LcMUVq1AuV6asUuczOOcol8u44vJV6Fl2KUyzfppSIhqN
	wBXur7oWLdjjb39MJTB41pYtJBnTfmCEdNSvxJ6ngrB+fb/v5pk/q3HgB7x+fT+IUbMLSxmGDgL7
	d3/ea5CcZgIlAAgpnpjIFyzGJj2onHMUiyX0rr4Kq1Z9AKVSaV5IIecMpVIJq1b9Pnp7r0KxWPL9
	np76whjnhUKxKqEe929pDCas/0cQ+9HV3nJAuuKZRCJOqIuJ8+xiA7fecjOaF5rzFUoBRAy3/MVn
	oetGk/UBkUjESQj3mSXtLQeni9yfzp1FAKBp2rdt24ZSk3U45ygUCli7thfXfPRq5PMTDUGJ5xs0
	zfM+X3vN1Vi7tg+FQqEpcp+YbdvQmPZtv2iK+jFThCojInnoSPbZRCq1tlgo1I41BFEKIyNHcO3H
	+lEqlc7LrU4iguO6SCbi+MmPB7CoYxGs6qTyrJQSyWSSFyYmnn3notY/mOncyEwOVfIfssmxbbAm
	F3+lUsXFFy/FV79yGyqVynm5W8cYg1mp4Ktf+Vt0dy+FWWlUXbytDFtxxr8GAAMzCNu0Pfd33nlX
	R9uLpmk+lkynuJSyNhdqGkcul8f66/ux8TM3YvzYOHT9/ImX0XUdx8bHsXHjp7B+/XXI5Rrjo6WU
	IplKctOsPtZ5YWq3Uoqvm+GowwmPOewdzXZGQ8aviVHCdaY55sAIn/nMzdh5nh1z6Ov7EP5t2wO1
	NAINxxx0HUqqgiR6T2dbdBSzOebg38Au6Ww77Nj2F+OxGFN19k3gO2OM4e67v4P3vW/FOR+5pWka
	stk8Lrvs93DP3d8BYzTFx6mUkvFYlDnC+uLiBbEReLkeZvTjHXfyIiKRyWS0ro62B7K53JMtLWlN
	eZk3vJt9Ey+VSmLb9+7HZSvei6wfP3OuwSMvixUr3ott37sfqVQS1Wrz5rl0W1rSWi6X+2HXhW0P
	+idUjxsEftKHDScmkCq7pV8autE902HDiYkCbv3cF7Bjx7l52HDt2j7cc/d3kDruYUNnX0x3359K
	pSZwOg4bBg9IpylnV81+IWVJ1/SG4cw5R6ViIpGIY9u2B3DTTRuRz+fhuu5Z1RM1jcN1XeTzedx0
	00Zs+94DSCTi05EndV1nQspS2ar0p9PpHDDZ9+PhpPQPIpKZTEZb0vmOV8rl0g2arinOOaSUtRdw
	7p3NVVLiW1u/gX+8604kEnFks/laMokzBe7nnclm84jH47jrrjvxra3fgFISlmU3kCelVJxz36FQ
	vP7Szne84g/dk9q/mNWR/32Hj25IplIP29WqdMXMR/737TuAO7beiaeeembOj/wTgMB0L5VKIGK4
	5pqP4LYv/RUuvrgbuVx+SqKe+iP/hdLEjd2LFp7ykf/ZJ50YzX4yHAk/LOXxkk6EoesGduzI4N77
	HsTu3T+HEGKOk05wrFrlJZ1Y++E+OLYN06zOmHSCca6qpvmp2eRLAN5m2pNDY9lrQuHwo5xpx097
	kkjAdhzs2vU8Hnt8AC++8DOMZ3PQdA3hUBi6fjrSnrTg8ss/iOuv70df74eg6yeR9kSIkmWbn3zn
	ha0/OWNpTwJkaol3jqyMJ9KPRKORS0+UeCcej0MphT17XsOOnYN47rkXMDQ0jGPHgsQ7hGA+mjnx
	jvAOAuo62tpasbxnGXp7r8Kavl4s67n0pBLvtHiJd14reYl3/idzphPvBAjSJg0Pjy5ILWy5JxqN
	9Hspm5yGk+0BhPB2+iORMMKhMKqWhZGRUQwN78HQ0DD27z+IsbEx5PMTKJcrNavGMHREo1Gk0ym0
	t7eje2kXli/vQU/PMnR0LPJTP1VhmtUpqZ8CSCmFYeg8FoujUikPjB4duXVlT8/ZS/0UoP4c7eGj
	hZs1xr8ZjUXbctmcIqIpJz0Bb/NaKTlt8jHbtmCaVViWDeGb3xrnMAwDkUgYhhHUFbAsuy75mGdW
	TtM+QUSUSqVYpVLJulJ8efHC5D83t322mIP0d2NdYSP9dSJ1YygUwsSs09/VpxhUkFLNLv1dKkW2
	bUNJfN8q5r/W1dV+QJ1L6e/qUf9Ff3sku1o3Qrcxzj8SCoVQLBYhpTijCRhty4YU4j9dx75jcXvL
	YHMbTwdOq9EaHEAZGBhgFy1q3QVg19jRYm/FdW9hjK5JpdJeClDTBJR0lUJAJDUfbDwRfLIaUoDG
	YjHSDZ2ViiWzUi4HKUAH/fps8+bNOJ3kAXOQBtkfFmL79u28v79fEdEggMFDb+a7y2XzOinFxwl4
	fzKV1k5DElqqJaGdKAirar3suO4PhRQ/uOiC9F4A2LRJsXe/e4BON3H1jZlTTJcG+eCRwrvCIf1K
	oUQfpFohlbwoFA5HDN0A595Gz8mkQWbEDhJjL4PheUPjgwuS4aHgHUopNjAwQHOVvTfAGYvRUHWJ
	uJvKtbGc2SEsa6nibAmk6gTQBiAZBHQTkQVCAQrjUGqEoB2UJA5edEHqt83K75lOxH1WoOZRKviz
	DvW7/4zg/zf+D8BlPh2NqFt1AAAAAElFTkSuQmCC
}]

foreach size {16 22 32} {
	set ::icon::${size}x${size}::whiteKnob [image create photo -width $size -height $size]
	set ::icon::${size}x${size}::blackKnob [image create photo -width $size -height $size]
	::scidb::tk::image copy $stmWhite [set ::icon::${size}x${size}::whiteKnob]
	::scidb::tk::image copy $stmBlack [set ::icon::${size}x${size}::blackKnob]
}
unset size

} ;# namespace board
} ;# namespace application

# vi:set ts=3 sw=3:
