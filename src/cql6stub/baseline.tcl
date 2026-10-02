::scidb::db::open big 20000
proc receive {r} {set ::Done $r}
proc waitResult {} {
 set timeout [after 120000 {set ::Done timeout}]
 if {$::Done eq {}} {vwait ::Done}
 after cancel $timeout
 if {$::Done eq "timeout"} {error timeout}
 return $::Done
}
proc busy {} {
 for {set i 0} {$i<1000} {incr i} {expr {$i*$i}}
 set ::bt [after 1 busy]
}
set rates {}
foreach competing {0 1} {
 if {$competing} {busy}
 foreach n {1 4 16} {
  set ::Done {}
  set start [clock microseconds]
  ::scidb::cql6::search big Normal MATCH_ALL -threads $n -command receive
  set r [waitResult]
  set rate [expr {20000.0*1000000/([clock microseconds]-$start)}]
  lappend rates $rate
  puts "BASELINE busy=$competing threads=$n games/s=$rate games=[dict get $r games]"
 }
 if {$competing} {after cancel $::bt}
}
set f [open [expr {[info exists ::env(CQL6_RATES_OUT)] ? $::env(CQL6_RATES_OUT) : "/tmp/cql6-baseline-rates"}] w]; puts $f $rates; close $f
::scidb::db::open order 500
set f [open /tmp/cql6-baseline-dump w]
puts $f [::scidb::cql6::search order Normal DUMP -pgn 1 -threads 1]
close $f
