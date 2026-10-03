source [file join [file dirname [info script]] .. tcl ai-search.tcl]
# ======================================================================
# Scidb App Test Suite - plain-language search (tcl/ai-search.tcl)
# ======================================================================
# A request becomes the search_games fields plus a pattern id; no model
# writes query text or CQL. Covers the deterministic extraction, the model
# (stub provider) and classifier (stubbed ::ai::decide) stages, every CQL
# template of the pattern library against purpose-built games, and the
# whole path into the main game list.
# ======================================================================
package require Tcl 8.5
package require tcltest 2.5
namespace eval ::scidb::test::cql6patterns {
	variable testDir [file dirname [file normalize [info script]]]
	variable Fixture [file join $testDir tmp-app nlsearch-[pid].pgn]
	# game index -> what it contains
	variable Games {
		{} 0-1 {1. f3 e5 2. g4 Qh4# 0-1}
		{} 1-0 {1. e4 c6 2. d4 d5 3. Nc3 dxe4 4. Nxe4 Nd7 5. Qe2 Ngf6 6. Nd6# 1-0}
		{} 1/2-1/2 {1. e4 e5 2. Nf3 Nc6 1/2-1/2}
		{} 1/2-1/2 {1. e4 Nf6 2. e5 d5 3. exd6 exd6 4. Nf3 Be7 5. Bc4 O-O 6. O-O 1/2-1/2}
		{8/P7/8/8/8/8/k7/4K3 w - - 0 1} * {1. a8=N Kb3 *}
		{4k2r/8/8/8/8/8/8/R3K3 w - - 0 1} * {1. Ra8+ Kd7 *}
		{4k3/4p3/8/8/8/8/4P3/4K3 w - - 0 1} * {1. e4 e5 *}
		{} * {1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. O-O d6 5. d3 Be6 6. Nc3 Qd7 7. Be3 O-O-O *}
		{k7/8/2K5/8/8/8/8/1Q6 w - - 0 1} 1/2-1/2 {1. Qb6 1/2-1/2}
		{4k3/8/8/8/4N3/8/8/4RK2 w - - 0 1} * {1. Nd6+ Kd7 *}
	}
}
proc ::scidb::test::cql6patterns::nop {args} { return 0 }
proc ::scidb::test::cql6patterns::openFixture {} {
	variable Fixture
	variable Games
	file mkdir [file dirname $Fixture]
	set fh [open $Fixture w]
	fconfigure $fh -encoding utf-8
	set n 0
	foreach {fen result moves} $Games {
		incr n
		puts $fh "\[Event \"NLS\"\]\n\[Site \"X\"\]\n\[Date \"2020.01.01\"\]\n\[Round \"$n\"\]"
		puts $fh "\[White \"W$n\"\]\n\[Black \"B$n\"\]\n\[Result \"$result\"\]"
		if {$fen ne ""} { puts $fh "\[SetUp \"1\"\]\n\[FEN \"$fen\"\]" }
		puts $fh "\n$moves\n"
	}
	close $fh
	::scidb::db::open $Fixture ::scidb::test::cql6patterns::nop {} ::scidb::test::cql6patterns::nop {}
}
proc ::scidb::test::cql6patterns::closeFixture {} {
	variable Fixture
	catch { ::scidb::db::close $Fixture }
	catch { file delete $Fixture }
}
# interpret synchronously
proc ::scidb::test::cql6patterns::interpret {request args} {
	variable Result
	unset -nocomplain Result
	::ai::search::interpret $request {set ::scidb::test::cql6patterns::Result} {*}$args
	set timer [after 5000 {set ::scidb::test::cql6patterns::Result timeout}]
	vwait ::scidb::test::cql6patterns::Result
	after cancel $timer
	return $Result
}
# the given (non-empty) criteria, the pattern and the sources, compactly
proc ::scidb::test::cql6patterns::brief {interpretation} {
	list [dict filter [dict get $interpretation criteria] value ?*] \
		[dict get $interpretation pattern] [dict get $interpretation sources]
}
lappend ::scidb::test::cql6patterns::Games \
    {k7/8/8/8/3P4/8/8/7K w - - 0 1} * {*} \
    {k1b5/8/8/8/8/8/8/2B4K w - - 0 1} * {*} \
    {rnb1k3/8/8/8/8/8/8/RNB1K3 w - - 0 1} * {*}
::scidb::test::cql6patterns::openFixture


tcltest::test cql6-patterns-parity {all vetted scripts match legacy semantics with positive cases} -body {
    set fixture $::scidb::test::cql6patterns::Fixture
    set output {}
    foreach id [::ai::search::patternIds] {
        set expected [::scidb::cql::search $fixture Normal [dict get [::ai::search::pattern $id] cql]]
        set result [::scidb::cql6::search $fixture Normal [::ai::search::pattern6 $id] -threads 8]
        set games [lmap m [dict get $result matches] {dict get $m game}]
        if {$games ne $expected} {error "$id: expected $expected, got $games"}
        if {![llength $games]} {error "$id has no positive fixture"}
        lappend output $id
    }
    expr {$output eq [::ai::search::patternIds]}
} -result 1
# Load the production query functions without the assistant's UI/provider setup.
namespace eval ::application::assistant {}
set file [open [file join [file dirname [info script]] .. tcl app-assistant.tcl]]
set collecting 0; set code {}
while {[gets $file line] >= 0} {
    if {!$collecting && [regexp {^proc ::application::assistant::(BuildQuery|SearchView|Combine|PatternRun|PatternIndexed|PatternSearchWait|PatternSearchNotify|PatternSearchFinished) } $line]} {set collecting 1}
    if {$collecting} {
        append code $line \n
        if {[info complete $code]} {eval $code;set code {};set collecting 0}
    }
}
close $file
tcltest::test cql6-patterns-route {vetted ids run through metadata narrowing and update a view} -body {
    set base $::scidb::test::cql6patterns::Fixture
    set view [::scidb::view::new $base Normal unused unused unused unused master slave]
    set criteria [dict create player {} color any result {} opponent {} eco {} from {} to {} event NLS min_elo {} pattern checkmate]
    lassign [::application::assistant::SearchView $base Normal $view $criteria] query summary count
    set indices {}
    for {set row 0} {$row<$count} {incr row} {lappend indices [::scidb::db::get gameNumber $base Normal $row $view]}
    ::scidb::view::close $base Normal $view
    list $count $indices [expr {[lsearch -exact $query cql]<0}]
} -result {2 {0 1} 1}

tcltest::test cql6-patterns-async {pattern route delivers its result after returning a native job} -body {
    set base $::scidb::test::cql6patterns::Fixture
    set view [::scidb::view::new $base Normal unused unused unused unused master slave]
    set criteria [dict create player {} color any result {} opponent {} eco {} from {} to {} event NLS min_elo {} pattern checkmate]
    unset -nocomplain ::scidb::test::cql6patterns::Result
    set job [::application::assistant::SearchView $base Normal $view $criteria {set ::scidb::test::cql6patterns::Result}]
    set immediate [info exists ::scidb::test::cql6patterns::Result]
    set timeout [after 10000 {set ::scidb::test::cql6patterns::Result timeout}]
    vwait ::scidb::test::cql6patterns::Result
    after cancel $timeout
    set result $::scidb::test::cql6patterns::Result
    ::scidb::view::close $base Normal $view
    list [string is integer -strict $job] $immediate [dict get $result ok] [dict get $result count]
} -result {1 0 1 2}
tcltest::test cql6-patterns-stale {a guarded completion cannot replace a closed dialog's view} -body {
    set base $::scidb::test::cql6patterns::Fixture
    set view [::scidb::view::new $base Normal unused unused unused unused master slave]
    set before [::scidb::view::count games $base Normal $view]
    set ::scidb::test::cql6patterns::Result untouched
    ::application::assistant::PatternSearchFinished $base Normal $view {} {} \
        {set ::scidb::test::cql6patterns::Result} {expr {0}} \
        [dict create ok 1 cancelled 0 matches [list [dict create game 0]]]
    set same [expr {$before==[::scidb::view::count games $base Normal $view]}]
    ::scidb::view::close $base Normal $view
    list $same $::scidb::test::cql6patterns::Result
} -result {1 untouched}

tcltest::test cql6-patterns-cancel {cancelled pattern search does not apply partial matches} -body {
    set base $::scidb::test::cql6patterns::Fixture
    set view [::scidb::view::new $base Normal unused unused unused unused master slave]
    set criteria [dict create player {} color any result {} opponent {} eco {} from {} to {} event NLS min_elo {} pattern checkmate]
    unset -nocomplain ::scidb::test::cql6patterns::Result
    set job [::application::assistant::SearchView $base Normal $view $criteria {set ::scidb::test::cql6patterns::Result}]
    ::scidb::cql6::cancel $job
    set timeout [after 10000 {set ::scidb::test::cql6patterns::Result timeout}]
    vwait ::scidb::test::cql6patterns::Result
    after cancel $timeout
    set result $::scidb::test::cql6patterns::Result
    set count [::scidb::view::count games $base Normal $view]
    ::scidb::view::close $base Normal $view
    list [dict get $result ok] [dict get $result error] $count
} -result {0 {Pattern search cancelled} 13}
::scidb::test::cql6patterns::closeFixture
tcltest::cleanupTests
