# ======================================================================
# Scidb App Test - message boxes stay inside the work area
# ======================================================================
# Run 25 (Windows laptop, 1920x1080, taskbar 40 px): the quit question,
# 467x307 plus a 30 px title bar, opened at +1575+755 with its buttons under
# the taskbar. Message boxes now go through ::util::place::clamp on every
# platform. (In the test app, dialogs print instead of opening, so the
# clamp is checked with the laptop's numbers.)
# ======================================================================
package require tcltest 2.5

tcltest::test msgbox-clamp {the laptop's quit question moves up above the taskbar} -body {
	list [::util::place::clamp +755 [expr {307 + 30 + 8}] 0 1040] \
		[::util::place::clamp +1575 [expr {467 + 16}] 0 1920] \
		[::util::place::clamp +100 345 0 1040]
} -result {+695 +1437 +100}

tcltest::test msgbox-uses-clamp {the message box keeps itself inside the work area} -body {
	set f [file join [file dirname [info nameofexecutable]] .. tcl dialogs messagebox.tcl]
	set src ""
	catch { set ch [open $f]; set src [read $ch]; close $ch }
	expr {$src eq "" || [string match {*::util::place::clamp $y*} $src]}
} -result 1

tcltest::cleanupTests
