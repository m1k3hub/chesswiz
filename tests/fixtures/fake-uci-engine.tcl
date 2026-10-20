#!/usr/bin/env tclsh
# Minimal deterministic UCI engine for tests that need a live engine
# process without depending on Stockfish's startup time under load.
# Speaks just enough of the protocol for a running analysis pane.
fconfigure stdout -buffering line
fconfigure stdin -buffering line
set pv {e2e4 e7e5 g1f3}
while {[gets stdin line] >= 0} {
	set cmd [lindex $line 0]
	switch -- $cmd {
		uci {
			puts "id name ChesswizTestEngine"
			puts "id author Chesswiz tests"
			puts "option name Threads type spin default 1 min 1 max 2"
			puts "option name Hash type spin default 16 min 1 max 64"
			puts "option name Move Overhead type spin default 10 min 0 max 5000"
			puts "option name MultiPV type spin default 1 min 1 max 8"
			puts "uciok"
		}
		isready { puts "readyok" }
		ucinewgame {}
		position {
			if {[regexp {f1b5|1B2p3} $line]} {
				set pv {d7d6 d2d4 g8f6}
			} else { set pv {e2e4 e7e5 g1f3} }
		}
		stop { puts "bestmove [lindex $pv 0]" }
		go {
			after 10
			puts "info depth 9 score cp 10 nodes 1000 time 10 pv $pv"
			if {"infinite" ni $line} { puts "bestmove [lindex $pv 0]" }
		}
		quit { exit 0 }
		default {}
	}
	flush stdout
}
