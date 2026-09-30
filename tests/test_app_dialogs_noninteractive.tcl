# ======================================================================
# Scidb App Test -- non-interactive mode: no modal dialog is ever built
# (tcl/dialogs/messagebox.tcl, ::scidb::bgerror in tcl/start.tcl)
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::ni {
	variable Saved 0
}

proc ::scidb::test::ni::on {} {
	variable Saved
	set Saved [::dialog::nonInteractive]
	::dialog::nonInteractive 1
	set ::dialog::NonInteractiveLog {}
	# keep the expected messages out of the test output
	rename ::puts ::scidb::test::ni::realPuts
	proc ::puts {args} {
		if {[lindex $args 0] eq "stderr"} { return }
		return [::scidb::test::ni::realPuts {*}$args]
	}
}

proc ::scidb::test::ni::off {} {
	variable Saved
	rename ::puts {}
	rename ::scidb::test::ni::realPuts ::puts
	::dialog::nonInteractive $Saved
}

proc ::scidb::test::ni::toplevelsAbove {} {
	set n 0
	foreach c [winfo children .] { if {[winfo toplevel $c] eq $c} { incr n } }
	return $n
}

tcltest::test ni-no-dialog-built {an error dialog returns at once and builds no window} -setup {
	::scidb::test::ni::on
} -body {
	set before [::scidb::test::ni::toplevelsAbove]
	set r [::dialog::error -parent . -message "Disk full" -detail "while saving"]
	list $r [expr {[::scidb::test::ni::toplevelsAbove] - $before}] \
		[lindex [lindex $::dialog::NonInteractiveLog end] 1] \
		[lindex [lindex $::dialog::NonInteractiveLog end] 2]
} -cleanup {
	::scidb::test::ni::off
} -result {ok 0 error {Disk full -- while saving}}

tcltest::test ni-safe-replies {a question is never answered with the destructive button} -setup {
	::scidb::test::ni::on
} -body {
	list \
		[::dialog::question -parent . -message "Overwrite?"] \
		[::dialog::question -parent . -message "Save?" -buttons {yes no cancel}] \
		[::dialog::question -parent . -message "Go on?" -buttons {ok cancel}] \
		[::dialog::info -parent . -message "FYI"] \
		[::dialog::warning -parent . -message "Careful"] \
		[::dialog::safeReply {abort retry ignore}] \
		[::dialog::safeReply {{yes Yes} {retry Retry}}]
} -cleanup {
	::scidb::test::ni::off
} -result {no cancel cancel ok cancel abort yes}

tcltest::test ni-raw-tk-messagebox {a direct tk_messageBox call does not block either} -setup {
	::scidb::test::ni::on
} -body {
	list [tk_messageBox -icon error -type ok -message "raw"] \
		[tk_messageBox -icon question -type yesno -message "raw?"] \
		[lindex [lindex $::dialog::NonInteractiveLog end] 1]
} -cleanup {
	::scidb::test::ni::off
} -result {ok no question}

tcltest::test ni-background-error {a background error is logged and does not open Tk's error dialog} -setup {
	::scidb::test::ni::on
} -body {
	set before [::scidb::test::ni::toplevelsAbove]
	# bgerror keeps the last error details of the whole process in these
	set ::scidb::intern::errresult ""; set ::scidb::intern::errmsg ""; set ::scidb::intern::tclStack ""
	set ::errorCode NONE
	set ::errorInfo "boom\n    while executing\n\"nothing\""
	::scidb::bgerror "boom" {}
	list [expr {[::scidb::test::ni::toplevelsAbove] - $before}] \
		[lindex [lindex $::dialog::NonInteractiveLog end] 1] \
		[string match boom* [lindex [lindex $::dialog::NonInteractiveLog end] 2]]
} -cleanup {
	::scidb::test::ni::off
} -result {0 background-error 1}

::tcltest::cleanupTests
return
