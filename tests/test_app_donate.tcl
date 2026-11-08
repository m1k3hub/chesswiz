package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
::scidb::test::actions::ready

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

tcltest::test donate-menu-links {Donate offers PayPal and Ko-fi (read, never clicked)} -body {
	set m [winfo parent $::application::Vars(donate)].donate_menu
	set out {}
	for {set i 0} {$i <= [$m index end]} {incr i} {
		lappend out [$m entrycget $i -label] [lindex [$m entrycget $i -command] end]
	}
	set out
} -result {PayPal https://paypal.me/MGThomas Ko-fi https://ko-fi.com/michaelthomas13477}

if {[info exists ::env(DONATE_SHOT)]} {
	catch { exec import -display $::env(DISPLAY) -window root $::env(DONATE_SHOT) }
}

tcltest::cleanupTests
