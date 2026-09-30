# ======================================================================
# Scidb App Test -- non-blocking notices (tcl/dialogs/notice.tcl): errors
# are seen but never hold the program up; decisions stay modal.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::notice {
	variable Life {}
}

proc ::scidb::test::notice::setup {} {
	variable Life
	set Life [array get ::dialog::notice::Life]
	::dialog::nonInteractive 0
	::dialog::notice::enable 1
	clear
	rename ::puts ::scidb::test::notice::realPuts
	proc ::puts {args} {
		if {[lindex $args 0] eq "stderr"} { return }
		return [::scidb::test::notice::realPuts {*}$args]
	}
}

proc ::scidb::test::notice::cleanup {} {
	variable Life
	rename ::puts {}
	rename ::scidb::test::notice::realPuts ::puts
	array set ::dialog::notice::Life $Life
	::dialog::notice::enable 1
	clear
}

proc ::scidb::test::notice::clear {} {
	foreach c $::dialog::notice::Cards { ::dialog::notice::Dismiss [lindex $c 0] }
}

proc ::scidb::test::notice::wait {ms} {
	after $ms { set ::scidb::test::notice::go 1 }
	vwait ::scidb::test::notice::go
}

# answer the modal dialog that is open in 200 ms
proc ::scidb::test::notice::answerLater {reply} {
	after 200 [list apply {{reply} {
		foreach c [winfo children .] {
			if {[string match .alert* $c]} { set ::dialog::Reply($c) $reply; return }
		}
	}} $reply]
}

tcltest::test notice-error-does-not-block {an error dialog returns at once and leaves a card} -setup {
	::scidb::test::notice::setup
} -body {
	set t0 [clock milliseconds]
	set r [::dialog::error -parent . -message "Disk full"]
	set ms [expr {[clock milliseconds] - $t0}]
	list $r [expr {$ms < 300}] [::dialog::notice::count] [winfo exists $::dialog::notice::Holder]
} -cleanup {
	::scidb::test::notice::cleanup
} -result {ok 1 1 1}

tcltest::test notice-recorded-in-log {every notice is written to the log, which stays closed} -setup {
	::scidb::test::notice::setup
	set ::scidb::test::notice::oldShow $::log::Priv(show)
	set ::scidb::test::notice::oldForce $::log::Priv(force)
	set ::log::Priv(show) 1	;# the state after startup: the first error would open the window
	set ::log::Priv(force) 0
	wm withdraw $::log::Log
} -body {
	::dialog::error -parent . -message "Cannot open file x.sci" -detail "permission denied"
	update
	set text [$::log::Log.top.text get 1.0 end]
	list [string match "*Cannot open file x.sci*" $text] [string match "*permission denied*" $text] \
		[winfo ismapped $::log::Log] $::log::Priv(show) $::log::Priv(force)
} -cleanup {
	set ::log::Priv(show) $::scidb::test::notice::oldShow
	set ::log::Priv(force) $::scidb::test::notice::oldForce
	::scidb::test::notice::cleanup
} -result {1 1 0 1 0}

tcltest::test notice-repeats-collapse {the same message raises a counter instead of stacking cards} -setup {
	::scidb::test::notice::setup
} -body {
	foreach i {1 2 3} { ::dialog::error -parent . -message "same problem" }
	set id [lindex [lindex $::dialog::notice::Cards 0] 0]
	list [::dialog::notice::count] [$::dialog::notice::Holder.$id.text cget -text]
} -cleanup {
	::scidb::test::notice::cleanup
} -result "1 {same problem  (×3)}"

tcltest::test notice-lifetimes {info fades, an error stays until dismissed} -setup {
	::scidb::test::notice::setup
	set ::dialog::notice::Life(info) 80
} -body {
	::dialog::info -parent . -message "saved"
	::dialog::error -parent . -message "broken"
	set both [::dialog::notice::count]
	::scidb::test::notice::wait 300
	set later [::dialog::notice::count]
	::scidb::test::notice::clear
	list $both $later [::dialog::notice::count]
} -cleanup {
	::scidb::test::notice::cleanup
} -result {2 1 0}

tcltest::test notice-at-most-four {a flood keeps four cards and drops the oldest non-error first} -setup {
	::scidb::test::notice::setup
} -body {
	::dialog::error -parent . -message "e1"
	foreach i {1 2 3 4 5} { ::dialog::info -parent . -message "i$i" }
	set kinds [lmap c $::dialog::notice::Cards { lindex $c 1 }]
	set msgs [lmap c $::dialog::notice::Cards { lindex $c 2 }]
	list [::dialog::notice::count] [lindex $kinds 0] $msgs
} -cleanup {
	::scidb::test::notice::cleanup
} -result {4 error {e1 i3 i4 i5}}

tcltest::test notice-close-button {the close button removes the card} -setup {
	::scidb::test::notice::setup
} -body {
	::dialog::error -parent . -message "go away"
	set id [lindex [lindex $::dialog::notice::Cards 0] 0]
	$::dialog::notice::Holder.$id.close invoke
	::dialog::notice::count
} -cleanup {
	::scidb::test::notice::cleanup
} -result 0

tcltest::test notice-decisions-stay-modal {a question still waits for the user's answer} -setup {
	::scidb::test::notice::setup
} -body {
	::scidb::test::notice::answerLater yes
	set r [::dialog::question -parent . -message "Overwrite the file?"]
	list $r [::dialog::notice::count]
} -cleanup {
	::scidb::test::notice::cleanup
} -result {yes 0}

tcltest::test notice-switch-off-restores-dialogs {with notices off an OK dialog is modal again} -setup {
	::scidb::test::notice::setup
	::dialog::notice::enable 0
} -body {
	::scidb::test::notice::answerLater ok
	set r [::dialog::info -parent . -message "modal again"]
	list $r [::dialog::notice::count]
} -cleanup {
	::scidb::test::notice::cleanup
} -result {ok 0}

tcltest::test notice-background-error {a background error becomes a card with the stack in the log, not Tk's modal dialog} -setup {
	::scidb::test::notice::setup
} -body {
	# bgerror keeps the last error details of the whole process in these
	set ::scidb::intern::errresult ""; set ::scidb::intern::errmsg ""; set ::scidb::intern::tclStack ""
	set ::errorCode NONE
	set ::errorInfo "boom\n    while executing\n\"nothing at all\""
	::scidb::bgerror "boom" {}
	set dialogs [lmap c [winfo children .] { expr {[string match .alert* $c] || [string match .bgerrorDialog* $c] ? $c : [continue]} }]
	list [::dialog::notice::count] [llength $dialogs] \
		[string match "*boom*" [$::log::Log.top.text get 1.0 end]]
} -cleanup {
	::scidb::test::notice::cleanup
} -result {1 0 1}

::tcltest::cleanupTests
return
