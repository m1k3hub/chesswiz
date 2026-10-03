# ======================================================================
# Scidb App Test — the position finder (tcl/ai-positions.tcl and the
# assistant's find_positions, cql_help and open_position tools)
# ======================================================================
# A small fixture database; scripts as a model would draft them.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::findpos {
	variable Fixture [file join [file dirname [file normalize [info script]]] tmp-app findpos.pgn]
	variable Games {
		{Anderssen, Adolf} {Kieseritzky, Lionel} 1-0 1851.06.21
			{1. e4 e5 2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7# 1-0}
		{Morphy, Paul} {Duke, Karl} 1-0 1858.11.02
			{1. e4 e5 2. Nf3 d6 3. d4 Bg4 4. dxe5 Bxf3 5. Qxf3 dxe5 6. Bc4 Nf6 7. Qb3 Qe7 8. Nc3 c6 9. Bg5 b5 10. Nxb5 cxb5 11. Bxb5+ Nbd7 12. O-O-O Rd8 13. Rxd7 Rxd7 14. Rd1 Qe6 15. Bxd7+ Nxd7 16. Qb8+ Nxb8 17. Rd8# 1-0}
		{Quiet, A} {Quiet, B} 1/2-1/2 1990.01.01
			{1. d4 d5 2. c4 e6 3. Nc3 Nf6 4. Bg5 Be7 5. e3 O-O 6. Nf3 h6 7. Bh4 b6 1/2-1/2}
	}
}

proc ::scidb::test::findpos::nop {args} { return 0 }

proc ::scidb::test::findpos::openFixture {} {
	variable Fixture
	variable Games
	file mkdir [file dirname $Fixture]
	set fh [open $Fixture w]
	fconfigure $fh -encoding utf-8
	set n 0
	foreach {white black result date moves} $Games {
		incr n
		puts $fh "\[Event \"Fixture\"\]\n\[Site \"X\"\]\n\[Date \"$date\"\]\n\[Round \"$n\"\]"
		puts $fh "\[White \"$white\"\]\n\[Black \"$black\"\]\n\[Result \"$result\"\]\n\n$moves\n"
	}
	close $fh
	::scidb::db::open $Fixture ::scidb::test::findpos::nop {} ::scidb::test::findpos::nop {}
	rename ::application::assistant::ActiveBase ::scidb::test::findpos::realActiveBase
	proc ::application::assistant::ActiveBase {} { list $::scidb::test::findpos::Fixture Normal }
	# the report pane is the GUI's; record what it would show
	set ::application::assistant::Priv(cqlHelp) 1
	rename ::application::assistant::ShowPositions ::scidb::test::findpos::realShow
	proc ::application::assistant::ShowPositions {args} { set ::scidb::test::findpos::Shown $args }
}

proc ::scidb::test::findpos::closeFixture {} {
	variable Fixture
	rename ::application::assistant::ActiveBase {}
	rename ::scidb::test::findpos::realActiveBase ::application::assistant::ActiveBase
	rename ::application::assistant::ShowPositions {}
	rename ::scidb::test::findpos::realShow ::application::assistant::ShowPositions
	catch { ::scidb::db::close $Fixture }
	catch { file delete $Fixture }
}

# Run a tool the way the assistant does and wait for a deferred reply.
proc ::scidb::test::findpos::run {name cargs} {
	set reply [::application::assistant::runTool $name $cargs]
	if {![string match "\x00later:*" $reply]} { return $reply }
	# Resolve hands the reply to ToolReply; catch it there
	set ::application::assistant::Priv(pending) [list $reply 0 $name $cargs {} {}]
	rename ::application::assistant::ToolReply ::scidb::test::findpos::realToolReply
	rename ::application::assistant::RunCalls ::scidb::test::findpos::realRunCalls
	proc ::application::assistant::ToolReply {name reply} { set ::scidb::test::findpos::Reply $reply }
	proc ::application::assistant::RunCalls {args} {}
	unset -nocomplain ::scidb::test::findpos::Reply
	set timer [after 30000 {set ::scidb::test::findpos::Reply timeout}]
	vwait ::scidb::test::findpos::Reply
	after cancel $timer
	rename ::application::assistant::ToolReply {}
	rename ::application::assistant::RunCalls {}
	rename ::scidb::test::findpos::realToolReply ::application::assistant::ToolReply
	rename ::scidb::test::findpos::realRunCalls ::application::assistant::RunCalls
	return $::scidb::test::findpos::Reply
}

tcltest::testConstraint cql6 [expr {[llength [info commands ::scidb::cql6::search]]
	&& [::scidb::cql6::version] ne "cql6 stub 6.2"}]

tcltest::test findpos-normalize {a script gets a cql() header; code fences go} -body {
	list [::ai::positions::normalize "mate"] \
		[::ai::positions::normalize "```cql\ncql() mate\n```"] \
		[::ai::positions::normalize "  cql(quiet) check "]
} -result [list "cql()\nmate" "cql() mate" "cql(quiet) check"]

tcltest::test findpos-position {a match's ply maps to its position and moves ("1.e4" stays a move, not the number 10000.0)} -constraints cql6 -setup {
	::scidb::test::findpos::openFixture
} -body {
	set base $::scidb::test::findpos::Fixture
	set mid [::ai::positions::position $base Normal 0 2]
	set end [::ai::positions::position $base Normal 0 7]
	set start [::ai::positions::position $base Normal 0 0]
	list [dict get $mid move] [dict get $mid next] [lindex [dict get $mid fen] 0] \
		[dict get $end move] [dict get $end next] [lindex [dict get $end fen] 0] \
		[dict get $start move] [dict get $start next] \
		[dict get [::ai::positions::position $base Normal 0 1] move]
} -cleanup {
	::scidb::test::findpos::closeFixture
} -result {1...e5 Bc4 rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR 4.Qxf7 {} r1bqkb1r/pppp1Qpp/2n2n2/4p3/2B1P3/8/PPPP1PPP/RNB1K1NR {} e4 1.e4}

tcltest::test findpos-sample {a sample finds the mates, lists them and shows them} -constraints cql6 -setup {
	::scidb::test::findpos::openFixture
	unset -nocomplain ::scidb::test::findpos::Shown
} -body {
	set reply [::scidb::test::findpos::run find_positions {request "checkmates" cql "cql() mate"}]
	list [string match "*sample positions*not yet confirmed*" $reply] \
		[string match "*Anderssen*after 4.Qxf7*" $reply] \
		[string match "*Morphy*after 17.Rd8*" $reply] \
		[string match "*Quiet*" $reply] \
		[llength [lindex $::scidb::test::findpos::Shown 3]]
} -cleanup {
	::scidb::test::findpos::closeFixture
} -result {1 1 1 0 2}

tcltest::test findpos-header {header fields narrow the games first} -constraints cql6 -setup {
	::scidb::test::findpos::openFixture
} -body {
	set reply [::scidb::test::findpos::run find_positions {request "mates" cql "cql() mate" player Morphy color white}]
	list [string match "*Morphy*" $reply] [string match "*Anderssen*" $reply] [string match "*(1 games)*" $reply]
} -cleanup {
	::scidb::test::findpos::closeFixture
} -result {1 0 1}

tcltest::test findpos-parse-error {a script that does not parse comes back with the parser's message} -constraints cql6 -setup {
	::scidb::test::findpos::openFixture
} -body {
	set reply [::scidb::test::findpos::run find_positions {request "nonsense" cql "cql() frobnicate the queen"}]
	list [string match "error: CQL 6.2 did not run the script:*" $reply] [string match "*Fix the script*" $reply]
} -cleanup {
	::scidb::test::findpos::closeFixture
} -result {1 1}

tcltest::test findpos-none {no match says so} -constraints cql6 -setup {
	::scidb::test::findpos::openFixture
} -body {
	::scidb::test::findpos::run find_positions {request "stalemates" cql "cql() stalemate"}
} -cleanup {
	::scidb::test::findpos::closeFixture
} -match glob -result "*no position matches*"

tcltest::test findpos-all {mode all filters the game list} -constraints cql6 -setup {
	::scidb::test::findpos::openFixture
} -body {
	set reply [::scidb::test::findpos::run find_positions {request "checkmates" cql "cql() mate" mode all}]
	list [string match "*2 games with a matching position*" $reply] \
		[::scidb::view::count games $::scidb::test::findpos::Fixture Normal 0]
} -cleanup {
	catch { ::scidb::view::search $::scidb::test::findpos::Fixture Normal 0 reset none }
	::scidb::test::findpos::closeFixture
} -result {1 2}

tcltest::test findpos-open-at-match {after mode all, the game list opens a game at its match} -constraints cql6 -setup {
	::scidb::test::findpos::openFixture
} -body {
	::scidb::test::findpos::run find_positions {request "checkmates" cql "cql() mate" mode all}
	set base $::scidb::test::findpos::Fixture
	set lookup $::gamestable::PositionLookup
	set fen [{*}$lookup $base Normal 1]
	set none [{*}$lookup $base Normal 2]
	# what a double-click does with it
	::game::new .application -base $base -variant Normal -number 1 -fen $fen
	set board [lindex [::scidb::pos::fen] 0]
	::application::assistant::DoClearSearch
	list $lookup [lindex $fen 0] $none $board $::gamestable::PositionLookup
} -cleanup {
	catch { ::scidb::view::search $::scidb::test::findpos::Fixture Normal 0 reset none }
	::scidb::test::findpos::closeFixture
} -result {::application::assistant::MatchPosition 1n1Rkb1r/p4ppp/4q3/4p1B1/4P3/8/PPP2PPP/2K5 {} 1n1Rkb1r/p4ppp/4q3/4p1B1/4P3/8/PPP2PPP/2K5 {}}

tcltest::test findpos-report-links {sample reports link each position to the board; only read-only tools are followed} -constraints cql6 -setup {
	::scidb::test::findpos::openFixture
	rename ::application::assistant::ShowPositions {}
	rename ::scidb::test::findpos::realShow ::application::assistant::ShowPositions
	rename ::application::ai::showReport ::scidb::test::findpos::realReport
	proc ::application::ai::showReport {parent title html} { set ::scidb::test::findpos::Html $html }
} -body {
	::scidb::test::findpos::run find_positions {request "checkmates" cql "cql() mate"}
	set html $::scidb::test::findpos::Html
	set kept [dict get [::scidb::html::sanitize $html ""] html]
	set opened [::application::report::FollowAiLink "scidb-ai:open_position?index=2"]
	set refused [::application::report::FollowAiLink "scidb-ai:clear_search"]
	list [regexp -all {scidb-ai:open_position\?index=\d} $kept] [string match "game 2 *on the board*" $opened] \
		[string match "*clear_search*" $refused] [::application::assistant::runTool open_position {index 1}]
} -cleanup {
	rename ::application::ai::showReport {}
	rename ::scidb::test::findpos::realReport ::application::ai::showReport
	rename ::application::assistant::ShowPositions ::scidb::test::findpos::realShow
	proc ::application::assistant::ShowPositions {args} { set ::scidb::test::findpos::Shown $args }
	::scidb::test::findpos::closeFixture
} -match glob -result {2 1 1 {game 1 *on the board*}}

tcltest::test findpos-checks {arguments are checked} -body {
	list [catch { ::application::assistant::CheckArgs find_positions {request x cql ""} } e1] $e1 \
		[catch { ::application::assistant::CheckArgs find_positions {request x cql "cql() mate" mode fast} } e2] $e2 \
		[dict get [::application::assistant::CheckArgs find_positions {request x cql "cql() mate"}] mode]
} -result {1 {cql must not be empty} 1 {mode must be sample or all} sample}

tcltest::test findpos-help-first {find_positions asks for cql_help first in a conversation} -body {
	::application::assistant::clear
	set before [::application::assistant::runTool find_positions {request x cql "cql() mate"}]
	::application::assistant::runTool cql_help {}
	list [string match "error: call cql_help first*" $before] $::application::assistant::Priv(cqlHelp)
} -result {1 1}

tcltest::test findpos-help {cql_help returns a reference with worked examples} -body {
	set text [::application::assistant::runTool cql_help {}]
	list [string match "*cql()*" $text] [string match "*Request:*" $text]
} -result {1 1}

tcltest::test findpos-save-pattern {a confirmed search is saved and shows up in cql_help} -constraints cql6 -setup {
	::scidb::test::findpos::openFixture
	set savedUser [expr {[info exists ::scidb::dir::user] ? $::scidb::dir::user : ""}]
	set ::scidb::dir::user [file join [file dirname $::scidb::test::findpos::Fixture] findpos-user]
	file delete -force $::scidb::dir::user
} -body {
	::scidb::test::findpos::run find_positions {request "checkmates" cql "cql() mate"}
	set reply [::application::assistant::runTool save_pattern {name {all mates}}]
	set saved [::ai::positions::patterns]
	set help [::application::assistant::runTool cql_help {}]
	list [string match "saved as 'all mates'*1 saved pattern*" $reply] [llength $saved] \
		[dict get [lindex $saved 0] cql] [llength [dict get [lindex $saved 0] fens]] \
		[string match "*saved as 'all mates'*" $help]
} -cleanup {
	file delete -force $::scidb::dir::user
	if {$savedUser eq ""} { unset ::scidb::dir::user } else { set ::scidb::dir::user $savedUser }
	::scidb::test::findpos::closeFixture
} -result {1 1 {cql() mate} 2 1}

tcltest::test findpos-open-without-search {open_position needs a search first} -body {
	set ::application::assistant::LastPositions {}
	::application::assistant::runTool open_position {index 1}
} -match glob -result "error: there is no find_positions result*"

tcltest::test findpos-similar-checks {find_similar arguments default to pawns and material, exact, same colours} -body {
	set d [::application::assistant::CheckArgs find_similar {}]
	list [dict get $d aspects] [dict get $d tolerance] [dict get $d colours] [dict get $d mode] \
		[catch { ::application::assistant::CheckArgs find_similar {aspects {pawns kings}} } e1] $e1 \
		[catch { ::application::assistant::CheckArgs find_similar {tolerance 3} } e2] $e2
} -result {pawns 0 same sample 1 {aspects are pawns, material and pieces} 1 {tolerance must be 0, 1 or 2}}

tcltest::test findpos-similar-runs {find_similar builds the script from the board and runs it like find_positions} -constraints cql6 -setup {
	::scidb::test::findpos::openFixture
	set had [llength [info commands ::ai::similar::script]]
	if {$had} {
		rename ::ai::similar::script ::scidb::test::findpos::realScript
		rename ::ai::similar::describe ::scidb::test::findpos::realDescribe
	}
	namespace eval ::ai::similar {}
	proc ::ai::similar::script {fen args} { set ::scidb::test::findpos::Board $fen; return "cql() mate" }
	proc ::ai::similar::describe {fen args} { return "the same mating pattern" }
	# no cql_help needed: the application wrote the script
	set ::application::assistant::Priv(cqlHelp) 0
} -body {
	set reply [::scidb::test::findpos::run find_similar {aspects {pawns}}]
	# the game on the board (left out) may be one of the mates, so either
	list [string match "*positions like the one on the board: the same mating pattern*" $reply] \
		[regexp {Anderssen|Morphy} $reply] [expr {$::scidb::test::findpos::Board eq [::scidb::pos::fen]}]
} -cleanup {
	rename ::ai::similar::script {}
	rename ::ai::similar::describe {}
	if {$had} {
		rename ::scidb::test::findpos::realScript ::ai::similar::script
		rename ::scidb::test::findpos::realDescribe ::ai::similar::describe
	}
	::scidb::test::findpos::closeFixture
} -result {1 1 1}

tcltest::test findpos-offered {the tools are offered to the model} -body {
	set json [::application::assistant::toolsJson]
	list [string match {*"name":"find_positions"*} $json] [string match {*"name":"cql_help"*} $json] \
		[string match {*"name":"open_position"*} $json] [string match {*"name":"find_similar"*} $json]
} -result {1 1 1 1}

tcltest::cleanupTests
