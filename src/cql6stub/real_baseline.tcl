package require tcltest
namespace eval ::scidb::test::cql6 {}
# Only helpers/fixtures needed by the benchmark, no post-change tests.
set f [open tests/test_app_cql6.tcl]; set text [read $f]; close $f
set text [string range $text 0 [expr {[string first {::scidb::test::cql6::makeFixture $::scidb::test::cql6::small} $text]-1}]]
eval $text
::scidb::test::cql6::makeFixture /tmp/cql6-real-bench.pgn 20000
::scidb::test::cql6::makeFixture /tmp/cql6-real-order.pgn 500
proc busy {} {
 for {set i 0} {$i<1000} {incr i} {expr {$i*$i}}
 set ::bt [after 1 busy]
}
set rates {}
foreach competing {0 1} {
 if {$competing} {busy}
 foreach n {1 4 16} {
  set ::scidb::test::cql6::Done {}
  set start [clock microseconds]
  ::scidb::cql6::search /tmp/cql6-real-bench.pgn Normal MATCH_ALL -threads $n -command ::scidb::test::cql6::receive
  set r [::scidb::test::cql6::waitResult]
  set rate [expr {20000.0*1000000/([clock microseconds]-$start)}]
  lappend rates $rate
  puts "REAL baseline busy=$competing threads=$n games/s=$rate games=[dict get $r games]"
 }
 if {$competing} {after cancel $::bt}
}
set f [open /tmp/cql6-real-baseline-rates w]; puts $f $rates; close $f
set f [open /tmp/cql6-real-baseline-dump w]
puts $f [::scidb::cql6::search /tmp/cql6-real-order.pgn Normal DUMP -pgn 1 -threads 1]
close $f
::scidb::db::close /tmp/cql6-real-bench.pgn
::scidb::db::close /tmp/cql6-real-order.pgn
