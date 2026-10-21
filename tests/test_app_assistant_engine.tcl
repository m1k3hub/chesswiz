# Exercise the Assistant's real start_engine tool, including the async UCI
# ready handshake. An active process alone does not prove analysis started.
package require tcltest 2.5
set program ""
if {[info exists ::env(SCIDB_TEST_ENGINE)]} {set program $::env(SCIDB_TEST_ENGINE)}
if {$program eq "" && [llength [auto_execok stockfish]]} {set program [lindex [auto_execok stockfish] 0]}
if {$program eq "" && [file executable /usr/games/stockfish]} {set program /usr/games/stockfish}
tcltest::testConstraint assistantRealEngine [expr {$program ne "" && [file executable $program]}]
namespace eval ::scidb::test::assistantEngine {}
proc ::scidb::test::assistantEngine::yes {args} {return 1}
proc ::scidb::test::assistantEngine::wait {ms} {
	set ::scidb::test::assistantEngine::waiting 0
	after $ms {set ::scidb::test::assistantEngine::waiting 1}
	vwait ::scidb::test::assistantEngine::waiting
}
tcltest::test assistant-start-engine-produces-lines {start_engine reaches the Analysis pane with real PV lines} -constraints assistantRealEngine -setup {
	set savedEngines $::engine::Engines
	set savedFile $::scidb::file::engines
	set savedConfirm $::application::assistant::Priv(confirm)
	set ::engine::Engines {}
	set ::scidb::file::engines [file join [::tcltest::temporaryDirectory] assistant-engine-[pid].dat]
	set ::application::assistant::Priv(confirm) ::scidb::test::assistantEngine::yes
} -body {
	::application::switchTab board
	set added [::application::assistant::runTool add_engine [list path $program]]
	set result [::application::assistant::runTool start_engine {lines 3 threads 1 hash 32}]
	set number [lindex [::application::analysis::Running] 0]
	for {set i 0} {$i < 200 && ![llength [::application::analysis::lines $number]]} {incr i} {
		::scidb::test::assistantEngine::wait 50
	}
	set lines [::application::analysis::lines $number]
	list [string match {*is analysing*} $result] [::engine::active? $number] \
		[expr {[llength $lines] > 0}] [expr {[lindex [lindex $lines 0] 2] > 0}] \
		[expr {[string length [lindex [lindex $lines 0] 8]] > 0}]
} -cleanup {
	foreach n [::application::analysis::Running] {::application::analysis::stopEngine $n}
	set ::engine::Engines $savedEngines
	file delete -force $::scidb::file::engines
	set ::scidb::file::engines $savedFile
	set ::application::assistant::Priv(confirm) $savedConfirm
} -result {1 1 1 1 1}

tcltest::test assistant-last-move-context {current_game provides the predecessor FEN without changing the board} -body {
	::ai::setup::position -moves {1.e4 e5 2.Nf3 Nc6 3.Bb5 a6}
	set slot [::scidb::game::current]
	set fen [::scidb::pos::fen]
	set key [::scidb::game::query current]
	set before [dict get [::ai::setup::validate -moves {1.e4 e5 2.Nf3 Nc6 3.Bb5}] fen]
	set text [::application::assistant::runTool current_game {}]
	# movefen normalizes the half-move clock; verify the board, side,
	# castling and en-passant fields against an independent forward walk.
	regexp {position before last move: ([^\n]+)} $text -> previous
	set result [list [string match {*last move: *a6*} $text] \
		[expr {[lrange $previous 0 3] eq [lrange $before 0 3]}] \
		[expr {[::scidb::pos::fen] eq $fen}] \
		[expr {[::scidb::game::query current] eq $key}] [::scidb::game::query modified?]]
	::game::release $slot
	set result
} -result {1 1 1 1 0}
tcltest::cleanupTests
