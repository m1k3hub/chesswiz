# ======================================================================
# Per-key shortcut editor.
#
# The two shortcut schemes are installed by
# ::application::ApplyShortcutScheme (the ChessBase scheme, on the
# ChessBaseBoard/ChessBaseEditing tags and the wrapped .application
# keys) and by ::menu::setup, ::searchentry::bindShortcuts and
# ::application::board::bind/bindKeys (the Chesswiz scheme, on
# .application and the board widgets). This module adds user overrides
# on top of the active scheme:
#
#   - a table of actions with their current key in the Shortcut
#     Preferences dialog; the user selects a row, presses the new key
#     combination in a capture field and applies it,
#   - conflicts are reported ("Ctrl+F is already used by Flip board")
#     and must be resolved before the override is stored,
#   - "Reset to scheme" per row and for all rows,
#   - overrides persist in the Options array (::options::hookWriter)
#     and are applied after the scheme (ApplyShortcutScheme), through
#     the same bind tags (the board widgets' FilterKey wrapper, the
#     ChessBaseBoard tag, .application), so the focus rules
#     (ShortcutBoardCommand, ShortcutEditingFocus, editable widgets)
#     keep working,
#   - an override is bound in every scheme: the schemes decide only the
#     DEFAULT keys. In particular an override of a ChessBase-only action
#     (board flip, the NAG keys) is installed on the ChessBaseBoard tag
#     even while the Chesswiz scheme is active; that tag is added to the
#     board widgets when such an override exists, and the scheme's
#     defaults are cleared there, so it carries only user overrides.
#   - both letter cases are bound, so Ctrl+Q keeps working with
#     Caps Lock.
#
# An override is stored as Options(shortcut:keys,<action>) = <key spec
# without the angle brackets>, e.g. "Control-g".
#
# Each action carries the key of BOTH schemes, because an override
# persists across scheme switches:
#   keySpec   the key the Chesswiz scheme binds ("" when it has none)
#   cbSpec    the key the ChessBase scheme binds ("" when it has none)
# When an override moves an action away from its scheme key, the
# scheme binding for the old key is removed on the same tag ("swallowed"),
# so exactly one key runs the action.
#
#   ::application::keyEditor::ApplyOverrides   from ApplyShortcutScheme
#   ::application::keyEditor::SetKey           checks and stores
#   ::application::keyEditor::Conflict         conflict messages
#
# The pure helpers (key spec <-> display, conflict detection, the
# override store) are covered by tests/test_app_key_editor.tcl.
# ======================================================================

::util::source app-key-editor

namespace eval application {
namespace eval keyEditor {
namespace eval mc {

set KeyAction				"Action"
set KeyCurrent				"Current Key"
set KeyNew					"Press new key..."
set KeyCapture				"Press the new key combination now."
set KeyApply				"&Apply"
set KeyResetRow			"Reset to &scheme"
set KeyResetAll			"Reset &all to scheme"
set KeyConflict			"%s is already used by %s"
set KeyConflictOther	"%s is already used by another binding"
set KeyAskPrecedence	"Ctrl+K focuses the Ask field (Ctrl+Shift+K always does); inside the comment editor, the PGN text and the engine console Ctrl+K keeps kill-line, and Ctrl+Shift+U inserts the king"
set KeyCaptured			"New key: %s"
set KeyNeedsSelection	"Select an action in the table first."
set KeySameScheme		"This key is already assigned in the active scheme."
set KeyEditorTitle		"Key Bindings"
set KeyColumnAction		"Action"
set KeyColumnKey			"Key"
set KeyNone				"—"
set SaveNewGame			"Save as new game"
set ReplaceGame			"Replace game"
set Find					"&Find"

} ;# namespace mc

# The actions offered in the editor, grouped for the table. Each entry is
# {action label-var tag key-spec cb-spec command}:
#   action      unique id, also the Options index (shortcut:keys,<action>)
#   label-var   mc variable with the action's name, fully qualified
#   tag         bind tag an override is installed on:
#                 app        .application (application-wide actions)
#                 board      the board widgets, through
#                            ::application::board::bind (FilterKey)
#                 chessbase  a ChessBase-only action, bound on the
#                            ChessBaseBoard tag; the tag is added to the
#                            board widgets for an override and carries
#                            only overrides in the Chesswiz scheme
#   key-spec    the key the CHESSWIZ scheme binds the action to,
#               without <...>; "" when the Chesswiz scheme has no key
#   cb-spec     the key the CHESSBASE scheme binds the action to;
#               "" when the ChessBase scheme has no key
#   command     Tcl command the key runs
#
# Navigation, board and annotation keys live on the board widgets
# (tcl/app-board.tcl bind/bindKeys); quit, log, help, fullscreen and find
# live on .application (tcl/menu.tcl setup, tcl/widgets/searchentry.tcl);
# the ChessBase-only actions (board flip, the NAG keys) are listed so
# their names show in a conflict message and their keys can be changed
# for the ChessBase scheme. New game is a normal app action: the menu
# advertises Ctrl+Shift+G, and the deprecated Ctrl+N alias is bound by
# ApplyShortcutScheme without appearing in this table (decision D-4).
variable Actions {
	{nav-back				::browser::mc::GoBackward					board		Left					Left					{::application::board::Goto -1}}
	{nav-forward			::browser::mc::GoForward					board		Right					Right					{::application::board::Goto +1}}
	{nav-fast-back			::browser::mc::GoBackFast					board		Prior					{}						{::application::board::Goto -10}}
	{nav-fast-forward		::browser::mc::GoForwardFast				board		Next					{}						{::application::board::Goto +10}}
	{nav-start				::browser::mc::GotoStartOfGame				board		Home					Home					{::application::board::Goto start}}
	{nav-end				::browser::mc::GotoEndOfGame				board		End					End					{::application::board::Goto end}}
	{nav-enter-var			::application::board::mc::GoIntoNextVar	board		Down					{}						{::application::board::Goto down}}
	{nav-leave-var			::application::board::mc::GoIntPrevVar		board		Up						m						{::application::board::Goto up}}
	{board-flip				::overview::mc::RotateBoard					chessbase	{}						Control-f			{::application::board::Rotate $::application::board::Vars(widget:frame)}}
	{board-null-move		::application::board::mc::InsertNullMove	board		Control-0				Control-Alt-0		{::application::board::InsertNullMove}}
	{game-new				::gamebar::mc::GameNew						app		Control-Shift-G			{}						{::menu::gameNew .application}}
	{game-save				mc::SaveNewGame							board		Control-s				Control-s			{::application::board::SaveGame add}}
	{game-replace			mc::ReplaceGame							board		Control-r				Control-r			{::application::board::SaveGame replace}}
	{game-next				::browser::mc::LoadNextGame				board		Control-Down			F10					{::application::board::LoadGame(any) .application next}}
	{game-prev				::browser::mc::LoadPrevGame				board		Control-Up				Control-F10			{::application::board::LoadGame(any) .application prev}}
	{game-first				::browser::mc::GotoGame(first)				board		Control-Home			{}						{::application::board::LoadGame(any) .application first}}
	{game-last				::browser::mc::GotoGame(last)				board		Control-End				{}						{::application::board::LoadGame(any) .application last}}
	{annot-comment-after	::application::pgn::mc::EditCommentAfter	board		Control-c				Control-a			{::application::pgn::editComment after}}
	{annot-comment-before	::application::pgn::mc::EditCommentBefore	board		Control-Shift-c		Control-Shift-A		{::application::pgn::editComment before}}
	{annot-palette			::application::pgn::mc::EditAnnotation	board		Control-a				{}						{::application::pgn::editAnnotation}}
	{annot-marks			::marks::mc::MarksPalette					board		Control-m				{}						{::application::pgn::openMarksPalette}}
	{annot-good-move		::annotation::mc::Nag(1)					chessbase	{}						exclam				{::annotation::addNag infix 1}}
	{annot-bad-move			::annotation::mc::Nag(2)					chessbase	{}						question				{::annotation::addNag infix 2}}
	{app-quit				::menu::mc::Quit							app		Control-q				Control-q			{::application::shutdown}}
	{app-find				mc::Find										app		Control-f				Control-f			{::application::keyEditor::Find %W}}
	{app-help				::help::mc::Help							app		F1						F1					{::help::open .application}}
	{app-log					::menu::mc::ShowLog						app		Control-l				Control-l			{::log::show -force}}
	{app-fullscreen		::menu::mc::Fullscreen					app		F11					F11					{::menu::viewFullscreen toggle}}
}

# Bind tags considered by the bind-based conflict net, in bindtag order.
variable ConflictTags {ChessBaseBoard ChessBaseEditing .application all}

# The keys ApplyShortcutScheme re-binds on .application while the
# ChessBase scheme is active (the n/o/f/x loop there); the scheme
# restores them itself, so a reset must not re-bind them.
variable WrappedAppKeys {Control-n Control-o Control-f Control-x}

variable Dialog

array set Options {}
array set Dialog {}

} ;# namespace keyEditor
} ;# namespace application


# -------------------------------------------------------------------------
# Pure helpers (unit-tested without a running application)
# -------------------------------------------------------------------------

# Normalize a key spec to the form used in the Options array: the modifiers
# in Tk order (Control, Alt, Shift), the keysym with its case, no angle
# brackets. The case matters: "Control-q" and "Control-Q" are different
# bindings, and both are installed (see BindSpecs).
proc ::application::keyEditor::NormalizeKeySpec {spec} {
	set spec [string trim $spec]
	if {[string match <*> $spec]} { set spec [string range $spec 1 end-1] }
	if {[regexp {^(.*-)([^<>-]+)$} $spec -> modifiers keysym]} {
		set mods {}
		foreach mod [split $modifiers -] {
			if {$mod eq ""} { continue }
			lappend mods [string tolower $mod]
		}
		# Tk's canonical modifier order, canonical capitalization
		set mods [lsort -command ::application::keyEditor::ModifierOrder $mods]
		set pretty {}
		foreach mod $mods { lappend pretty [string totitle $mod] }
		return "[join $pretty -]-$keysym"
	}
	return $spec
}


proc ::application::keyEditor::ModifierOrder {a b} {
	set order {control alt shift meta super hyper mode}
	set ia [lsearch -exact $order $a]
	set ib [lsearch -exact $order $b]
	if {$ia == -1} { set ia 99 }
	if {$ib == -1} { set ib 99 }
	return [expr {$ia - $ib}]
}


# The key specs an override has to bind to work with Caps Lock: the spec
# itself and, for a single letter, the same spec with the other case.
proc ::application::keyEditor::BindSpecs {spec} {
	set spec [NormalizeKeySpec $spec]
	if {[regexp {^(.*-)([a-zA-Z])$} $spec -> modifiers letter]} {
		if {[string is lower $letter]} {
			return [list $spec "$modifiers[string toupper $letter]"]
		}
		return [list $spec "$modifiers[string tolower $letter]"]
	}
	return [list $spec]
}


# A human readable key description, e.g. "Control-Shift-C" -> "Ctrl+Shift+C".
proc ::application::keyEditor::DescribeKey {spec} {
	set spec [NormalizeKeySpec $spec]
	set mods {}
	if {[regexp {^(.*-)([^<>-]+)$} $spec -> modifiers keysym]} {
		foreach mod [split $modifiers -] {
			if {$mod eq ""} { continue }
			switch -- [string tolower $mod] {
				control { lappend mods $::mc::Key(Ctrl) }
				shift	 { lappend mods $::mc::Key(Shift) }
				alt		 { lappend mods $::mc::Key(Alt) }
				default { lappend mods [string totitle $mod] }
			}
		}
	} else {
		set keysym $spec
	}
	if {[info exists ::mc::Key($keysym)]} { set keysym $::mc::Key($keysym) }
	if {[string length $keysym] == 1} { set keysym [string toupper $keysym] }
	if {[llength $mods] == 0} { return $keysym }
	return "[join $mods +]+$keysym"
}


# Is the ChessBase scheme the active one?
proc ::application::keyEditor::SchemeActive? {} {
	return [expr {$::application::Options(shortcut:scheme) eq "chessbase"}]
}


# Is <spec> one of the keys ApplyShortcutScheme re-binds on .application
# while the ChessBase scheme is active?
proc ::application::keyEditor::WrappedAppKey? {spec} {
	variable WrappedAppKeys
	foreach wrapped $WrappedAppKeys {
		if {[SameKey $wrapped $spec]} { return 1 }
	}
	return 0
}


# The key the active scheme binds an action to, ignoring an override
# ("" when the scheme has none).
proc ::application::keyEditor::SchemeKey {action} {
	variable Actions

	foreach entry $Actions {
		lassign $entry a labelVar tag keySpec cbSpec cmd
		if {$a ne $action} { continue }
		if {[SchemeActive?] && $cbSpec ne ""} { return $cbSpec }
		return $keySpec
	}
	return ""
}


# The key currently in effect for an action: the override if there is one,
# else the key of the active scheme ("" when the scheme has none).
proc ::application::keyEditor::CurrentKey {action} {
	variable Options

	if {[info exists Options(shortcut:keys,$action)]} {
		return $Options(shortcut:keys,$action)
	}
	return [SchemeKey $action]
}


# Is <spec> a modifier-only key? (Control, Shift, Caps_Lock...)
proc ::application::keyEditor::ModifierOnly? {spec} {
	set spec [NormalizeKeySpec $spec]
	return [expr {[regexp -nocase {^(control|shift|alt|meta|super|hyper|mode)(_l|_r|_lock)?$} $spec]}]
}


# Do two key specs name the same key? Equal, or the same letter in the
# other case (Caps Lock): "Control-s" matches "Control-S" but not "Control-f".
proc ::application::keyEditor::SameKey {a b} {
	set a [NormalizeKeySpec $a]
	set b [NormalizeKeySpec $b]
	if {[string equal $a $b]} { return 1 }
	if {[regexp {^(.*-)?([a-zA-Z])$} $a -> ma la] && [regexp {^(.*-)?([a-zA-Z])$} $b -> mb lb]} {
		return [expr {$ma eq $mb && [string tolower $la] eq [string tolower $lb]}]
	}
	return 0
}


# The display name of an action: the label variable's value without a
# menu mnemonic ("&") and without the ellipsis of dialog commands.
proc ::application::keyEditor::ActionLabel {action labelVar} {
	if {![info exists ${labelVar}]} { return $action }
	set value [set ${labelVar}]
	set value [string map {& ""} $value]
	set value [string trimright $value .]
	if {$value eq ""} { return $action }
	return $value
}


# The display name of an action looked up by its id.
proc ::application::keyEditor::LabelOf {action} {
	variable Actions
	foreach entry $Actions {
		lassign $entry a labelVar
		if {$a eq $action} { return [ActionLabel $a $labelVar] }
	}
	return $action
}


# Run one of the table's commands from the action registry. The table
# commands are the scheme's own handlers, so a menu/palette/assistant
# invocation of the same id does exactly what the key does. Find is
# special: its table command contains the %W substitution, which only a
# key event provides.
proc ::application::keyEditor::RunAction {action args} {
	variable Actions

	if {$action eq "app-find"} { return [Find [focus]] }
	foreach entry $Actions {
		lassign $entry a labelVar tag keySpec cbSpec cmd
		if {$a eq $action} { return [uplevel #0 $cmd] }
	}
	return -code error "unknown key-editor action $action"
}


# Every id in the key-editor table is a registry id (VAL-REG-003). The
# drop-down carries most of them; the board-only navigation and
# annotation actions are registered here, so menus, the palette and the
# assistant resolve the same ids. Existing registrations keep their
# handler; ::menu::Register refreshes their placement and label.
proc ::application::keyEditor::RegisterActions {} {
	variable Actions

	foreach entry $Actions {
		lassign $entry action labelVar tag keySpec cbSpec cmd
		if {[dict exists $::action::Registry $action]} { continue }
		set label [ActionLabel $action $labelVar]
		::action::register $action [dict create \
			label    $label \
			object   {} \
			args     {} \
			handler  [list ::application::keyEditor::RunAction $action] \
			what     $label \
			ai       0 \
			keys     [list {} {}] \
			menu     {} \
			dropdown {} \
			doc      $label \
		]
	}
}


# Does an override of another action use <spec>?
proc ::application::keyEditor::OwnedByOverride? {spec action} {
	variable Options
	variable Actions

	foreach entry $Actions {
		lassign $entry a labelVar tag keySpec cbSpec cmd
		if {$a eq $action} { continue }
		if {[info exists Options(shortcut:keys,$a)] && [SameKey $Options(shortcut:keys,$a) $spec]} {
			return 1
		}
	}
	return 0
}


# -------------------------------------------------------------------------
# Conflict detection
# -------------------------------------------------------------------------

# Look for a conflict of <spec> with another action's key: first with the
# other overridden actions, then with the scheme keys still in effect
# (of both schemes: an override persists across scheme switches).
# Returns a message ("Ctrl+F is already used by Flip board"), or "".
proc ::application::keyEditor::Conflict {action spec} {
	if {[ModifierOnly? $spec]} { return "" }

	# D-2 / D-7: Ctrl+K belongs to the Ask field, with the kill-line
	# exception inside the multi-line text editors. Report the precedence
	# instead of silently replacing it.
	if {[SameKey $spec Control-k] || [SameKey $spec Control-Shift-K]} {
		return $mc::KeyAskPrecedence
	}

	# other user overrides
	set found [OverrideConflict $action $spec]
	if {$found ne ""} { return $found }

	# the scheme keys of the other table actions
	set found [SchemeAction $spec $action]
	if {$found ne ""} { return $found }

	# keys bound outside the action table, on the scheme's own tags
	foreach spec2 [BindSpecs $spec] {
		set found [SchemeKeyAction $spec2 $action]
		if {$found ne ""} { return $found }
	}
	return ""
}


# Does <spec> collide with another action's override?
proc ::application::keyEditor::OverrideConflict {action spec} {
	variable Options
	variable Actions

	foreach entry $Actions {
		lassign $entry other labelVar tag keySpec cbSpec cmd
		if {$other eq $action} { continue }
		if {![info exists Options(shortcut:keys,$other)]} { continue }
		if {[SameKey $Options(shortcut:keys,$other) $spec]} {
			return [format $mc::KeyConflict [DescribeKey $spec] [ActionLabel $other $labelVar]]
		}
	}
	return ""
}


# Does <spec> collide with a scheme key of another table action? Both
# scheme columns count: the overrides survive a scheme switch, so a key
# free today must not collide after the switch either.
proc ::application::keyEditor::SchemeAction {spec action} {
	variable Options
	variable Actions

	foreach entry $Actions {
		lassign $entry a labelVar tag keySpec cbSpec cmd
		if {$a eq $action} { continue }
		if {[info exists Options(shortcut:keys,$a)]} { continue }
		foreach candidate [list $keySpec $cbSpec] {
			if {$candidate eq ""} { continue }
			if {[SameKey $candidate $spec]} {
				return [format $mc::KeyConflict [DescribeKey $spec] [ActionLabel $a $labelVar]]
			}
		}
	}
	return ""
}


# Is <binding>, a script bound on one of the ConflictTags, the scheme key
# of a table action? Returns "own" when it runs <action> itself (its old
# key, being replaced), another action id when it runs another table
# action, and "" when it belongs to no table action (font size, the
# search field's keys, select-all, ...).
proc ::application::keyEditor::TableActionOf {binding action} {
	variable Actions

	if {[regexp {::application::ShortcutApplicationCommand %W ([a-z]+)$} $binding -> word]} {
		# the ChessBase scheme's wrapped .application keys
		switch -- $word {
			new { set a game-new }
			search { set a app-find }
			default { return "" }
		}
	} else {
		set a ""
		foreach entry $Actions {
			lassign $entry id labelVar tag keySpec cbSpec cmd
			if {$cmd eq ""} { continue }
			if {[string match "*$cmd*" $binding]} { set a $id; break }
		}
	}
	if {$a eq ""} { return "" }
	if {$a eq $action} { return "own" }
	return $a
}


# Does <spec> collide with a key bound outside the action table, on the
# tags the schemes manage themselves? Returns a conflict message or "".
proc ::application::keyEditor::SchemeKeyAction {spec action} {
	variable ConflictTags

	set description [DescribeKey $spec]
	foreach tag $ConflictTags {
		set binding [bind $tag <$spec>]
		if {$binding eq ""} { continue }
		set found [TableActionOf $binding $action]
		if {$found eq "own"} { continue }	;# the action's old key, being replaced
		if {$found ne ""} {
			return [format $mc::KeyConflict $description [LabelOf $found]]
		}
		return [format $mc::KeyConflictOther $description]
	}
	return ""
}


# -------------------------------------------------------------------------
# Applying overrides
# -------------------------------------------------------------------------

# Remove the scheme binding for <spec>, the old key of an action the
# override moves away from it, on the tag <where> (app, board, cb). The
# scheme re-binds its keys on every ApplyShortcutScheme, so this runs
# after every scheme application, not only when the override is set.
# A key another action's override has taken over is left alone.
proc ::application::keyEditor::RemoveSchemeKey {where action spec} {
	variable Options

	if {$spec eq ""} { return }
	if {[SameKey $spec $Options(shortcut:keys,$action)]} { return }
	if {[OwnedByOverride? $spec $action]} { return }
	switch -- $where {
		app { foreach spec [BindSpecs $spec] { bind .application <$spec> {} } }
		board { foreach spec [BindSpecs $spec] { ::application::board::bind <$spec> {} } }
		cb { foreach spec [BindSpecs $spec] { bind ChessBaseBoard <$spec> {} } }
	}
}


# Bind one action's key on its tag, and swallow the scheme bindings for
# the action's old keys. Called by ApplyShortcutScheme after the scheme
# has been installed, and by SetKey when an override changes.
proc ::application::keyEditor::BindAction {action} {
	variable Options
	variable Actions

	foreach entry $Actions {
		lassign $entry a labelVar tag keySpec cbSpec cmd
		if {$a ne $action} { continue }
		if {![info exists Options(shortcut:keys,$action)]} { return }
		set spec $Options(shortcut:keys,$action)

		switch -- $tag {
			app {
				# like the menu bindings and the ChessBase scheme's
				# wrapped keys: plain .application bindings
				foreach s [BindSpecs $spec] {
					bind .application <$s> [list uplevel #0 $cmd]
				}
				RemoveSchemeKey app $action $keySpec
				RemoveSchemeKey app $action $cbSpec
			}
			board {
				# the board bindings run through FilterKey, which hands plain
				# letter keys to the variation selector
				foreach s [BindSpecs $spec] {
					::application::board::bind <$s> $cmd
				}
				RemoveSchemeKey board $action $keySpec
				RemoveSchemeKey cb $action $cbSpec
			}
			chessbase {
				# An override runs in every scheme; the schemes decide only
				# the DEFAULT keys. The ChessBaseBoard tag is added to the
				# board widgets only while the ChessBase scheme is active, so
				# make sure it is present; ApplyShortcutScheme clears the
				# tag in the Chesswiz scheme, where it then carries just the
				# user's overrides. The action's ChessBase-scheme default is
				# swallowed, so exactly one key runs it.
				if {[info exists ::application::board::Vars(need-binding)]} {
					foreach w $::application::board::Vars(need-binding) {
						::application::AddShortcutTag $w
					}
				}
				foreach s [BindSpecs $spec] {
					bind ChessBaseBoard <$s> [list ::application::ShortcutBoardCommand %W %K %s $cmd]
				}
				RemoveSchemeKey cb $action $cbSpec
			}
		}
		return
	}
}


# Remove the bindings an override installed for <action>.
proc ::application::keyEditor::UnbindAction {action} {
	variable Options
	variable Actions

	if {![info exists Options(shortcut:keys,$action)]} { return }
	set spec $Options(shortcut:keys,$action)
	foreach entry $Actions {
		lassign $entry a labelVar tag keySpec cbSpec cmd
		if {$a ne $action} { continue }
		switch -- $tag {
			app {
				foreach s [BindSpecs $spec] { bind .application <$s> {} }
			}
			board {
				# board::bind only adds bindings; removing one takes the
				# widgets themselves
				if {[info exists ::application::board::Vars(need-binding)]} {
					foreach w $::application::board::Vars(need-binding) {
						foreach s [BindSpecs $spec] { bind $w <$s> {} }
					}
				}
			}
			chessbase {
				foreach s [BindSpecs $spec] { bind ChessBaseBoard <$s> {} }
			}
		}
		return
	}
}


# Apply all overrides after the scheme. Called from ApplyShortcutScheme
# (both schemes) and after a language change re-bound the board keys.
proc ::application::keyEditor::ApplyOverrides {args} {
	variable Options
	variable Actions

	if {![winfo exists .application]} { return }
	if {![info exists ::application::board::Vars(need-binding)]} { return }
	foreach entry $Actions {
		lassign $entry action labelVar tag keySpec cbSpec cmd
		if {[info exists Options(shortcut:keys,$action)]} { BindAction $action }
	}
}


# Set (or, with an empty key, remove) the override for <action> after
# checking for conflicts. Returns an error message, or "" on success.
proc ::application::keyEditor::SetKey {action spec} {
	variable Options
	variable Actions

	set found 0
	foreach entry $Actions {
		lassign $entry a labelVar tag keySpec cbSpec cmd
		if {$a eq $action} {
			set found 1
			break
		}
	}
	if {!$found} { return -code error "unknown action $action" }

	set spec [NormalizeKeySpec $spec]
	if {$spec eq ""} {
		ResetAction $action
		return ""
	}
	if {[ModifierOnly? $spec]} {
		return -code error "modifier keys cannot be bound alone"
	}

	# the active scheme's key needs no override; an existing override for
	# another key is dropped, so the scheme key takes over again
	if {[SameKey $spec [SchemeKey $action]]} {
		if {[info exists Options(shortcut:keys,$action)]} { ResetAction $action }
		return ""
	}
	# a key already in effect (the override itself) needs no change
	if {[SameKey $spec [CurrentKey $action]]} { return "" }

	set conflict [Conflict $action $spec]
	# The Ask-field precedence is reported by Conflict so the editor can
	# show it, but an explicit user rebind is still allowed; every other
	# collision is refused.
	if {$conflict ne "" && $conflict ne $mc::KeyAskPrecedence} {
		return -code error $conflict
	}

	# remove the old override binding first, then store and install the
	# new one; the scheme binding for the old key is swallowed by
	# BindAction, so the moved key does not keep running the action
	UnbindAction $action
	set Options(shortcut:keys,$action) $spec
	BindAction $action
	# menu accelerators are read from the binding, so they change with it
	catch { ::menu::RefreshAccelerators }
	return ""
}


# Re-install the scheme binding for one action after its override was
# removed. ApplyShortcutScheme has already re-bound the ChessBaseBoard
# tag and the wrapped .application keys; what is left are the plain
# .application keys and the board widget keys.
proc ::application::keyEditor::RestoreSchemeKey {action labelVar tag keySpec cbSpec cmd} {
	switch -- $tag {
		app {
			if {[SchemeActive?] && [WrappedAppKey? $cbSpec]} { return }
			if {$action eq "app-find"} {
				# the Chesswiz scheme binds the search field's find-next
				set script [list ::searchentry::TriggerFindNext .application focus]
			} elseif {$keySpec eq ""} {
				return
			} else {
				set script [list uplevel #0 $cmd]
			}
			if {![OwnedByOverride? $keySpec $action]} {
				foreach s [BindSpecs $keySpec] { bind .application <$s> $script }
			}
		}
		board {
			if {$keySpec eq ""} { return }
			if {![OwnedByOverride? $keySpec $action]} {
				foreach s [BindSpecs $keySpec] { ::application::board::bind <$s> $cmd }
			}
		}
		chessbase {
			# the scheme binds the ChessBaseBoard keys itself
		}
	}
}


# Remove the override for <action>; the scheme key takes over again.
proc ::application::keyEditor::ResetAction {action} {
	variable Options
	variable Actions

	if {![info exists Options(shortcut:keys,$action)]} { return }
	UnbindAction $action
	unset Options(shortcut:keys,$action)
	::application::ApplyShortcutScheme
	foreach entry $Actions {
		lassign $entry a labelVar tag keySpec cbSpec cmd
		if {$a ne $action} { continue }
		RestoreSchemeKey $a $labelVar $tag $keySpec $cbSpec $cmd
		return
	}
}


# Remove all overrides; the schemes take over completely.
proc ::application::keyEditor::ResetAll {} {
	variable Options
	variable Actions

	foreach entry $Actions {
		lassign $entry action
		UnbindAction $action
	}
	foreach key [array names Options shortcut:keys,*] { unset Options($key) }
	::application::ApplyShortcutScheme
	foreach entry $Actions {
		lassign $entry action labelVar tag keySpec cbSpec cmd
		RestoreSchemeKey $action $labelVar $tag $keySpec $cbSpec $cmd
	}
}


# The command behind the Find key: like the schemes, the database pane
# opens the advanced search, everything else runs the search field's
# find-next; editable widgets keep their own text-editing keys.
proc ::application::keyEditor::Find {w} {
	if {[::application::ShortcutEditable $w]} { return }
	if {[.application.nb select] ne ".application.nb.database"} {
		::searchentry::TriggerFindNext .application focus
		return
	}
	::application::database::OpenAdvancedSearch .application \
		[::scidb::db::get name] \
		[::application::database::currentVariant]
}


# -------------------------------------------------------------------------
# Persistence
# -------------------------------------------------------------------------

proc ::application::keyEditor::WriteOptions {chan} {
	variable Options

	# the Options array holds only the overrides (shortcut:keys,<action>);
	# the scheme itself is in ::application::Options(shortcut:scheme),
	# written by ::application::WriteShortcutOptions
	if {[array size Options] > 0} {
		::options::writeItem $chan [namespace current]::Options
	}
}


::options::hookWriter ::application::keyEditor::WriteOptions


# -------------------------------------------------------------------------
# The editor section of the Shortcut Preferences dialog
# -------------------------------------------------------------------------

# Build (or rebuild) the key table in the Shortcut Preferences dialog.
# Returns the table widget.
proc ::application::keyEditor::BuildTable {top} {
	variable Dialog

	if {[winfo exists $top.keys]} { destroy $top.keys }
	set frame [ttk::frame $top.keys]
	pack $frame -fill both -expand yes -pady 8

	ttk::label $frame.label -text $mc::KeyEditorTitle
	pack $frame.label -anchor w

	set list [ttk::frame $frame.list]
	set tree [ttk::treeview $list.tree -columns {key} -height 10 -selectmode browse]
	$tree heading #0 -text $mc::KeyColumnAction -anchor w
	$tree heading key -text $mc::KeyColumnKey -anchor w
	$tree column #0 -width 220
	$tree column key -width 140 -stretch no
	ttk::scrollbar $list.vs -orient vertical -command [list $tree yview]
	$tree configure -yscrollcommand [list $list.vs set]
	pack $list.vs -side right -fill y
	pack $tree -side left -fill both -expand yes
	pack $list -fill both -expand yes

	# select a row, then press the new key combination in the capture field
	bind $tree <<TreeviewSelect>> [namespace code [list SelectAction $tree]]

	set capture [ttk::frame $frame.capture]
	ttk::label $capture.label -text $mc::KeyNew
	pack $capture.label -side left
	set entry [ttk::entry $capture.entry -state readonly]
	pack $entry -side left -fill x -expand yes -padx [list $::theme::padx 0]
	bind $entry <KeyPress> [namespace code [list CaptureKey $entry %K %s]]
	bind $entry <FocusIn> [namespace code [list CaptureFocus $entry]]
	# A read-only entry does not take the focus from a click on every
	# platform (notably Windows); clicking the capture field focuses it
	# explicitly, so it is reachable without Shift-Tab.
	bind $entry <Button-1> [namespace code [list CaptureClick $entry]]
	bind $capture.label <Button-1> [namespace code [list CaptureClick $entry]]
	bind $capture <Button-1> [namespace code [list CaptureClick $entry]]
	pack $capture -fill x -pady [list $::theme::pady 0]

	set buttons [ttk::frame $frame.buttons]
	ttk::button $buttons.apply -text $mc::KeyApply \
		-command [namespace code [list ApplyCapture $tree $entry]]
	ttk::button $buttons.reset -text $mc::KeyResetRow \
		-command [namespace code [list ResetSelected $tree]]
	ttk::button $buttons.resetAll -text $mc::KeyResetAll \
		-command [namespace code [list ResetAllAndRefresh $tree]]
	pack $buttons.apply $buttons.reset $buttons.resetAll -side left -padx [list 0 $::theme::padx]
	pack $buttons -anchor w -pady [list $::theme::pady 0]

	set status [ttk::label $frame.status -text "" -wraplength 460 -justify left]
	pack $status -anchor w

	set Dialog(tree) $tree
	set Dialog(entry) $entry
	set Dialog(status) $status
	set Dialog(action) {}

	FillTable $tree
	return $tree
}


proc ::application::keyEditor::FillTable {tree} {
	variable Actions

	$tree delete [$tree children {}]
	foreach entry $Actions {
		lassign $entry action labelVar tag keySpec cbSpec cmd
		set key [CurrentKey $action]
		if {$key eq ""} {
			set key $mc::KeyNone
		} else {
			set key [DescribeKey $key]
		}
		$tree insert {} end -id $action -text [ActionLabel $action $labelVar] \
			-values [list $key]
	}
}


proc ::application::keyEditor::SelectAction {tree} {
	variable Dialog
	if {[info exists Dialog(captured)]} { unset Dialog(captured) }
	set selection [$tree selection]
	if {[llength $selection] == 0} { return }
	set Dialog(action) [lindex $selection 0]
	$Dialog(entry) configure -state normal
	$Dialog(entry) delete 0 end
	$Dialog(entry) insert 0 $mc::KeyCapture
	$Dialog(entry) configure -state readonly
}


# The capture field shows the pressed combination; Return applies it.
# <platform> is only passed by tests, to drive the state decoding of
# another windowing system; real key events use the running platform.
proc ::application::keyEditor::CaptureKey {entry keysym state {platform ""}} {
	variable Dialog

	if {$keysym eq "Return"} { ApplyCapture $Dialog(tree) $entry; return "break" }
	if {[ModifierOnlyKeysym? $keysym]} {
		# A modifier alone is not a key. Windows delivers a KeyPress for
		# Alt_L/Meta_L when Alt goes down; it must not clear or replace
		# the combination being captured.
		return "break"
	}
	if {$Dialog(action) eq ""} {
		SetStatus $mc::KeyNeedsSelection
		return "break"
	}
	set spec [SpecFromEvent $keysym $state $platform]
	if {$spec eq ""} { return "break" }
	if {[SameKey $spec [CurrentKey $Dialog(action)]]} {
		# the key already in effect needs no override
		SetStatus $mc::KeySameScheme
		return "break"
	}
	set Dialog(captured) $spec
	$entry configure -state normal
	$entry delete 0 end
	$entry insert 0 [format $mc::KeyCaptured [DescribeKey $spec]]
	$entry configure -state readonly
	return "break"
}


# Clicking the read-only capture field gives it the keyboard focus; the
# class binding does not focus a read-only entry on every platform.
proc ::application::keyEditor::CaptureClick {entry} {
	focus -force $entry
	return "break"
}


proc ::application::keyEditor::CaptureFocus {entry} {
	variable Dialog
	$entry configure -state normal
	$entry delete 0 end
	if {[info exists Dialog(captured)] && $Dialog(action) ne ""} {
		$entry insert 0 [format $mc::KeyCaptured [DescribeKey $Dialog(captured)]]
	} elseif {$Dialog(action) ne ""} {
		$entry insert 0 $mc::KeyCapture
	}
	$entry configure -state readonly
}


# Is <keysym> a modifier key (pressed alone)? Caps Lock and Num Lock are
# included: Tk reports them as plain KeyPresses too.
proc ::application::keyEditor::ModifierOnlyKeysym? {keysym} {
	set modifierKeysyms {
		Shift_L Shift_R Control_L Control_R
		Alt_L Alt_R Meta_L Meta_R
		Super_L Super_R Hyper_L Hyper_R
		Caps_Lock Num_Lock Mode_switch
	}
	if {[lsearch -exact $modifierKeysyms $keysym] >= 0} { return 1 }
	return [ModifierOnly? $keysym]
}


# Native events share the C++ mask used by ::util::altIsHeldDown?. An
# explicit platform lets tests simulate another windowing system.
proc ::application::keyEditor::AltStateMask {{platform ""}} {
	if {$platform eq "" || $platform eq [tk windowingsystem]} {
		return $::util::altMask
	}
	switch -- $platform {
		win32 { return [expr {0x20000}] }
		aqua  { return [expr {0x10}] }
	}
	# Simulated X11: Mod1 for Alt_L, Mod5 for a remapped Alt_R.
	return [expr {0x8 | 0x80}]
}


# With Caps Lock on, Tk reports the other case of a letter keysym; the
# binding must not depend on it (see BindSpecs). <platform> is only
# passed by tests (see AltStateMask).
proc ::application::keyEditor::SpecFromEvent {keysym state {platform ""}} {
	if {$state & $::util::lockMask && [string length $keysym] == 1 && [string is alpha $keysym]} {
		if {[string is lower $keysym]} {
			set keysym [string toupper $keysym]
		} else {
			set keysym [string tolower $keysym]
		}
	}
	set mods {}
	if {$state & 0x4} { lappend mods Control }
	if {$state & [AltStateMask $platform]} { lappend mods Alt }
	if {$state & 0x1} { lappend mods Shift }
	set keysym [NormalizeKeysym $keysym]
	if {$keysym eq ""} { return "" }
	if {[llength $mods] == 0} { return $keysym }
	return "[join $mods -]-$keysym"
}


# Map a captured keysym to the keysym used in bind patterns.
proc ::application::keyEditor::NormalizeKeysym {keysym} {
	switch -- $keysym {
		space - Space { return "space" }
		comma { return "comma" }
		period { return "period" }
		Return - KP_Enter { return "Return" }
		Escape { return "Escape" }
		Tab { return "Tab" }
		BackSpace { return "BackSpace" }
		Delete { return "Delete" }
		Insert { return "Insert" }
		Home { return "Home" }
		End { return "End" }
		Prior { return "Prior" }
		Next { return "Next" }
		Up { return "Up" }
		Down { return "Down" }
		Left { return "Left" }
		Right { return "Right" }
	}
	if {[string length $keysym] == 1} {
		# printable characters keep their case in the keysym
		return $keysym
	}
	if {[regexp {^F([0-9]+)$} $keysym -> n]} { return "F$n" }
	return $keysym
}


# Apply the captured key to the selected action; report conflicts.
proc ::application::keyEditor::ApplyCapture {tree entry} {
	variable Dialog

	if {$Dialog(action) eq "" || ![info exists Dialog(captured)]} {
		SetStatus $mc::KeyNeedsSelection
		return
	}
	set action $Dialog(action)
	set spec $Dialog(captured)
	unset Dialog(captured)
	if {[catch {SetKey $action $spec} error]} {
		SetStatus $error
		return
	}
	FillTable $tree
	$tree selection set $action
	SelectAction $tree
	SetStatus ""
}


proc ::application::keyEditor::ResetSelected {tree} {
	variable Dialog
	if {$Dialog(action) eq ""} { return }
	ResetAction $Dialog(action)
	FillTable $tree
	SetStatus ""
}


proc ::application::keyEditor::ResetAllAndRefresh {tree} {
	ResetAll
	FillTable $tree
	set Dialog(action) {}
	SetStatus ""
}


proc ::application::keyEditor::SetStatus {text} {
	variable Dialog
	if {[info exists Dialog(status)] && [winfo exists $Dialog(status)]} {
		$Dialog(status) configure -text $text
	}
}


# Called from ::application::ShortcutPreferences; adds the key table below
# the scheme radio buttons.
proc ::application::keyEditor::ExtendDialog {dlg content} {
	BuildTable $content
}
