# Cold opening-tree searches on ::BSCI: positions after plies 1..12 of game ::BGAME (each cold once).
::application::database::openBase .application $::BSCI no
update
set db $::BSCI
::game::new .application -base $db -variant Normal -view 0 -number $::BGAME
update
::scidb::tree::set $db
set out {}
::scidb::game::go 0 start
for {set k 1} {$k <= 12} {incr k} {
	::scidb::game::go 1
	set t0 [clock microseconds]
	if {![::scidb::tree::update Elo exact 0]} {
		while {![::scidb::tree::isUpToDate?]} { after 1; update }
	}
	::scidb::tree::finish Elo exact 0 -sort 2
	lappend out [expr {([clock microseconds] - $t0)/1000}]
}
set sum 0; foreach t $out { incr sum $t }
list total=$sum per-ply=$out
