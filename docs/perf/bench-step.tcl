# Move stepping: open ::BPGN, load game ::BGAME, 40x goto +1 with update, 3 runs.
::application::database::openBase .application $::BPGN yes -encoding $::encoding::autoEncoding
update
::application::switchTab board; update
::game::new .application -base $::BPGN -variant Normal -view 0 -number $::BGAME
update
set out {}
for {set run 0} {$run < 3} {incr run} {
	::scidb::game::go -1 start; update
	set t0 [clock microseconds]
	for {set i 0} {$i < 40} {incr i} { ::application::board::goto +1; update }
	lappend out [format "%.1f ms/step" [expr {([clock microseconds]-$t0)/40000.0}]]
}
join $out "; "
