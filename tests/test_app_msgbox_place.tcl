# ======================================================================
# Scidb App Test - message boxes stay inside the work area
# ======================================================================
# Run 25 (Windows laptop, 1920x1080, taskbar 40 px): the quit question,
# 467x307 plus a 30 px title bar, opened at +1575+755 with its buttons under
# the taskbar. Message boxes now go through ::util::place::clamp on every
# platform. (In the test app, dialogs print instead of opening, so the
# clamp cases derive their boundaries from the live work area.)
# ======================================================================
package require tcltest 2.5

tcltest::test msgbox-clamp {an overflowing quit question moves inside the live work area} -body {
    lassign [winfo workarea .application] x y w h
    set dw [expr {$w/3}]; set dh [expr {$h/3}]
    set safe [expr {$y+$h/10}]
    list [expr {[::util::place::clamp +[expr {$y+$h-$dh/2}] $dh $y $h] eq "+[expr {$y+$h-$dh}]"}] \
        [expr {[::util::place::clamp +[expr {$x+$w-$dw/2}] $dw $x $w] eq "+[expr {$x+$w-$dw}]"}] \
        [expr {[::util::place::clamp +$safe $dh $y $h] eq "+$safe"}]
} -result {1 1 1}

tcltest::test msgbox-uses-clamp {the message box keeps itself inside the work area} -body {
	set f [file join [file dirname [info nameofexecutable]] .. tcl dialogs messagebox.tcl]
	set src ""
	catch { set ch [open $f]; set src [read $ch]; close $ch }
	expr {$src eq "" || [string match {*::util::place::clamp $y*} $src]}
} -result 1

tcltest::cleanupTests
