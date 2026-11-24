# Sent into a running Chesswiz: in-memory PGN import, 3 runs. Set ::BPGN first.
proc ::BLog {args} {}
proc ::BProg {args} {return 0}
set out {}
for {set r 0} {$r < 3} {incr r} {
	catch {::scidb::db::close BenchImp}
	::scidb::db::new BenchImp Undetermined [::application::database::lookupType Clipbase]
	set t0 [clock microseconds]
	set res [::scidb::db::import BenchImp $::BPGN ::BLog {} ::BProg {} -encoding utf-8]
	lappend out "[expr {([clock microseconds]-$t0)/1000}] ms games=[lindex $res 0]"
	::scidb::db::close BenchImp
}
join $out "; "
