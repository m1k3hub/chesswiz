# ======================================================================
# Scidb App Test — Ask placeholder and assistant Send button in
# Spanish, Italian, Hungarian, and Swedish
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::askI18nMore {}

set ::scidb::test::askI18nMore::savedShare $::scidb::dir::share
set ::scidb::test::askI18nMore::worktreeShare [file normalize [file join \
	[file dirname [file normalize [info script]]] .. tcl]]
if {[file isdirectory [file join $::scidb::test::askI18nMore::worktreeShare lang]]} {
	set ::scidb::dir::share $::scidb::test::askI18nMore::worktreeShare
}

proc ::scidb::test::askI18nMore::Clean {} {
	catch { ::menu::SwitchLanguage English }
	catch { ::application::ask::HideList }
	set ::application::ask::Query ""
	catch { [::application::ask::Entry] delete 0 end }
	catch { ::application::ask::PlaceholderState }
}

tcltest::test ask-i18n-more-languages {for es/it/hu/sv the Ask placeholder and assistant Send button differ from English} -body {
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
	::scidb::test::askI18nMore::Clean
} -result {Español {phDiff 1 sndDiff 1} Italiano {phDiff 1 sndDiff 1} Magyar {phDiff 1 sndDiff 1} Svenska {phDiff 1 sndDiff 1}}

if {[info exists ::scidb::test::askI18nMore::savedShare]} {
	set ::scidb::dir::share $::scidb::test::askI18nMore::savedShare
}

tcltest::cleanupTests
