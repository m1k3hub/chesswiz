#!/usr/bin/env tclsh
# A WinBoard engine for tests whose variants list is followed by more
# features on the same line, as most engines send it.
fconfigure stdout -buffering line
puts "FakeVariants 1.0"
while {[gets stdin line] >= 0} {
	switch -glob -- $line {
		protover* { puts {feature myname="FakeVariants" variants="normal,suicide" analyze=1 setboard=1 sigint=0 sigterm=0 done=1} }
		quit      { exit 0 }
	}
}
