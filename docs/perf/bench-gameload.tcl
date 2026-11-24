# Load games from ::BSCI into the board (::game::new), close them; ms per load.
::application::database::openBase .application $::BSCI no
update; ::application::switchTab board; update
set times {}
foreach n {11 222 3333 4444 5555 6666 7777 8888} {
	set t0 [clock microseconds]
	::game::new .application -base $::BSCI -variant Normal -view 0 -number $n
	update
	lappend times [expr {([clock microseconds]-$t0)/1000}]
	set gb $::application::pgn::Vars(gamebar)
	foreach p [::game::usedPositions?] { catch { ::gamebar::remove $gb $p; ::game::release $p } }
	update
}
list load-ms: $times
