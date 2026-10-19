# ======================================================================
# Scidb App Test Suite - Add New Variation (G05)
# ======================================================================
# Regression test for gap G05: "Add New Variation" does nothing.
# Root cause: doAction in move.tcl called ::scidb::game::tags 0 after
# creating the variation; if no game was at position 0, this threw an
# unhandled error that propagated up, making the variation appear to
# have failed even though the C++ layer created it successfully.
# Fix: wrap the tags call in a catch and use current game (no arg).
package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::addvar {
	variable testDir [file dirname [file normalize [info script]]]
	variable Fixture [file join $testDir tmp-app addvar-[pid].pgn]
	variable slot 7
}

proc ::scidb::test::addvar::nop {args} { return 0 }

proc ::scidb::test::addvar::openFixture {} {
	variable Fixture
	variable slot
	file mkdir [file dirname $Fixture]
	set fh [open $Fixture w]
	fconfigure $fh -encoding utf-8
	puts $fh "\[Event \"VariationTest\"\]\n\[Site \"X\"\]\n\[Date \"2024.01.01\"\]\n\[Round \"1\"\]"
	puts $fh "\[White \"White\"\]\n\[Black \"Black\"\]\n\[Result \"*\"\]\n"
	puts $fh "1. e4 e5 2. Nf3 Nc6 3. Bb5 *\n"
	close $fh
	::scidb::db::open $Fixture ::scidb::test::addvar::nop {} ::scidb::test::addvar::nop {}
	::scidb::game::load $slot $Fixture Normal 0
	::scidb::game::layout $slot
	::scidb::game::subscribe pgn $slot ::scidb::test::addvar::nop
	::scidb::game::switch $slot
}

proc ::scidb::test::addvar::closeFixture {} {
	variable Fixture
	catch { ::scidb::db::close $Fixture }
	catch { file delete $Fixture }
}

proc ::scidb::test::addvar::goStart {} {
	variable slot
	::scidb::game::go $slot -100
}

proc ::scidb::test::addvar::goPly1 {} {
	variable slot
	goStart
	::scidb::game::go $slot 1
}

# Open fixture and load game into a slot
::scidb::test::addvar::openFixture

set _S $::scidb::test::addvar::slot

# --- Test 1: Verify initial state ---
tcltest::test addvar-01 {Game loaded, current set, at start position} -body {
	set current_game [::scidb::game::current]
	set pos [::scidb::game::query $_S current]
	set moves [::scidb::game::next moves $_S -ascii]
	list "cur=$current_game" "pos=$pos" "moves=$moves"
} -match glob -result "*cur=$_S*pos=m-0*moves=e4*"

# --- Test 2: Navigate to ply 1, check continuations (main line is not a variation) ---
tcltest::test addvar-02 {At ply 1 after e4, main line e5 exists, no variations yet} -body {
	::scidb::test::addvar::goPly1
	set moves [::scidb::game::next moves $_S -ascii]
	set vc [::scidb::game::variation count]
	list "moves=$moves" "vc=$vc"
} -match glob -result "*moves=e5*vc=0*"

# --- Test 3: doAction variation creates a new variation (core G05 test) ---
tcltest::test addvar-03 {doAction variation b5 creates variation without error} -body {
	::scidb::test::addvar::goPly1

	set err ""
	set result ""
	if {[catch { set result [::move::doAction variation b5] } err]} {
		list "error=$err"
	} else {
		# After doAction, we're inside the new variation.
		# Leave and go back to the branch point to verify.
		::scidb::game::variation leave
		::scidb::game::go $_S -1
		set allMoves [::scidb::game::next moves $_S -ascii]
		set vc [::scidb::game::variation count]
		list "ok=$result" "vc=$vc" "allMoves=$allMoves"
	}
} -cleanup {
	::scidb::test::addvar::goStart
} -match glob -result "*ok=1*vc=1*allMoves=*b5*"

# --- Test 4: Direct C++ API variation new also works ---
tcltest::test addvar-04 {C++ API variation new c5 creates variation} -body {
	::scidb::test::addvar::goPly1

	set vcBefore [::scidb::game::variation count]
	set varno [::scidb::game::variation new c5]
	set vcAfter [::scidb::game::variation count]

	# At the branch point (still at m-0.1 after variation new), check moves
	set allMoves [::scidb::game::next moves $_S -ascii]

	list "varno=$varno" "before=$vcBefore" "after=$vcAfter" "allMoves=$allMoves"
} -cleanup {
	::scidb::test::addvar::goStart
} -match glob -result "*allMoves=*c5*"

# Cleanup
::scidb::test::addvar::closeFixture
tcltest::cleanupTests
