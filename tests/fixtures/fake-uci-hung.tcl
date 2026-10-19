#!/usr/bin/env tclsh
# A UCI engine which never ends its search for the analysis tests: it starts,
# shows lines, but ignores "stop" and "quit" (a hung engine). Tcl's close of a
# command pipeline waits for the child, so this is the engine which froze the
# application when the analysis pane was closed (F-11).
#
# It ends by itself after 20 seconds: a close which blocks again makes the test
# fail after that time instead of hanging the whole run for ever.

fconfigure stdin -blocking 0 -buffering line
fconfigure stdout -buffering line

proc send {line} {
	puts $line
	flush stdout
}

proc search {} {
	foreach n {1 2 3 4} {
		send "info depth 8 seldepth 10 multipv $n score cp [expr {20 - $n}] nodes 1000 nps 10000 time 10 pv e2e4 e7e5 g1f3"
	}
}

proc handle {line} {
	switch -glob -- $line {
		uci {
			send "id name HungEngine 1.0"
			send "id author the Scidb test suite"
			send "option name MultiPV type spin default 1 min 1 max 8"
			send "uciok"
		}
		isready	{ send "readyok" }
		go* 		{ search }
	}
}

fileevent stdin readable {
	while {[gets stdin line] >= 0} { handle $line }
}

after 20000 exit
vwait ::forever
