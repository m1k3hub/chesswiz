# ======================================================================
# Scidb App Test — ::scidb::progress::interrupt -wait from inside the
# operation's own progress callback must not hang (review finding BIND-04).
# ======================================================================

package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

namespace eval ::scidb::test::progress {
	variable calls {}
	variable dir [file join $::env(HOME) progress-interrupt]
}

proc ::scidb::test::progress::Callback {subcmd args} {
	variable calls
	if {$subcmd eq "open"} {
		set t0 [clock milliseconds]
		set rc [::scidb::progress::interrupt -wait yes]
		lappend calls [list $rc [expr {[clock milliseconds] - $t0 < 2000}]]
	}
	return 0
}

tcltest::test progress-interrupt-nested {interrupt -wait inside the operation's callback returns 0 at once} -setup {
	set dir $::scidb::test::progress::dir
	file mkdir $dir
	set pgn [file join $dir nested.pgn]
	set f [open $pgn w]
	puts $f "\[Event \"T\"\]\n\[White \"A\"\]\n\[Black \"B\"\]\n\[Result \"*\"\]\n\n1. e4 e5 *"
	close $f
	set ::scidb::test::progress::calls {}
} -body {
	catch { ::scidb::db::open $pgn {list} {} ::scidb::test::progress::Callback {} }
	catch { ::scidb::db::close $pgn }
	list $::scidb::test::progress::calls [::scidb::progress::interrupt -wait yes]
} -cleanup {
	file delete -force $dir
} -result {{{0 1}} 1}

tcltest::cleanupTests
