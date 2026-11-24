::application::database::openBase .application $::BPGN yes -encoding $::encoding::autoEncoding
update; ::application::switchTab board; update
::game::new .application -base $::BPGN -variant Normal -view 0 -number $::BGAME
update
set out {}
foreach r {1 2 3} { set t0 [clock microseconds]; ::application::pgn::refresh 1; update; lappend out [expr {([clock microseconds]-$t0)/1000}] }
set n [$::application::pgn::Vars(pgn:$::application::pgn::Vars(index)) count -chars 1.0 end]
list "pgn::refresh 1: $out ms" chars=$n
