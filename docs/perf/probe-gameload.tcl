# Time selected procs (wall, inclusive) during 8 game loads.
set ::TW {}
foreach p {::application::media::MediaDestroy ::util::place::besideSettle ::ai::systemone::evaluateAsync ::application::reflow::updateCollapse ::application::pgn::add ::gamebar::add ::scidb::game::load ::scidb::game::switch ::application::board::UpdateControls ::application::pgn::ShowEmptyHint ::application::pgn::PrepareAsHeader} {
	if {[info commands $p] eq ""} { continue }
	rename $p ${p}__tw
	proc $p args [string map [list @P@ $p] {
		set t [clock microseconds]
		set rc [catch {uplevel 1 [list @P@__tw {*}$args]} r o]
		dict incr ::TW @P@ [expr {[clock microseconds]-$t}]
		return {*}$o $r
	}]
}
::application::database::openBase .application $::BSCI no
update; ::application::switchTab board; update
set ::TW {}
set total 0
foreach n {11 222 3333 4444 5555 6666 7777 8888} {
	set t0 [clock microseconds]
	::game::new .application -base $::BSCI -variant Normal -view 0 -number $n
	update
	incr total [expr {[clock microseconds]-$t0}]
	set gb $::application::pgn::Vars(gamebar)
	foreach p [::game::usedPositions?] { catch { ::gamebar::remove $gb $p; ::game::release $p } }
	update
}
set out [list "total per load [expr {$total/8000}] ms (including removal-phase calls below)"]
dict for {k v} $::TW { lappend out [format "%7.1f ms/load  %s" [expr {$v/8000.0}] $k] }
join [lsort -decreasing $out] \n
