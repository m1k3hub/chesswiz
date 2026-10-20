#!/usr/bin/env tclsh
# Minimal deterministic UCI engine for tests that need a live engine
# process without depending on Stockfish's startup time under load.
# Speaks just enough of the protocol for a running analysis pane.
fconfigure stdout -buffering line
fconfigure stdin -buffering line
while {[gets stdin line] >= 0} {
	set cmd [lindex $line 0]
	switch -- $cmd {
		uci {
			puts "id name ChesswizTestEngine"
			puts "id author Chesswiz tests"
			puts "uciok"
		}
		isready { puts "readyok" }
		ucinewgame {}
		stop { puts "bestmove e2e4" }
		go {
			after 10
			puts "bestmove e2e4"
		}
		quit { exit 0 }
		default {}
	}
	flush stdout
}
