# ======================================================================
# ::application::assistant::panel -- the docked assistant panel shown at
# startup (VAL-AI-011).
#
# On a fresh profile the assistant presents itself beside the board with a
# one-line greeting and three or four suggestions chosen from the current
# state through the action registry. Every suggestion is a normal action:
# a click runs ::action::run, so the confirmation rules of the menu apply.
# The suggestions are built locally; no model, network or classifier is
# needed to show or run them.
#
# The panel is a normal layout pane. It is inserted next to the board in
# the board layout (or reopened through the usual pane API), so the layout
# mission's resize, zoom and reflow rules keep working. A visible Hide
# button collapses it and clears the "Show assistant at startup" option;
# opening the pane again (Ask field, F2/Ctrl+Shift+K, View > Panes, Tools >
# Assistant) sets the option again.
#
#   ::application::assistant::panel::Startup    start-of-session open
#   ::application::assistant::panel::SuggestIds ids for the current state
#   ::application::assistant::panel::Hide       one-click collapse
#   ::application::assistant::panel::SetEnabled persist the startup choice
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source app-assistant-panel
}

namespace eval application {
namespace eval assistant {
namespace eval panel {
namespace eval mc {

set StartupGreeting	"I can run Chesswiz for you. Pick a suggestion below, or ask in your own words."
set Hide				"Hide"
set NoModelHint		"No model is connected yet. Open Tools > Choose Model\u2026 to connect one; the suggestions above work without one."

} ;# namespace mc

variable Frame {}
variable Buttons {}
variable MaxSuggestions 4
variable HintShown 0
variable Retries 0
variable Stash {}
variable Placed 0
variable Compact 0

} ;# namespace panel
} ;# namespace assistant
} ;# namespace application


# ----------------------------------------------------------------------
# The startup choice, saved in the options file ("Show assistant at
# startup", default on).
# ----------------------------------------------------------------------
proc ::application::assistant::panel::Enabled {} {
	if {![info exists ::application::Options(assistant:startup)]} { return 1 }
	return [expr {$::application::Options(assistant:startup) ? 1 : 0}]
}

proc ::application::assistant::panel::SetEnabled {flag} {
	set ::application::Options(assistant:startup) [expr {$flag ? 1 : 0}]
	return $flag
}

proc ::application::assistant::panel::MarkShown {} {
	set was [Enabled]
	SetEnabled 1
	if {!$was} { SaveOption }
}


# The startup choice must survive even if the process is ended without a
# clean shutdown, so a click that changes it writes the options now.
proc ::application::assistant::panel::SaveOption {} {
	catch {
		::options::startTransaction
		::options::saveOptionsFile
		::options::endTransaction
	}
}


# ----------------------------------------------------------------------
# The pane.
# ----------------------------------------------------------------------
proc ::application::assistant::panel::Attach {pane} {
	variable Frame

	if {[winfo exists $pane.suggest]} { destroy $pane.suggest }
	set Frame [ttk::frame $pane.suggest]
	if {[winfo exists $pane.bottom]} {
		pack $Frame -side bottom -fill x -before $pane.bottom -padx 4 -pady {0 2}
	} else {
		pack $Frame -side bottom -fill x -padx 4 -pady {0 2}
	}
	# Suggestion labels and the Hide control follow the active language.
	# setLang emits this before SwitchLanguage refreshes registry labels.
	bind $Frame <<LanguageChanged>> [list after idle [namespace code Render]]
	Render
	return $Frame
}


proc ::application::assistant::panel::Render {} {
	variable Frame
	variable Buttons
	variable Retries

	set Buttons {}
	if {$Frame eq "" || ![winfo exists $Frame]} { return }
	# A saved Assistant pane is built inside the native layout transaction,
	# before the current game exists. Even a caught native query failure
	# poisons that transaction. Startup will render again once it is ready.
	if {![info exists ::application::Vars(display:after)]} {
		after 100 [namespace code Render]
		return
	}
	foreach w [winfo children $Frame] { destroy $w }

	set i 0
	foreach id [SuggestIds] {
		if {[catch { set rec [::action::get $id] }]} { continue }
		set label [::action::displayLabel [dict get $rec label]]
		set b [ttk::button $Frame.s[incr i] -text $label -style Toolbutton \
			-command [list ::application::assistant::panel::Run $id]]
		pack $b -side top -fill x -pady 1
		lappend Buttons $id $b
	}
	if {[winfo exists $Frame]} { Relabel }

	# The pane can be built before the drop-down has registered its
	# actions (slower starts, for example the first Windows run). Try
	# again shortly rather than leaving the panel without suggestions.
	if {![llength $Buttons] && $Retries < 20} {
		incr Retries
		after 100 [namespace code Render]
	} else {
		set Retries 0
	}
}


proc ::application::assistant::panel::Relabel {} {
	variable Frame

	if {$Frame eq "" || ![winfo exists $Frame]} { return }
	set pane [winfo parent $Frame]
	if {$pane ne "" && [winfo exists $pane.bottom.hide]} {
		catch { $pane.bottom.hide configure -text $::application::assistant::panel::mc::Hide }
	}
}


# Run one suggestion exactly as its menu row would.
proc ::application::assistant::panel::Run {id} {
	set result {}
	set rc [catch { set result [::action::run $id] } err]
	if {$rc} { set result "error: $err" }
	if {[string match "error:*" $result] || [string match "declined*" $result]
	 || [string match "not enabled*" $result]} {
		catch { ::ui::message $result }
	}
	after idle [namespace code Render]
	return $result
}


# One click: the panel goes away and the startup choice is cleared.
proc ::application::assistant::panel::Hide {} {
	SetEnabled 0
	SaveOption
	set twm [Twm]
	if {$twm eq ""} { return }
	if {[lsearch -exact [$twm leaves] assistant] >= 0} {
		catch { ::application::twm::ChangeState $twm assistant }
	}
	return
}


# Preferences > Assistant: apply the checkbox at once as well as saving it.
proc ::application::assistant::panel::SyncPreference {} {
	set twm [Twm]
	if {$twm eq ""} { return }
	set present [expr {[lsearch -exact [$twm leaves] assistant] >= 0}]
	if {[Enabled]} {
		if {!$present} { catch { ::application::openPane assistant } }
	} else {
		if {$present} { catch { ::application::twm::ChangeState $twm assistant } }
	}
	SaveOption
	return
}


proc ::application::assistant::panel::Show {} {
	SetEnabled 1
	SaveOption
	set twm [Twm]
	if {$twm eq ""} { return }
	if {[lsearch -exact [$twm leaves] assistant] < 0} {
		catch { ::application::openPane assistant }
	}
	# Reopening from the Ask field, its shortcut or View restores the same
	# docked position beside the board, not the default bottom slot. The
	# pane's own opening may finish on a later idle, so dock again then.
	PlaceBesideBoard $twm
	after idle [namespace code [list PlaceBesideBoard $twm]]
	return
}


proc ::application::assistant::panel::Twm {} {
	if {![info exists ::application::Vars(board:twm)]} { return "" }
	set twm $::application::Vars(board:twm)
	return [expr {[winfo exists $twm] ? $twm : ""}]
}


# ----------------------------------------------------------------------
# Start of the session: dock the panel beside the board when the option is
# on. The work is deferred to idle time so the main window is mapped at the
# same speed with and without the panel (VAL-AI-010/011).
# ----------------------------------------------------------------------
# The user may start working while optional startup work waits. Never switch
# away from that work or take typing focus when the deferred pane opens.
proc ::application::assistant::panel::DeferredStartup {initialTab} {
	if {![Enabled]} { return }
	if {[::application::activeTab] ne $initialTab} { return }
	set previous [focus]
	set entry ""
	catch { set entry [::application::ask::Entry] }
	if {$previous ni [list "" .application $entry]} { return }
	# A native layout rebuild can move focus internally. Active composition
	# takes precedence; sending the request will open the assistant normally.
	if {$previous eq $entry && $entry ne "" && [$entry get] ne ""} { return }
	Startup
	if {$previous eq $entry && $entry ne "" && [winfo exists $entry]} {
		focus $entry
	}
}

proc ::application::assistant::panel::Startup {} {
	if {![Enabled]} { return }
	set twm [Twm]
	if {$twm eq ""} { return }

	if {[lsearch -exact [$twm leaves] assistant] >= 0} {
		# A saved layout already contains the pane: bring it to the front
		# without creating a persistent reopen override.
		catch { ::application::openPane assistant false }
		after idle [namespace code Render]
		after 100 [namespace code StartupFocus]
		return
	}

	set ::application::assistant::Priv(startup) 1
	if {[catch { ::application::openPane assistant false } frame]} { return }
	if {$frame eq "" || ![winfo exists $frame]} { return }
	PlaceBesideBoard $twm
	after idle [namespace code Render]
	after 100 [namespace code StartupFocus]
}


# Native layout mapping can restore focus after its idle callbacks. Finish
# startup on Ask only while focus still belongs to the board, so a user's
# intervening choice of an editor or dialog keeps the keyboard.
proc ::application::assistant::panel::StartupFocus {} {
	set current [focus]
	if {$current eq "" || [string match .application.nb.board.board.* $current]} {
		::application::ask::StartupFocus
	}
}


# Move the freshly created pane to the right of the board, keeping every
# other pane where the user had it. Done through the native layout, so the
# result is an ordinary pane (resize, zoom, reflow and save all apply).
proc ::application::assistant::panel::PlaceBesideBoard {twm} {
	if {![winfo exists $twm]} { return }
	if {[catch { ::application::twm::inspectLayout $twm } layout]} { return }
	if {[lsearch -exact [$twm leaves] assistant] < 0} { return }
	if {[llength [$twm floats]] || [$twm zoomed] ne ""} { return }

	variable Stash
	variable Placed
	variable Compact
	set Stash {}
	set Placed 0
	# Keep the board's preferred width when a third column would squeeze
	# its native video reserve. A tab beside the board uses the existing
	# editor group's space; larger windows can show all three columns.
	set required [expr {[dict get $::application::PaneOptions(board) -width]
		+ [dict get $::application::PaneOptions(assistant) -minwidth]
		+ [dict get $::application::PaneOptions(editor) -width]}]
	set Compact [expr {[winfo width $twm] < $required}]

	lassign $layout root attrs children
	set children [MapLayout $children remove]
	if {![llength $Stash]} { return }
	set children [MapLayout $children insert]
	if {!$Placed} { return }
	set layout [list $root $attrs $children]
	catch { $twm load $layout }
	update idletasks
	catch { ::application::openPane assistant false }
	return
}


# Walk the layout's flat list of {type a b} triples. In "remove" mode the
# assistant leaf is taken out and remembered in Stash; in "insert" mode it
# is put back directly after the board leaf.
proc ::application::assistant::panel::MapLayout {nodes mode} {
	variable Stash
	variable Placed
	variable Compact

	set out {}
	set n [llength $nodes]
	for {set i 0} {$i + 2 < $n} {incr i 3} {
		set type [lindex $nodes $i]
		set a [lindex $nodes [expr {$i + 1}]]
		set b [lindex $nodes [expr {$i + 2}]]
		if {$type in {panedwindow multiwindow notebook}} {
			lappend out $type $a [MapLayout $b $mode]
		} elseif {$mode eq "remove" && $a eq "assistant"} {
			set Stash [list $type $a $b]
		} else {
			lappend out $type $a $b
			if {$mode eq "insert" && !$Placed && $a eq "board"} {
				set next [lindex $nodes [expr {$i + 3}]]
				if {$Compact && $next in {multiwindow notebook}} {
					lappend out $next [lindex $nodes [expr {$i + 4}]] \
						[concat $Stash [lindex $nodes [expr {$i + 5}]]]
					incr i 3
				} else {
					lappend out {*}$Stash
				}
				set Placed 1
			}
		}
	}
	return $out
}


# ----------------------------------------------------------------------
# Suggestions from the current state, through the registry. Three or four
# ordinary actions; one play/train entry is always present.
# ----------------------------------------------------------------------
proc ::application::assistant::panel::SuggestIds {} {
	EnsureRegistry

	set pool {}
	set loaded [GameLoaded]
	if {$loaded} {
		lappend pool menu.analysis.game_review menu.analysis.explain.position
	}
	if {[DbOpen]} {
		if {!$loaded} { lappend pool menu.db.search.plain menu.db.reports.eco }
		lappend pool menu.file.import.pgn
	} else {
		lappend pool menu.file.open menu.file.new.normal
	}

	set ids {}
	foreach id $pool {
		if {[Usable $id] && $id ni $ids} { lappend ids $id }
		if {[llength $ids] >= 3} break
	}

	# Always one way to play or train.
	foreach id {menu.training.play_engine menu.training.tactics menu.training.guess} {
		if {[Usable $id] && $id ni $ids} { lappend ids $id; break }
	}

	# Fill a short list from the same state's pool.
	foreach id [concat $pool {menu.file.open menu.file.new.normal menu.db.search.plain \
		menu.analysis.game_review menu.analysis.explain.position \
		menu.training.tactics menu.training.guess}] {
		if {[llength $ids] >= 3} break
		if {[Usable $id] && $id ni $ids} { lappend ids $id }
	}

	return [lrange $ids 0 [expr {[set ::application::assistant::panel::MaxSuggestions] - 1}]]
}


proc ::application::assistant::panel::EnsureRegistry {} {
	if {![catch { ::action::get menu.file.open }]} { return }
	catch {
		if {![info exists ::menu::DropdownTree] || [llength $::menu::DropdownTree] == 0} {
			::menu::DefineTree
		}
		::menu::RegisterTree
	}
}


proc ::application::assistant::panel::Usable {id} {
	if {[catch { ::action::get $id } rec]} { return 0 }
	if {[dict get $rec handler] eq ""} { return 0 }
	if {[llength [info commands ::menu::state]]} {
		if {[catch { set state [::menu::state $id] }]} { return 0 }
		return [expr {[dict get $state visible] && [dict get $state enabled]}]
	}
	return 1
}


proc ::application::assistant::panel::DbOpen {} {
	if {[llength [info commands ::menu::DbOpen]]} { return [::menu::DbOpen] }
	set base ""
	catch { set base [::scidb::db::get name] }
	return [expr {$base ne "" && $base ne $::scidb::clipbaseName}]
}


proc ::application::assistant::panel::GameLoaded {} {
	# A game with moves on the board counts, including one from the recent
	# game history; an empty scratch board does not.
	if {[catch { ::scidb::game::query length } length]} { return 0 }
	return [expr {[lindex $length 0] > 0}]
}


# ----------------------------------------------------------------------
# Greeting and the one-time model hint.
# ----------------------------------------------------------------------
proc ::application::assistant::panel::StartupGreeting {} {
	return $::application::assistant::panel::mc::StartupGreeting
}


proc ::application::assistant::panel::AfterGreeting {} {
	variable HintShown

	if {![NoModel]} { return "" }
	set hint $::application::assistant::panel::mc::NoModelHint
	# The pane is rebuilt when the layout changes (and when it is docked);
	# add the hint again to the new text if it is not already there, so it
	# is shown once per conversation rather than once per build.
	set text ""
	if {[info exists ::application::assistant::Priv(text)]} {
		set text $::application::assistant::Priv(text)
	}
	if {$text ne "" && [winfo exists $text]} {
		if {[string first $hint [$text get 1.0 end]] >= 0} {
			set HintShown 1
			return ""
		}
	} elseif {$HintShown} {
		return ""
	}
	set HintShown 1
	catch { ::application::assistant::Append info $hint }
	return $hint
}


# A cloud provider without a key is the honest "no model configured" case;
# the local default always counts as available. Nothing here opens a dialog.
proc ::application::assistant::panel::NoModel {} {
	if {![info exists ::application::ai::Config]} { return 0 }
	set provider $::application::ai::Config(provider)
	set model $::application::ai::Config(model)
	if {[catch { ::ai::provider::configure -name $provider -model $model }]} { return 0 }
	if {[catch { ::ai::provider::cloudProvider } cloud]} { return 0 }
	if {!$cloud} { return 0 }
	if {[catch { ::ai::provider::apiKey $provider } key]} { return 1 }
	return [expr {$key eq ""}]
}
