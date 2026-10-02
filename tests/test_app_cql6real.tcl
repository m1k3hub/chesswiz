package require tcltest 2.5
if {[::scidb::cql6::version] eq "cql6 stub 6.2"} { return }

namespace eval ::scidb::test::cql6real {
	variable base [file join [file dirname [info script]] tmp-app cql6-real-[pid].pgn]
	variable done {}
}
proc ::scidb::test::cql6real::nop {args} { return 0 }
proc ::scidb::test::cql6real::receive {result} {
	set ::scidb::test::cql6real::done $result
}
file mkdir [file dirname $::scidb::test::cql6real::base]
set fh [open $::scidb::test::cql6real::base w]
puts $fh {[Event "Mate"]
[White "White"]
[Black "Black"]
[Result "0-1"]

1. f3 e5 2. g4 Qh4# 0-1

[Event "Quiet"]
[White "White"]
[Black "Black"]
[Result "*"]

1. e4 e5 2. Nf3 (2. Bc4 Nc6 3. Qh5 Nf6 4. Qxf7#) *

[Event "Null"]
[White "White"]
[Black "Black"]
[Result "*"]

1. -- Nf6 *}
close $fh
::scidb::db::open $::scidb::test::cql6real::base ::scidb::test::cql6real::nop {} ::scidb::test::cql6real::nop {}

tcltest::test cql6-real-mate {real engine returns host index and matching ply} -body {
	set r [::scidb::cql6::search $::scidb::test::cql6real::base Normal {cql() mate} -threads 1]
	list [dict get $r games] [dict get $r matches]
} -result {3 {{game 0 first_ply 4}}}

tcltest::test cql6-real-compact {-compact flattens the same matches into game/ply pairs} -body {
	set base $::scidb::test::cql6real::base
	set full [dict get [::scidb::cql6::search $base Normal {cql() initial} -threads 1] matches]
	set flat [dict get [::scidb::cql6::search $base Normal {cql() initial} -threads 1 -compact 1] matches]
	list [expr {[concat {*}[lmap m $full {list [dict get $m game] [dict get $m first_ply]}]] eq $flat}] [llength $flat]
} -result {1 6}

tcltest::test cql6-real-paged {-paged keeps matches in the glue until released} -body {
	set base $::scidb::test::cql6real::base
	set flat [dict get [::scidb::cql6::search $base Normal {cql() initial} -threads 1 -compact 1] matches]
	set r [::scidb::cql6::search $base Normal {cql() initial} -threads 1 -paged 1]
	set id [dict get $r results]
	set pages [concat [::scidb::cql6::matches $id 0 2] [::scidb::cql6::matches $id 2 5]]
	list [dict get $r count] [dict exists $r matches] [expr {$pages eq $flat}] \
		[::scidb::cql6::matches $id 9 3] [::scidb::cql6::release $id] [::scidb::cql6::release $id] \
		[catch {::scidb::cql6::matches $id 0 1}]
} -result {3 0 1 {} 1 0 1}

tcltest::test cql6-real-null {explicit null moves retain following legal moves} -body {
	set r [::scidb::cql6::search $::scidb::test::cql6real::base Normal {cql() initial} -threads 1 -pgn 1]
	set last [lindex [dict get $r matches] end]
	list [dict get $r games] [dict get $last game] [regexp -- {--} [dict get $last pgn]]
} -result {3 2 1}

tcltest::test cql6-real-threads {multiple workers preserve match identity} -body {
	set base $::scidb::test::cql6real::base
	expr {[dict get [::scidb::cql6::search $base Normal {cql() check} -threads 1] matches]
		eq [dict get [::scidb::cql6::search $base Normal {cql() check} -threads 8] matches]}
} -result 1

tcltest::test cql6-real-recovery {parse error leaves engine usable} -body {
	set base $::scidb::test::cql6real::base
	list [catch {::scidb::cql6::search $base Normal {cql() invalid_filter}}] \
		[dict get [::scidb::cql6::search $base Normal {cql() mate} -threads 1] games]
} -result {1 3}

tcltest::test cql6-real-async {real engine delivers result on Tcl thread} -body {
	set ::scidb::test::cql6real::done {}
	set job [::scidb::cql6::search $::scidb::test::cql6real::base Normal {cql() mate} \
		-threads 2 -command ::scidb::test::cql6real::receive]
	set timeout [after 10000 {set ::scidb::test::cql6real::done timeout}]
	vwait ::scidb::test::cql6real::done
	after cancel $timeout
	set r $::scidb::test::cql6real::done
	list [dict get $r ok] [dict get $r matches] [::scidb::cql6::progress $job]
} -result {1 {{game 0 first_ply 4}} -1}

tcltest::test cql6-real-batch {batch shares feed and returns script identity} -body {
    set r [::scidb::cql6::search $::scidb::test::cql6real::base Normal {cql() mate} \
        -scripts [list {cql() initial}] -threads 8 -max 1]
    list [dict get $r games] [dict get $r matches]
} -result {3 {{game 0 first_ply 4 script 0} {game 0 first_ply 0 script 1}}}

tcltest::test cql6-real-batch-variations {parsed headers select independent variation views} -body {
    set r [::scidb::cql6::search $::scidb::test::cql6real::base Normal {cql() mate} \
        -scripts [list {cql(variations) mate}] -threads 8]
    dict get $r matches
} -result {{game 0 first_ply 4 script 0} {game 0 first_ply 4 script 1} {game 1 first_ply -1 script 1}}

tcltest::test cql6-real-view {metadata prefilter restricts decoding and retains native indices} -body {
    set base $::scidb::test::cql6real::base
    set view [::scidb::view::new $base Normal unused unused unused unused master slave]
    ::scidb::view::search $base Normal $view null none {eventname Null}
    set r [::scidb::cql6::search $base Normal {cql() initial} -view $view -threads 8]
    ::scidb::view::search $base Normal $view null none {eventname Missing}
    set empty [::scidb::cql6::search $base Normal {cql() initial} -view $view]
    ::scidb::view::close $base Normal $view
    list [dict get $r games] [dict get $r matches] [dict get $empty games] [dict get $empty matches]
} -result {1 {{game 2 first_ply 0}} 0 {}}

::scidb::db::close $::scidb::test::cql6real::base
file delete $::scidb::test::cql6real::base
tcltest::cleanupTests
