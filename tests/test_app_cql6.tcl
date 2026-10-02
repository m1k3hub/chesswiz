# App-backed acceptance tests for the CQL 6 host and its test-only engine.
package require Tcl 8.5
package require tcltest 2.5

# Stub commands exercise the host adapter; real-language coverage is separate.
if {[::scidb::cql6::version] ne "cql6 stub 6.2"} { return }

namespace eval ::scidb::test::cql6 {
	variable dir [file join [file dirname [file normalize [info script]]] tmp-app]
	variable small [file join $dir cql6-small-[pid].pgn]
	variable large [file join $dir cql6-large-[pid].pgn]
	variable conversion [file join $dir cql6-conversion-[pid].pgn]
	variable Done {}
	variable samples {}
	variable gaps {}
	variable last 0
	variable timer {}
}

proc ::scidb::test::cql6::nop {args} { return 0 }
proc ::scidb::test::cql6::openBase {path} {
	::scidb::db::open $path ::scidb::test::cql6::nop {} ::scidb::test::cql6::nop {}
}
proc ::scidb::test::cql6::writeGame {fh n moves {fen {}} {date 2024.03.07}} {
	foreach {tag value} [list Event CQL6 Site London Date $date Round [expr {$n + 1}] White "White $n" \
		Black "Black $n" Result * WhiteElo 2101 BlackElo 2202 ECO C20 Annotator Tester] {
		puts $fh "\[$tag \"$value\"\]"
	}
	if {$fen ne {}} { puts $fh "\[SetUp \"1\"\]\n\[FEN \"$fen\"\]" }
	puts $fh "\n$moves\n"
}
proc ::scidb::test::cql6::makeFixture {path n} {
	file mkdir [file dirname $path]
	set fh [open $path w]
	fconfigure $fh -encoding utf-8
	for {set i 0} {$i < $n} {incr i} { writeGame $fh $i {1. e4 e5 2. Nf3 *} }
	close $fh
	openBase $path
}
proc ::scidb::test::cql6::indexes {r} { lmap m [dict get $r matches] {dict get $m game} }
proc ::scidb::test::cql6::dump {} {
	variable conversion
	lmap m [dict get [::scidb::cql6::search $conversion Normal DUMP -pgn 1 -variations 1] matches] {
		dict get $m pgn
	}
}
proc ::scidb::test::cql6::receive {r} { set ::scidb::test::cql6::Done $r }
proc ::scidb::test::cql6::waitResult {} {
	variable Done
	set timeout [after 15000 {set ::scidb::test::cql6::Done timeout}]
	if {$Done eq {}} { vwait ::scidb::test::cql6::Done }
	after cancel $timeout
	if {$Done eq "timeout"} { error "CQL 6 callback timed out" }
	return $Done
}
proc ::scidb::test::cql6::tick {job} {
	variable last
	variable samples
	variable gaps
	variable timer
	set now [clock milliseconds]
	lappend gaps [expr {$now - $last}]
	set last $now
	lappend samples [::scidb::cql6::progress $job]
	set timer [after 20 [list ::scidb::test::cql6::tick $job]]
}
proc ::scidb::test::cql6::atProgress {job threshold action} {
	if {[::scidb::cql6::progress $job] >= $threshold} {
		{*}$action
	} elseif {[::scidb::cql6::progress $job] >= 0} {
		after 5 [list ::scidb::test::cql6::atProgress $job $threshold $action]
	}
}

::scidb::test::cql6::makeFixture $::scidb::test::cql6::small 12
::scidb::test::cql6::makeFixture $::scidb::test::cql6::large 600
set fh [open $::scidb::test::cql6::conversion w]
fconfigure $fh -encoding utf-8
::scidb::test::cql6::writeGame $fh 0 \
	{1. e4 (1. d4 {variation note} d5 (1... Nf6 {nested note})) e5 2. Nf3 Nc6 3. Bc4 Bc5 4. O-O Nf6 5. d3 O-O *}
::scidb::test::cql6::writeGame $fh 1 {1. O-O-O *} {7k/8/8/8/8/8/8/R3K3 w Q - 0 1}
::scidb::test::cql6::writeGame $fh 2 {1... O-O-O *} {r3k3/8/8/8/8/8/8/7K b q - 0 1}
::scidb::test::cql6::writeGame $fh 3 {1. e4 a6 2. e5 d5 3. exd6 *}
set n 4
foreach piece {Q R B N} {
	::scidb::test::cql6::writeGame $fh $n "1. a8=$piece *" {7k/P7/8/8/8/8/8/7K w - - 0 1}
	incr n
}
::scidb::test::cql6::writeGame $fh 8 {1. d4 *} {} {????.??.??}
::scidb::test::cql6::writeGame $fh 9 {{opening note} 1. e4 {move note} e5 {end note} *}
close $fh
::scidb::test::cql6::openBase $::scidb::test::cql6::conversion

tcltest::test cql6-version {version comes from the linked engine} -body {
	::scidb::cql6::version
} -result {cql6 stub 6.2}

tcltest::test cql6-all {every game, sorted indexes, default workers and no unsolicited PGN} -body {
	set r [::scidb::cql6::search $::scidb::test::cql6::small Normal MATCH_ALL]
	list [::scidb::test::cql6::indexes $r] [dict get $r games] [dict get $r threads] \
		[dict get $r cancelled] [dict get $r messages] [dict exists [lindex [dict get $r matches] 0] pgn] \
		[lsort -unique [lmap m [dict get $r matches] {dict get $m first_ply}]]
} -result {{0 1 2 3 4 5 6 7 8 9 10 11} 12 4 0 {} 0 0}

tcltest::test cql6-even {even indexes and exact first-ply values} -body {
	set r [::scidb::cql6::search $::scidb::test::cql6::small Normal MATCH_EVEN -threads 3]
	list [::scidb::test::cql6::indexes $r] \
		[lmap m [dict get $r matches] {dict get $m first_ply}] [dict get $r games] [dict get $r threads]
} -result {{0 2 4 6 8 10} {0 2 4 6 1 3} 12 3}

tcltest::test cql6-max {max is exact even with parallel workers} -body {
	set r [::scidb::cql6::search $::scidb::test::cql6::small Normal MATCH_EVEN -max 3 -threads 8]
	list [::scidb::test::cql6::indexes $r] [dict get $r games] [dict get $r threads]
} -result {{0 2 4} 5 8}

tcltest::test cql6-none {unknown scripts match nothing but still examine all games} -body {
	set r [::scidb::cql6::search $::scidb::test::cql6::small Normal OTHER -threads 1]
	list [dict get $r matches] [dict get $r games] [dict get $r threads]
} -result {{} 12 1}

tcltest::test cql6-tags {mandatory tags, date, ratings, opening code, retained extra tag} -body {
	set text [lindex [::scidb::test::cql6::dump] 0]
	set out {}
	foreach tag {White:White\ 0 Black:Black\ 0 Event:CQL6 Site:London Date:2024.03.07 \
		Round:1 Result:* WhiteElo:2101 BlackElo:2202 ECO:C20 Annotator:Tester} {
		lappend out [expr {[string first $tag $text] >= 0}]
	}
	lappend out [regexp {ntags=([0-9]+)} $text -> count] [expr {$count >= 11}]
	set out
} -result {1 1 1 1 1 1 1 1 1 1 1 1 1}

tcltest::test cql6-fen {standard start is null; custom start is a complete FEN} -body {
	set dump [::scidb::test::cql6::dump]
	list [string match {number=0 fen=- *} [lindex $dump 0]] \
		[string match {number=1 fen=7k/8/8/8/8/8/8/R3K3 w Q - 0 1 *} [lindex $dump 1]] \
		[expr {[string first {Date:????.??.??} [lindex $dump 8]] >= 0}]
} -result {1 1 1}

tcltest::test cql6-castling {both colours and both castling wings use king destinations} -body {
	set dump [::scidb::test::cql6::dump]
	list [expr {[string first {4-6} [lindex $dump 0]] >= 0}] \
		[expr {[string first {60-62} [lindex $dump 0]] >= 0}] \
		[string match {*moves=4-2} [lindex $dump 1]] [string match {*moves=60-58} [lindex $dump 2]]
} -result {1 1 1 1}

tcltest::test cql6-ep {en passant is the pawn move to the captured pawn's passed square} -body {
	string match {*moves=12-28,48-40,28-36,51-35,36-43} [lindex [::scidb::test::cql6::dump] 3]
} -result 1

tcltest::test cql6-promotions {all four promotion piece encodings} -body {
	lmap text [lrange [::scidb::test::cql6::dump] 4 7] {
		regexp {moves=(.*)$} $text -> moves
		set moves
	}
} -result {48-56Q 48-56R 48-56B 48-56N}

tcltest::test cql6-variations {nested variation delimiters and comments in their proper lines} -body {
	set text [lindex [::scidb::test::cql6::dump] 0]
	string match {*moves=12-28,(,11-27{variation note},51-35,(,62-45{nested note},),),52-36,*} $text
} -result 1

tcltest::test cql6-mainline {disabled variations omit their moves, delimiters, and comments} -body {
	set r [::scidb::cql6::search $::scidb::test::cql6::conversion Normal DUMP -pgn 1 -variations 0 -max 1]
	set text [dict get [lindex [dict get $r matches] 0] pgn]
	list [string match {*moves=12-28,52-36,6-21,57-42,5-26,61-34,4-6,62-45,11-19,60-62} $text] \
		[expr {[string first {(} $text] < 0 && [string first {)} $text] < 0 && [string first {note} $text] < 0}]
} -result {1 1}

tcltest::test cql6-comments {preceding, move and final comments survive as one-line dump text} -body {
	set text [lindex [::scidb::test::cql6::dump] 9]
	regexp {moves=(.*)$} $text -> moves
	list [expr {$moves eq {12-28{opening note\nmove note},52-36{end note}}}] \
		[expr {[string first \n $text] < 0}]
} -result {1 1}

tcltest::test cql6-errors {engine and database errors leave the application usable} -body {
	list [catch {::scidb::cql6::search $::scidb::test::cql6::small Normal ERROR} error] $error \
		[catch {::scidb::cql6::search no-such-database Normal MATCH_ALL} error] $error \
		[dict get [::scidb::cql6::search $::scidb::test::cql6::small Normal MATCH_ALL] games]
} -result {1 {stub error} 1 {unknown database 'no-such-database'} 12}

tcltest::test cql6-options {malformed arguments are errors, never unbounded resource requests} -body {
	set out {}
	foreach args {{-threads -1} {-threads 257} {-max -1} {-variations 2} {-pgn 2} \
		{-bogus 1} {-threads x} {-command {}} {-threads}} {
		lappend out [catch {::scidb::cql6::search $::scidb::test::cql6::small Normal MATCH_ALL {*}$args}]
	}
	set out
} -result {1 1 1 1 1 1 1 1 1}

# Tcl 8.5 has no lseq; keep the expected 600-index check explicit.
proc ::scidb::test::cql6::sequence {n} {
	set out {}
	for {set i 0} {$i < $n} {incr i} { lappend out $i }
	return $out
}

tcltest::test cql6-async {600 games, growing progress, responsive 20ms timer and one completion} -setup {
	set ::scidb::test::cql6::Done {}
	set ::scidb::test::cql6::samples {}
	set ::scidb::test::cql6::gaps {}
	set ::scidb::test::cql6::last [clock milliseconds]
} -body {
	set job [::scidb::cql6::search $::scidb::test::cql6::large Normal SLOW -command ::scidb::test::cql6::receive]
	set isid [string is integer -strict $job]
	::scidb::test::cql6::tick $job
	set r [::scidb::test::cql6::waitResult]
	after cancel $::scidb::test::cql6::timer
	set maxgap [tcl::mathfunc::max {*}$::scidb::test::cql6::gaps]
	puts "CQL6 async: timer max gap ${maxgap}ms; [llength $::scidb::test::cql6::samples] progress samples"
	list $isid [dict get $r ok] [dict get $r games] [llength [dict get $r matches]] \
		[dict get $r cancelled] [expr {$maxgap < 100}] \
		[expr {[llength [lsort -unique $::scidb::test::cql6::samples]] > 3}] \
		[expr {[::scidb::cql6::progress $job] == -1}] [::scidb::cql6::cancel $job] \
		[expr {[::scidb::test::cql6::indexes $r] eq [::scidb::test::cql6::sequence 600]}]
} -cleanup {
	after cancel $::scidb::test::cql6::timer
} -result {1 1 600 600 0 1 1 1 0 1}

tcltest::test cql6-cancel {cancel after about 300 games preserves the matches already found} -setup {
	set ::scidb::test::cql6::Done {}
	set ::scidb::test::cql6::CancelReturn 0
} -body {
	set job [::scidb::cql6::search $::scidb::test::cql6::large Normal SLOW -command ::scidb::test::cql6::receive]
	::scidb::test::cql6::atProgress $job 300 [list apply {{job} {
		set ::scidb::test::cql6::CancelReturn [::scidb::cql6::cancel $job]
	}} $job]
	set r [::scidb::test::cql6::waitResult]
	set n [dict get $r games]
	puts "CQL6 cancel: $n games examined"
	list $::scidb::test::cql6::CancelReturn [dict get $r ok] [dict get $r cancelled] \
		[expr {$n >= 300 && $n < 600}] [expr {$n == [llength [dict get $r matches]]}] \
		[expr {[::scidb::test::cql6::indexes $r] eq [::scidb::test::cql6::sequence $n]}]
} -result {1 1 1 1 1 1}

tcltest::test cql6-busy {second sync or async search is rejected while a job runs} -setup {
	set ::scidb::test::cql6::Done {}
} -body {
	set job [::scidb::cql6::search $::scidb::test::cql6::large Normal SLOW -command ::scidb::test::cql6::receive]
	set out [list [catch {::scidb::cql6::search $::scidb::test::cql6::small Normal MATCH_ALL} error] $error \
		[catch {::scidb::cql6::search $::scidb::test::cql6::small Normal MATCH_ALL -command ::scidb::test::cql6::receive} error] $error]
	::scidb::cql6::cancel $job
	::scidb::test::cql6::waitResult
	set out
} -result {1 {CQL 6 engine busy} 1 {CQL 6 engine busy}}

tcltest::test cql6-async-error {engine errors arrive through the main-thread callback} -body {
	set ::scidb::test::cql6::Done {}
	::scidb::cql6::search $::scidb::test::cql6::small Normal ERROR -command ::scidb::test::cql6::receive
	::scidb::test::cql6::waitResult
} -result {ok 0 error {stub error}}

tcltest::test cql6-close {close during a search cancels safely and reports the closed database} -setup {
	set ::scidb::test::cql6::Done {}
} -body {
	set job [::scidb::cql6::search $::scidb::test::cql6::large Normal SLOW -command ::scidb::test::cql6::receive]
	::scidb::test::cql6::atProgress $job 50 [list ::scidb::db::close $::scidb::test::cql6::large]
	::scidb::test::cql6::waitResult
} -cleanup {
	::scidb::test::cql6::openBase $::scidb::test::cql6::large
} -result {ok 0 error {database closed}}

tcltest::test cql6-reopen {closing and immediately reopening the same name cannot revive a job} -setup {
	set ::scidb::test::cql6::Done {}
} -body {
	set job [::scidb::cql6::search $::scidb::test::cql6::large Normal SLOW -command ::scidb::test::cql6::receive]
	::scidb::test::cql6::atProgress $job 50 [list apply {{} {
		::scidb::db::close $::scidb::test::cql6::large
		::scidb::test::cql6::openBase $::scidb::test::cql6::large
	}}]
	::scidb::test::cql6::waitResult
} -result {ok 0 error {database closed}}

tcltest::test cql6-unknown {unknown jobs have stable progress and cancel responses} -body {
	list [::scidb::cql6::progress -1] [::scidb::cql6::cancel -1]
} -result {-1 0}

source [file join [file dirname [info script]] .. src cql6stub task2b_tests.tcl]

foreach path [list $::scidb::test::cql6::small $::scidb::test::cql6::large $::scidb::test::cql6::conversion] {
	catch {::scidb::db::close $path}
	file delete $path
}
::tcltest::cleanupTests
