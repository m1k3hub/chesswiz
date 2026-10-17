# ======================================================================
# Scidb App Test - repertoire trainer with spaced repetition
# (tcl/repertoire-trainer.tcl)
# ======================================================================
# The scheduler core is pure and driven directly; the card builder walks
# a small game with a variation (built with ::move::addMove); the drill
# is driven through the trainer dialog, answering by the board move
# hook. The deck goes to a scratch home, never to the user's.
# ======================================================================

package require tcltest 2.5

namespace eval ::scidb::test::rep {
	variable Dir [file join [file dirname [file normalize [info script]]] tmp-app reptrainer_[pid]]
}

# Runs <body> with the deck's home (and nothing else of the app state)
# pointing at a scratch directory.
proc ::scidb::test::rep::isolated {body} {
	set home $::scidb::dir::home
	file mkdir $::scidb::test::rep::Dir
	set ::scidb::dir::home $::scidb::test::rep::Dir
	set rc [catch { uplevel 1 $body } result opts]
	set ::scidb::dir::home $home
	if {$rc} { return -options $opts $result }
	return $result
}


proc ::scidb::test::rep::cleanup {} {
	catch { file delete -force $::scidb::test::rep::Dir }
}


proc ::scidb::test::rep::freeGameSlots {} {
	for {set i 0} {$i < [llength $::game::List]} {incr i} {
		catch { ::game::stateChanged $i 0 }
		catch { ::game::lockChanged $i 0 }
	}
}


# 1. e4 e5 2. Nf3 Nc6, and 2. Bc4 as a variation at the position after
# 1. e4 e5. The trainer's cards come out of such a game.
proc ::scidb::test::rep::buildGame {} {
	::scidb::test::rep::freeGameSlots
	::menu::gameNew .application
	update
	set ::move::Options(addVarWithoutAsking) 1
	::move::addMove menu e4
	::move::addMove menu e5
	::move::addMove menu Nf3
	::move::addMove menu Nc6
	::scidb::game::go -2
	::move::addMove menu Bc4
}


# The position keys of the trained side in the built game, taken from the
# game itself (the key is the FEN without the clocks).
proc ::scidb::test::rep::gameKeys {} {
	::scidb::game::go start
	set startKey [::reptrainer::Key [::scidb::pos::fen]]
	::scidb::game::go 2
	set afterKey [::reptrainer::Key [::scidb::pos::fen]]
	::scidb::game::go 1
	set blackKey2 [::reptrainer::Key [::scidb::pos::fen]]
	::scidb::game::go start
	::scidb::game::go 1
	set blackKey1 [::reptrainer::Key [::scidb::pos::fen]]
	return [list $startKey $afterKey $blackKey1 $blackKey2]
}


tcltest::test reptrainer-review {SM-2 intervals for a sequence of grades} -body {
	set card [::reptrainer::newCard {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1} {e4} 1700000000]
	set intervals {}
	set t 1700000000
	foreach grade {2 2 2 3 0 2 2 1} {
		incr t 86400
		set card [::reptrainer::review $card $grade $t]
		lappend intervals [dict get $card interval]
	}
	list $intervals \
		[dict get $card ease] \
		[dict get $card reps] \
		[dict get $card lapses] \
		[expr {[dict get $card due] - [dict get $card reviewed]}] \
		[catch { ::reptrainer::review $card 4 $t } msg] \
		[string match "invalid grade*" $msg]
} -result {{1 6 15 51 0 1 6 7} 214 3 1 604800 1 1}


tcltest::test reptrainer-due {due cards come back most overdue first} -body {
	set now 1700000000
	set day 86400
	set c1 [::reptrainer::newCard {8/8/8/8/8/8/8/8 w - - 0 1} {e4} [expr {$now - 10*$day}]]
	dict set c1 reps 1
	set c2 [::reptrainer::newCard {7/8/8/8/8/8/8/8 w - - 0 1} {d4} [expr {$now - 2*$day}]]
	dict set c2 reps 1
	dict set c2 reviewed $now
	set c3 [::reptrainer::newCard {6/8/8/8/8/8/8/8 w - - 0 1} {Nf3} $now]
	set c4 [::reptrainer::newCard {5/8/8/8/8/8/8/8 w - - 0 1} {c4} [expr {$now + 5*$day}]]
	set cards [list $c4 $c3 $c2 $c1]
	set due [::reptrainer::due $cards $now]
	list \
		[lmap c $due { lindex [dict get $c fen] 0 }] \
		[llength [::reptrainer::due $cards $now 2]] \
		[llength [::reptrainer::due $cards $now 0]] \
		[::reptrainer::counters $cards $now]
} -result {{8/8/8/8/8/8/8/8 7/8/8/8/8/8/8/8 6/8/8/8/8/8/8/8} 2 3 {2 1 1}}


tcltest::test reptrainer-deck {a deck round-trips through its file, written atomically} -body {
	::scidb::test::rep::isolated {
		set fen {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}
		set card [::reptrainer::review [::reptrainer::newCard $fen {e4} 1700000000] 2 1700000864]
		set deck [dict create \
			version 1 \
			source /somewhere/rep.sci \
			side white \
			built 1700000000 \
			cards [dict create [::reptrainer::Key $fen] $card] \
		]
		set file [::reptrainer::deckFile /somewhere/rep.sci]
		::reptrainer::saveDeck $deck $file
		list \
			[string match "*training/rep_sci.deck" $file] \
			[string equal [::reptrainer::loadDeck $file] $deck] \
			[expr {![file exists $file.tmp]}] \
			[dict get [::reptrainer::loadDeck $file] cards [::reptrainer::Key $fen] interval] \
			[::reptrainer::loadDeck [file join [file dirname $file] none.deck]] \
			[::reptrainer::loadDeck [file join [file dirname $file] stale.deck]]
	}
} -cleanup {
	::scidb::test::rep::cleanup
} -result {1 1 1 1 {} {}}


tcltest::test reptrainer-merge {a rebuild keeps the scheduling, drops the stale, spares the other side} -body {
	set now 1700000000
	set f1 {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}
	set f2 {rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e6 0 1}
	set f3 {rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2}

	set old [dict create]
	set c1 [::reptrainer::review [::reptrainer::newCard $f1 {e4} [expr {$now - $::reptrainer::Day}]] 2 [expr {$now - $::reptrainer::Day}]]
	dict set old [::reptrainer::Key $f1] $c1
	set c2 [::reptrainer::review [::reptrainer::newCard $f2 {e5} [expr {$now - $::reptrainer::Day}]] 3 [expr {$now - $::reptrainer::Day}]]
	dict set old [::reptrainer::Key $f2] $c2
	dict set old [::reptrainer::Key $f3] [::reptrainer::newCard $f3 {Nf3} [expr {$now - 2*$::reptrainer::Day}]]

	set new [dict create [::reptrainer::Key $f1] [::reptrainer::newCard $f1 {e4 d4} $now]]
	set merged [::reptrainer::mergeCards $old $new white]
	list \
		[dict size $merged] \
		[dict get $merged [::reptrainer::Key $f1] interval] \
		[dict get $merged [::reptrainer::Key $f1] reps] \
		[dict get $merged [::reptrainer::Key $f1] moves] \
		[dict get $merged [::reptrainer::Key $f1] due] \
		[dict exists $merged [::reptrainer::Key $f3]] \
		[dict get $merged [::reptrainer::Key $f2] interval] \
		[dict get $merged [::reptrainer::Key $f2] moves]
} -result {2 1 1 {e4 d4} 1700000000 0 4 e5}


tcltest::test reptrainer-cards {cards come from the mainline and the variations} -setup {
	set ::scidb::test::rep::addVar $::move::Options(addVarWithoutAsking)
	::scidb::test::rep::buildGame
} -body {
	set white [::reptrainer::buildFromCurrentGame white 1700000000]
	set black [::reptrainer::buildFromCurrentGame black 1700000000]
	lassign [::scidb::test::rep::gameKeys] startKey afterKey blackKey1 blackKey2
	list \
		[dict size $white] \
		[dict get $white $startKey moves] \
		[dict get $white $afterKey moves] \
		[dict get $white $startKey interval] \
		[dict get $white $startKey due] \
		[dict size $black] \
		[dict get $black $blackKey1 moves] \
		[dict get $black $blackKey2 moves] \
		[lrange [dict get $black $blackKey1 fen] 0 1]
} -cleanup {
	set ::move::Options(addVarWithoutAsking) $::scidb::test::rep::addVar
} -result {2 e4 {Nf3 Bc4} 0 1700000000 2 e5 Nc6 {rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b}}


tcltest::test reptrainer-drill {answering right and wrong updates the card} -setup {
	set ::scidb::test::rep::addVar $::move::Options(addVarWithoutAsking)
	set ::scidb::test::rep::delay $::reptrainer::Delay
	set ::reptrainer::Delay 0
} -body {
	::scidb::test::rep::isolated {
		::scidb::test::rep::buildGame
		lassign [::scidb::test::rep::gameKeys] startKey afterKey blackKey1 blackKey2

		::reptrainer::open .application
		update
		set dlg .application.__reptrainer__
		$dlg.setup.start invoke
		update

		# the first card is on the board and the hook owns the moves
		set board1 [lindex [::scidb::pos::fen] 0]
		set active1 [::reptrainer::active]

		# a wrong answer through the board hook: the move never enters
		# the game, the expected move is shown instead
		::move::addMove menu d4
		set shown [lindex [::scidb::pos::fen] 0]
		set state1 $::reptrainer::Vars(state)
		set wrongText $::reptrainer::Vars(instruction)
		update
		;# Delay 0 delivered the next card
		set board2 [lindex [::scidb::pos::fen] 0]
		set active2 [::reptrainer::active]
		set queue1 [llength $::reptrainer::Vars(queue)]

		# the second card answers Nf3 (Bc4 is right too), graded Easy
		::reptrainer::answered Nf3
		set state2 $::reptrainer::Vars(state)
		::reptrainer::grade 3
		update
		# the lapsed first card returns
		set board3 [lindex [::scidb::pos::fen] 0]
		set active3 [::reptrainer::active]

		# e4, graded Good; that was the last card
		::reptrainer::answered e4
		::reptrainer::grade 2

		set c1 [dict get $::reptrainer::Vars(deck) cards $startKey]
		set c2 [dict get $::reptrainer::Vars(deck) cards $afterKey]
		set finished [expr {$::reptrainer::Vars(running) == 0 && ![::reptrainer::active]}]
		set instruction $::reptrainer::Vars(instruction)
		set counter [$dlg.drill.counter cget -text]

		::reptrainer::Close $dlg
		set saved [::reptrainer::loadDeck [::reptrainer::deckFile current-game]]
		# the hook is off again: moves enter the game
		::move::addMove menu e4
		set playing [::scidb::game::position atStart?]

		list \
			$active1 [string match rnbqkbnr/pppppppp/8/8/8/8/* $board1] \
			[string match rnbqkbnr/pppppppp/8/8/4P3/* $shown] $state1 \
			[string match "d4 is not*" $wrongText] \
			[string match rnbqkbnr/pppp1ppp/* $board2] $active2 $queue1 \
			$state2 \
			[string match rnbqkbnr/pppppppp/8/8/8/8/* $board3] $active3 \
			[dict get $c1 interval] [dict get $c1 reps] [dict get $c1 lapses] [dict get $c1 ease] \
			[dict get $c2 interval] [dict get $c2 reps] [dict get $c2 ease] \
			$finished $instruction $counter \
			[string equal [dict get $saved cards] [dict get $::reptrainer::Vars(deck) cards]] \
			$playing
	}
} -cleanup {
	catch { destroy .application.__reptrainer__ }
	set ::reptrainer::Delay $::scidb::test::rep::delay
	set ::move::Options(addVarWithoutAsking) $::scidb::test::rep::addVar
	::scidb::test::rep::cleanup
} -result {1 1 1 show 1 1 1 3 grade 1 1 1 1 1 218 4 1 260 1 {No cards are due. Repertoire training finished.} {due: 0, new: 0, done today: 2} 1 0}


# ----------------------------------------------------------------------
# System One (Jev) decisions in tcl/repertoire-trainer.tcl
# ----------------------------------------------------------------------

namespace eval ::scidb::test::rep {
	variable StubChoice ""
	variable StubConf 0.9
	variable StubOk 1
	variable StubCalls 0
}

proc ::scidb::test::rep::wait {var} {
	set timer [after 3000 [list set $var timeout]]
	vwait $var
	after cancel $timer
	return [set $var]
}

# Runs <body> with ::ai::systemone::evaluate and ::ai::systemone::evaluateAsync
# stubbed in-process (no network), with SCIDB_AI_UNCALIBRATED=1 and backend
# set to typesafe so ::ai::systemone::chooseSync and ::ai::decide run their
# full validation and threshold gates.
proc ::scidb::test::rep::withStubClassifier {body} {
	set savedBackend $::ai::systemone::Config(backend)
	set savedKey $::ai::systemone::Config(apiKey)
	set hadUncal [info exists ::env(SCIDB_AI_UNCALIBRATED)]
	set savedUncal [expr {$hadUncal ? $::env(SCIDB_AI_UNCALIBRATED) : ""}]
	set ::env(SCIDB_AI_UNCALIBRATED) 1
	::ai::systemone::configure -backend typesafe -apiKey stub-key

	rename ::ai::systemone::evaluate ::scidb::test::rep::realEvaluate
	rename ::ai::systemone::evaluateAsync ::scidb::test::rep::realEvaluateAsync

	proc ::ai::systemone::evaluate {state questions} {
		incr ::scidb::test::rep::StubCalls
		if {!$::scidb::test::rep::StubOk} { error "stubbed error" }
		set out {}
		dict for {id _} $questions {
			dict set out $id [dict create \
				type choice \
				choice $::scidb::test::rep::StubChoice \
				confidence $::scidb::test::rep::StubConf]
		}
		return $out
	}

	proc ::ai::systemone::evaluateAsync {state questions script} {
		incr ::scidb::test::rep::StubCalls
		if {!$::scidb::test::rep::StubOk} {
			after 0 [list {*}$script [list ok 0 error "stubbed error"]]
			return
		}
		set out {}
		dict for {id _} $questions {
			dict set out $id [dict create \
				type choice \
				choice $::scidb::test::rep::StubChoice \
				confidence $::scidb::test::rep::StubConf]
		}
		after 0 [list {*}$script [list ok 1 answers $out]]
	}

	set rc [catch { uplevel 1 $body } result opts]

	rename ::ai::systemone::evaluate {}
	rename ::ai::systemone::evaluateAsync {}
	rename ::scidb::test::rep::realEvaluate ::ai::systemone::evaluate
	rename ::scidb::test::rep::realEvaluateAsync ::ai::systemone::evaluateAsync
	::ai::systemone::configure -backend $savedBackend -apiKey $savedKey
	if {$hadUncal} {
		set ::env(SCIDB_AI_UNCALIBRATED) $savedUncal
	} else {
		unset -nocomplain ::env(SCIDB_AI_UNCALIBRATED)
	}
	if {$rc} { return -options $opts $result }
	return $result
}


tcltest::test reptrainer-jev-side {reptrainer_side rules, classifier pick, fallback, and database-type firewall} -body {
	::scidb::test::rep::withStubClassifier {
		# 1. Deterministic rule settles explicit White/Black names without calling the classifier
		set ::scidb::test::rep::StubCalls 0
		set r1 [::reptrainer::sideRule "1.e4 White Repertoire"]
		set r2 [::reptrainer::sideRule "Sicilian Defense for Black"]
		set r3 [::reptrainer::sideRule "White vs Black"]
		set r4 [::reptrainer::sideRule "Caro-Kann Mainline"]
		set rulePick [::reptrainer::inferSide "My Black Repertoire" white]
		set callsAfterRule $::scidb::test::rep::StubCalls

		# 2. High-confidence classifier pick for an ambiguous opening name
		set ::scidb::test::rep::StubChoice black
		set ::scidb::test::rep::StubConf 0.92
		set ::scidb::test::rep::StubOk 1
		set caroPick [::reptrainer::inferSide "Caro-Kann Mainline" white]

		# 3. Low-confidence, unsure, or error falls back to the caller's default
		set ::scidb::test::rep::StubConf 0.45
		set lowConfPick [::reptrainer::inferSide "Caro-Kann Mainline" white]
		set ::scidb::test::rep::StubConf 0.92
		set ::scidb::test::rep::StubChoice unsure
		set unsurePick [::reptrainer::inferSide "Opening Notes" black]
		set ::scidb::test::rep::StubOk 0
		set errPick [::reptrainer::inferSide "Caro-Kann Mainline" white]

		# 4. Firewall: OpeningsWhite / OpeningsBlack database types are authoritative
		# and never overridden by the classifier even if the name or model says otherwise
		set ::scidb::test::rep::StubOk 1
		set ::scidb::test::rep::StubChoice black
		set ::scidb::test::rep::StubConf 0.99
		set callsBeforeFirewall $::scidb::test::rep::StubCalls
		rename ::scidb::db::get ::scidb::test::rep::realDbGet
		proc ::scidb::db::get {what args} {
			if {$what eq "type"} {
				::switch -- [lindex $args 0] {
					/tmp/w.sci { return OpeningsWhite }
					/tmp/b.sci { return OpeningsBlack }
					/tmp/o.sci { return Openings }
				}
			}
			return [::scidb::test::rep::realDbGet $what {*}$args]
		}
		set fwWhite [::reptrainer::DefaultSide /tmp/w.sci]
		set ::scidb::test::rep::StubChoice white
		set fwBlack [::reptrainer::DefaultSide /tmp/b.sci]
		set callsAfterFirewall $::scidb::test::rep::StubCalls
		set ::scidb::test::rep::StubChoice black
		set genericOpenings [::reptrainer::DefaultSide /tmp/o.sci]
		rename ::scidb::db::get {}
		rename ::scidb::test::rep::realDbGet ::scidb::db::get

		list $r1 $r2 $r3 $r4 $rulePick $callsAfterRule \
			$caroPick $lowConfPick $unsurePick $errPick \
			$fwWhite $fwBlack [expr {$callsAfterFirewall == $callsBeforeFirewall}] $genericOpenings
	}
} -result {white black {} {} black 0 black white black white white black 1 black}


tcltest::test reptrainer-jev-note {reptrainer_note rules, classifier roles, spoiler firewall, and drill display} -setup {
	set ::scidb::test::rep::addVar $::move::Options(addVarWithoutAsking)
	set ::scidb::test::rep::delay $::reptrainer::Delay
	set ::reptrainer::Delay 0
	::scidb::test::rep::freeGameSlots
} -body {
	::scidb::test::rep::isolated {
		::scidb::test::rep::withStubClassifier {
			set fen {rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2}
			set moves {Nf3 Bc4}

			# 1. Deterministic rule: empty/clock -> none, engine eval/clock -> noise, prose -> ""
			set nr1 [::reptrainer::noteRule ""]
			set nr2 [::reptrainer::noteRule "\[%clk 0:05:00\]"]
			set nr3 [::reptrainer::noteRule "\[%clk 0:05:00\] +0.34/22 0:12"]
			set nr4 [::reptrainer::noteRule "Develops toward the center"]

			# 2. High-confidence non-spoiling hint is accepted
			set ::scidb::test::rep::StubOk 1
			set ::scidb::test::rep::StubChoice hint
			set ::scidb::test::rep::StubConf 0.91
			set ::scidb::test::rep::NoteRes {}
			::reptrainer::decideNote $fen $moves " Italian / King's Knight branch " \
				{set ::scidb::test::rep::NoteRes}
			set dHint [::scidb::test::rep::wait ::scidb::test::rep::NoteRes]

			# 3. Spoiler firewall: classifier says hint (0.95), but comment names "Nf3"
			# -> clamped to explanation so the move is never spoiled before answering
			set ::scidb::test::rep::StubChoice hint
			set ::scidb::test::rep::StubConf 0.95
			set ::scidb::test::rep::NoteRes {}
			::reptrainer::decideNote $fen $moves "Play Nf3 to attack e5 immediately." \
				{set ::scidb::test::rep::NoteRes}
			set dSpoiler [::scidb::test::rep::wait ::scidb::test::rep::NoteRes]

			# 4. Low confidence falls back to none
			set ::scidb::test::rep::StubChoice hint
			set ::scidb::test::rep::StubConf 0.30
			set ::scidb::test::rep::NoteRes {}
			::reptrainer::decideNote $fen $moves "Italian / King's Knight branch" \
				{set ::scidb::test::rep::NoteRes}
			set dLow [::scidb::test::rep::wait ::scidb::test::rep::NoteRes]

			# 5. Card building extracts comments and drill UI places hint vs explanation
			::scidb::test::rep::buildGame
			::scidb::game::go start
			::scidb::game::go 1
			set e4Key [::scidb::game::position key]
			::scidb::game::update addcomment $e4Key after "Play e4 to claim the center"
			set built [::reptrainer::buildFromCurrentGame white 1700000000]
			lassign [::scidb::test::rep::gameKeys] startKey afterKey
			set cardComment [dict get $built $startKey comment]

			# Drill with classifier returning 'hint' on a spoiler comment ("Play e4..."):
			# firewall downgrades to explanation, so pre-move instruction has no spoiler,
			# and post-answer instruction shows the explanation.
			set ::scidb::test::rep::StubChoice hint
			set ::scidb::test::rep::StubConf 0.95
			::reptrainer::open .application
			update
			set dlg .application.__reptrainer__
			$dlg.setup.start invoke
			update
			# Wait for the async note decision to fire
			after 20 { set ::scidb::test::rep::Tick 1 }
			::scidb::test::rep::wait ::scidb::test::rep::Tick
			set preMovePrompt $::reptrainer::Vars(instruction)

			set ::scidb::test::rep::StubChoice good
			set ::scidb::test::rep::StubConf 0.30
			::reptrainer::answered e4
			set postMovePrompt $::reptrainer::Vars(instruction)
			::reptrainer::Close $dlg

			list $nr1 $nr2 $nr3 $nr4 \
				[dict get $dHint label] [dict get $dHint source] \
				[dict get $dSpoiler label] [dict get $dSpoiler source] \
				[dict get $dLow label] [dict get $dLow source] \
				$cardComment \
				$preMovePrompt \
				$postMovePrompt
		}
	}
} -cleanup {
	catch { destroy .application.__reptrainer__ }
	set ::reptrainer::Delay $::scidb::test::rep::delay
	set ::move::Options(addVarWithoutAsking) $::scidb::test::rep::addVar
	::scidb::test::rep::cleanup
} -result {none none noise {} hint classifier explanation classifier none rules {Play e4 to claim the center} {Play the repertoire move for White.} {e4 is right. How well did you know it? -- Play e4 to claim the center}}


tcltest::test reptrainer-jev-grade {reptrainer_grade suggestions, lapsed-card firewall, fallback, and user override} -setup {
	set ::scidb::test::rep::addVar $::move::Options(addVarWithoutAsking)
	set ::scidb::test::rep::delay $::reptrainer::Delay
	set ::reptrainer::Delay 0
	::scidb::test::rep::freeGameSlots
} -body {
	::scidb::test::rep::isolated {
		::scidb::test::rep::withStubClassifier {
			set fen {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}
			set cleanCard [::reptrainer::review [::reptrainer::newCard $fen {e4} 1700000000] 2 1700086400]
			set lapsedCard [::reptrainer::review $cleanCard 0 1700172800]

			# 1. High-confidence easy on a clean card is accepted
			set ::scidb::test::rep::StubOk 1
			set ::scidb::test::rep::StubChoice easy
			set ::scidb::test::rep::StubConf 0.90
			set ::scidb::test::rep::GradeRes {}
			::reptrainer::decideGrade $cleanCard e4 800 {set ::scidb::test::rep::GradeRes}
			set dEasy [::scidb::test::rep::wait ::scidb::test::rep::GradeRes]

			# 2. Firewall: easy on a lapsed card (reps=0, lapses=1) is clamped to good
			set ::scidb::test::rep::GradeRes {}
			::reptrainer::decideGrade $lapsedCard e4 700 {set ::scidb::test::rep::GradeRes}
			set dClamped [::scidb::test::rep::wait ::scidb::test::rep::GradeRes]

			# 3. Low confidence falls back to ""
			set ::scidb::test::rep::StubConf 0.35
			set ::scidb::test::rep::GradeRes {}
			::reptrainer::decideGrade $cleanCard e4 2500 {set ::scidb::test::rep::GradeRes}
			set dFallback [::scidb::test::rep::wait ::scidb::test::rep::GradeRes]

			# 4. In the drill UI, a suggested grade updates the prompt, but the user's
			# button click remains authoritative
			::scidb::test::rep::buildGame
			lassign [::scidb::test::rep::gameKeys] startKey
			::reptrainer::open .application
			update
			set dlg .application.__reptrainer__
			$dlg.setup.start invoke
			update

			set ::scidb::test::rep::StubChoice hard
			set ::scidb::test::rep::StubConf 0.88
			::reptrainer::answered e4
			after 20 { set ::scidb::test::rep::Tick 1 }
			::scidb::test::rep::wait ::scidb::test::rep::Tick
			set suggestedPrompt $::reptrainer::Vars(instruction)
			set suggestedVar $::reptrainer::Vars(suggestedGrade)
			# User clicks Easy (grade 3) despite the Hard suggestion
			$dlg.drill.grades.easy invoke
			set recordedInterval [dict get $::reptrainer::Vars(deck) cards $startKey interval]
			::reptrainer::Close $dlg

			list \
				[dict get $dEasy label] [dict get $dEasy source] \
				[dict get $dClamped label] [dict get $dClamped source] \
				[dict get $dFallback label] [dict get $dFallback source] \
				$suggestedVar $suggestedPrompt $recordedInterval
		}
	}
} -cleanup {
	catch { destroy .application.__reptrainer__ }
	set ::reptrainer::Delay $::scidb::test::rep::delay
	set ::move::Options(addVarWithoutAsking) $::scidb::test::rep::addVar
	::scidb::test::rep::cleanup
} -result {easy classifier good classifier {} rules hard {e4 is right. How well did you know it? (Suggested: Hard)} 4}


tcltest::testConstraint typesafeKey [expr {
	[info exists ::env(TYPESAFE_API_KEY)] && [string length $::env(TYPESAFE_API_KEY)] > 0
}]

tcltest::test reptrainer-jev-live {live cloud check via SCIDB_AI_CLASSIFIER=typesafe} -constraints typesafeKey -setup {
	set ::scidb::test::rep::savedBackend $::ai::systemone::Config(backend)
	set ::env(SCIDB_AI_UNCALIBRATED) 1
	::ai::systemone::configure -backend typesafe
} -body {
	set side [::reptrainer::inferSide "Caro-Kann Defense Repertoire" white]
	set ::scidb::test::rep::LiveNote {}
	::reptrainer::decideNote \
		{rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1} \
		{e4} "Play e4 to control d5 and f5" \
		{set ::scidb::test::rep::LiveNote}
	set note [::scidb::test::rep::wait ::scidb::test::rep::LiveNote]
	list [expr {$side in {white black}}] [dict get $note label]
} -cleanup {
	::ai::systemone::configure -backend $::scidb::test::rep::savedBackend
} -result {1 explanation}

tcltest::cleanupTests