# ======================================================================
# Scidb App Test — Download games from the internet
# (tcl/app-download-games.tcl)
# ======================================================================
# The pure helpers parse TWIC issue pages, Lichess game links and URL
# names; the fetch queue is driven with a stubbed Get (no network). The
# import call is captured by renaming ::import::import.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::download {
	variable Dir [file join [file dirname [file normalize [info script]]] tmp-app download_[pid]]
}

# Run <body> with the download state, the downloads dir and the import
# command restored; the downloads go to a scratch dir.
proc ::scidb::test::download::isolated {body} {
	set home $::scidb::dir::home
	set priv [array get ::application::download::Priv]
	file mkdir $::scidb::test::download::Dir
	set ::scidb::dir::home $::scidb::test::download::Dir
	set rc [catch { uplevel 1 $body } result]
	set ::scidb::dir::home $home
	array set ::application::download::Priv $priv
	if {$rc} { return -code error $result }
	return $result
}

# A <result> for the stubbed Get: {ok 1 data D code 200} or {ok 0 error E code C};
# the first is answered, the rest queue up, the last one repeating.
proc ::scidb::test::download::stubGet {results} {
	rename ::application::download::Get ::scidb::test::download::realGet
	set ::scidb::test::download::getCalls 0
	proc ::application::download::Get {url done} {
		variable ::scidb::test::download::getCalls
		variable ::scidb::test::download::getResults
		incr getCalls
		# pop before calling done: the queue recurses into the next Get synchronously
		set result [lindex $getResults 0]
		if {[llength $getResults] > 1} { set getResults [lrange $getResults 1 end] }
		{*}$done $result
	}
	set ::scidb::test::download::getResults $results
}

proc ::scidb::test::download::unstubGet {} {
	catch { rename ::application::download::Get {} }
	catch { rename ::scidb::test::download::realGet ::application::download::Get }
}

# Capture import calls: a list of {base files title encoding}.
proc ::scidb::test::download::captureImport {} {
	rename ::import::import ::scidb::test::download::realImport
	proc ::import::import {parent base files title {encoding {}}} {
		lappend ::scidb::test::download::importCalls [list $base $files $title $encoding]
		return 1
	}
	set ::scidb::test::download::importCalls {}
}

proc ::scidb::test::download::uncaptureImport {} {
	catch { rename ::import::import {} }
	catch { rename ::scidb::test::download::realImport ::import::import }
}

# A single event-loop tick (enough for a scheduled `after` retry); the
# synchronous stub needs no pumping for the success/failure paths.
proc ::scidb::test::download::tick {} {
	# let any `after` scheduled by the retry path fire once
	set ::scidb::test::download::tickFlag 0
	after 30 {set ::scidb::test::download::tickFlag 1}
	vwait ::scidb::test::download::tickFlag
}

proc ::scidb::test::download::cleanup {} {
	catch { file delete -force $::scidb::test::download::Dir }
}

# The TWIC index page shape: the current g/c6 zips and older plain zips.
tcltest::test download-twic-issues {issue numbers are parsed, newest first} -body {
	::scidb::test::download::isolated {
		set html {<html><a href="https://theweekinchess.com/zips/twic1663g.zip">twic1663g.zip</a>
<a href="https://theweekinchess.com/zips/twic1663c6.zip">chessbase</a>
<a href="https://theweekinchess.com/zips/twic1662g.zip">twic1662g.zip</a>
<a href="https://theweekinchess.com/zips/twic1661g.zip">twic1661g.zip</a>
<a href="https://theweekinchess.com/html/twic1663.html">issue 1663</a>}
		list [::application::download::twicIssues $html] \
			[::application::download::twicZipUrl 1663] \
			[::application::download::twicZipName 1663] \
			[::application::download::twicIssues {no zips here}]
	}
} -result {{1663 1662 1661} https://theweekinchess.com/zips/twic1663g.zip twic1663g.zip {}}

tcltest::test download-lichess-ids {lichess links and ids are extracted and deduplicated} -body {
	::scidb::test::download::isolated {
		set text {
https://lichess.org/HhM18x7g
https://lichess.org/game/export/HhM18x7g
lichess.org/q7ZvsdUF
some comment
AbCdEf12, ghIJKl34 ; mnOPqr56
not-a-game-link
}
		list [::application::download::lichessGameIds $text] \
			[::application::download::lichessGameIds {}] \
			[::application::download::lichessUrl HhM18x7g]
	}
} -result {{HhM18x7g q7ZvsdUF AbCdEf12 ghIJKl34 mnOPqr56} {} https://lichess.org/game/export/HhM18x7g}

tcltest::test download-dest-name {url downloads get safe file names} -body {
	::scidb::test::download::isolated {
		list \
			[::application::download::destName https://example.com/games/twic1660.pgn?dl=1] \
			[::application::download::destName https://example.com/download] \
			[::application::download::destName https://example.com/games%20file.zip] \
			[::application::download::destName https://example.com/games.pgn.gz]
	}
} -result {twic1660.pgn download.pgn games_20file.zip games.pgn.gz}

# The queue: each fetched file lands in the downloads dir and is passed to
# ::import::import.
tcltest::test download-queue-imports {fetched files are written and imported} -setup {
	::scidb::test::download::captureImport
	::scidb::test::download::stubGet [list \
		[list ok 1 data "1. e4 e5 2. Nf3" code 200] \
		[list ok 1 data "1. d4 d5" code 200]]
} -body {
	::scidb::test::download::isolated {
		set ::application::download::Priv(base) test-base
		set ::application::download::Priv(title) test-import
		set ::application::download::Priv(dialog) {}
		set ::application::download::Priv(cancel) 0
		set ::application::download::Priv(fetched) {}
		set ::application::download::Priv(failures) {}
		set ::application::download::Priv(queue) [list \
			[list https://example.com/a.pgn [file join [::application::download::Dir] a.pgn] A] \
			[list https://example.com/b.pgn [file join [::application::download::Dir] b.pgn] B]]
		::application::download::FetchNext
		set files [lsort [glob -directory [::application::download::Dir] *.pgn]]
		set contents [lmap f $files { set c [::open $f r]; set d [read $c]; close $c; set d }]
		lassign [lindex $::scidb::test::download::importCalls 0] base ifiles title encoding
		list $contents $base [lmap f $ifiles { file tail $f }] $title $encoding
	}
} -cleanup {
	::scidb::test::download::unstubGet
	::scidb::test::download::uncaptureImport
	::scidb::test::download::cleanup
} -result {{{1. e4 e5 2. Nf3} {1. d4 d5}} test-base {a.pgn b.pgn} test-import utf-8}

tcltest::test download-queue-retries {a transient failure is retried once} -setup {
	::scidb::test::download::captureImport
	set ::application::download::RetryDelay 1
	::scidb::test::download::stubGet [list \
		[list ok 0 error "connection reset" code 503] \
		[list ok 1 data "1. c4" code 200]]
} -body {
	::scidb::test::download::isolated {
		set ::application::download::Priv(base) test-base
		set ::application::download::Priv(title) test-import
		set ::application::download::Priv(dialog) {}
		set ::application::download::Priv(cancel) 0
		set ::application::download::Priv(fetched) {}
		set ::application::download::Priv(failures) {}
		set ::application::download::Priv(queue) [list \
			[list https://example.com/a.pgn [file join [::application::download::Dir] a.pgn] A]]
		::application::download::FetchNext
		::scidb::test::download::tick
		set f [lindex [glob -directory [::application::download::Dir] *.pgn] 0]
		set c [::open $f r]; set d [read $c]; close $c
		list $::scidb::test::download::getCalls [string length $d]
	}
} -cleanup {
	set ::application::download::RetryDelay 3000
	::scidb::test::download::unstubGet
	::scidb::test::download::uncaptureImport
	::scidb::test::download::cleanup
} -result {2 5}

tcltest::test download-queue-failure {a failed fetch keeps its file out of the import} -setup {
	::scidb::test::download::captureImport
	::scidb::test::download::stubGet [list [list ok 0 error "not found" code 404]]
} -body {
	::scidb::test::download::isolated {
		set ::application::download::Priv(base) test-base
		set ::application::download::Priv(title) test-import
		set ::application::download::Priv(dialog) {}
		set ::application::download::Priv(cancel) 0
		set ::application::download::Priv(fetched) {}
		set ::application::download::Priv(failures) {}
		set ::application::download::Priv(queue) [list \
			[list https://example.com/a.pgn [file join [::application::download::Dir] a.pgn] A]]
		::application::download::FetchNext
		list [llength $::scidb::test::download::importCalls] \
			[llength $::application::download::Priv(failures)] \
			[llength [glob -nocomplain -directory [::application::download::Dir] *.pgn]]
	}
} -cleanup {
	::scidb::test::download::unstubGet
	::scidb::test::download::uncaptureImport
	::scidb::test::download::cleanup
} -result {0 1 0}

# The dialog: opens with the three sources, and a TWIC start builds the
# queue from a stubbed index page.
tcltest::test download-dialog-twic {the dialog downloads TWIC issues and imports them} -setup {
	::scidb::test::download::captureImport
	set html {<a href="https://theweekinchess.com/zips/twic1663g.zip">twic1663g.zip</a>
<a href="https://theweekinchess.com/zips/twic1662g.zip">twic1662g.zip</a>}
	::scidb::test::download::stubGet [list \
		[list ok 1 data $html code 200] \
		[list ok 1 data "PK...zip-bytes..." code 200] \
		[list ok 1 data "PK...zip-bytes..." code 200]]
} -body {
	::scidb::test::download::isolated {
		set dlg [::application::download::open .application test-download-base]
		set have [list [winfo exists $dlg] [llength [info commands ::application::download::Start]]]
		set ::application::download::Priv(source) twic
		set ::application::download::Priv(issues) 2
		::application::download::Start
		lassign [lindex $::scidb::test::download::importCalls 0] base files title encoding
		list $have $base [llength $files] [string match {*1662-1663*} $title] $encoding \
			[file exists [file join [::application::download::Dir] twic1663g.zip]] \
			[winfo exists $dlg]
	}
} -cleanup {
	::scidb::test::download::unstubGet
	::scidb::test::download::uncaptureImport
	::scidb::test::download::cleanup
} -result {{1 1} test-download-base 2 1 utf-8 1 0}

# The headless entry used by the assistant: run() reports its result to a
# callback and needs no dialog at all.
tcltest::test download-run-headless {run() downloads and reports without a dialog} -setup {
	::scidb::test::download::captureImport
	set html {<a href="https://theweekinchess.com/zips/twic1663g.zip">x</a>}
	::scidb::test::download::stubGet [list \
		[list ok 1 data $html code 200] \
		[list ok 1 data "PK...zip..." code 200]]
} -body {
	::scidb::test::download::isolated {
		set ::application::download::Priv(dialog) {}
		set ::result {}
		::application::download::run test-base {-source twic -issues 1} \
			{apply {{r} {set ::result $r}}}
		::scidb::test::download::tick
		list [dict get $::result ok] [dict get $::result files] \
			[llength $::scidb::test::download::importCalls] \
			[file exists [file join [::application::download::Dir] twic1663g.zip]]
	}
} -cleanup {
	::scidb::test::download::unstubGet
	::scidb::test::download::uncaptureImport
	::scidb::test::download::cleanup
} -result {1 1 1 1}

tcltest::test download-player-name {player names from names and profile links} -body {
	lmap t {MagnusCarlsen " hikaru " https://www.chess.com/member/Hikaru https://lichess.org/@/DrNykterstein?x=1 "a b" x "bad;name"} {
		::application::download::playerName $t
	}
} -result {MagnusCarlsen hikaru Hikaru DrNykterstein {} {} {}}

tcltest::test download-chesscom-archives {the last months' archives, oldest first} -body {
	set json {{"archives":["https://api.chess.com/pub/player/hikaru/games/2026/07","https://api.chess.com/pub/player/hikaru/games/2026/08","https://api.chess.com/pub/player/hikaru/games/2026/09"]}}
	list [::application::download::chessComArchives $json 2] \
		[llength [::application::download::chessComArchives $json 12]] \
		[::application::download::chessComArchives {{"archives":[]}} 3] \
		[::application::download::chessComArchivesUrl Hikaru]
} -result {{https://api.chess.com/pub/player/hikaru/games/2026/08 https://api.chess.com/pub/player/hikaru/games/2026/09} 3 {} https://api.chess.com/pub/player/hikaru/games/archives}

tcltest::test download-run-chesscom {run() fetches a Chess.com player's months and imports them} -setup {
	::scidb::test::download::captureImport
	set json {{"archives":["https://api.chess.com/pub/player/hikaru/games/2026/08","https://api.chess.com/pub/player/hikaru/games/2026/09"]}}
	::scidb::test::download::stubGet [list \
		[list ok 1 data $json code 200] \
		[list ok 1 data "1. e4 e5" code 200]]
} -body {
	::scidb::test::download::isolated {
		set ::application::download::Priv(dialog) {}
		set ::result {}
		::application::download::run test-base {-source player -site Chess.com -player Hikaru -months 2} \
			{apply {{r} {set ::result $r}}}
		::scidb::test::download::tick
		list [dict get $::result ok] [dict get $::result files] \
			[file exists [file join [::application::download::Dir] chesscom-Hikaru-2026-09.pgn]] \
			[lindex $::scidb::test::download::importCalls 0 2]
	}
} -cleanup {
	::scidb::test::download::unstubGet
	::scidb::test::download::uncaptureImport
	::scidb::test::download::cleanup
} -result {1 2 1 {Chess.com games of Hikaru download import}}

tcltest::test download-run-lichess-user {run() fetches a Lichess player's games as one file} -setup {
	::scidb::test::download::captureImport
	::scidb::test::download::stubGet [list [list ok 1 data "1. d4 d5" code 200]]
} -body {
	::scidb::test::download::isolated {
		set ::application::download::Priv(dialog) {}
		set ::result {}
		::application::download::run test-base {-source player -site Lichess -player DrNykterstein -months 1} \
			{apply {{r} {set ::result $r}}}
		::scidb::test::download::tick
		list [dict get $::result ok] \
			[file exists [file join [::application::download::Dir] lichess-DrNykterstein.pgn]] \
			[string match https://lichess.org/api/games/user/DrNykterstein?since=* \
				[::application::download::lichessUserUrl DrNykterstein 0]]
	}
} -cleanup {
	::scidb::test::download::unstubGet
	::scidb::test::download::uncaptureImport
	::scidb::test::download::cleanup
} -result {1 1 1}

tcltest::test download-lichess-token {Lichess refusals ask for a token; the token goes to lichess.org only} -setup {
	::scidb::test::download::captureImport
	::scidb::test::download::stubGet [list [list ok 0 error "see other" code 303]]
} -body {
	::scidb::test::download::isolated {
		set ::application::download::Priv(dialog) {}
		set ::result {}
		::application::download::run test-base {-source player -site Lichess -player thibault -months 1} \
			{apply {{r} {set ::result $r}}}
		::scidb::test::download::tick
		list [dict get $::result ok] \
			[string match *lichess.org/account/oauth/token* [dict get $::result error]] \
			[info exists ::application::download::Options(lichess:token)]
	}
} -cleanup {
	::scidb::test::download::unstubGet
	::scidb::test::download::uncaptureImport
	::scidb::test::download::cleanup
} -result {0 1 1}

tcltest::test download-run-reports-failure {run() reports a failed download to its callback} -setup {
	::scidb::test::download::captureImport
	::scidb::test::download::stubGet [list [list ok 0 error "not found" code 404]]
} -body {
	::scidb::test::download::isolated {
		set ::application::download::Priv(dialog) {}
		set ::result {}
		::application::download::run test-base {-source url -url https://example.com/x.pgn} \
			{apply {{r} {set ::result $r}}}
		list [dict get $::result ok] [string match {*not found*} [dict get $::result error]]
	}
} -cleanup {
	::scidb::test::download::unstubGet
	::scidb::test::download::uncaptureImport
	::scidb::test::download::cleanup
} -result {0 1}

tcltest::cleanupTests