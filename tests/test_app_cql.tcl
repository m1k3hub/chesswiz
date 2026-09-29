# ======================================================================
# Scidb App Test Suite - ::scidb::cql (src/tcl/tcl_cql.cpp)
# ======================================================================
# The CQL matcher in src/db/cql, reached from Tcl: parse, match one game
# (the first mainline ply that satisfies the query, or -1) and search a
# database. The fixture has four known games:
#   0  Fool's mate            1.f3 e5 2.g4 Qh4#          (0-1, ply 4)
#   1  Caro-Kann smothered    ... 6.Nd6#                  (1-0, ply 11)
#   2  a quiet draw           1.e4 e5 2.Nf3 Nc6           (no check)
#   3  en passant, castling   3.exd6 e.p. (ply 5), 5...O-O (10), 6.O-O (11)
# ======================================================================
package require Tcl 8.5
package require tcltest 2.5
namespace eval ::scidb::test::cql {
	variable testDir [file dirname [file normalize [info script]]]
	variable Fixture [file join $testDir tmp-app cql-[pid].pgn]
}
proc ::scidb::test::cql::nop {args} { return 0 }
proc ::scidb::test::cql::openFixture {} {
	variable Fixture
	file mkdir [file dirname $Fixture]
	set fh [open $Fixture w]
	fconfigure $fh -encoding utf-8
	set n 0
	foreach {result moves} {
		0-1     {1. f3 e5 2. g4 Qh4# 0-1}
		1-0     {1. e4 c6 2. d4 d5 3. Nc3 dxe4 4. Nxe4 Nd7 5. Qe2 Ngf6 6. Nd6# 1-0}
		1/2-1/2 {1. e4 e5 (1... c5 2. Nf3 d6) 2. Nf3 Nc6 1/2-1/2}
		1/2-1/2 {1. e4 Nf6 2. e5 d5 3. exd6 exd6 4. Nf3 Be7 5. Bc4 O-O 6. O-O 1/2-1/2}
	} {
		incr n
		puts $fh "\[Event \"CQL\"\]\n\[Site \"X\"\]\n\[Date \"2024.01.01\"\]\n\[Round \"$n\"\]"
		puts $fh "\[White \"W$n\"\]\n\[Black \"B$n\"\]\n\[Result \"$result\"\]\n"
		puts $fh "$moves\n"
	}
	close $fh
	::scidb::db::open $Fixture ::scidb::test::cql::nop {} ::scidb::test::cql::nop {}
}
proc ::scidb::test::cql::closeFixture {} {
	variable Fixture
	catch { ::scidb::db::close $Fixture }
	catch { file delete $Fixture }
}
# the first matching ply of every fixture game
proc ::scidb::test::cql::plies {query} {
	variable Fixture
	lmap g {0 1 2 3} { ::scidb::cql::match $Fixture Normal $g $query }
}
proc ::scidb::test::cql::search {query} {
	variable Fixture
	::scidb::cql::search $Fixture Normal $query
}
::scidb::test::cql::openFixture


# --- parse ------------------------------------------------------------------

tcltest::test cql-parse-ok {a query parses and names the sections it needs} -body {
	list [::scidb::cql::parse {(match (position :mate))}] \
		[::scidb::cql::parse {(match :result 1-0 (position :mate))}] \
		[::scidb::cql::parse {(match (position))}]
} -result {{ok 1 sections positions standard 1} {ok 1 sections {gameinfo positions} standard 1} {ok 1 sections positions standard 1}}

tcltest::test cql-parse-errors {errors carry a name and an offset; nothing throws} -body {
	list [::scidb::cql::parse garbage] \
		[::scidb::cql::parse {(position :mate)}] \
		[::scidb::cql::parse {(match (position :bogus))}] \
		[::scidb::cql::parse {(match (position :mate)}]
} -result {{ok 0 error Left_Parenthesis_Expected offset 0} {ok 0 error Keyword_Match_Expected offset 1} {ok 0 error Invalid_Keyword offset 17} {ok 0 error Right_Parenthesis_Expected offset 23}}

tcltest::test cql-parse-unimplemented {half-built keywords are refused, not silently ignored} -body {
	lmap k {accumulate sumrange following} {
		dict get [::scidb::cql::parse "(match (position :$k))"] error
	}
} -result {Not_Implemented Not_Implemented Not_Implemented}


# --- position filters ---------------------------------------------------------

tcltest::test cql-mate {checkmate, and whose turn it is} -body {
	list [::scidb::test::cql::plies {(match (position :mate))}] \
		[::scidb::test::cql::plies {(match (position :wtm :mate))}] \
		[::scidb::test::cql::plies {(match (position :btm :mate))}] \
		[::scidb::test::cql::plies {(match (position :check))}]
} -result {{4 11 -1 -1} {4 -1 -1 -1} {-1 11 -1 -1} {4 11 -1 -1}}

tcltest::test cql-designators {piece designators, and the smothered-mate example from the help} -body {
	list [::scidb::test::cql::plies {(match (position qh4 :check))}] \
		[::scidb::test::cql::plies {(match (position Nd6 :mate))}] \
		[::scidb::test::cql::plies {(match (position :attackcount k [A.] 0 :btm :mate))}] \
		[::scidb::test::cql::plies {(match (position Ke1))}]
} -result {{4 -1 -1 -1} {-1 11 -1 -1} {-1 11 -1 -1} {0 0 0 0}}

tcltest::test cql-contactcheck {a contact check is by an adjacent enemy piece or a knight} -body {
	::scidb::test::cql::plies {(match (position :contactcheck))}
} -result {-1 11 -1 -1}

tcltest::test cql-terminal {the final position of every game} -body {
	::scidb::test::cql::plies {(match (position :terminal))}
} -result {4 11 4 11}

tcltest::test cql-logical {:and / :or of position lists, :sequence of consecutive positions} -body {
	list [::scidb::test::cql::plies {(match (position :and ((position :check) (position :wtm))))}] \
		[::scidb::test::cql::plies {(match (position :or ((position qh4) (position Nd6))))}] \
		[::scidb::test::cql::plies {(match (position :sequence ((position Qe2) (position Nd6))))}] \
		[::scidb::test::cql::plies {(match (position :sequence ((position :check) (position :mate))))}]
} -result {{4 -1 -1 -1} {4 11 -1 -1} {-1 11 -1 -1} {-1 -1 -1 -1}}


tcltest::test cql-attackcount {attacks on designated pieces and empty squares} -body {
	list [::scidb::test::cql::plies {(match (position :btm :attackcount k . 1 8))}] \
		[::scidb::test::cql::plies {(match (position :btm :attackcount k [A.] 0 :mate))}] \
		[::scidb::test::cql::plies {(match (position :attackcount Q k 1 8))}]
} -result {{3 5 3 5} {-1 11 -1 -1} {-1 -1 -1 -1}}

tcltest::test cql-flipcolor {either colour: the board is also tested colour-flipped} -body {
	list [::scidb::test::cql::plies {(match (position :flipcolor :wtm :mate))}] \
		[::scidb::test::cql::plies {(match (position :flipcolor :attackcount k [A.] 0 :btm :mate))}] \
		[::scidb::test::cql::plies {(match (position :flipcolor Qh5))}] \
		[::scidb::test::cql::plies {(match (position :flipcolor :movefrom K))}] \
		[dict get [::scidb::cql::parse {(match (position :flipcolor :sequence ((position :check) (position :mate))))}] error]
} -result {{4 11 -1 -1} {-1 11 -1 -1} {4 -1 -1 -1} {-1 -1 -1 10} Not_Implemented}

tcltest::test cql-variations {variations are searched only when asked for} -body {
	set f $::scidb::test::cql::Fixture
	list \
		[::scidb::test::cql::plies {(match (position pd6))}] \
		[::scidb::test::cql::plies {(match (position :variations pd6))}] \
		[::scidb::test::cql::plies {(match (position :variationsonly pd6))}] \
		[::scidb::test::cql::search {(match (position pd6))}] \
		[::scidb::test::cql::search {(match (position :variations pd6))}] \
		[::scidb::test::cql::search {(match (position :variationsonly pd6))}]
} -result {{-1 -1 -1 6} {-1 -1 5 6} {-1 -1 5 -1} 3 {2 3} 2}

# --- move filters -------------------------------------------------------------

tcltest::test cql-moves {move filters test the move that led to the position} -body {
	list [::scidb::test::cql::plies {(match (position :iscastling))}] \
		[::scidb::test::cql::plies {(match (position :iscastling :btm))}] \
		[::scidb::test::cql::plies {(match (position :enpassant))}] \
		[::scidb::test::cql::plies {(match (position :movefrom K))}] \
		[::scidb::test::cql::plies {(match (position :moveto .d6))}] \
		[::scidb::test::cql::plies {(match (position :moveto p))}]
} -result {{-1 -1 -1 10} {-1 -1 -1 11} {-1 -1 -1 5} {-1 -1 -1 11} {-1 11 -1 -1} {-1 7 -1 5}}


# --- game information and search ------------------------------------------------

tcltest::test cql-gameinfo {game-information filters alone and with positions} -body {
	list [::scidb::test::cql::plies {(match :result 1-0)}] \
		[::scidb::test::cql::plies {(match :result 1-0 (position :mate))}]
} -result {{-1 0 -1 -1} {-1 11 -1 -1}}

tcltest::test cql-search {search agrees with match game by game, also for nested lists} -body {
	set out {}
	foreach q {
		{(match (position :mate))}
		{(match (position :and ((position :check) (position :wtm))))}
		{(match (position :sequence ((position Qe2) (position Nd6))))}
		{(match (position :iscastling))}
	} {
		set expected {}
		foreach g {0 1 2 3} p [::scidb::test::cql::plies $q] { if {$p >= 0} { lappend expected $g } }
		lappend out [expr {[::scidb::test::cql::search $q] eq $expected}]
	}
	lappend out [::scidb::cql::search $::scidb::test::cql::Fixture Normal {(match (position :terminal))} 2]
} -result {1 1 1 1 {0 1}}

tcltest::test cql-errors {bad queries and indices are Tcl errors from match and search} -body {
	list [catch {::scidb::cql::match $::scidb::test::cql::Fixture Normal 0 {(match (position :bogus))}} e1] $e1 \
		[catch {::scidb::cql::match $::scidb::test::cql::Fixture Normal 9 {(match (position :mate))}} e2] $e2 \
		[dict get [::scidb::cql::parse {(match (position :following))}] error]
} -result {1 {CQL error Invalid_Keyword at offset 17} 1 {game index 9 out of range} Not_Implemented}

# --- the game list (view 0) -----------------------------------------------------

proc ::scidb::test::cql::rows {} {
	variable Fixture
	set n [::scidb::view::count games $Fixture Normal 0]
	lmap r [lrange {0 1 2 3 4 5} 0 [expr {$n - 1}]] { ::scidb::db::get gameNumber $Fixture Normal $r 0 }
}

tcltest::test cql-view {a cql term filters the game list, alone and inside AND} -body {
	set f $::scidb::test::cql::Fixture
	::scidb::view::search $f Normal 0 null none {cql {(match (position :mate))}}
	set mate [::scidb::test::cql::rows]
	::scidb::view::search $f Normal 0 null none {AND {result 1-0} {cql {(match (position :mate))}}}
	set white [::scidb::test::cql::rows]
	::scidb::view::search $f Normal 0 null none {cql {(match (position :flipcolor :enpassant))}}
	set ep [::scidb::test::cql::rows]
	set bad [list [catch {::scidb::view::search $f Normal 0 null none {cql {(match (position :bogus))}}} e] $e]
	::scidb::view::search $f Normal 0 reset none
	list $mate $white $ep $bad [::scidb::test::cql::rows]
} -result {{0 1} 1 3 {1 {::scidb::view::search cql: CQL error Invalid_Keyword at offset 17}} {0 1 2 3}}

::scidb::test::cql::closeFixture
::tcltest::cleanupTests
