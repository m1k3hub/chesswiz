#!/usr/bin/env tclsh
# A UCI engine for tests: one principal variation, then only time-only info
# lines ("info time ... nodes ... nps ..."), as engines send between depths.
# It ends by itself after 20 seconds.

fconfigure stdin -blocking 0 -buffering line
fconfigure stdout -buffering line

proc send {line} {
	puts $line
	flush stdout
}

proc tick {n} {
	if {!$::searching} { return }
	send "info time [expr {$n*100}] nodes [expr {$n*1000000}] nps 7654321"
	after 100 [list tick [incr n]]
}

proc handle {line} {
	switch -glob -- $line {
		uci {
			send "id name TimeInfoEngine 1.0"
			send "id author the Scidb test suite"
			send "uciok"
		}
		isready	{ send "readyok" }
		go* {
			set ::searching 1
			send "info depth 5 seldepth 5 score cp 20 nodes 1000 nps 1000 time 1 pv e2e4 e7e5"
			after 200 [list tick 1]
		}
		stop {
			set ::searching 0
			send "bestmove e2e4 ponder e7e5"
		}
		quit	{ exit 0 }
	}
}

set ::searching 0
fileevent stdin readable {
	while {[gets stdin line] >= 0} { handle $line }
}

after 20000 exit
vwait ::forever
