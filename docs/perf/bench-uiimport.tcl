# UI import (progress dialog + log) of ::BPGN into the Clipbase-like memory base, 3 runs.
set out {}
for {set r 0} {$r < 3} {incr r} {
	catch {::scidb::db::close BenchUi}
	::scidb::db::new BenchUi Normal [::application::database::lookupType Clipbase]
	set t0 [clock microseconds]
	::import::import .application BenchUi [list $::BPGN] "Importing" utf-8
	lappend out "[expr {([clock microseconds]-$t0)/1000}] ms"
	catch {::log::close}
	update
	::scidb::db::close BenchUi
}
join $out "; "
