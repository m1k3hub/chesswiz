# ======================================================================
# Scidb App Test Suite - the pattern index (tcl/ai-pattern-index.tcl)
# ======================================================================
# The index must answer exactly what a scan answers, survive a restart
# (its file), stop answering when a pattern's script changes, and take
# the other search terms into account (::scidb::view::setGames -intersect).
# ======================================================================
package require Tcl 8.6
package require tcltest 2.5
namespace eval ::scidb::test::patternIndex {
	variable Fixture [file join [file dirname [file normalize [info script]]] tmp-app pindex-[pid].pgn]
	variable Games {
		{} 0-1 {1. f3 e5 2. g4 Qh4# 0-1}
		{} 1-0 {1. e4 c6 2. d4 d5 3. Nc3 dxe4 4. Nxe4 Nd7 5. Qe2 Ngf6 6. Nd6# 1-0}
		{} 1/2-1/2 {1. e4 e5 2. Nf3 Nc6 1/2-1/2}
		{8/P7/8/8/8/8/k7/4K3 w - - 0 1} * {1. a8=N Kb3 *}
		{4k3/4p3/8/8/8/8/4P3/4K3 w - - 0 1} * {1. e4 e5 *}
		{} * {1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. O-O d6 5. d3 Be6 6. Nc3 Qd7 7. Be3 O-O-O *}
		{k7/8/2K5/8/8/8/8/1Q6 w - - 0 1} 1/2-1/2 {1. Qb6 1/2-1/2}
		{k7/8/8/8/3P4/8/8/7K w - - 0 1} * {*}
		{k1b5/8/8/8/8/8/8/2B4K w - - 0 1} * {*}
		{rnb1k3/8/8/8/8/8/8/RNB1K3 w - - 0 1} * {*}
	}
}
proc ::scidb::test::patternIndex::nop {args} { return 0 }
proc ::scidb::test::patternIndex::openFixture {} {
	variable Fixture
	variable Games
	file mkdir [file dirname $Fixture]
	set fh [open $Fixture w]
	set n 0
	foreach {fen result moves} $Games {
		incr n
		puts $fh "\[Event \"PI\"\]\n\[Site \"X\"\]\n\[Date \"2020.01.01\"\]\n\[Round \"$n\"\]"
		puts $fh "\[White \"W$n\"\]\n\[Black \"B$n\"\]\n\[Result \"$result\"\]"
		if {$fen ne ""} { puts $fh "\[SetUp \"1\"\]\n\[FEN \"$fen\"\]" }
		puts $fh "\n$moves\n"
	}
	close $fh
	::scidb::db::open $Fixture ::scidb::test::patternIndex::nop {} ::scidb::test::patternIndex::nop {}
}
proc ::scidb::test::patternIndex::wait {varName {ms 30000}} {
	set timer [after $ms [list set $varName timeout]]
	vwait $varName
	after cancel $timer
	return [set $varName]
}
proc ::scidb::test::patternIndex::scan {base id} {
	::scidb::cql6::search $base Normal [::ai::search::pattern6 $id] -compact 1 \
		-command {set ::scidb::test::patternIndex::Scan}
	return [dict get [wait ::scidb::test::patternIndex::Scan] matches]
}
::scidb::test::patternIndex::openFixture
set ::env(SCIDB_AI_PATTERN_INDEX_MIN_GAMES) 1

tcltest::test pattern-index-equals-scan {every library pattern: the index answers what a scan answers} -body {
	set base $::scidb::test::patternIndex::Fixture
	catch { file delete [::ai::patternIndex::File $base] }
	array unset ::ai::patternIndex::Loaded
	set wanted [::ai::patternIndex::wanted $base Normal]
	set before [::ai::patternIndex::has $base Normal checkmate]
	::ai::patternIndex::build $base Normal {set ::scidb::test::patternIndex::Built}
	set built [::scidb::test::patternIndex::wait ::scidb::test::patternIndex::Built]
	set differ {}
	set found 0
	foreach id [::ai::search::patternIds] {
		set indexed [::ai::patternIndex::lookup $base Normal $id]
		if {$indexed ne [::scidb::test::patternIndex::scan $base $id]} { lappend differ $id }
		if {[llength $indexed]} { incr found }
	}
	list $wanted $before [dict get $built ok] $differ [expr {$found >= 6}]
} -result {1 0 1 {} 1}

tcltest::test pattern-index-file {the index is read back from its file} -body {
	set base $::scidb::test::patternIndex::Fixture
	set before [::ai::patternIndex::lookup $base Normal checkmate]
	array unset ::ai::patternIndex::Loaded
	list [file isfile [::ai::patternIndex::File $base]] [expr {[::ai::patternIndex::lookup $base Normal checkmate] eq $before}] \
		[llength $before]
} -result {1 1 4}

tcltest::test pattern-index-script-changed {a pattern whose script changed is not answered} -body {
	set base $::scidb::test::patternIndex::Fixture
	set saved $::ai::search::Patterns6
	dict set ::ai::search::Patterns6 checkmate {cql() mate}
	set has [::ai::patternIndex::has $base Normal checkmate]
	set other [::ai::patternIndex::has $base Normal stalemate]
	set ::ai::search::Patterns6 $saved
	list $has $other [::ai::patternIndex::has $base Normal checkmate]
} -result {0 1 1}

tcltest::test pattern-index-identity {a different game count invalidates the index} -body {
	set base $::scidb::test::patternIndex::Fixture
	set index [::ai::patternIndex::Load $base]
	set identity [lindex $index 0]
	dict set identity games 999
	set ::ai::patternIndex::Loaded([file normalize $base]) [list $identity [lindex $index 1]]
	set has [::ai::patternIndex::has $base Normal checkmate]
	array unset ::ai::patternIndex::Loaded
	list $has [::ai::patternIndex::has $base Normal checkmate]
} -result {0 1}

tcltest::test pattern-index-search {SearchView answers from the index, narrowed by the other terms} -body {
	set base $::scidb::test::patternIndex::Fixture
	set view [::scidb::view::new $base Normal unused unused unused unused master slave]
	set all [dict create player {} color any result {} opponent {} eco {} from {} to {} event PI min_elo {} pattern checkmate]
	set job [::application::assistant::SearchView $base Normal $view $all {set ::scidb::test::patternIndex::Search}]
	set count [dict get [::scidb::test::patternIndex::wait ::scidb::test::patternIndex::Search] count]
	set narrow [dict replace $all result 0-1]
	lassign [::application::assistant::SearchView $base Normal $view $narrow] query summary narrowed
	set game [::scidb::db::get gameNumber $base Normal 0 $view]
	::scidb::view::close $base Normal $view
	list $job $count $narrowed $game
} -result {{} 2 1 0}

tcltest::test pattern-index-small {a small database is scanned, never indexed} -body {
	set base $::scidb::test::patternIndex::Fixture
	set ::env(SCIDB_AI_PATTERN_INDEX_MIN_GAMES) 100000
	set wanted [::ai::patternIndex::wanted $base Normal]
	set ::env(SCIDB_AI_PATTERN_INDEX_MIN_GAMES) 1
	set wanted
} -result 0

tcltest::test pattern-index-intersect {setGames -intersect keeps only the view's games} -body {
	set base $::scidb::test::patternIndex::Fixture
	set view [::scidb::view::new $base Normal unused unused unused unused master slave]
	::scidb::view::setGames $base Normal $view {1 2 3}
	set n [::scidb::view::setGames $base Normal $view {0 2 3 5} -intersect]
	set bad [catch { ::scidb::view::setGames $base Normal $view {0} -bogus }]
	::scidb::view::close $base Normal $view
	list $n $bad
} -result {2 1}

# --- keeping the index current --------------------------------------------------

# A Scidb database of the fixture's games <from>..<to> (so that fingerprints
# exist), and a PGN file of games to add later.
proc ::scidb::test::patternIndex::pgn {file first last} {
	variable Games
	set fh [open $file w]
	set n 0
	foreach {fen result moves} $Games {
		incr n
		if {$n < $first || $n > $last} continue
		puts $fh "\[Event \"PI\"\]\n\[Site \"X\"\]\n\[Date \"2020.01.01\"\]\n\[Round \"$n\"\]"
		puts $fh "\[White \"W$n\"\]\n\[Black \"B$n\"\]\n\[Result \"$result\"\]"
		if {$fen ne ""} { puts $fh "\[SetUp \"1\"\]\n\[FEN \"$fen\"\]" }
		puts $fh "\n$moves\n"
	}
	close $fh
}
proc ::scidb::test::patternIndex::append {sci pgn} {
	::scidb::db::open $pgn ::scidb::test::patternIndex::nop {} ::scidb::test::patternIndex::nop {}
	::scidb::db::copy $pgn $sci {} ::scidb::test::patternIndex::nop {} ::scidb::test::patternIndex::nop {}
	::scidb::db::save $sci ::scidb::test::patternIndex::nop {}
	::scidb::db::close $pgn
}
proc ::scidb::test::patternIndex::allEqualScan {base} {
	set differ {}
	foreach id [::ai::search::patternIds] {
		if {[::ai::patternIndex::lookup $base Normal $id] ne [scan $base $id]} { lappend differ $id }
	}
	return $differ
}

tcltest::test pattern-index-update {added games, and a changed game, are searched alone; the index stays a scan} -setup {
	set dir [file dirname $::scidb::test::patternIndex::Fixture]
	set sci [file join $dir pindex-upd-[pid].sci]
	set first [file join $dir pindex-upd-[pid]-a.pgn]
	set more [file join $dir pindex-upd-[pid]-b.pgn]
	::scidb::test::patternIndex::pgn $first 1 6
	::scidb::test::patternIndex::pgn $more 7 10
	::scidb::db::new $sci Normal [::application::database::lookupType Unspecific]
	::scidb::db::attach $sci $sci
	::scidb::test::patternIndex::append $sci $first
	array unset ::ai::patternIndex::Loaded
	array unset ::ai::patternIndex::Plans
	catch { file delete [::ai::patternIndex::File $sci] }
} -body {
	::ai::patternIndex::build $sci Normal {set ::scidb::test::patternIndex::Built}
	set full [dict get [::scidb::test::patternIndex::wait ::scidb::test::patternIndex::Built] ok]
	set fingerprinted [expr {[string length [lindex [::ai::patternIndex::Load $sci] 2]] == 24}]

	# four games added and saved: only they are searched
	after 1100
	::scidb::test::patternIndex::append $sci $more
	set stale [::ai::patternIndex::has $sci Normal checkmate]
	set planned [dict get [::ai::patternIndex::Plan $sci Normal] games]
	::ai::patternIndex::build $sci Normal {set ::scidb::test::patternIndex::Built}
	set added [dict get [::scidb::test::patternIndex::wait ::scidb::test::patternIndex::Built] ok]
	set afterAdd [::scidb::test::patternIndex::allEqualScan $sci]

	# a game whose record changed (its stored CRC no longer agrees) and a
	# file that changed: that game alone is searched again
	lassign [::ai::patternIndex::Load $sci] identity patterns fingerprints
	dict set identity mtime 0
	set fingerprints [string replace $fingerprints 4 7 "\0\0\0\0"]
	set ::ai::patternIndex::Loaded([file normalize $sci]) [list $identity $patterns $fingerprints]
	array unset ::ai::patternIndex::Plans
	set replanned [dict get [::ai::patternIndex::Plan $sci Normal] games]
	::ai::patternIndex::build $sci Normal {set ::scidb::test::patternIndex::Built}
	set changed [dict get [::scidb::test::patternIndex::wait ::scidb::test::patternIndex::Built] ok]
	set afterChange [::scidb::test::patternIndex::allEqualScan $sci]

	# a library script that changed needs a full build
	lassign [::ai::patternIndex::Load $sci] identity patterns fingerprints
	dict set identity mtime 0
	set ::ai::patternIndex::Loaded([file normalize $sci]) [list $identity $patterns $fingerprints]
	array unset ::ai::patternIndex::Plans
	set saved $::ai::search::Patterns6
	dict set ::ai::search::Patterns6 checkmate {cql() mate}
	set library [::ai::patternIndex::updatable $sci Normal]
	set ::ai::search::Patterns6 $saved

	list $full $fingerprinted $stale $planned $added $afterAdd $replanned $changed $afterChange $library
} -cleanup {
	catch { file delete [::ai::patternIndex::File $sci] }
	array unset ::ai::patternIndex::Loaded
	array unset ::ai::patternIndex::Plans
	catch { ::scidb::db::close $sci }
	foreach f [glob -nocomplain [file rootname $sci].*] { catch { file delete $f } }
	catch { file delete $first $more }
} -result {1 1 0 {6 7 8 9} 1 {} 1 1 {} 0}

tcltest::test pattern-index-format {a format without game records (PGN) has no fingerprints and is not updated} -body {
	set base $::scidb::test::patternIndex::Fixture
	list [::ai::patternIndex::Fingerprints $base Normal] [::ai::patternIndex::updatable $base Normal]
} -result {{} 0}

catch { file delete [::ai::patternIndex::File $::scidb::test::patternIndex::Fixture] }
array unset ::ai::patternIndex::Loaded
unset -nocomplain ::env(SCIDB_AI_PATTERN_INDEX_MIN_GAMES)
catch { ::scidb::db::close $::scidb::test::patternIndex::Fixture }
catch { file delete $::scidb::test::patternIndex::Fixture }
tcltest::cleanupTests
