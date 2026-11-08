# ======================================================================
# Scidb App Test — Free Internet Chess Server client (tcl/ics.tcl)
# All transport tests below use a fake server bound to 127.0.0.1. The
# real freechess.org is never contacted.
# ======================================================================

package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

namespace eval ::scidb::test::ics {}

set ::scidb::test::ics::style12 {<12> ---r--k- pp---qpp --p-np-- P------- --P----Q B------P -----PP- ----R-K- W -1 0 0 0 0 2 21 SENHUS MIHAILOP 0 3 0 22 23 55150 89881 26 N/c5-e6 (0:05.071) Ne6 0 1 0}

# ----------------------------------------------------------------------
# Pure protocol parsers
# ----------------------------------------------------------------------

tcltest::test ics-cleanline {prompt runs, CR, telnet IAC and UTF-8 cleaning} -body {
	set utf8 [::ics::cleanLine "fics% caf\xc3\xa9 \xff text"]
	list \
		[::ics::cleanLine "fics% fics% <sc>\r"] \
		[::ics::cleanLine "fics% \xff\xfb\x01password: "] \
		[binary encode hex [encoding convertto utf-8 $utf8]]
} -result {<sc> {password: } 636166c3a9202074657874}

tcltest::test ics-style12 {the verified live style 12 line, including FEN and clocks} -body {
	set p [::ics::parseStyle12 $::scidb::test::ics::style12]
	list \
		[dict get $p board] [dict get $p stm] [dict get $p castling] \
		[dict get $p enPassant] [dict get $p halfmove] [dict get $p game] \
		[dict get $p white] [dict get $p black] [dict get $p relation] \
		[dict get $p minutes] [dict get $p increment] \
		[dict get $p whiteClock] [dict get $p blackClock] \
		[dict get $p moveNumber] [dict get $p verbose] [dict get $p san] \
		[dict get $p ticking] [dict get $p ply] [dict get $p fen]
} -result {3r2k1/pp3qpp/2p1np2/P7/2P4Q/B6P/5PP1/4R1K1 w - - 2 21 SENHUS MIHAILOP 0 3 0 55150 89881 26 N/c5-e6 Ne6 1 50 {3r2k1/pp3qpp/2p1np2/P7/2P4Q/B6P/5PP1/4R1K1 w - - 2 26}}

tcltest::test ics-style12-ep-castling {double-pawn file becomes en-passant and castling bits become FEN} -body {
	set p [::ics::parseStyle12 {<12> rnbqkbnr pppppppp -------- -------- ----P--- -------- PPPP-PPP RNBQKBNR B 4 1 1 1 1 0 1 White Black -1 5 0 39 39 300000 300000 1 P/e2-e4 (0:00.000) e4 0 1 0}]
	list [dict get $p fen] [dict get $p ply] [dict get $p san]
} -result {{rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1} 1 e4}

tcltest::test ics-seek-parser {the verified live seek fields} -body {
	set s [::ics::parseSeek {<s> 6 w=konnybrook ti=00 rt=1285E t=10 i=0 r=u tp=blitz c=? rr=0-9999 a=t f=f}]
	list [dict get $s index] [dict get $s name] [dict get $s computer] \
		[dict get $s rating] [dict get $s time] [dict get $s inc] \
		[dict get $s rated] [dict get $s type] [dict get $s color] \
		[::ics::StandardSeek $s]
} -result {6 konnybrook 0 1285E 10 0 u blitz ? 1}

tcltest::test ics-seek-updates {standard seeks are live, computers included; variants are filtered; sr and sc remove} -setup {
	set ::ics::Seeks [dict create]
} -body {
	::ics::ProcessLine {<s> 6 w=konnybrook ti=00 rt=1285E t=10 i=0 r=u tp=blitz c=? rr=0-9999 a=t f=f}
	::ics::ProcessLine {<s> 7 w=WildPlayer ti=00 rt=1500 t=5 i=0 r=u tp=wild/8 c=? rr=0-9999 a=t f=f}
	::ics::ProcessLine {<s> 8 w=Computer ti=02 rt=2469 t=30 i=5 r=r tp=standard c=? rr=0-9999 a=t f=t}
	set first [lsort -integer [dict keys $::ics::Seeks]]
	::ics::ProcessLine {<sr> 55 6}
	set removed [dict keys $::ics::Seeks]
	::ics::ProcessLine {<s> 9 w=Second ti=00 rt=1500P t=0 i=0 r=u tp=untimed c=B rr=0-9999 a=t f=f}
	::ics::ProcessLine {<sc>}
	list $first $removed [dict keys $::ics::Seeks]
} -cleanup {
	set ::ics::Seeks [dict create]
} -result {{6 8} 8 {}}

tcltest::test ics-game-start-parsers {creating, numbered match and observation descriptions} -body {
	set a [::ics::parseGameStart {Creating: GuestAAAA (++++) Opponent (1500) unrated blitz 5 0}]
	set b [::ics::parseGameStart {{Game 42 (GuestAAAA vs. Opponent) Creating unrated blitz match.}}]
	set c [::ics::parseGameStart {Game 21: SENHUS (1914) MIHAILOP (2183) rated blitz 3 0}]
	list [dict get $a white] [dict get $a whiteRating] [dict get $a blackRating] \
		[dict get $a rated] [dict get $a type] [dict get $a minutes] [dict get $a increment] \
		[dict get $b game] [dict get $b white] [dict get $b black] \
		[dict get $c game] [dict get $c observing] [dict get $c whiteRating] [dict get $c blackRating]
} -result {GuestAAAA ++++ 1500 unrated blitz 5 0 42 GuestAAAA Opponent 21 1 1914 2183}

tcltest::test ics-game-end-parser {resignation, mate, timeout, draw and abort endings} -body {
	set rows {}
	foreach line {
		{{Game 42 (GuestAAAA vs. Opponent) GuestAAAA resigns} 0-1}
		{{Game 42 (GuestAAAA vs. Opponent) GuestAAAA checkmated} 0-1}
		{{Game 42 (GuestAAAA vs. Opponent) GuestAAAA forfeits on time} 0-1}
		{{Game 42 (GuestAAAA vs. Opponent) Game drawn by repetition} 1/2-1/2}
		{{Game 42 (GuestAAAA vs. Opponent) Game aborted on move 1} *}
	} {
		set p [::ics::parseGameEnd $line]
		lappend rows [dict get $p game] [dict get $p reason] [dict get $p result]
	}
	set rows
} -result {42 {GuestAAAA resigns} 0-1 42 {GuestAAAA checkmated} 0-1 42 {GuestAAAA forfeits on time} 0-1 42 {Game drawn by repetition} 1/2-1/2 42 {Game aborted on move 1} *}

tcltest::test ics-clock-countdown {only the ticking side to move counts down between server snapshots} -setup {
	set saved [array get ::ics::Priv]
	array set ::ics::Priv {clock:w 10000 clock:b 8000 clockAt 100000 clockStm w ticking 1}
} -body {
	list [::ics::Remaining w 100250] [::ics::Remaining b 100250] [::ics::Remaining w 101100]
} -cleanup {
	array set ::ics::Priv $saved
} -result {9750 8000 8900}

# ----------------------------------------------------------------------
# Loopback FICS server. Its replies are real byte streams, including
# unterminated prompts, IAC bytes and repeated fics% prompts.
# ----------------------------------------------------------------------

namespace eval ::scidb::test::ics {
	variable server {}
	variable chan {}
	variable input {}
	variable received {}
	variable mode guest
	variable state login
	variable nf3 0
}

proc ::scidb::test::ics::Start {{kind guest}} {
	variable server
	variable mode
	set mode $kind
	set server [socket -server ::scidb::test::ics::Accept -myaddr 127.0.0.1 0]
	return [lindex [fconfigure $server -sockname] 2]
}

proc ::scidb::test::ics::Accept {channel address port} {
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
	fileevent $chan readable ::scidb::test::ics::Read
	Write "login: "
}

proc ::scidb::test::ics::Write {text} {
	variable chan
	if {$chan eq ""} { return }
	catch { puts -nonewline $chan $text; flush $chan }
}

proc ::scidb::test::ics::Line {line} { Write "$line\r\n" }

proc ::scidb::test::ics::Read {} {
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

proc ::scidb::test::ics::Login {} {
	Line {**** Starting FICS session as GuestTEST(U) ****}
	Line {<sc>}
	Line {fics% fics% <s> 6 w=konnybrook ti=00 rt=1285E t=10 i=0 r=u tp=blitz c=? rr=0-9999 a=t f=f}
	Line {<s> 7 w=WildPlayer ti=00 rt=1500 t=5 i=0 r=u tp=wild/8 c=? rr=0-9999 a=t f=f}
	Line {<s> 8 w=Computer ti=02 rt=2469 t=30 i=5 r=r tp=standard c=? rr=0-9999 a=t f=t}
	Line {ROBOadmin tells you: Welcome to the test server.}
}

proc ::scidb::test::ics::Handle {line} {
	variable received
	variable mode
	variable state
	variable nf3
	lappend received $line

	if {$state eq "login"} {
		if {$mode eq "guest" && $line eq "guest"} {
			Line {Logging you in as "GuestTEST"; you may use this name to play unrated games.}
			Write "Press return to enter the server as \"GuestTEST\":\xff\xfc\x01"
			set state guestReturn
		} elseif {$mode ni "guest" && $line ne ""} {
			Write "password: \xff\xfb\x01"
			set state password
		}
		return
	}
	if {$state eq "guestReturn" && $line eq ""} {
		set state online
		Login
		return
	}
	if {$state eq "password"} {
		if {$mode eq "registeredReject"} {
			Line {**** Invalid password! ****}
			set state rejected
		} else {
			set state online
			Line {**** Starting FICS session as TestPlayer ****}
			Line {<sc>}
		}
		return
	}
	if {$state ne "online"} { return }

	switch -- $line {
		{play 6} {
			Line {Creating: GuestTEST (++++) Opponent (1500) unrated blitz 5 0}
			Line {{Game 42 (GuestTEST vs. Opponent) Creating unrated blitz match.}}
			Line {fics% fics% <12> rnbqkbnr pppppppp -------- -------- -------- -------- PPPPPPPP RNBQKBNR W -1 1 1 1 1 0 42 GuestTEST Opponent 1 5 0 39 39 300000 300000 1 none (0:00.000) none 0 1 0}
		}
		e4 {
			Line {<12> rnbqkbnr pppppppp -------- -------- ----P--- -------- PPPP-PPP RNBQKBNR B 4 1 1 1 1 0 42 GuestTEST Opponent -1 5 0 39 39 299000 300000 1 P/e2-e4 (0:01.000) e4 0 1 0}
			Line {<12> rnbqkbnr pppp-ppp -------- ----p--- ----P--- -------- PPPP-PPP RNBQKBNR W 4 1 1 1 1 0 42 GuestTEST Opponent 1 5 0 39 39 299000 298000 2 P/e7-e5 (0:02.000) e5 0 1 0}
		}
		Nf3 {
			incr nf3
			if {$nf3 == 1} {
				Line {Illegal move: Nf3}
			} else {
				Line {<12> rnbqkbnr pppp-ppp -------- ----p--- ----P--- -----N-- PPPP-PPP RNBQKB-R B -1 1 1 1 1 1 42 GuestTEST Opponent -1 5 0 39 39 298000 298000 2 N/g1-f3 (0:01.000) Nf3 0 1 0}
				Line {<12> r-bqkbnr pppp-ppp --n----- ----p--- ----P--- -----N-- PPPP-PPP RNBQKB-R W -1 1 1 1 1 2 42 GuestTEST Opponent 1 5 0 38 39 298000 297000 3 N/b8-c6 (0:01.000) Nc6 0 1 0}
				Line {{Game 42 (GuestTEST vs. Opponent) Opponent resigns} 1-0}
			}
		}
		{observe /b} {
			Line {You are now observing game 21.}
			Line {Game 21: SENHUS (1914) MIHAILOP (2183) rated blitz 3 0}
			Line $::scidb::test::ics::style12
		}
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
			Line {Removing game 21 from observation list.}
		}
		quit {
			Line {Logging you out.}
			catch { close $::scidb::test::ics::chan }
			set ::scidb::test::ics::chan {}
		}
	}
}

proc ::scidb::test::ics::Stop {} {
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

proc ::scidb::test::ics::Release {} {
	set pos $::ics::Priv(pos)
	::ics::Close
	catch { ::application::pgn::release $pos }
	catch { ::game::release $pos }
	Stop
}

proc ::scidb::test::ics::Connect {{handle ""} {password ""} {kind ""}} {
	variable received
	if {$kind eq ""} { set kind [expr {$handle eq "" ? "guest" : "registeredReject"}] }
	set port [Start $kind]
	set ::ics::Options(host) 127.0.0.1
	set ::ics::Options(port) $port
	set ::ics::Options(handle) $handle
	set dlg [::ics::open .application]
	update
	set ::ics::Priv(dlg:password) $password
	[::util::place::playingBody $dlg].ok invoke
	return $dlg
}

# ----------------------------------------------------------------------
# Real client transport and board integration against the fake server
# ----------------------------------------------------------------------

tcltest::test ics-options-password {options retain host, port and handle but never a password} -setup {
	set saved [array get ::ics::Options]
	set ::ics::Priv(textLines) {}
} -body {
	set dlg [::scidb::test::ics::Connect TestPlayer never-save-me]
	if {[catch { ::scidb::test::wait::until {$::ics::Priv(state) eq "offline" && $::ics::Priv(statusText) eq "The server rejected the password."} } err]} {
		error "$err; clientState=$::ics::Priv(state); status=$::ics::Priv(statusText); serverState=$::scidb::test::ics::state; serverLineCount=[llength $::scidb::test::ics::received]"
	}
	set file [file join $::env(HOME) ics-options.tcl]
	set out [open $file w]
	::ics::WriteOptions $out
	close $out
	set in [open $file r]
	set savedText [read $in]
	close $in
	set logged [join $::ics::Priv(textLines) "\n"]
	list \
		[expr {"never-save-me" in $::scidb::test::ics::received}] \
		[expr {[string first never-save-me $savedText] < 0}] \
		[expr {[string first never-save-me $logged] < 0}] \
		[expr {[string first TestPlayer $savedText] >= 0}] \
		$::ics::Priv(loginPassword) $::ics::Priv(dlg:password) \
		[::capability::present ics]
} -cleanup {
	::scidb::test::ics::Release
	array set ::ics::Options $saved
	set ::ics::Priv(textLines) {}
} -result {1 1 1 1 {} {} 1}

tcltest::test ics-registered-login {registered login enables rated seeks and sends the style 12 setup} -setup {
	set saved [array get ::ics::Options]
} -body {
	set dlg [::scidb::test::ics::Connect TestPlayer transient-secret registeredAccept]
	::scidb::test::wait::until {$::ics::Priv(state) eq "lobby"}
	set ::ics::Priv(dlg:rated) 1
	set ::ics::Priv(dlg:color) $::ics::mc::Black
	::ics::Seek
	::scidb::test::wait::until {"seek 5 0 r b" in $::scidb::test::ics::received}
	set setupSeen 1
	foreach command {
		{iset nowrap 1} {iset ms 1} {iset seekinfo 1} {iset seekremove 1}
		{set style 12} {set bell 0} {set interface Chesswiz}
	} {
		if {$command ni $::scidb::test::ics::received} { set setupSeen 0 }
	}
	list $::ics::Priv(handle) $::ics::Priv(guest) \
		[$::ics::Priv(widget:rated) instate !disabled] \
		[expr {"seek 5 0 r b" in $::scidb::test::ics::received}] $setupSeen \
		$::ics::Priv(loginPassword) $::ics::Priv(dlg:password)
} -cleanup {
	::scidb::test::ics::Release
	array set ::ics::Options $saved
} -result {TestPlayer 0 1 1 1 {} {}}

tcltest::test ics-guest-game {guest login, seeks, moves, clocks, illegal rollback and result on the main board} -setup {
	set saved [array get ::ics::Options]
	set ::ics::Priv(textLines) {}
} -body {
	set dlg [::scidb::test::ics::Connect]
	::scidb::test::wait::until {$::ics::Priv(state) eq "lobby"}
	set tree $::ics::Priv(widget:tree)
	set rows [$tree children {}]
	set guestRated [$::ics::Priv(widget:rated) instate disabled]
	set ::ics::Priv(dlg:minutes) 3
	set ::ics::Priv(dlg:increment) 2
	set ::ics::Priv(dlg:rated) 1
	::ics::Seek
	::ics::Unseek
	set ::ics::Priv(dlg:raw) {tell 4 hello}
	::ics::SendRaw
	$tree selection set 6
	::ics::PlaySelected
	::scidb::test::wait::until {$::ics::Priv(active) && $::ics::Priv(gameNumber) == 42}
	set initialFen [::scidb::pos::fen]
	set initialTags [::scidb::game::tags]
	puts "EVIDENCE ics-initial-tags=$initialTags"
	puts "EVIDENCE ics-initial-info=$::ics::Priv(gameInfo)"
	set accepted [::ics::UserMove e4]
	::scidb::test::wait::until {[::ics::BoardPly] == 2 && [lsearch -exact $::scidb::test::ics::received e4] >= 0}
	set afterPair [::scidb::pos::fen]
	set clocks [list $::ics::Priv(clock:w) $::ics::Priv(clock:b)]
	set illegalAccepted [::ics::UserMove Nf3]
	::scidb::test::wait::until {$::scidb::test::ics::nf3 == 1 && $::ics::Priv(pendingMove) eq ""}
	set rollback [list [::ics::BoardPly] [lindex [::scidb::pos::fen] 0] $::ics::Priv(relation)]
	set secondAccepted [::ics::UserMove Nf3]
	::scidb::test::wait::until {$::ics::Priv(state) eq "over"}
	set finalFen [::scidb::pos::fen]
	set finalTags [::scidb::game::tags]
	set finalClocks [list $::ics::Priv(clock:w) $::ics::Priv(clock:b)]
	list \
		$::ics::Priv(handle) $::ics::Options(handle) $rows $guestRated \
		[expr {"seek 3 2 u" in $::scidb::test::ics::received}] \
		[expr {"unseek" in $::scidb::test::ics::received}] \
		[expr {"tell 4 hello" in $::scidb::test::ics::received}] \
		[lindex $initialFen 0] \
		[expr {[lsearch -exact $initialTags {White GuestTEST}] >= 0}] \
		[expr {[lsearch -exact $initialTags {Black Opponent}] >= 0}] \
		[expr {[lsearch -exact $initialTags {BlackElo 1500}] >= 0}] \
		[expr {[lsearch -exact $initialTags {WhiteElo ++++}] >= 0}] \
		[expr {[lsearch -exact $initialTags {Event {FICS unrated blitz game}}] >= 0}] \
		[expr {[lsearch -exact $initialTags {TimeControl 300+0}] >= 0}] \
		$accepted [lindex $afterPair 0] $clocks \
		$illegalAccepted $rollback $secondAccepted \
		[lindex $finalFen 0] $finalClocks \
		[expr {[lsearch -exact $finalTags {Result 1-0}] >= 0}] \
		[$::ics::Priv(widget:back) instate !disabled]
} -cleanup {
	::scidb::test::ics::Release
	array set ::ics::Options $saved
} -result {GuestTEST {} {6 8} 1 1 1 1 rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR 1 1 1 0 1 1 1 rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR {299000 298000} 1 {2 rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR 1} 1 r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R {298000 297000} 1 1}

tcltest::test ics-observe {a mid-game observed board imports SetUp/FEN, stays read-only and follows style 12} -setup {
	set saved [array get ::ics::Options]
} -body {
	set dlg [::scidb::test::ics::Connect]
	::scidb::test::wait::until {$::ics::Priv(state) eq "lobby"}
	::ics::Watch
	::scidb::test::wait::until {$::ics::Priv(active) && $::ics::Priv(gameNumber) == 21 && $::move::Disabled}
	set tags [::scidb::game::tags]
	set pgn [::scidb::game::toPGN modified -position $::ics::Priv(pos)]
	set headerPgn [::ics::BoardPgn $::ics::Priv(gameInfo) [::ics::parseStyle12 $::scidb::test::ics::style12] 1 *]
	puts "EVIDENCE ics-observe-tags=$tags"
	puts "EVIDENCE ics-observe-pgn=$pgn"
	puts "EVIDENCE ics-observe-state=active=$::ics::Priv(active) observing=$::ics::Priv(observing) relation=$::ics::Priv(relation) disabled=$::move::Disabled"
	set fen [::scidb::pos::fen]
	set before [list [::ics::BoardPly] $::move::Disabled \
		$::ics::Priv(clock:w) $::ics::Priv(clock:b)]
	set refused [::ics::UserMove Qg4]
	::move::addMove menu Qg4
	set unchanged [::ics::BoardPly]
	::ics::Send next
	::scidb::test::wait::until {[::ics::BoardPly] == 51}
	set moved [list [lindex [::scidb::pos::fen] 0] [::scidb::game::query length] $::move::Disabled]
	::ics::Send mismatch
	::scidb::test::wait::until {[::ics::BoardPly] == 52 && [::scidb::game::query length] == 0}
	set resynced [list [lindex [::scidb::pos::fen] 0] [::scidb::game::query length] $::move::Disabled]
	::ics::Send jump
	::scidb::test::wait::until {[::ics::BoardPly] == 58}
	set jumped [list [::ics::BoardPly] [::scidb::game::query length] $::move::Disabled]
	::ics::BackToLobby
	::scidb::test::wait::until {"unobserve" in $::scidb::test::ics::received}
	list \
		[expr {[string first {[SetUp "1"]} $headerPgn] >= 0}] \
		[expr {[string first [format {[FEN "%s"]} [dict get [::ics::parseStyle12 $::scidb::test::ics::style12] fen]] $headerPgn] >= 0}] \
		$fen $before $refused $unchanged $moved $resynced $jumped \
		$::ics::Priv(state) $::move::Disabled
} -cleanup {
	::scidb::test::ics::Release
	array set ::ics::Options $saved
} -result {1 1 {3r2k1/pp3qpp/2p1np2/P7/2P4Q/B6P/5PP1/4R1K1 w - - 2 26} {50 1 55150 89881} 0 50 {3r2k1/pp3qpp/2p1np2/P7/2P3Q1/B6P/5PP1/4R1K1 1 1} {4r1k1/pp3qpp/2p1np2/P7/2P3Q1/B6P/4PP2/4R1K1 0 1} {58 0 1} lobby 0}

tcltest::test ics-text-limit {only the last 200 server text lines are retained} -setup {
	set saved $::ics::Priv(textLines)
	set ::ics::Priv(textLines) {}
} -body {
	for {set i 0} {$i < 205} {incr i} { ::ics::LogText "line $i" }
	list [llength $::ics::Priv(textLines)] [lindex $::ics::Priv(textLines) 0] [lindex $::ics::Priv(textLines) end]
} -cleanup {
	set ::ics::Priv(textLines) $saved
} -result {200 {line 5} {line 204}}

tcltest::cleanupTests
