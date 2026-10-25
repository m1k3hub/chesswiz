# ======================================================================
# macOS integration, proven where Linux can prove it (VAL-BAR-003)
# ======================================================================
# The mac VM was not available to this worker, so the Tk-level dumps and
# the scripted Quit on aqua are listed as not-run in the evidence report.
# What is provable here: the About/Preferences/Quit handlers route through
# the shared About dialog and ::tk::mac preferences/quit hooks, and nothing
# installs a second global menu bar on X11. UI boundaries are stubbed.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::mac {}
catch { namespace eval ::tk::mac {} }

proc ::scidb::test::mac::Called {} { return [set ::scidb::test::mac::called] }
proc ::scidb::test::mac::About {} { set ::scidb::test::mac::called about }
proc ::scidb::test::mac::Prefs {} { set ::scidb::test::mac::called prefs }
proc ::scidb::test::mac::Quit {} { set ::scidb::test::mac::called quit }

tcltest::test mac-about-has-support {About uses the application dialog with its support link} -setup {
	rename ::info::openDialog ::scidb::test::mac::RealAbout
	proc ::info::openDialog {parent} { set ::scidb::test::mac::called [list about $parent] }
} -body {
	::menu::MacAbout
	::scidb::test::mac::Called
} -cleanup {
	rename ::info::openDialog {}
	rename ::scidb::test::mac::RealAbout ::info::openDialog
} -result {about .application}

tcltest::test mac-preferences-hook {Preferences routes through ::tk::mac::ShowPreferences} -body {
	set ::scidb::test::mac::called ""
	set had [llength [info commands ::tk::mac::ShowPreferences]]
	if {$had} { set savedBody [info body ::tk::mac::ShowPreferences] }
	proc ::tk::mac::ShowPreferences {} { ::scidb::test::mac::Prefs }
	::menu::MacPreferences
	set got [::scidb::test::mac::Called]
	rename ::tk::mac::ShowPreferences {}
	if {$had} {
		proc ::tk::mac::ShowPreferences {} $savedBody
	}
	list $got
} -result {prefs}

tcltest::test mac-quit-hook {Quit routes through ::tk::mac::Quit, not a second shutdown} -body {
	set ::scidb::test::mac::called ""
	set had [llength [info commands ::tk::mac::Quit]]
	if {$had} { set savedBody [info body ::tk::mac::Quit] }
	proc ::tk::mac::Quit {} { ::scidb::test::mac::Quit }
	::menu::MacQuit
	set got [::scidb::test::mac::Called]
	rename ::tk::mac::Quit {}
	if {$had} {
		proc ::tk::mac::Quit {} $savedBody
	}
	list $got
} -result {quit}

tcltest::test mac-no-second-menu-bar {X11 installs no global menu bar and keeps the button} -body {
	set bars {}
	foreach w {.menubar .mbar .menu} {
		if {[winfo exists $w]} { lappend bars $w }
	}
	list $bars [winfo exists .application.nb.menu_main] [winfo class .application.nb.menu_main]
} -result {{} 1 Menubutton}

tcltest::cleanupTests
