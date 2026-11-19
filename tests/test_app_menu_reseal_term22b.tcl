# ======================================================================
# Terminal review 6 GAP-003/004/005 (W-term22b)
# ======================================================================
# GAP-003: the Ask result list prints action labels as text; Tk menu
# mnemonics ("&Quit") must not appear there, and "&&" must stay one
# literal ampersand. The same rule covers knowledge, assistant offers,
# the key editor and toolbar tooltips.
# GAP-004: every registered menu action keeps a real translation in every
# language loaded from tcl/lang/localization.tcl, or is explicitly
# allowlisted as a proper/technical name.
# GAP-005: on aqua the Command twins of the Ask bindtag make Cmd+Shift+K
# win over multiline Text/Script class bindings, and the placeholder
# advertises Cmd+K.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

namespace eval ::scidb::test::term22b {}

# The app bundle bakes in the installed share directory. Read the language
# files of this worktree instead (the same rule as the other i18n tests).
set ::scidb::test::term22b::savedShare $::scidb::dir::share
set ::scidb::test::term22b::worktreeShare [file normalize [file join \
	[file dirname [file normalize [info script]]] .. tcl]]
if {[file isdirectory [file join $::scidb::test::term22b::worktreeShare lang]]} {
	set ::scidb::dir::share $::scidb::test::term22b::worktreeShare
}

proc ::scidb::test::term22b::Languages {} {
	return $::i18n::languages
}

proc ::scidb::test::term22b::Names {} {
	return [lmap entry $::i18n::languages {lindex $entry 0}]
}

proc ::scidb::test::term22b::Codes {} {
	return [lmap entry $::i18n::languages {lindex $entry 1}]
}

# The rows the Ask list actually paints, in the language in force.
proc ::scidb::test::term22b::AskLines {lang} {
	::menu::SwitchLanguage $lang
	catch { ::application::ask::HideList }
	set ::application::ask::Priv(rows) [::action::labels asklist ""]
	catch { ::application::ask::ShowList }
	set w .application.askList.list
	set lines {}
	if {[winfo exists $w]} { set lines [$w get 0 end] }
	catch { ::application::ask::HideList }
	return $lines
}

# Registered menu actions, excluding the 09.950 block: those are API-only
# dynamic targets (View > Theme/Colors/Icon size/Language/Layout) whose
# posted rows use the ::menu::mc keys; their registry label is an
# assistant-facing description, not menu text.
proc ::scidb::test::term22b::MenuLabels {lang} {
	::menu::SwitchLanguage $lang
	set out [dict create]
	foreach id [::action::list] {
		set rec [::action::get $id]
		if {[dict get $rec dropdown] eq ""} continue
		if {[string match "09.950*" [dict get $rec dropdown]]} continue
		dict set out $id [dict get $rec label]
	}
	return $out
}

# Names this product legitimately spells the same in a language and English.
proc ::scidb::test::term22b::SameOK {} {
	return [list \
		Three-check \
		Crazyhouse \
		{Standard} \
		{PayPal} \
		{Ko-fi} \
	]
}

proc ::scidb::test::term22b::Clean {} {
	catch { ::application::ask::HideList }
	catch { set ::application::ask::Priv(rows) {} }
	catch { set ::application::ask::Priv(index) 0 }
	catch { ::application::ask::PlaceholderState }
	catch { ::menu::SwitchLanguage English }
	return
}

# ----------------------------------------------------------------------
# GAP-003: no mnemonic ampersands on the Ask surface (VAL-PAL).
# ----------------------------------------------------------------------
tcltest::test term22b-ask-no-mnemonics {no Ask row in any registered language shows a single & mnemonic} -body {
	set bad {}
	set checked 0
	foreach entry [::scidb::test::term22b::Languages] {
		lassign $entry name code
		set lines [::scidb::test::term22b::AskLines $name]
		if {[llength $lines] < 100} { lappend bad [list $code short [llength $lines]] }
		incr checked [llength $lines]
		foreach line $lines {
			# A displayed literal ampersand ("A && B" -> "A & B") is
			# fine, but no label may carry a lone menu marker. No
			# shipped label has a literal ampersand today, so the
			# stricter check is the useful regression guard.
			if {[string first "&" $line] >= 0} {
				lappend bad [list $code [string trim $line]]
			}
		}
	}
	::scidb::test::term22b::Clean
	list $bad [expr {$checked > 1000}]
} -result {{} 1}

tcltest::test term22b-ask-ampersand-handling {&& stays one literal ampersand and & before a letter is a mnemonic} -body {
	set savedRows $::application::ask::Priv(rows)
	set savedIndex $::application::ask::Priv(index)
	set ::application::ask::Priv(rows) {
		{test.term22b.file  {&File}         "Ctrl+O" 1 1}
		{test.term22b.lit   {Save && Exit}  ""       1 1}
		{test.term22b.plain {R&&D}          ""       1 1}
	}
	set ::application::ask::Priv(index) 0
	set w [::application::ask::ShowList]
	set lines [$w.list get 0 end]
	::application::ask::HideList
	set ::application::ask::Priv(rows) $savedRows
	set ::application::ask::Priv(index) $savedIndex
	list \
		[regexp {^ File +Ctrl\+O$} [lindex $lines 0]] \
		[regexp {^ Save & Exit *$} [lindex $lines 1]] \
		[regexp {^ R&D *$} [lindex $lines 2]] \
		[::action::plainText "&Quit"] \
		[::action::plainText "Save && Exit"] \
		[::action::plainText "R&&D"]
} -result {1 1 1 Quit {Save & Exit} R&D}

tcltest::test term22b-text-surfaces-strip-mnemonics {knowledge, assistant, key editor and tooltips print plain labels} -body {
	set ::scidb::test::term22b::ActionLabel "&Apply"
	set ::scidb::test::term22b::LiteralLabel "Save && Exit..."
	list \
		[::knowledge::LabelText "&Support Chesswiz\u2026"] \
		[::action::displayLabel "&Quit"] \
		[::action::displayLabel "Save && Exit"] \
		[::application::keyEditor::ActionLabel test.term22b ::scidb::test::term22b::ActionLabel] \
		[::application::keyEditor::ActionLabel test.term22b ::scidb::test::term22b::LiteralLabel] \
		[::action::plainText "&Start Engine"] \
		[::action::plainText "Drag && Drop"]
} -result {{Support Chesswiz} Quit {Save & Exit} Apply {Save & Exit} {Start Engine} {Drag & Drop}}

# ----------------------------------------------------------------------
# GAP-004: registered menu labels are translated (VAL-BAR-007).
# ----------------------------------------------------------------------
tcltest::test term22b-registered-labels-translated {every registered menu label differs from English or is allowlisted, in every language} -body {
	set english [::scidb::test::term22b::MenuLabels English]
	if {[dict size $english] < 150} { return [list short-english [dict size $english]] }
	set allow [::scidb::test::term22b::SameOK]
	set bad {}
	set report {}
	foreach entry [::scidb::test::term22b::Languages] {
		lassign $entry name code
		if {$code eq "en"} continue
		set local [::scidb::test::term22b::MenuLabels $name]
		set same {}
		foreach id [dict keys $english] {
			if {![dict exists $local $id]} { lappend bad [list $code missing $id]; continue }
			set en [dict get $english $id]
			set loc [dict get $local $id]
			if {$loc eq $en && [lsearch -exact $allow $en] < 0} {
				lappend same [list $id $en]
				lappend bad [list $code identical $id $en]
			}
		}
		lappend report [list $code [llength $same] [dict size $local]]
	}
	::scidb::test::term22b::Clean
	puts "term22b translations: $report"
	foreach item $bad { puts "  BAD $item" }
	list $bad [llength $report]
} -result {{} 5}

tcltest::test term22b-lichess-and-extras-translated {ExportLichess, UploadStudy and the pane/focus extras relabel in every language} -body {
	set ids {menu.file.export.lichess menu.game.export.study \
		view.pane_zoom view.focus_zoom view.focus_ratio view.focus_pin}
	::menu::SwitchLanguage English
	set english {}
	foreach id $ids { lappend english [dict get [::action::get $id] label] }
	set bad {}
	set seen 0
	foreach entry [::scidb::test::term22b::Languages] {
		lassign $entry name code
		if {$code eq "en"} continue
		::menu::SwitchLanguage $name
		incr seen
		foreach id $ids en $english {
			set loc [dict get [::action::get $id] label]
			if {$loc eq "" || $loc eq $en} { lappend bad [list $code $id $loc] }
		}
	}
	::scidb::test::term22b::Clean
	list $bad $seen
} -result {{} 5}

tcltest::test term22b-extras-use-mc-catalog {RegisterExtras uses the translated catalog keys and follows a live switch} -body {
	::menu::SwitchLanguage English
	set english [list [dict get [::action::get view.pane_zoom] label] \
		[dict get [::action::get view.focus_zoom] label] \
		[dict get [::action::get view.focus_ratio] label] \
		[dict get [::action::get view.focus_pin] label]]
	set de [expr {[::menu::SwitchLanguage Deutsch] ne ""}]
	set german [list [dict get [::action::get view.pane_zoom] label] \
		[dict get [::action::get view.focus_zoom] label] \
		[dict get [::action::get view.focus_ratio] label] \
		[dict get [::action::get view.focus_pin] label]]
	set germanMC $::menu::mc::MaximisePane
	::scidb::test::term22b::Clean
	list $english $german \
		[expr {$german ne $english}] \
		[expr {[lindex $german 0] eq $germanMC}] \
		$de
} -result [list \
	[list "&Maximise / Restore Pane" "Focus &follows size" "Zoom &ratio" "&Pin board size"] \
	[list "Bereich &maximieren / wiederherstellen" "Fokus folgt der &Größe" "&Zoomfaktor" "&Brettgröße fixieren"] \
	1 1 1]

# ----------------------------------------------------------------------
# GAP-005: aqua mirrors the Ask bindtag and advertises Cmd+K (VAL-CROSS).
# ----------------------------------------------------------------------
proc ::scidb::test::term22b::FakeAqua {} {
	rename ::tk ::scidb::test::term22b::RealTk
	proc ::tk {args} {
		if {$args eq "windowingsystem"} { return aqua }
		return [uplevel 1 [list ::scidb::test::term22b::RealTk {*}$args]]
	}
}

proc ::scidb::test::term22b::RealAqua {} {
	if {[llength [info commands ::scidb::test::term22b::RealTk]] == 0} { return }
	rename ::tk {}
	rename ::scidb::test::term22b::RealTk ::tk
}

tcltest::test term22b-aqua-ask-bindtag {aqua mirrors Command to the AskShortcut tag ahead of Text} -setup {
	set ::scidb::test::term22b::mirrored [array names ::menu::Mirrored]
	set ::scidb::test::term22b::hadCmdK [bind AskShortcut <Command-Key-k>]
	set ::scidb::test::term22b::hadCmdShiftK [bind AskShortcut <Command-Key-K>]
} -body {
	set controlK [bind AskShortcut <Control-Key-k>]
	set controlShiftK [bind AskShortcut <Control-Key-K>]
	::scidb::test::term22b::FakeAqua
	::menu::MirrorCommandBindings
	set cmdK [bind AskShortcut <Command-Key-k>]
	set cmdShiftK [bind AskShortcut <Command-Key-K>]
	catch { destroy .application.term22btext }
	text .application.term22btext -width 20 -height 3
	::application::ask::AttachShortcutTag .application.term22btext
	set tags [bindtags .application.term22btext]
	set askAt [lsearch -exact $tags AskShortcut]
	set textAt [lsearch -exact $tags Text]
	# The Command twin must run the same handler as the Control binding:
	# from a multiline editor it focuses the Ask entry.
	set savedBefore $::application::ask::Priv(focusBefore)
	focus -force .application.term22btext
	catch { uplevel #0 [bind AskShortcut <Command-Key-K>] }
	set focused [focus]
	set ::application::ask::Priv(focusBefore) $savedBefore
	::scidb::test::term22b::RealAqua
	list \
		[expr {$cmdK eq $controlK}] \
		[expr {$cmdShiftK eq $controlShiftK}] \
		[expr {$askAt >= 0 && $textAt >= 0 && $askAt < $textAt}] \
		[expr {$focused eq [::application::ask::Entry]}] \
		$controlK $controlShiftK
} -cleanup {
	catch { ::scidb::test::term22b::RealAqua }
	catch { destroy .application.term22btext }
	# Remove only the Command twins this test created.
	foreach key [array names ::menu::Mirrored] {
		if {[lsearch -exact $::scidb::test::term22b::mirrored $key] >= 0} continue
		set comma [string first , $key]
		if {$comma < 0} continue
		set tag [string range $key 0 [expr {$comma - 1}]]
		set seq [string range $key [expr {$comma + 1}] end]
		catch { bind $tag $seq {} }
		catch { unset ::menu::Mirrored($key) }
	}
	catch { bind AskShortcut <Command-Key-k> $::scidb::test::term22b::hadCmdK }
	catch { bind AskShortcut <Command-Key-K> $::scidb::test::term22b::hadCmdShiftK }
} -result [list 1 1 1 1 {::application::ask::CtrlK} {::application::ask::CtrlShiftK; break}]

tcltest::test term22b-aqua-placeholder {the Ask placeholder says Cmd+K on aqua and keeps the language} -setup {
	set ::scidb::test::term22b::savedLang $::mc::langID
} -body {
	::scidb::test::term22b::FakeAqua
	::menu::SwitchLanguage English
	set english [::application::ask::PlaceholderText]
	::menu::SwitchLanguage Deutsch
	set german [::application::ask::PlaceholderText]
	set shown ""
	catch { ::application::ask::Relabel }
	if {[winfo exists .application.nb.ask.placeholder]} {
		set shown [.application.nb.ask.placeholder cget -text]
	}
	::scidb::test::term22b::RealAqua
	list \
		[expr {[string match {*Cmd+K*} $english] && ![string match {*Ctrl+K*} $english]}] \
		[expr {[string match {*Cmd+K*} $german] && ![string match {*Strg+K*} $german]}] \
		[expr {$shown eq $german}] \
		$english $german
} -cleanup {
	catch { ::scidb::test::term22b::RealAqua }
	::scidb::test::term22b::Clean
	catch { ::menu::SwitchLanguage $::scidb::test::term22b::savedLang }
} -result {1 1 1 {Ask or tell Chesswiz what to do (Cmd+K)} {Chesswiz fragen oder sagen, was zu tun ist (Cmd+K)}}

# Put the installed share directory back for the files that follow.
if {[info exists ::scidb::test::term22b::savedShare]} {
	set ::scidb::dir::share $::scidb::test::term22b::savedShare
}

tcltest::cleanupTests
