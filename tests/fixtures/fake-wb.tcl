#!/usr/bin/env tclsh
# A minimal WinBoard engine for the analysis stop test: answers xboard/protover,
# emits thinking output on "analyze", and leaves analyze mode on "exit".

fconfigure stdin -blocking 0 -buffering line
fconfigure stdout -buffering line

proc send {line} {
	puts $line
	flush stdout
}

set ::analyzing 0

proc search {} {
	if {!$::analyzing} { return }
	send "8 25 10 1000 e2e4 e7e5 g1f3"
}

proc handle {line} {
	switch -glob -- $line {
		xboard {
			send "FakeWB 1.0"
		}
		protover* {
			send {feature myname="FakeWB 1.0" analyze=1 setboard=1 ping=1 done=1}
		}
		ping* {
			send "pong [lindex $line 1]"
		}
		analyze {
			set ::analyzing 1
			search
		}
		exit {
			set ::analyzing 0
		}
		quit {
			exit 0
		}
	}
}

fileevent stdin readable {
	while {[gets stdin line] >= 0} { handle $line }
}

after 20000 exit
vwait ::forever
