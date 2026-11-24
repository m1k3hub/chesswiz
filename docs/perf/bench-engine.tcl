# Time from startEngine Stockfish to the first PV, 3 runs each for ::BCORES.
set out {}
foreach cores $::BCORES {
	set times {}
	for {set run 0} {$run < 3} {incr run} {
		set t0 [clock microseconds]
		set num [::application::analysis::startEngine Stockfish "" [dict create threads $cores]]
		set tree $::application::analysis::NumberToTree($num)
		set dl [expr {[clock milliseconds] + 15000}]
		set ms timeout
		while {[clock milliseconds] < $dl} {
			update
			if {[llength [::application::analysis::BestLine $tree]] > 0} { set ms [expr {([clock microseconds]-$t0)/1000}]; break }
			after 2
		}
		lappend times $ms
		::application::analysis::stopEngine $num
		set twm [::application::twm board]
		set uid analysis:[::application::mapToTerminalNumber $num]
		if {[::application::exists? $uid]} { $twm close [$twm leaf $uid] }
		update; after 500; update
	}
	lappend out "threads=$cores first PV: $times ms"
}
join $out \n
