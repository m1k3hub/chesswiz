::application::database::openBase .application $::BPGN yes -encoding $::encoding::autoEncoding
update
::application::switchTab board; update
::game::new .application -base $::BPGN -variant Normal -view 0 -number $::BGAME
update
::scidb::game::go -1 start; update
set g 0; set u 0; set ui 0
for {set i 0} {$i < 40} {incr i} {
	set t0 [clock microseconds]; ::application::board::goto +1
	set t1 [clock microseconds]; update idletasks
	set t2 [clock microseconds]; update
	set t3 [clock microseconds]
	incr g [expr {$t1-$t0}]; incr ui [expr {$t2-$t1}]; incr u [expr {$t3-$t2}]
}
format "goto %.1f  idle %.1f  events %.1f ms/step" [expr {$g/40000.0}] [expr {$ui/40000.0}] [expr {$u/40000.0}]
