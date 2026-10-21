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

tcltest::cleanupTests
