# ======================================================================
# Scidb App Test — name patterns with spaces inside (util::Pattern,
# src/util/u_match.cpp). Pattern::normalize dropped the spaces before an
# ordinary character, so "Karvina 5th" became "Karvina5th" and no event,
# site or player whose name has a space inside was ever found.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::names {
	variable Fixture [file join [file dirname [file normalize [info script]]] tmp-app names.pgn]
}

proc ::scidb::test::names::openFixture {} {
	variable Fixture
	file mkdir [file dirname $Fixture]
	set fh [open $Fixture w]
	set n 0
	foreach {event site white black} {
		{Karvina 5th} {Karvina} {van der Wiel, John} {Smith, A}
		{Wijk aan Zee Open} {Wijk aan Zee} {Carlsen, Magnus} {van der Wiel, John}
		{Ch CZE} {Praha} {Novak, P} {Smith, A}
	} {
		puts $fh "\[Event \"$event\"\]\n\[Site \"$site\"\]\n\[Date \"2020.01.01\"\]\n\[Round \"[incr n]\"\]"
		puts $fh "\[White \"$white\"\]\n\[Black \"$black\"\]\n\[Result \"*\"\]\n\n1. e4 *\n"
	}
	close $fh
	::scidb::db::open $Fixture {apply {args {return 0}}} {} {apply {args {return 0}}} {}
}

proc ::scidb::test::names::count {term} {
	variable Fixture
	set view [::scidb::view::new $Fixture Normal unused unused unused unused master slave]
	::scidb::view::search $Fixture Normal $view null none $term
	set n [::scidb::view::count games $Fixture Normal $view]
	::scidb::view::close $Fixture Normal $view
	return $n
}

tcltest::test names-spaces-inside {names with spaces inside are found, whole or in part} -setup {
	::scidb::test::names::openFixture
} -body {
	lmap term {
		{eventname {Karvina 5th}}
		{eventname {*Karvina 5th*}}
		{eventname {*aan Zee*}}
		{eventname {Wijk aan Zee Open}}
		{sitename {Wijk aan Zee}}
		{playername {van der Wiel, John}}
		{playername {*der Wiel*}}
		{eventname {*Ch *}}
		{eventname {*Karvina 6th*}}
	} { ::scidb::test::names::count $term }
} -cleanup {
	catch { ::scidb::db::close $::scidb::test::names::Fixture }
	catch { file delete $::scidb::test::names::Fixture }
} -result {1 1 1 1 1 2 2 1 0}

tcltest::cleanupTests
