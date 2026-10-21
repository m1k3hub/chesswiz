# ======================================================================
# Scidb App Test — the Ask field in the user's language
# (tcl/app-ask.tcl, tcl/lang/english.tcl, tcl/lang/deutsch.tcl)
# ======================================================================
# Run 197: with the UI in German the Ask field kept the English
# placeholder ("Ask or tell Chesswiz what to do (Ctrl+K)"). The field's
# text was set once, when it was built, so a language switch with the
# window open left it behind; the module's English text also had no
# entry in english.tcl, so switching back to English left the German
# strings in place.
#
# The field now binds <<LanguageChanged>> (i18n.tcl generates the event
# for every widget) and relabels in place: the placeholder label takes
# the new text, the microphone takes the label of the speech state it is
# in (Speak, or Recording/Transcribing while it is busy), an open result
# list is redrawn so its last row -- "Ask the assistant" -- follows, and
# an open Preferences > Assistant dialog relabels itself. The user's own
# typing is never touched. ResetMC, registered with ::mc::addDefaultReset,
# restores the English defaults before each language load, so a language
# without a translation of these strings shows English.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::askI18n {}

# The app bundle bakes in the installed share directory. Read the language
# files of this worktree instead, so the test verifies what we are about
# to commit rather than a stale system install.
set ::scidb::test::askI18n::savedShare $::scidb::dir::share
set ::scidb::test::askI18n::worktreeShare [file normalize [file join \
	[file dirname [file normalize [info script]]] .. tcl]]
if {[file isdirectory [file join $::scidb::test::askI18n::worktreeShare lang]]} {
	set ::scidb::dir::share $::scidb::test::askI18n::worktreeShare
}

set ::scidb::test::askI18n::placeholder .application.nb.ask.placeholder
set ::scidb::test::askI18n::list .application.askList.list
# the speech settings -setup saved, for -cleanup to put back
set ::scidb::test::askI18n::SavedSettings {}

proc ::scidb::test::askI18n::Placeholder {} {
	return $::scidb::test::askI18n::placeholder
}

# The placeholder's text and whether it is on screen (place) or not.
proc ::scidb::test::askI18n::shown {} {
	set w [::scidb::test::askI18n::Placeholder]
	return [list [$w cget -text] [winfo manager $w]]
}

# The last row of the open result list (the "Ask the assistant" row).
proc ::scidb::test::askI18n::LastRow {} {
	set w $::scidb::test::askI18n::list
	if {![winfo exists $w]} { return "" }
	return [string trim [$w get end]]
}

proc ::scidb::test::askI18n::Type {text} {
	set entry [::application::ask::Entry]
	$entry delete 0 end
	$entry insert 0 $text
	::application::ask::Typed ""
	catch { update idletasks }
	return $text
}

proc ::scidb::test::askI18n::Empty {} {
	catch { ::application::ask::HideList }
	set ::application::ask::Query ""
	catch { [::application::ask::Entry] delete 0 end }
	catch { ::application::ask::PlaceholderState }
	return
}

# The speech settings and state a test changes are put back by -cleanup,
# so a failing test cannot leave the microphone recording or a stub path
# behind for the files that follow.
proc ::scidb::test::askI18n::SaveSettings {} {
	set ::scidb::test::askI18n::SavedSettings [array get ::application::speech::Settings]
	return
}

# Back to English, an empty field, an idle microphone and the settings the
# suite started with; an open dialog is closed.
proc ::scidb::test::askI18n::Clean {} {
	variable SavedSettings
	if {[info exists SavedSettings] && [llength $SavedSettings]} {
		array set ::application::speech::Settings $SavedSettings
		set SavedSettings {}
	}
	catch { set ::application::speech::Priv(state) idle }
	catch { ::application::ask::SyncMic }
	catch { destroy .application.assistantPreferences }
	catch { ::menu::SwitchLanguage English }
	Empty
	return
}

# A language file overwrites the mc strings of every module; snapshot the
# two namespaces this file switches, and put them back, so a failing test
# cannot leave German text for the files that follow.
proc ::scidb::test::askI18n::snapshot {} {
	variable Saved
	set Saved {}
	foreach ns {::application::ask ::application::speech} {
		foreach v [info vars ${ns}::mc::*] {
			if {[array exists $v]} {
				lappend Saved [list array $v [array get $v]]
			} elseif {[info exists $v]} {
				lappend Saved [list scalar $v [set $v]]
			}
		}
	}
	return
}

proc ::scidb::test::askI18n::restore {} {
	variable Saved
	foreach entry $Saved {
		lassign $entry kind v value
		if {$kind eq "array"} {
			array unset $v
			array set $v $value
		} else {
			set $v $value
		}
	}
	return
}

::scidb::test::askI18n::snapshot

# ----------------------------------------------------------------------
# The placeholder.
# ----------------------------------------------------------------------
tcltest::test ask-i18n-placeholder {the placeholder follows a live language switch, without a restart} -body {
	::menu::SwitchLanguage English
	::scidb::test::askI18n::Empty
	set english [::scidb::test::askI18n::shown]
	::menu::SwitchLanguage Deutsch
	set german [::scidb::test::askI18n::shown]
	::menu::SwitchLanguage English
	set again [::scidb::test::askI18n::shown]
	::scidb::test::askI18n::Empty
	list $english $german [expr {$again eq $english}]
} -cleanup {
	::scidb::test::askI18n::Clean
} -result {{{Ask or tell Chesswiz what to do (Ctrl+K)} place} {{Chesswiz fragen oder sagen, was zu tun ist (Strg+K)} place} 1}

tcltest::test ask-i18n-typed-text-survives {a language switch never overwrites what was typed} -body {
	::menu::SwitchLanguage English
	::scidb::test::askI18n::Empty
	::scidb::test::askI18n::Type "new game"
	set typed [list [set ::application::ask::Query] \
		[[::application::ask::Entry] get] [lindex [::scidb::test::askI18n::shown] 1]]
	# the field is not empty: the placeholder is out of the way, and the
	# switch rewrites its text without putting it back or touching the text
	::menu::SwitchLanguage Deutsch
	set german [list [set ::application::ask::Query] \
		[[::application::ask::Entry] get] \
		[lindex [::scidb::test::askI18n::shown] 1] \
		[lindex [::scidb::test::askI18n::shown] 0]]
	::menu::SwitchLanguage English
	set again [list [set ::application::ask::Query] \
		[[::application::ask::Entry] get] [lindex [::scidb::test::askI18n::shown] 1]]
	::scidb::test::askI18n::Empty
	list $typed $german $again
} -cleanup {
	::scidb::test::askI18n::Clean
} -result {{{new game} {new game} {}} {{new game} {new game} {} {Chesswiz fragen oder sagen, was zu tun ist (Strg+K)}} {{new game} {new game} {}}}

# ----------------------------------------------------------------------
# The result list; its last row is the assistant row (also the row a
# query with no matching action shows).
# ----------------------------------------------------------------------
tcltest::test ask-i18n-assistant-row {the "Ask the assistant" row follows a live switch} -body {
	::menu::SwitchLanguage English
	::scidb::test::askI18n::Type "new game"
	set visible [::application::ask::ListVisible]
	set english [::scidb::test::askI18n::LastRow]
	# no retyping: the open list is redrawn in place
	::menu::SwitchLanguage Deutsch
	set german [::scidb::test::askI18n::LastRow]
	::menu::SwitchLanguage English
	set again [::scidb::test::askI18n::LastRow]
	::scidb::test::askI18n::Empty
	list $visible $english $german [expr {$again eq $english}]
} -cleanup {
	::scidb::test::askI18n::Clean
} -result {1 {Ask the assistant} {Den Assistenten fragen} 1}

tcltest::test ask-i18n-no-match-row {a query with no matching action shows the assistant row in the new language} -body {
	::menu::SwitchLanguage English
	::scidb::test::askI18n::Type "zzzznothingmatchesthis"
	set rows [llength $::application::ask::Priv(rows)]
	set english [::scidb::test::askI18n::LastRow]
	::menu::SwitchLanguage Deutsch
	set german [::scidb::test::askI18n::LastRow]
	::menu::SwitchLanguage English
	::scidb::test::askI18n::Empty
	list $rows $english $german
} -cleanup {
	::scidb::test::askI18n::Clean
} -result {0 {Ask the assistant} {Den Assistenten fragen}}

# ----------------------------------------------------------------------
# The microphone: its own label and the busy text while it records or
# transcribes, in the language in force.
# ----------------------------------------------------------------------
tcltest::test ask-i18n-mic-busy-text {the microphone's busy text follows the language and its state} -setup {
	::scidb::test::askI18n::SaveSettings
} -body {
	::application::speech::configure whisperCli /nonexistent/whisper-cli \
		whisperModel /nonexistent/model.bin recorder /nonexistent/arecord stub {return "hi"}
	::scidb::test::askI18n::Empty
	::menu::SwitchLanguage English
	set english [[::application::ask::Mic] cget -text]
	set ::application::speech::Priv(state) recording
	::menu::SwitchLanguage Deutsch
	set recording [[::application::ask::Mic] cget -text]
	set ::application::speech::Priv(state) transcribing
	::menu::SwitchLanguage English
	set transcribing [[::application::ask::Mic] cget -text]
	set ::application::speech::Priv(state) idle
	::menu::SwitchLanguage English
	set idle [[::application::ask::Mic] cget -text]
	list $english $recording $transcribing $idle
} -cleanup {
	::scidb::test::askI18n::Clean
} -result {Speak {Aufnahme… Klicken zum Stoppen} {Transcribing… click to cancel} Speak}

# ----------------------------------------------------------------------
# What a request brings back into the field.
# ----------------------------------------------------------------------
tcltest::test ask-i18n-request-messages {refusals and failures are reported in the user's language} -setup {
	rename ::application::assistant::ask ::scidb::test::askI18n::realAsk
	rename ::application::assistant::show ::scidb::test::askI18n::realShow
	proc ::application::assistant::show {} {}
	rename ::ui::message ::scidb::test::askI18n::realMessage
	set ::scidb::test::askI18n::Messages {}
	proc ::ui::message {message args} { lappend ::scidb::test::askI18n::Messages $message }
	::menu::SwitchLanguage Deutsch
} -body {
	proc ::application::assistant::ask {args} { return 0 }
	set ::application::ask::Query "a request"
	::application::ask::SendToAssistant
	set busy [lindex $::scidb::test::askI18n::Messages 0]
	proc ::application::assistant::ask {args} { error {offline} }
	::application::ask::SendToAssistant
	set failed [lindex $::scidb::test::askI18n::Messages 1]
	rename ::application::assistant::ask {}
	::application::ask::SendToAssistant
	set missing [lindex $::scidb::test::askI18n::Messages 2]
	list $busy $failed $missing
} -cleanup {
	catch { rename ::application::assistant::ask {} }
	rename ::scidb::test::askI18n::realAsk ::application::assistant::ask
	catch { rename ::application::assistant::show {} }
	rename ::scidb::test::askI18n::realShow ::application::assistant::show
	catch { rename ::ui::message {} }
	rename ::scidb::test::askI18n::realMessage ::ui::message
	::scidb::test::askI18n::Clean
} -result {{Der Assistent ist beschäftigt. Versuchen Sie es noch einmal, wenn er fertig ist.} {Fehler: offline} {Der Assistent ist nicht verfügbar.}}

# ----------------------------------------------------------------------
# Preferences > Assistant, if it is open when the language changes.
# ----------------------------------------------------------------------
tcltest::test ask-i18n-preferences-dialog {an open Preferences > Assistant relabels in place} -setup {
	::scidb::test::askI18n::SaveSettings
} -body {
	::application::speech::configure whisperCli /nonexistent/whisper-cli \
		whisperModel /nonexistent/model.bin recorder /nonexistent/arecord stub ""
	::menu::SwitchLanguage English
	catch { destroy .application.assistantPreferences }
	::application::ask::Preferences
	update idletasks
	set dlg .application.assistantPreferences
	set labels [list [wm title $dlg] [$dlg.content.title cget -text] \
		[$dlg.content.whisperCli.label cget -text] \
		[$dlg.content.buttons.detect cget -text] [$dlg.content.buttons.close cget -text]]
	set ehint [$dlg.content.hint cget -text]
	::menu::SwitchLanguage Deutsch
	set german [list [wm title $dlg] [$dlg.content.title cget -text] \
		[$dlg.content.whisperCli.label cget -text] \
		[$dlg.content.buttons.detect cget -text] [$dlg.content.buttons.close cget -text]]
	set ghint [$dlg.content.hint cget -text]
	::menu::SwitchLanguage English
	set again [list [wm title $dlg] [$dlg.content.title cget -text] \
		[$dlg.content.whisperCli.label cget -text] \
		[$dlg.content.buttons.detect cget -text] [$dlg.content.buttons.close cget -text]]
	list $labels $german [expr {$again eq $labels}] \
		[string match {*Spracheingabe*} $ghint] \
		[string match {*Speech input needs*} $ehint]
} -cleanup {
	::scidb::test::askI18n::Clean
} -result {{Assistant {Speech input} {whisper-cli path} Detect Close} {Assistent Spracheingabe {Pfad zu whisper-cli} Erkennen Schliessen} 1 1 1}

# ----------------------------------------------------------------------
# Coverage: every string of the field has a German text of its own, and a
# language without one falls back to English.
# ----------------------------------------------------------------------
tcltest::test ask-i18n-german-coverage {every string of the field has a German text of its own} -body {
	::menu::SwitchLanguage English
	set checked 0
	::menu::SwitchLanguage Deutsch
	set same {}
	foreach ns {::application::ask ::application::speech} {
		foreach {name value} [set ${ns}::DefaultMC] {
			# whisper-cli is the tool it is, in every language
			if {$name eq "MissingCli"} { continue }
			incr checked
			if {[set ${ns}::mc::$name] eq $value} { lappend same "$ns::$name" }
		}
	}
	::menu::SwitchLanguage English
	if {[llength $same]} { puts "  not translated: $same" }
	list $checked $same
} -cleanup {
	::scidb::test::askI18n::Clean
} -result {34 {}}

tcltest::test ask-i18n-fallback {ResetMC restores English defaults} -body {
	::menu::SwitchLanguage Deutsch
	set german [list [set ::application::ask::mc::Placeholder] \
		[set ::application::ask::mc::Busy] \
		[set ::application::speech::mc::MissingModel]]
	::application::ask::ResetMC
	::application::speech::ResetMC
	set english [list [set ::application::ask::mc::Placeholder] \
		[set ::application::ask::mc::Busy] \
		[set ::application::speech::mc::MissingModel]]
	list [expr {$german ne $english}] $english
} -cleanup {
	::scidb::test::askI18n::Clean
} -result {1 {{Ask or tell Chesswiz what to do (Ctrl+K)} {The assistant is busy. Try again when it finishes.} {a ggml model}}}

tcltest::test ask-i18n-translated-languages {for es/it/hu/sv the Ask placeholder and assistant Send button differ from English} -body {
	::menu::SwitchLanguage English
	set enPlaceholder [set ::application::ask::mc::Placeholder]
	set enSend [set ::application::assistant::mc::Send]

	set results {}
	foreach lang {Español Italiano Magyar Svenska} {
		::menu::SwitchLanguage $lang
		set ph [set ::application::ask::mc::Placeholder]
		set snd [set ::application::assistant::mc::Send]
		set phDiff [expr {$ph ne $enPlaceholder}]
		set sndDiff [expr {$snd ne $enSend}]
		lappend results $lang [list phDiff $phDiff sndDiff $sndDiff]
	}
	set results
} -cleanup {
	::scidb::test::askI18n::Clean
} -result {Español {phDiff 1 sndDiff 1} Italiano {phDiff 1 sndDiff 1} Magyar {phDiff 1 sndDiff 1} Svenska {phDiff 1 sndDiff 1}}

::menu::SwitchLanguage English
::scidb::test::askI18n::Empty
::scidb::test::askI18n::restore

tcltest::cleanupTests
