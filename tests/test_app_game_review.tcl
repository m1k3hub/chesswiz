# ======================================================================
# Scidb App Test — Game Review: move classes and accuracy
# (tcl/game-review.tcl)
# ======================================================================
# The pure core (win probability, accuracy, classification, summaries) is
# tested against the documented formulas; the run path is driven with a
# stubbed engine (no real UCI, no network).
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::gamereview {}

# ----------------------------------------------------------------------
# Pure core: win probability and accuracy.
# ----------------------------------------------------------------------

tcltest::test gamereview-wp {win probability from centipawns and mate scores} -body {
	list \
		[::gamereview::wp 0] \
		[::gamereview::wp {#3}] \
		[::gamereview::wp {#-3}] \
		[::gamereview::wp 10000] \
		[::gamereview::wp -10000] \
		[format %.2f [::gamereview::wp 100]] \
		[format %.2f [::gamereview::wp -100]] \
		[::gamereview::wp {not-a-score}]
} -result {50.0 100.0 0.0 100.0 0.0 59.10 40.90 50.0}

tcltest::test gamereview-accuracy {move accuracy from a win-probability loss} -body {
	list \
		[format %.2f [::gamereview::accuracy 0]] \
		[format %.2f [::gamereview::accuracy 10]] \
		[format %.2f [::gamereview::accuracy 100]] \
		[format %.2f [::gamereview::accuracy -5]]
} -result {100.00 63.58 0.00 100.00}

tcltest::test gamereview-loss-classes {loss buckets and the best/not-best split} -body {
	# before/after are the mover's view; a loss under 2 with the engine's
	# best move is Best, without it Excellent, then the loss buckets.
	lmap {before after best} {0 0 1  0 0 0  0 -50 0  0 -100 0  0 -200 0  0 -500 0} {
		::gamereview::classFor [::gamereview::loss $before $after] $best
	}
} -result {Best Excellent Good Inaccuracy Mistake Blunder}

# ----------------------------------------------------------------------
# Classification of a synthetic sequence.
# ----------------------------------------------------------------------

tcltest::test gamereview-classify {a synthetic eval sequence classifies and counts} -body {
	set plies {
		{san e4   before 0 after 0     best 1}
		{san e5   before 0 after -200  best 0}
		{san Nf3  before 0 after -500  best 0}
		{san Nc6  before 0 after -50   best 0}
		{san Bc4  before 0 after 0     best 0}
		{san Nf6  before 0 after -100  best 0}
	}
	set r [::gamereview::classify $plies]
	set classes [lmap m [dict get $r moves] { dict get $m class }]
	set wc [dict get $r white counts]
	set bc [dict get $r black counts]
	list $classes \
		[dict get $r white n] [dict get $r black n] \
		[dict get $wc Best] [dict get $wc Excellent] [dict get $wc Blunder] \
		[dict get $bc Mistake] [dict get $bc Good] [dict get $bc Inaccuracy]
} -result {{Best Mistake Blunder Good Excellent Inaccuracy} 3 3 1 1 1 1 1 1}

tcltest::test gamereview-classify-carry {per-move dicts carry the input fields through} -body {
	set r [::gamereview::classify {
		{san e4 before 0 after 0 best 1 uci e2e4 bestMove e2e4 key m1}
		{san e5 before 0 after 0 best 1 uci e7e5 bestMove e7e5 key m2}
	}]
	set m0 [lindex [dict get $r moves] 0]
	set m1 [lindex [dict get $r moves] 1]
	list [dict get $m0 ply] [dict get $m0 side] [dict get $m0 key] \
		[dict get $m1 ply] [dict get $m1 side] [dict get $m1 key]
} -result {0 White m1 1 Black m2}

tcltest::test gamereview-mate {mate scores map to certainty and a mate is a blunder} -body {
	set r [::gamereview::classify {
		{san Qh5 before 0 after {#-3} best 0}
		{san hxg7 before {#3} after {#3} best 1}
	}]
	set classes [lmap m [dict get $r moves] { dict get $m class }]
	list $classes [format %.2f [dict get [lindex [dict get $r moves] 0] loss]]
} -result {{Blunder Best} 50.00}

# ----------------------------------------------------------------------
# The run path, with a stubbed engine.
# ----------------------------------------------------------------------

proc ::scidb::test::gamereview::stubEngine {results} {
	rename ::ai::engine::available ::scidb::test::gamereview::realAvailable
	rename ::ai::engine::classify ::scidb::test::gamereview::realClassify
	set ::scidb::test::gamereview::classifyResults $results
	set ::scidb::test::gamereview::classifyCalls 0
	proc ::ai::engine::available {} { return 1 }
	proc ::ai::engine::classify {fen san args} {
		incr ::scidb::test::gamereview::classifyCalls
		set r [lindex $::scidb::test::gamereview::classifyResults 0]
		if {[llength $::scidb::test::gamereview::classifyResults] > 1} {
			set ::scidb::test::gamereview::classifyResults \
				[lrange $::scidb::test::gamereview::classifyResults 1 end]
		}
		return $r
	}
}

proc ::scidb::test::gamereview::unstubEngine {} {
	catch { rename ::ai::engine::available {} }
	catch { rename ::ai::engine::classify {} }
	catch { rename ::scidb::test::gamereview::realAvailable ::ai::engine::available }
	catch { rename ::scidb::test::gamereview::realClassify ::ai::engine::classify }
}

tcltest::test gamereview-run {run analyses the mainline and reports classes} -setup {
	::menu::gameNew .application
	update
	foreach m {e4 e5 Nf3 Nc6} {
		::move::addMove menu $m
		update
	}
	update
	# a per-ply engine answer: {evalBeforeCp evalAfterCp uci bestMove}
	::scidb::test::gamereview::stubEngine [list \
		[dict create evalBeforeCp 0 evalAfterCp 0    uci a bestMove a] \
		[dict create evalBeforeCp 0 evalAfterCp -300 uci b bestMove c] \
		[dict create evalBeforeCp 0 evalAfterCp 0    uci d bestMove d] \
		[dict create evalBeforeCp 0 evalAfterCp 0    uci e bestMove e]]
	set ::scidb::test::gamereview::doneFlag 0
	set ::scidb::test::gamereview::result {}
} -body {
	::gamereview::run .application -done \
		{apply {{r} {set ::scidb::test::gamereview::result $r; set ::scidb::test::gamereview::doneFlag 1}}}
	vwait ::scidb::test::gamereview::doneFlag
	set r $::scidb::test::gamereview::result
	set review [dict get $r review]
	set classes [lmap m [dict get $review moves] { dict get $m class }]
	set wc [dict get $review white counts]
	set bc [dict get $review black counts]
	list [dict get $r plies] [dict get $r cancelled] $classes \
		[dict get $wc Best] [dict get $bc Best] [dict get $bc Blunder] \
		$::scidb::test::gamereview::classifyCalls
} -cleanup {
	::scidb::test::gamereview::unstubEngine
	catch { destroy .application.__gamereview }
	catch { destroy .application.__gamereview_progress }
	unset -nocomplain ::scidb::test::gamereview::doneFlag ::scidb::test::gamereview::result
} -result {4 0 {Best Blunder Best Best} 2 1 1 4}

tcltest::test gamereview-nags {NAG symbols for the classes and mark merging} -body {
	list \
		[::gamereview::nagFor Inaccuracy] [::gamereview::nagFor Mistake] \
		[::gamereview::nagFor Blunder] [::gamereview::nagFor Best] \
		[::gamereview::mergeNags {$1 $2} {$6}] \
		[::gamereview::mergeNags {$2} {$2}] \
		[::gamereview::mergeNags {} {$4}]
} -result {{$6} {$2} {$4} {} {$1 $2 $6} {$2} {$4}}

# ----------------------------------------------------------------------
# System One (Jev): Turning point, Focus, and Symbol gating.
# ----------------------------------------------------------------------

tcltest::test gamereview-turning-point-fallback {turning point picks competitive blunder over late garbage} -body {
	set emptyRev [::gamereview::classify {}]
	set rEmpty [::gamereview::turningPointFallback [::gamereview::turningPointCandidates $emptyRev]]

	# Ply 2: blunder in competitive position (before=0 cp, after=-250 cp)
	# Ply 4: mistake in already dead-lost position (before=-500 cp)
	set plies {
		{san e4   before 0    after 0     best 1}
		{san e5   before 0    after 0     best 1}
		{san Qh5  before 0    after -250  best 0}
		{san Nc6  before 0    after 0     best 1}
		{san Bc4  before -500 after -1500 best 0}
		{san Nf6  before 0    after 0     best 1}
	}
	set review [::gamereview::classify $plies]
	set candidates [::gamereview::turningPointCandidates $review]
	set rCompetitive [::gamereview::turningPointFallback $candidates]
	list $rEmpty $rCompetitive [llength $candidates]
} -result {none ply_2 2}

tcltest::test gamereview-focus-fallback {review focus categorized deterministically} -body {
	# 1. Solid: high accuracy, 0 blunders
	set solidRev [::gamereview::classify {
		{san e4  before 0 after 0 best 1}
		{san e5  before 0 after 0 best 1}
		{san Nf3 before 0 after 0 best 1}
		{san Nc6 before 0 after 0 best 1}
	}]
	set fSolid [::gamereview::focusFallback $solidRev]

	# 2. Opening: blunder before ply 20
	set openRev [::gamereview::classify {
		{san e4   before 0 after 0    best 1}
		{san e5   before 0 after 0    best 1}
		{san f4   before 0 after -600 best 0}
		{san exf4 before 0 after 0    best 1}
	}]
	set fOpen [::gamereview::focusFallback $openRev]

	# 3. Tactics: big tactical blunder in middlegame
	set midPlies {}
	for {set i 0} {$i < 30} {incr i} {
		lappend midPlies [list san "m$i" before 0 after 0 best 1]
	}
	lappend midPlies [list san "Bxf7+" before 0 after -500 best 0]
	set midRev [::gamereview::classify $midPlies]
	set fTactics [::gamereview::focusFallback $midRev]

	# 4. Endgame: long game with error in late phase (ply 60+)
	set endPlies {}
	for {set i 0} {$i < 62} {incr i} {
		lappend endPlies [list san "m$i" before 0 after 0 best 1]
	}
	lappend endPlies [list san "Ke4" before 0 after -200 best 0]
	set endRev [::gamereview::classify $endPlies]
	set fEndgame [::gamereview::focusFallback $endRev]

	list $fSolid $fOpen $fTactics $fEndgame
} -result {solid opening tactics endgame}

tcltest::test gamereview-symbol-gate-fallback {symbol gate filters based on error density} -body {
	# 0 errors -> skip
	set cleanRev [::gamereview::classify {
		{san e4 before 0 after 0 best 1}
		{san e5 before 0 after 0 best 1}
	}]
	set gClean [::gamereview::symbolGateFallback $cleanRev]

	# Dense inaccuracies -> critical_only
	set densePlies {}
	for {set i 0} {$i < 16} {incr i} {
		lappend densePlies [list san "m$i" before 0 after -80 best 0]
	}
	set denseRev [::gamereview::classify $densePlies]
	set gDense [::gamereview::symbolGateFallback $denseRev]

	# Sparse errors -> all_errors
	set sparsePlies {
		{san e4  before 0 after 0    best 1}
		{san e5  before 0 after 0    best 1}
		{san Nf3 before 0 after -80  best 0}
		{san Nc6 before 0 after 0    best 1}
		{san Bc4 before 0 after 0    best 1}
		{san Bc5 before 0 after 0    best 1}
	}
	set sparseRev [::gamereview::classify $sparsePlies]
	set gSparse [::gamereview::symbolGateFallback $sparseRev]

	list $gClean $gDense $gSparse
} -result {skip critical_only all_errors}

# ----------------------------------------------------------------------
# Async and Sync System One decisions with stubbed classifier.
# ----------------------------------------------------------------------

proc ::scidb::test::gamereview::stubClassifier {answers {ok 1}} {
	catch { rename ::ai::systemone::enabled ::scidb::test::gamereview::realEnabled }
	catch { rename ::ai::systemone::qualified ::scidb::test::gamereview::realQualified }
	catch { rename ::ai::systemone::evaluateAsync ::scidb::test::gamereview::realEvalAsync }

	set ::scidb::test::gamereview::stubAnswers $answers
	set ::scidb::test::gamereview::stubOk $ok

	proc ::ai::systemone::enabled {} { return 1 }
	proc ::ai::systemone::qualified {args} { return 1 }
	proc ::ai::systemone::evaluateAsync {state questions script} {
		if {$::scidb::test::gamereview::stubOk} {
			after 0 [list {*}$script [dict create ok 1 answers $::scidb::test::gamereview::stubAnswers]]
		} else {
			after 0 [list {*}$script [dict create ok 0 error "classifier error"]]
		}
	}
}

proc ::scidb::test::gamereview::unstubClassifier {} {
	catch { rename ::ai::systemone::enabled {} }
	catch { rename ::ai::systemone::qualified {} }
	catch { rename ::ai::systemone::evaluateAsync {} }
	catch { rename ::scidb::test::gamereview::realEnabled ::ai::systemone::enabled }
	catch { rename ::scidb::test::gamereview::realQualified ::ai::systemone::qualified }
	catch { rename ::scidb::test::gamereview::realEvalAsync ::ai::systemone::evaluateAsync }
}

proc ::scidb::test::gamereview::stubChooseSync {chosen} {
	catch { rename ::ai::systemone::enabled ::scidb::test::gamereview::realEnabled }
	catch { rename ::ai::systemone::qualified ::scidb::test::gamereview::realQualified }
	catch { rename ::ai::systemone::chooseManySync ::scidb::test::gamereview::realChooseManySync }
	set ::scidb::test::gamereview::stubChosen $chosen
	proc ::ai::systemone::enabled {} { return 1 }
	proc ::ai::systemone::qualified {args} { return 1 }
	proc ::ai::systemone::chooseManySync {feature state questions args} {
		return $::scidb::test::gamereview::stubChosen
	}
}

proc ::scidb::test::gamereview::unstubChooseSync {} {
	catch { rename ::ai::systemone::enabled {} }
	catch { rename ::ai::systemone::qualified {} }
	catch { rename ::ai::systemone::chooseManySync {} }
	catch { rename ::scidb::test::gamereview::realEnabled ::ai::systemone::enabled }
	catch { rename ::scidb::test::gamereview::realQualified ::ai::systemone::qualified }
	catch { rename ::scidb::test::gamereview::realChooseManySync ::ai::systemone::chooseManySync }
}

tcltest::test gamereview-judge-async-classifier {async review judgment via classifier} -setup {
	set review [::gamereview::classify {
		{san e4  before 0 after 0    best 1}
		{san e5  before 0 after 0    best 1}
		{san Qh5 before 0 after -300 best 0}
		{san Nc6 before 0 after 0    best 1}
	}]
	::scidb::test::gamereview::stubClassifier [dict create \
		review_turning_point [dict create type choice choice ply_2 confidence 0.88 probabilities {ply_2 0.88}] \
		review_focus [dict create type choice choice tactics confidence 0.92 probabilities {tactics 0.92}] \
		review_symbol_gate [dict create type choice choice critical_only confidence 0.85 probabilities {critical_only 0.85}]]
	set ::scidb::test::gamereview::judgeResult {}
	set ::scidb::test::gamereview::judgeFlag 0
} -body {
	::gamereview::judgeReviewAsync $review {apply {{r} {
		set ::scidb::test::gamereview::judgeResult $r
		set ::scidb::test::gamereview::judgeFlag 1
	}}}
	vwait ::scidb::test::gamereview::judgeFlag
	set r $::scidb::test::gamereview::judgeResult
	list [dict get $r ok] [dict get $r source] \
		[dict get $r turning_point] [dict get $r turning_point_source] \
		[dict get $r focus] [dict get $r focus_source] \
		[dict get $r symbol_gate] [dict get $r symbol_gate_source]
} -cleanup {
	::scidb::test::gamereview::unstubClassifier
	unset -nocomplain ::scidb::test::gamereview::judgeResult ::scidb::test::gamereview::judgeFlag
} -result {1 classifier ply_2 engine tactics classifier critical_only classifier}

tcltest::test gamereview-judge-async-fallback-abstain {low confidence abstains to deterministic fallback} -setup {
	set review [::gamereview::classify {
		{san e4  before 0 after 0    best 1}
		{san e5  before 0 after 0    best 1}
		{san Qh5 before 0 after -300 best 0}
		{san Nc6 before 0 after 0    best 1}
	}]
	# Confidence 0.3 is below default 0.6 threshold
	::scidb::test::gamereview::stubClassifier [dict create \
		review_turning_point [dict create type choice choice ply_2 confidence 0.3 probabilities {ply_2 0.3}] \
		review_focus [dict create type choice choice tactics confidence 0.3 probabilities {tactics 0.3}] \
		review_symbol_gate [dict create type choice choice critical_only confidence 0.3 probabilities {critical_only 0.3}]]
	set ::scidb::test::gamereview::judgeResult {}
	set ::scidb::test::gamereview::judgeFlag 0
} -body {
	::gamereview::judgeReviewAsync $review {apply {{r} {
		set ::scidb::test::gamereview::judgeResult $r
		set ::scidb::test::gamereview::judgeFlag 1
	}}}
	vwait ::scidb::test::gamereview::judgeFlag
	set r $::scidb::test::gamereview::judgeResult
	list [dict get $r ok] [dict get $r source] \
		[dict get $r turning_point_source] [dict get $r focus_source] [dict get $r symbol_gate_source]
} -cleanup {
	::scidb::test::gamereview::unstubClassifier
	unset -nocomplain ::scidb::test::gamereview::judgeResult ::scidb::test::gamereview::judgeFlag
} -result {1 rules engine rules rules}

tcltest::test gamereview-judge-async-disabled {disabled classifier returns rules fallback immediately} -setup {
	set review [::gamereview::classify {
		{san e4  before 0 after 0    best 1}
		{san e5  before 0 after 0    best 1}
		{san Qh5 before 0 after -300 best 0}
		{san Nc6 before 0 after 0    best 1}
	}]
	::ai::systemone::configure -backend off
	set ::scidb::test::gamereview::judgeResult {}
	set ::scidb::test::gamereview::judgeFlag 0
} -body {
	::gamereview::judgeReviewAsync $review {apply {{r} {
		set ::scidb::test::gamereview::judgeResult $r
		set ::scidb::test::gamereview::judgeFlag 1
	}}}
	vwait ::scidb::test::gamereview::judgeFlag
	set r $::scidb::test::gamereview::judgeResult
	list [dict get $r ok] [dict get $r source] \
		[dict get $r turning_point] [dict get $r focus] [dict get $r symbol_gate]
} -cleanup {
	unset -nocomplain ::scidb::test::gamereview::judgeResult ::scidb::test::gamereview::judgeFlag
} -result {1 rules ply_2 opening all_errors}

tcltest::test gamereview-judge-sync {sync review judgment via chooseManySync} -setup {
	set review [::gamereview::classify {
		{san e4  before 0 after 0    best 1}
		{san e5  before 0 after 0    best 1}
		{san Qh5 before 0 after -300 best 0}
		{san Nc6 before 0 after 0    best 1}
	}]
	::scidb::test::gamereview::stubChooseSync [dict create \
		review_turning_point ply_2 \
		review_focus tactics \
		review_symbol_gate critical_only]
} -body {
	set res [::gamereview::judgeReviewSync $review]
	list [dict get $res ok] [dict get $res source] \
		[dict get $res turning_point] [dict get $res focus] [dict get $res symbol_gate]
} -cleanup {
	::scidb::test::gamereview::unstubChooseSync
} -result {1 classifier ply_2 tactics critical_only}

tcltest::test gamereview-add-symbols-gated {AddSymbols respects gate filter} -setup {
	set ::scidb::test::gamereview::annotated {}
	catch { rename ::scidb::game::update ::scidb::test::gamereview::realGameUpdate }
	catch { rename ::scidb::game::query ::scidb::test::gamereview::realGameQuery }
	proc ::scidb::game::update {what key val} {
		lappend ::scidb::test::gamereview::annotated $key $val
	}
	proc ::scidb::game::query {args} { return "" }
} -body {
	# Create synthetic moves
	set moves [list \
		[dict create key m1 class Inaccuracy] \
		[dict create key m2 class Mistake] \
		[dict create key m3 class Blunder] \
		[dict create key m4 class Best]]

	# 1. Gate: critical_only -> skips Inaccuracy (m1), annotates m2 and m3
	set c1 [::gamereview::AddSymbols $moves "" critical_only]
	set a1 $::scidb::test::gamereview::annotated

	# 2. Gate: all_errors -> annotates m1, m2, m3
	set ::scidb::test::gamereview::annotated {}
	set c2 [::gamereview::AddSymbols $moves "" all_errors]
	set a2 $::scidb::test::gamereview::annotated

	# 3. Gate: skip -> annotates nothing
	set ::scidb::test::gamereview::annotated {}
	set c3 [::gamereview::AddSymbols $moves "" skip]
	set a3 $::scidb::test::gamereview::annotated

	list $c1 [expr {[llength $a1] / 2}] $c2 [expr {[llength $a2] / 2}] $c3 [expr {[llength $a3] / 2}]
} -cleanup {
	catch { rename ::scidb::game::update {} }
	catch { rename ::scidb::game::query {} }
	catch { rename ::scidb::test::gamereview::realGameUpdate ::scidb::game::update }
	catch { rename ::scidb::test::gamereview::realGameQuery ::scidb::game::query }
	unset -nocomplain ::scidb::test::gamereview::annotated
} -result {2 2 3 3 0 0}

# ----------------------------------------------------------------------
# Live check against TypeSafe cloud backend (only if TYPESAFE_API_KEY is set).
# ----------------------------------------------------------------------

tcltest::testConstraint liveTypesafe [expr {
	[info exists ::env(TYPESAFE_API_KEY)] && [string length $::env(TYPESAFE_API_KEY)] > 10
}]

tcltest::test gamereview-live-typesafe {live typesafe cloud classifier evaluation} -constraints liveTypesafe -body {
	::ai::systemone::configure -backend typesafe
	set review [::gamereview::classify {
		{san e4  before 0 after 0    best 1}
		{san e5  before 0 after 0    best 1}
		{san Qh5 before 0 after -500 best 0}
		{san Nc6 before 0 after 0    best 1}
	}]
	set res [::gamereview::judgeReviewSync $review -timeout 10000]
	list [dict get $res ok] [expr {[dict get $res focus] in {tactics opening conversion endgame solid}}]
} -cleanup {
	::ai::systemone::configure -backend off
} -result {1 1}

# Engine first: the turning point is the engine's call; a typed judgment
# may only choose between candidates the engine rates as close.
proc ::scidb::test::gamereview::mv {ply side san class loss before after} {
	dict create ply $ply side $side san $san class $class loss $loss before $before after $after
}

tcltest::test gamereview-tp-engine-first {the earliest error that decided a contested game, not the biggest drop} -body {
	# ply 10: White (0 cp) blunders into -500 (decided, never recovers);
	# ply 30: a bigger drop later, in an already lost position
	set moves [list \
		[::scidb::test::gamereview::mv 10 White Qd2 Blunder 40.0 0 -500] \
		[::scidb::test::gamereview::mv 11 Black Nf6 Best 0.0 500 500] \
		[::scidb::test::gamereview::mv 30 White Kf1 Blunder 45.0 -500 -2000] \
		[::scidb::test::gamereview::mv 31 Black Qh1 Best 0.0 2000 2000]]
	set review [dict create moves $moves]
	set c [::gamereview::turningPointCandidates $review]
	::gamereview::turningPointEngine $review $c
} -result {ply_10 {}}

tcltest::test gamereview-tp-close-only {Jev is asked only between close engine candidates, and its other answers are ignored} -setup {
	rename ::ai::systemone::enabled ::scidb::test::gamereview::realEnabled
	rename ::ai::systemone::evaluateAsync ::scidb::test::gamereview::realEvalAsync
	proc ::ai::systemone::enabled {} { return 1 }
	proc ::ai::systemone::evaluateAsync {state questions script} {
		set ::scidb::test::gamereview::asked [expr {[dict exists $questions review_turning_point]
			? [dict keys [dict get $questions review_turning_point criteria]] : {}}]
		after 0 [list {*}$script [dict create ok 1 answers [dict create \
			review_turning_point [dict create type choice choice $::scidb::test::gamereview::answer confidence 0.9 \
				probabilities [list $::scidb::test::gamereview::answer 0.9]]]]]
	}
} -body {
	# two competitive errors 1 point apart, neither decisive: close
	set moves [list \
		[::scidb::test::gamereview::mv 12 White Bd3 Mistake 15.0 50 -100] \
		[::scidb::test::gamereview::mv 13 Black Bg4 Mistake 14.0 100 -60] \
		[::scidb::test::gamereview::mv 40 White Rd1 Inaccuracy 8.0 -60 -150]]
	set counts {Best 0 Excellent 0 Good 0 Inaccuracy 0 Mistake 0 Blunder 0}
	set review [dict create moves $moves white [dict create accuracy 80 n 2 counts [dict replace $counts Mistake 2]] black [dict create accuracy 80 n 1 counts [dict replace $counts Mistake 1]]]
	set out {}
	foreach ans {ply_13 ply_40} {
		set ::scidb::test::gamereview::answer $ans
		set ::scidb::test::gamereview::r {}
		::gamereview::judgeReviewAsync $review {apply {{d} {set ::scidb::test::gamereview::r $d}}}
		vwait ::scidb::test::gamereview::r
		lappend out [lsort $::scidb::test::gamereview::asked] \
			[dict get $::scidb::test::gamereview::r turning_point] \
			[dict get $::scidb::test::gamereview::r turning_point_source]
	}
	set out
} -cleanup {
	rename ::ai::systemone::enabled {}
	rename ::scidb::test::gamereview::realEnabled ::ai::systemone::enabled
	rename ::ai::systemone::evaluateAsync {}
	rename ::scidb::test::gamereview::realEvalAsync ::ai::systemone::evaluateAsync
} -result {{ply_12 ply_13} ply_13 classifier {ply_12 ply_13} ply_12 engine}

tcltest::cleanupTests
