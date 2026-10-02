# Shared by the app acceptance tests and the standalone real-Tcl harness.
namespace eval ::scidb::test::cql6::prefetch {
 variable big /tmp/cql6-prefetch-big-[pid].pgn
 variable order /tmp/cql6-prefetch-order-[pid].pgn
 variable stress /tmp/cql6-prefetch-stress-[pid].pgn
 variable Done {}
 variable timer {}
 variable last 0
 variable gaps {}
 variable busyTimer {}
}
proc ::scidb::test::cql6::prefetch::receive {r} { variable Done; set Done $r }
proc ::scidb::test::cql6::prefetch::waitResult {} {
 variable Done
 set timeout [after 120000 {set ::scidb::test::cql6::prefetch::Done timeout}]
 if {$Done eq {}} { vwait ::scidb::test::cql6::prefetch::Done }
 after cancel $timeout
 if {$Done eq "timeout"} {error "prefetch callback timed out"}
 return $Done
}
proc ::scidb::test::cql6::prefetch::search {base script args} {
 variable Done; set Done {}
 return [::scidb::cql6::search $base Normal $script {*}$args -command ::scidb::test::cql6::prefetch::receive]
}
proc ::scidb::test::cql6::prefetch::tick {} {
 variable last; variable gaps; variable timer
 set now [clock milliseconds]
 lappend gaps [expr {$now-$last}]; set last $now
 set timer [after 20 ::scidb::test::cql6::prefetch::tick]
}
proc ::scidb::test::cql6::prefetch::busy {} {
 variable busyTimer
 # A real competing Tcl workload, with a one millisecond cadence.
 for {set i 0} {$i < 1000} {incr i} {expr {$i*$i}}
 set busyTimer [after 1 ::scidb::test::cql6::prefetch::busy]
}
proc ::scidb::test::cql6::prefetch::rss {} {
 return [string trim [exec ps -o rss= -p [pid]]]
}
::scidb::test::cql6::makeFixture $::scidb::test::cql6::prefetch::big 20000
::scidb::test::cql6::makeFixture $::scidb::test::cql6::prefetch::order 500
::scidb::test::cql6::makeFixture $::scidb::test::cql6::prefetch::stress 20000

tcltest::test cql6-prefetch-responsive {three several-second 20000-game searches with strict timer budget} -body {
 namespace eval ::scidb::test::cql6::prefetch {
  set out {}
  for {set i 0} {$i < 3} {incr i} {
   set gaps {}; set last [clock milliseconds]
   set start $last
   set job [search $big SLOW -threads 16]
   set timer [after 20 ::scidb::test::cql6::prefetch::tick]
   set r [waitResult]
   after cancel $timer
   set gap [tcl::mathfunc::max {*}$gaps]
   puts "CQL6 prefetch responsiveness run=[expr {$i+1}] max_gap=${gap}ms duration=[expr {[clock milliseconds]-$start}]ms"
   lappend out [expr {$gap < 40 && [dict get $r games]==20000 && [dict get $r ok]
    && [clock milliseconds]-$start > 3000 && [::scidb::cql6::progress $job]==-1}]
  }
  set out
 }
} -cleanup {after cancel $::scidb::test::cql6::prefetch::timer} -result {1 1 1}

tcltest::test cql6-prefetch-throughput {20000-game rates with and without competing 1ms timer} -body {
 namespace eval ::scidb::test::cql6::prefetch {
  set out {}; set index 0
  foreach competing {0 1} {
   if {$competing} {busy}
   foreach n {1 4 16} {
    set start [clock microseconds]
    set job [search $big MATCH_ALL -threads $n]
    set r [waitResult]
    set rate [expr {20000.0*1000000/([clock microseconds]-$start)}]
    puts "CQL6 prefetch throughput busy=$competing threads=$n games/s=$rate"
    set speedOK 1
    if {[info exists ::env(CQL6_BASELINE_RATES)]} {
     set baseline [lindex $::env(CQL6_BASELINE_RATES) $index]
     set speedOK [expr {$rate >= 5*$baseline}]
     puts "CQL6 throughput baseline=$baseline speedup=[expr {$rate/$baseline}]"
    } else {
     # Never invent an app baseline from the fake-database harness.
     error "5x comparison requires CQL6_BASELINE_RATES with six measured round-trip rates"
    }
    incr index
    lappend out [expr {$speedOK && [dict get $r games]==20000
     && [dict get $r threads]==$n && [::scidb::cql6::progress $job]==-1}]
   }
   if {$competing} {after cancel $busyTimer}
  }
  set out
 }
} -cleanup {after cancel $::scidb::test::cql6::prefetch::busyTimer} -result {1 1 1 1 1 1}

tcltest::test cql6-prefetch-order {500 dumps identical to the old glue; every index exactly once at all thread counts} -body {
 namespace eval ::scidb::test::cql6::prefetch {
  set reference [::scidb::cql6::search $order Normal DUMP -threads 1 -pgn 1]
  if {[info exists ::env(CQL6_BASELINE_DUMP)]} {
   set f [open $::env(CQL6_BASELINE_DUMP)]; set old [string trim [read $f]]; close $f
   # the baseline predates the truncated count, which this fixture leaves at 0
   if {$old ne [dict remove $reference truncated]} {error "DUMP differs from round-trip glue"}
  } else {error "DUMP comparison requires CQL6_BASELINE_DUMP from the round-trip glue"}
  set out {}
  foreach n {1 4 16} {
   search $order DUMP -threads $n -pgn 1
   set r [waitResult]
   lappend out [expr {[dict get $r games]==500 && [dict get $r matches] eq [dict get $reference matches]
    && [::scidb::test::cql6::indexes $r] eq [::scidb::test::cql6::sequence 500]}]
  }
  set out
 }
} -result {1 1 1}

proc ::scidb::test::cql6::prefetch::endJob {action job} {
 variable stress
 # These run at a slice boundary: a Tcl command cannot interrupt an
 # indivisible database export on the same Tcl thread.
 if {$action eq "cancel"} {::scidb::cql6::cancel $job} else {
  ::scidb::db::close $stress
  if {$action eq "reopen"} {::scidb::test::cql6::openBase $stress}
 }
}
tcltest::test cql6-prefetch-lifetime {200 cancellations/close/reopen, no residual jobs or sustained RSS growth} -body {
 namespace eval ::scidb::test::cql6::prefetch {
  set before [rss]; set good 1
  for {set i 0} {$i < 200} {incr i} {
   if {$i && $i%50==0} {puts "CQL6 lifetime completed $i jobs"; flush stdout}
   set action [lindex {cancel close reopen} [expr {$i%3}]]
   set job [search $stress SLOW -threads 4]
   after 1 [list ::scidb::test::cql6::prefetch::endJob $action $job]
   set r [waitResult]
   if {$action eq "cancel"} {
    if {![dict get $r ok] || ![dict get $r cancelled] || [dict get $r games]>=20000} {set good 0}
   } elseif {$r ne {ok 0 error {database closed}}} {set good 0}
   if {$action eq "close"} {::scidb::test::cql6::openBase $stress}
   if {[::scidb::cql6::progress $job]!=-1 || [::scidb::cql6::cancel $job]!=0} {set good 0}
   if {[info commands testJobs] ne {} && [testJobs]!=0} {set good 0}
  }
  set after [rss]; puts "CQL6 lifetime 200 jobs RSS before=${before}KiB after=${after}KiB delta=[expr {$after-$before}]KiB"
  # ASan intentionally quarantines allocations; its leak checker is the memory assertion there.
  if {![info exists ::env(ASAN_OPTIONS)] && $after-$before > 16384} {set good 0}
  set good
 }
} -result 1

# Real child-interpreter initialization/deletion is exercised by the standalone
# harness. Scidb's application commands are not loadable into Tcl slave interpreters.
tcltest::testConstraint cql6Standalone [expr {[info commands testDelete] ne {}}]
tcltest::test cql6-prefetch-interp-delete {200 interpreter deletions remove timers, queued events and jobs} -constraints cql6Standalone -body {
 ::scidb::db::open big 20000
 set before [::scidb::test::cql6::prefetch::rss]
 for {set i 0} {$i < 200} {incr i} {
  testDelete
  set deadline [expr {[clock milliseconds]+5000}]
  while {[testJobs] || [testEngines]} {
   if {[clock milliseconds]>$deadline} {error "deleted interpreter left a live job"}
   after 1; update
  }
 }
 set after [::scidb::test::cql6::prefetch::rss]
 puts "CQL6 deletion 200 jobs RSS before=${before}KiB after=${after}KiB delta=[expr {$after-$before}]KiB"
 expr {[testJobs]==0 && [testEngines]==0 && ([info exists ::env(ASAN_OPTIONS)] || $after-$before < 16384)}
} -result 1
foreach base [list $::scidb::test::cql6::prefetch::big $::scidb::test::cql6::prefetch::order $::scidb::test::cql6::prefetch::stress] {
 catch {::scidb::db::close $base}; file delete $base
}
