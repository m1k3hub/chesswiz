# ======================================================================
# Scidb App Test - the game Overview window (tcl/overview.tcl)
# ======================================================================
# Two reports from a Windows tester: Escape did not close the Overview, and
# at 200% scaling on a 1920x1080 screen its button row fell below the screen
# edge, so that no Close button was reachable. The window is opened on a
# small generated PGN, the way the game list does it (gametable Open
# (overview)), and both are checked on the real window.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::ovw {
	variable testDir [file dirname [file normalize [info script]]]
	variable Counter 0
}

proc ::scidb::test::ovw::nop {args} { return 0 }

# A small PGN, written once, handed back with the window it opened
proc ::scidb::test::ovw::makeFixture {base} {
	file mkdir [file dirname $base]
	set fh [open $base w]
	fconfigure $fh -encoding utf-8
	puts $fh "\[Event \"Overview\"\]\n\[Site \"X\"\]\n\[Date \"2020.01.01\"\]"
	puts $fh "\[Round \"1\"\]\n\[White \"W1\"\]\n\[Black \"B1\"\]\n\[Result \"1-0\"\]"
	puts $fh "\n1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 1-0\n"
	close $fh
}

# as gametable Open(overview): the game list's own view and game info
proc ::scidb::test::ovw::openWindow {} {
	variable testDir
	variable Counter

	set base [file join $testDir tmp-app overview-[pid]-[incr Counter].pgn]
	makeFixture $base
	::scidb::db::open $base ::scidb::test::ovw::nop {} ::scidb::test::ovw::nop {}
	set info [::scidb::db::get gameInfo 0 0 $base Normal]
	set nb [::overview::open .application $base Normal $info 0 0]
	update
	return [list [winfo toplevel $nb] $base]
}

proc ::scidb::test::ovw::closeWindow {dlg base} {
	catch { destroy $dlg }
	catch { ::scidb::db::close $base }
	catch { file delete $base }
}

# Xvfb has no window manager to hand the keyboard to a new window; a real
# user's window has the focus, so the test gives it.
proc ::scidb::test::ovw::focusWindow {dlg} {
	focus -force $dlg
	update
}


tcltest::test ovw-escape-closes {Escape closes the Overview window} -setup {
	lassign [::scidb::test::ovw::openWindow] d base
} -body {
	update idletasks
	::scidb::test::ovw::focusWindow $d
	event generate $d <Escape>
	update
	if {[winfo exists $d]} { list $d [llength [winfo children $d]] } else { list closed 0 }
} -cleanup {
	catch { ::scidb::test::ovw::closeWindow $d $base }
} -result {closed 0}

tcltest::test ovw-fits-screen {the window and its button row stay within the screen} -setup {
	lassign [::scidb::test::ovw::openWindow] d base
} -body {
	update idletasks
	set screenH [winfo screenheight $d]
	set bottom [expr {[winfo rooty $d] + [winfo height $d]}]
	set closeBottom [expr {[winfo rooty $d.close] + [winfo height $d.close]}]
	list \
		[expr {$bottom <= $screenH}] \
		[expr {$closeBottom <= $screenH}] \
		[expr {[winfo rooty $d.close] >= 0}] \
		[winfo ismapped $d.close] \
		[expr {[winfo height $d.close] > 0}]
} -cleanup {
	catch { ::scidb::test::ovw::closeWindow $d $base }
} -result {1 1 1 1 1}

tcltest::test ovw-close-button {the Close button of the fitted window destroys it} -setup {
	lassign [::scidb::test::ovw::openWindow] d base
} -body {
	update idletasks
	$d.close invoke
	update
	winfo exists $d
} -cleanup {
	catch { ::scidb::test::ovw::closeWindow $d $base }
} -result 0

tcltest::test ovw-reopen-fitted {after closing, a new Overview is fitted again} -setup {
	lassign [::scidb::test::ovw::openWindow] d base
	update idletasks
	::scidb::test::ovw::focusWindow $d
	event generate $d <Escape>
	update
	set closed [winfo exists $d]
	::scidb::test::ovw::closeWindow $d $base
	lassign [::scidb::test::ovw::openWindow] d base
} -body {
	update idletasks
	set screenH [winfo screenheight $d]
	set bottom [expr {[winfo rooty $d] + [winfo height $d]}]
	list $closed [expr {$bottom <= $screenH}] [winfo exists $d]
} -cleanup {
	catch { ::scidb::test::ovw::closeWindow $d $base }
} -result {0 1 1}

::tcltest::cleanupTests
return
