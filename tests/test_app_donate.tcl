package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
::scidb::test::actions::ready

# A scheduled popup runs native menu tracking when the event loop reaches it.
# Cancel the pending idle instead of updating into it, so a suite run on
# win32/aqua does not wait for a user to dismiss the Donate menu.
proc donateTestCancelPost {} {
	foreach id [after info] {
		if {[string match *::menu::PostDonateMenu* [after info $id]]} {
			after cancel $id
		}
	}
	catch { ::tk::MenuUnpost [winfo parent $::application::Vars(donate)].donate_menu }
}

tcltest::test donate-button-placed {Donate sits in the top strip, left of the Main Menu, right of the Ask field} -body {
	update idletasks
	set d $::application::Vars(donate)
	set m $::application::Vars(menu:main)
	set ask $::application::ask::Priv(frame)
	list [winfo ismapped $d] \
		[expr {[winfo x $d] + [winfo width $d] <= [winfo x $m]}] \
		[expr {[winfo x $ask] + [winfo width $ask] <= [winfo x $d]}] \
		[expr {[winfo y $d] == [winfo y $m]}]
} -result {1 1 1 1}

tcltest::test donate-menu-links {Donate dispatches the exact PayPal and Ko-fi destinations without opening a browser} -setup {
	rename ::web::open ::web::donateTestOpen
	proc ::web::open {parent url} {set ::donateTestURL $url}
} -body {
	set m [winfo parent $::application::Vars(donate)].donate_menu
	set out {}
	for {set i 0} {$i <= [$m index end]} {incr i} {
		set ::donateTestURL {}
		$m invoke $i
		lappend out [$m entrycget $i -label] $::donateTestURL
	}
	set out
} -cleanup {
	rename ::web::open {}
	rename ::web::donateTestOpen ::web::open
	unset -nocomplain ::donateTestURL
} -result {PayPal https://paypal.me/MGThomas Ko-fi https://ko-fi.com/michaelthomas13477}

# The top-strip button and the assistant both dispatch this row through
# ::action::run. Posting the menu inside that call runs native menu tracking
# synchronously on Windows and macOS, so the caller never returns. The row
# must return at once (under 1 s) and post only from the event loop.
tcltest::test donate-action-returns {::action::run menu.help.donate returns before its popup is posted} -body {
	set m [winfo parent $::application::Vars(donate)].donate_menu
	catch { ::tk::MenuUnpost $m }
	update
	set t0 [clock milliseconds]
	set result [::action::run menu.help.donate]
	set elapsed [expr {[clock milliseconds] - $t0}]
	set posted [winfo ismapped $m]
	list $result [expr {$elapsed < 1000}] $posted
} -cleanup {
	donateTestCancelPost
} -result {{} 1 0}

tcltest::test donate-knowledge-run-action-returns {assistant run_action menu.help.donate returns before its popup is posted} -body {
	set m [winfo parent $::application::Vars(donate)].donate_menu
	catch { ::tk::MenuUnpost $m }
	update
	set t0 [clock milliseconds]
	set result [::knowledge::RunAction menu.help.donate {}]
	set elapsed [expr {[clock milliseconds] - $t0}]
	set posted [winfo ismapped $m]
	list [expr {![string match {error:*} $result]}] [expr {$elapsed < 1000}] $posted
} -cleanup {
	donateTestCancelPost
} -result {1 1 0}

if {[info exists ::env(DONATE_SHOT)]} {
	catch { exec import -display $::env(DISPLAY) -window root $::env(DONATE_SHOT) }
}

tcltest::cleanupTests
