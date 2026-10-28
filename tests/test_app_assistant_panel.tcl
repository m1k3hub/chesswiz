# ======================================================================
# Scidb App Test — the docked assistant panel shown at startup
# (tcl/app-assistant-panel.tcl, VAL-AI-011, VAL-AI-010)
# ======================================================================
# The panel is a normal layout pane: it is docked directly after the
# board, its suggestions are ordinary registry actions, one click or the
# Preferences checkbox hides it and the startup choice is remembered.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::panel {
	variable Fixture ""
	variable Nop
}

proc ::scidb::test::panel::nop {args} {}

proc ::scidb::test::panel::twm {} {
	if {![info exists ::application::Vars(board:twm)]} { return "" }
	return $::application::Vars(board:twm)
}

proc ::scidb::test::panel::shown {} {
	set twm [::scidb::test::panel::twm]
	if {$twm eq ""} { return 0 }
	return [expr {[lsearch -exact [$twm leaves] assistant] >= 0}]
}

proc ::scidb::test::panel::closePane {} {
	set twm [::scidb::test::panel::twm]
	if {$twm eq ""} { return }
	if {[lsearch -exact [$twm leaves] assistant] >= 0} {
		catch { ::application::twm::ChangeState $twm assistant }
		update idletasks
	}
}

# A controlled start: the pane is gone, the option is on, then the same
# deferred entry point Startup2 uses runs.
proc ::scidb::test::panel::startup {} {
	::scidb::test::panel::closePane
	::application::assistant::panel::SetEnabled 1
	catch { unset ::application::assistant::Priv(startup) }
	::application::assistant::panel::Startup
	update
	update idletasks
}

# Leaf uids in document order, walking the flat {type a b} triple list.
proc ::scidb::test::panel::leafOrder {nodes} {
	set out {}
	set n [llength $nodes]
	for {set i 0} {$i + 2 < $n} {incr i 3} {
		set type [lindex $nodes $i]
		set a [lindex $nodes [expr {$i + 1}]]
		set b [lindex $nodes [expr {$i + 2}]]
		if {$type in {panedwindow multiwindow notebook}} {
			lappend out {*}[::scidb::test::panel::leafOrder $b]
		} else {
			lappend out $a
		}
	}
	return $out
}

proc ::scidb::test::panel::suggestions {} {
	variable ::application::assistant::panel::Buttons
	set ids {}
	foreach {id button} $Buttons { lappend ids $id }
	return $ids
}

proc ::scidb::test::panel::labels {} {
	variable ::application::assistant::panel::Buttons
	set out {}
	foreach {id button} $Buttons {
		if {[winfo exists $button]} { lappend out [$button cget -text] }
	}
	return $out
}

proc ::scidb::test::panel::rect {w} {
	return [list [winfo rootx $w] [winfo rooty $w] [winfo width $w] [winfo height $w]]
}

proc ::scidb::test::panel::overlap {a b} {
	lassign $a ax ay aw ah
	lassign $b bx by bw bh
	set w [expr {min($ax + $aw, $bx + $bw) - max($ax, $bx)}]
	set h [expr {min($ay + $ah, $by + $bh) - max($ay, $by)}]
	return [expr {$w > 0 && $h > 0}]
}

# Run <body> with the startup state probes replaced, so the suggestion pool
# is checked for a named state without opening real databases.
proc ::scidb::test::panel::withState {db game body} {
	foreach p {DbOpen GameLoaded} {
		rename ::application::assistant::panel::$p ::scidb::test::panel::real$p
		proc ::application::assistant::panel::$p {} [list return [expr {$p eq "DbOpen" ? $db : $game}]]
	}
	set rc [catch { uplevel 1 $body } result opts]
	foreach p {DbOpen GameLoaded} {
		rename ::application::assistant::panel::$p {}
		rename ::scidb::test::panel::real$p ::application::assistant::panel::$p
	}
	return -options $opts $result
}

proc ::scidb::test::panel::fixture {} {
	variable Fixture
	set Fixture [file join [file dirname [file normalize [info script]]] tmp-app panel-game.pgn]
	file mkdir [file dirname $Fixture]
	set f [open $Fixture w]
	puts $f {[Event "Panel"]
[Site "X"]
[Date "2020.01.01"]
[Round "1"]
[White "Tal, M"]
[Black "Smyslov, V"]
[Result "1-0"]

1. e4 e5 2. Nf3 Nc6 1-0}
	close $f
	return $Fixture
}

proc ::scidb::test::panel::loadGame {} {
	variable Fixture
	::scidb::db::open $Fixture {apply {args {return 0}}} {} {apply {args {return 0}}} {}
	::scidb::game::load 55 $Fixture Normal 0
	::scidb::game::subscribe board 55 ::scidb::test::panel::nop
	::scidb::game::switch 55
	return $Fixture
}

proc ::scidb::test::panel::unloadGame {} {
	variable Fixture
	catch { ::scidb::game::release 55 }
	catch { ::scidb::game::switch $::scidb::clipbaseName }
	catch { ::scidb::db::close $Fixture }
	catch { file delete $Fixture }
	set Fixture ""
	return
}


# ----------------------------------------------------------------------
# The option and a fresh start.
# ----------------------------------------------------------------------
tcltest::test panel-option-default {the startup option is on by default} -body {
	namespace eval ::application { variable Options }
	set previous [expr {[info exists ::application::Options(assistant:startup)] ? $::application::Options(assistant:startup) : "unset"}]
	set ::application::Options(assistant:startup) 1
	set on [::application::assistant::panel::Enabled]
	::application::assistant::panel::SetEnabled 0
	set off [::application::assistant::panel::Enabled]
	::application::assistant::panel::SetEnabled $previous
	list $on $off
} -result {1 0}

tcltest::test panel-startup-docks {the startup panel is a board-layout pane docked directly after the board} -body {
	::scidb::test::panel::startup
	set twm [::scidb::test::panel::twm]
	set leaves [$twm leaves]
	set layout [::application::twm::inspectLayout $twm]
	set order [::scidb::test::panel::leafOrder [lindex $layout 2]]
	set board [expr {[lsearch -exact $order board]}]
	set assistant [expr {[lsearch -exact $order assistant]}]
	list [expr {"assistant" in $leaves}] [expr {$board >= 0 && $assistant == $board + 1}] \
		[expr {!![$twm isundockable assistant]}]
} -result {1 1 1}

tcltest::test panel-one-line-greeting {the panel opens with a one-line greeting that says it can run Chesswiz} -body {
	set text $::application::assistant::panel::mc::StartupGreeting
	list [expr {[string first "\n" $text] < 0}] \
		[string match {*run Chesswiz*} $text] \
		[expr {$text eq [::application::assistant::panel::StartupGreeting]}]
} -result {1 1 1}

tcltest::test panel-greeting-in-conversation {the greeting is the first line of the pane's one conversation} -body {
	::scidb::test::panel::startup
	set ::application::assistant::Priv(startup) 1
	::application::assistant::clear
	set body [$::application::assistant::Priv(text) get 1.0 end]
	string match "*[::application::assistant::panel::StartupGreeting]*" $body
} -result 1

tcltest::test panel-startup-keeps-focus {the docked panel does not take the keyboard at startup} -body {
	::scidb::test::panel::startup
	set focused [focus]
	set pane [::scidb::test::panel::twm]
	set leaf [$pane leaf assistant]
	list [expr {$focused eq "" || ![string match "$leaf*" $focused]}] \
		[expr {[winfo exists $::application::assistant::Priv(entry)] && $focused ne $::application::assistant::Priv(entry)}]
} -result {1 1}

tcltest::test panel-does-not-cover-board {the panel sits beside the board, never over it} -body {
	::scidb::test::panel::startup
	set twm [::scidb::test::panel::twm]
	set boardW [$twm leaf board]
	set paneW [$twm leaf assistant]
	set board [::scidb::test::panel::rect $boardW]
	set pane [::scidb::test::panel::rect $paneW]
	list [expr {[lindex $pane 2] > 0 && [lindex $pane 3] > 0}] \
		[expr {![::scidb::test::panel::overlap $board $pane]}]
} -result {1 1}


# ----------------------------------------------------------------------
# Suggestions: three or four, state-based, ordinary registry actions.
# ----------------------------------------------------------------------
tcltest::test panel-suggestions {three or four distinct usable actions, one of them play or train} -body {
	set ids [::application::assistant::panel::SuggestIds]
	set usable [lmap id $ids { ::application::assistant::panel::Usable $id }]
	set training [lmap id $ids { expr {[string match menu.training.* $id]} }]
	list [expr {[llength $ids] >= 3 && [llength $ids] <= 4}] \
		[expr {[llength [lsort -unique $ids]] == [llength $ids]}] \
		[expr {[lsearch -exact $usable 0] < 0}] \
		[expr {[lsearch -exact $training 1] >= 0}]
} -result {1 1 1 1}

tcltest::test panel-suggestions-empty-profile {with no database and no game the ways in are file actions plus play} -body {
	::scidb::test::panel::withState 0 0 {
		set ids [::application::assistant::panel::SuggestIds]
	}
	list [expr {[lsearch -glob $ids menu.file.*] >= 0}] \
		[expr {[lsearch -glob $ids menu.training.*] >= 0}] \
		[expr {[lsearch -exact $ids menu.analysis.game_review] < 0}]
} -result {1 1 1}

tcltest::test panel-suggestions-loaded-game {a game on the board gets review and explanation suggestions} -body {
	::scidb::test::panel::withState 0 1 {
		set ids [::application::assistant::panel::SuggestIds]
	}
	list [expr {[lsearch -exact $ids menu.analysis.game_review] >= 0}] \
		[expr {[lsearch -exact $ids menu.analysis.explain.position] >= 0}] \
		[expr {[lsearch -glob $ids menu.training.*] >= 0}]
} -result {1 1 1}

tcltest::test panel-game-detected {a loaded game is seen without the gamebar} -setup {
	::scidb::test::panel::fixture
} -body {
	::scidb::test::panel::loadGame
	set loaded [::application::assistant::panel::GameLoaded]
	set ids [::application::assistant::panel::SuggestIds]
	::scidb::test::panel::unloadGame
	list $loaded [expr {[lsearch -exact $ids menu.analysis.game_review] >= 0}]
} -result {1 1}

tcltest::test panel-buttons {the pane shows one button per suggestion and each runs its action id} -body {
	::scidb::test::panel::startup
	::application::assistant::panel::Render
	set frame $::application::assistant::panel::Frame
	set ids [::scidb::test::panel::suggestions]
	set commands {}
	foreach {id button} $::application::assistant::panel::Buttons {
		lappend commands [lindex [$button cget -command] 1]
	}
	list [expr {[llength $ids] >= 3}] \
		[expr {[llength [winfo children $frame]] == [llength $ids]}] \
		[expr {$commands eq $ids}]
} -result {1 1 1}

tcltest::test panel-suggestion-runs-action {a click runs the same registry action as the menu row} -body {
	rename ::action::run ::scidb::test::panel::realRun
	set ::scidb::test::panel::Ran {}
	proc ::action::run {id} {
		set ::scidb::test::panel::Ran $id
		return ok
	}
	set rc [catch { ::application::assistant::panel::Run menu.training.tactics } result]
	rename ::action::run {}
	rename ::scidb::test::panel::realRun ::action::run
	list $rc $result $::scidb::test::panel::Ran
} -result {0 ok menu.training.tactics}

tcltest::test panel-suggestion-confirms {a declined suggestion is reported, not silently swallowed} -setup {
	rename ::action::run ::scidb::test::panel::realRun
	rename ::ui::message ::scidb::test::panel::realMessage
	proc ::action::run {id} { return "declined: the action was cancelled" }
	proc ::ui::message {text} { set ::scidb::test::panel::Told $text }
	set ::scidb::test::panel::Told ""
} -body {
	::application::assistant::panel::Run menu.file.open
	set ::scidb::test::panel::Told
} -cleanup {
	rename ::action::run {}
	rename ::scidb::test::panel::realRun ::action::run
	rename ::ui::message {}
	rename ::scidb::test::panel::realMessage ::ui::message
} -result {declined: the action was cancelled}


# ----------------------------------------------------------------------
# Hide, persist, preferences and reopening.
# ----------------------------------------------------------------------
tcltest::test panel-hide-button {the pane has a visible Hide control in its action language} -body {
	::scidb::test::panel::startup
	set pane $::application::assistant::panel::Frame
	set bottom [winfo parent $pane].bottom
	set hide $bottom.hide
	list [winfo exists $hide] [winfo ismapped $hide] \
		[$hide cget -text] \
		[expr {[$hide cget -text] eq $::application::assistant::panel::mc::Hide}]
} -result {1 1 Hide 1}

tcltest::test panel-hide-persists {Hide collapses the pane and a later start leaves it closed} -body {
	::scidb::test::panel::startup
	::application::assistant::panel::Hide
	update idletasks
	set first [list [::scidb::test::panel::shown] [::application::assistant::panel::Enabled]]
	::application::assistant::panel::Startup
	update
	list $first [list [::scidb::test::panel::shown] [::application::assistant::panel::Enabled]]
} -result {{0 0} {0 0}}

tcltest::test panel-reopen-sets-option {opening the pane again (Ask field, shortcut, View) re-enables startup} -body {
	::application::assistant::panel::SetEnabled 0
	::scidb::test::panel::closePane
	::application::assistant::show
	update
	list [::scidb::test::panel::shown] [::application::assistant::panel::Enabled]
} -cleanup {
	::application::assistant::panel::SetEnabled 1
} -result {1 1}

tcltest::test panel-reopen-docks-beside-board {reopening from the Ask field restores the docked position} -body {
	::scidb::test::panel::startup
	::scidb::test::panel::closePane
	::application::assistant::show
	update
	set twm [::scidb::test::panel::twm]
	set order [::scidb::test::panel::leafOrder [lindex [::application::twm::inspectLayout $twm] 2]]
	list [::scidb::test::panel::shown] \
		[expr {[lsearch -exact $order assistant] == [lsearch -exact $order board] + 1}]
} -result {1 1}

tcltest::test panel-pane-toggle-remembers {View > Panes hides the pane and clears the option; showing it again restores both} -body {
	::scidb::test::panel::startup
	set shownBefore [::scidb::test::panel::shown]
	::menu::TogglePaneId assistant
	update
	set hidden [list [::scidb::test::panel::shown] [::application::assistant::panel::Enabled]]
	::menu::TogglePaneId assistant
	update
	list $shownBefore $hidden [list [::scidb::test::panel::shown] [::application::assistant::panel::Enabled]]
} -result {1 {0 0} {1 1}}

tcltest::test panel-hide-writes-option {Hide writes the choice at once, so it survives an unclean exit} -body {
	::application::assistant::panel::SetEnabled 1
	::application::assistant::panel::Hide
	set chan [open $::scidb::file::options r]
	set data [read $chan]
	close $chan
	set saved [regexp {assistant:startup\s+\{0\}} $data]
	::application::assistant::panel::Show
	set saved
} -result 1

tcltest::test panel-preference-checkbox {Preferences > Assistant has the startup checkbox bound to the option} -body {
	::application::ask::Preferences
	update
	set dlg .application.assistantPreferences
	set box $dlg.content.startup
	set out [list [winfo exists $dlg] [winfo exists $box] [$box cget -text] \
		[$box cget -variable] [$box cget -command]]
	destroy $dlg
	update
	set out
} -result {1 1 {Show assistant at startup} ::application::Options(assistant:startup) ::application::assistant::panel::SyncPreference}

tcltest::test panel-option-written {the startup choice is saved in the options file} -body {
	::application::assistant::panel::SetEnabled 0
	set path [file join [file dirname [file normalize [info script]]] tmp-app panel-options.txt]
	set chan [open $path w]
	::application::WriteShortcutOptions $chan
	close $chan
	set chan [open $path r]
	set data [read $chan]
	close $chan
	file delete $path
	::application::assistant::panel::SetEnabled 1
	regexp {assistant:startup\s+\{0\}} $data
} -result 1

tcltest::test panel-preference-applies {the Preferences checkbox hides or shows the pane at once} -body {
	::scidb::test::panel::startup
	::application::assistant::panel::SetEnabled 0
	::application::assistant::panel::SyncPreference
	update
	set hidden [::scidb::test::panel::shown]
	::application::assistant::panel::SetEnabled 1
	::application::assistant::panel::SyncPreference
	update
	list $hidden [::scidb::test::panel::shown]
} -result {0 1}


# ----------------------------------------------------------------------
# Offline: the suggestions need no model, and the hint is shown once.
# ----------------------------------------------------------------------
tcltest::test panel-no-model-hint-once {with no model connected the pane says once how to connect one} -body {
	rename ::application::assistant::panel::NoModel ::scidb::test::panel::realNoModel
	proc ::application::assistant::panel::NoModel {} { return 1 }
	set ::application::assistant::panel::HintShown 0
	::scidb::test::panel::startup
	set hint $::application::assistant::panel::mc::NoModelHint
	::application::assistant::panel::AfterGreeting
	::application::assistant::panel::AfterGreeting
	set body [$::application::assistant::Priv(text) get 1.0 end]
	set count 0
	set at 0
	while {[set at [string first $hint $body $at]] >= 0} { incr count; incr at [string length $hint] }
	rename ::application::assistant::panel::NoModel {}
	rename ::scidb::test::panel::realNoModel ::application::assistant::panel::NoModel
	list [expr {$count == 1}] [string match {*Choose Model*} $hint]
} -result {1 1}

tcltest::test panel-ask-field-same-conversation {the Ask field submits into the panel's one conversation} -body {
	::scidb::test::panel::startup
	rename ::application::assistant::ask ::scidb::test::panel::realAsk
	set ::scidb::test::panel::Asked ""
	proc ::application::assistant::ask {text} {
		set ::scidb::test::panel::Asked $text
		return 1
	}
	set ask [::application::ask::Entry]
	$ask delete 0 end
	$ask insert 0 "review my last game"
	::application::ask::SendToAssistant
	set asked $::scidb::test::panel::Asked
	rename ::application::assistant::ask {}
	rename ::scidb::test::panel::realAsk ::application::assistant::ask
	list $asked [::scidb::test::panel::shown]
} -result {{review my last game} 1}

tcltest::test panel-deferred-user-work {deferred startup preserves a database view and its typing focus} -setup {
 set idleInitialTab [::application::activeTab]
 set idleInitialFocus [focus]
 set idleInitialOption $::application::Options(assistant:startup)
 set ::application::Options(assistant:startup) 1
 update
 ::application::switchTab database
 update idletasks
 set idleWorkFocus [focus]
 set idleWorkLeaves [[::application::twm board] leaves]
} -body {
 ::application::assistant::panel::DeferredStartup information
 update idletasks
 list [::application::activeTab] [expr {[focus] eq $idleWorkFocus}] \
  [expr {[[::application::twm board] leaves] eq $idleWorkLeaves}]
} -cleanup {
 set ::application::Options(assistant:startup) $idleInitialOption
 ::application::switchTab $idleInitialTab
 if {$idleInitialFocus ne "" && [winfo exists $idleInitialFocus]} {focus $idleInitialFocus}
} -result {database 1 1}

tcltest::test panel-deferred-typing-focus {deferred startup yields to active Ask composition without transient focus theft} -setup {
 set typingInitialTab [::application::activeTab]
 set typingInitialOption $::application::Options(assistant:startup)
 ::scidb::test::panel::closePane
 update
 ::application::switchTab information
 set typingEntry [::application::ask::Entry]
 set typingText [$typingEntry get]
 $typingEntry delete 0 end
 $typingEntry insert 0 {Unsent request still being composed}
 focus -force $typingEntry
 update
 set ::application::Options(assistant:startup) 1
 set typingBinding [bind all <FocusIn>]
 set ::scidb::test::panel::typingFocus {}
 bind all <FocusIn> {+lappend ::scidb::test::panel::typingFocus [focus]}
} -body {
 ::application::assistant::panel::DeferredStartup information
 after 200 {set ::scidb::test::panel::typingSettled 1}
 vwait ::scidb::test::panel::typingSettled
 set other {}
 foreach target $::scidb::test::panel::typingFocus {
  if {$target ne $typingEntry} {lappend other $target}
 }
 list [::scidb::test::panel::shown] [expr {[focus] eq $typingEntry}] \
  [expr {[$typingEntry get] eq {Unsent request still being composed}}] $other
} -cleanup {
 bind all <FocusIn> $typingBinding
 $typingEntry delete 0 end
 $typingEntry insert 0 $typingText
 set ::application::Options(assistant:startup) $typingInitialOption
 ::application::switchTab $typingInitialTab
} -result {0 1 1 {}}


tcltest::test panel-live-language-switch {suggestion labels follow en->de->en after registry refresh} -setup {
	set savedLang $::mc::langID
	::scidb::test::panel::startup
} -body {
	set labels {}
	set matches {}
	foreach lang {en de en} {
		::menu::SwitchLanguage $lang
		update idletasks
		set expected {}
		foreach {id button} $::application::assistant::panel::Buttons {
			lappend expected [::action::displayLabel [dict get [::action::get $id] label]]
		}
		set actual [::scidb::test::panel::labels]
		lappend labels $actual
		lappend matches [expr {[llength $actual] >= 3 && $actual eq $expected}]
	}
	list $matches [expr {[lindex $labels 0] ne [lindex $labels 1]}] \
		[expr {[lindex $labels 0] eq [lindex $labels 2]}]
} -cleanup {
	::menu::SwitchLanguage $savedLang
	update idletasks
} -result {{1 1 1} 1 1}

tcltest::cleanupTests
