# ======================================================================
# Scidb App Test Suite - plain-language search (tcl/ai-search.tcl)
# ======================================================================
# A request becomes the search_games fields plus a pattern id; no model
# writes query text or CQL. Covers the deterministic extraction, the model
# (stub provider) and classifier (stubbed ::ai::decide) stages, every CQL
# template of the pattern library against purpose-built games, and the
# whole path into the main game list.
# ======================================================================
package require Tcl 8.5
package require tcltest 2.5
namespace eval ::scidb::test::nls {
	variable testDir [file dirname [file normalize [info script]]]
	variable Fixture [file join $testDir tmp-app nlsearch-[pid].pgn]
	# game index -> what it contains
	variable Games {
		{} 0-1 {1. f3 e5 2. g4 Qh4# 0-1}
		{} 1-0 {1. e4 c6 2. d4 d5 3. Nc3 dxe4 4. Nxe4 Nd7 5. Qe2 Ngf6 6. Nd6# 1-0}
		{} 1/2-1/2 {1. e4 e5 2. Nf3 Nc6 1/2-1/2}
		{} 1/2-1/2 {1. e4 Nf6 2. e5 d5 3. exd6 exd6 4. Nf3 Be7 5. Bc4 O-O 6. O-O 1/2-1/2}
		{8/P7/8/8/8/8/k7/4K3 w - - 0 1} * {1. a8=N Kb3 *}
		{4k2r/8/8/8/8/8/8/R3K3 w - - 0 1} * {1. Ra8+ Kd7 *}
		{4k3/4p3/8/8/8/8/4P3/4K3 w - - 0 1} * {1. e4 e5 *}
		{} * {1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. O-O d6 5. d3 Be6 6. Nc3 Qd7 7. Be3 O-O-O *}
		{k7/8/2K5/8/8/8/8/1Q6 w - - 0 1} 1/2-1/2 {1. Qb6 1/2-1/2}
		{4k3/8/8/8/4N3/8/8/4RK2 w - - 0 1} * {1. Nd6+ Kd7 *}
	}
}
proc ::scidb::test::nls::nop {args} { return 0 }
proc ::scidb::test::nls::openFixture {} {
	variable Fixture
	variable Games
	file mkdir [file dirname $Fixture]
	set fh [open $Fixture w]
	fconfigure $fh -encoding utf-8
	set n 0
	foreach {fen result moves} $Games {
		incr n
		puts $fh "\[Event \"NLS\"\]\n\[Site \"X\"\]\n\[Date \"2020.01.01\"\]\n\[Round \"$n\"\]"
		puts $fh "\[White \"W$n\"\]\n\[Black \"B$n\"\]\n\[Result \"$result\"\]"
		if {$fen ne ""} { puts $fh "\[SetUp \"1\"\]\n\[FEN \"$fen\"\]" }
		puts $fh "\n$moves\n"
	}
	close $fh
	::scidb::db::open $Fixture ::scidb::test::nls::nop {} ::scidb::test::nls::nop {}
}
proc ::scidb::test::nls::closeFixture {} {
	variable Fixture
	catch { ::scidb::db::close $Fixture }
	catch { file delete $Fixture }
}
# interpret synchronously
proc ::scidb::test::nls::interpret {request args} {
	variable Result
	unset -nocomplain Result
	::ai::search::interpret $request {set ::scidb::test::nls::Result} {*}$args
	set timer [after 5000 {set ::scidb::test::nls::Result timeout}]
	vwait ::scidb::test::nls::Result
	after cancel $timer
	return $Result
}
# the given (non-empty) criteria, the pattern and the sources, compactly
proc ::scidb::test::nls::brief {interpretation} {
	list [dict filter [dict get $interpretation criteria] value ?*] \
		[dict get $interpretation pattern] [dict get $interpretation sources]
}
::scidb::test::nls::openFixture


# --- the pattern library ------------------------------------------------------

tcltest::test nls-patterns {every legacy template finds exactly its games} -body {
	set f $::scidb::test::nls::Fixture
	lmap id [::ai::search::patternIds] {
		# the CQL 6.2-only patterns: tests/test_app_pattern_library.tcl
		if {[dict get [::ai::search::pattern $id] cql] eq ""} continue
		list $id [::scidb::cql::search $f Normal [dict get [::ai::search::pattern $id] cql]]
	}
} -result {{checkmate {0 1}} {smothered_mate 1} {stalemate 8} {en_passant 3} {underpromotion 4} {double_check 9} {opposite_castling 7} {rook_endgame 5} {pawn_endgame {4 6}} {endgame {4 5 6 8 9}} {isolated_queen_pawn {}} {opposite_bishops {}} {queenless {}}}

tcltest::test nls-schema {the assistant's pattern enum is the library} -body {
	set schema [lindex [dict get $::application::assistant::Actions search_games] 4]
	regexp {"pattern":\{"type":"string","enum":\[([^\]]*)\]} $schema -> ids
	expr {[split [string map {\" ""} $ids] ,] eq [::ai::search::patternIds]}
} -result 1


# --- deterministic extraction ---------------------------------------------------

tcltest::test nls-extract {years, results, colours, ECO, Elo and patterns come from the words} -body {
	lmap request {
		{Carlsen's losses as Black in B90-B99 since 2015}
		{smothered mates in games rated 2500+}
		{white wins between 2010 and 2012 with en passant}
		{draws in 2019}
		{rook endings before 2000 above 2600}
		{games with an underpromotion}
		{Kasparov's wins with the white pieces}
	} { ::scidb::test::nls::brief [::ai::search::extract $request] }
} -result {{{color black result loss eco B90-B99 from 2015} {} {from text result text color text eco text}} {{min_elo 2500} smothered_mate {min_elo text pattern text}} {{result 1-0 from 2010 to 2012} en_passant {from text to text result text pattern text}} {{result draw from 2019 to 2019} {} {from text to text result text}} {{to 1999 min_elo 2600} rook_endgame {to text min_elo text pattern text}} {{} underpromotion {pattern text}} {{color white result win} {} {result text color text}}}


# --- interpretation ---------------------------------------------------------------

tcltest::test nls-interpret-plain {without a model or a classifier the words alone answer} -body {
	list [::scidb::test::nls::brief [::scidb::test::nls::interpret {draws since 2015} -model 0 -classifier 0]] \
		[::scidb::test::nls::brief [::scidb::test::nls::interpret {losses as black} -model 0 -classifier 0]]
} -result {{{result 1/2-1/2 from 2015} {} {from text result text}} {{} {} {}}}

proc ::scidb::test::nls::withStub {replies body} {
	set saved [array get ::ai::provider::Config]
	::ai::provider::configure -name stub -responses $replies
	set rc [catch {uplevel 1 $body} result opts]
	array set ::ai::provider::Config $saved
	return -options $opts $result
}

tcltest::test nls-interpret-model {model fields are validated; an unknown pattern is dropped} -body {
	::scidb::test::nls::withStub [list \
		{{"player":"Carlsen","color":"black","result":"loss","eco":"B90-B99","from":"2015","pattern":""}} \
		{Sure! {"player":"Kasparov","from":"yesterday","pattern":"windmill"}} \
		{{"pattern":"smothered_mate"}} \
		{not json at all}] {
		lmap request {
			{Carlsen's losses as Black in the Najdorf since 2015}
			{Kasparov's windmills}
			{knight mates with the king boxed in}
			{Carlsen's wins}
		} { ::scidb::test::nls::brief [::scidb::test::nls::interpret $request -classifier 0] }
	}
} -result {{{player Carlsen color black result loss eco B90-B99 from 2015} {} {from model result model color model player model eco model}} {{player Kasparov} {} {player model}} {{} smothered_mate {pattern model}} {{} {} {}}}

tcltest::test nls-positional {a position no library pattern covers comes back as words for the finder} -body {
	::scidb::test::nls::withStub [list \
		{{"player":"Kasparov","pattern":"","positional":"windmill of discovered checks"}} \
		{{"pattern":"smothered_mate","positional":"smothered mate"}}] {
		lmap request {
			{Kasparov's windmills}
			{smothered mates}
		} {
			set i [::scidb::test::nls::interpret $request -classifier 0]
			list [dict get $i positional] [dict get $i pattern] [expr {[dict exists $i sources positional] ? [dict get $i sources positional] : ""}]
		}
	}
} -result {{{windmill of discovered checks} {} model} {{} smothered_mate {}}}

tcltest::test nls-find-positions {Find Positions hands the position and the fields to the assistant} -setup {
	set dlg .__nls_handoff__
	array set ::application::database::PlainSearchData [list $dlg,file /x/base.sci $dlg,variant Normal \
		$dlg,positional {Greek gift bishop sacrifice on h7}]
	foreach key $::application::database::PlainSearchFields {
		set ::application::database::PlainSearchData($dlg,$key) ""
	}
	set ::application::database::PlainSearchData($dlg,player) Kasparov
	set ::application::database::PlainSearchData($dlg,color) white
	foreach cmd {::application::ai::cloudReady ::application::database::switchToBase
			::application::assistant::show ::application::assistant::ask} {
		rename $cmd ${cmd}__saved
	}
	proc ::application::ai::cloudReady {args} { return 1 }
	proc ::application::database::switchToBase {file} { lappend ::scidb::test::nls::Handoff base $file }
	proc ::application::assistant::show {} { lappend ::scidb::test::nls::Handoff show }
	proc ::application::assistant::ask {request args} { lappend ::scidb::test::nls::Handoff ask $request }
	set ::scidb::test::nls::Handoff {}
} -body {
	::application::database::PlainFindPositions $dlg
	set ::scidb::test::nls::Handoff
} -cleanup {
	foreach cmd {::application::ai::cloudReady ::application::database::switchToBase
			::application::assistant::show ::application::assistant::ask} {
		rename $cmd {}
		rename ${cmd}__saved $cmd
	}
	array unset ::application::database::PlainSearchData $dlg,*
} -result {base /x/base.sci show ask {Find positions in this database: Greek gift bishop sacrifice on h7. Search only the games with these fields: player Kasparov, color white.}}

tcltest::test nls-interpret-classifier {the classifier picks a pattern only when the words named none} -setup {
	set ::scidb::test::nls::SavedDecide [info body ::ai::decide]
	set ::scidb::test::nls::SavedArgs [info args ::ai::decide]
	set ::scidb::test::nls::SavedEnabled [info body ::ai::systemone::enabled]
	proc ::ai::systemone::enabled {} { return 1 }
	proc ::ai::decide {feature state question script args} {
		lappend ::scidb::test::nls::Asked $feature
		after 0 [list {*}$script $::scidb::test::nls::Decision]
	}
} -body {
	set ::scidb::test::nls::Asked {}
	set ::scidb::test::nls::Decision {ok 1 label double_check confidence 0.83 source classifier}
	set a [::scidb::test::nls::brief [::scidb::test::nls::interpret {games where the king is hit twice at once} -model 0]]
	set ::scidb::test::nls::Decision {ok 1 label none confidence 0.9 source classifier}
	set b [::scidb::test::nls::brief [::scidb::test::nls::interpret {games from 2020} -model 0]]
	set ::scidb::test::nls::Decision {ok 1 label {} confidence {} source rules}
	set c [::scidb::test::nls::brief [::scidb::test::nls::interpret {odd games} -model 0]]
	set d [::scidb::test::nls::brief [::scidb::test::nls::interpret {stalemates} -model 0]]
	list $a $b $c $d $::scidb::test::nls::Asked
} -cleanup {
	proc ::ai::decide $::scidb::test::nls::SavedArgs $::scidb::test::nls::SavedDecide
	proc ::ai::systemone::enabled {} $::scidb::test::nls::SavedEnabled
} -result {{{} double_check {pattern {classifier 0.83}}} {{from 2020 to 2020} {} {from text to text}} {{} {} {}} {{} stalemate {pattern text}} {pattern_search pattern_search pattern_search}}


# --- validation, the query, the game list --------------------------------------------

tcltest::test nls-checkargs {search_games takes a pattern alone, refuses an unknown one} -body {
	list [::application::assistant::CheckArgs search_games {pattern en_passant}] \
		[catch {::application::assistant::CheckArgs search_games {pattern windmill}} e] \
		[string match "pattern must be one of: checkmate, *" $e]
} -result {{criteria {player {} color any result {} opponent {} eco {} from {} to {} event {} min_elo {} both_min_elo {} pattern en_passant}} 1 1}

tcltest::test nls-query {the template is the last term of the AND} -body {
	set f $::scidb::test::nls::Fixture
	set c [dict get [::application::assistant::CheckArgs search_games {result 1-0 pattern checkmate}] criteria]
	lassign [::application::assistant::BuildQuery $f Normal $c] query summary
	list [lindex $query 0] [lindex $query 1] [lindex [lindex $query end] 0] $summary
} -result {AND {result 1-0} cql {result 1-0; with checkmate}}

tcltest::test nls-both-min-elo {both players rated at least N, against an average} -body {
	set f $::scidb::test::nls::Fixture
	set c [dict get [::application::assistant::CheckArgs search_games {both_min_elo 2600}] criteria]
	lassign [::application::assistant::BuildQuery $f Normal $c] query summary
	list $query $summary [catch {::application::assistant::CheckArgs search_games {both_min_elo 5000}} e] $e \
		[::scidb::view::search $f Normal 0 null none $query]
} -cleanup {
	::scidb::view::search $::scidb::test::nls::Fixture Normal 0 reset none
} -match glob -result {{rating Elo both 2600-4000 2600-4000} {both players rated at least 2600} 1 {both_min_elo must be a number up to 4000} *}

tcltest::test nls-assistant-gaps {open_game by player, event_report, an annotation range} -body {
	list [::application::assistant::CheckArgs open_game {player carlsen}] \
		[catch {::application::assistant::CheckArgs open_game {}} e] $e \
		[::application::assistant::CheckArgs open_view {kind event_report event Biel}] \
		[catch {::application::assistant::CheckArgs open_view {kind event_report}} e] $e \
		[::application::assistant::CheckArgs annotate_game {from_move 20 to_move 30}] \
		[catch {::application::assistant::CheckArgs annotate_game {from_move 30 to_move 20}} e] $e
} -result {{number {} move {} after {} player carlsen} 1 {give a game number or a player} {kind event_report name {} event Biel} 1 {event_report needs an event} {prose 1 marks 0 depth 12 max_plies 200 from_move 20 to_move 30} 1 {to_move must not be before from_move}}

tcltest::test nls-engine-tools {Stockfish asked directly: arguments, a mate, a blunder} -body {
	set mate {6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1}
	set open {r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3}
	list [::application::assistant::CheckArgs engine_evaluate {}] \
		[catch {::application::assistant::CheckArgs engine_evaluate {lines 9}} e] $e \
		[catch {::application::assistant::CheckArgs engine_check_move {}} e] \
		[string match "*1) #1 1.Ra8*" [::application::assistant::DoEngineEvaluate $mate 1 12]] \
		[string match "*Ng5 is a blunder*best was 3.*" [::application::assistant::DoEngineCheckMove Ng5 $open 12]]
} -result {{fen {} lines 3 depth 18} 1 {lines must be a whole number from 1 to 5} 1 1 1}

tcltest::test nls-tablebase-offline {the tablebase tool: piece limit and the words, without the network} -body {
	list [::application::assistant::DoTablebase {r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3}] \
		[::application::assistant::TablebaseWord loss 1] [::application::assistant::TablebaseWord win] \
		[::application::assistant::TablebaseWord blessed-loss]
} -result {{error: the tablebases cover at most 7 pieces; this position has 32} wins wins {loses, but the 50-move rule saves it (a draw in practice)}}

tcltest::test nls-pane-dock {undock and dock a pane; twice is harmless} -body {
	set out {}
	foreach a {undock undock dock dock} {
		lappend out [::application::assistant::runTool pane [list action $a pane tree]]
		update
	}
	lappend out [catch {::application::assistant::CheckArgs pane {action dock pane nonsense}}]
} -result {{the tree pane is now a separate window} {the tree pane is already a separate window} {the tree pane is docked in the main window} {the tree pane is already docked in the main window} 1}

tcltest::test nls-game-list {an interpretation filters the main game list} -body {
	set f $::scidb::test::nls::Fixture
	set out {}
	foreach request {{white wins by checkmate} {games with a pawn ending} {stalemates}} {
		set i [::scidb::test::nls::interpret $request -model 0 -classifier 0]
		set c [dict get [::application::assistant::CheckArgs search_games [::ai::search::arguments $i]] criteria]
		lassign [::application::assistant::BuildQuery $f Normal $c] query
		::scidb::view::search $f Normal 0 null none $query
		set n [::scidb::view::count games $f Normal 0]
		lappend out [lmap r [lrange {0 1 2 3 4 5 6 7 8 9} 0 $n-1] { ::scidb::db::get gameNumber $f Normal $r 0 }]
	}
	::scidb::view::search $f Normal 0 reset none
	lappend out [::scidb::view::count games $f Normal 0]
} -result {1 {4 6} 8 10}

tcltest::test nls-dialog {the dialog fills its form, searches, and shows all again} -body {
	set f $::scidb::test::nls::Fixture
	set dlg [::application::database::OpenPlainSearch . $f Normal]
	set i [::scidb::test::nls::interpret {white wins by checkmate} -model 0 -classifier 0]
	::application::database::PlainUnderstood $dlg $i
	set form [list $::application::database::PlainSearchData($dlg,result) \
		$::application::database::PlainSearchData($dlg,pattern) \
		$::application::database::PlainSearchData($dlg,pattern,source)]
	::application::database::PlainRun $dlg
	set jobVar ::application::database::PlainSearchData($dlg,job)
	set timeout [after 10000 [list set $jobVar timeout]]
	vwait $jobVar
	after cancel $timeout
	if {[set $jobVar] eq "timeout"} {error "plain-language search timed out"}
	set found [list [::scidb::view::count games $f Normal 0] $::application::database::PlainSearchData($dlg,status)]
	::application::database::PlainShowAll $dlg
	set all [::scidb::view::count games $f Normal 0]
	destroy $dlg
	list $form $found $all [info exists ::application::database::PlainSearchData($dlg,file)]
} -result {{1-0 checkmate (text)} {1 {1 games: result 1-0; with checkmate}} 10 0}

::scidb::test::nls::closeFixture
::tcltest::cleanupTests
