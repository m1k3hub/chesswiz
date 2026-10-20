# ======================================================================
# Author : $Author$
# Version: $Revision: 1522 $
# Date   : $Date: 2018-09-16 09:56:42 -0400 (Sun, 16 Sep 2018) $
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

::util::source application

# ======================================================================
# ::ui::message — lightweight status/notification message
# Used by analysis, novelty, and search-preset features.
# Forwards to the log so messages are visible without a modal dialog.
# ======================================================================

namespace eval ui {
proc message {text} {
	::log::info UI $text
}
}

namespace eval application {
namespace eval mc {

set Tab(information)			"&Information"
set Tab(database)				"&Database"
set Tab(board)					"&Board"
set ShortcutPreferences		"Keyboard Preferences"
set ShortcutScheme			"Shortcut scheme:"
set ShortcutChesswiz		"Chesswiz (default)"
set ShortcutChessBase		"ChessBase"
set MainMenu					"&Main Menu"

set ChessInfoDatabase		"Chess Information Data Base"
set Shutdown					"Shutdown..."
set QuitAnyway					"Quit anyway?"
set CancelLogout				"Cancel Logout"
set AbortWriteOperation		"Abort write operation"
set UpdatesAvailable			"Updates available"

set WriteOperationInProgress "Write operation in progress: currently Chesswiz is modifying/writing database '%s'."
set LogoutNotPossible		"Logout is currently not possible, the result would be a corrupted database."
set RestartLogout				"Aborting the write operation will restart the logout process."
set UnsavedFiles				"The following PGN files are unsaved:"
set ThrowAwayAllChanges		"Do you really want to throw away all changes?"

set Deleted						"Games deleted: %d"
set Changed						"Games changed: %d"
set Added						"Games added: %d"
set DescriptionHasChanged	"Description has changed"

} ;# namespace mc

namespace import ::tcl::mathfunc::abs
namespace import ::tcl::mathfunc::max

array set PaneOptions {
	board		{ -width 500 -height 540 -minwidth 300 -minheight 300 -expand both -shrink x -grow x }
	tree		{ -width 500 -height 120 -minwidth 250 -minheight 100 -expand y }
	editor	{ -width 500 -height 520 -minwidth 150 -minheight 200 -expand y }
	games		{ -width 500 -height 520 -minwidth 300 -minheight 100 -expand both }
	dbgames		{ -width 500 -height 200 -minwidth 200 -minheight 100 -expand y }
	analysis	{ -width 500 -height 120 -minwidth 300 -minheight 120 -expand x }
	eco		{ -width 500 -height 520 -minwidth 150 -minheight 100 -expand both }
	media		{ -width 400 -height 300 -minwidth 250 -minheight 200 -expand y }
	report	{ -width 500 -height 400 -minwidth 250 -minheight 150 -expand both }
	assistant	{ -width 400 -height 400 -minwidth 250 -minheight 150 -expand both }
	explorer	{ -width 360 -height 420 -minwidth 220 -minheight 200 -expand y }
}

set BoardLayout {
	root { -shrink none -grow none -width 1005 -height 689 } {
		panedwindow { -orient vert } {
			panedwindow { -orient horz } {
				pane board %board%
				multiwindow { -expand x -shrink x -grow x } {
					frame editor %editor%
					frame games %games%
					frame dbgames %dbgames%
				}
			}
			panedwindow { -orient horz } {
				frame tree %tree%
				frame analysis:1 %analysis%
			}
		}
	}
}

array set Options { shortcut:scheme chesswiz window:geometry {} window:state normal }
array set ShortcutDefaults {}

set FontSizeActive 0

array set Prios		{ analysis 200 board 500 editor 400 games 100 dbgames 110 tree 300 eco 90 media 80 report 70 assistant 60 explorer 50 }
# Explicit allowlist: new panes default to off; eco is deliberately excluded.
array set Zoomable {analysis 1 board 1 editor 1 games 1 dbgames 1 tree 1 media 1 report 1 assistant 1 explorer 1}
array set Defaults	{ menu:background #c3c3c3 }

array set Vars {
	menu:locked		0
	menu:state		normal
	tabs:changed	0
	exit:save		1
	active			1
	updates			{}
	geometry			{}
	need:maxsize	0
	shutdown			0
	scaling:listeners	{}
	window:state:last		""
	last:normal:geometry	""
	restoring:normal		0
}

array set MapTerminalToAnalysis {}
array set MapAnalysisToTerminal {}


proc open {} {
	variable BoardLayout
	variable PaneOptions
	variable Defaults
	variable Vars

	# setup
	::move::setup
	::tcl::mathfunc::srand [clock milliseconds]
	set app .application
	::widget::dialogWatch $app
	set ::util::place::mainWindow $app
	::widget::dialogSetTitle $app [namespace code Title]
	wm protocol $app WM_DELETE_WINDOW [namespace code shutdown]
	set nb [::ttk::notebook $app.nb -takefocus 0] ;# otherwise board does not have focus
	set Vars(control) [::widget::dialogFullscreenButtons $nb]
	set Vars(notebook) $nb
	bind $nb <Configure> [namespace code PlaceMenues]
	bind $Vars(control) <Configure> +[namespace code PlaceMenues]
	::theme::configureBackground $Vars(control).minimize
	::theme::configureBackground $Vars(control).restore
	::theme::configureBackground $Vars(control).close
	$Vars(control).minimize configure -command { wm iconify .application }
	$Vars(control).restore configure -command { ::menu::viewFullscreen toggle }
	$Vars(control).close configure -command [namespace code shutdown]

	set m [tk::menubutton $nb.menu_main \
		-borderwidth 1 \
		-relief raised \
		-padx 2 \
		-pady 2 \
		-background $Defaults(menu:background) \
		-activebackground [::dropdownbutton::activebackground] \
		-activeforeground [::dropdownbutton::activeforeground] \
		-foreground black \
		-activeforeground white \
		-image $icon::16x12::downArrow(black) \
		-compound right \
	]
	UpdateSettingsText $m
	bind $m <<LanguageChanged>> [namespace code [list UpdateSettingsText $m]]
	bind $m <Enter> [namespace code [list EnterSettings $m]]
	bind $m <Leave> [namespace code [list LeaveSettings $m]]
	bind $m <<MenuWillPost>> [namespace code [list BuildSettingsMenu $m]]
	bind $m <<MenuWillUnpost>> [namespace code [list FinishSettings $m]]
	bind $m <Configure> [namespace code PlaceMenues]
	set Vars(menu:main) $m
	set Vars(menu:updates) $nb.menu_updates

	::ttk::notebook::enableTraversal $nb
	bind $nb <<NotebookTabChanged>> [namespace code [list TabChanged $nb]]
	set info [::ttk::frame $nb.information]
	set db [::ttk::frame $nb.database]

	set Vars(ready) 0
	set Vars(terminal:number) 0
	set Vars(frame:information) $info
	set Vars(frame:database) $db

	# IMPORTANT NOTE: this layout has to be loaded before any other layout will be loaded.
	set twm [twm::make $nb.board board \
		[namespace current]::Prios \
		[array get PaneOptions] \
		$BoardLayout \
		-makepane [namespace current]::MakePane \
		-buildpane [namespace current]::BuildPane \
	]
	bind $twm <<TwmReady>> [namespace code [list Startup $twm %d]]
	bind $twm <<TwmAfter>> [namespace code board::afterTWM]
	twm::load $twm

	pack $nb -fill both -expand yes

	bind $app <Destroy> [namespace code { Exit %W }]

#	bind $app <FocusIn> [namespace code [list Activate $nb]]
#	# Will never be triggered. For any reason Tk does not send <FocusOut>
#	# events anymore to toplevels?!
#	bind $app <FocusOut> [namespace code [list Deactivate $nb]]

	if {[tk windowingsystem] eq "x11"} {
		wm client $app [lindex [split [info hostname] .] 0]
		wm protocol $app WM_SAVE_YOURSELF [namespace code [list WmSaveYourself $app]]
		WmSaveYourself $app 0 ;# initial setup

		::scidb::tk::sm connect \
			-restart no \
			-saveYourself [namespace code SmSaveYourself] \
			-interactRequest [namespace code SmInteractRequest] \
			;
	}

	set incrFontSize { ::font::changeFontSize +1 }
	set decrFontSize { ::font::changeFontSize -1 }

	# TODO: Ctrl-Shift-minus is not working on most keyboards.
	# NOTE: Ctrl-Alt is problematic and cannot be used.
	# Possible workaround: Only bind Control-minus and test whether Caps Lock is on.
	# Possible workaround: Bind function keys instead of Control-Shift.
	# Some editors bind Control-Z broadly for undo. A leading pane-only
	# bindtag reserves Ctrl+Shift+Z before those widget/class bindings.
	bind PaneZoomShortcut <Control-Shift-Z> [namespace code {TogglePaneZoom; break}]
	bind .application <FocusIn> +[namespace code {PaneZoomFocus %W}]
	bind .application <Control-Shift-Z> [namespace code {TogglePaneZoom; break}]
	# Phase 2 pane zoom (focus follows size): only real user gestures count.
	# A click reports its widget directly; a keyboard pane switch is a Tab
	# that moves the focus, so the key press arms the next FocusIn. Focus
	# moved by the program (dialogs, engine output, 'focus' calls) has no
	# arming key press and never resizes anything.
	bind .application <ButtonPress-1> +[namespace code {focuszoom::clicked %W}]
	foreach fzKey {<Key-Tab> <Shift-Key-Tab> <Key-ISO_Left_Tab>} {
		bind PaneZoomShortcut $fzKey [namespace code focuszoom::keySwitch]
	}
	bind .application <FocusIn> +[namespace code {focuszoom::focusIn %W}]
	bind .application <Control-Shift-plus>				$incrFontSize
	bind .application <Control-Shift-KP_Add>			$incrFontSize
	bind .application <Control-Shift-minus>			$decrFontSize
	bind .application <Control-Shift-KP_Subtract>	$decrFontSize
	bind .application <<FontSizeChanged>>				[namespace code { FontSizeChanged %W %d }]

	::searchentry::bindShortcuts .application
	bind all <FocusIn> +[namespace code {ShortcutEditingFocus %W}]
	ApplyShortcutScheme
}


# A leading tag overrides board/notation bindings without modifying them.
# Emptying the tag restores the current defaults, including language changes.
proc ApplyShortcutScheme {args} {
	variable Options
	variable ShortcutDefaults

	foreach key [bind ChessBaseBoard] { bind ChessBaseBoard $key {} }
	foreach key [bind ChessBaseEditing] { bind ChessBaseEditing $key {} }
	if {![winfo exists .application]} { return }
	foreach key [array names ShortcutDefaults] {
		bind .application $key $ShortcutDefaults($key)
	}
	array unset ShortcutDefaults

	# Shortcut collisions (PROPOSAL section 7.4, decision D-4). The menu
	# advertises Ctrl+Shift+N (new database) and Ctrl+Shift+G (new game);
	# the deprecated Ctrl+N is kept as a hidden alias for new game in both
	# schemes and is shown nowhere. F10/Ctrl+F10 stay prev/next in both
	# schemes while the menu shows the active scheme's key (Ctrl+Down and
	# Ctrl+Up in the app scheme).
	foreach {spec action} {
		Control-Shift-n newdb
		Control-Shift-N newdb
		Control-Shift-g new
		Control-Shift-G new
		Control-n       new
		Control-N       new
		F10             next
		Control-F10     prev
	} {
		bind .application <$spec> \
			[list ::application::ShortcutApplicationCommand %W $action]
	}

	if {$Options(shortcut:scheme) ne "chessbase"} {
		# the user key overrides come last: they replace the scheme bindings
		::application::keyEditor::ApplyOverrides
		catch { ::menu::RefreshAccelerators }
		return
	}
	foreach key {a A} {
		bind ChessBaseEditing <Control-$key> {event generate %W <<SelectAll>>; break}
	}
	if {[focus] ne ""} { ShortcutEditingFocus [focus] }

	foreach {key cmd} {
		Left              {::application::board::Goto -1}
		Right             {::application::board::Goto +1}
		Home              {::application::board::Goto start}
		End               {::application::board::Goto end}
		Prior             {::application::pgn::scroll -1 pages}
		Next              {::application::pgn::scroll +1 pages}
		Control-f         {::application::board::Rotate $::application::board::Vars(widget:frame)}
		Control-Alt-0     {::application::board::InsertNullMove}
		Control-y         {::application::pgn::RemoveVariation}
		m                 {::application::board::Goto up}
		bracketright      {::scidb::game::strip truncate}
		bracketleft       {::scidb::game::strip moves}
		Control-Alt-y     {::scidb::game::strip marks}
		Control-a         {::application::pgn::editComment after}
		Control-Shift-A   {::application::pgn::editComment before}
		exclam            {::annotation::addNag infix 1}
		question          {::annotation::addNag infix 2}
		Control-n         {::menu::gameNew .application}
		Control-o         {::menu::dbOpen .application}
		Control-s         {::application::board::SaveGame add}
		Control-r         {::application::board::SaveGame replace}
		F10               {::application::board::LoadGame(any) .application next}
		Control-F10       {::application::board::LoadGame(any) .application prev}
		Control-z         {::application::pgn::undo}
		Alt-F2            {::application::ToggleShortcutEngine}
	} {
		# FilterKey preserves the sliding variation selector's handling.
		set command [namespace code [list ShortcutBoardCommand %W %K %s $cmd]]
		bind ChessBaseBoard <$key> $command
		if {[regexp {^(.*-)([a-zA-Z])$} $key -> modifiers letter]} {
			if {[string is lower $letter]} { set letter [string toupper $letter] } \
			else { set letter [string tolower $letter] }
			bind ChessBaseBoard <$modifiers$letter> $command
		}
	}
	if {[info exists ::application::board::Vars(need-binding)]} {
		foreach w $::application::board::Vars(need-binding) { AddShortcutTag $w }
	}

	foreach {key action} {n new o open f search x database} {
		foreach letter [list $key [string toupper $key]] {
			set event <Control-$letter>
			set ShortcutDefaults($event) [bind .application $event]
			bind .application $event [list ::application::ShortcutApplicationCommand %W $action]
		}
	}

	# the user key overrides come last: they replace the scheme bindings
	::application::keyEditor::ApplyOverrides
	catch { ::menu::RefreshAccelerators }
}


proc AddShortcutTag {w} {
	if {![winfo exists $w]} { return }
	if {[ShortcutEditable $w]} { return }
	set tags [bindtags $w]
	if {"ChessBaseBoard" ni $tags} { bindtags $w [linsert $tags 0 ChessBaseBoard] }
}


proc ShortcutEditable {w} {
	if {[winfo class $w] ni {Entry TEntry Text TCombobox Spinbox TSpinbox}} { return 0 }
	# The bundled Tk supports readonly Text widgets (used by PGN notation).
	# They need board shortcuts just like disabled Text widgets.
	return [expr {[$w cget -state] ni {disabled readonly}}]
}


proc ShortcutEditingFocus {w} {
	variable Options
	if {$Options(shortcut:scheme) ne "chessbase"} { return }
	if {![ShortcutEditable $w]} {
		# Clicking the board leaves focus where it was, often a pane's control
		# (e.g. the media seek slider); the scheme applies there too.
		if {[string match .application.nb.board.* $w]} { AddShortcutTag $w }
		return
	}
	set tags [bindtags $w]
	if {"ChessBaseEditing" ni $tags} { bindtags $w [linsert $tags 0 ChessBaseEditing] }
}


proc ShortcutBoardCommand {w key state script} {
	# Continue with widget/class editing even if an editable child inherits this tag.
	if {[ShortcutEditable $w]} { return -code continue }
	# Orientation is independent of the variation selector, which interprets
	# letter keys as variation indices even when Control is pressed.
	if {[string match {::application::board::Rotate *} $script]} {
		uplevel #0 $script
		return -code break
	}
	if {$script eq "::application::board::Goto +1"} {
		# FilterKey recognizes this command when a variation was selected.
		set cmd [list namespace inscope ::application::board { Goto +1 }]
	} else {
		set cmd [list apply [list {} $script ::]]
	}
	board::FilterKey $key $state $cmd
	return -code break
}


proc ShortcutApplicationCommand {w action} {
	# Dialogs and editable fields keep their own text-editing shortcuts.
	if {[winfo class $w] in {Entry TEntry Text TCombobox Spinbox TSpinbox}} { return }
	switch $action {
		new  { ::menu::gameNew .application }
		newdb { ::menu::dbNew .application Normal }
		next { ::application::board::LoadGame(any) .application next }
		prev { ::application::board::LoadGame(any) .application prev }
		open { ::menu::dbOpen .application }
		search - database {
			if {[.application.nb select] ne ".application.nb.database"} {
				if {$action eq "search"} {
					variable ShortcutDefaults
					set cmd $ShortcutDefaults(<Control-f>)
					if {$cmd ne ""} { uplevel #0 $cmd }
				}
				return
			}
			if {$action eq "database"} {
				::menu::dbNew .application Normal
			} else {
				database::OpenAdvancedSearch .application [::scidb::db::get name] \
					[database::currentVariant]
			}
		}
	}
	return -code break
}


proc ToggleShortcutEngine {} {
	set name [analysis::defaultEngine]
	if {$name eq ""} { return }
	foreach number [analysis::Running] {
		if {[set ::engine::${number}::Vars(current:name)] eq $name} {
			analysis::stopEngine $number
			return
		}
	}
	analysis::startEngine $name
}


proc ShortcutPreferences {parent} {
	set dlg $parent.shortcutPreferences
	if {[winfo exists $dlg]} { raise $dlg; return }
	tk::toplevel $dlg -class Dialog
	::widget::dialogButtons $dlg {ok}
	$dlg.ok configure -command [list destroy $dlg]
	set top [ttk::frame $dlg.content -padding 12]
	ttk::label $top.label -text $mc::ShortcutScheme
	pack $top.label -anchor w -pady 4
	foreach {scheme label} {chesswiz ShortcutChesswiz chessbase ShortcutChessBase} {
		ttk::radiobutton $top.$scheme -text [set mc::$label] \
			-variable [namespace current]::Options(shortcut:scheme) -value $scheme
		pack $top.$scheme -anchor w -pady 4
	}
	# the per-key editor: a table of actions with their current key, a
	# capture field for the new key, conflict reporting and reset
	::application::keyEditor::ExtendDialog $dlg $top
	pack $top -fill both -expand yes
	wm title $dlg $mc::ShortcutPreferences
	wm transient $dlg [winfo toplevel $parent]
	wm resizable $dlg false false
	::util::place $dlg -parent $parent -position center
}


# RULE (VAL-RSZ-006): the computed layout minimum of the main window is the
# board layout's own minimum plus the notebook chrome, the same arithmetic as
# ::application::twm::geometry. wm minsize is not authoritative here: fitWindow
# lowers it to fit a smaller saved geometry, so a stale 200x200 save would
# otherwise become the floor.
proc LayoutMinimum {} {
	variable Vars
	if {[info exists Vars(board:twm)] && $Vars(board:twm) ne ""} {
		if {![catch {$Vars(board:twm) dimension} dim] && [llength $dim] >= 4} {
			lassign $dim _ _ minwidth minheight
			if {$minwidth > 0 && $minheight > 0} {
				set bd [expr {2*[::theme::notebookBorderwidth]}]
				return [list [expr {$minwidth + $bd}] \
					[expr {$minheight + $bd + [::theme::notebookTabPaneSize .application.nb]}]]
			}
		}
	}
	lassign [wm minsize .application] minwidth minheight
	return [list $minwidth $minheight]
}


proc GeometrySize {geometry} {
	if {![regexp {^([0-9]+)x([0-9]+)} $geometry -> width height]} { return {} }
	return [list $width $height]
}


proc BelowMinimum? {geometry} {
	lassign [LayoutMinimum] minwidth minheight
	lassign [GeometrySize $geometry] width height
	if {$width eq "" || $height eq ""} { return 1 }
	return [expr {$width < $minwidth || $height < $minheight}]
}


# A normal geometry derived from the work area (80%, centred) for a session
# that starts zoomed without a sane saved normal geometry.
proc DefaultNormalGeometry {app} {
	lassign [winfo workarea $app] wx wy ww wh
	set width [expr {int($ww * 0.8)}]
	set height [expr {int($wh * 0.8)}]
	set x [expr {$wx + ($ww - $width) / 2}]
	set y [expr {$wy + ($wh - $height) / 2}]
	return "${width}x${height}+${x}+${y}"
}


# fitWindow lowers wm minsize to the fitted size; put the real layout minimum
# back so the window manager cannot restore a smaller normal window.
proc ApplyLayoutMinimum {app} {
	lassign [LayoutMinimum] minwidth minheight
	if {$minwidth > 0 && $minheight > 0} {
		lassign [winfo workarea $app] _ _ ww wh
		wm minsize $app [expr {min($minwidth, $ww)}] [expr {min($minheight, $wh)}]
	}
}


proc RestoreNormalGeometry {w} {
	variable Options
	variable Vars
	set geometry $Vars(last:normal:geometry)
	if {[BelowMinimum? $geometry]} { set geometry [DefaultNormalGeometry $w] }
	set geometry [::util::place::fitWindow $w $geometry]
	ApplyLayoutMinimum $w
	if {[BelowMinimum? $geometry]} {
		set geometry [::util::place::fitWindow $w [DefaultNormalGeometry $w]]
		ApplyLayoutMinimum $w
	}
	set Vars(last:normal:geometry) $geometry
	set Options(window:geometry) $geometry
}


proc RestoreWindowGeometry {app} {
	variable Options
	variable Vars
	set geometry $Options(window:geometry)
	if {$geometry ne "" && ![BelowMinimum? $geometry]} {
		set geometry [::util::place::fitWindow $app $geometry]
	} elseif {$geometry ne "" && $Options(window:state) eq "zoomed"} {
		# A legacy save made while maximised (e.g. 200x200): derive a usable
		# normal geometry from the work area instead of restoring it.
		set geometry [::util::place::fitWindow $app [DefaultNormalGeometry $app]]
	} else {
		::util::place $app -position center
		set geometry [::util::place::fitWindow $app]
		if {[BelowMinimum? $geometry]} {
			set geometry [::util::place::fitWindow $app [DefaultNormalGeometry $app]]
		}
	}
	ApplyLayoutMinimum $app
	if {[BelowMinimum? $geometry]} {
		set geometry [::util::place::fitWindow $app [DefaultNormalGeometry $app]]
		ApplyLayoutMinimum $app
	}
	set Vars(last:normal:geometry) $geometry
	# Never persist a normal geometry below the layout minimum.
	if {$Options(window:geometry) eq "" || [BelowMinimum? $Options(window:geometry)]} {
		set Options(window:geometry) $geometry
	}
	wm deiconify $app
	if {[tk windowingsystem] eq "win32" && $Options(window:state) eq "zoomed"} {
		wm state $app zoomed
	}
}


proc RememberWindowGeometry {w} {
	variable Options
	variable Vars
	if {$w ne ".application" || !$Vars(ready) || [::menu::fullscreen?]} { return }
	set state [wm state $w]
	# Iconifying must not erase the last normal/zoomed state.
	if {$state ni {normal zoomed}} { return }
	set previous $Vars(window:state:last)
	set Vars(window:state:last) $state
	set Options(window:state) $state
	if {$state eq "normal"} {
		set geometry [wm geometry $w]
		if {[BelowMinimum? $geometry]} {
			# A zoomed -> normal restore can hand back a stale pre-maximise
			# rect below the layout minimum (Windows 200x200). Re-apply the
			# remembered normal geometry rather than save the degenerate one.
			if {!$Vars(restoring:normal) && $previous eq "zoomed"} {
				set Vars(restoring:normal) 1
				try {
					RestoreNormalGeometry $w
				} finally {
					set Vars(restoring:normal) 0
				}
			}
			return
		}
		set Vars(last:normal:geometry) $geometry
		set Options(window:geometry) $geometry
	}
	# The media inset follows the board's own settled rebuild (the
	# afterRebuild hook in media-inset.tcl), so no independent resize timer
	# is needed here: one would fire after the layout settled and make a
	# quiet window look busy (VAL-RSZ-001). Fullscreen has its own
	# <<Fullscreen>> path. A pure move sends <Configure> too, and changes
	# nothing.
}


# A user resize can push the frame past a work area edge (a moved window
# grown in place, a smaller taskbar, a larger minimum size). Debounced so a
# drag does not move the window on every pixel (the 20 ms debounce leaves
# the layout inside its 500 ms settle budget); fitWindow is a no-op when
# the frame already fits, so it cannot loop. A pure move that keeps the
# window size and stays inside the current work area is deliberately not
# yanked back (a monitor left of the primary one uses a negative origin);
# a move that leaves the work area is clamped like a resize, and so is the
# first size change after the reported work area itself changed.
proc WindowResized {w} {
	variable Vars

	if {$w ne ".application" || !$Vars(ready)} { return }
	if {[info exists Vars(after:fit)]} { after cancel $Vars(after:fit) }
	set Vars(after:fit) [after 20 [namespace code [list KeepInWorkArea $w]]]
}


proc KeepInWorkArea {w} {
	if {![winfo exists $w]} { return 0 }
	if {[wm state $w] ne "normal" || [::menu::fullscreen?]} { return 0 }
	set geometry [wm geometry $w]
	set fitted [::util::place::clampGeometry $geometry [winfo workarea $w] [winfo extents $w]]
	# clampGeometry returns the input unchanged when the frame (including
	# its decorations) already lies inside the current work area, so this
	# is also the "a pure move inside the work area is not yanked" rule.
	if {$fitted eq $geometry} { return 0 }
	::util::place::fitWindow $w $geometry
	return 1
}


# ----------------------------------------------------------------------
# Runtime DPI change: `tk scaling` got a new value while running. Tk 8.6
# neither resizes existing fonts nor emits an event for this (Tk 9's
# <<TkScalingChanged>> is not available), so the relayout is driven from
# here: every pane layout refreshes, the board rebuilds with the new
# factor (its border and coordinate margins follow tk scaling, see
# ComputeLayout in app-board.tcl), the main window is kept inside the
# work area, and registered listeners re-measure the settled layout.
proc scalingChanged {} {
	variable Vars

	if {!$Vars(ready) || [::menu::fullscreen?]} { return }

	if {[info exists Vars(twm)]} {
		foreach twm $Vars(twm) {
			if {[winfo exists $twm]} {
				if {[catch {$twm refresh} err]} {
					::log::error "scalingChanged: $twm refresh failed: $err"
				}
			}
		}
	}

	# Synchronous and forced: the board canvas kept its pixel size, so it
	# sends no <Configure> and ConfigureWindow's deferred rebuild would see
	# unchanged dimensions. board::Apply is a no-op until the pane exists.
	if {[catch {board::Apply} err]} {
		::log::error "scalingChanged: board rebuild failed: $err"
	}
	update idletasks

	# RULE (VAL-RSZ-002): a runtime scaling change relays out in place. The
	# main window keeps its current size while that size still fits the
	# work area; only a window that the new layout minimum (or the old
	# geometry) no longer fits is clamped by fitWindow. A later scaling
	# change never grows the window back, so 1.0 -> 2.0 -> 1.0 restores the
	# board/inset rectangles at the size the window now has.
	if {[wm state .application] eq "normal"} {
		::util::place::fitWindow .application
	}

	# The media inset positions itself against the board's bbox; it owns no
	# scaling hook of its own. Once it registers a listener, this call and
	# the listener notification are the same idempotent relayout.
	if {[info commands ::mediainset::Relayout] ne ""} {
		after idle [list catch {::mediainset::Relayout}]
	}

	foreach listener $Vars(scaling:listeners) {
		after idle [namespace code [list NotifyScalingListener $listener]]
	}
}


# Register/unregister a command evaluated (at global level, after idle)
# after a runtime tk scaling change. Registration is idempotent.
proc addScalingListener {cmd} {
	variable Vars
	if {$cmd ni $Vars(scaling:listeners)} {
		lappend Vars(scaling:listeners) $cmd
	}
}


proc removeScalingListener {cmd} {
	variable Vars
	set pos [lsearch -exact $Vars(scaling:listeners) $cmd]
	if {$pos >= 0} {
		set Vars(scaling:listeners) [lreplace $Vars(scaling:listeners) $pos $pos]
	}
}


proc NotifyScalingListener {listener} {
	if {[catch {uplevel #0 $listener} err]} {
		::log::error "scalingChanged: listener failed: $listener: $err"
	}
}

proc WriteShortcutOptions {chan} {
	RememberWindowGeometry .application
	::options::writeItem $chan [namespace current]::Options
}

trace add variable Options(shortcut:scheme) write [namespace code ApplyShortcutScheme]
::options::hookWriter [namespace current]::WriteShortcutOptions


proc twm {{id ""}} {
	variable Vars

	if {[string length $id]} { return $Vars($id:twm) }
	set tab [$Vars(notebook) select]
	if {[string match {*.board} $tab]} { return $Vars(board:twm) }
	if {[string match {*.database} $tab]} { return [database::twm] }
	return -code error "[namespace current]::twm: no twm selected"
}


proc nameVarFromUid {uid} {
	set name [NameFromUid $uid]
	if {$name eq "analysis"} {
		variable NameVar
		variable Vars

		set analysisNumber [analysisNumberFromUid $uid]
		set nameVar [namespace current]::NameVar($analysisNumber)
		trace add variable [namespace current]::twm::mc::Pane($name) write \
			[namespace code [list UpdateNameVar $analysisNumber]]
		UpdateAnalysisTitle $analysisNumber
	} elseif {$name eq "report"} {
		# the report pane titles itself after the document it shows
		set nameVar [namespace current]::report::PaneTitle
	} elseif {$name eq "assistant"} {
		set nameVar [namespace current]::assistant::PaneTitle
	} else {
		set nameVar [namespace current]::twm::mc::Pane($name)
	}
	return $nameVar
}


proc analysisNumberFromUid {uid} {
	variable MapTerminalToAnalysis
	return $MapTerminalToAnalysis([NumberFromUid $uid])
}


proc NameFromUid {uid}   { return [lindex [split $uid :] 0] }
proc NumberFromUid {uid} { return [lindex [split $uid :] 1] }


proc TabChanged {nb} {
	variable Vars

	set twm $Vars(board:twm)
	if {[string match {*.board} [$nb select]]} { set cmd show } else { set cmd hide }

	foreach w [$twm floats] {
		if {[$twm get! $w hide 0]} { $twm $cmd $w }
	}
}


proc MakePane {twm parent type uid} {
	variable Prios
	variable Vars

	set name [NameFromUid $uid]
	set prio $Prios($name)
	set analysisNumber 0
	set transient 0

	if {[string match {analysis:*} $uid]} {
		variable MapTerminalToAnalysis
		variable MapAnalysisToTerminal

		set number [NumberFromUid $uid]
		incr prio [expr {$number - 1}]
		incr Vars(terminal:number)

		if {![info exists MapTerminalToAnalysis($number)]} {
			set MapTerminalToAnalysis($number) $number
			set MapAnalysisToTerminal($number) $number
		}

		set analysisNumber $MapTerminalToAnalysis($number)
		set Vars(title:$analysisNumber) ""
		if {$analysisNumber > 1} { set transient 1 }
	}

	set nameVar [nameVarFromUid $uid]
	set takefocus [expr {$uid eq "board"}]
	set frame [tk::frame $parent.$uid -borderwidth 0 -takefocus $takefocus]
	variable Zoomable
	set result [list $frame $nameVar $prio $transient [expr {$uid ne "editor"}] yes yes \
		[expr {[info exists Zoomable($name)] && $Zoomable($name)}]]
	switch $name {
		games   { set ns tree::games }
		editor  { set ns pgn }
		dbgames { set ns boardgames }
		default { set ns $name }
	}
	bind $frame <Map> [list [namespace current]::${ns}::activate $frame 1]
	bind $frame <Unmap> [list [namespace current]::${ns}::activate $frame 0]
	bind $frame <Destroy> [list [namespace current]::${ns}::closed $frame]
	bind $frame <Destroy> +[namespace code [list DestroyPane $twm $uid $analysisNumber]]
	set Vars(frame:$uid) $frame
	set Vars(align:board:$uid) 0
	return $result
}


# Phase 2 pane zoom: focus follows size (opt-in per layout, see
# docs/features/FEATURE_PANE_ZOOM.md). Tcl-only: the twm panedwindows are
# plain Tk widgets, so growing a pane is an animated sash move; the layout
# tree and the saved layout stay untouched, and switching the mode off puts
# the saved sash coordinates back exactly.
namespace eval focuszoom {
	variable ratio		1.4		;# R, clamped to the spec range 1.2-1.8
	variable pinBoard	0		;# the board never shrinks
	variable duration	150	;# ~150 ms per the spec; 0 is instant
	variable steps		10
	variable enabled		;# per layout (twm) on/off
	variable baseline	;# sash snapshot taken when switched on
	variable lastPane	;# last grown leaf per twm
	variable keyAfter {}
	variable pendingKey 0	;# a Tab/Shift-Tab armed the next FocusIn
	variable animAfter	;# pending animation timer per panedwindow
	namespace import ::tcl::mathfunc::max ::tcl::mathfunc::min
}


proc focuszoom::isEnabled {twm} {
	variable enabled
	return [expr {[info exists enabled($twm)] && $enabled($twm)}]
}


proc focuszoom::setRatio {r} {
	variable ratio
	set ratio [expr {max(1.2, min(1.8, $r))}]
	return $ratio
}


# The menu checkbutton has already flipped the variable when this runs.
proc focuszoom::toggle {twm} {
	variable enabled
	if {[info exists enabled($twm)] && $enabled($twm)} { enable $twm } else { disable $twm }
}


# The baseline is taken at the first actual zoom, not here: a window resize
# between switching on and zooming must not leave a stale arrangement to
# restore. Switching off with no zoom taken therefore changes nothing.
proc focuszoom::enable {twm} {
	if {[isEnabled $twm]} {return}
	variable enabled
	variable baseline
	variable lastPane
	set enabled($twm) 1
	catch { unset baseline($twm) }
	catch { unset lastPane($twm) }
}


proc focuszoom::disable {twm} {
 variable animAfter
 foreach pw [array names animAfter $twm.*] {after cancel $animAfter($pw); unset animAfter($pw)}
	variable enabled
	variable baseline
	variable lastPane
	set enabled($twm) 0
	if {[info exists baseline($twm)]} {
		# Only at the size the snapshot belongs to; after a window resize
		# the old coordinates would squeeze the board (VAL-PANE-007C).
		lassign $baseline($twm) size snapshot
		if {$size eq [WindowSize $twm]} { Restore $twm $snapshot }
		unset baseline($twm)
	}
	catch { unset lastPane($twm) }
}


proc focuszoom::WindowSize {twm} {
	set top [winfo toplevel $twm]
	return [list [winfo width $top] [winfo height $top]]
}


# A window resize between zooms re-bases the arrangement: the user's
# sashes at the new size are what switching off returns to.
proc focuszoom::windowResized {twm} {
	variable baseline
	variable lastPane
	if {![isEnabled $twm] || ![info exists baseline($twm)]} { return }
	if {[lindex $baseline($twm) 0] eq [WindowSize $twm]} { return }
	unset baseline($twm)
	catch { unset lastPane($twm) }
}


# Same traversal as twm::ZoomSashes; session-only, never part of the layout.
proc focuszoom::Snapshot {twm} {
	set result {}
	set queue [winfo children $twm]
	while {[llength $queue]} {
		set queue [lassign $queue w]
		lappend queue {*}[winfo children $w]
		if {![string match *Panedwindow [winfo class $w]]} { continue }
		set coords {}
		for {set i 0} {$i < [llength [$w panes]] - 1} {incr i} {
			lappend coords [$w sash coord $i]
		}
		lappend result $w $coords
	}
	return $result
}


proc focuszoom::Restore {twm snapshot} {
	# Twice, as in twm::ZoomSashes: a sash placed in a still-shrunken
	# panedwindow is clamped to the panes' minimum size for good.
	foreach pass {1 2} {
		update idletasks
		foreach {w coords} $snapshot {
			if {![winfo exists $w]} { continue }
			set i 0
			foreach xy $coords { catch { $w sash place $i {*}$xy }; incr i }
		}
		if {$pass == 1} { update }
	}
}


proc focuszoom::clicked {w} {
	if {![winfo exists $w]} { return }
	lassign [PaneOfWidget $w] twm pane
	if {$pane ne ""} { growPane $twm $pane }
}


proc focuszoom::keySwitch {} {
 variable pendingKey; variable keyAfter
 set pendingKey 1
 if {$keyAfter ne {}} {after cancel $keyAfter}
 # Tk traverses on idle after the key binding. Expire the gesture within
 # this event turn; a later programmatic focus must never consume it.
 set keyAfter [after idle [namespace code {set pendingKey 0; set keyAfter {}}]]
}


proc focuszoom::focusIn {w} {
	variable pendingKey
	if {!$pendingKey} { return }
	set pendingKey 0
	if {![winfo exists $w]} { return }
	lassign [PaneOfWidget $w] twm pane
	if {$pane ne ""} { growPane $twm $pane }
}


# Resolve a widget to {twm leaf}; "" when the mode is off for its layout,
# the widget is in no pane, or the pane may not zoom.
proc focuszoom::PaneOfWidget {w} {
	if {[catch { set twm [::application::twm] }]} { return "" }
	if {$w ne $twm && ![string match "$twm.*" $w]} { return "" }
	if {![isEnabled $twm]} { return "" }
	foreach uid [$twm leaves] {
		set f [$twm leaf $uid]
		if {$w eq $f || [string match "$f.*" $w]} { return [list $twm $f] }
	}
	return ""
}


proc focuszoom::growPane {twm pane} {
	variable lastPane
	if {![isEnabled $twm] || [$twm zoomed] ne {} || ![$twm get $pane zoomable 0]} { return }
	if {[$twm isfloat [$twm toplevel $pane]]} { return }
	if {[info exists lastPane($twm)] && $lastPane($twm) eq $pane} { return }
	# Grow the child of the enclosing panedwindow; like phase 1, a notebook
	# (including meta frames) grows as a whole. The twm tree decides the
	# parenting: panedwindow panes are not path-parents of their leaves.
	set node $pane
	while {1} {
		set pw [$twm parent $node]
		if {$pw eq "" || $pw eq $twm || ![winfo exists $pw]} { return }
		if {[string match *Panedwindow [winfo class $pw]]} { break }
		set node $pw
	}
	variable baseline
	if {![info exists baseline($twm)]} { set baseline($twm) [list [WindowSize $twm] [Snapshot $twm]] }
	set lastPane($twm) $pane
	set board ""
	catch { set board [$twm leaf board] }
	resize $pw $node $board
}


proc focuszoom::Contains {pw pane leaf} {
 set t [winfo parent $pw]
 while {$t ne {} && ![llength [info commands $t]]} {set t [winfo parent $t]}
 # Panedwindows have the twm root as their Tk parent.
 set node $leaf
 while {$node ne {} && $node ne $t} {
  if {$node eq $pane} {return 1}
  if {[catch {set node [$t parent $node]}]} {break}
 }
 return 0
}

# The board's minimum is expressed in squares by the board renderer. Probe
# that same arithmetic, including decorations, instead of guessing pixels.
# While the media inset owns a strip of the board pane, the minimum must
# also keep that reserve feasible: otherwise focus zoom squeezes the board
# until no strip fits and the video falls back over the board (VAL-PANE-008).
proc focuszoom::BoardMinimum {node board horizontal} {
 set dim [expr {$horizontal ? "width" : "height"}]
 if {$board ne [::mediainset::Pane]} {return 0}
 set c $::application::board::Vars(widget:frame)
 set width [winfo width $c]; set height [winfo height $c]
 set lo 1; set hi [expr {$horizontal ? $width : $height}]
 while {$lo < $hi} {
  set mid [expr {($lo+$hi)/2}]
  set sq [BoardMinSquare [expr {$horizontal ? $mid : $width}] [expr {$horizontal ? $height : $mid}]]
  if {$sq >= $::application::board::MinimumReserveSquare} {set hi $mid} else {set lo [expr {$mid+1}]}
 }
 return [expr {[winfo $dim $node]-[winfo $dim $c]+$lo}]
}

# The square size a board canvas <w> x <h> would have once the media inset
# has taken its strip, using the inset's own planner so the probe and the
# realized reserve cannot drift. While the inset is shown its reserve is
# mandatory here: a size at which no strip fits reports no square, so the
# search keeps growing until the video has a place beside the board.
proc focuszoom::BoardMinSquare {w h} {
 set reserve [::mediainset::reserveForLayout $w $h]
 if {![llength $reserve]} {
  # hidden, swapped or 3D: the inset is not reserving a strip
  return [::application::board::reserveSquare {} 0 $w $h]
 }
 lassign $reserve side px
 if {$side eq {}} {return 0}
 return [::application::board::reserveSquare $side $px $w $h]
}

proc focuszoom::resize {pw node board} {
	variable ratio
	variable pinBoard
	set panes [$pw panes]
	set n [llength $panes]
	if {$n < 2} { return }
	set horz [expr {[$pw cget -orient] eq "horizontal"}]
	set dim [expr {$horz ? "width" : "height"}]
	set idx [lsearch -exact $panes $node]
	if {$idx < 0} { return }
	set R [setRatio $ratio]
	set sizes {}
	set total 0
	foreach p $panes {
		set s [winfo $dim $p]
		lappend sizes $s
		incr total $s
	}
	set cur [lindex $sizes $idx]
	if {$cur <= 0 || $total <= 0} { return }
	# Minimums: the panedwindow -minsize of every pane; the board can be
	# pinned so it never shrinks below its current size.
	set mins {}
	foreach p $panes {
		set m [$pw panecget $p -minsize]
		if {$board ne {} && [Contains $pw $p $board]} {
			set m [max $m [BoardMinimum $p $board $horz]]
		}
		if {$pinBoard && $p ne $node && $board ne ""
				&& [Contains $pw $p $board]} {
			set m [expr {max($m, [winfo $dim $p])}]
		}
		lappend mins $m
	}
	# The focused pane grows by R, bounded by the siblings' minimums.
	set avail $total
	foreach m $mins { incr avail -$m }
	incr avail [lindex $mins $idx]
	set target [expr {int(round($cur * $R))}]
	if {$target > $avail} { set target $avail }
	if {$target <= $cur} { return }
	# The siblings shrink in proportion, each keeping its minimum size.
	set new [lreplace $sizes $idx $idx $target]
	set rest [expr {$total - $target}]
	set factor [expr {double($rest) / ($total - $cur)}]
	set others {}
	for {set i 0} {$i < $n} {incr i} {
		if {$i == $idx} { continue }
		lappend others $i
		set ns [expr {int(round([lindex $sizes $i] * $factor))}]
		set new [lreplace $new $i $i [expr {max($ns, [lindex $mins $i])}]]
	}
	# Absorb rounding and clamping drift into siblings with room to spare.
	set drift $rest
	foreach i $others { incr drift -[lindex $new $i] }
	while {$drift != 0} {
		set progressed 0
		foreach i $others {
			if {$drift == 0} { break }
			set ns [lindex $new $i]
			if {$drift < 0 && $ns > [lindex $mins $i]} {
				set new [lreplace $new $i $i [incr ns -1]]
				incr drift 1
				set progressed 1
			} elseif {$drift > 0} {
				set new [lreplace $new $i $i [incr ns 1]]
				incr drift -1
				set progressed 1
			}
		}
		if {!$progressed} { break }
	}
	# Sash offsets (sash width and padding) are taken from the live geometry,
	# so restored and animated coordinates land exactly.
	set offsets {}
	for {set i 0} {$i < $n - 1} {incr i} {
		lassign [$pw sash coord $i] x y
		set cum 0
		for {set j 0} {$j <= $i} {incr j} { incr cum [lindex $sizes $j] }
		lappend offsets [expr {($horz ? $x : $y) - $cum}]
	}
	set final {}
	set cum 0
	for {set i 0} {$i < $n - 1} {incr i} {
		incr cum [lindex $new $i]
		lappend final [expr {$cum + [lindex $offsets $i]}]
	}
	animate $pw $horz $final
}


proc focuszoom::animate {pw horz final} {
	variable duration
	variable steps
	variable animAfter
	if {[info exists animAfter($pw)]} {
		after cancel $animAfter($pw)
		unset animAfter($pw)
	}
	set start {}
	for {set i 0} {$i < [llength [$pw panes]] - 1} {incr i} {
		lassign [$pw sash coord $i] x y
		lappend start [expr {$horz ? $x : $y}]
	}
	# Instant when the animation cannot run or keep up.
	if {$duration <= 0 || $steps <= 1 || [catch { AnimateStep $pw $horz $start $final [clock milliseconds] }]} {
		catch { Place $pw $horz $final }
	}
}


proc focuszoom::AnimateStep {pw horz start final began} {
 variable duration; variable steps; variable animAfter
 catch {unset animAfter($pw)}
 if {![winfo exists $pw]} {return}
 set fraction [expr {min(1.0, double([clock milliseconds]-$began)/max(1,$duration))}]
 set coords {}
 foreach a $start b $final {lappend coords [expr {int(round($a+($b-$a)*$fraction))}]}
 # A delayed frame catches up immediately, rather than extending animation.
 if {[catch {Place $pw $horz $coords}]} {catch {Place $pw $horz $final}; return}
 if {$fraction >= 1} {return}
 set animAfter($pw) [after [expr {max(1,$duration/max(1,$steps))}] \
  [list ::application::focuszoom::AnimateStep $pw $horz $start $final $began]]
}

proc focuszoom::Place {pw horz coords} {
	set i 0
	foreach c $coords {
		if {$horz} { $pw sash place $i $c 0 } else { $pw sash place $i 0 $c }
		incr i
	}
}


proc PaneZoomFocus {w} {
	if {![winfo exists $w] || [catch {set manager [twm]}]} { return }
	foreach uid [$manager leaves] {
		set p [$manager leaf $uid]
		if {$w eq $p || [string match "$p.*" $w]} {
			set tags [bindtags $w]
			if {"PaneZoomShortcut" ni $tags} { bindtags $w [linsert $tags 0 PaneZoomShortcut] }
			return
		}
	}
}


# The explicit pane is used by header buttons; menu/key actions use focus.
proc TogglePaneZoom {{pane ""} {manager ""}} {
	variable Vars
	if {$manager eq ""} {
		if {[catch {set manager [twm]}]} { return }
	}
	if {$pane eq ""} {
		set w [focus]
		foreach uid [$manager leaves] {
			set f [$manager leaf $uid]
			if {$w eq $f || [string match "$f.*" $w]} { set pane $f; break }
		}
		if {$pane eq "" && [$manager zoomed] ne ""} { $manager zoom ""; return }
		if {$pane eq "" && "board" in [$manager leaves]} { set pane [$manager leaf board] }
	}
	if {$pane eq "" || ![$manager get $pane zoomable 0]
		|| [$manager isfloat [$manager toplevel $pane]]} { return }
	$manager zoom $pane
}


proc BuildPane {twm frame uid width height} {
	variable Vars

	switch [NameFromUid $uid] {
		analysis	{
			variable MapTerminalToAnalysis
			set analysisNumber $MapTerminalToAnalysis([NumberFromUid $uid])
			set patternNumber 0
			if {!$Vars(loading) && [set patternNumber [expr {$Vars(terminal:number) - 1}]] > 0} {
				set patternNumber $MapTerminalToAnalysis($patternNumber)
			}
			analysis::build $frame $analysisNumber $patternNumber
		}
		eco {
			if {"editor" in [$twm leaves]} {
				lassign [$twm dimension [$twm leaf editor]] width height _ _ _ _
			}
			eco::build $frame -id board
			$frame configure -width $width -height $height
			set Vars(align:board:eco) 1
		}
		tree {
			tree::build $twm $frame $width $height
			set Vars(align:board:tree) 1
		}
		media	{ media::build $twm $frame $width $height }
		report	{ report::build $frame $width $height }
		assistant	{ assistant::build $frame $width $height }
		explorer	{ explorer::build $frame $width $height }
		board		{ board::build $frame $width $height }
		editor	{ pgn::build $frame $width $height }
		games		{ tree::games::build $twm $frame $width $height }
		dbgames		{ boardgames::build $frame $width $height }
		default	{ return -code error "BuildPane: unknown pane $uid" }
	}
}


proc DestroyPane {twm uid analysisNumber} {
	variable Vars

	if {$Vars(shutdown)} { return }

	if {[string match {analysis:*} $uid]} {
		variable MapTerminalToAnalysis
		variable MapAnalysisToTerminal

		set terminalNumber $MapAnalysisToTerminal($analysisNumber)
		array unset MapAnalysisToTerminal $analysisNumber
		array set vars [array get Vars frame:*]

		for {set i [expr {$terminalNumber + 1}]} {$i <= $Vars(terminal:number)} {incr i} {
			set newTerminalNumber [expr {$i - 1}]
			set number $MapTerminalToAnalysis($i)
			$twm set [$twm leaf analysis:$i] transient [expr {$newTerminalNumber != 1}]
			$twm changeuid analysis:$i analysis:$newTerminalNumber
			set MapTerminalToAnalysis($newTerminalNumber) $number
			set MapAnalysisToTerminal($number) $newTerminalNumber
			set Vars(frame:analysis:$newTerminalNumber) $vars(frame:analysis:$i)
			UpdateAnalysisTitle $number
		}

		array unset Vars frame:analysis:$Vars(terminal:number)
		array unset MapTerminalToAnalysis $Vars(terminal:number)
		incr Vars(terminal:number) -1
	} else {
		array unset Vars frame:$uid
	}
}


proc UpdateNameVar {analysisNumber args} {
	UpdateAnalysisTitle $analysisNumber
}


proc UpdateAnalysisTitle {analysisNumber {title ""}} {
	variable Vars

	if {[string length $title] == 0} {
		set title $Vars(title:$analysisNumber)
	}
	updateAnalysisTitle $analysisNumber $title
}


proc updateAnalysisTitle {analysisNumber {title ""}} {
	reflow::onPaneStateChange
	variable MapAnalysisToTerminal
	variable NameVar
	variable Vars

	set Vars(title:$analysisNumber) $title
	if {[string length $title] == 0} { set title $twm::mc::Pane(analysis) }
	if {[info exists MapAnalysisToTerminal($analysisNumber)]} {
		set terminalNumber $MapAnalysisToTerminal($analysisNumber)
		if {$terminalNumber > 1} { append title " ($terminalNumber)" }
	}
	set NameVar($analysisNumber) $title
}


proc newAnalysisPane {analysisNumber} {
	variable MapTerminalToAnalysis
	variable MapAnalysisToTerminal
	variable PaneOptions
	variable Vars

	set highest $Vars(terminal:number)
	set terminalNumber [expr {$highest + 1}]
	set uid analysis:$terminalNumber
	set twm $Vars(board:twm)
	set MapTerminalToAnalysis($terminalNumber) $analysisNumber
	set MapAnalysisToTerminal($analysisNumber) $terminalNumber

	if {$highest > 0} {
		$twm clone analysis:$highest $uid
	} else {
		$twm new frame analysis:1 $PaneOptions(analysis)
	}
}


# Show pane <uid> of the board tab: add it to the layout when it is not
# part of it, then bring it to the front (its tab, its multiwindow or
# notebook page, or its toplevel when undocked). Returns the twm frame,
# or {} when the board layout is not available. Automatic content callers
# pass explicit=false so they do not create a persistent user reopen override.
proc openPane {uid {explicit true}} {
	variable PaneOptions
	variable Vars

	if {![info exists Vars(board:twm)]} { return {} }
	set twm $Vars(board:twm)

	if {$uid ni [$twm leaves]} {
		$twm new frame $uid $PaneOptions($uid)
		update idletasks
	}
	if {[catch { set frame [$twm leaf $uid] }] || ![winfo exists $frame]} { return {} }

	if {![string match {*.board} [$Vars(notebook) select]]} {
		switchTab board
	}

	if {$explicit} { reflow::explicitOpen $twm $uid }
	reflow::onPaneStateChange
	set parent [$twm parent $frame]
	if {[$twm ismultiwindow $parent] || [$twm isnotebook $parent]} {
		$twm select $parent $frame
	}

	set top [$twm toplevel $frame]
	if {[$twm isfloat $top]} { raise $top }
	return $frame
}


proc resizePaneHeight {analysisNumber minHeight} {
	variable MapAnalysisToTerminal
	variable Vars

	set twm $Vars(board:twm)
	set uid analysis:$MapAnalysisToTerminal($analysisNumber)
	set pane [$twm leaf $uid]

	lassign [$twm dimension $pane] _ height _ _ _ _
	set height [expr {max($height,$minHeight)}]

	if {[$twm isfloat [$twm toplevel $pane]]} {
		set height $minHeight
		set maxHeight $minHeight
	} else {
		set maxHeight 0
	}
	$twm resize $pane 0 $height 0 $minHeight 0 $maxHeight
}


proc mapToTerminalNumber {analysisNumber} {
	variable MapAnalysisToTerminal

	if {![info exists MapAnalysisToTerminal($analysisNumber)]} { return -1 }
	return $MapAnalysisToTerminal($analysisNumber)
}


proc activeTab {} {
	return [lindex [split [.application.nb select] .] end]
}


proc exists? {uid} {
	variable Vars
	if {![info exists Vars(frame:$uid)]} { return false }
	return [winfo exists $Vars(frame:$uid)]
}


proc shutdown {} {
	variable icon::32x32::shutdown
	variable ::scidb::mergebaseName
	variable twm::Options
	variable Vars

	set dlg .application.shutdown
	if {[winfo exists $dlg]} { return }

	if {[::dialog::messagebox::open?] eq "question"} { bell; return }
	if {[string match .application* [grab current]]} { bell; return }

	#::widget::dialogRaise .application
	raise .application

	if {[::util::photos::busy?]} {
		append msg $::util::photos::mc::DownloadStillInProgress "\n\n"
		append msg $mc::QuitAnyway
		set reply [::dialog::question -parent .application -message $msg -default no]
		if {$reply ne "yes"} { return }
		::util::photos::terminateUpdate
	}

	set n 0
	set unsavedFiles [::scidb::app::get unsavedFiles]
	if {$mergebaseName in $unsavedFiles} { incr n }

	if {[llength $unsavedFiles] > $n} {
		append msg $mc::UnsavedFiles
		append msg <embed>
		append msg $mc::ThrowAwayAllChanges

		set reply [::dialog::question \
			-parent .application \
			-message $msg \
			-default no \
			-topmost yes \
			-embed [namespace code [list EmbedUnsavedFiles $unsavedFiles]] \
		]
		if {$reply ne "yes"} { return }
	}

	# Keep presentation suspended through modal close/save dialogs too.
	set ::application::reflow::S(saving) 1
	try {
		# Session presentation must not leak into the saved layout.
		foreach t $Vars(twm) { focuszoom::disable $t }
		reflow::RevertForExit

		if {![twm::saveLayouts]} { return }

		switch [::game::queryCloseApplication .application] {
			restore	{ set backup 1 }
			discard	{ set backup 0 }
			cancel	{ return }
		}

		foreach toplevel [winfo children .] {
			if {$toplevel ne ".application"} { destroy $toplevel }
		}

		tk::toplevel $dlg -class Scidb
		wm withdraw $dlg
		pack [tk::frame $dlg.f -borderwidth 2 -relief raised]
		pack [tk::label $dlg.f.text -compound left -image $shutdown -text " $mc::Shutdown"] -padx 10 -pady 10
		wm resizable $dlg no no
		wm transient $dlg .application
		::util::place $dlg -parent .application -position center
		update idletasks
		::scidb::tk::wm frameless $dlg
		wm deiconify $dlg
		::ttk::grabWindow $dlg
		::widget::busyCursor on
		prepareExit $backup
		if {[tk windowingsystem] eq "x11"} { ::scidb::tk::sm disconnect }
		::widget::busyCursor off
		::ttk::releaseGrab $dlg
		set Vars(shutdown) 1
		catch { file delete -force -- $::scidb::dir::temp }
		destroy .application
	} finally {
		set ::application::reflow::S(saving) 0
		if {[winfo exists .application]} {
			reflow::onConfigure .application [winfo width .application] [winfo height .application]
		}
	}
}


proc prepareExit {{backup 1}} {
	variable Vars

	if {$Vars(exit:save)} {
		::log::delay
		::remote::cleanup
		database::prepareClose
		::scidb::app::close
		if {$backup} { ::game::backup }
		::scidb::app::finalize
		set Vars(exit:save) 0
		::options::startTransaction
		::options::saveOptionsFile
		twm::saveTableOptions
		::options::endTransaction
		::load::write
	}
}


proc switchTab {which} {
	.application.nb select .application.nb.$which
	update idletasks
	${which}::setFocus
}


proc ready? {} {
	variable Vars
	return $Vars(ready)
}


if {[tk windowingsystem] eq "x11"} {

proc WmSaveYourself {app {shutdown 0}} {
	if {$shutdown} { prepareExit }
	wm command $app [concat [::scidb::tk::sm get -command] [::scidb::tk::sm get -argv]]
}


proc SmSaveYourself {shutdown} {
	if {$shutdown} {
		prepareExit
	}
}


proc SmInteractRequest {shutdown} {
	set base [::scidb::app::writing -background no]

	## Handle foreground process ####################################
	if {[string length $base]} {
		set parent [grab current]
		if {[string length $parent] == 0} { set parent .application }
		set base [::util::databaseName $base]
		set msg [format $mc::WriteOperationInProgress $base]

		if {![::scidb::progress::interruptable?]} {
			set detail $mc::LogoutNotPossible
			dialog::error -parent $parent -message $msg -detail $detail -topmost yes 
		} else {
			set buttons [list [list cancel $mc::CancelLogout] [list abort $mc::AbortWriteOperation]]
			set detail  $mc::RestartLogout
			set reply [::dialog::warning \
				-parent $parent \
				-message $msg \
				-detail $detail \
				-buttons $buttons \
				-topmost yes \
				-centeronscreen yes \
			]
			if {$reply eq "cancel"} { return 0 }
			set cmd [namespace code [list SmCallSaveYourself $shutdown]]
			if {[::scidb::progress::interrupt -inform $cmd]} { return 1 }
		}

		::log::suppress yes
		update
		return 0
	}

	## Handle background process - always interruptable #############
	set base [::scidb::app::writing -background yes]
	if {[string length $base] == 0} { return 1 }
	set base [::util::databaseName $base]
	set msg [format $mc::WriteOperationInProgress $base]
	set buttons [list [list cancel $mc::CancelLogout] [list abort $mc::AbortWriteOperation]]

	set reply [::dialog::warning -parent $parent \
		-message $msg \
		-buttons $buttons \
		-topmost yes \
		-centeronscreen yes \
	]
	if {$reply eq "cancel"} { return 0 }
	::log::suppress yes
	::scidb::progress::interrupt -wait yes
	return 1
}


proc SmCallSaveYourself {shutdown} {
	update
	::log::suppress no
	::scidb::tk::sm saveyourself -shutdown $shutdown
}

} ;# [tk windowingsystem] eq "x11"


proc InformAboutUpdates {item} {
	variable Vars

	lappend Vars(updates) $item
	BuildUpdatesButton
}


# TODO: unused
proc Activate {nb} {
	variable Vars

	if {!$Vars(active)} {
		set Vars(active) 1
		set current [lindex [split [$nb select] .] end]
		${current}::setActive yes
	}
}	


# TODO: unused
proc Deactivate {nb} {
	variable Vars

	if {$Vars(active) && ![string match {.application.*} [focus]]} {
		set Vars(active) 0
		set current [lindex [split [$nb select] .] end]
		${current}::setActive no
	}
}	


proc EnterSettings {w} {
	variable Vars

	set Vars(menu:state) active

	if {!$Vars(menu:locked)} {
		$w configure -state active -image $icon::16x12::downArrow(white)
	}
}


proc LeaveSettings {w} {
	variable Vars

	set Vars(menu:state) normal

	if {!$Vars(menu:locked)} {
		$w configure -state normal -image $icon::16x12::downArrow(black)
	}
}


proc BuildSettingsMenu {m} {
	variable Vars

	# The drop-down is built once; each cascade fills lazily on post
	# (VAL-BAR-005). Re-posting only re-points the menubutton.
	if {![info exists Vars(menu:entries)] || ![winfo exists $Vars(menu:entries)]} {
		catch { destroy $m.entries }
		::menu $m.entries
		::menu::build $m.entries
		set Vars(menu:entries) $m.entries
	}

	$m configure \
		-background [::dropdownbutton::activebackground] \
		-activebackground [::dropdownbutton::activebackground] \
		-foreground white \
		-activeforeground [::dropdownbutton::activeforeground] \
		-image $icon::16x12::downArrow(white) \
		-menu $m.entries \
		-direction below \
		;
	set Vars(menu:locked) 1
}


proc FinishSettings {m} {
	variable Defaults
	variable Vars

	$m configure \
		-background $Defaults(menu:background) \
		-activebackground [::dropdownbutton::activebackground] \
		-foreground black \
		-activeforeground white \
		-image $icon::16x12::downArrow(black) \
		;
	set Vars(menu:locked) 0

	if {$Vars(menu:state) eq "normal"} {
		LeaveSettings $m
	} else {
		EnterSettings $m
	}
}


proc MakeUpdateInfo {} {
	variable Vars

	if {[llength $Vars(updates)]} {
		set Vars(updates:tooltip) "${mc::UpdatesAvailable}:"
		foreach item $Vars(updates) {
			switch $item {
				photos { append Vars(updates:tooltip) \n $::util::photos::mc::PhotoFiles }
			}
		}
	}
}


proc BuildUpdatesButton {} {
	variable Defaults
	variable Vars

	set m $Vars(menu:updates)
	if {[winfo exists $m]} { return }

	tk::menubutton $m \
		-borderwidth 1 \
		-relief raised \
		-padx 2 \
		-pady 2 \
		-background $Defaults(menu:background) \
		-activebackground [::dropdownbutton::activebackground] \
		-foreground black \
		-activeforeground white \
		-image $icon::16x16::softwareUpdate \
		;
	bind $m <<LanguageChanged>> [namespace code MakeUpdateInfo]
	bind $m <Enter> [list set [namespace current]::Vars(menu:state) active]
	bind $m <Leave> [list set [namespace current]::Vars(menu:state) normal]
	bind $m <<MenuWillPost>> [namespace code [list BuildUpdatesMenu $m]]
	bind $m <<MenuWillUnpost>> [namespace code [list FinishUpdates $m]]
	bind $m <Configure> [namespace code PlaceMenues]

	PlaceMenues
	MakeUpdateInfo
	tooltip::tooltip $m [namespace current]::Vars(updates:tooltip)
}


proc BuildUpdatesMenu {m} {
	variable Vars

	catch { destroy $m.updates }
	::menu $m.updates

	foreach item $Vars(updates) {
		switch $item {
			photos { set txt $::util::photos::mc::PhotoFiles }
		}
		$m.updates add command -label $txt -command [namespace code [list InstallUpdate $item]]
	}

	$m configure \
		-background [::dropdownbutton::activebackground] \
		-activebackground [::dropdownbutton::activebackground] \
		-foreground white \
		-activeforeground white \
		-menu $m.updates \
		-direction below \
		;
	set Vars(menu:locked) 1
}


proc FinishUpdates {m} {
	variable Defaults
	variable Vars

	$m configure \
		-background $Defaults(menu:background) \
		-activebackground [::dropdownbutton::activebackground] \
		-foreground black \
		-activeforeground white \
		;
	set Vars(menu:locked) 0
}


proc InstallUpdate {item} {
	variable Vars

	::util::photos::openDialog .application
	set i [lsearch $Vars(updates) $item]
	set Vars(updates) [lreplace $Vars(updates) $i $i]

	if {[llength $Vars(updates)] == 0} {
		destroy $Vars(menu:updates)
	}
}


proc EmbedUnsavedFiles {unsaved w infoFont alertFont} {
	::html $w.t \
		-center no \
		-fittowidth no \
		-borderwidth 0 \
		-doublebuffer no \
		-exportselection yes \
		-imagecmd [namespace code GetImage] \
		-css "html { background: [$w cget -background] }"
		;
	place $w.t -x 10 -y 0

	$w.t onmouseover [list [namespace current]::MouseEnter $w.t]
	$w.t onmouseout  [list [namespace current]::MouseLeave $w.t]

	array set font [font actual $infoFont]
	set family $font(-family)
	set size [expr {abs($font(-size)) + 4}]

	append content "<table style='font-family: ${family}; font-size: ${size}px;'>"

	foreach file $unsaved {
		lassign [::scidb::db::get changes $file] added changed deleted descriptionHasChanged
		append content "<tr>"
		append content "<td id='$file'>[::util::databaseName $file]&ensp;</td>"
		if {$deleted > 0} {
			append content "<td id='Deleted' count='$deleted'><img src='deleted'></td>"
		}
		if {$changed > 0} {
			append content "<td id='Changed' count='$changed'><img src='edit'></td>"
		}
		if {$added > 0} {
			append content "<td id='Added' count='$added'><img src='plus'></td>"
		}
		if {$descriptionHasChanged} {
			append content "<td id='DescriptionHasChanged'><img src='info'></td>"
		}
		append content "</tr>"
	}

	append content "</table>"
	lassign [$w.t parse $content] x0 y0 x1 y1
	set margins [expr {2*[$w.t margin]}]
	set width [expr {$x1 - $x0 + $margins + 10}]
	set height [expr {$y1 - $y0 + $margins}]
	$w configure -width $width -height $height
	$w.t configure -width $width ;# prevent endless loop in Tk lib (Tk bug)
}


proc GetImage {code} {
	return [list [set ::icon::12x12::$code] [namespace code DoNothing]]
}


proc DoNothing {args} {
	# nothing to do
}


proc MouseEnter {w nodes} {
	foreach node $nodes {
		set id [$node attribute -default {} id]
		if {[llength $id]} {
			if {[info exists mc::$id]} {
				set count [$node attribute -default 0 count]
				if {$count} {
					set id [format [set mc::$id] $count]
				} else {
					set id [set mc::$id]
				}
			}
			::tooltip::show $w $id
		}
	}
}


proc MouseLeave {w nodes} {
	foreach node $nodes {
		set id [$node attribute -default {} id]
		if {[llength $id]} { return [::tooltip::hide] }
	}
}


proc PlaceMenues {} {
	variable Vars

	set height [expr {[::theme::notebookTabPaneSize $Vars(notebook)] - 2}]

	# place controls
	set w $Vars(control)
	set parent [winfo parent $w]
	if {[::menu::fullscreen?]} {
		set x [expr {[winfo width $parent] - [winfo width $w]}]
		place $w -x $x -y 0 -height [winfo height $Vars(menu:main)]
	} else {
		place forget $w
	}

	# place main menu
	set m $Vars(menu:main)
	set parent [winfo parent $m]
	set x [expr {[winfo width $parent] - [winfo width $m]}]
	if {$Vars(control) in [place slaves $parent]} {
		set x [expr {$x - [winfo width $Vars(control)]}]
	}
	$m configure -height $height
	place $m -x $x -y 0

	# place update menu
	set m $Vars(menu:updates)
	if {[winfo exists $m]} {
		$m configure -height $height
		set x [expr {$x - [winfo width $m] - 5}]
		place $m -x $x -y 0
	}
}


proc UpdateSettingsText {w} {
	variable Vars

	lassign [::tk::UnderlineAmpersand $mc::MainMenu] text ul
	$w configure -text " $text" -underline [incr ul]
}


proc ChooseLanguage {parent} {
	variable ::country::icon::flag

	if {!$::scidb::dir::setup} { return }
	wm protocol $parent WM_DELETE_WINDOW {#}
	set dlg $parent.lang
	tk::toplevel $dlg -class Scidb
	wm withdraw $dlg
	set top [tk::frame $dlg.top -border 2 -relief raised]
	pack $top
	set r 0
	foreach lang [lsort [array names ::mc::input]] {
		if {[string length $lang]} {
			set icon ""
			catch { set icon $flag([set ::mc::langToCountry([set ::mc::lang$lang])]) }
			if {[string length $icon] == 0} { set icon none }
			set code [set ::mc::lang$lang]
			ttk::button $top.$code \
				-style aligned.TButton \
				-text " $lang" \
				-image $icon \
				-compound left \
				-command [namespace code [list SetupLang $code]] \
				;
			grid $top.$code -column 1 -row [incr r 1]
			bind $top.$code <Return>	{ event generate %W <Key-space>; break }
			bind $top.$code <Down>		{ focus [tk_focusNext [focus]] }
			bind $top.$code <Up>			{ focus [tk_focusPrev [focus]] }
		}
	}
	wm resizable $dlg no no
	wm title $dlg [lindex [::tk::UnderlineAmpersand $::menu::mc::Language] 0]
	wm transient $dlg $parent
	::util::place $dlg -parent $parent -position center
	update idletasks
	::scidb::tk::wm frameless $dlg
	wm deiconify $dlg
	focus $top.en
	::ttk::grabWindow $dlg
	vwait ::mc::langID
	::ttk::releaseGrab $dlg
	catch { destroy $dlg }
	::mc::setLang $::mc::langID
	wm protocol $parent WM_DELETE_WINDOW [namespace code shutdown]
	focus -force .application
}


proc SetupLang {langID} {
	pgn::setActiveLang $::mc::langID 0
	set ::mc::langID $langID
	::font::useLanguage $langID
	pgn::setActiveLang $langID 1
}


proc Title {} {
	return "$::scidb::app - $mc::ChessInfoDatabase"
}


proc Exit {w} {
	if {$w eq ".application"} {
		::board3d::WebGLStopServer
		set ::remote::blocking 1
		set ::remote::postponed 0
		exit
	}
}


proc Startup {main args} {
	variable Vars

	if {$Vars(ready)} { return }

	lassign $args width height
	set app .application
	set nb $app.nb

	information::build $Vars(frame:information) $width $height
	database::build $Vars(frame:database) $width $height

	$nb add $Vars(frame:information) -sticky nsew
	$nb add $Vars(frame:database) -sticky nsew
	$nb add $main -sticky nsew

	::widget::notebookTextvarHook $nb $Vars(frame:information) [namespace current]::mc::Tab(information)
	::widget::notebookTextvarHook $nb $Vars(frame:database) [namespace current]::mc::Tab(database)
	::widget::notebookTextvarHook $nb $main [namespace current]::mc::Tab(board)

	foreach tab {information database board} {
		bind $Vars(frame:$tab) <FocusIn>  [namespace code [list ${tab}::setActive yes]]
		bind $Vars(frame:$tab) <FocusOut> [namespace code [list ${tab}::setActive no]]
	}

	foreach pane {information database} {
		set frame $Vars(frame:$pane)
		bind $frame <Map> [list [namespace current]::${pane}::activate $frame 1]
		bind $frame <Unmap> [list [namespace current]::${pane}::activate $frame 0]
	}

	# Switching notebook tabs maps/unmaps only the notebook page ($main), not
	# the board pane inside it, so forward those events to the board pane.
	set frame $Vars(frame:board)
	bind $main <Map> +[list [namespace current]::board::activate $frame 1]
	bind $main <Unmap> +[list [namespace current]::board::activate $frame 0]

	RestoreWindowGeometry $app
	bind $app <Configure> +[namespace code {RememberWindowGeometry %W}]
	bind $app <Configure> +[namespace code {WindowResized %W}]
	database::finish $app
	::splash::close
	set Vars(ready) 1

	# we need a small timeout for HTML widget (tab "Information");
	# for any reason "update idletasks" is not sufficient
	after 1 [namespace code Startup2]
}


proc Startup2 {} {
	set app .application
	set nb $app.nb

	ChooseLanguage $app
	::load::writeLog
	update idletasks
	set ::scidb::intern::blocked 0

	database::preOpen $app

	foreach file [::process::arguments] {
		set path [::util::databasePath $file]
		if {![::scidb::db::get open? $path]} {
			database::openBase .application $path yes -encoding $::encoding::autoEncoding
		}
	}
 
	if {[::game::recover $app] + [::game::reopenLockedGames $app] > 0} {
		set tab board
	} elseif {[::process::testOption show-board]} {
		set tab board
	} elseif {[::process::testOption re-open] || [llength [::process::arguments]]} {
		set tab database
	} else {
		set tab information
	}
	$nb select .application.nb.$tab

	after idle [namespace code [list switchTab $tab]]
	after idle { ::tips::show .application }
	#after idle [list ::beta::welcomeToScidb $app]
	#::util::photos::checkForUpdate [namespace current]::InformAboutUpdates
	reflow::Startup
}


proc FontSizeChanged {w value} {
	variable Vars

	if {$w eq ".application"} {
		$Vars(board:twm) headerfontsize [::html::incrFontSize [$Vars(board:twm) headerfontsize] $value]
	}
}


wm iconphoto .application -default $::icon::64x64::logo $::icon::16x16::logo


namespace eval icon {
namespace eval 16x12 {

set downArrow(white) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAMCAYAAABr5z2BAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
	ZXIgSWNvbnMgdjMuMzEuMDogaHR0cHM6Ly9jb2RlbG9hZC5naXRodWIuY29tL3RhYmxlci90YWJs
	ZXItaWNvbnMvdGFyLmd6L3JlZnMvdGFncy92My4zMS4wClNIQTI1NjogNmNhZTU3YzFjMTdmNjIz
	MjY3OTQ1ZmM0ODFjODExYzNkODg3ZjMzYTU1MWE2MmI2ZjBlYTdhNDFiNWEzZWYxZgoKTUlUIExp
	Y2Vuc2UKCkNvcHlyaWdodCAoYykgMjAyMC0yMDI0IFBhd2XFgiBLdW5hCgpQZXJtaXNzaW9uIGlz
	IGhlcmVieSBncmFudGVkLCBmcmVlIG9mIGNoYXJnZSwgdG8gYW55IHBlcnNvbiBvYnRhaW5pbmcg
	YSBjb3B5Cm9mIHRoaXMgc29mdHdhcmUgYW5kIGFzc29jaWF0ZWQgZG9jdW1lbnRhdGlvbiBmaWxl
	cyAodGhlICJTb2Z0d2FyZSIpLCB0byBkZWFsCmluIHRoZSBTb2Z0d2FyZSB3aXRob3V0IHJlc3Ry
	aWN0aW9uLCBpbmNsdWRpbmcgd2l0aG91dCBsaW1pdGF0aW9uIHRoZSByaWdodHMKdG8gdXNlLCBj
	b3B5LCBtb2RpZnksIG1lcmdlLCBwdWJsaXNoLCBkaXN0cmlidXRlLCBzdWJsaWNlbnNlLCBhbmQv
	b3Igc2VsbApjb3BpZXMgb2YgdGhlIFNvZnR3YXJlLCBhbmQgdG8gcGVybWl0IHBlcnNvbnMgdG8g
	d2hvbSB0aGUgU29mdHdhcmUgaXMKZnVybmlzaGVkIHRvIGRvIHNvLCBzdWJqZWN0IHRvIHRoZSBm
	b2xsb3dpbmcgY29uZGl0aW9uczoKClRoZSBhYm92ZSBjb3B5cmlnaHQgbm90aWNlIGFuZCB0aGlz
	IHBlcm1pc3Npb24gbm90aWNlIHNoYWxsIGJlIGluY2x1ZGVkIGluIGFsbApjb3BpZXMgb3Igc3Vi
	c3RhbnRpYWwgcG9ydGlvbnMgb2YgdGhlIFNvZnR3YXJlLgoKVEhFIFNPRlRXQVJFIElTIFBST1ZJ
	REVEICJBUyBJUyIsIFdJVEhPVVQgV0FSUkFOVFkgT0YgQU5ZIEtJTkQsIEVYUFJFU1MgT1IKSU1Q
	TElFRCwgSU5DTFVESU5HIEJVVCBOT1QgTElNSVRFRCBUTyBUSEUgV0FSUkFOVElFUyBPRiBNRVJD
	SEFOVEFCSUxJVFksCkZJVE5FU1MgRk9SIEEgUEFSVElDVUxBUiBQVVJQT1NFIEFORCBOT05JTkZS
	SU5HRU1FTlQuIElOIE5PIEVWRU5UIFNIQUxMIFRIRQpBVVRIT1JTIE9SIENPUFlSSUdIVCBIT0xE
	RVJTIEJFIExJQUJMRSBGT1IgQU5ZIENMQUlNLCBEQU1BR0VTIE9SIE9USEVSCkxJQUJJTElUWSwg
	V0hFVEhFUiBJTiBBTiBBQ1RJT04gT0YgQ09OVFJBQ1QsIFRPUlQgT1IgT1RIRVJXSVNFLCBBUklT
	SU5HIEZST00sCk9VVCBPRiBPUiBJTiBDT05ORUNUSU9OIFdJVEggVEhFIFNPRlRXQVJFIE9SIFRI
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABIUlEQVR4nKVS
	X0vCcBQ9d0wcCpOivYSU5WJBn6D14YYfaVArpDkyJRU/gX+YNIeLMvAlmMZuD5swWLOiA7+He889
	v3vv4QL/BGVThgAjp7oBAI3orz/u5CgTceWkcHC0v8FnhNUHAwAqJSpAFDZvz++glQvOTG0IBKAo
	V1XTstujieuPp7O55wdLzw+W4+lsPpq4vmnZ7aJcVSnRAICY7h6G66hcLkln9dohACxeXl0GoJ4e
	1wCQ5wd+GK4j+n5PJiJA3Du/bDrdPjOzedu6MS37mpn5/uFpICmaHos5z6qYEBVNbz32h5zA6QyG
	knJxla7JhZH4ISmafmd3ek2n29uKjWTvH8G87SLX45fO/RqxJ0QAdojFPAIgZk5GJsq9vi+WFH+j
	Vx1XjAAAAABJRU5ErkJggg==
}]

set downArrow(black) [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAABAAAAAMCAYAAABr5z2BAAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
	ZXIgSWNvbnMgdjMuMzEuMDogaHR0cHM6Ly9jb2RlbG9hZC5naXRodWIuY29tL3RhYmxlci90YWJs
	ZXItaWNvbnMvdGFyLmd6L3JlZnMvdGFncy92My4zMS4wClNIQTI1NjogNmNhZTU3YzFjMTdmNjIz
	MjY3OTQ1ZmM0ODFjODExYzNkODg3ZjMzYTU1MWE2MmI2ZjBlYTdhNDFiNWEzZWYxZgoKTUlUIExp
	Y2Vuc2UKCkNvcHlyaWdodCAoYykgMjAyMC0yMDI0IFBhd2XFgiBLdW5hCgpQZXJtaXNzaW9uIGlz
	IGhlcmVieSBncmFudGVkLCBmcmVlIG9mIGNoYXJnZSwgdG8gYW55IHBlcnNvbiBvYnRhaW5pbmcg
	YSBjb3B5Cm9mIHRoaXMgc29mdHdhcmUgYW5kIGFzc29jaWF0ZWQgZG9jdW1lbnRhdGlvbiBmaWxl
	cyAodGhlICJTb2Z0d2FyZSIpLCB0byBkZWFsCmluIHRoZSBTb2Z0d2FyZSB3aXRob3V0IHJlc3Ry
	aWN0aW9uLCBpbmNsdWRpbmcgd2l0aG91dCBsaW1pdGF0aW9uIHRoZSByaWdodHMKdG8gdXNlLCBj
	b3B5LCBtb2RpZnksIG1lcmdlLCBwdWJsaXNoLCBkaXN0cmlidXRlLCBzdWJsaWNlbnNlLCBhbmQv
	b3Igc2VsbApjb3BpZXMgb2YgdGhlIFNvZnR3YXJlLCBhbmQgdG8gcGVybWl0IHBlcnNvbnMgdG8g
	d2hvbSB0aGUgU29mdHdhcmUgaXMKZnVybmlzaGVkIHRvIGRvIHNvLCBzdWJqZWN0IHRvIHRoZSBm
	b2xsb3dpbmcgY29uZGl0aW9uczoKClRoZSBhYm92ZSBjb3B5cmlnaHQgbm90aWNlIGFuZCB0aGlz
	IHBlcm1pc3Npb24gbm90aWNlIHNoYWxsIGJlIGluY2x1ZGVkIGluIGFsbApjb3BpZXMgb3Igc3Vi
	c3RhbnRpYWwgcG9ydGlvbnMgb2YgdGhlIFNvZnR3YXJlLgoKVEhFIFNPRlRXQVJFIElTIFBST1ZJ
	REVEICJBUyBJUyIsIFdJVEhPVVQgV0FSUkFOVFkgT0YgQU5ZIEtJTkQsIEVYUFJFU1MgT1IKSU1Q
	TElFRCwgSU5DTFVESU5HIEJVVCBOT1QgTElNSVRFRCBUTyBUSEUgV0FSUkFOVElFUyBPRiBNRVJD
	SEFOVEFCSUxJVFksCkZJVE5FU1MgRk9SIEEgUEFSVElDVUxBUiBQVVJQT1NFIEFORCBOT05JTkZS
	SU5HRU1FTlQuIElOIE5PIEVWRU5UIFNIQUxMIFRIRQpBVVRIT1JTIE9SIENPUFlSSUdIVCBIT0xE
	RVJTIEJFIExJQUJMRSBGT1IgQU5ZIENMQUlNLCBEQU1BR0VTIE9SIE9USEVSCkxJQUJJTElUWSwg
	V0hFVEhFUiBJTiBBTiBBQ1RJT04gT0YgQ09OVFJBQ1QsIFRPUlQgT1IgT1RIRVJXSVNFLCBBUklT
	SU5HIEZST00sCk9VVCBPRiBPUiBJTiBDT05ORUNUSU9OIFdJVEggVEhFIFNPRlRXQVJFIE9SIFRI
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAABG0lEQVR4nKWS
	P0vDUBTFz4npnzi6iNKhJYJFHAqCFF2cHYqfwQ/gHzKKRHCRCOLo5MdwcFYXOwgKpViNCOLmIiFq
	8R2XKGkpRuxbHrx7zj0/7rvAkIf9D5KsXw2kGTY0k6ACYAyAAaCUzgLwQjJM6+3EZJE0kqZ294+O
	r27abi43ovjt3QEAp1iIu91P1man7yStkux8e+w+APMaRcXrVmdy1MmjNDEegkD7NixH8Qfdcukp
	IeslSNJJ8l7SOojDk9Oz+bnaTIsW9fD4XFlZXroMdryNRMOBw5TE5F7wtoJmtd5Qtd6Qtx00JS2m
	NT0EPxMl5fu+RfJC0lq+YB8YA+z5mx7J86SW/Y0pEleSOyj5z03+ZU4ZrazN/AIdEoxM0u18/AAA
	AABJRU5ErkJggg==
}]

# Aqua draws the main menu button as a native pop-up button with its own
# arrow; ours would be drawn over the label.
if {[tk windowingsystem] eq "aqua"} {
	foreach color {white black} { $downArrow($color) blank; $downArrow($color) configure -width 1 -height 1 }
}

} ;# namespace 16x12
namespace eval 32x32 {

set shutdown [image create photo -data {
	iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAYAAABzenr0AAAE5mlUWHRMaWNlbnNlAAAAAABUYWJs
	ZXIgSWNvbnMgdjMuMzEuMDogaHR0cHM6Ly9jb2RlbG9hZC5naXRodWIuY29tL3RhYmxlci90YWJs
	ZXItaWNvbnMvdGFyLmd6L3JlZnMvdGFncy92My4zMS4wClNIQTI1NjogNmNhZTU3YzFjMTdmNjIz
	MjY3OTQ1ZmM0ODFjODExYzNkODg3ZjMzYTU1MWE2MmI2ZjBlYTdhNDFiNWEzZWYxZgoKTUlUIExp
	Y2Vuc2UKCkNvcHlyaWdodCAoYykgMjAyMC0yMDI0IFBhd2XFgiBLdW5hCgpQZXJtaXNzaW9uIGlz
	IGhlcmVieSBncmFudGVkLCBmcmVlIG9mIGNoYXJnZSwgdG8gYW55IHBlcnNvbiBvYnRhaW5pbmcg
	YSBjb3B5Cm9mIHRoaXMgc29mdHdhcmUgYW5kIGFzc29jaWF0ZWQgZG9jdW1lbnRhdGlvbiBmaWxl
	cyAodGhlICJTb2Z0d2FyZSIpLCB0byBkZWFsCmluIHRoZSBTb2Z0d2FyZSB3aXRob3V0IHJlc3Ry
	aWN0aW9uLCBpbmNsdWRpbmcgd2l0aG91dCBsaW1pdGF0aW9uIHRoZSByaWdodHMKdG8gdXNlLCBj
	b3B5LCBtb2RpZnksIG1lcmdlLCBwdWJsaXNoLCBkaXN0cmlidXRlLCBzdWJsaWNlbnNlLCBhbmQv
	b3Igc2VsbApjb3BpZXMgb2YgdGhlIFNvZnR3YXJlLCBhbmQgdG8gcGVybWl0IHBlcnNvbnMgdG8g
	d2hvbSB0aGUgU29mdHdhcmUgaXMKZnVybmlzaGVkIHRvIGRvIHNvLCBzdWJqZWN0IHRvIHRoZSBm
	b2xsb3dpbmcgY29uZGl0aW9uczoKClRoZSBhYm92ZSBjb3B5cmlnaHQgbm90aWNlIGFuZCB0aGlz
	IHBlcm1pc3Npb24gbm90aWNlIHNoYWxsIGJlIGluY2x1ZGVkIGluIGFsbApjb3BpZXMgb3Igc3Vi
	c3RhbnRpYWwgcG9ydGlvbnMgb2YgdGhlIFNvZnR3YXJlLgoKVEhFIFNPRlRXQVJFIElTIFBST1ZJ
	REVEICJBUyBJUyIsIFdJVEhPVVQgV0FSUkFOVFkgT0YgQU5ZIEtJTkQsIEVYUFJFU1MgT1IKSU1Q
	TElFRCwgSU5DTFVESU5HIEJVVCBOT1QgTElNSVRFRCBUTyBUSEUgV0FSUkFOVElFUyBPRiBNRVJD
	SEFOVEFCSUxJVFksCkZJVE5FU1MgRk9SIEEgUEFSVElDVUxBUiBQVVJQT1NFIEFORCBOT05JTkZS
	SU5HRU1FTlQuIElOIE5PIEVWRU5UIFNIQUxMIFRIRQpBVVRIT1JTIE9SIENPUFlSSUdIVCBIT0xE
	RVJTIEJFIExJQUJMRSBGT1IgQU5ZIENMQUlNLCBEQU1BR0VTIE9SIE9USEVSCkxJQUJJTElUWSwg
	V0hFVEhFUiBJTiBBTiBBQ1RJT04gT0YgQ09OVFJBQ1QsIFRPUlQgT1IgT1RIRVJXSVNFLCBBUklT
	SU5HIEZST00sCk9VVCBPRiBPUiBJTiBDT05ORUNUSU9OIFdJVEggVEhFIFNPRlRXQVJFIE9SIFRI
	RSBVU0UgT1IgT1RIRVIgREVBTElOR1MgSU4gVEhFClNPRlRXQVJFLgp7oPpaAAAE+ElEQVR4nMVX
	a2xURRT+zty5exehgVKIFEubFlKpEQjFR4lEQQn8gRifMSBBXpEESGqCJkJJd4PEaFEBg6aEghRL
	DMVHBASRACbIQ9NgA/KotthCwytAC23ZuzP3Hn94t17LLt2lP3qSTWZn5pzznbnfOXMG6GWhrhPM
	TPHmuzVE5PYYjef8foXuR79TgZmJiJiZTQAPayATWndrUEoZBdAghGhi5k47yQKQXZznfL/n0Fvf
	7No37UbLrXRmFvfUZkBKQ+fmZJ3/u6m5Ijsrs5KIIqmAkD7nA6qqd4bXbtg2u73jDlw3uSCIgLr6
	pkF/1jeOXPdBCaQ0ypECh6S3mTtse9LW7btf6eiI8KD0/u2FowtOm6ZULjOJONG4zCQNw7ly7UbG
	H2f/ym9obE77tLxygVL6ByK6wMwiGWJKImLDENh/8OiYlpbWB0xT4tUXpn69aN6MdwFob1+84xAA
	XAB5cxaXbD5ec7KgofFiLoDhAC6kcgIwhIAdiVguM0xpYOiQzCYiupSMAWbWDw4eeJ0BclxXaK0D
	3lJnOjMzEnGik2T+DUpFJTNTaWmpYGZK8BNe2pmu1oKI2LPBnj3HG7PHsbi8kPEmiYitgMlRpREO
	h+Mij0XFzOwChm1HSWllSikNbz3zWM3JGQLAE+NGbSWiq/F4ERdAsuJFdXvihCePnmu4UFBUOKoW
	QAMR4bcTp2YuW/lJWdRWXLxwVj4zlxDRta4gkgbgpWvnf9/YZuZV06Y+swdAExHVMUBHbMXRqMLN
	1lu0ev0X85ldYublHgjD+0TJA4hxxAqYYGb/AoSg68z4CQAsKwDLddkuGrt5xdKFw1auLp/f1tbe
	d/X6LfOEIeGdxNVY/ekWgK9QDfn91JnXzpw7P0RKw/HXGgIRgwURmBkugenL7bucEXnZHROfeuzI
	3v2Hn4tGFX24rmJBWt/gCGZeRERnmFl0CyAUCpEQgo/V1M5ctnJtWeutNjLEvSu0d2LQjgMCGASS
	0kAkEnHfX7Np0uBBGctN03wdQDe1vofiZUqMOwzQXRUtmRPgcDiMonFjqj5+720n2U/QHrmjHskf
	kX74aM2Uqh278x3HoWCfIC0rnntw7OiCVUopAKBuAcTIR0SXAayJR0KlFGJTlhUAuy7sqBq478Av
	4W93H8hWWlPQstx3lsytmPLsBD8J3ZTT0I6qOEucAaAQ/6bhOQboyK8n5oTLPl/c0nobaf36uksX
	vbHxpemTS3qchn5A3tDa9ePPy8srd8wtKhxVy8wLhBB1x02TgpaF9AHExW/O2vjy81P8hciJ2elR
	JfTSM+3Q4ePjT5+t7691tBBAHjPXPT720apVK4rZV4rvqoIJATAz2VFFoVCIQqFQQv8eF0gAjmUF
	2JSm0lo7HrhLAD7y24zXH0j/htjYNAM6drOFw+FEANjTU0JKN3ZLaq2FN2/EHN7rOpYA4LgurGDQ
	FkSwlUbzpcs5zDwUgPI76yKdDcmVazcyCGBDCDcYDNo+nVgGJQriv55w8tPjaz/b9FXHxeYrfaq/
	2/tifUPjyFRaMiKi3Jys8wDqE3qLI+Sr9f2rqneuXbdh2+y2FJtSAiEv56Hb68tKlg7PHbZBKZ18
	VxzrVoiolZlLB6T1u1m9c//0my2t6W4KbfmShbMqsrMyK7V2UnqcJH6YaJ3pX08YQQ8fJv+TXn2a
	dQHRO4/T3pB/AHPu+EF+3TRhAAAAAElFTkSuQmCC
}]

} ;# namespace 32x32
} ;# namespace icon
} ;# namespace application

rename ::tk::PostOverPoint ::tk::_PostOverPoint_application

proc ::tk::PostOverPoint {menu x y {entry {}}} {
	variable ::application::Vars

	if {$Vars(menu:main) eq $menu} {
		set rx [winfo rootx .application]
		set mw [winfo reqwidth $menu]
		set x [expr {min($rx + [winfo width .application] - $mw, $x)}]
	}

	::tk::_PostOverPoint_application $menu $x $y $entry
}

# Session presentation of the DEFAULT board layout. No option or layout-file
# writes live here. $t load reuses leaves by uid (verified with a running
# Stockfish and native widget IDs); only the containers are rebuilt.
namespace eval ::application::reflow {
variable WideAspect 1.25
variable TallAspect 1.05 ;# hysteresis: keep the current shape in [1.05,1.25]
variable DebounceMs 140
variable ShortWidth 1100
variable ShortHeight 720
variable S
array set S {mode wide base {} busy 0 saving 0 afterId {} loadCount 0 collapsed {} override {} snapshot {}}

proc boardTwm {} {
 if {![info exists ::application::Vars(board:twm)]} {return {}}
 set t $::application::Vars(board:twm)
 return [expr {[winfo exists $t] ? $t : {}}]
}
proc substTpl {tpl} {
 set map {}; foreach {name value} [array get ::application::PaneOptions] {lappend map %${name}% [list $value]}
 return [string map $map $tpl]
}
# Fingerprint only structure; optional Media may be a sibling or a tab of
# Analysis, as created by openPane. Single-child containers are equivalent.
proc shapeTokens {stream} {
 set out {}
 foreach {type attrs children} $stream {
  if {$type in {root panedwindow multiwindow notebook}} {
   set kids [shapeTokens $children]
   if {[llength $kids] == 1 && $type in {multiwindow notebook}} {lappend out {*}$kids; continue}
   set orient {}; if {$type eq "panedwindow"} {set orient [string index [dict get $attrs -orient] 0]}
   lappend out "${type}${orient}\[[join $kids ,]\]"
  } elseif {$attrs ne "media"} {lappend out $type:$attrs}
 }
 return $out
}
proc shapeOf {layout} {return [lindex [shapeTokens $layout] 0]}
# Fullscreen is window state, not pane layout. A shape captured while the
# window is fullscreen must not replay that stale flag later: stamp the flag
# in force at load time, or leaving fullscreen at a tall aspect re-enters it
# and keeps the screen rectangle as the normal geometry.
proc withFullscreen {layout flag} {
 lassign $layout root attrs children
 set rootAttrs {}
 if {[dict exists $attrs -attrs]} {set rootAttrs [dict get $attrs -attrs]}
 dict set rootAttrs fullscreen $flag
 dict set attrs -attrs $rootAttrs
 return [list $root $attrs $children]
}
proc tallFrom {wide} {
 lassign $wide root attrs outer
 lassign $outer type options rows
 # The default top row is board + notation notebook. Promote its two
 # children into the outer vertical panedwindow, retaining every leaf/attr.
 # The notation shares one horizontal row with the bottom row's panes, so
 # the board keeps most of the height: a tall window gives a tall canvas
 # with room for a bottom media strip (VAL-BRD-002 on the reflowed layout).
 set top [lindex [lrange $rows 0 2] 2]
 set below [lrange $top 3 end]
 set rest [lrange $rows 3 end]
 if {[llength $rest] == 3 && [lindex $rest 0] eq "panedwindow"
  && [string match h* [dict get [lindex $rest 1] -orient]]} {
  set below [concat $below [lindex $rest 2]]
  set rows [concat [lrange $top 0 2] [list panedwindow [lindex $rest 1] $below]]
 } else {
  set rows [concat $top $rest]
 }
 return [list $root $attrs [list $type $options $rows]]
}
# Give the board the height left once the row below is at its minimum,
# capped where the canvas would be clearly taller than wide.
proc tallSashes {t} {
 set board [$t leaf board]
 set node $board
 while {1} {
  set pw [$t parent $node]
  if {$pw eq {} || $pw eq $t} {return}
  if {[$t ispanedwindow $pw]} {break}
  set node $pw
 }
 if {[$pw cget -orient] ne "vertical" || [lindex [$pw panes] 0] ne $node || [llength [$pw panes]] < 2} {return}
 update idletasks
 set below 0
 foreach p [lrange [$pw panes] 1 end] {
  set h [$pw panecget $p -minsize]
  if {![string is integer -strict $h] || $h < 1} {set h [winfo reqheight $p]}
  incr below [expr {$h+[$pw cget -sashwidth]+2*[$pw cget -sashpad]}]
 }
 set y [expr {min([winfo height $pw]-$below, int([winfo width $node]*1.35))}]
 if {$y > [winfo height $node]} {$pw sash place 0 0 $y}
}
proc reflowable? {t} {
 variable S
 if {$t eq {} || $S(busy) || $S(saving) || ![info exists S(wideShape)]} {return 0}
 if {$::application::twm::Options(board:layout:name) ne {}} {return 0}
 if {[llength [$t floats]] || [$t zoomed] ne {}} {return 0}
 if {$::application::Vars(loading) || $::application::Vars(lock:layout)} {return 0}
 # Focus zoom owns its sash snapshot until switched off.
 if {[::application::focuszoom::isEnabled $t]} {return 0}
 set shape [shapeOf [::application::twm::inspectLayout $t]]
 return [expr {$shape eq $S(wideShape) || ($S(mode) eq "tall" && $shape eq $S(tallShape))}]
}
proc restoreCollapsed {} {
 variable S
 foreach {pw node} $S(collapsed) {
  if {[winfo exists $pw] && $node in [$pw panes]} {$pw paneconfigure $node -hide 0}
 }
 set S(collapsed) {}
 if {[info exists S(stretch)]} {
  foreach {pw node stretch} $S(stretch) {
   if {[winfo exists $pw] && $node in [$pw panes]} {$pw paneconfigure $node -stretch $stretch}
  }
  unset S(stretch)
 }
 if {$S(snapshot) ne {}} {
  # The snapshot holds absolute sash coordinates from the size at which the
  # collapse was made. Restoring them after a window resize squeezes the
  # pane that grew (a short default window enlarged while a pane is
  # collapsed), so only restore at the size the snapshot belongs to; the
  # resize has already arranged the panes for the new size.
  if {![info exists S(snapshotSize)]
   || $S(snapshotSize) eq [list [winfo width .application] [winfo height .application]]} {
   ::application::focuszoom::Restore [boardTwm] $S(snapshot)
  }
  set S(snapshot) {}
  unset -nocomplain S(snapshotSize)
 }
}
proc setMode {t target} {
 variable S
 if {$S(busy) || $target eq $S(mode)} {return}
 set S(busy) 1
 set loading $::application::Vars(loading)
 set geometry [wm geometry .application]
 set minimum [wm minsize .application]
 set ::application::Vars(loading) 1
 set rc [catch {
  restoreCollapsed
  if {$target eq "tall"} {
   set S(base) [::application::twm::inspectLayout $t]
   set layout [tallFrom $S(base)]
   set S(tallShape) [shapeOf $layout]
  } else {set layout $S(base)}
  $t load [withFullscreen $layout [::menu::fullscreen?]]
  if {$target eq "tall"} {tallSashes $t}
  incr S(loadCount)
  set S(mode) $target
  array unset S expanded*
  array unset S return*
  update idletasks
  wm minsize .application {*}$minimum
  wm geometry .application $geometry
  update idletasks
  # Back at the size the wide shape was left at: put its sashes back too.
  if {$target eq "wide" && [info exists S(wideSashes)]} {
   lassign $S(wideSashes) w h snapshot
   if {$w == [winfo width .application] && $h == [winfo height .application]} {
    # The load rebuilds the panedwindows under new paths, in the same
    # traversal order; map the old coordinates onto the new widgets.
    set live [::application::focuszoom::Snapshot $t]
    if {[llength $live] == [llength $snapshot]} {
     set mapped {}
     foreach {pw -} $live {- coords} $snapshot {lappend mapped $pw $coords}
     ::application::focuszoom::Restore $t $mapped
    }
   }
   unset S(wideSashes)
  }
  # The board's Configure may land while the twm is frozen by the load,
  # which skips its rebuild; rebuild once so afterRebuild owners (the media
  # inset reserve) re-plan for the reflowed extent.
  ::application::board::rebuildDeferred
 } error options]
 set ::application::Vars(loading) $loading
 set S(busy) 0
 if {$rc} {return -options $options $error}
 updateCollapse
}
proc evaluate {w h} {
 variable S; variable WideAspect; variable TallAspect
 if {$w < 40 || $h < 40 || ![reflowable? [set t [boardTwm]]]} {return}
 set aspect [expr {double($w)/$h}]
 if {$S(mode) eq "wide" && $aspect < $TallAspect} {setMode $t tall}
 if {$S(mode) eq "tall" && $aspect > $WideAspect} {setMode $t wide}
}
proc onConfigure {W w h} {
 variable S; variable DebounceMs
 if {$W ne ".application" || $S(busy)} {return}
 cancelPending
 set S(afterId) [after $DebounceMs [namespace code [list onDebounced $w $h]]]
}
proc onDebounced {w h} {
 variable S; set S(afterId) {}
 if {[set t [boardTwm]] ne {}} {::application::focuszoom::windowResized $t}
 evaluate $w $h
 updateCollapse
 # The last settled wide arrangement, put back when a tall excursion
 # returns to this window size (see setMode).
 if {$S(mode) eq "wide" && [reflowable? [set t [boardTwm]]]} {
  set S(wideSashes) [list [winfo width .application] [winfo height .application] [::application::focuszoom::Snapshot $t]]
 }
}
proc cancelPending {} {
 variable S
 if {$S(afterId) ne {}} {after cancel $S(afterId); set S(afterId) {}}
}
proc shouldCollapse {uid} {
 if {[string match analysis:* $uid]} {
  set n [::application::analysisNumberFromUid $uid]
  return [expr {![::application::analysis::active? $n]}]
 }
 if {$uid eq "media"} {return [expr {![llength [::application::media::MediaRows]]}]}
 return 0
}
# A group is eligible only when ALL its tabs are empty candidates. Hiding
# the Tk panedwindow child keeps both the native twm tree and live widgets.
proc collapseNode {t uid} {
 set leaf [$t leaf $uid]; set node $leaf
 while {1} {
  set pw [$t parent $node]
  if {$pw eq {} || $pw eq $t} {return {}}
  if {[$t ispanedwindow $pw]} {break}
  set node $pw
 }
 foreach other [$t leaves] {
  set p [$t leaf $other]
  if {[::application::focuszoom::Contains $pw $node $p]} {
   if {![shouldCollapse $other]} {return {}}
  }
 }
 return [list $pw $node]
}
proc updateCollapse {} {
 variable S; variable ShortWidth; variable ShortHeight
 set t [boardTwm]
 if {![reflowable? $t] || ![winfo ismapped [$t leaf board]]} {return}
 set short [expr {[winfo width .application] < $ShortWidth || [winfo height .application] < $ShortHeight}]
 if {!$short} {set S(override) {}}
 set desired {}
 set deficit [expr {max($ShortWidth-[winfo width .application], $ShortHeight-[winfo height .application])}]
 # Lowest priority first. Content and an explicit reopen always win.
 if {$short} {
  foreach uid [concat [lsort -dictionary [lsearch -all -inline -glob [$t leaves] analysis:*]] media] {
   if {$uid ni [$t leaves] || $uid in $S(override) || ![shouldCollapse $uid]} {continue}
   set pair [collapseNode $t $uid]
   if {$pair eq {} || [lindex $pair 1] in $desired} {continue}
   # An explicitly reopened tab protects its entire container.
   lassign $pair pw node
   set protected 0
   foreach keep $S(override) {
    if {$keep ni [$t leaves]} {continue}
    set p [$t leaf $keep]
    if {[::application::focuszoom::Contains $pw $node $p]} {set protected 1}
   }
   if {!$protected && $deficit > 0} {
    lappend desired {*}$pair
    incr deficit -[winfo width $node]
   }
  }
 }
 if {$desired eq $S(collapsed)} {
  if {!$short && $desired eq {}} {rememberExpanded $t}
  return
 }
 set S(busy) 1
 restoreCollapsed
 if {$desired ne {}} {
  set S(snapshot) [::application::focuszoom::Snapshot $t]
  set S(snapshotSize) [list [winfo width .application] [winfo height .application]]
  if {![info exists S(returnSnapshot)] && [info exists S(expandedSnapshot)]} {
   set S(returnSnapshot) $S(expandedSnapshot)
   set S(returnSize) $S(expandedSize)
  }
  set S(stretch) {}
  set touched {}
  foreach {pw node} $desired {
   if {$pw ni $touched} {
    lappend touched $pw
    foreach sibling [$pw panes] {
     lappend S(stretch) $pw $sibling [$pw panecget $sibling -stretch]
     $pw paneconfigure $sibling -stretch always
    }
   }
   $pw paneconfigure $node -hide 1
  }
  set S(collapsed) $desired
 }
 update idletasks
 set S(busy) 0
 if {!$short && $desired eq {}} {rememberExpanded $t}
}
proc rememberExpanded {t} {
 variable S
 set size [list [winfo width .application] [winfo height .application]]
 if {[info exists S(returnSnapshot)]} {
  if {$size eq $S(returnSize)} {::application::focuszoom::Restore $t $S(returnSnapshot)}
  unset S(returnSnapshot) S(returnSize)
 }
 set S(expandedSnapshot) [::application::focuszoom::Snapshot $t]
 set S(expandedSize) $size
}
proc explicitOpen {t uid} {
 variable S
 if {$t ne [boardTwm]} {return}
 if {$uid ni $S(override)} {lappend S(override) $uid}
 if {[llength $S(collapsed)]} {
  set S(busy) 1; restoreCollapsed; set S(busy) 0
  updateCollapse
 }
}
proc explicitHide {t pane} {
 variable S
 if {$t ne [boardTwm]} {return}
 catch {set uid [$t uid $pane]; set i [lsearch -exact $S(override) $uid]; if {$i >= 0} {set S(override) [lreplace $S(override) $i $i]}}
}
proc onPaneStateChange args {
 variable S
 if {![info exists S(contentAfter)]} {set S(contentAfter) [after 0 [namespace code contentChanged]]}
}
proc contentChanged {} {
 variable S; unset S(contentAfter)
 updateCollapse
}
# SAVE RULE (VAL-PANE-009): block an explicit layout save while automatic
# reflow/collapse is active. The pre-reflow tree lives in S(base); shutdown
# restores it before saveLayouts. Never serialize a presentation by accident.
proc allowSave {t parent} {
 variable S
 if {$t ne [boardTwm] || ($S(mode) ne "tall" && $S(collapsed) eq {})} {return 1}
 ::dialog::info -parent $parent -message "This layout is temporarily adapted to the window. Enlarge the window to restore its saved shape before saving the layout."
 return 0
}
proc RevertForExit {} {
 variable S
 cancelPending
 set t [boardTwm]
 if {$t eq {}} {return}
 set S(busy) 1
 restoreCollapsed
 # A user may have loaded a custom layout while adapted. Never overwrite it.
 if {$S(mode) eq "tall" && [shapeOf [::application::twm::inspectLayout $t]] eq $S(tallShape)} {
  set loading $::application::Vars(loading); set ::application::Vars(loading) 1
  $t load $S(base)
  set ::application::Vars(loading) $loading
 }
 set S(mode) wide; set S(base) {}; set S(busy) 0
}
# Test and inspection helpers.
proc mode {} {variable S; return $S(mode)}
proc wideShape {} {variable S; return $S(wideShape)}
proc tallShape {} {variable S; return $S(tallShape)}
proc liveShape {} {return [shapeOf [::application::twm::inspectLayout [boardTwm]]]}
proc loadCount {} {variable S; return $S(loadCount)}
proc resetLoadCount {} {variable S; set S(loadCount) 0}
proc wideAspect {} {variable WideAspect; return $WideAspect}
proc tallAspect {} {variable TallAspect; return $TallAspect}
proc reset {} {
 variable S
 cancelPending
 set S(busy) 1; restoreCollapsed
 set t [boardTwm]
 if {$t ne {}} {
  ::application::focuszoom::disable $t
  set ::application::Vars(loading) 1
  $t load [substTpl $::application::BoardLayout]
  set ::application::Vars(loading) 0
 }
 array unset S expanded*
 array unset S return*
 array unset S wideSashes
 array unset S snapshotSize
 array set S {mode wide base {} busy 0 loadCount 0 collapsed {} override {} snapshot {}}
 update idletasks
}
proc Startup {} {
 variable S
 set S(wideShape) [shapeOf $::application::BoardLayout]
 set S(tallShape) [shapeOf [tallFrom $::application::BoardLayout]]
 bind .application <Configure> +[namespace code {onConfigure %W %w %h}]
 foreach v {::application::MapTerminalToAnalysis ::application::MapAnalysisToTerminal} {
  trace add variable $v write [namespace code onPaneStateChange]
 }
 onConfigure .application [winfo width .application] [winfo height .application]
}

# Tk 8.6 sends no notification when `tk scaling` changes at runtime, and
# existing fonts and widgets keep their old pixel sizes (Tk 8.6.17), so
# without this hook nothing re-lays out until a restart. Intercept the
# setter and drive the relayout through ::application::scalingChanged,
# deferred to idle so bursts of changes settle in one pass. Only the
# plain two-word form the app uses itself (see exec.tcl) is intercepted;
# queries and the -displayof forms pass through unchanged.
#
# On Tk 8.6 the setter returns the empty string and stores the factor
# quantised to whole millimetres of screen width, so the effective value
# (re-derived by the query form) must be re-read after setting.
if {[info commands ::__application_tk_orig] eq ""} {
	rename ::tk ::__application_tk_orig

	proc ::tk {args} {
		if {[llength $args] == 2 && [lindex $args 0] eq "scaling"} {
			set old [::__application_tk_orig scaling]
			set result [::__application_tk_orig scaling [lindex $args 1]]
			set new [::__application_tk_orig scaling]
			if {	[info exists ::application::Vars]
				&& $::application::Vars(ready)
				&& $new != $old
			} {
				after idle ::application::scalingChanged
			}
			return $result
		}
		tailcall ::__application_tk_orig {*}$args
	}
}
}

# vi:set ts=3 sw=3:
