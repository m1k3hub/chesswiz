package require tcltest 2.5
namespace eval ::scidb::test::cql6 {}
proc ::scidb::test::cql6::makeFixture {p n} {::scidb::db::open $p $n}
proc ::scidb::test::cql6::openBase {p} {::scidb::db::open $p 20000}
proc ::scidb::test::cql6::indexes {r} {lmap m [dict get $r matches] {dict get $m game}}
proc ::scidb::test::cql6::sequence {n} {
 set out {}; for {set i 0} {$i<$n} {incr i} {lappend out $i}; return $out
}
if {[info exists ::env(CQL6_TEST_MATCH)]} {tcltest::configure -match $::env(CQL6_TEST_MATCH)}
source [file join [file dirname [info script]] task2b_tests.tcl]
set failed $::tcltest::numTests(Failed)
tcltest::cleanupTests
if {$failed} {error "$failed standalone tests failed"}
