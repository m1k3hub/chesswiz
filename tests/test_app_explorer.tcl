# ======================================================================
# Scidb App Test - online opening explorer
# (tcl/app-explorer.tcl)
# ======================================================================
# The JSON answers below are trimmed copies of real explorer.lichess.ovh
# answers. URL building and JSON parsing are pure; the lookup is driven
# with a stubbed Get and a stubbed Fen (no network, no game needed).
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5
package require json

namespace eval ::scidb::test::explorer {}

# A trimmed Masters answer: three moves and two top games.
set ::scidb::test::explorer::masters {
{"white":1000,"draws":600,"black":400,"moves":[
 {"uci":"e2e4","san":"e4","averageRating":2450,"white":600,"draws":250,"black":150,"game":null},
 {"uci":"d2d4","san":"d4","averageRating":2400,"white":250,"draws":200,"black":150,"game":null},
 {"uci":"g1f3","san":"Nf3","averageRating":2430,"white":150,"draws":150,"black":100,"game":null}],
"topGames":[
 {"uci":"e2e4","id":"abc123","winner":"white",
  "white":{"name":"Kasparov","rating":2850},
  "black":{"name":"Karpov","rating":2750},
  "year":1985,"month":"1985-10"},
 {"uci":"d2d4","id":"def456","winner":"black",
  "white":{"name":"Anand","rating":2790},
  "black":{"name":"Kramnik","rating":2795},
  "year":2008,"month":"2008-10"}]}
}

# A Lichess answer: moves only, no top games.
set ::scidb::test::explorer::lichess {
{"white":500,"draws":300,"black":200,"moves":[
 {"uci":"e2e4","san":"e4","averageRating":1800,"white":300,"draws":150,"black":50}]}
}

set ::scidb::test::explorer::fen {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}

# The lookup is driven against a fixed FEN and a stubbed Get; <results>
# is a list of {ok .. } answers as the stub returns them in turn.
proc ::scidb::test::explorer::stub {results {token abc}} {
	rename ::application::explorer::Fen ::scidb::test::explorer::realFen
	proc ::application::explorer::Fen {} { return $::scidb::test::explorer::fen }
	rename ::application::download::Get ::scidb::test::explorer::realGet
	set ::scidb::test::explorer::getCalls 0
	set ::scidb::test::explorer::getUrls {}
	set ::scidb::test::explorer::getResults $results
	proc ::application::download::Get {url done} {
		incr ::scidb::test::explorer::getCalls
		lappend ::scidb::test::explorer::getUrls $url
		set r [lindex $::scidb::test::explorer::getResults 0]
		if {[llength $::scidb::test::explorer::getResults] > 1} {
			set ::scidb::test::explorer::getResults [lrange $::scidb::test::explorer::getResults 1 end]
		}
		{*}$done $r
	}
	# a bare frame for the pane; Show writes Shown even without children
	set ::application::explorer::Pane [ttk::frame .application.__explorer_pane__]
	set ::application::explorer::Cache [dict create]
	set ::application::explorer::Shown {}
	set ::scidb::test::explorer::savedToken $::application::download::Options(lichess:token)
	set ::application::download::Options(lichess:token) $token
}

proc ::scidb::test::explorer::unstub {} {
	catch { rename ::application::explorer::Fen {} }
	catch { rename ::scidb::test::explorer::realFen ::application::explorer::Fen }
	catch { rename ::application::download::Get {} }
	catch { rename ::scidb::test::explorer::realGet ::application::download::Get }
	catch { destroy .application.__explorer_pane__ }
	set ::application::explorer::Pane {}
	set ::application::download::Options(lichess:token) $::scidb::test::explorer::savedToken
}


tcltest::test explorer-url {masters and lichess URLs carry the fen, speeds and ratings} -body {
	set fen $::scidb::test::explorer::fen
	list \
		[::application::explorer::mastersUrl $fen] \
		[::application::explorer::lichessUrl $fen {blitz rapid} {1600 2000}] \
		[::application::explorer::lichessUrl $fen {} {}] \
		[::application::explorer::url $fen]
} -result [list \
	"https://explorer.lichess.ovh/masters?fen=rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR_w_KQkq_-_0_1" \
	"https://explorer.lichess.ovh/lichess?fen=rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR_w_KQkq_-_0_1&speeds=blitz,rapid&ratings=1600,2000" \
	"https://explorer.lichess.ovh/lichess?fen=rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR_w_KQkq_-_0_1&speeds=blitz,rapid,classical&ratings=1600,1800,2000,2200,2500" \
	"https://explorer.lichess.ovh/masters?fen=rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR_w_KQkq_-_0_1"]

tcltest::test explorer-parse-moves {moves are parsed into san, counts and rating} -body {
	::application::explorer::parseMoves $::scidb::test::explorer::masters
} -result [list \
	{san e4 white 600 draws 250 black 150 games 1000 rating 2450} \
	{san d4 white 250 draws 200 black 150 games 600 rating 2400} \
	{san Nf3 white 150 draws 150 black 100 games 400 rating 2430}]

tcltest::test explorer-rows {rows carry the percentage split} -body {
	::application::explorer::rows $::scidb::test::explorer::masters
} -result [list \
	{e4 1000 60 25 15 2450} \
	{d4 600 42 33 25 2400} \
	{Nf3 400 38 38 24 2430}]

tcltest::test explorer-top-games {top games give the players and year} -body {
	list \
		[::application::explorer::parseTopGames $::scidb::test::explorer::masters] \
		[::application::explorer::parseTopGames $::scidb::test::explorer::lichess]
} -result [list \
	{{Kasparov Karpov 1985} {Anand Kramnik 2008}} {}]

tcltest::test explorer-percent {percentages sum to 100} -body {
	list \
		[::application::explorer::percent 600 250 150] \
		[::application::explorer::percent 1 1 1] \
		[::application::explorer::percent 0 0 0]
} -result {{60 25 15} {33 33 34} {0 0 0}}

# No token: the pane says so and no request is made.
tcltest::test explorer-no-token {without a token the pane says so and does not fetch} -setup {
	::scidb::test::explorer::stub {} {}
} -body {
	::application::explorer::Lookup $::scidb::test::explorer::fen
	list \
		[dict get $::application::explorer::Shown error] \
		$::scidb::test::explorer::getCalls
} -cleanup {
	::scidb::test::explorer::unstub
} -result [list $::application::explorer::mc::NoToken 0]

# A failed request is reported through the status path.
tcltest::test explorer-error {a failed request reports the error} -setup {
	::scidb::test::explorer::stub [list [list ok 0 error {boom} code 500]]
} -body {
	::application::explorer::Lookup $::scidb::test::explorer::fen
	list \
		[dict get $::application::explorer::Shown error] \
		$::scidb::test::explorer::getCalls \
		[string match {https://explorer.lichess.ovh/masters?fen=*} [lindex $::scidb::test::explorer::getUrls 0]]
} -cleanup {
	::scidb::test::explorer::unstub
} -result [list "not available (boom)" 1 1]

# A good answer fills the pane: the move table and the top games.
tcltest::test explorer-lookup {a good answer fills the move table and top games} -setup {
	::scidb::test::explorer::stub [list [list ok 1 data $::scidb::test::explorer::masters code 200]]
	# a real pane so the table rows are visible, not only the Shown state
	destroy .application.__explorer_pane__
	ttk::frame .application.__explorer_pane__
	::application::explorer::build .application.__explorer_pane__ 300 400
	after cancel $::application::explorer::Pending
	set ::application::explorer::Pending {}
} -body {
	::application::explorer::Lookup $::scidb::test::explorer::fen
	set tbl .application.__explorer_pane__.table
	set rows {}
	foreach item [$tbl children {}] {
		lappend rows [list [$tbl item $item -text] [$tbl set $item games] \
			[$tbl set $item white] [$tbl set $item draw] [$tbl set $item black] \
			[$tbl set $item rating]]
	}
	set games [.application.__explorer_pane__.topgames.text get 1.0 end-1c]
	list \
		[dict get $::application::explorer::Shown topGames] \
		$rows \
		$games
} -cleanup {
	::scidb::test::explorer::unstub
	destroy .application.__explorer_pane__
} -result [list \
	{{Kasparov Karpov 1985} {Anand Kramnik 2008}} \
	{{e4 1000 60% 25% 15% 2450} {d4 600 42% 33% 25% 2400} {Nf3 400 38% 38% 24% 2430}} \
	"Kasparov - Karpov  (Year 1985)\nAnand - Kramnik  (Year 2008)\n"]

tcltest::cleanupTests
