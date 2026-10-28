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

# Pretend to be Tk aqua: only "tk windowingsystem" changes.
proc ::scidb::test::mac::FakeAqua {} {
	rename ::tk ::scidb::test::mac::RealTk
	proc ::tk {args} {
		if {$args eq "windowingsystem"} { return aqua }
		return [uplevel 1 [list ::scidb::test::mac::RealTk {*}$args]]
	}
}
proc ::scidb::test::mac::RealAqua {} {
	if {[llength [info commands ::scidb::test::mac::RealTk]] == 0} { return }
	rename ::tk {}
	rename ::scidb::test::mac::RealTk ::tk
}

tcltest::test mac-accel-format {Aqua shows Cmd for Control, X11 keeps Ctrl} -body {
	set specs {Control-o Control-q Control-Shift-N Control-Down Control-Shift-plus F11 Alt-Shift-x}
	set x11 {}
	foreach spec $specs { lappend x11 [::menu::FormatAccel $spec] }
	::scidb::test::mac::FakeAqua
	set aqua {}
	foreach spec $specs { lappend aqua [::menu::FormatAccel $spec] }
	::scidb::test::mac::RealAqua
	list $x11 $aqua
} -result {{Ctrl+O Ctrl+Q Ctrl+Shift+N Ctrl+Down Ctrl+Shift++ F11 Alt+Shift+X} {Cmd+O Cmd+Q Cmd+Shift+N Cmd+Down Cmd+Shift++ F11 Alt+Shift+X}}

tcltest::test mac-accel-rows {Drop-down rows carry key specs, not Ctrl+ strings} -body {
	set bad {}
	foreach top $::menu::DropdownTree {
		set stack [list $top]
		while {[llength $stack]} {
			set node [lindex $stack end]
			set stack [lrange $stack 0 end-1]
			foreach field $node {
				if {[string match Ctrl+* $field]} { lappend bad $field }
			}
			if {[lindex $node 0] eq "cascade" && [lindex $node 3] ne "dynamic"} {
				lappend stack {*}[lindex $node 3]
			}
		}
	}
	list $bad [::menu::Label menu.file.open] [::menu::Accel menu.file.open] [::menu::Accel app-quit]
} -result [list {} [::menu::Label menu.file.open] Ctrl+O Ctrl+Q]

tcltest::test mac-accel-binding {Aqua mirrors Control bindings to Command and follows rebinds} -setup {
	toplevel .mactest
	bind .mactest <Control-o> {set ::scidb::test::mac::called open}
	bind .mactest <Control-w> {set ::scidb::test::mac::called close}
	set savedNeed [set ::application::board::Vars(need-binding)]
	set ::application::board::Vars(need-binding) [list .mactest]
	set ::scidb::test::mac::called ""
} -body {
	::scidb::test::mac::FakeAqua
	::menu::MirrorCommandBindings
	# the native key press is proven on the Mac mini; here the Command
	# binding (Mod1 on X11) must run what the Control binding runs
	uplevel #0 [bind .mactest <Command-o>]
	set first $::scidb::test::mac::called
	bind .mactest <Control-o> {set ::scidb::test::mac::called moved}
	bind .mactest <Control-w> {}
	::menu::MirrorCommandBindings
	uplevel #0 [bind .mactest <Command-o>]
	set second $::scidb::test::mac::called
	set closeGone [expr {[bind .mactest <Command-w>] eq ""}]
	::scidb::test::mac::RealAqua
	list $first $second $closeGone [string match *Ctrl* [::menu::FormatAccel Control-o]]
} -cleanup {
	catch { ::scidb::test::mac::RealAqua }
	set ::application::board::Vars(need-binding) $savedNeed
	array unset ::menu::Mirrored .mactest,*
	destroy .mactest
} -result {open moved 1 1}

tcltest::test mac-about-dialog-hook {::tkAboutDialog opens the About dialog} -setup {
	rename ::info::openDialog ::scidb::test::mac::RealAbout
	proc ::info::openDialog {parent} { set ::scidb::test::mac::called [list about $parent] }
	set had [llength [info commands ::tkAboutDialog]]
	set hadPrefs [llength [info commands ::tk::mac::ShowPreferences]]
	set hadQuit [llength [info commands ::tk::mac::Quit]]
	::scidb::test::mac::FakeAqua
} -body {
	set ::scidb::test::mac::called ""
	::menu::InstallMacHooks
	after cancel ::menu::MirrorCommandBindings
	set hooks [list [llength [info commands ::tk::mac::ShowPreferences]] [llength [info commands ::tk::mac::Quit]]]
	::tkAboutDialog
	list $hooks [::scidb::test::mac::Called]
} -cleanup {
	catch { ::scidb::test::mac::RealAqua }
	if {!$had} { catch { rename ::tkAboutDialog {} } }
	if {!$hadPrefs} { catch { rename ::tk::mac::ShowPreferences {} } }
	if {!$hadQuit} { catch { rename ::tk::mac::Quit {} } }
	rename ::info::openDialog {}
	rename ::scidb::test::mac::RealAbout ::info::openDialog
} -result {{1 1} {about .application}}

tcltest::cleanupTests
