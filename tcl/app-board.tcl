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
# Modified for Chesswiz, 2026; see docs/UPSTREAM.md
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
	# The square images are already built when a hidden board is reopened;
	# refreshing them must not abort the pane build if the theme marks the
	# border as texture-only (zero width/opacity). A reopened pane sits in a
	# metaframe, so the layout's header height is not reachable through the
	# parent; use the same 74 pixel default the layout API falls back to.
	Preload $width [expr {$height - 74}]
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
	after idle ::mediainset::InitMedia
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
	::bind $canv <Destroy> [namespace code [list CanvasDestroyed $w]]
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

	# The list is per build: a rebuilt pane must not bind the widgets of the
	# pane it replaced (they no longer exist).
	set Vars(need-binding) {}
	needBinding $Vars(widget:border)
	needBinding $Vars(widget:frame)
	needBinding $Vars(holding:w)
	needBinding $Vars(holding:b)
	needBinding [::board::diagram::canvas $board]

	# The notation pane shares this list. A rebuilt pane can leave the widgets
	# of the pane it replaced behind; they are gone, so skip them.
	foreach w $Vars(need-binding) {
		if {![winfo exists $w]} { continue }
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
		after cancel $Vars(after)
		set Vars(3d) 1
		::bind $Vars(3dwin) <Configure> [namespace code {ConfigureReserve3D %w %h}]
		::bind $Vars(3dwin) <Map> [namespace code {ConfigureReserve3D [winfo width %W] [winfo height %W]}]
		# The 3D view inherits the board's slot and then gets reserve padding
		# of its own; keep the 2D padding so it can be restored exactly (the
		# dynamic layout reserves a top toolbar strip).
		if {[winfo manager $Vars(widget:frame)] eq "pack"} {
			set Vars(pack:2d) [pack info $Vars(widget:frame)]
		} else {
			unset -nocomplain Vars(pack:2d)
		}
		ReplaceBoardView $Vars(widget:frame) $Vars(3dwin)
		ApplyReserve3D
		::board3d::refresh
		# Configure/Map supplies the realised frame, including its camera bar.
		# Rebuilding here uses the old canvas height and can overwrite the
		# correct reserve during a nested geometry update on the first toggle.
	} else {
		after cancel $Vars(after)
		if {$Vars(3dwin) ne "" && [winfo exists $Vars(3dwin)]} {
			ReplaceBoardView $Vars(3dwin) $Vars(widget:frame)
			# ReplaceBoardView copies the 3D view's options, including any
			# reserve padding; put the 2D slot's own options back.
			if {[info exists Vars(pack:2d)]} {
				catch { pack configure $Vars(widget:frame) {*}$Vars(pack:2d) }
				unset -nocomplain Vars(pack:2d)
			} else {
				pack configure $Vars(widget:frame) -padx 0 -pady 0
			}
		}
		set Vars(3d) 0
		# Let packing restore the canvas before notifying inset owners. Use
		# the restored slot size: the 3D view's reserve-adjusted height is
		# not the 2D canvas height (no Configure follows when the unmapped
		# canvas kept its size).
		set Vars(after) [after 0 [namespace code {
			set f $Vars(widget:frame)
			set Vars(width) [winfo width $f]
			set Vars(height) [winfo height $f]
			RebuildBoard $f $Vars(width) $Vars(height) true
		}]]
	}
	return 1
}


proc closed {w} {
	# should only happen after shutdown
}


# The board canvas is going away. A Configure queued a delayed RebuildBoard
# for it (50-300 ms, to coalesce a resize burst), and that timer holds the
# canvas path: firing it after View > Panes > Board off raised "invalid
# command name ...board.c" as a background error. Cancel the queued rebuild
# with the canvas it was queued for, so a closed pane leaves no timer behind
# (and none can land on a reopened pane that happens to reuse the path).
proc CanvasDestroyed {w} {
	variable Vars

	if {[info exists Vars(widget:frame)] && ![winfo exists $Vars(widget:frame)]} {
		if {[info exists Vars(after)] && $Vars(after) ne ""} {
			after cancel $Vars(after)
			set Vars(after) ""
		}
	}
	activate $w 0
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

	# endgame tablebase verdict under the board (seven pieces or fewer)
	if {[llength [info commands ::tablebase::positionChanged]]} {
		::tablebase::positionChanged $Vars(widget:frame)
	}

	# online opening explorer for the board position (its own dockable pane)
	if {[llength [info commands ::application::explorer::positionChanged]]} {
		::application::explorer::positionChanged
	}

	# the opening book editor follows the board position
	if {[llength [info commands ::book::positionChanged]]} {
		::book::positionChanged
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
		if {![winfo exists $w]} { continue }
		::bind $w $key [namespace code [list FilterKey %K %s $cmd]]
		::bind $w $key {+ break }
		if {[regexp {^<Key-[^>]+>$} $key]} {
			# A plain key binding also matches the key with Control; let Ctrl+Q
			# and the other application shortcuts through to .application.
			::bind $w $key "if {%s & 4} continue\n[::bind $w $key]"
		}
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
	::application::AddShortcutTag $w
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


# The board lost the focus: drop the selection and the variation list. This
# runs from a <FocusOut> binding on .application and the board canvas, and a
# queued FocusOut still runs after View > Panes > Board off destroyed the
# canvas. `::variation::hide` then asked the diagram to clear its alternatives
# with the dead path ("can't access ...::Board: parent namespace doesn't
# exist"). Nothing is focused on a board that is gone, so there is nothing to
# drop either.
proc LostFocus {} {
	variable Vars

	if {![info exists Vars(widget:frame)] || ![winfo exists $Vars(widget:frame)]} { return }

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
	variable RebuildCallbacks

	if {$Vars(3d) || $width <= 1 || $height <= 1} { return }

	set Vars(width) $width
	set Vars(height) $height

	if {[::twm::frozen?]} {
		if {$Vars(initialized)} { SetBackground $Vars(widget:frame) window $width $height }
		set Vars(deferred) 1
		return
	}

	if {$Vars(initialized)} {
		set parent [winfo parent $w]
		catch { [winfo parent $parent] set $parent Extent [expr {[winfo height $parent] - $height}] }
		after cancel $Vars(after)
		if {$Vars(initialized) == 1} {
			set timeout 300
			set Vars(initialized) 2
		} else {
			set timeout 50
		}
		set rebuild [namespace code [list RebuildBoard $w $width $height]]
		if {[llength $RebuildCallbacks]} {
			# Coalesce the WM's decoration/client Configure burst before
			# painting: rendering every intermediate large board can consume
			# the entire dialog settle budget. A timer (rather than idle)
			# stays outside a rebuild's nested update idletasks.
			set Vars(after) [after 20 $rebuild]
		} else {
			set Vars(after) [after $timeout $rebuild]
		}
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

	# C1: the one board/position context menu (PROPOSAL section 3).
	set fen ""
	catch { set fen [::scidb::game::query fen] }
	set square ""
	catch {
		set sq [::board::getSquare $w [winfo pointerx $w] [winfo pointery $w]]
		if {$sq >= 0} { set square [lindex $::board::squareIndex $sq] }
	}
	if {[llength [info commands ::context::Post]]
	 && [::context::Post C1 $m [dict create widget $w square $square fen $fen]]} {
		return
	}

	if {[llength [info commands ::application::assistant::offers::AskAboutBoard]]} {
		$m add command \
			-compound left \
			-image $::icon::16x16::none \
			-label " $::application::assistant::offers::mc::AskAbout" \
			-command ::application::assistant::offers::AskAboutBoard \
			;
		$m add separator
	}

	if {[llength [info commands ::gamereview::run]]} {
		$m add command \
			-compound left \
			-image $::icon::16x16::none \
			-label " $::gamereview::mc::Title..." \
			-command [list ::gamereview::run .application] \
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

	if {![::application::pgn::empty?] && [llength [info commands ::guessmove::start]]} {
		$m add separator
		$m add command \
			-compound left \
			-image $::icon::16x16::none \
			-label " $::guessmove::mc::GuessTheMove" \
			-command [list ::guessmove::start] \
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
	if {[llength [info commands ::mediainset::toggle]]} {
		$m add checkbutton \
			-label $::mediainset::mc::ShowInBoard \
			-variable ::mediainset::Options(enabled) \
			-command ::mediainset::toggle \
			;
		::theme::configureCheckEntry $m
	}
	if {[llength [info commands ::tablebase::toggle]]} {
		$m add checkbutton \
			-label $::tablebase::mc::ShowTablebase \
			-variable ::tablebase::Options(enabled) \
			-command ::tablebase::toggle \
			;
		::theme::configureCheckEntry $m
		$m add checkbutton \
			-label $::tablebase::mc::OnlineLookup \
			-variable ::tablebase::Options(online) \
			-command ::tablebase::toggle \
			;
		::theme::configureCheckEntry $m
		$m add command \
			-label " $::tablebase::mc::LocalFolder" \
			-command [list ::tablebase::chooseFolder .application] \
			;
	}
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


# A layout load freezes the twm, so a resize landing then skips its rebuild
# (and the afterRebuild owners). The loader calls this once it is done.
proc rebuildDeferred {} {
	variable Vars
	if {[info exists Vars(deferred)] && $Vars(deferred)} {
		set Vars(deferred) 0
		Apply
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


# Reserve dimensions are pixels in the full board-pane coordinate system.
# Below 32 pixels per square, media must use its corner-overlay fallback.
variable MinimumReserveSquare 32
variable ReserveSide {}
variable ReservePixels 0
# Who asked for the strip. "auto" is the ordinary video strip: it may only
# be reserved when it costs the drawn board no square (VAL-MED-012).
# "squeeze" is the video yielding a strip so a dialog keeps its usable size,
# and "dialog" is a dialog reserving board room itself (VAL-DLG-012); both
# are explicit requests to shrink the board and align it for that dialog.
variable ReserveKind auto
variable ReserveMaxBoard 0
variable RebuildCallbacks {}
variable NotifyingRebuild 0

proc reserveRect {} {
	variable Dim
	if {![info exists Dim(reserve:x)]} { return {0 0 0 0} }
	return [list $Dim(reserve:x) $Dim(reserve:y) $Dim(reserve:w) $Dim(reserve:h)]
}

# Register command prefixes; callbacks take no additional arguments and can
# query reserveRect. Registration is idempotent. Pass true to unregister.
proc afterRebuild {callback {remove false}} {
	variable RebuildCallbacks
	set i [lsearch -exact $RebuildCallbacks $callback]
	if {$remove} {
		if {$i >= 0} { set RebuildCallbacks [lreplace $RebuildCallbacks $i $i] }
	} elseif {$i < 0} {
		lappend RebuildCallbacks $callback
	}
}

# Probe using the same decoration/DPI arithmetic as the actual rebuild.
# No widgets or accepted reserve are changed while the inset compares strips.
proc reserveSquare {side px width height {kind auto} {maxBoard 0}} {
	variable Dim
	variable Vars
	variable ReserveSide
	variable ReservePixels
	variable ReserveKind
	variable ReserveMaxBoard
	set saved [array get Dim]
	set oldSide $ReserveSide
	set oldPixels $ReservePixels
	set oldKind $ReserveKind
	set oldMaxBoard [expr {[info exists ReserveMaxBoard] ? $ReserveMaxBoard : 0}]
	try {
		set ReserveSide $side
		set ReservePixels $px
		set ReserveKind $kind
		set ReserveMaxBoard $maxBoard
		ComputeLayout $width $height
		if {$ReserveSide ne $side} { return 0 }
		return $Dim(squaresize:$Vars(layout))
	} finally {
		array unset Dim
		array set Dim $saved
		set ReserveSide $oldSide
		set ReservePixels $oldPixels
		set ReserveKind $oldKind
		set ReserveMaxBoard $oldMaxBoard
	}
}

# The border rectangle {x y size} (canvas coordinates) the current canvas
# would draw with this reserve, or {} when ComputeLayout refuses it; {} 0
# probes the unreserved layout. With decorations=1 returns {x y w h},
# including the always-visible side-to-move column. With withReserve=1,
# returns {borderRect reserveRect} so the future inset can be measured too.
# These probes never render or change the live reserve.
proc reserveBorder {side px {kind auto} {maxBoard 0} {decorations 0} {withReserve 0}} {
	variable Dim
	variable Vars
	variable ReserveSide
	variable ReservePixels
	variable ReserveKind
	variable ReserveMaxBoard
	if {![info exists Vars(width)] || ![info exists Vars(height)]} { return {} }
	if {$side eq {} || $px == 0} { set side {}; set px 0; set kind auto; set maxBoard 0 }
	set saved [array get Dim]
	set oldSide $ReserveSide
	set oldPixels $ReservePixels
	set oldKind $ReserveKind
	set oldMaxBoard [expr {[info exists ReserveMaxBoard] ? $ReserveMaxBoard : 0}]
	try {
		set ReserveSide $side
		set ReservePixels $px
		set ReserveKind $kind
		set ReserveMaxBoard $maxBoard
		ComputeLayout $Vars(width) $Vars(height)
		if {$ReserveSide ne $side} { return {} }
		if {$decorations} {
			set extra 0
			# An enabled side-to-move image is always drawn beside the
			# border. Its column is part of the protected bounding box.
			if {$::board::layout(side-to-move)
				&& (![info exists Vars(3d)] || !$Vars(3d))} {
				set extra [expr {$Dim(gap:x)+$Dim(stm)}]
			}
			set box [list $Dim(border:x1) $Dim(border:y1) \
				[expr {$Dim(bordersize)+$extra}] $Dim(bordersize)]
			if {$withReserve} { return [list $box [reserveRect]] }
			return $box
		}
		return [list $Dim(border:x1) $Dim(border:y1) $Dim(bordersize)]
	} finally {
		array unset Dim
		array set Dim $saved
		set ReserveSide $oldSide
		set ReservePixels $oldPixels
		set ReserveKind $oldKind
		set ReserveMaxBoard $oldMaxBoard
	}
}

# The square this layout would draw if the reserve were released. ComputeLayout
# refuses a reserve that is worse than this, so probe it with the reserve
# cleared; the caller's dimensions and accepted reserve are restored.
proc unreservedSquare {width height} {
	variable Dim
	variable Vars
	variable ReserveSide
	variable ReservePixels
	set saved [array get Dim]
	set oldSide $ReserveSide
	set oldPixels $ReservePixels
	try {
		set ReserveSide {}
		set ReservePixels 0
		ComputeLayout $width $height
		return $Dim(squaresize:$Vars(layout))
	} finally {
		array unset Dim
		array set Dim $saved
		set ReserveSide $oldSide
		set ReservePixels $oldPixels
	}
}

proc setReserve {side px {kind auto} {maxBoard 0}} {
	variable ReserveSide
	variable ReservePixels
	variable ReserveKind
	variable ReserveMaxBoard
	variable Vars
	variable Dim
	if {$side ni {right bottom left {}} || ![string is integer -strict $px] || $px < 0} {
		error "expected reserve side right, bottom, left or {}, and nonnegative integer pixels"
	}
	if {$kind ni {auto squeeze dialog}} {
		error "expected reserve kind auto, squeeze or dialog"
	}
	if {$side eq {} || $px == 0} { set side {}; set px 0; set kind auto; set maxBoard 0 }
	if {![info exists Vars(widget:frame)]} { return 0 }
	# Inset callbacks may request the same reserve after every rebuild.
	if {$side eq $ReserveSide && $px == $ReservePixels && $kind eq $ReserveKind
		&& [info exists ReserveMaxBoard] && $maxBoard == $ReserveMaxBoard} {
		return 1
	}
	set oldSide $ReserveSide
	set oldPixels $ReservePixels
	set oldKind $ReserveKind
	set oldMaxBoard [expr {[info exists ReserveMaxBoard] ? $ReserveMaxBoard : 0}]
	set saved [array get Dim]
	set ReserveSide $side
	set ReservePixels $px
	set ReserveKind $kind
	set ReserveMaxBoard $maxBoard
	ComputeLayout $Vars(width) $Vars(height)
	# ComputeLayout is the single arbitrator: an ordinary ("auto") reserve is
	# kept only when the reserved square stays at least 32 px (see below).
	set accepted [expr {$side eq {} || $ReserveSide eq $side}]
	array unset Dim
	array set Dim $saved
	if {!$accepted} {
		set ReserveSide $oldSide
		set ReservePixels $oldPixels
		set ReserveKind $oldKind
		set ReserveMaxBoard $oldMaxBoard
		return 0
	}
	ApplyReserve3D
	RebuildBoard $Vars(widget:frame) $Vars(width) $Vars(height) true
	return 1
}

proc ApplyReserve3D {} {
	variable Vars
	variable ReserveSide
	variable ReservePixels
	if {![info exists Vars(3d)] || !$Vars(3d)} { return }
	set x {0 0}
	set y {0 0}
	switch $ReserveSide {
		left { set x [list $ReservePixels 0] }
		right { set x [list 0 $ReservePixels] }
		bottom { set y [list 0 $ReservePixels] }
	}
	pack configure $Vars(3dwin) -padx $x -pady $y
}

proc ConfigureReserve3D {width height} {
	variable Vars
	variable ReserveSide
	variable ReservePixels
	if {!$Vars(3d) || $width <= 1 || $height <= 1} { return }
	if {$ReserveSide in {left right}} { incr width $ReservePixels }
	if {$ReserveSide eq "bottom"} { incr height $ReservePixels }
	set Vars(width) $width
	set Vars(height) $height
	# Coalesce Configure/Map and padding changes outside the packer's idle
	# callback. A synchronous rebuild here can nest inside an older rebuild,
	# whose saved layout then overwrites this frame's reserve.
	after cancel $Vars(after)
	set Vars(after) [after 0 [namespace code {
		RebuildBoard $Vars(widget:frame) $Vars(width) $Vars(height) true
	}]]
}

proc RebuildBoard {canv width height {force false}} {
	variable ::board::layout
	variable Layouts
	variable Dim
	variable Vars
	variable board

	# A queued rebuild can outlive its canvas (a pane hidden before the
	# coalescing delay elapsed). There is nothing to lay out for a widget
	# that no longer exists.
	if {![winfo exists $canv]} { return }

	set dimensions ${width}x${height}
	if {!$force && $dimensions eq $Vars(dimensions)} { return }
	set Vars(dimensions) $dimensions
	set Vars(deferred) 0
	set sqsize squaresize:$Vars(layout)

	if {[info exists Dim($sqsize)]} {
		set squareSize $Dim($sqsize)
	} else {
		set squareSize $Dim(squaresize:Normal)
	}
	set edgeThickness $Dim(edgethickness)
	if {[info commands ::mediainset::reserveForLayout] ne ""} {
		set reserve [::mediainset::reserveForLayout $width $height]
		if {[llength $reserve]} {
			variable ReserveSide
			variable ReservePixels
			lassign $reserve ReserveSide ReservePixels
			if {[llength $reserve] == 3} {
				variable ReserveKind
				variable ReserveMaxBoard
				set ReserveKind squeeze
				set ReserveMaxBoard [lindex $reserve 2]
			}
		}
	}
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
	variable RebuildCallbacks
	ApplyReserve3D
	variable NotifyingRebuild
	# A callback may adjust the reserve once, causing a nested rebuild.
	# Notify owners only for the outer rebuild to avoid feedback cycles.
	if {!$NotifyingRebuild} {
		set NotifyingRebuild 1
		try {
			foreach callback $RebuildCallbacks { uplevel #0 $callback }
		} finally { set NotifyingRebuild 0 }
	}
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

	variable ReserveSide
	variable ReservePixels
	variable ReserveKind
	variable ReserveMaxBoard
	variable MinimumReserveSquare
	set fullWidth $canvWidth
	set fullHeight $canvHeight
	set originX 0
	set Dim(reserve:x) 0
	set Dim(reserve:y) 0
	set Dim(reserve:w) 0
	set Dim(reserve:h) 0
	switch $ReserveSide {
		right - left {
			set canvWidth [expr {max(1, $canvWidth - $ReservePixels)}]
			set Dim(reserve:w) $ReservePixels
			set Dim(reserve:h) $fullHeight
			if {$ReserveSide eq "left"} {
				set originX $ReservePixels
			} else {
				set Dim(reserve:x) $canvWidth
			}
		}
		bottom {
			set canvHeight [expr {max(1, $canvHeight - $ReservePixels)}]
			set Dim(reserve:y) $canvHeight
			set Dim(reserve:w) $fullWidth
			set Dim(reserve:h) $ReservePixels
		}
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

	# The coordinate letters are sized in points, so the room for them (in
	# pixels) grows with the screen's DPI, else a 200% display clips them.
	set dpi [expr {max(1.0, [tk scaling]*72.0/96.0)}]
	if {$layout(border) && $layout(coordinates)} {
		set Dim(borderthickness) [expr {int($dpi*[::font::scaleFactor]*$Dim(borderthickness) + 0.5)}]
		set Dim(offset) [expr {int($dpi*[::font::scaleFactor]*$Dim(offset) + 0.5)}]
	} elseif {$layout(coordinates)} {
		set Dim(offset) [expr {int($dpi*$Dim(offset) + 0.5)}]
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

	# Decorations occupy one column, to the right of the board. In a
	# reserved slot centre board + that column together, recovering the
	# otherwise empty mirror column on the left (needed in small windows).
	set decorationShift [expr {$ReserveSide ne {} ? $stmsize : 0}]
	if {$layout(border)} {
		set width [expr {$width - 2*$Dim(borderthickness) - 2*$stmsize + $decorationShift}]
	} else {
		set width [expr {$width - 2*max($Dim(offset), $stmsize) + $decorationShift}]
	}

	set height [expr {$height - 2*$Dim(offset)}]

	if {$Vars(layout) eq "Crazyhouse" && ($layout(border) || !$layout(coordinates))} {
		set width [expr {$width - min($width, $height)/24}]
	}

	set boardsize				[expr {min($width, $height)}]
	if {$ReserveSide eq "left" && $ReserveKind eq "squeeze" && [info exists ReserveMaxBoard] && $ReserveMaxBoard > 0} {
		set extraWidth [expr {2*$Dim(borderthickness) + $stmsize + $Dim(offset:coords)}]
		set targetBoard [expr {$ReserveMaxBoard - $extraWidth}]
		set minBoard [expr {8 * $MinimumReserveSquare}]
		if {$targetBoard >= $minBoard} {
			set boardsize [expr {min($boardsize, $targetBoard)}]
		} else {
			set boardsize [expr {min($boardsize, $minBoard)}]
		}
	}
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

	# Video may shrink the board down to the floor (VAL-MED-013).
	# Below the floor, a reserve may shift the board but never shrink it
	# (VAL-MED-014). The same rule applies to video and dialog reserves.
	if {$ReserveSide ne {} && $Dim($sqsize) < $MinimumReserveSquare} {
		set unreserved [unreservedSquare $fullWidth $fullHeight]
		if {$Dim($sqsize) < $unreserved} {
			set ReserveSide {}
			set ReservePixels 0
			set ReserveKind auto
			ComputeLayout $fullWidth $fullHeight $bordersize
			return
		}
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
	# The video inset yielding its strip to a dialog that needs the work-area
	# strip on the right (VAL-DLG-013) sits flush against that strip: the free
	# margin then falls where the dialog is placed. Any other reserve,
	# including a dialog-owned left strip, centres the board in the remaining
	# area exactly like a right reserve, so a left dialog gets the same
	# balanced free margin instead of a hard-coded mirror column.
	if {$ReserveSide eq "left" && $ReserveKind eq "squeeze"} {
		set Dim(border:x1) [expr {$originX + $Dim(offset:coords)}]
	} else {
		set Dim(border:x1)	[expr {$originX + ($canvWidth - $Dim(bordersize) + $Dim(offset:coords) - $decorationShift)/2}]
	}
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

	# Even 6pt is too tall (a high-DPI screen): fall back to pixels (negative size).
	set px [expr {max(6, $Dim(offset) - $delta)}]
	while {$px > 6} {
		set Dim(font) [list $Defaults(coords-font-family) -$px]
		if {[font metrics $Dim(font) -linespace] <= $Dim(offset) - $delta} { break }
		incr px -1
	}
	set Dim(font) [list $Defaults(coords-font-family) -$px]
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
		# A pane rebuild can run before the first game is loaded or after
		# the last one closes. ply requires a live game in the backend.
		if {![::scidb::game::query open?]} {
			$canv itemconfigure stm -state hidden
			return
		}
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
	# bindKeys re-bound the scheme keys over the user overrides' places
	::application::keyEditor::ApplyOverrides
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
	oDlUAAAAAElFTkSuQmCC
}]

set stmBlack [image create photo -data {
	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
	RK5CYII=
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
