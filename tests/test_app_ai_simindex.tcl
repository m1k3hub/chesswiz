# ======================================================================
# Similar-game index: exact prefixes, bounded work and revision changes.
# The reader seam counts decodes; the disk fixture exercises game::dump.
# ======================================================================
package require Tcl 8.5
package require tcltest 2.5
source [file join [file dirname [file normalize [info script]]] .. tcl ai-simindex.tcl]

namespace eval ::scidb::test::simindex {
	variable Moves {{e4 e5 Nf3} {e4 e5 Nf3} {e4 e5 Nc3} {d4 d5}}
	variable Stamp 0
	variable Reads 0
}
proc ::scidb::test::simindex::reader {base variant op {n 0}} {
	variable Moves
	variable Stamp
	variable Reads
	switch $op {
		count { return [llength $Moves] }
		stamp { return $Stamp }
		game {
			incr Reads
			return [dict create start standard moves [lindex $Moves $n] white W$n black B result * year 2024]
		}
	}
}
proc ::scidb::test::simindex::get {args} {
	::ai::similar::candidates fixture Normal 0 -reader ::scidb::test::simindex::reader {*}$args
}
proc ::scidb::test::simindex::nop {args} { return 0 }

tcltest::test simindex-prefix {duplicates, prefix, no overlap, reference exclusion} -setup {
	::ai::similar::invalidate
	set ::scidb::test::simindex::Reads 0
} -body {
	set rows [::scidb::test::simindex::get]
	list $rows $::scidb::test::simindex::Reads
} -result {{{white W1 black B result * year 2024 shared 3} {white W2 black B result * year 2024 shared 2}} 4}

tcltest::test simindex-cache {warm queries do not decode again; cap applies to warm cache} -body {
	set before $::scidb::test::simindex::Reads
	list [llength [::scidb::test::simindex::get -max 2]] \
		[expr {$before == $::scidb::test::simindex::Reads}] \
		[llength [::scidb::test::simindex::get -limit 1]]
} -result {1 1 1}

tcltest::test simindex-cap {cold index caps reads and resumes without rereading} -setup {
	::ai::similar::invalidate
	set ::scidb::test::simindex::Reads 0
} -body {
	set first [llength [::scidb::test::simindex::get -max 2]]
	set reads $::scidb::test::simindex::Reads
	set rest [llength [::scidb::test::simindex::get]]
	list $first $reads $rest $::scidb::test::simindex::Reads
} -result {1 2 2 4}

tcltest::test simindex-edit {same-count edit invalidates moves and metadata} -body {
	lset ::scidb::test::simindex::Moves 1 {d4 d5}
	incr ::scidb::test::simindex::Stamp
	set rows [::scidb::test::simindex::get]
	list [llength $rows] [dict get [lindex $rows 0] white]
} -cleanup {
	lset ::scidb::test::simindex::Moves 1 {e4 e5 Nf3}
	incr ::scidb::test::simindex::Stamp
} -result {1 W2}

tcltest::test simindex-events {timer events run during indexing; zero budgets return empty} -setup {
	::ai::similar::invalidate
	set ::scidb::test::simindex::Tick 0
} -body {
	after 0 {set ::scidb::test::simindex::Tick 1}
	::scidb::test::simindex::get
	list $::scidb::test::simindex::Tick [::scidb::test::simindex::get -seconds 0] \
		[::scidb::test::simindex::get -limit 0] [::scidb::test::simindex::get -max 0]
} -result {1 {} {} {}}

tcltest::test simindex-mid-edit {in-flight invalidation discards stale work and releases guard} -body {
	after 0 ::ai::similar::invalidate
	set rc [catch {::scidb::test::simindex::get} message]
	list $rc $message [llength [::scidb::test::simindex::get]]
} -result {1 {database changed during retrieval} 2}

tcltest::test simindex-disk {real PGN dump produces ply tokens and tag facts} -setup {
	set dir [file join [file dirname [file normalize [info script]]] tmp-app simindex_[pid]]
	file mkdir $dir
	set base [file join $dir games.pgn]
	set fd [open $base w]
	foreach moves {{1. e4 e5 2. Nf3} {1. e4 e5 2. Nf3} {1. e4 e5 2. Nc3} {1. d4 d5}} {
		puts $fd {[Event "Index"]}
		puts $fd {[Site "X"]}
		puts $fd {[Date "2024.01.01"]}
		puts $fd {[Round "1"]}
		puts $fd {[White "White"]}
		puts $fd {[Black "Black"]}
		puts $fd {[Result "*"]}
		puts $fd "\n$moves *\n"
	}
	close $fd
	::scidb::db::open $base ::scidb::test::simindex::nop {} ::scidb::test::simindex::nop {}
} -body {
	set rows [::ai::similar::candidates $base Normal 0]
	list [llength $rows] [dict get [lindex $rows 0] shared] \
		[dict get [lindex $rows 1] shared] [dict get [lindex $rows 0] year]
} -cleanup {
	catch {::scidb::db::close $base}
	file delete -force $dir
} -result {2 3 2 2024}

tcltest::testConstraint nativeSimilar [llength [info commands ::scidb::db::similar]]

tcltest::test simindex-native {native PGN ranking, caps, validation and dispatch} -constraints nativeSimilar -setup {
	set dir [file join [file dirname [file normalize [info script]]] tmp-app simindex_[pid]]
	file mkdir $dir
	set base [file join $dir games.pgn]
	set fd [open $base w]
	foreach moves {{1. e4 e5 2. Nf3} {1. e4 e5 2. Nf3} {1. e4 e5 2. Nc3} {1. d4 d5}} {
		puts $fd {[Event "Index"]}
		puts $fd {[Site "X"]}
		puts $fd {[Date "2024.01.01"]}
		puts $fd {[Round "1"]}
		puts $fd {[White "White"]}
		puts $fd {[Black "Black"]}
		puts $fd {[Result "*"]}
		puts $fd "\n$moves *\n"
	}
	close $fd
	::scidb::db::open $base ::scidb::test::simindex::nop {} ::scidb::test::simindex::nop {}
} -body {
	set rows [::scidb::db::similar $base Normal 0]
	set facts {}
	foreach row $rows {
		lappend facts [list [dict get $row number] [dict get $row shared] \
			[dict get $row white] [dict get $row black] [dict get $row result] [dict get $row year]]
	}
	set caps {}
	foreach args {{-limit 1} {-max 2} {-max 1} {-seconds 0} {-limit 0} {-max 0}} {
		lappend caps [llength [::scidb::db::similar $base Normal 0 {*}$args]]
	}
	set errors {}
	foreach args {{-limit -1} {-max -1} {-seconds -1} {-seconds Inf} {-seconds NaN} {-bogus 1} {-limit}} {
		lappend errors [catch {::scidb::db::similar $base Normal 0 {*}$args}]
	}
	lappend errors [catch {::scidb::db::similar $base Normal 4}]
	# A fallback call would fail immediately: native dispatch must bypass it.
	rename ::ai::similar::IndexCollect ::ai::similar::SavedIndexCollect
	proc ::ai::similar::IndexCollect {args} { error "unexpected fallback" }
	set dispatched [expr {$rows eq [::ai::similar::candidates $base Normal 0]}]
	list $facts $caps $errors $dispatched
} -cleanup {
	catch {rename ::ai::similar::IndexCollect {}}
	catch {rename ::ai::similar::SavedIndexCollect ::ai::similar::IndexCollect}
	catch {::scidb::db::close $base}
	file delete -force $dir
} -result {{{1 3 White Black * 2024} {2 2 White Black * 2024}} {1 1 0 0 0 0} {1 1 1 1 1 1 1 1} 1}

tcltest::test simindex-native-start {exact starts, empty games, mainlines and heap replacement} -constraints nativeSimilar -setup {
	set dir [file join [file dirname [file normalize [info script]]] tmp-app simindex_[pid]]
	file mkdir $dir
	set base [file join $dir starts.pgn]
	set fd [open $base w]
	foreach {fen moves} {
		{} {1. e4 e5 2. Nf3}
		{} {1. e4}
		{rnbqkbnr/ppppppp1/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1} {1. e4 e5 2. Nf3}
		{} {}
		{} {1. e4 (1. d4 d5) e5 2. Nf3}
		{rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 7 9} {9. e4 e5 10. Nf3}
	} {
		foreach {tag value} {Event Starts Site X Date 2024.01.01 Round 1 White W Black B Result *} {
			puts $fd [format {[%s "%s"]} $tag $value]
		}
		if {$fen ne ""} {
			puts $fd {[SetUp "1"]}
			puts $fd [format {[FEN "%s"]} $fen]
		}
		puts $fd "\n$moves *\n"
	}
	close $fd
	::scidb::db::open $base ::scidb::test::simindex::nop {} ::scidb::test::simindex::nop {}
} -body {
	set stamp [::scidb::db::get lastChange $base Normal]
	set rows [::scidb::db::similar $base Normal 0 -limit 2]
	set facts {}
	foreach row $rows { lappend facts [list [dict get $row number] [dict get $row shared]] }
	list $facts [::scidb::db::similar $base Normal 3] \
		[expr {$stamp eq [::scidb::db::get lastChange $base Normal]}] \
		[dict get [lindex [::scidb::db::similar $base Normal 4 -max 2 -limit 1] 0] number]
} -cleanup {
	catch {::scidb::db::close $base}
	file delete -force $dir
} -result {{{4 3} {5 3}} {} 1 0}

::tcltest::cleanupTests
return
