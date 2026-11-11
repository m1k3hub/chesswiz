# Loopback-only ICC fixture. Sourcing this file never opens a socket.
namespace eval ::icc::fake {}
namespace eval ::icc::fake {
	variable server {}
	variable chan {}
	variable input {}
	variable received {}
	variable mode guest
	variable state login
	variable nf3 0
}

proc ::icc::fake::Start {{kind guest}} {
	variable server
	variable mode
	set mode $kind
	set server [socket -server ::icc::fake::Accept -myaddr 127.0.0.1 0]
	return [lindex [fconfigure $server -sockname] 2]
}

proc ::icc::fake::Accept {channel address port} {
	variable chan
	variable input
	variable received
	variable state
	variable nf3
	set chan $channel
	set input {}
	set received {}
	set state login
	set nf3 0
	fconfigure $chan -blocking 0 -buffering none -translation binary -encoding binary
	fileevent $chan readable ::icc::fake::Read
	Write "login: "
}

proc ::icc::fake::Write {text} {
	variable chan
	if {$chan eq ""} { return }
	catch { puts -nonewline $chan $text; flush $chan }
}

proc ::icc::fake::Line {line} { Write "$line\r\n" }

proc ::icc::fake::Read {} {
	variable chan
	variable input
	if {$chan eq ""} { return }
	append input [read $chan]
	while {[set end [string first "\n" $input]] >= 0} {
		set line [string range $input 0 [expr {$end - 1}]]
		set input [string range $input [expr {$end + 1}] end]
		regsub -all "\r" $line {} line
		Handle $line
		if {$chan eq ""} { return }
	}
	if {[eof $chan]} {
		catch { close $chan }
		set chan {}
	}
}

proc ::icc::fake::DG {id args} {
    set fields [list $id]
    foreach arg $args {
        if {$arg eq "" || [regexp {\s|[{}]} $arg]} {
            lappend fields "\x19\{$arg\x19\}"
        } else { lappend fields $arg }
    }
    Write "\x19([join $fields { }]\x19)"
}
proc ::icc::fake::Login {} {
    variable mode
    DG 0 [expr {$mode eq "guest" ? "guest1234" : "TestPlayer"}] {}
    DG 50 6 Opponent {} 1500 0 0 blitz 5 0 0 ? 0 9999 1 0 {}
    DG 50 7 Wild {} 1500 0 8 blitz 5 0 0 ? 0 9999 1 0 {}
    DG 50 8 Computer C 2400 0 0 standard 15 2 1 ? 0 9999 1 0 {}
    DG 29 Challenger 1600 {} guest1234 0 {} 0 blitz 0 0 5 0 5 0 ?
    DG 31 Admin {} {Welcome to the test server.} 1
    DG 28 4 Admin {} {Channel welcome.} 1
}


proc ::icc::fake::Handle {line} {
	variable received
	variable mode
	variable state
	variable nf3
	lappend received $line


    if {$state eq "login"} {
        if {![regexp {^level2settings=([01]+) (\S+)$} $line -> bits handle]} { return }
        if {$mode eq "guest" && $handle eq "guest"} {
            set state online
            Login
        } else {
            Write "password: "
            set state password
        }
        return
    }
    if {$state eq "password"} {
        if {$mode eq "registeredReject"} {
            Line {Invalid password}
            set state rejected
        } else { set state online; Login }
        return
    }

	if {$state ne "online"} { return }

	switch -- $line {
		{play 6} {
			DG 15 42 guest1234 Opponent 0 blitz 0 5 0 5 0 1 0 0 0 1500
            DG 51 6
			Line {<12> rnbqkbnr pppppppp -------- -------- -------- -------- PPPPPPPP RNBQKBNR W -1 1 1 1 1 0 42 guest1234 Opponent 1 5 0 39 39 300000 300000 1 none (0:00.000) none 0 1 0}
		}
		e4 {
			Line {<12> rnbqkbnr pppppppp -------- -------- ----P--- -------- PPPP-PPP RNBQKBNR B 4 1 1 1 1 0 42 guest1234 Opponent -1 5 0 39 39 299000 300000 1 P/e2-e4 (0:01.000) e4 0 1 0}
			Line {<12> rnbqkbnr pppp-ppp -------- ----p--- ----P--- -------- PPPP-PPP RNBQKBNR W 4 1 1 1 1 0 42 guest1234 Opponent 1 5 0 39 39 299000 298000 2 P/e7-e5 (0:02.000) e5 0 1 0}
		}
		Nf3 {
			incr nf3
			if {$nf3 == 1} {
				DG 26 42 Nf3 {Illegal move}
			} else {
				Line {<12> rnbqkbnr pppp-ppp -------- ----p--- ----P--- -----N-- PPPP-PPP RNBQKB-R B -1 1 1 1 1 1 42 guest1234 Opponent -1 5 0 39 39 298000 298000 2 N/g1-f3 (0:01.000) Nf3 0 1 0}
				Line {<12> r-bqkbnr pppp-ppp --n----- ----p--- ----P--- -----N-- PPPP-PPP RNBQKB-R W -1 1 1 1 1 2 42 guest1234 Opponent 1 5 0 38 39 298000 297000 3 N/b8-c6 (0:01.000) Nc6 0 1 0}
				DG 16 42 0 Res 1-0 {Opponent resigns}
                DG 17 42
			}
		}
		{observe 21} {
            DG 18 21 SENHUS MIHAILOP 0 blitz 1 3 0 3 0 1 0 0 1914 2183
            Line $::icc::fake::style12
        }
        games { Line {21 SENHUS MIHAILOP rated blitz 3 0} }
        clock { DG 56 42 W 123456 1; DG 56 42 B 120000 0 }
        offers { DG 34 42 0 1 0 0 0 0 0 1 }
        removematch { DG 30 Challenger }
        adjourn { DG 16 42 0 Adj * {Game adjourned} }
        resign { DG 16 42 0 Res 0-1 {You resign} }
        abort { DG 16 42 0 Agr * {Game aborted} }
        {tell Admin hello} { DG 31 Admin {} hello 1 }
        {tell 4 hello} { DG 28 4 Admin {} hello 1 }
		next {
			Line {<12> ---r--k- pp---qpp --p-np-- P------- --P---Q- B------P -----PP- ----R-K- B -1 0 0 0 0 3 21 SENHUS MIHAILOP 0 3 0 22 23 50144 89881 26 Q/h4-g4 (0:07.838) Qg4 0 1 117}
		}
		mismatch {
			Line {<12> ----r-k- pp---qpp --p-np-- P------- --P---Q- B------P ----PP-- ----R-K- W -1 0 0 0 0 4 21 SENHUS MIHAILOP 0 3 0 22 23 50144 87644 27 R/d8-e8 (0:02.237) Re8 0 1 120}
		}
		jump {
			Line {<12> ----r-k- pp---qpp --p-np-- P------- --P---Q- B------P ----PP-- ----R-K- W -1 0 0 0 0 4 21 SENHUS MIHAILOP 0 3 0 22 23 50144 87644 30 R/d8-e8 (0:02.237) Re8 0 1 120}
		}
		unobserve {
			DG 19 21
		}
		quit {
			Line {Logging you out.}
			catch { close $::icc::fake::chan }
			set ::icc::fake::chan {}
		}
	}
}

proc ::icc::fake::Stop {} {
	variable server
	variable chan
	variable input
	variable received
	if {$chan ne ""} {
		catch { fileevent $chan readable {} }
		catch { close $chan }
		set chan {}
	}
	if {$server ne ""} { catch { close $server }; set server {} }
	set input {}
	set received {}
}


namespace eval ::icc::fake {
    variable style12 {<12> ---r--k- pp---qpp --p-np-- P------- --P----Q B------P -----PP- ----R-K- W -1 0 0 0 0 2 21 SENHUS MIHAILOP 0 3 0 22 23 55150 89881 26 N/c5-e6 (0:05.071) Ne6 0 1 0}
}
