# ======================================================================
# Scidb App Test - engine matches and gauntlets (tcl/engine-match.tcl)
# ======================================================================
# No engine process is started: the tests stub ::enginematch::RequestMove
# (the move-request seam) with per-side queues of UCI moves, answered
# through ::enginematch::GotMove -- the same entry the pipe reader uses.
# Scripting evals works like the playengine tests: the stub plants the
# mover's Priv(eval:<side>) before the move is delivered. Saved games
# land in the Clipbase and are read back through a scratch game slot.
# ======================================================================

package require tcltest 2.5

namespace eval ::scidb::test::em {}


# UCI engine entries in the configured list, and RequestMove replaced by
# per-side queue readers: each turn pops one entry. An entry is a uci
# string or {uci cp}; cp plants the engine's latest score (from its own
# perspective, like an "info ... score cp N" line) before the move lands.
# An empty queue leaves the engine "thinking" silently.
proc ::scidb::test::em::stub {names repliesW repliesB} {
	variable engines

	catch { rename ::scidb::test::em::realRequest {} }
	set engines $::engine::Engines
	set fresh {}
	foreach name $names {
		lappend fresh [dict merge $::engine::EmptyEngine [list \
			Name		$name \
			Command		/bin/true \
			Protocol	{UCI} \
		]]
	}
	set ::engine::Engines $fresh

	proc ::enginematch::RequestMove {side} {
		set queue $::scidb::test::em::replies($side)
		if {![llength $queue]} { return }
		set ::scidb::test::em::replies($side) [lrange $queue 1 end]
		lassign [lindex $queue 0] move cp
		if {$cp ne ""} { set ::enginematch::Priv(eval:$side) [list cp $cp] }
		::enginematch::GotMove $side $move
	}
	array set ::scidb::test::em::replies [list w $repliesW b $repliesB]
}


# The state of the world back to how the test found it: match wrapped
# up, stub lifted, engine list restored, slot released, Clipbase
# emptied, thresholds reset.
proc ::scidb::test::em::unstub {} {
	variable engines

	set pos $::enginematch::Priv(pos)
	catch { ::enginematch::Finish }
	catch { rename ::enginematch::RequestMove {} }
	catch { rename ::scidb::test::em::realRequest ::enginematch::RequestMove }
	if {[info exists engines]} { set ::engine::Engines $engines }
	if {$pos >= 0} {
		catch { ::application::pgn::release $pos }
		catch { ::game::release $pos }
	}
	set ::enginematch::Priv(pos) -1
	array unset ::scidb::test::em::replies
	catch { ::scidb::db::clear $::scidb::clipbaseName Normal }
	update
}


# Games in the Clipbase.
proc ::scidb::test::em::clipCount {} {
	return [::scidb::db::count games $::scidb::clipbaseName Normal]
}


# {pgn termination length} of Clipbase game <index>; a scratch slot
# reads it back.
proc ::scidb::test::em::clipGame {index} {
	set pos 46
	if {[catch { ::scidb::game::query $pos open? } open] || !$open} {
		::scidb::game::new $pos
	}
	::scidb::game::load $pos $::scidb::clipbaseName Normal $index
	set pgn [::scidb::game::toPGN original -position $pos]
	set term [::scidb::game::query $pos termination]
	set len [::scidb::game::query $pos length]
	return [list $pgn $term $len]
}


# Run the event loop until the match wrapped up (running goes 0) or the
# time is out.
proc ::scidb::test::em::pump {{ms 5000}} {
	set end [expr {[clock milliseconds] + $ms}]
	while {$::enginematch::Priv(running) && [clock milliseconds] < $end} {
		set ::scidb::test::em::flag 0
		after 20 {set ::scidb::test::em::flag 1}
		vwait ::scidb::test::em::flag
	}
}


# The local Syzygy test tables (KQvK, KRvK, KPvK), wherever they sit.
proc ::scidb::test::em::syzygyDir {} {
	foreach d [list \
		[file join [file dirname [file normalize [info script]]] data syzygy] \
		[file join [file dirname [file normalize [info script]]] .. data syzygy] \
		[file join [file dirname [file normalize [info script]]] .. .. data syzygy] \
		[file join [file dirname [file normalize [info script]]] .. .. .. data syzygy] \
	] {
		if {[file isdirectory $d]} { return $d }
	}
	return ""
}


# ----------------------------------------------------------------------
# The schedule: colours, openings, gauntlet rounds
# ----------------------------------------------------------------------

tcltest::test em-schedule-match {match: colours alternate, no openings mark -1} -body {
	list \
		[::enginematch::schedule match {A B} 6 0] \
		[::enginematch::schedule match {A B} 2 0] \
		[::enginematch::schedule match {A B} 4 2]
} -result {{{A B -1} {B A -1} {A B -1} {B A -1} {A B -1} {B A -1}} {{A B -1} {B A -1}} {{A B 0} {B A 0} {A B 1} {B A 1}}}

tcltest::test em-schedule-gauntlet {gauntlet: round-robin over the opponents, colours alternate per pairing, openings rotate in pairs} -body {
	list \
		[::enginematch::schedule gauntlet {G O1 O2} 4 2] \
		[::enginematch::schedule gauntlet {G O1} 3 0]
} -result {{{G O1 0} {G O2 0} {O1 G 0} {O2 G 0} {G O1 1} {G O2 1} {O1 G 1} {O2 G 1}} {{G O1 -1} {O1 G -1} {G O1 -1}}}

# ----------------------------------------------------------------------
# The opening suite parser
# ----------------------------------------------------------------------

tcltest::test em-parse-openings {comments, variations, NAGs and the plies cap} -body {
	set text {\
[Event "x"]

1. e4 {best by test} e5 2. Nf3 (2. d4 d5) Nc6 $1 3. Bb5 a6 1-0

[Event "y"]
[White "?"]

1. d4! d5 2. c4 *
}
	list [::enginematch::parsePgnOpenings $text 4] \
		[::enginematch::parsePgnOpenings $text 2] \
		[::enginematch::parsePgnOpenings $text 40]
} -result {{{e4 e5 Nf3 Nc6} {d4 d5 c4}} {{e4 e5} {d4 d5}} {{e4 e5 Nf3 Nc6 Bb5 a6} {d4 d5 c4}}}

tcltest::test em-parse-openings-edge {duplicates, empty games, the missing terminator} -body {
	set text {\
[Event "x"]

1. e4 e5 2. Nf3 *

[Event "y"]

1. e4 e5 2. Nf3 *

[Event "w"]

1. e4 e5 2. Nc3 *

[Event "no moves"]

[Event "z"]

1. c4 c5
}
	# the second game repeats the first and drops out; the third shares a
	# prefix but diverges and stays; the game without moves drops; the
	# last one ends without a terminator
	::enginematch::parsePgnOpenings $text 30
} -result {{e4 e5 Nf3} {e4 e5 Nc3} {c4 c5}}

# ----------------------------------------------------------------------
# Adjudication rules
# ----------------------------------------------------------------------

tcltest::test em-resign-rule {five agreed heavy scores end the game} -body {
	list \
		[::enginematch::resignRule {900 1000 800 5000 10000}] \
		[::enginematch::resignRule {900 900 900 900}] \
		[::enginematch::resignRule {-800 -801 -900 -10000 -800}] \
		[::enginematch::resignRule {900 -900 900 900 900}] \
		[::enginematch::resignRule {0 0 900 900 900 900 900}] \
		[::enginematch::resignRule {}]
} -result {1-0 {} 0-1 {} 1-0 {}}

tcltest::test em-draw-rule {ten flat plies, but only past move 40} -body {
	set flat {0 0 0 0 0 0 0 0 0 0}
	list \
		[::enginematch::drawRule 79 $flat] \
		[::enginematch::drawRule 80 $flat] \
		[::enginematch::drawRule 81 $flat] \
		[::enginematch::drawRule 80 {0 0 0 0 0 0 0 0 0 10}] \
		[::enginematch::drawRule 80 {0 0 0 0 0 0 0 0 0 -9}] \
		[::enginematch::drawRule 80 {0 0 0}] \
		[::enginematch::drawRule 100 {500 0 0 0 0 0 0 0 0 0 0}]
} -result {0 1 1 0 1 0 1}

tcltest::test em-norm-score {scores of the mover, in white's perspective} -body {
	list \
		[::enginematch::NormScore w {cp 30}] \
		[::enginematch::NormScore b {cp 30}] \
		[::enginematch::NormScore b {cp -250}] \
		[::enginematch::NormScore w {mate 3}] \
		[::enginematch::NormScore b {mate -3}] \
		[::enginematch::NormScore b {mate 0}] \
		[::enginematch::NormScore w {}]
} -result {30 -30 250 10000 10000 -10000 0}

tcltest::test em-tb-verdict {tablebase categories as results; cursed and blessed stay draws} -body {
	list \
		[::enginematch::tbVerdict win w] \
		[::enginematch::tbVerdict win b] \
		[::enginematch::tbVerdict loss w] \
		[::enginematch::tbVerdict loss b] \
		[::enginematch::tbVerdict draw w] \
		[::enginematch::tbVerdict cursed-win w] \
		[::enginematch::tbVerdict blessed-loss b] \
		[::enginematch::tbVerdict maybe-win b] \
		[::enginematch::tbVerdict unknown w]
} -result {1-0 0-1 0-1 1-0 1/2-1/2 1/2-1/2 1/2-1/2 {} {}}

# ----------------------------------------------------------------------
# Score, Elo and clock helpers
# ----------------------------------------------------------------------

tcltest::test em-elo {the Elo difference with its error bar} -body {
	set diff [::enginematch::eloDiff 10 10 0]
	set err [::enginematch::eloError 10 10 0]
	list \
		[expr {abs($diff - 190.85) < 0.01}] \
		[expr {abs($err - 52.5) < 0.5}] \
		[::enginematch::eloDiff 0 0 0] \
		[::enginematch::eloError 0 0 0] \
		[::enginematch::eloDiff 5 0 0] \
		[::enginematch::eloDiff 0 0 5] \
		[::enginematch::eloError 5 0 0] \
		[::enginematch::eloText 10 10 0] \
		[::enginematch::eloText 5 0 0] \
		[expr {abs([::enginematch::eloDiff 1 0 2] - -120.41) < 0.01}]
} -result {1 1 {} {} inf -inf {} {+191 ± 52} inf 1}

tcltest::test em-headers-text {TimeControl and Termination tag values} -body {
	list \
		[::enginematch::timeControlText 0 5 2 1000] \
		[::enginematch::timeControlText 1 5 2 1000] \
		[::enginematch::termTag normal] \
		[::enginematch::termTag time] \
		[::enginematch::termTag adjudication] \
		[::enginematch::termTag abandoned] \
		[::enginematch::termTag rulesinfraction]
} -result {300+2 {movetime 1000} Normal TimeForfeit Adjudication Abandoned RulesInfraction}

tcltest::test em-clock {the ledger: elapsed charged, increment granted} -body {
	array set ::enginematch::Priv {noclock 0 increment 2 clock:w 60000 clock:b 60000}
	unset -nocomplain ::enginematch::Priv(seg:w) ::enginematch::Priv(seg:b)
	::enginematch::StartSegment w 100000
	set running [::enginematch::Remaining w 101500]
	set settled [::enginematch::SettleClock w 103000]
	set ::enginematch::Priv(noclock) 1
	set noClock [::enginematch::SettleClock w 200000]
	list $running $settled $::enginematch::Priv(clock:w) $noClock \
		[info exists ::enginematch::Priv(seg:w)]
} -cleanup {
	set ::enginematch::Priv(noclock) 0
	unset -nocomplain ::enginematch::Priv(seg:w) ::enginematch::Priv(seg:b)
} -result {58500 59000 59000 1 0}

# ----------------------------------------------------------------------
# The local tablebase adjudication against the bundled test tables
# ----------------------------------------------------------------------

tcltest::test em-tb-local {local Syzygy verdicts; uncovered positions stay with the engines} -setup {
	set saved [array get ::tablebase::Options]
	set dir [::scidb::test::em::syzygyDir]
	if {$dir eq ""} { error "no syzygy test tables" }
	set ::tablebase::Options(local) $dir
	set ::tablebase::Options(online) 0
} -body {
	list \
		[::enginematch::TbLocal {8/8/8/4k3/8/8/8/4KQ2 w - - 0 1}] \
		[::enginematch::TbLocal {8/8/8/4K3/8/8/8/4kq2 b - - 0 1}] \
		[::enginematch::TbLocal {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}] \
		[::enginematch::TbLocal {8/8/8/4k3/8/8/8/4K3 w - - 0 1}]
} -cleanup {
	array set ::tablebase::Options $saved
} -result {1-0 0-1 {} 1/2-1/2}

# ----------------------------------------------------------------------
# Whole matches with stub engines
# ----------------------------------------------------------------------

tcltest::test em-match-selfplay {an engine can play itself; the second entry is labelled "#2"} -setup {
	set clipBefore [::scidb::test::em::clipCount]
	::scidb::test::em::stub {StubA} \
		{e2e4 d1h5 f1c4 h5f7 e2e4 d1h5 f1c4 h5f7} \
		{e7e5 b8c6 g8f6 e7e5 b8c6 g8f6}
} -body {
	set ok [::enginematch::StartMatch {-engines {StubA StubA} -minutes 5 -increment 2}]
	set engines $::enginematch::Priv(engines)
	::scidb::test::em::pump
	lassign [::scidb::test::em::clipGame $clipBefore] pgn0
	list $ok $engines [expr {[string first {[White "StubA"]} $pgn0] >= 0}] \
		[expr {[string first {[Black "StubA #2"]} $pgn0] >= 0}] [::enginematch::EngineBase {StubA #2}]
} -cleanup {
	::scidb::test::em::unstub
} -result {1 {StubA {StubA #2}} 1 1 StubA}

tcltest::test em-match-mate {a scripted mate ends each game; headers name the engines} -setup {
	set clipBefore [::scidb::test::em::clipCount]
	# two games: the per-side queues hold the Scholar's mate line twice
	::scidb::test::em::stub {StubA StubB} \
		{e2e4 d1h5 f1c4 h5f7 e2e4 d1h5 f1c4 h5f7} \
		{e7e5 b8c6 g8f6 e7e5 b8c6 g8f6}
} -body {
	set ok [::enginematch::StartMatch {-engines {StubA StubB} -minutes 5 -increment 2}]
	::scidb::test::em::pump
	lassign [::scidb::test::em::clipGame $clipBefore] pgn0 term0 len0
	lassign [::scidb::test::em::clipGame [expr {$clipBefore + 1}]] pgn1 term1 len1
	list \
		$ok $::enginematch::Priv(running) \
		[expr {[::scidb::test::em::clipCount] - $clipBefore}] \
		$len0 7 $len1 7 \
		[expr {[string first {[Event "Engine match"]} $pgn0] >= 0}] \
		[expr {[string first {[White "StubA"]} $pgn0] >= 0}] \
		[expr {[string first {[Black "StubB"]} $pgn0] >= 0}] \
		[expr {[string first {[Result "1-0"]} $pgn0] >= 0}] \
		[expr {[string first {[TimeControl "300+2"]} $pgn0] >= 0}] \
		[string match {*Qxf7*} $pgn0] \
		[expr {[string first {[White "StubB"]} $pgn1] >= 0}] \
		[expr {[string first {[Black "StubA"]} $pgn1] >= 0}] \
		$term0 $term1 \
		[::enginematch::ScoreOf StubA] [::enginematch::ScoreOf StubB] \
		[::enginematch::eloText 1 0 1]
} -cleanup {
	::scidb::test::em::unstub
} -result {1 0 2 7 7 7 7 1 1 1 1 1 1 1 1 Normal Normal {1 0 1} {1 0 1} {+0 ± 306}}

tcltest::test em-draw-adjudicated {flat scores in a long game end it early} -setup {
	::scidb::test::em::stub {StubA StubB} {e2e4 d2d4 g1f3 b1c3} {e7e5 d7d5 b8c6 g8f6}
	set savedMinMove $::enginematch::DrawMinMove
	set savedPlies $::enginematch::DrawPlies
	set ::enginematch::DrawMinMove 2
	set ::enginematch::DrawPlies 4
} -body {
	set clipBefore [::scidb::test::em::clipCount]
	::enginematch::StartMatch {-engines {StubA StubB} -games 2 -minutes 0 -movetime 500}
	::scidb::test::em::pump
	lassign [::scidb::test::em::clipGame $clipBefore] pgn term len
	list $len \
		[expr {[string first {[Result "1/2-1/2"]} $pgn] >= 0}] \
		[expr {[string first {[TimeControl "movetime 500"]} $pgn] >= 0}] \
		$term \
		[::enginematch::ScoreOf StubA] \
		[expr {[::scidb::test::em::clipCount] - $clipBefore}]
} -cleanup {
	set ::enginematch::DrawMinMove $savedMinMove
	set ::enginematch::DrawPlies $savedPlies
	::scidb::test::em::unstub
} -result {4 1 1 Adjudication {0 2 0} 2}

tcltest::test em-resign-adjudicated {both engines agree on a heavy score} -setup {
	::scidb::test::em::stub {StubA StubB} \
		{{e2e4 900} {d2d4 950} {g1f3 900} {e2e4 900} {d2d4 950} {g1f3 900}} \
		{{e7e5 -900} {d7d5 -1200} {e7e5 -900} {d7d5 -1200}}
	set savedPlies $::enginematch::ResignPlies
	set ::enginematch::ResignPlies 3
} -body {
	set clipBefore [::scidb::test::em::clipCount]
	::enginematch::StartMatch {-engines {StubA StubB} -games 2 -minutes 0 -movetime 500}
	::scidb::test::em::pump
	lassign [::scidb::test::em::clipGame $clipBefore] pgn term len
	list $len \
		[expr {[string first {[Result "1-0"]} $pgn] >= 0}] \
		$term \
		[::enginematch::ScoreOf StubA] [::enginematch::ScoreOf StubB]
} -cleanup {
	set ::enginematch::ResignPlies $savedPlies
	::scidb::test::em::unstub
} -result {3 1 Adjudication {1 0 1} {1 0 1}}

tcltest::test em-match-suite {the suite's openings seed the games, both colours per opening} -setup {
	# four games, each: the suite's two plies, then Nf3 Nc6
	::scidb::test::em::stub {StubA StubB} \
		{g1f3 g1f3 g1f3 g1f3} {b8c6 b8c6 b8c6 b8c6}
	set savedMinMove $::enginematch::DrawMinMove
	set savedPlies $::enginematch::DrawPlies
	set ::enginematch::DrawMinMove 2
	set ::enginematch::DrawPlies 2
	set suiteDir [file join [file dirname [file normalize [info script]]] tmp-app]
	file mkdir $suiteDir
	set suiteFile [file join $suiteDir em-suite-[pid].pgn]
	set chan [open $suiteFile w]
	puts $chan {[Event "suite"]}
	puts $chan {1. e4 e5 *}
	puts $chan {}
	puts $chan {[Event "suite"]}
	puts $chan {1. d4 d5 *}
	close $chan
} -body {
	set clipBefore [::scidb::test::em::clipCount]
	set ok [::enginematch::StartMatch [list \
		-engines {StubA StubB} -games 4 -minutes 0 -movetime 500 \
		-suite $suiteFile -suitePlies 2]]
	::scidb::test::em::pump
	lassign [::scidb::test::em::clipGame $clipBefore] pgn0
	lassign [::scidb::test::em::clipGame [expr {$clipBefore + 1}]] pgn1
	lassign [::scidb::test::em::clipGame [expr {$clipBefore + 2}]] pgn2
	list $ok $::enginematch::Priv(running) \
		[expr {[::scidb::test::em::clipCount] - $clipBefore}] \
		[string match {*e4 e5*Nf3 Nc6*} $pgn0] \
		[string match {*e4 e5*Nf3 Nc6*} $pgn1] \
		[string match {*d4 d5*Nf3 Nc6*} $pgn2] \
		[expr {[string first {[White "StubA"]} $pgn0] >= 0}] \
		[expr {[string first {[White "StubB"]} $pgn1] >= 0}] \
		[expr {[string first {[White "StubA"]} $pgn2] >= 0}]
} -cleanup {
	set ::enginematch::DrawMinMove $savedMinMove
	set ::enginematch::DrawPlies $savedPlies
	catch { file delete -force $suiteFile }
	::scidb::test::em::unstub
} -result {1 0 4 1 1 1 1 1 1}

tcltest::test em-gauntlet {the champion plays everyone, once with each colour} -setup {
	# four games, each a Scholar's mate
	::scidb::test::em::stub {G O1 O2} \
		{e2e4 d1h5 f1c4 h5f7 e2e4 d1h5 f1c4 h5f7 e2e4 d1h5 f1c4 h5f7 e2e4 d1h5 f1c4 h5f7} \
		{e7e5 b8c6 g8f6 e7e5 b8c6 g8f6 e7e5 b8c6 g8f6 e7e5 b8c6 g8f6}
} -body {
	set clipBefore [::scidb::test::em::clipCount]
	set ok [::enginematch::StartMatch {-mode gauntlet -engines {G O1 O2} -games 2 -minutes 0 -movetime 500}]
	::scidb::test::em::pump
	list $ok $::enginematch::Priv(running) \
		[expr {[::scidb::test::em::clipCount] - $clipBefore}] \
		[::enginematch::ScoreOf G] [::enginematch::ScoreOf O1] [::enginematch::ScoreOf O2] \
		[llength $::enginematch::Priv(schedule)]
} -cleanup {
	::scidb::test::em::unstub
} -result {1 0 4 {2 0 2} {1 0 1} {1 0 1} 4}

tcltest::test em-stop {a silent engine keeps the game pending; Stop wraps the match up} -setup {
	::scidb::test::em::stub {StubA StubB} {} {}
} -body {
	set clipBefore [::scidb::test::em::clipCount]
	::enginematch::StartMatch {-engines {StubA StubB} -games 2 -minutes 0 -movetime 500}
	set mid [list $::enginematch::Priv(running) $::enginematch::Priv(phase) \
		$::enginematch::Priv(side) [::scidb::game::query length]]
	::enginematch::Stop
	list $mid $::enginematch::Priv(running) \
		[expr {[::scidb::test::em::clipCount] - $clipBefore}]
} -cleanup {
	::scidb::test::em::unstub
} -result {{1 play w 0} 0 0}

tcltest::test em-specs-rejected {unknown engines and half a pairing are refused} -setup {
	::scidb::test::em::stub {StubA StubB} {} {}
} -body {
	list \
		[catch { ::enginematch::StartMatch {-engines {NoSuch StubB}} } err] \
		[catch { ::enginematch::StartMatch {-engines {StubA}} }] \
		[catch { ::enginematch::StartMatch {-mode nonsense -engines {StubA StubB}} }] \
		$::enginematch::Priv(running)
} -cleanup {
	::scidb::test::em::unstub
} -result {1 1 1 0}

# ----------------------------------------------------------------------
# The dialog
# ----------------------------------------------------------------------

tcltest::test em-dialog {the dialog lists the engines; the run panel holds the table} -setup {
	::scidb::test::em::stub {StubA StubB} {} {}
} -body {
	set dlg [::enginematch::open .application]
	update
	set e1 [[::util::place::playingBody $dlg].top.setup.picker.e1.engine cget -values]
	set bases [::enginematch::BaseList]
	# switch to the gauntlet picker and back
	set ::enginematch::Priv(dlg:mode) gauntlet
	::enginematch::ModeChanged
	update
	set opps [winfo exists [::util::place::playingBody $dlg].top.setup.picker.opps.list]
	set oppList [expr {$opps ? [[::util::place::playingBody $dlg].top.setup.picker.opps.list get 0 end] : {}}]
	set ::enginematch::Priv(dlg:mode) match
	::enginematch::ModeChanged
	update
	# start a silent match through the dialog Start, then stop it
	[::util::place::playingBody $dlg].ok invoke
	update
	set running $::enginematch::Priv(running)
	set panel [expr {[winfo manager [::util::place::playingBody $dlg].top.run] eq "pack"}]
	set okText [[::util::place::playingBody $dlg].ok cget -text]
	::enginematch::Stop
	set stopText [[::util::place::playingBody $dlg].ok cget -text]
	::enginematch::Close
	set hasClipbase [expr {[lsearch -exact $bases $::scidb::clipbaseName] >= 0}]
	list $e1 [::util::place::playingBody $dlg].top.run.table $hasClipbase $opps $oppList \
		$running $panel $okText $stopText [winfo exists $dlg]
} -cleanup {
	catch { ::enginematch::Close }
	::scidb::test::em::unstub
} -result {{StubA StubB} .application.enginematch.__viewport.canvas.body.top.run.table 1 1 StubB 1 1 Pause {New Match} 0}

tcltest::test em-pipe-open {Connect opens the engine pipe with the global open} -body {
	regexp {\[::open "\|} [info body ::enginematch::Connect]
} -result 1

tcltest::cleanupTests
