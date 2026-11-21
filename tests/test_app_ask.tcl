# ======================================================================
# Scidb App Test - the Ask field is the palette (VAL-PAL-001/002)
# ======================================================================
# The Ask field filters the action registry on every keystroke. Only
# actions the user can run now are listed, Enter runs through
# ::action::run (so the confirm gate applies), the last row hands the
# text to the assistant, Esc closes and restores the focus. Ctrl+K keeps
# D-2 kill-line inside multi-line editors. Nothing here opens a dialog
# unless it says so; every test restores what it touched.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

# The placeholder overlays the entry, so it must forward clicks in every theme.
foreach theme {clam dark} {
    tcltest::test ask-placeholder-focus-$theme {clicking the empty field focuses its entry} -setup {
        set savedTheme [::theme::currentTheme]
        set savedQuery $::application::ask::Query
        set savedFocus [focus]
        ::theme::setTheme $theme
        set ::application::ask::Query {}
        ::application::ask::PlaceholderState
        ::application::ask::HideList
        focus -force .application
        update
    } -body {
        set label .application.nb.ask.placeholder
        focus -force .application
        set before [focus]
        set mapped [winfo ismapped $label]
        event generate $label <ButtonPress-1> -x 5 -y 5
        update
        list [expr {$before ne ".application.nb.ask.entry"}] $mapped [focus]
    } -cleanup {
        ::application::ask::HideList
        set ::application::ask::Query $savedQuery
        ::application::ask::PlaceholderState
        ::theme::setTheme $savedTheme
        if {$savedFocus ne "" && [winfo exists $savedFocus]} { focus $savedFocus }
        update
    } -result {1 1 .application.nb.ask.entry}
}

namespace eval ::scidb::test::ask {
	variable Ran {}
	variable Sent {}
	variable Asked {}
	variable Answer 1
	variable Synthetics {}
}

proc ::scidb::test::ask::reset {} {
	variable Ran {}
	variable Sent {}
	variable Asked {}
	variable Answer 1

	catch { ::application::ask::HideList }
	set ::application::ask::Query ""
	catch { ::application::ask::Entry delete 0 end }
	catch { ::application::ask::PlaceholderState }
	return
}

# Register a synthetic action and remove it afterwards. <opts> is a
# dict merged over the required fields (confirm, enabled, visible...).
proc ::scidb::test::ask::action {id label opts} {
	set record [dict merge [dict create \
		label    $label \
		object   {} \
		handler  ::scidb::test::ask::ran \
		what     "" \
		doc      ""] $opts]
	::action::register $id $record
	return $id
}

proc ::scidb::test::ask::yes {} { return 1 }
proc ::scidb::test::ask::explode {} { error "predicate failed" }
proc ::scidb::test::ask::no {} { return 0 }

proc ::scidb::test::ask::ran {args} {
	lappend ::scidb::test::ask::Ran $args
	return "ran"
}

proc ::scidb::test::ask::forget {args} {
	foreach id $args {
		catch { dict unset ::action::Registry $id }
	}
}

# Stub the assistant and the provider so nothing leaves the process.
proc ::scidb::test::ask::install {} {
	catch { rename ::application::assistant::ask ::scidb::test::ask::realAsk }
	proc ::application::assistant::ask {request args} {
		lappend ::scidb::test::ask::Asked $request
		return 1
	}
	catch { rename ::application::assistant::show ::scidb::test::ask::realShow }
	proc ::application::assistant::show {args} { return 1 }
}

proc ::scidb::test::ask::uninstall {} {
	catch { rename ::application::assistant::ask {} }
	catch { rename ::scidb::test::ask::realAsk ::application::assistant::ask }
	catch { rename ::application::assistant::show {} }
	catch { rename ::scidb::test::ask::realShow ::application::assistant::show }
}

proc ::scidb::test::ask::isolated {body} {
	set saved [dict create \
		confirm $::action::ConfirmHook \
		query   $::application::ask::Query \
		priv    [array get ::application::ask::Priv] \
		hist    [expr {[info exists ::application::assistant::History] ? $::application::assistant::History : {}}]]
	unset -nocomplain ::application::assistant::History
	reset
	install
	catch { update }

	set rc [catch { uplevel 1 $body } result]

	uninstall
	set ::action::ConfirmHook [dict get $saved confirm]
	set ::application::ask::Query [dict get $saved query]
	array set ::application::ask::Priv [dict get $saved priv]
	if {[dict get $saved hist] ne ""} {
		set ::application::assistant::History [dict get $saved hist]
	}
	catch { ::application::ask::HideList }
	if {$rc} { return -code error $result }
	return $result
}

proc ::scidb::test::ask::type {text} {
	set entry [::application::ask::Entry]
	$entry delete 0 end
	$entry insert 0 $text
	::application::ask::Typed ""
	catch { update idletasks }
	return $text
}

proc ::scidb::test::ask::Percentile {values pct} {
	set values [lsort -real $values]
	if {![llength $values]} { return 0 }
	set i [expr {int(ceil($pct * [llength $values])) - 1}]
	if {$i < 0} { set i 0 }
	return [lindex $values $i]
}

proc ::scidb::test::ask::answer {what} {
	lappend ::scidb::test::ask::Asked $what
	return $::scidb::test::ask::Answer
}

# ----------------------------------------------------------------------
# The field in the top strip.
# ----------------------------------------------------------------------
tcltest::test ask-field-present {the Ask field exists with its placeholder} -body {
	list [winfo exists [::application::ask::Entry]] \
		[[::application::ask::Entry] cget -textvariable] \
		[set ::application::ask::mc::Placeholder] \
		[::application::ask::PlaceholderState]
} -result {1 ::application::ask::Query {Ask or tell Chesswiz what to do (Ctrl+K)} {}}

tcltest::test ask-first-in-tab-order {Tab from the main window reaches the Ask field first} -body {
	set next [tk_focusNext .application]
	list $next [::application::ask::Entry]
} -result [list [::application::ask::Entry] [::application::ask::Entry]]

tcltest::test ask-placeholder-hides-with-text {the placeholder is only shown while the field is empty} -body {
	::scidb::test::ask::isolated {
		set entry [::application::ask::Entry]
		set placeholder .application.nb.ask.placeholder
		set empty [winfo manager $placeholder]
		$entry insert 0 "x"
		::application::ask::Typed ""
		update idletasks
		set typed [winfo manager $placeholder]
		$entry delete 0 end
		::application::ask::Typed ""
		update idletasks
		set again [winfo manager $placeholder]
		list $empty $typed $again
	}
} -result {place {} place}

# ----------------------------------------------------------------------
# Filtering (VAL-PAL-001, VAL-RULE-004).
# ----------------------------------------------------------------------
tcltest::test ask-typing-filters {typing narrows the registry to matching actions} -body {
	::scidb::test::ask::isolated {
		set all [::action::labels asklist ""]
		::scidb::test::ask::type "new game"
		set rows $::application::ask::Priv(rows)
		set labels {}
		foreach row $rows { lappend labels [lindex $row 1] }
		# Context-only rows need their object (VAL-RULE-005); the global
		# registry is still far larger than the available list.
		list [expr {[llength $all] > 200}] \
			[expr {[llength $rows] > 0 && [llength $rows] < [llength $all]}] \
			[expr {[lsearch -exact $labels "New Game"] >= 0}] \
			[::application::ask::ListVisible]
	}
} -result {1 1 1 1}

# GAP-003 (terminal review 7): the search text starts with the visible
# label, so typing exactly what the row shows ranks that row first even
# though the stored label also carries "&" mnemonic markup.
tcltest::test ask-exact-visible-label-ranks-first {the exact visible label ranks first in every catalog} -body {
	set saved $::mc::langID
	set bad {}
	foreach {lang query} {
		en Help
		en {Focus follows size}
		es Motores
		de Anmerkungen
		hu Értékelés
	} {
		::menu::SwitchLanguage $lang
		update
		set rows [::action::labels asklist $query]
		if {![llength $rows]} { lappend bad [list $lang $query no-rows]; continue }
		set top [lindex $rows 0]
		set visible [::action::displayLabel [lindex $top 1]]
		if {$visible ne $query} {
			lappend bad [list $lang $query [lindex $top 0] $visible]
		}
	}
	::menu::SwitchLanguage $saved
	update
	set bad
} -result {}

tcltest::test ask-stored-markup-label-still-matches {typing a stored "&" label still finds the row} -body {
	set saved $::mc::langID
	::menu::SwitchLanguage en
	set englishHelp [lmap row [::action::labels asklist "&Help"] {lindex $row 0}]
	set englishSupport [lmap row [::action::labels asklist "&Support"] {lindex $row 0}]
	::menu::SwitchLanguage es
	set spanishEngines [lmap row [::action::labels asklist "Motor&es"] {lindex $row 0}]
	::menu::SwitchLanguage de
	set german [lmap row [::action::labels asklist "&Anmerkungen"] {lindex $row 0}]
	::menu::SwitchLanguage $saved
	update
	list [expr {"app-help" in $englishHelp}] \
		[expr {"menu.help.support" in $englishSupport}] \
		[expr {"menu.edit.preferences.engines" in $spanishEngines || "menu.analysis.engines" in $spanishEngines}] \
		[expr {"menu.board.appearance.annotation" in $german}]
} -result {1 1 1 1}

tcltest::test ask-asklist-only-runnable {hidden and disabled actions never reach the list} -body {
	::scidb::test::ask::isolated {
		set ::scidb::test::ask::Ran {}
		::scidb::test::ask::action test.ask.hidden "Zebra Hidden Action" \
			[dict create visible ::scidb::test::ask::no]
		::scidb::test::ask::action test.ask.disabled "Zebra Disabled Action" \
			[dict create enabled ::scidb::test::ask::no]
		::scidb::test::ask::action test.ask.shown "Zebra Shown Action" \
			[dict create visible ::scidb::test::ask::yes enabled ::scidb::test::ask::yes]
		set rows [::action::labels asklist "zebra"]
		set ids {}
		foreach row $rows { lappend ids [lindex $row 0] }
		set result [list \
			[expr {[lsearch -exact $ids test.ask.shown] >= 0}] \
			[expr {[lsearch -exact $ids test.ask.hidden] < 0}] \
			[expr {[lsearch -exact $ids test.ask.disabled] < 0}]]
		::scidb::test::ask::forget test.ask.hidden test.ask.disabled test.ask.shown
		set result
	}
} -result {1 1 1}

tcltest::test ask-asklist-rows-shape {asklist rows carry id, label, accelerator, enabled, visible} -body {
	::scidb::test::ask::isolated {
		set rows [::action::labels asklist ""]
		set bad {}
		foreach row $rows {
			if {[llength $row] != 5} { lappend bad $row }
			lassign $row id label accel enabled visible
			if {!$enabled || !$visible || $id eq "" || $label eq ""} { lappend bad $row }
		}
		list [llength $bad] [expr {[llength $rows] > 200}]
	}
} -result {0 1}

tcltest::test ask-up-down-wraps-in-list {Up/Down move the selection inside the list} -body {
	::scidb::test::ask::isolated {
		::scidb::test::ask::type "new game"
		set count [llength $::application::ask::Priv(rows)]
		set first $::application::ask::Priv(index)
		::application::ask::Move 1
		update idletasks
		set second $::application::ask::Priv(index)
		::application::ask::Move -1
		update idletasks
		set third $::application::ask::Priv(index)
		::application::ask::Move -1
		update idletasks
		set top $::application::ask::Priv(index)
		list $first $second $third $top [expr {$count > 1}]
	}
} -result {0 1 0 0 1}

# ----------------------------------------------------------------------
# Enter runs through the registry (confirm gate included).
# ----------------------------------------------------------------------
tcltest::test ask-enter-runs-registry-action {Enter runs the selected action through ::action::run} -body {
	::scidb::test::ask::isolated {
		set ::scidb::test::ask::Ran {}
		::scidb::test::ask::action test.ask.run "Zebra Run Action" {}
		::scidb::test::ask::type "zebra run"
		# the synthetic action must be the top match
		set top [lindex $::application::ask::Priv(rows) 0]
		::application::ask::Choose
		set result [list [lindex $top 0] [llength $::scidb::test::ask::Ran] \
			[::application::ask::ListVisible] $::application::ask::Query]
		::scidb::test::ask::forget test.ask.run
		set result
	}
} -result {test.ask.run 1 0 {}}

tcltest::test ask-declined-confirm-runs-nothing {declining the confirm gate runs no handler} -body {
	::scidb::test::ask::isolated {
		set ::scidb::test::ask::Ran {}
		set ::scidb::test::ask::Answer 0
		::scidb::test::ask::action test.ask.confirm "Zebra Confirm Action" \
			[dict create confirm 1 what "do the zebra thing"]
		set ::action::ConfirmHook ::scidb::test::ask::answer
		::scidb::test::ask::type "zebra confirm"
		::application::ask::Choose
		set result [list [llength $::scidb::test::ask::Ran] [::application::ask::ListVisible]]
		::scidb::test::ask::forget test.ask.confirm
		set result
	}
} -result {0 0}

tcltest::test ask-accepted-confirm-runs-once {accepting the confirm gate runs the handler exactly once} -body {
	::scidb::test::ask::isolated {
		set ::scidb::test::ask::Ran {}
		set ::scidb::test::ask::Answer 1
		::scidb::test::ask::action test.ask.confirm2 "Zebra Confirm Two" \
			[dict create confirm 1 what "do the zebra thing"]
		set ::action::ConfirmHook ::scidb::test::ask::answer
		::scidb::test::ask::type "zebra confirm two"
		::application::ask::Choose
		set result [list [llength $::scidb::test::ask::Ran] [lindex $::scidb::test::ask::Asked 0]]
		::scidb::test::ask::forget test.ask.confirm2
		set result
	}
} -result {1 {do the zebra thing}}

# ----------------------------------------------------------------------
# The assistant row.
# ----------------------------------------------------------------------
tcltest::test ask-no-match-sends-to-assistant {a query with no action match goes to the assistant} -body {
	::scidb::test::ask::isolated {
		::scidb::test::ask::type "qqzzxx no such action"
		set rows [llength $::application::ask::Priv(rows)]
		::application::ask::Choose
		list $rows [lindex $::scidb::test::ask::Asked 0] $::application::ask::Query
	}
} -result {0 {qqzzxx no such action} {}}

tcltest::test ask-last-row-sends-to-assistant {the last row always hands the text to the assistant} -body {
	::scidb::test::ask::isolated {
		::scidb::test::ask::type "new game"
		set rows [llength $::application::ask::Priv(rows)]
		set ::application::ask::Priv(index) $rows
		::application::ask::Choose
		list [expr {$rows > 0}] [lindex $::scidb::test::ask::Asked 0]
	}
} -result {1 {new game}}

tcltest::test ask-list-shows-assistant-row {the open list ends with the "Ask the assistant" row} -body {
	::scidb::test::ask::isolated {
		::scidb::test::ask::type "new game"
		set list .application.askList.list
		set n [$list size]
		list [expr {$n == [llength $::application::ask::Priv(rows)] + 1}] \
			[string trim [$list get [expr {$n - 1}]]] \
			$::application::ask::mc::AskAssistant
	}
} -result {1 {Ask the assistant} {Ask the assistant}}

# ----------------------------------------------------------------------
# Esc and focus.
# ----------------------------------------------------------------------
tcltest::test ask-esc-closes-and-restores-focus {Esc closes the list and returns the old focus} -body {
	::scidb::test::ask::isolated {
		catch { destroy .asktest }
		toplevel .asktest
		ttk::entry .asktest.e
		pack .asktest.e
		update
		focus -force .asktest.e
		::application::ask::Focus
		set inField [expr {[focus] eq [::application::ask::Entry]}]
		::scidb::test::ask::type "new game"
		::application::ask::Escape
		update idletasks
		set result [list $inField [focus] [::application::ask::ListVisible]]
		destroy .asktest
		set result
	}
} -result {1 .asktest.e 0}

tcltest::test ask-ctrl-k-keeps-kill-line {Ctrl+K inside a Text editor does not steal focus; Ctrl+Shift+K does} -body {
	::scidb::test::ask::isolated {
		catch { destroy .asktest }
		toplevel .asktest
		text .asktest.t
		pack .asktest.t
		update
		focus -force .asktest.t
		::application::ask::CtrlK
		set afterK [focus]
		::application::ask::CtrlShiftK
		set afterShift [focus]
		set result [list [expr {$afterK eq ".asktest.t"}] \
			[expr {$afterShift eq [::application::ask::Entry]}]]
		destroy .asktest
		set result
	}
} -result {1 1}

# GAP-001 (terminal review 7): the private AskShortcut tag runs before the
# widget class, so Ctrl+K must stop the binding chain when it handles the
# key. Otherwise the class Control-k binding (TEntry/Entry: delete from the
# cursor to end) wipes the Ask field or truncates another single-line entry.
tcltest::test ask-ctrl-k-keeps-field-text {Ctrl+K in the Ask field keeps and selects its text} -body {
	set entry [::application::ask::Entry]
	set savedQuery $::application::ask::Query
	$entry delete 0 end
	$entry insert 0 "flip board"
	$entry icursor 0
	focus -force $entry
	update
	event generate $entry <Control-Key-k>
	update
	set result [list [$entry get] [$entry selection present] [focus]]
	$entry delete 0 end
	::application::ask::Typed ""
	set ::application::ask::Query $savedQuery
	set result
} -result {{flip board} 1 .application.nb.ask.entry}

tcltest::test ask-ctrl-k-keeps-other-entry-text {Ctrl+K in another single-line entry keeps its text} -body {
	catch { destroy .application.__askgap }
	frame .application.__askgap
	place .application.__askgap -x 2 -y 2 -width 160 -height 60
	ttk::entry .application.__askgap.te
	entry .application.__askgap.e
	pack .application.__askgap.te .application.__askgap.e -fill x
	update
	set out {}
	foreach entry {.application.__askgap.te .application.__askgap.e} {
		$entry delete 0 end
		$entry insert 0 "hello world"
		$entry icursor 2
		focus -force $entry
		update
		set tagged [expr {"AskShortcut" in [bindtags $entry]}]
		event generate $entry <Control-Key-k>
		update
		lappend out [list $tagged [$entry get] [focus]]
	}
	destroy .application.__askgap
	set out
} -result {{1 {hello world} .application.nb.ask.entry} {1 {hello world} .application.nb.ask.entry}}

tcltest::test ask-ctrl-k-multiline-still-kills-line {Ctrl+K in a mapped Text editor keeps kill-line and Ctrl+Shift+K focuses Ask} -body {
	catch { destroy .application.__askgap }
	frame .application.__askgap
	place .application.__askgap -x 2 -y 2 -width 160 -height 80
	text .application.__askgap.t -width 20 -height 3
	pack .application.__askgap.t -fill both -expand yes
	update
	set editor .application.__askgap.t
	$editor insert 1.0 "one\ntwo"
	$editor mark set insert 1.1
	focus -force $editor
	update
	set tagged [expr {"AskShortcut" in [bindtags $editor]}]
	event generate $editor <Control-Key-k>
	update
	set afterK [list [$editor get 1.0 1.end] [focus]]
	event generate $editor <Control-Key-K>
	update
	set afterShiftK [list [$editor get 1.0 1.end] [focus]]
	destroy .application.__askgap
	list $tagged $afterK $afterShiftK
} -result {1 {o .application.__askgap.t} {o .application.nb.ask.entry}}

tcltest::test ask-command-k-aqua-breaks-on-entry {mirrored aqua Command-k breaks outside multiline editors} -setup {
	set savedMirrored [array names ::menu::Mirrored]
	set hadCmdK [bind AskShortcut <Command-Key-k>]
	rename ::tk ::scidb::test::ask::RealTk
	proc ::tk {args} {
		if {$args eq "windowingsystem"} { return aqua }
		return [uplevel 1 [list ::scidb::test::ask::RealTk {*}$args]]
	}
} -body {
	::menu::MirrorCommandBindings
	set cmdK [bind AskShortcut <Command-Key-k>]
	catch { destroy .application.__askgap }
	frame .application.__askgap
	place .application.__askgap -x 2 -y 2 -width 160 -height 28
	ttk::entry .application.__askgap.e
	pack .application.__askgap.e -fill both -expand yes
	update
	.application.__askgap.e insert 0 "hello world"
	.application.__askgap.e icursor 2
	focus -force .application.__askgap.e
	update
	set rc [catch { uplevel #0 $cmdK }]
	set result [list [expr {$cmdK eq [bind AskShortcut <Control-Key-k>]}] \
		$rc [.application.__askgap.e get] [focus]]
	destroy .application.__askgap
	set result
} -cleanup {
	if {[llength [info commands ::scidb::test::ask::RealTk]]} {
		rename ::tk {}
		rename ::scidb::test::ask::RealTk ::tk
	}
	catch { destroy .application.__askgap }
	foreach key [array names ::menu::Mirrored] {
		if {$key in $savedMirrored} continue
		set comma [string first , $key]
		if {$comma < 0} continue
		catch { bind [string range $key 0 [expr {$comma - 1}]] [string range $key [expr {$comma + 1}] end] {} }
		catch { unset ::menu::Mirrored($key) }
	}
	catch { bind AskShortcut <Command-Key-k> $hadCmdK }
} -result {1 3 {hello world} .application.nb.ask.entry}

tcltest::test ask-key-editor-reports-precedence {the key editor explains the Ctrl+K precedence} -body {
	set text [::application::keyEditor::Conflict some.action Control-k]
	list [expr {[string match {*Ctrl+K*} $text]}] \
		[expr {[string match {*Ctrl+Shift+K*} $text]}] \
		[expr {[string match {*kill-line*} $text]}]
} -result {1 1 1}

tcltest::test ask-history-from-assistant {Up in the empty field recalls the shared history} -body {
	::scidb::test::ask::isolated {
		set ::application::assistant::History [list {first request} {second request}]
		::application::ask::HistoryStep -1
		set once $::application::ask::Query
		::application::ask::HistoryStep -1
		set twice $::application::ask::Query
		::application::ask::HistoryStep 1
		set back $::application::ask::Query
		list $once $twice $back
	}
} -result {{second request} {first request} {second request}}

# ----------------------------------------------------------------------
# State rules and absent modules (VAL-RULE-004).
# ----------------------------------------------------------------------
tcltest::test ask-asklist-follows-capability {an absent optional module removes the action from the list} -body {
	::scidb::test::ask::isolated {
		::action::register test.ask.cap [dict create \
			label "Zebra Capability Action" object {} \
			handler ::scidb::test::ask::ran what "" doc "" \
			visible {::capability::present studyplan} enabled ::scidb::test::ask::yes]
		::capability::Override studyplan 1
		set idsOn {}
		foreach row [::action::labels asklist "zebra capability"] { lappend idsOn [lindex $row 0] }
		set stateOn [::menu::state test.ask.cap]
		::capability::Override studyplan 0
		set idsOff {}
		foreach row [::action::labels asklist "zebra capability"] { lappend idsOff [lindex $row 0] }
		set stateOff [::menu::state test.ask.cap]
		::capability::ClearOverrides
		::scidb::test::ask::forget test.ask.cap
		list [expr {[lsearch -exact $idsOn test.ask.cap] >= 0}] \
			[expr {[lsearch -exact $idsOff test.ask.cap] < 0}] \
			[dict get $stateOn visible] [dict get $stateOff visible]
	}
} -result {1 1 1 0}

tcltest::test ask-asklist-uses-dropdown-predicates {every listed action is enabled and visible in the menu state} -body {
	::scidb::test::ask::isolated {
		set bad {}
		set checked 0
		foreach row [::action::labels asklist ""] {
			set id [lindex $row 0]
			if {[catch { ::menu::state $id } state]} { continue }
			incr checked
			if {![dict get $state visible] || ![dict get $state enabled]} {
				lappend bad $id
			}
		}
		list [llength $bad] [expr {$checked > 100}]
	}
} -result {0 1}

tcltest::test ask-asklist-error-predicate-matches-menu-state {a raising predicate is treated as shown, as the menu state does} -body {
	::scidb::test::ask::isolated {
		::action::register test.ask.broken [dict create \
			label "Zebra Broken Predicate" object {} \
			handler ::scidb::test::ask::ran what "" doc "" \
			visible ::scidb::test::ask::explode enabled ::scidb::test::ask::yes]
		set ids {}
		foreach row [::action::labels asklist "zebra broken"] { lappend ids [lindex $row 0] }
		set state [::menu::state test.ask.broken]
		::scidb::test::ask::forget test.ask.broken
		list [expr {[lsearch -exact $ids test.ask.broken] >= 0}] \
			[dict get $state visible]
	}
} -result {1 1}

# ----------------------------------------------------------------------
# Board focus (VAL-PAL-002).
# ----------------------------------------------------------------------
tcltest::test ask-board-keystroke-stays-on-board {the board owns its keys and a key on a focused canvas never edits the field} -body {
	::scidb::test::ask::isolated {
		set board [::application::ask::BoardWidget]
		if {$board eq ""} { return {no-board} }
		# the board widget has its own key binding (it ends in break)
		set hasBinding [expr {[bind $board <Key-e>] ne ""}]
		# typing on a focused non-entry widget leaves the field alone
		catch { destroy .asktest }
		toplevel .asktest
		canvas .asktest.c -takefocus 1
		pack .asktest.c -fill both -expand yes
		update
		focus -force .asktest.c
		update
		set focused [expr {[focus] eq ".asktest.c"}]
		event generate .asktest.c <KeyPress-e>
		event generate .asktest.c <KeyRelease-e>
		update
		set result [list $hasBinding $focused $::application::ask::Query]
		destroy .asktest
		set result
	}
} -result {1 1 {}}

# ----------------------------------------------------------------------
# Keystroke budget (VAL-PAL-001: p95 < 100 ms, stage-1 plus 400 actions).
# ----------------------------------------------------------------------
tcltest::test ask-keystroke-budget {p95 of one keystroke is under 100 ms on a 400-action registry} -body {
	::scidb::test::ask::isolated {
		variable Synthetics
		set Synthetics {}
		for {set i 0} {$i < 400} {incr i} {
			set id [format "test.ask.syn%03d" $i]
			::action::register $id [dict create \
				label [format "Synthetic Zebra Action %03d" $i] \
				object {} handler ::scidb::test::ask::ran what "" doc "synthetic entry"]
			lappend Synthetics $id
		}
		set entry [::application::ask::Entry]
		# warm up the first list build (toplevel + fonts) outside the sample
		$entry delete 0 end
		$entry insert 0 "zebra"
		::application::ask::Typed ""
		update idletasks
		::application::ask::HideList
		set times {}
		set text ""
		foreach ch [split "zebra action" ""] {
			append text $ch
			set t0 [clock microseconds]
			$entry delete 0 end
			$entry insert 0 $text
			::application::ask::Typed ""
			update idletasks
			lappend times [expr {([clock microseconds] - $t0) / 1000.0}]
		}
		set p95 [::scidb::test::ask::Percentile $times 0.95]
		puts "EVIDENCE ask-keystroke p95Ms=$p95 samplesMs=$times"
		::scidb::test::ask::forget {*}$Synthetics
		set Synthetics {}
		list [expr {$p95 < 100}] [expr {[llength $times] >= 10}]
	}
} -match glob -result {1 1}

tcltest::test ask-pgn-editor-ctrl-k-precedence {real PGN text editor keeps Ctrl+K kill-line and Ctrl+Shift+K focus across language switches} -setup {
	set savedLang $::mc::langID
	set savedTab [::application::activeTab]
	set addedGame ""
	::application::switchTab board
	update
	if {[::application::pgn::empty?]} {
		::menu::gameNew .application
		update
		set addedGame [::gamebar::selected $::application::pgn::Vars(gamebar)]
	}
	set slot [::scidb::game::current]
	if {$slot < 0 || $slot > 8} { set slot 0 }
	::application::pgn::select $slot
	# Raise the PGN editor pane if the startup assistant panel is stacked on top.
	set editorFrame [winfo parent [winfo parent $::application::pgn::Vars(main)]]
	foreach mw [winfo children .application.nb.board] {
		if {[string match *__multiwindow__* $mw]} {
			catch { $mw raise $editorFrame }
		}
	}
	update
	set pgn $::application::pgn::Vars(pgn:$slot)
	set savedState [$pgn cget -state]
	set savedText [$pgn get 1.0 end-1c]
	set savedFocus [focus]
	set savedMirrored [array names ::menu::Mirrored]
} -body {
	# Switching en -> de -> en used to leave zombie FilterKey/break bindings
	# for Control-k/Control-K on PGN because German binds edit-comment to K.
	::menu::SwitchLanguage de
	update
	::menu::SwitchLanguage en
	update
	set enCtrlK [bind $pgn <Control-Key-k>]
	set enCtrlShiftK [bind $pgn <Control-Key-K>]

	# In English (after visiting German): editable PGN must kill-line on Ctrl+K
	# and focus Ask on Ctrl+Shift+K, just like the Comment editor.
	$pgn configure -state normal
	$pgn delete 1.0 end
	$pgn insert 1.0 "pgn text line"
	$pgn mark set insert 1.3
	focus -force $pgn
	update
	event generate $pgn <Control-Key-k>
	update
	set enAfterK [list [$pgn get 1.0 end-1c] [expr {[focus] eq $pgn}]]
	event generate $pgn <Control-Key-K>
	update
	set enAfterShiftK [list [$pgn get 1.0 end-1c] [expr {[focus] eq [::application::ask::Entry]}]]

	# While in German (where board Accel(edit-comment) is K): editable PGN
	# must still kill-line on Ctrl+K and focus Ask on Ctrl+Shift+K.
	::menu::SwitchLanguage de
	update
	$pgn configure -state normal
	$pgn delete 1.0 end
	$pgn insert 1.0 "pgn text line"
	$pgn mark set insert 1.3
	focus -force $pgn
	update
	event generate $pgn <Control-Key-k>
	update
	set deAfterK [list [$pgn get 1.0 end-1c] [expr {[focus] eq $pgn}]]
	event generate $pgn <Control-Key-K>
	update
	set deAfterShiftK [list [$pgn get 1.0 end-1c] [expr {[focus] eq [::application::ask::Entry]}]]

	# Simulated Aqua Command mirror: de -> en must clear mirrored Command-k on PGN.
	rename ::tk ::scidb::test::ask::RealTkPgn
	proc ::tk {args} {
		if {$args eq "windowingsystem"} { return aqua }
		return [uplevel 1 [list ::scidb::test::ask::RealTkPgn {*}$args]]
	}
	::menu::MirrorCommandBindings
	::menu::SwitchLanguage en
	update
	set aquaCmdK [bind $pgn <Command-Key-k>]
	set aquaCmdShiftK [bind $pgn <Command-Key-K>]
	rename ::tk {}
	rename ::scidb::test::ask::RealTkPgn ::tk

	list [expr {$enCtrlK eq ""}] [expr {$enCtrlShiftK eq ""}] \
		$enAfterK $enAfterShiftK $deAfterK $deAfterShiftK \
		[expr {$aquaCmdK eq ""}] [expr {$aquaCmdShiftK eq ""}]
} -cleanup {
	if {[llength [info commands ::scidb::test::ask::RealTkPgn]]} {
		rename ::tk {}
		rename ::scidb::test::ask::RealTkPgn ::tk
	}
	foreach key [array names ::menu::Mirrored] {
		if {$key in $savedMirrored} continue
		set comma [string first , $key]
		if {$comma < 0} continue
		catch { bind [string range $key 0 [expr {$comma - 1}]] [string range $key [expr {$comma + 1}] end] {} }
		catch { unset ::menu::Mirrored($key) }
	}
	catch { ::menu::SwitchLanguage $savedLang }
	catch {
		$pgn configure -state normal
		$pgn delete 1.0 end
		$pgn insert 1.0 $savedText
		$pgn configure -state $savedState
	}
	if {$addedGame ne ""} {
		catch { ::gamebar::remove $::application::pgn::Vars(gamebar) $addedGame }
	}
	if {$savedTab ne ""} { catch { ::application::switchTab $savedTab } }
	if {$savedFocus ne "" && [winfo exists $savedFocus]} { catch { focus $savedFocus } }
	update
} -result {1 1 {pgn 1} {pgn 1} {pgn 1} {pgn 1} 1 1}

tcltest::test ask-keystroke-no-label-recompute {synthetic-400 keystrokes do not recompute labels per keystroke and stay fast} -body {
	::scidb::test::ask::isolated {
		variable Synthetics
		set Synthetics {}
		for {set i 0} {$i < 400} {incr i} {
			set id [format "test.ask.nocmp%03d" $i]
			::action::register $id [dict create \
				label [format "Synthetic &Zebra Action %03d" $i] \
				object {} handler ::scidb::test::ask::ran what "" doc "synthetic entry"]
			lappend Synthetics $id
		}
		set entry [::application::ask::Entry]
		# Warm up cache + list once
		$entry delete 0 end
		$entry insert 0 "z"
		unset -nocomplain ::application::ask::Priv(filtered)
		::application::ask::Typed ""
		update idletasks

		set ::scidb::test::ask::ampCalls 0
		set ::scidb::test::ask::plainCalls 0
		set ::scidb::test::ask::markupCalls 0
		proc ::scidb::test::ask::_countAmp {args} { incr ::scidb::test::ask::ampCalls }
		proc ::scidb::test::ask::_countPlain {args} { incr ::scidb::test::ask::plainCalls }
		proc ::scidb::test::ask::_countMarkup {args} { incr ::scidb::test::ask::markupCalls }
		trace add execution ::menu::AmpText enter ::scidb::test::ask::_countAmp
		trace add execution ::action::plainText enter ::scidb::test::ask::_countPlain
		trace add execution ::action::markupLabel enter ::scidb::test::ask::_countMarkup

		set times {}
		set text "z"
		foreach ch [split "ebra action" ""] {
			append text $ch
			set t0 [clock microseconds]
			$entry delete 0 end
			$entry insert 0 $text
			::application::ask::Typed ""
			update idletasks
			lappend times [expr {([clock microseconds] - $t0) / 1000.0}]
		}
		trace remove execution ::menu::AmpText enter ::scidb::test::ask::_countAmp
		trace remove execution ::action::plainText enter ::scidb::test::ask::_countPlain
		trace remove execution ::action::markupLabel enter ::scidb::test::ask::_countMarkup

		set p95 [::scidb::test::ask::Percentile $times 0.95]
		set list .application.askList.list
		set expectedRows [::action::labels asklist $text]
		set listCount [$list size]
		set exactCount [expr {$listCount == [llength $expectedRows] + 1}]
		set noAmp [expr {[string first "&" [join [$list get 0 end] \n]] < 0}]
		puts "EVIDENCE ask-no-recompute p95Ms=$p95 amp=$::scidb::test::ask::ampCalls plain=$::scidb::test::ask::plainCalls markup=$::scidb::test::ask::markupCalls rows=$listCount"
		::scidb::test::ask::forget {*}$Synthetics
		::action::NoteRegistryChange
		set Synthetics {}
		list [expr {$p95 < 100}] \
			$::scidb::test::ask::ampCalls \
			$::scidb::test::ask::plainCalls \
			$::scidb::test::ask::markupCalls \
			$exactCount $noAmp
	}
} -result {1 0 0 0 1 1}

tcltest::test ask-cache-invalidation-language-theme-registry {open Ask rows and all caches update on language switch, theme change, relabel, and registry/context changes} -setup {
	set savedLang $::mc::langID
	set savedTheme [::theme::currentTheme]
	set savedQuery $::application::ask::Query
	::menu::SwitchLanguage en
	update
	set ::application::ask::Query Annotations
	focus -force [::application::ask::Entry]
	unset -nocomplain ::application::ask::Priv(filtered)
	::application::ask::Typed {}
	update
} -body {
	set enRows $::application::ask::Priv(rows)
	set enText [string trim [.application.askList.list get 0]]
	set enListText [string trim [lindex $::application::ask::ListTexts 0]]

	# 1. Language switch en -> de while Ask list is open must recompute Priv(rows)
	#    and redraw visible rows in German (not stale English FmtCache/Priv(rows)).
	::menu::SwitchLanguage de
	update
	set deRows $::application::ask::Priv(rows)
	set deExpected [::action::labels asklist Annotations]
	set deVisible [string trim [.application.askList.list get 0]]
	set deListText [string trim [lindex $::application::ask::ListTexts 0]]
	set deExpectedText [string trim [lindex [::menu::AmpText [lindex $deExpected 0 1]] 0]]
	set deOk [expr {$deRows eq $deExpected && $deVisible eq $deExpectedText && $deListText eq $deExpectedText && $deVisible ne $enText}]

	# 2. Switch back de -> en while still open must restore English rows.
	::menu::SwitchLanguage en
	update
	set backRows $::application::ask::Priv(rows)
	set backExpected [::action::labels asklist Annotations]
	set backVisible [string trim [.application.askList.list get 0]]
	set backOk [expr {$backRows eq $backExpected && $backVisible eq $enText}]

	# 3. Theme change while open must invalidate cached geometry/metrics/rows cleanly.
	set otherTheme [expr {$savedTheme eq "dark" ? "clam" : "dark"}]
	::theme::setTheme $otherTheme
	update
	set themeVisible [string trim [.application.askList.list get 0]]
	set themeOk [expr {[::application::ask::ListVisible] && $themeVisible eq $enText}]

	# 4. Registry add/remove and label update must invalidate AskMetaCache,
	#    AskLiveScriptsKey, FmtCache, and Priv(filtered).
	::scidb::test::ask::action test.ask.cacheinv "Zebra Cache Invalidator" {}
	set afterAdd [expr {"test.ask.cacheinv" in [lmap r [::action::labels asklist "Zebra Cache Invalidator"] {lindex $r 0}]}]
	set metaBefore [dict exists $::action::AskMetaCache test.ask.cacheinv]
	::action::Unregister test.ask.cacheinv
	set afterRemove [expr {"test.ask.cacheinv" ni [lmap r [::action::labels asklist "Zebra Cache Invalidator"] {lindex $r 0}]}]
	set metaAfterUnreg [dict exists $::action::AskMetaCache test.ask.cacheinv]
	set regOk [expr {$afterAdd && $metaBefore && $afterRemove && !$metaAfterUnreg}]

	# 5. Context cascade definition updates must invalidate CascadeIdSet.
	set savedMenus $::context::Menus
	set hadFakeBefore [dict exists [::context::EnsureCascadeIdSet] test.ask.fake_cascade]
	::context::Define C99 {{cascade test.ask.fake_cascade {test.ask.fake_child}}}
	set hasFakeAfter [dict exists [::context::EnsureCascadeIdSet] test.ask.fake_cascade]
	set ::context::Menus $savedMenus
	if {[llength [info commands ::context::InvalidateCascadeIdSet]]} {
		::context::InvalidateCascadeIdSet
	}
	set ctxOk [expr {!$hadFakeBefore && $hasFakeAfter}]

	list $deOk $backOk $themeOk $regOk $ctxOk
} -cleanup {
	catch { ::action::Unregister test.ask.cacheinv }
	catch { ::theme::setTheme $savedTheme }
	catch { ::menu::SwitchLanguage $savedLang }
	set ::application::ask::Query $savedQuery
	::application::ask::HideList
	::application::ask::PlaceholderState
	update
} -result {1 1 1 1 1}

tcltest::cleanupTests
