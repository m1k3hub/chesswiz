#!/usr/bin/env tclsh
# A minimal WinBoard engine for tests: it analyses by sending one PV whose
# move number has three dots ("1... e4"), as Sjeng does.
fconfigure stdout -buffering line
puts "FakeBoard 1.0"
while {[gets stdin line] >= 0} {
	switch -glob -- $line {
		protover* { puts {feature myname="FakeBoard" analyze=1 setboard=1 sigint=0 sigterm=0 done=1} }
		analyze   { puts "1 10 0 1 1... e4" }
		quit      { exit 0 }
	}
}
