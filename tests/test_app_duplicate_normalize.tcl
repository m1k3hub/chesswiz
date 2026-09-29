# Key-only duplicate normalization through the public database command.
package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::duplicate {
	variable Dir [file join [file dirname [file normalize [info script]]] tmp-app duplicates_[pid]]
}

proc ::scidb::test::duplicate::nop {args} {}

proc ::scidb::test::duplicate::create {} {
	variable Dir
	file mkdir $Dir
	set file [file join $Dir duplicates.pgn]
	set fh [open $file w]
	fconfigure $fh -encoding utf-8
	foreach {white black date round result moves} {
		{Garry Kasparov} {José Smith} 2020.04.05 3.1 1-0 {1. e4 e5 2. Nf3 Nc6}
		{Kasparov, G.} {Smith, J.} 2020.??.?? 3 1-0 {1. e4 {comment} e5 (1... c5) 2. Nf3 $1 Nc6}
		{José Smith} {Garry Kasparov} 2020.04.05 3 1-0 {1. e4 e5 2. Nf3 Nc6}
		{Garry Kasparov} {José Smith} 2020.04.05 3 0-1 {1. e4 e5 2. Nf3 Nc6}
		{Garry Kasparov} {José Smith} 2020.04.05 3 * {1. e4 e5 2. Nf3 Nc6}
		Empty Opponent 2020.04.05 1 * {}
		Empty Opponent 2020.04.05 1 * {}
	} {
		puts $fh "\[Event \"Open\"\]\n\[Site \"London\"\]\n\[Date \"$date\"\]\n\[Round \"$round\"\]"
		puts $fh "\[White \"$white\"\]\n\[Black \"$black\"\]\n\[Result \"$result\"\]\n"
		puts $fh "$moves $result\n"
	}
	close $fh
	::scidb::db::open $file ::scidb::test::duplicate::nop {} ::scidb::test::duplicate::nop {}
	return $file
}

proc ::scidb::test::duplicate::bytes {file} {
	set fh [open $file rb]
	set bytes [read $fh]
	close $fh
	return $bytes
}

proc ::scidb::test::duplicate::cleanup {file} {
	variable Dir
	::scidb::db::close $file
	file delete -force $Dir
}

tcltest::test duplicate-normalize-modes {default normalizes without modifying the PGN; exact remains available} -setup {
	set db [::scidb::test::duplicate::create]
	set before [::scidb::test::duplicate::bytes $db]
} -body {
	set normal [lsort -integer -index 0 [::scidb::db::findDuplicates $db Normal]]
	set explicit [lsort -integer -index 0 [::scidb::db::findDuplicates $db Normal -normalize 1]]
	set exact [::scidb::db::findDuplicates $db Normal -normalize 0]
	list $normal [expr {$normal eq $explicit}] $exact \
		[expr {$before eq [::scidb::test::duplicate::bytes $db]}]
} -cleanup {
	::scidb::test::duplicate::cleanup $db
} -result {{{0 1 4} {5 6}} 1 {{5 6}} 1}

tcltest::test duplicate-normalize-options {invalid options and booleans are rejected} -setup {
	set db [::scidb::test::duplicate::create]
} -body {
	list [catch {::scidb::db::findDuplicates $db Normal -bogus 1}] \
		[catch {::scidb::db::findDuplicates $db Normal -normalize garbage}]
} -cleanup {
	::scidb::test::duplicate::cleanup $db
} -result {1 1}

::tcltest::cleanupTests
return
