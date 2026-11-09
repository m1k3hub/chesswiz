# ======================================================================
# Scidb App Test — stream overlay server (tcl/stream.tcl)
# Talks to the server over 127.0.0.1 from inside the app with async
# sockets, since a blocking client would starve the server's event loop.
# ======================================================================

package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

namespace eval ::scidb::test::stream {
	variable Reply
	array set Reply {}
	variable Port 18765
}

# GET path; returns {status body} once the server closes, or the first
# event of an event stream.
proc ::scidb::test::stream::Get {path} {
	variable Reply
	variable Port
	set chan [socket 127.0.0.1 $Port]
	fconfigure $chan -blocking 0 -translation binary
	set Reply($chan) ""
	fileevent $chan readable [list ::scidb::test::stream::Read $chan]
	puts -nonewline $chan "GET $path HTTP/1.1\r\nHost: 127.0.0.1\r\n\r\n"
	flush $chan
	::scidb::test::wait::until {
		![info exists ::scidb::test::stream::Reply($chan)]
		|| [string match "*\n\n" $::scidb::test::stream::Reply($chan)]
		|| $chan ni [chan names]
	} 5000
	set text [expr {[info exists Reply($chan)] ? $Reply($chan) : ""}]
	catch { close $chan }
	if {[info exists Reply(done:$chan)]} { set text $Reply(done:$chan) }
	array unset Reply *$chan
	set status [lindex [split $text " "] 1]
	return [list $status $text]
}

proc ::scidb::test::stream::Read {chan} {
	variable Reply
	append Reply($chan) [encoding convertfrom utf-8 [read $chan]]
	if {[eof $chan]} {
		set Reply(done:$chan) $Reply($chan)
		unset Reply($chan)
		close $chan
	}
}

proc ::scidb::test::stream::Token {} {
	return $::stream::Priv(token)
}

proc ::scidb::test::stream::EventJson {} {
	::scidb::test::wait::until {$::stream::Priv(shown) ne ""} 3000
	lassign [Get /[Token]/events] status text
	regexp {data: (\{.*\})\n\n} $text -> json
	return $json
}

proc ::scidb::test::stream::OnlineGame {side {white Alice}} {
	set v [::online::window::gameTab test:stream Stream list $side]
	::online::view::setGame $v $white Bob startpos {e2e4 e7e5}
	::online::window::select test:stream
	update
	return $v
}

tcltest::test stream-start-url {start returns a 127.0.0.1 URL with a 32-hex token} -setup {
	::stream::stop
} -body {
	set url [::stream::start $::scidb::test::stream::Port]
	regexp {^http://127\.0\.0\.1:18765/[0-9a-f]{32}/scene/analysis$} $url
} -result 1

tcltest::test stream-pages {pages need the token; unknown pages 404} -body {
	set t [::scidb::test::stream::Token]
	list \
		[lindex [::scidb::test::stream::Get /$t/scene/analysis] 0] \
		[string match *EventSource* [lindex [::scidb::test::stream::Get /$t/block/eval] 1]] \
		[lindex [::scidb::test::stream::Get /wrongtoken/scene/analysis] 0] \
		[lindex [::scidb::test::stream::Get /$t/nope] 0]
} -result {200 1 404 404}

tcltest::test stream-events-board {the event stream carries the main board position} -body {
	set json [::scidb::test::stream::EventJson]
	list [string match {*"source":"board"*} $json] \
		[string match "*\"fen\":\"[::scidb::pos::fen]\"*" $json]
} -result {1 1}

tcltest::test stream-json-escape {JSON escapes quotes, backslashes and newlines} -body {
	::stream::Json [dict create white "A \"B\" \\ C\nD" sans {e4 e5} current 2]
} -result {{"white":"A \"B\" \\ C\nD","sans":["e4","e5"],"current":2}}

tcltest::test stream-fairplay-live {engine blocks are off while playing a person} -setup {
	set v [::scidb::test::stream::OnlineGame w]
	set ::stream::Priv(eval:score) 35
	set ::stream::Priv(eval:pv) {Nf3 Nc6}
	set ::stream::Priv(eval:fen) [::online::view::fen $v]
} -body {
	set d [::stream::state]
	list [dict get $d source] [dict get $d white] [dict get $d live] \
		[dict get $d engine] [dict exists $d score] [dict get $d last]
} -cleanup {
	::online::window::closeTab test:stream
} -result {online Alice 1 off 0 e7e5}

tcltest::test stream-fairplay-watching {watching a game keeps the engine on} -setup {
	set v [::scidb::test::stream::OnlineGame {}]
	set ::stream::Priv(eval:score) 35
	set ::stream::Priv(eval:fen) [::online::view::fen $v]
} -body {
	set d [::stream::state]
	list [dict get $d live] [dict get $d engine] [dict get $d score]
} -cleanup {
	::online::window::closeTab test:stream
} -result {0 on 35}

tcltest::test stream-fairplay-over {the engine comes back when the game is over} -setup {
	set v [::scidb::test::stream::OnlineGame b]
	set ::online::view::${v}::V(over) 1
	set ::stream::Priv(eval:score) -20
	set ::stream::Priv(eval:fen) [::online::view::fen $v]
} -body {
	set d [::stream::state]
	list [dict get $d live] [dict get $d engine]
} -cleanup {
	::online::window::closeTab test:stream
	wm withdraw .online
} -result {0 on}

tcltest::test stream-stale-eval {an eval for another position is not shown} -setup {
	set ::stream::Priv(eval:score) 99
	set ::stream::Priv(eval:fen) "8/8/8/8/8/8/8/K6k w - - 0 1"
} -body {
	dict get [::stream::state] engine
} -result none

tcltest::test stream-delay-field {the delay applies only while playing a person, clamped to 300 s} -setup {
	set saved $::stream::Options(delay)
} -body {
	set ::stream::Options(delay) 999
	set board [dict get [::stream::state] delay]
	set v [::scidb::test::stream::OnlineGame w]
	set live [dict get [::stream::state] delay]
	::online::window::closeTab test:stream
	set v [::scidb::test::stream::OnlineGame {}]
	set watch [dict get [::stream::state] delay]
	list $board $live $watch
} -cleanup {
	::online::window::closeTab test:stream
	wm withdraw .online
	set ::stream::Options(delay) $saved
} -result {0 300 0}

tcltest::test stream-delay-release {a live game reaches the pages only after the delay} -setup {
	set saved $::stream::Options(delay)
	set ::stream::Options(delay) 1
	::stream::stop
	::stream::start $::scidb::test::stream::Port
	::scidb::test::wait::until {$::stream::Priv(shown) ne ""} 3000
} -body {
	set t0 [clock milliseconds]
	set v [::scidb::test::stream::OnlineGame w Carol]
	::scidb::test::wait::until {[llength $::stream::Priv(queue)]} 3000
	set early [string match *Carol* $::stream::Priv(shown)]
	::scidb::test::wait::until {[string match *Carol* $::stream::Priv(shown)]} 5000
	set waited [expr {[clock milliseconds] - $t0 >= 950}]
	set json [::scidb::test::stream::EventJson]
	list $early $waited [string match {*"delay":1*} $json]
} -cleanup {
	::online::window::closeTab test:stream
	wm withdraw .online
	set ::stream::Options(delay) $saved
} -result {0 1 1}


# ----------------------------------------------------------------------
# Twitch chat, replayed from recorded IRC lines (no network)
# ----------------------------------------------------------------------

proc ::scidb::test::stream::Replay {lines} {
	set ::stream::chat::Priv(lines) {}
	foreach l $lines { ::stream::chat::handle $l }
	lmap l [::stream::chat::lines] { list [dict get $l name] [dict get $l text] }
}

tcltest::test stream-chat-parse {tags, prefix, command and trailing text} -body {
	lassign [::stream::chat::Parse {@badge-info=;color=#1E90FF;display-name=Chess\sFan;id=a1 :chessfan!chessfan@chessfan.tmi.twitch.tv PRIVMSG #wiz :hello there: e4!}] tags prefix cmd params
	list [dict get $tags display-name] [dict get $tags color] $prefix $cmd $params
} -result {{Chess Fan} #1E90FF chessfan!chessfan@chessfan.tmi.twitch.tv PRIVMSG {{#wiz} {hello there: e4!}}}

tcltest::test stream-chat-messages {display names, /me actions, fallback to login} -body {
	::scidb::test::stream::Replay {
		{@color=#FF0000;display-name=Magnus;id=m1 :magnus!magnus@magnus.tmi.twitch.tv PRIVMSG #wiz :Nf3 is best}
		"@display-name=;id=m2 :anon42!anon42@anon42.tmi.twitch.tv PRIVMSG #wiz :\x01ACTION waves\x01"
		{:tmi.twitch.tv PING :tmi.twitch.tv}
	}
} -result {{Magnus {Nf3 is best}} {anon42 waves}}

tcltest::test stream-chat-moderation {deleted messages and timed-out users disappear} -body {
	list [::scidb::test::stream::Replay {
		{@display-name=A;id=1 :a!a@a.tmi.twitch.tv PRIVMSG #wiz :one}
		{@display-name=B;id=2 :b!b@b.tmi.twitch.tv PRIVMSG #wiz :spam}
		{@display-name=A;id=3 :a!a@a.tmi.twitch.tv PRIVMSG #wiz :two}
		{@login=a;target-msg-id=1 :tmi.twitch.tv CLEARMSG #wiz :one}
		{@ban-duration=600 :tmi.twitch.tv CLEARCHAT #wiz :b}
	}] [::scidb::test::stream::Replay {
		{@display-name=A;id=1 :a!a@a.tmi.twitch.tv PRIVMSG #wiz :one}
		{:tmi.twitch.tv CLEARCHAT #wiz}
	}]
} -result {{{A two}} {}}

tcltest::test stream-chat-keep {only the last 50 lines are kept} -body {
	set lines {}
	for {set i 1} {$i <= 60} {incr i} {
		lappend lines "@display-name=U;id=$i :u!u@u.tmi.twitch.tv PRIVMSG #wiz :line $i"
	}
	set got [::scidb::test::stream::Replay $lines]
	list [llength $got] [lindex $got 0 1]
} -result {50 {line 11}}

tcltest::test stream-chat-bad-channel {channel names are checked before connecting} -body {
	list [catch { ::stream::chat::connect "no spaces!" }] [::stream::chat::state]
} -result {1 off}

tcltest::test stream-chat-event {pages receive chat as its own event, escaped} -setup {
	::stream::stop
	::stream::start $::scidb::test::stream::Port
	::scidb::test::wait::until {$::stream::Priv(shown) ne ""} 3000
	::scidb::test::stream::Replay {
		{@color=#00FF00;display-name=Fan;id=9 :fan!fan@fan.tmi.twitch.tv PRIVMSG #wiz :<b>"hi"</b>}
	}
} -body {
	lassign [::scidb::test::stream::Get /[::scidb::test::stream::Token]/events] status text
	::scidb::test::wait::until {1} 100
	regexp {event: chat\ndata: (\{[^\n]*\})} $text -> json
	set json
} -result {{"chat":[{"name":"Fan","colour":"#00FF00","text":"<b>\"hi\"</b>","platform":"twitch"}]}}

tcltest::test stream-stop {stop closes the port} -body {
	::stream::stop
	list [::stream::running?] [catch { socket 127.0.0.1 $::scidb::test::stream::Port }]
} -result {0 1}

tcltest::cleanupTests
