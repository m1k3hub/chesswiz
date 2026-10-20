# ======================================================================
# macOS integration, proven where Linux can prove it (VAL-BAR-003)
# ======================================================================
# The mac VM was not available to this worker, so the Tk-level dumps and
# the scripted Quit on aqua are listed as not-run in the evidence report.
# What is provable here: the About/Preferences/Quit handlers route through
# the ::tk::mac hooks, and nothing installs a second global menu bar on
# X11. The hooks are stubbed so no dialog opens and no shutdown runs.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::mac {}
catch { namespace eval ::tk::mac {} }

proc ::scidb::test::mac::Called {} { return [set ::scidb::test::mac::called] }
proc ::scidb::test::mac::About {} { set ::scidb::test::mac::called about }
proc ::scidb::test::mac::Prefs {} { set ::scidb::test::mac::called prefs }
proc ::scidb::test::mac::Quit {} { set ::scidb::test::mac::called quit }

tcltest::test mac-about-uses-standard-panel {About calls the Tk application panel} -body {
	set ::scidb::test::mac::called ""
	# on Aqua the real panel exists: set it aside so the test sees the call
	set had [llength [info commands ::tk::mac::standardAboutPanel]]
	if {$had} { rename ::tk::mac::standardAboutPanel ::scidb::test::mac::RealAbout }
	proc ::tk::mac::standardAboutPanel {} { ::scidb::test::mac::About }
	::menu::MacAbout
	set got [::scidb::test::mac::Called]
	rename ::tk::mac::standardAboutPanel {}
	if {$had} { rename ::scidb::test::mac::RealAbout ::tk::mac::standardAboutPanel }
	list $got
} -result {about}

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
