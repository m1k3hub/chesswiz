# ======================================================================
# Scidb App Test — the assistant's offers in the user's language
# (tcl/app-assistant-offers.tcl, tcl/lang/english.tcl, tcl/lang/deutsch.tcl)
# ======================================================================
# Run 197: with the UI in German the assistant pane's Send/Clear buttons
# were German, but its offer buttons stayed English. An offer carried
# the label it had when it was chosen, and the offers are chosen before
# the pane opens (a database switch at startup), so the pane drew labels
# of the language in force at that earlier moment. An offer now carries
# the name of its mc string and is labelled when it is drawn.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::offersI18n {}

# The app bundle bakes in the installed share directory. Read the language
# files of this worktree instead, so the test verifies what we are about
# to commit rather than a stale system install.
set ::scidb::test::offersI18n::savedShare $::scidb::dir::share
set ::scidb::test::offersI18n::worktreeShare [file normalize [file join \
	[file dirname [file normalize [info script]]] .. tcl]]
if {[file isdirectory [file join $::scidb::test::offersI18n::worktreeShare lang]]} {
	set ::scidb::dir::share $::scidb::test::offersI18n::worktreeShare
}

# The labels of the offer buttons in the pane, left to right.
proc ::scidb::test::offersI18n::buttons {} {
	set frame $::application::assistant::offers::Frame
	if {$frame eq "" || ![winfo exists $frame]} { return {} }
	return [lmap w [winfo children $frame] { $w cget -text }]
}

# The labels of the offers of the moment (Offers is {label request ...}).
proc ::scidb::test::offersI18n::labels {} {
	return [lmap {label request} $::application::assistant::offers::Offers { set label }]
}

# A language file overwrites the mc strings of every module, and only
# some modules (::mc::addDefaultReset) restore their own English text --
# the assistant pane and the Ask field do not. Switching back to English
# here would therefore leave their German text for the test files that
# follow; snapshot every mc string this file can touch, and put them back.
proc ::scidb::test::offersI18n::snapshot {} {
	variable Saved
	set Saved {}
	# ::*::mc::* is not a valid info vars pattern ("*" stops at "::"),
	# so walk the namespaces and collect the mc ones.
	set todo [list ::]
	while {[llength $todo]} {
		set ns [lindex $todo 0]
		set todo [lrange $todo 1 end]
		foreach child [namespace children $ns] {
			lappend todo $child
			if {[namespace tail $child] ne "mc"} { continue }
			foreach v [info vars ${child}::*] {
				if {[array exists $v]} {
					lappend Saved [list array $v [array get $v]]
				} elseif {[info exists $v]} {
					lappend Saved [list scalar $v [set $v]]
				} else {
					# an array that the language loader unset
					lappend Saved [list unset $v]
				}
			}
		}
	}
	return
}

proc ::scidb::test::offersI18n::restore {} {
	variable Saved
	foreach entry $Saved {
		lassign $entry kind v value
		if {$kind eq "array"} {
			array unset $v
			array set $v $value
		} elseif {$kind eq "unset"} {
			catch { unset $v }
		} else {
			set $v $value
		}
	}
	return
}

# Run <body> with the current game's tags replaced by <tags>. A database
# would do as well, but a test file that opens one takes a game slot and
# fails when the files before it left all nine occupied.
proc ::scidb::test::offersI18n::withTags {tags body} {
	rename ::scidb::game::tags ::scidb::test::offersI18n::realTags
	proc ::scidb::game::tags {args} [list return $tags]
	set rc [catch { uplevel 1 $body } result opts]
	rename ::scidb::game::tags {}
	rename ::scidb::test::offersI18n::realTags ::scidb::game::tags
	return -options $opts $result
}

::scidb::test::offersI18n::snapshot

tcltest::test offers-i18n-german {the pane shows German offer buttons although the offers were chosen in English} -body {
	::menu::SwitchLanguage English
	set saved $::application::ai::Settings(me)
	set ::application::ai::Settings(me) {}
	# the moment is chosen while the UI is English (as at startup)
	::scidb::test::offersI18n::withTags {{White {Kasparov, G}} {Black {Karpov, A}}} {
		::application::assistant::offers::GameSwitched 0 0
	}
	set english [::scidb::test::offersI18n::labels]
	# the user switches to German and opens the pane (run 197)
	::menu::SwitchLanguage Deutsch
	::application::assistant::show
	set german [::scidb::test::offersI18n::buttons]
	set ::application::ai::Settings(me) $saved
	::menu::SwitchLanguage English
	::application::assistant::offers::put {}
	set same {}
	foreach label $german {
		if {[lsearch -exact $english $label] >= 0} { lappend same $label }
	}
	if {[llength $same]} { puts "  still English: $same" }
	list [llength $english] [expr {[llength $german] == [llength $english]}] \
		[expr {[llength $same] == 0}] $german
} -result {3 1 1 {{Stellung erklären} {Partien mit dieser Stellung} {Ähnliche Stellungen}}}

tcltest::test offers-i18n-open-pane {a language switch relabels the offers of an open pane} -body {
	::menu::SwitchLanguage English
	::application::assistant::show
	::application::assistant::offers::put \
		{Summary {What is in the active database? A short summary, please.} \
		FindPositions {Find positions where ...} Duplicates {Open the duplicate search.}}
	set english [::scidb::test::offersI18n::buttons]
	::menu::SwitchLanguage Deutsch
	set german [::scidb::test::offersI18n::buttons]
	::menu::SwitchLanguage English
	set again [::scidb::test::offersI18n::buttons]
	::application::assistant::offers::put {}
	list $english $german [expr {$again eq $english}]
} -result {{{What's in this database?} {Find positions...} Duplicates?} {{Was enthält diese Datenbank?} {Stellungen finden...} Duplikate?} 1}

tcltest::test offers-i18n-fallback {a language without offer translations falls back to English} -body {
	::menu::SwitchLanguage English
	::application::assistant::show
	::application::assistant::offers::put {Summary {r} FindPositions {r}}
	set english [::scidb::test::offersI18n::buttons]
	::menu::SwitchLanguage Deutsch
	set german [::scidb::test::offersI18n::buttons]
	::menu::SwitchLanguage Svenska
	set swedish [::scidb::test::offersI18n::buttons]
	::menu::SwitchLanguage English
	::application::assistant::offers::put {}
	list [expr {$german ne $english}] [expr {$swedish eq $english}] $swedish
} -result {1 1 {{What's in this database?} {Find positions...}}}

tcltest::test offers-i18n-coverage {every offer string has a German text of its own} -body {
	::menu::SwitchLanguage English
	set english {}
	foreach {name value} $::application::assistant::offers::DefaultMC {
		lappend english $name $value
	}
	::menu::SwitchLanguage Deutsch
	set same {}
	foreach {name value} $english {
		if {[set ::application::assistant::offers::mc::$name] eq $value} {
			lappend same $name
		}
	}
	::menu::SwitchLanguage English
	if {[llength $same]} { puts "  not translated: $same" }
	list [expr {[llength $english] / 2}] $same
} -result {18 {}}

::scidb::test::offersI18n::restore

tcltest::cleanupTests
