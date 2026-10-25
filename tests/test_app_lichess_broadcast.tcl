# ======================================================================
# Scidb App Test — Lichess broadcast download
# (tcl/app-download-games.tcl)
# ======================================================================
# The pure helpers read a broadcast round URL or a tournament id, build
# the PGN URL of the API and tell the games of a round apart (the dedup
# key). The fetch is driven with a stubbed Get (no network) and the
# import call is captured by renaming ::import::import.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::broadcast {
	variable Dir [file join [file dirname [file normalize [info script]]] tmp-app roadmap-partial broadcast scratch_[pid]]
}

# Run <body> with the download state, the options and the downloads dir
# restored; the downloads go to a scratch dir.
proc ::scidb::test::broadcast::isolated {body} {
	set home $::scidb::dir::home
	set priv [array get ::application::download::Priv]
	set options [array get ::application::download::Options]
	file mkdir $::scidb::test::broadcast::Dir
	set ::scidb::dir::home $::scidb::test::broadcast::Dir
	set rc [catch { uplevel 1 $body } result]
	# the dialog and its timers are gone before the state is restored
	catch { ::application::download::Close }
	set ::scidb::dir::home $home
	array set ::application::download::Priv $priv
	array set ::application::download::Options $options
	if {$rc} { return -code error $result }
	return $result
}

# A <result> for the stubbed Get: {ok 1 data D code 200} or {ok 0 error E
# code C}; the first is answered, the rest queue up, the last one
# repeating.
proc ::scidb::test::broadcast::stubGet {results} {
	rename ::application::download::Get ::scidb::test::broadcast::realGet
	set ::scidb::test::broadcast::getCalls 0
	set ::scidb::test::broadcast::getUrls {}
	set ::scidb::test::broadcast::getFlag 0
	proc ::application::download::Get {url done} {
		variable ::scidb::test::broadcast::getCalls
		variable ::scidb::test::broadcast::getResults
		variable ::scidb::test::broadcast::getUrls
		variable ::scidb::test::broadcast::getFlag
		incr getCalls
		lappend getUrls $url
		incr getFlag
		# pop before calling done: the queue recurses into the next Get synchronously
		set result [lindex $getResults 0]
		if {[llength $getResults] > 1} { set getResults [lrange $getResults 1 end] }
		{*}$done $result
	}
	set ::scidb::test::broadcast::getResults $results
}

proc ::scidb::test::broadcast::unstubGet {} {
	catch { rename ::application::download::Get {} }
	catch { rename ::scidb::test::broadcast::realGet ::application::download::Get }
}

# Capture import calls: a list of {base files title encoding text}.
proc ::scidb::test::broadcast::captureImport {} {
	rename ::import::import ::scidb::test::broadcast::realImport
	proc ::import::import {parent base files title {encoding {}}} {
		set file [lindex $files 0]
		set text ""
		if {[file exists $file]} {
			set chan [::open $file r]
			set text [read $chan]
			close $chan
		}
		lappend ::scidb::test::broadcast::importCalls \
			[list $base $files $title $encoding $text]
		return 1
	}
	set ::scidb::test::broadcast::importCalls {}
}

proc ::scidb::test::broadcast::uncaptureImport {} {
	catch { rename ::import::import {} }
	catch { rename ::scidb::test::broadcast::realImport ::import::import }
}

# The text of the file that was imported.
proc ::scidb::test::broadcast::importedText {n} {
	return [lindex $::scidb::test::broadcast::importCalls $n 4]
}

# A dict of the keys, as the download code keeps them.
proc ::scidb::test::broadcast::keyDict {keys} {
	set dict [dict create]
	foreach key $keys { dict set dict $key 1 }
	return $dict
}

# The file that was imported.
proc ::scidb::test::broadcast::importedFile {n} {
	return [lindex [lindex $::scidb::test::broadcast::importCalls $n 1] 0]
}

# Wait until the stubbed Get was called <n> times.
proc ::scidb::test::broadcast::waitForCalls {n} {
	set deadline [expr {[clock seconds] + 10}]
	while {$::scidb::test::broadcast::getCalls < $n && [clock seconds] < $deadline} {
		set timeout [after 10000 [list set ::scidb::test::broadcast::getFlag 0]]
		vwait ::scidb::test::broadcast::getFlag
		after cancel $timeout
	}
	return $::scidb::test::broadcast::getCalls
}

proc ::scidb::test::broadcast::cleanup {} {
	catch { file delete -force $::scidb::test::broadcast::Dir }
}

# The games of a database, as ::scidb::db::get answers them: a list of
# {name value} pairs for every game. The database is asked for the games
# it has, not for a file.
proc ::scidb::test::broadcast::stubDb {games} {
	rename ::scidb::db::get ::scidb::test::broadcast::realDbGet
	rename ::scidb::db::count ::scidb::test::broadcast::realDbCount
	# the stub lives in the namespace of the command it replaces: an
	# unqualified switch would be the database switch, not the Tcl one
	proc ::scidb::db::get {args} {
		variable ::scidb::test::broadcast::dbGames
		::set sub [lindex $args 0]
		if {$sub eq "open?"} { return 1 }
		if {$sub eq "tags"} {
			::set index [lindex $args 1]
			if {$index >= [llength $::scidb::test::broadcast::dbGames]} {
				error "no game $index"
			}
			return [lindex $::scidb::test::broadcast::dbGames $index]
		}
		return ""
	}
	# the number of games of the base
	proc ::scidb::db::count {args} {
		variable ::scidb::test::broadcast::dbGames
		return [llength $::scidb::test::broadcast::dbGames]
	}
	set ::scidb::test::broadcast::dbGames $games
}

proc ::scidb::test::broadcast::unstubDb {} {
	catch { rename ::scidb::db::get {} }
	catch { rename ::scidb::db::count {} }
	catch { rename ::scidb::test::broadcast::realDbGet ::scidb::db::get }
	catch { rename ::scidb::test::broadcast::realDbCount ::scidb::db::count }
}

# A round of a broadcast as the API answers it: two games, each with its
# own Lichess id in the Site tag.
proc ::scidb::test::broadcast::roundPgn {ids} {
	set pgn ""
	foreach id $ids {
		append pgn "\[Event \"Broadcast round\"\]\n"
		append pgn "\[Site \"https://lichess.org/broadcast/tournamentSlug/roundSlug/roundId/$id\"\]\n"
		append pgn "\[Date \"2026.10.23\"\]\n"
		append pgn "\[White \"player-$id\"\]\n"
		append pgn "\[Black \"opponent-$id\"\]\n"
		append pgn "\[Result \"1-0\"\]\n"
		append pgn "\n1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 1-0\n\n"
	}
	return $pgn
}

# A round whose games have no game id: the Site tag is the round URL.
proc ::scidb::test::broadcast::roundPgnWithoutIds {} {
	set pgn ""
	foreach n {1 2} {
		append pgn "\[Event \"Broadcast round\"\]\n"
		append pgn "\[Site \"https://lichess.org/broadcast/tournamentSlug/roundSlug/roundId\"\]\n"
		append pgn "\[Date \"2026.10.23\"\]\n"
		append pgn "\[Round \"1\"\]\n"
		append pgn "\[White \"player$n\"\]\n"
		append pgn "\[Black \"opponent$n\"\]\n"
		append pgn "\[Result \"1-0\"\]\n"
		append pgn "\n1. e4 e5 2. Nf3 Nc6 1-0\n\n"
	}
	return $pgn
}

# A round as the API of a tournament answers it: the Site tag is the place
# of the game and the GameURL tag has the game id. The database keeps the
# round, the players and the date, but not the id.
proc ::scidb::test::broadcast::roundPgnWithPlaces {ids} {
	set pgn ""
	foreach id $ids {
		append pgn "\[Event \"Broadcast round\"\]\n"
		append pgn "\[Site \"Daqing, China\"\]\n"
		append pgn "\[Date \"2026.10.23\"\]\n"
		append pgn "\[Round \"6.1\"\]\n"
		append pgn "\[White \"player-$id\"\]\n"
		append pgn "\[Black \"opponent-$id\"\]\n"
		append pgn "\[Result \"1-0\"\]\n"
		append pgn "\[BroadcastURL \"https://lichess.org/broadcast/2026/round-6/h1AnAjoy\"\]\n"
		append pgn "\[GameURL \"https://lichess.org/broadcast/2026/round-6/h1AnAjoy/$id\"\]\n"
		append pgn "\n1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 1-0\n\n"
	}
	return $pgn
}

# The games of a database with the tags that the database keeps.
proc ::scidb::test::broadcast::dbGames {ids} {
	set games {}
	foreach id $ids {
		lappend games [list \
			[list Event "Broadcast round"] \
			[list Round 6.1] \
			[list White "player-$id"] \
			[list Black "opponent-$id"] \
			[list Date 2026.10.23]]
	}
	return $games
}

# ----------------------------------------------------------------------
# The pure helpers.
# ----------------------------------------------------------------------

tcltest::test broadcast-spec-round {a round URL is read} -body {
	set spec [::application::download::broadcastSpec \
		"https://lichess.org/broadcast/tournamentSlug/roundSlug/roundId"]
	list [dict get $spec kind] [dict get $spec round] [dict get $spec tournament]
} -result {round roundId tournamentSlug}

tcltest::test broadcast-spec-round-without-scheme {the scheme and www are optional} -body {
	set spec [::application::download::broadcastSpec \
		"lichess.org/broadcast/tournamentSlug/roundSlug/roundId"]
	list [dict get $spec kind] [dict get $spec round]
} -result {round roundId}

tcltest::test broadcast-spec-tournament {a tournament URL is read} -body {
	set spec [::application::download::broadcastSpec "https://lichess.org/broadcast/tournamentId"]
	list [dict get $spec kind] [dict get $spec tournament]
} -result {tournament tournamentId}

tcltest::test broadcast-spec-bare-id {a bare id may be a round or a tournament} -body {
	set spec [::application::download::broadcastSpec "kTc9bC3r"]
	list [dict get $spec kind] [dict get $spec id]
} -result {auto kTc9bC3r}

tcltest::test broadcast-spec-nothing {no broadcast is no spec} -body {
	list [::application::download::broadcastSpec ""] \
		[::application::download::broadcastSpec "   "] \
		[::application::download::broadcastSpec "https://example.com/broadcast/a/b/c"] \
		[::application::download::broadcastSpec "https://lichess.org/abcdefgh"] \
		[::application::download::broadcastSpec "not an id!"]
} -result {{} {} {} {} {}}

tcltest::test broadcast-urls {the PGN URLs of the API are built} -body {
	set round [::application::download::broadcastUrls \
		[::application::download::broadcastSpec \
			"https://lichess.org/broadcast/tournamentSlug/roundSlug/roundId"]]
	set tour [::application::download::broadcastUrls \
		[::application::download::broadcastSpec "https://lichess.org/broadcast/tournamentId"]]
	set auto [::application::download::broadcastUrls \
		[::application::download::broadcastSpec "kTc9bC3r"]]
	list [llength $round] [lindex $round 0] \
		[llength $tour] [lindex $tour 0] \
		[llength $auto] [lindex $auto 0] [lindex $auto 1]
} -result {1 https://lichess.org/api/broadcast/round/roundId.pgn 1 https://lichess.org/api/broadcast/tournamentId.pgn 2 https://lichess.org/api/broadcast/round/kTc9bC3r.pgn https://lichess.org/api/broadcast/kTc9bC3r.pgn}

tcltest::test broadcast-game-id {the game id is read from the Site tag} -body {
	list [::application::download::broadcastGameId "https://lichess.org/AbCdEf12" ""] \
		[::application::download::broadcastGameId "https://lichess.org/game/export/AbCdEf12" ""] \
		[::application::download::broadcastGameId \
			"https://lichess.org/broadcast/t/r/roundId/AbCdEf12" "roundId"] \
		[::application::download::broadcastGameId \
			"https://lichess.org/broadcast/t/r/roundId" "roundId"] \
		[::application::download::broadcastGameId "Bilbao ESP" ""]
} -result {AbCdEf12 AbCdEf12 AbCdEf12 {} {}}

tcltest::test broadcast-round-of {the round id is read from the Site tag} -body {
	list [::application::download::broadcastRoundOf \
			"https://lichess.org/broadcast/t/roundId"] \
		[::application::download::broadcastRoundOf \
			"https://lichess.org/broadcast/t/roundSlug/roundId"] \
		[::application::download::broadcastRoundOf \
			"https://lichess.org/broadcast/t/roundSlug/roundId/AbCdEf12"] \
		[::application::download::broadcastRoundOf "https://lichess.org/AbCdEf12"]
} -result {roundId roundId roundId {}}

tcltest::test broadcast-key {the games of a round are told apart} -body {
	# the game's own Lichess id
	set id [::application::download::broadcastKey \
		[dict create Site "https://lichess.org/broadcast/t/r/roundId/AbCdEf12"] "roundId"]
	# the round and the board
	set board [::application::download::broadcastKey \
		[dict create Site "https://lichess.org/broadcast/t/r/roundId" Round 1 Board 2] "roundId"]
	# the round and the players
	set players [::application::download::broadcastKey \
		[dict create White alice Black bob Date "2026.10.23"] "roundId"]
	# nothing to tell it apart by
	set none [::application::download::broadcastKey [dict create Result "1-0"] "roundId"]
	list $id $board $players $none
} -result {lichess:AbCdEf12 {board {} {} 1 2} {players {} 2026.10.23 roundId alice bob} {}}

tcltest::test broadcast-keys {a game has a key for every way to tell it apart} -body {
	set tags [dict create \
		Site "https://lichess.org/broadcast/t/r/roundId/AbCdEf12" \
		Round 6.1 Board 2 White alice Black bob Date "2026.10.23"]
	::application::download::broadcastKeys $tags "roundId"
} -result {lichess:AbCdEf12 {board {} 2026.10.23 6.1 2} {players {} 2026.10.23 6.1 alice bob}}

tcltest::test broadcast-key-round {the round of the game is its own round} -body {
	# the round of the game tells it apart; the round of the broadcast is
	# only the fallback
	set tags [dict create Round 6.1 White alice Black bob Date "2026.10.23"]
	set noRound [dict create White alice Black bob Date "2026.10.23"]
	list [::application::download::broadcastKey $tags "roundId"] \
		[::application::download::broadcastKey $noRound "roundId"] \
		[::application::download::broadcastKey $noRound ""]
} -result {{players {} 2026.10.23 6.1 alice bob} {players {} 2026.10.23 roundId alice bob} {players {} 2026.10.23 {} alice bob}}

tcltest::test broadcast-key-gameurl {the game url is read when the site is a place} -body {
	set tags [dict create Site "Daqing, China" \
		GameURL "https://lichess.org/broadcast/2026/round-6/h1AnAjoy/4Jkd3TqS" \
		Round "6.1" White "wais ahmad" Black "Chen, Zhongkai" Date "2026.10.23"]
	list [::application::download::broadcastKey $tags "h1AnAjoy"] \
		[::application::download::broadcastRoundOf [dict get $tags GameURL]]
} -result {lichess:4Jkd3TqS h1AnAjoy}

tcltest::test broadcast-games {the games of a PGN text are read} -body {
	set games [::application::download::broadcastGames \
		[::scidb::test::broadcast::roundPgn {AbCdEf12 GhIjKl34}]]
	list [llength $games] \
		[dict get [lindex $games 0] tags White] \
		[dict get [lindex $games 0] body] \
		[dict get [lindex $games 1] tags Black]
} -result {2 player-AbCdEf12 {1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 1-0} opponent-GhIjKl34}

tcltest::test broadcast-game-text {a game is PGN again} -body {
	set games [::application::download::broadcastGames \
		[::scidb::test::broadcast::roundPgn {AbCdEf12}]]
	::application::download::broadcastGameText [lindex $games 0]
} -result "\[Event \"Broadcast round\"\]\n\[Site \"https://lichess.org/broadcast/tournamentSlug/roundSlug/roundId/AbCdEf12\"\]\n\[Date \"2026.10.23\"\]\n\[White \"player-AbCdEf12\"\]\n\[Black \"opponent-AbCdEf12\"\]\n\[Result \"1-0\"\]\n\n1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 1-0\n"

tcltest::test broadcast-new-games {only the games that are not there yet are new} -body {
	set pgn [::scidb::test::broadcast::roundPgn {AbCdEf12 GhIjKl34}]
	lassign [::application::download::broadcastNewGames $pgn {} "roundId"] text keys count
	set known [dict create lichess:AbCdEf12 1]
	lassign [::application::download::broadcastNewGames $pgn $known "roundId"] text2 keys2 count2
	list $count [llength $keys] $count2 [llength $keys2] \
		[string match {*GhIjKl34*} $text] \
		[string match {*AbCdEf12*} $text2] \
		[string match {*AbCdEf12*} $text]
} -result {2 4 1 2 1 0 1}

tcltest::test broadcast-new-games-without-ids {the players tell the games apart} -body {
	set pgn [::scidb::test::broadcast::roundPgnWithoutIds]
	lassign [::application::download::broadcastNewGames $pgn {} "roundId"] text keys count
	lassign [::application::download::broadcastNewGames \
		$pgn [::scidb::test::broadcast::keyDict $keys] "roundId"] text2 keys2 count2
	list $count $keys $count2
} -result {2 {{players {Broadcast round} 2026.10.23 1 player1 opponent1} {players {Broadcast round} 2026.10.23 1 player2 opponent2}} 0}

tcltest::test broadcast-db-keys {the games of the database are read} -setup {
	::scidb::test::broadcast::stubDb \
		[::scidb::test::broadcast::dbGames {AbCdEf12 GhIjKl34}]
} -body {
	lassign [::application::download::broadcastDbKeys test-base h1AnAjoy] keys games
	list $games [dict keys $keys]
} -cleanup {
	::scidb::test::broadcast::unstubDb
} -result {2 {{players {Broadcast round} 2026.10.23 6.1 player-AbCdEf12 opponent-AbCdEf12} {players {Broadcast round} 2026.10.23 6.1 player-GhIjKl34 opponent-GhIjKl34}}}

tcltest::test broadcast-db-dedup {the games of the database are not imported again} -setup {
	::scidb::test::broadcast::captureImport
	::scidb::test::broadcast::stubDb \
		[::scidb::test::broadcast::dbGames {AbCdEf12}]
	::scidb::test::broadcast::stubGet [list \
		[list ok 1 data [::scidb::test::broadcast::roundPgnWithPlaces {AbCdEf12 GhIjKl34}] code 200]]
} -body {
	::scidb::test::broadcast::isolated {
		set ::application::download::Priv(dialog) {}
		set result {}
		::application::download::run test-base \
			{-source broadcast -broadcast https://lichess.org/broadcast/2026/round-6/h1AnAjoy} \
			{apply {{r} {set ::result $r}}}
		list [dict get $result ok] [dict get $result files] \
			[llength $::scidb::test::broadcast::importCalls] \
			[string match {*GhIjKl34*} [::scidb::test::broadcast::importedText 0]] \
			[string match {*AbCdEf12*} [::scidb::test::broadcast::importedText 0]]
	}
} -cleanup {
	::scidb::test::broadcast::unstubGet
	::scidb::test::broadcast::uncaptureImport
	::scidb::test::broadcast::unstubDb
	::scidb::test::broadcast::cleanup
} -result {1 1 1 1 0}

# ----------------------------------------------------------------------
# The dialog: the broadcast is fetched, and only the new games are
# imported.
# ----------------------------------------------------------------------

tcltest::test broadcast-dialog-imports {the round is fetched and imported} -setup {
	::scidb::test::broadcast::captureImport
	::scidb::test::broadcast::stubGet [list \
		[list ok 1 data [::scidb::test::broadcast::roundPgn {AbCdEf12 GhIjKl34}] code 200]]
} -body {
	::scidb::test::broadcast::isolated {
		set dlg [::application::download::open .application test-broadcast-base]
		set ::application::download::Priv(source) broadcast
		set ::application::download::Priv(broadcast) \
			"https://lichess.org/broadcast/tournamentSlug/roundSlug/roundId"
		::application::download::Start
		lassign [lindex $::scidb::test::broadcast::importCalls 0] base files title encoding text
		set result [list $::scidb::test::broadcast::getCalls \
			[lindex $::scidb::test::broadcast::getUrls 0] \
			[llength $files] $title $encoding \
			[string match {*AbCdEf12*} $text] \
			[file exists [file join [::application::download::Dir] lichess-broadcast-roundId.pgn]] \
			[winfo exists $dlg]]
		::application::download::Close
		set result
	}
} -cleanup {
	::scidb::test::broadcast::unstubGet
	::scidb::test::broadcast::uncaptureImport
	::scidb::test::broadcast::cleanup
} -result {1 https://lichess.org/api/broadcast/round/roundId.pgn 1 {Lichess broadcast import} utf-8 1 1 1}

tcltest::test broadcast-refresh-imports-only-new {the refresh imports only the new games} -setup {
	::scidb::test::broadcast::captureImport
	::scidb::test::broadcast::stubGet [list \
		[list ok 1 data [::scidb::test::broadcast::roundPgn {AbCdEf12}] code 200] \
		[list ok 1 data [::scidb::test::broadcast::roundPgn {AbCdEf12 GhIjKl34}] code 200]]
} -body {
	::scidb::test::broadcast::isolated {
		set dlg [::application::download::open .application test-broadcast-base]
		set ::application::download::Priv(source) broadcast
		set ::application::download::Priv(broadcast) \
			"https://lichess.org/broadcast/tournamentSlug/roundSlug/roundId"
		set ::application::download::Priv(refreshOn) 1
		set ::application::download::Priv(refresh) 1
		::application::download::Start
		# the refresh is a timer: it is fired here, without waiting a minute
		set ::application::download::Priv(bcInterval) 1
		::application::download::BroadcastRefresh
		set result [list [llength $::scidb::test::broadcast::importCalls] \
			[string match {*AbCdEf12*} [::scidb::test::broadcast::importedText 0]] \
			[string match {*AbCdEf12*} [::scidb::test::broadcast::importedText 1]] \
			[string match {*GhIjKl34*} [::scidb::test::broadcast::importedText 1]] \
			$::application::download::Priv(bcImported) \
			$::scidb::test::broadcast::getCalls]
		::application::download::Close
		set result
	}
} -cleanup {
	::scidb::test::broadcast::unstubGet
	::scidb::test::broadcast::uncaptureImport
	::scidb::test::broadcast::cleanup
} -result {2 1 0 1 1 2}

tcltest::test broadcast-refresh-timer {the refresh waits for its interval} -setup {
	::scidb::test::broadcast::captureImport
	::scidb::test::broadcast::stubGet [list \
		[list ok 1 data [::scidb::test::broadcast::roundPgn {AbCdEf12}] code 200] \
		[list ok 1 data [::scidb::test::broadcast::roundPgn {AbCdEf12 GhIjKl34}] code 200]]
} -body {
	::scidb::test::broadcast::isolated {
		set dlg [::application::download::open .application test-broadcast-base]
		set ::application::download::Priv(source) broadcast
		set ::application::download::Priv(broadcast) \
			"https://lichess.org/broadcast/tournamentSlug/roundSlug/roundId"
		set ::application::download::Priv(refreshOn) 1
		set ::application::download::Priv(refresh) 1
		::application::download::Start
		set timer $::application::download::Priv(bcTimer)
		# the timer of a minute is replaced by one of a second
		after cancel $timer
		set ::application::download::Priv(bcInterval) 1
		::application::download::ScheduleRefresh
		set calls [::scidb::test::broadcast::waitForCalls 2]
		set result [list [expr {[string length $timer] > 0}] $calls \
			[llength $::scidb::test::broadcast::importCalls] \
			[string match {*GhIjKl34*} [::scidb::test::broadcast::importedText 1]]]
		::application::download::Close
		set result
	}
} -cleanup {
	::scidb::test::broadcast::unstubGet
	::scidb::test::broadcast::uncaptureImport
	::scidb::test::broadcast::cleanup
} -result {1 2 2 1}

tcltest::test broadcast-cancel-stops-refresh {Cancel stops the refresh} -setup {
	::scidb::test::broadcast::captureImport
	::scidb::test::broadcast::stubGet [list \
		[list ok 1 data [::scidb::test::broadcast::roundPgn {AbCdEf12}] code 200]]
} -body {
	::scidb::test::broadcast::isolated {
		set dlg [::application::download::open .application test-broadcast-base]
		set ::application::download::Priv(source) broadcast
		set ::application::download::Priv(broadcast) \
			"https://lichess.org/broadcast/tournamentSlug/roundSlug/roundId"
		set ::application::download::Priv(refreshOn) 1
		set ::application::download::Priv(refresh) 1
		::application::download::Start
		set timer $::application::download::Priv(bcTimer)
		::application::download::Close
		list [expr {[string length $timer] > 0}] \
			[string length $::application::download::Priv(bcTimer)] \
			$::application::download::Priv(bcInterval) \
			$::application::download::Priv(cancel)
	}
} -cleanup {
	::scidb::test::broadcast::unstubGet
	::scidb::test::broadcast::uncaptureImport
	::scidb::test::broadcast::cleanup
} -result {1 0 0 1}

tcltest::test broadcast-run-headless {run() fetches the round and imports it} -setup {
	::scidb::test::broadcast::captureImport
	::scidb::test::broadcast::stubGet [list \
		[list ok 1 data [::scidb::test::broadcast::roundPgn {AbCdEf12 GhIjKl34}] code 200]]
} -body {
	::scidb::test::broadcast::isolated {
		set ::application::download::Priv(dialog) {}
		set result {}
		::application::download::run test-base \
			{-source broadcast -broadcast https://lichess.org/broadcast/tournamentSlug/roundSlug/roundId} \
			{apply {{r} {set ::result $r}}}
		list [dict get $result ok] [dict get $result files] \
			[llength $::scidb::test::broadcast::importCalls] \
			[lindex $::scidb::test::broadcast::importCalls 0 2]
	}
} -cleanup {
	::scidb::test::broadcast::unstubGet
	::scidb::test::broadcast::uncaptureImport
	::scidb::test::broadcast::cleanup
} -result {1 2 1 {Lichess broadcast import}}

tcltest::test broadcast-no-broadcast {an empty broadcast is refused} -body {
	::scidb::test::broadcast::isolated {
		set ::scidb::test::broadcast::importCalls {}
		set ::application::download::Priv(dialog) {}
		::application::download::run test-base {-source broadcast -broadcast ""} \
			{apply {{r} {set ::result $r}}}
		list [llength $::scidb::test::broadcast::importCalls] \
			$::application::download::Priv(bcUrls)
	}
} -cleanup {
	::scidb::test::broadcast::cleanup
} -result {0 {}}

tcltest::test broadcast-invalid-path {unsafe or empty path segments are rejected} -body {
	list [::application::download::broadcastSpec https://lichess.org/broadcast/a/../x] \
		[::application::download::broadcastSpec https://lichess.org/broadcast/a//x]
} -result {{} {}}

tcltest::test broadcast-multiline-body {blank lines in comments preserve one game} -body {
	set pgn [::scidb::test::broadcast::roundPgn {AbCdEf12}]
	set pgn [string map [list {1. e4 e5} "1. e4 {comment\n\ncontinued} e5"] $pgn]
	set games [::application::download::broadcastGames $pgn]
	list [llength $games] [string match {*continued*} [dict get [lindex $games 0] body]]
} -result {1 1}

tcltest::test broadcast-board-event {boards in unrelated events remain distinct} -body {
	set a [dict create Event A Date 2026.10.23 Round 1 Board 1]
	set b [dict replace $a Event B]
	expr {[::application::download::broadcastKey $a] ne [::application::download::broadcastKey $b]}
} -result 1

tcltest::test broadcast-retry {transient failures fetch again before importing} -setup {
	::scidb::test::broadcast::captureImport
	::scidb::test::broadcast::stubGet [list \
		[list ok 0 error busy code 503] \
		[list ok 1 data [::scidb::test::broadcast::roundPgn {AbCdEf12}] code 200]]
	set savedDelay $::application::download::RetryDelay
	set ::application::download::RetryDelay 1
} -body {
	::scidb::test::broadcast::isolated {
		::application::download::run test-base {-source broadcast -broadcast roundId} \
			{apply {{r} {set ::broadcastRetryResult $r}}}
		::scidb::test::broadcast::waitForCalls 2
		list $::scidb::test::broadcast::getCalls [dict get $::broadcastRetryResult ok]
	}
} -cleanup {
	set ::application::download::RetryDelay $savedDelay
	::scidb::test::broadcast::unstubGet
	::scidb::test::broadcast::uncaptureImport
	::scidb::test::broadcast::cleanup
} -result {2 1}

tcltest::test broadcast-other-sources-finish {a non-broadcast download still reaches Done (OnFetched must not depend on the broadcast state)} -body {
	::scidb::test::broadcast::isolated {
		::scidb::test::broadcast::stubGet [list [dict create ok 1 data "\[Event \"x\"\]\n\n1. e4 *\n" code 200]]
		::scidb::test::broadcast::captureImport
		set ::otherResult {}
		::application::download::run test-base {-source url -url https://example.org/games.pgn} \
			{apply {{r} {set ::otherResult $r}}}
		list $::scidb::test::broadcast::getCalls [expr {$::otherResult ne ""}]
	}
} -cleanup {
	::scidb::test::broadcast::unstubGet
	::scidb::test::broadcast::uncaptureImport
	::scidb::test::broadcast::cleanup
} -result {1 1}

tcltest::cleanupTests
