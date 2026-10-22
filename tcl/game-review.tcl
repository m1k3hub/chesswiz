# ======================================================================
# ::gamereview -- Chess.com-style "Game Review": move classes and accuracy.
#
# Walks the current game's mainline and labels every move, like the
# Chess.com / Lichess computer analysis:
#
#   Best        the engine's best move, and it loses nothing (<= 2)
#   Excellent   a move that loses nothing (<= 2) but is not the best
#   Good        loses at most 5 win-percent
#   Inaccuracy  loses at most 10 win-percent    (?!)
#   Mistake     loses at most 20 win-percent    (?)
#   Blunder     loses more than 20 win-percent  (??)
#
# Per move the "loss" is the drop in win probability the move causes,
# both before and after measured from the side to move's point of view:
#
#   loss = wp(before) - wp(after)
#
# where wp() is the Lichess win-probability from centipawns,
#
#   wp(cp) = 50 + 50 * (2 / (1 + exp(-0.00368208 * cp)) - 1)
#
# and a mate score maps to 0 or 100 (a forced mate is a certainty).  A
# move's accuracy is the Lichess formula
#
#   acc = 103.1668 * exp(-0.04354 * loss) - 3.1669      (clamped 0..100)
#
# and each side's game accuracy is the mean of that side's move
# accuracies.
#
# The pure core (wp, loss, accuracy, classFor, classify) is UI-free and
# fully tested; ::gamereview::run drives it.  The engine facts come from
# ::ai::engine::classify (the same Stockfish UCI client the rest of the
# AI layer uses); no new UCI client is invented here.
#
#   ::gamereview::classify $plies      -> {moves ... white ... black ...}
#   ::gamereview::run $parent ?-depth N? ?-done CMD?
#   ::gamereview::judgeReviewAsync $review $script
#   ::gamereview::judgeReviewSync $review ?args?
#   ::gamereview::cancel
#   ::gamereview::running?
#
# System One (Jev) typed decisions:
#   review_turning_point (choice)  the single decisive turning point
#   review_focus         (choice)  coaching focus {tactics opening conversion endgame solid}
#   review_symbol_gate   (choice)  symbol gating {all_errors critical_only skip}
#
# Each decision has a deterministic fallback used when the classifier is
# off, unreachable, abstains, or scores below threshold. Engine facts and
# win probabilities are never overridden.
#
# <plies> is a list of per-move dicts, one per ply, each with:
#   san     the move in SAN
#   before  the evaluation of the position BEFORE the move, from the
#           mover's point of view (centipawns, or a mate marker)
#   after   the evaluation AFTER the move, from the mover's point of view
#   best    1 when the move is the engine's best move, else 0
#   (side, uci, bestMove, bestSan, key, fen are carried through when given)
#
# A score is a centipawn number (a large |cp| >= 9900 is the ai-engine's
# mate convention) or the string "#N": N > 0 means the side whose view it
# is mates (100), N < 0 means that side is mated (0).
# ======================================================================

::util::source game-review

package require Tcl 8.5
package require Tk 8.5

namespace eval ::gamereview {
namespace eval mc {

set Title			"Game Review"
set White			"White"
set Black			"Black"
set Accuracy		"Accuracy"
set Best			"Best"
set Excellent		"Excellent"
set Good			"Good"
set Inaccuracy		"Inaccuracy"
set Mistake			"Mistake"
set Blunder			"Blunder"
set Reviewing		"Reviewing move %d of %d (%s)..."
set NoEngine		"No chess engine is available for game review."
set NoGame			"No game to review."
set Cancelled		"Review cancelled after %d move(s)."
set AddSymbols		"Add symbols to game"
set AddedSymbols	"Added %d symbol(s) to the game."
set Close			"Close"
set Cancel			"Cancel"
set BetterMove		"better was"
set KeyMoves		"Mistakes and blunders"
set NoKeyMoves		"No inaccuracies, mistakes or blunders."
set TurningPoint	"Turning Point"
set Focus			"Review Focus"
set FocusTactics	"Tactics"
set FocusOpening	"Opening"
set FocusConversion	"Conversion"
set FocusEndgame	"Endgame"
set FocusSolid		"Solid"

} ;# namespace mc

array set Options {
	depth	12
}

variable MaxPlies 200

variable Priv
array set Priv {
	running			0
	cancel			0
	plies				{}
	index				0
	total				0
	results			{}
	done				{}
	parent			{}
	rows				{}
	turning_point	{}
	focus				{}
	symbol_gate		all_errors
	review			{}
	dialog			{}
}

} ;# namespace ::gamereview


proc ::gamereview::configure {args} {
	variable Options
	variable MaxPlies

	foreach {key value} $args {
		set key [string trimleft $key -]
		switch -- $key {
			depth    { set Options(depth) $value }
			maxPlies { set MaxPlies $value }
			default  { error "unknown game-review setting '$key'" }
		}
	}
	return
}


proc ::gamereview::running? {} {
	variable Priv
	return $Priv(running)
}


# ======================================================================
# Pure core (no Tk).
# ======================================================================

# Win probability in [0,100] for a score from the side whose view it is.
# A number is centipawns; "#N" is a mate (N>0 this side mates, N<0 this
# side is mated); a centipawn magnitude >= 9900 is the ai-engine's mate
# convention and also maps to 0 or 100.
proc ::gamereview::wp {score} {
	if {[string match "#*" $score]} {
		set n [string range $score 1 end]
		if {![string is integer -strict $n]} { return 50.0 }
		return [expr {$n > 0 ? 100.0 : 0.0}]
	}
	if {![string is double -strict $score]} { return 50.0 }
	set cp [expr {double($score)}]
	if {$cp >= 9900} { return 100.0 }
	if {$cp <= -9900} { return 0.0 }
	return [expr {50.0 + 50.0 * (2.0 / (1.0 + exp(-0.00368208 * $cp)) - 1.0)}]
}


# The win-probability loss a move causes, both scores from the mover's
# view. Never negative.
proc ::gamereview::loss {before after} {
	set l [expr {[wp $before] - [wp $after]}]
	if {$l < 0} { set l 0.0 }
	return $l
}


# Move accuracy from a win-probability loss (Lichess), clamped 0..100.
proc ::gamereview::accuracy {loss} {
	set a [expr {103.1668 * exp(-0.04354 * $loss) - 3.1669}]
	if {$a < 0} { set a 0.0 }
	if {$a > 100} { set a 100.0 }
	return $a
}


# The class of a move from its loss and whether it is the engine's best.
# Thresholds (win-percent loss):
#   <= 2   Best (engine best move) else Excellent
#   <= 5   Good
#   <= 10  Inaccuracy
#   <= 20  Mistake
#   > 20   Blunder
proc ::gamereview::classFor {loss best} {
	if {$loss <= 2} {
		return [expr {$best ? "Best" : "Excellent"}]
	}
	if {$loss <= 5}  { return Good }
	if {$loss <= 10} { return Inaccuracy }
	if {$loss <= 20} { return Mistake }
	return Blunder
}


# The numeric annotation (NAG) for a class, or "" when none is shown.
proc ::gamereview::nagFor {class} {
	switch -- $class {
		Inaccuracy	{ return {$6} }
		Mistake		{ return {$2} }
		Blunder		{ return {$4} }
	}
	return {}
}


# The numeric annotations in a "marks" string, as a list of $n.
proc ::gamereview::extractNags {marks} {
	set out {}
	foreach {whole number} [regexp -all -inline {\$(\d+)} $marks] {
		lappend out "\$$number"
	}
	return $out
}


# The union of the marks already on a move and the one we want to add.
proc ::gamereview::mergeNags {existing nag} {
	set out [extractNags $existing]
	if {[string length $nag] && $nag ni $out} { lappend out $nag }
	return [join $out " "]
}


# Classify a game's moves. <plies> is a list of per-move dicts (see the
# header). Returns:
#
#   moves  { {ply 0 san e4 class Best loss 0.00 accuracy 100.00 side White
#              ...carried-through keys...} ... }
#   white  {accuracy 85.50 n 5 counts {Best 3 Excellent 1 Good 1 ...}}
#   black  {accuracy 72.30 n 5 counts {Best 2 Excellent 1 Good 0 ...}}
#
# White moves on even plies, Black on odd, unless a ply carries an
# explicit "side" key.
proc ::gamereview::classify {plies} {
	set moves {}
	set i 0
	foreach ply $plies {
		set san    [expr {[dict exists $ply san]    ? [dict get $ply san]    : ""}]
		set before [expr {[dict exists $ply before] ? [dict get $ply before] : 0}]
		set after  [expr {[dict exists $ply after]  ? [dict get $ply after]  : 0}]
		set best   [expr {[dict exists $ply best]   ? [dict get $ply best]   : 0}]

		set l   [loss $before $after]
		set cls [classFor $l $best]
		set acc [accuracy $l]

		set move [dict create ply $i san $san class $cls \
			loss [format %.2f $l] accuracy [format %.2f $acc]]
		set side [expr {$i % 2 == 0 ? "White" : "Black"}]
		if {[dict exists $ply side]} { set side [dict get $ply side] }
		dict set move side $side
		foreach k {uci bestMove bestSan key fen} {
			if {[dict exists $ply $k]} { dict set move $k [dict get $ply $k] }
		}
		lappend moves $move
		incr i
	}
	return [dict create moves $moves \
		white [summary $moves White] black [summary $moves Black]]
}


# The per-side summary: mean accuracy, the number of moves and the count
# of each class.
proc ::gamereview::summary {moves side} {
	set counts [dict create Best 0 Excellent 0 Good 0 Inaccuracy 0 Mistake 0 Blunder 0]
	set n 0
	set sum 0.0
	foreach m $moves {
		if {[dict get $m side] ne $side} { continue }
		incr n
		set sum [expr {$sum + [dict get $m accuracy]}]
		set cls [dict get $m class]
		dict set counts $cls [expr {[dict get $counts $cls] + 1}]
	}
	set acc [expr {$n ? [format %.2f [expr {$sum / double($n)}]] : 0.0}]
	return [dict create accuracy $acc n $n counts $counts]
}


# ======================================================================
# System One (Jev) typed decisions.
# ======================================================================

# Candidate moments for turning-point selection: Mistakes and Blunders,
# or Inaccuracies if the game was free of mistakes and blunders.
proc ::gamereview::turningPointCandidates {review} {
	set candidates {}
	set moves [expr {[dict exists $review moves] ? [dict get $review moves] : {}}]
	foreach m $moves {
		set cls [dict get $m class]
		if {$cls in {Mistake Blunder}} {
			lappend candidates [CandidateFromMove $m]
		}
	}
	if {[llength $candidates] == 0} {
		foreach m $moves {
			if {[dict get $m class] eq "Inaccuracy"} {
				lappend candidates [CandidateFromMove $m]
			}
		}
	}
	return $candidates
}


proc ::gamereview::CandidateFromMove {m} {
	set ply [dict get $m ply]
	set side [dict get $m side]
	set san [dict get $m san]
	set loss [dict get $m loss]
	set cls [dict get $m class]
	set before [expr {[dict exists $m before] ? [dict get $m before] : 0}]
	set after [expr {[dict exists $m after] ? [dict get $m after] : 0}]
	set phase [expr {$ply < 20 ? "opening" : ($ply < 60 ? "middlegame" : "endgame")}]
	set label "[moveLabel $m] $san"

	return [dict create \
		tag "ply_$ply" \
		ply $ply \
		move $label \
		side $side \
		loss $loss \
		class $cls \
		evalBefore $before \
		evalAfter $after \
		phase $phase]
}


# The classifier question for the decisive turning point.
proc ::gamereview::turningPointQuestion {candidates {allowNone 1}} {
	set crit [dict create]
	foreach c $candidates {
		dict set crit [dict get $c tag] \
			"[dict get $c move] ([dict get $c side], loss [dict get $c loss]%, [dict get $c class] in [dict get $c phase])"
	}
	if {$allowNone} {
		dict set crit none "no single decisive turning point; gradual shift or clean game"
	}
	return [dict create \
		type choice \
		instructions "Which move is the decisive turning point where the game's outcome fundamentally tilted, rather than a late blunder in an already decided position or a minor shift?" \
		criteria $crit]
}


# Deterministic fallback for the turning point: among moves where the game
# was still competitive (before win probability 15%..85%), pick the largest
# loss; otherwise the overall largest loss.
proc ::gamereview::turningPointFallback {candidates} {
	if {[llength $candidates] == 0} { return "none" }

	set competitive {}
	foreach c $candidates {
		set before [dict get $c evalBefore]
		set prob [wp $before]
		if {$prob >= 15.0 && $prob <= 85.0} {
			lappend competitive $c
		}
	}
	set pool [expr {[llength $competitive] ? $competitive : $candidates}]

	set bestTag [dict get [lindex $pool 0] tag]
	set maxLoss [dict get [lindex $pool 0] loss]
	foreach c [lrange $pool 1 end] {
		set l [dict get $c loss]
		if {$l > $maxLoss} {
			set maxLoss $l
			set bestTag [dict get $c tag]
		}
	}
	return $bestTag
}


# The turning point decided by the engine's numbers, engine first:
#
#   the earliest flagged error that turned a contested game (the mover's
#   win probability 15..85 before the move) into a decided one (below 15
#   after it), when the mover never got back into the game (above 30)
#   afterwards; else the turning-point fallback (largest loss in a
#   competitive position, else largest loss).
#
# Returns {tag close}: close lists the other candidates whose loss is
# within 3 points of the chosen one's in the same tier -- the only case
# where a typed judgment (Jev) may choose, and only among {tag close}.
proc ::gamereview::turningPointEngine {review candidates} {
	if {![llength $candidates]} { return [list none {}] }
	set moves [dict get $review moves]

	# the mover's win probability after every ply, from each side's view
	set wpAfter [dict create]
	foreach m $moves {
		set after [expr {[dict exists $m after] ? [dict get $m after] : 0}]
		set p [wp $after]
		dict set wpAfter [dict get $m ply] [dict get $m side] $p
		dict set wpAfter [dict get $m ply] [expr {[dict get $m side] eq "White" ? "Black" : "White"}] [expr {100.0 - $p}]
	}

	set decisive {}
	foreach c $candidates {
		set before [wp [dict get $c evalBefore]]
		set after [wp [dict get $c evalAfter]]
		if {$before < 15.0 || $before > 85.0 || $after >= 15.0} { continue }
		set side [dict get $c side]
		set recovered 0
		dict for {ply bySide} $wpAfter {
			if {$ply > [dict get $c ply] && [dict get $bySide $side] > 30.0} { set recovered 1; break }
		}
		if {!$recovered} { lappend decisive $c }
	}

	if {[llength $decisive]} {
		set pool $decisive
		set chosen [lindex [lsort -integer -index 1 [lmap c $decisive {list [dict get $c tag] [dict get $c ply]}]] 0 0]
	} else {
		set chosen [turningPointFallback $candidates]
		set pool {}
		foreach c $candidates {
			set b [wp [dict get $c evalBefore]]
			if {$b >= 15.0 && $b <= 85.0} { lappend pool $c }
		}
		if {![llength $pool]} { set pool $candidates }
	}

	set chosenLoss 0
	foreach c $pool { if {[dict get $c tag] eq $chosen} { set chosenLoss [dict get $c loss] } }
	set close {}
	foreach c $pool {
		if {[dict get $c tag] ne $chosen && abs([dict get $c loss] - $chosenLoss) <= 3.0} {
			lappend close [dict get $c tag]
		}
	}
	return [list $chosen $close]
}


# The candidates among <tags>, for a question that may only choose there.
proc ::gamereview::candidatesTagged {candidates tags} {
	return [lmap c $candidates { expr {[dict get $c tag] in $tags ? $c : [continue]} }]
}


proc ::gamereview::turningPointState {review candidates} {
	set nPlies [llength [dict get $review moves]]
	set wacc [dict get $review white accuracy]
	set bacc [dict get $review black accuracy]
	set cparts {}
	foreach c $candidates {
		lappend cparts "[dict get $c tag]: [dict get $c move] ([dict get $c side], loss=[dict get $c loss]%, before=[dict get $c evalBefore], after=[dict get $c evalAfter], phase=[dict get $c phase])"
	}
	if {[llength $cparts] == 0} { set ctext "none" } else { set ctext [join $cparts "; "] }
	return "plies=$nPlies white_acc=$wacc black_acc=$bacc candidates: $ctext"
}


# The classifier question for review focus / coaching takeaway.
proc ::gamereview::focusQuestion {} {
	return [dict create \
		type choice \
		instructions "What is the primary review focus or coaching takeaway for this game?" \
		criteria [dict create \
			tactics    "sharp tactical swings or decisive single-move tactical blunders" \
			opening    "game was compromised or decided in the opening (first 15 moves)" \
			conversion "one side obtained a clear winning advantage but struggled or failed to convert" \
			endgame    "game was balanced into the endgame (move 30+) where technical execution decided the result" \
			solid      "clean, high-accuracy play from both sides with few or no major errors" \
		]]
}


# Deterministic fallback for review focus.
proc ::gamereview::focusFallback {review} {
	set wacc 0.0
	set bacc 0.0
	if {[dict exists $review white accuracy]} { set wacc [dict get $review white accuracy] }
	if {[dict exists $review black accuracy]} { set bacc [dict get $review black accuracy] }

	set wc [dict get $review white counts]
	set bc [dict get $review black counts]
	set totalBlunders [expr {[dict get $wc Blunder] + [dict get $bc Blunder]}]
	set totalMistakes [expr {[dict get $wc Mistake] + [dict get $bc Mistake]}]
	set totalInacc [expr {[dict get $wc Inaccuracy] + [dict get $bc Inaccuracy]}]

	if {$wacc >= 88.0 && $bacc >= 88.0 && $totalBlunders == 0 && $totalMistakes == 0 && $totalInacc <= 2} {
		return solid
	}

	set openLoss 0.0
	set midLoss 0.0
	set endLoss 0.0
	set worstLoss 0.0
	set worstPly 0
	set moves [dict get $review moves]

	foreach m $moves {
		set l [dict get $m loss]
		set p [dict get $m ply]
		if {$l > $worstLoss} {
			set worstLoss $l
			set worstPly $p
		}
		if {$p < 20} {
			set openLoss [expr {$openLoss + $l}]
		} elseif {$p < 60} {
			set midLoss [expr {$midLoss + $l}]
		} else {
			set endLoss [expr {$endLoss + $l}]
		}
	}

	if {[llength $moves] >= 60 && ($worstPly >= 60 || $endLoss > $midLoss)} {
		return endgame
	}
	if {$worstPly < 20 && $openLoss >= $midLoss && ($totalBlunders > 0 || $totalMistakes > 0)} {
		return opening
	}
	if {$worstLoss >= 20.0} {
		return tactics
	}
	return conversion
}


proc ::gamereview::focusState {review} {
	set nPlies [llength [dict get $review moves]]
	set wacc [dict get $review white accuracy]
	set bacc [dict get $review black accuracy]
	set wc [dict get $review white counts]
	set bc [dict get $review black counts]

	set openLoss 0.0
	set midLoss 0.0
	set endLoss 0.0
	set worstLoss 0.0
	set worstPly 0

	foreach m [dict get $review moves] {
		set l [dict get $m loss]
		set p [dict get $m ply]
		if {$l > $worstLoss} {
			set worstLoss $l
			set worstPly $p
		}
		if {$p < 20} {
			set openLoss [expr {$openLoss + $l}]
		} elseif {$p < 60} {
			set midLoss [expr {$midLoss + $l}]
		} else {
			set endLoss [expr {$endLoss + $l}]
		}
	}
	return [format "plies=%d white_acc=%.1f black_acc=%.1f counts: white={Best:%d Exc:%d Good:%d Inacc:%d Mist:%d Blund:%d} black={Best:%d Exc:%d Good:%d Inacc:%d Mist:%d Blund:%d} worst_loss=%.1f worst_ply=%d phase_losses: opening=%.1f middlegame=%.1f endgame=%.1f" \
		$nPlies $wacc $bacc \
		[dict get $wc Best] [dict get $wc Excellent] [dict get $wc Good] [dict get $wc Inaccuracy] [dict get $wc Mistake] [dict get $wc Blunder] \
		[dict get $bc Best] [dict get $bc Excellent] [dict get $bc Good] [dict get $bc Inaccuracy] [dict get $bc Mistake] [dict get $bc Blunder] \
		$worstLoss $worstPly $openLoss $midLoss $endLoss]
}


proc ::gamereview::focusLabel {focus} {
	variable mc
	switch -- $focus {
		tactics    { return $mc::FocusTactics }
		opening    { return $mc::FocusOpening }
		conversion { return $mc::FocusConversion }
		endgame    { return $mc::FocusEndgame }
		solid      { return $mc::FocusSolid }
		default    { return $focus }
	}
}


# The classifier question for selective NAG annotation gating.
proc ::gamereview::symbolGateQuestion {} {
	return [dict create \
		type choice \
		instructions "When adding annotation symbols to this game, should minor inaccuracies (?!), mistakes (?), and blunders (??) all be annotated, or should symbols be restricted to critical mistakes and blunders to avoid cluttering notation?" \
		criteria [dict create \
			all_errors    "include inaccuracies (?!), mistakes (?), and blunders (??) because errors are sparse and informative" \
			critical_only "include only mistakes (?) and blunders (??); skip minor inaccuracies (?!) to prevent notation clutter" \
			skip          "do not add symbols; game is either error-free or already sufficiently annotated" \
		]]
}


# Deterministic fallback for symbol gating.
proc ::gamereview::symbolGateFallback {review} {
	set wc [dict get $review white counts]
	set bc [dict get $review black counts]
	set inacc [expr {[dict get $wc Inaccuracy] + [dict get $bc Inaccuracy]}]
	set mist [expr {[dict get $wc Mistake] + [dict get $bc Mistake]}]
	set blund [expr {[dict get $wc Blunder] + [dict get $bc Blunder]}]
	set totalErr [expr {$inacc + $mist + $blund}]
	if {$totalErr == 0} { return skip }

	set moves [dict get $review moves]
	set nMoves [expr {[llength $moves] / 2 + 1}]
	if {$inacc >= 6 && double($inacc) / $nMoves > 0.25} {
		return critical_only
	}
	return all_errors
}


proc ::gamereview::symbolGateState {review} {
	set nPlies [llength [dict get $review moves]]
	set wc [dict get $review white counts]
	set bc [dict get $review black counts]
	set inacc [expr {[dict get $wc Inaccuracy] + [dict get $bc Inaccuracy]}]
	set mist [expr {[dict get $wc Mistake] + [dict get $bc Mistake]}]
	set blund [expr {[dict get $wc Blunder] + [dict get $bc Blunder]}]
	set totalErr [expr {$inacc + $mist + $blund}]
	set density [expr {$nPlies > 0 ? double($totalErr) / $nPlies : 0.0}]
	return [format "plies=%d inaccuracies=%d mistakes=%d blunders=%d error_density=%.2f" \
		$nPlies $inacc $mist $blund $density]
}


# Asynchronously query System One for the review decisions (turning point,
# focus, symbol gate). Calls <script> with a dictionary of outcomes.
proc ::gamereview::judgeReviewAsync {review script} {
	set candidates [turningPointCandidates $review]
	lassign [turningPointEngine $review $candidates] engineTP close
	# Jev chooses the turning point only between close engine candidates
	set ask [expr {[llength $close] ? [candidatesTagged $candidates [list $engineTP {*}$close]] : {}}]
	set fbFocus [focusFallback $review]
	set fbGate [symbolGateFallback $review]

	set fallbackResult [dict create \
		ok 1 source rules \
		turning_point $engineTP turning_point_source engine \
		focus $fbFocus focus_source rules \
		symbol_gate $fbGate symbol_gate_source rules]

	if {[llength [info commands ::ai::systemone::enabled]] == 0
	 || ![::ai::systemone::enabled]
	 || ([llength [info commands ::ai::systemone::qualified]] && ![::ai::systemone::qualified review_turning_point])} {
		after 0 [list {*}$script $fallbackResult]
		return
	}

	set tpState [turningPointState $review [expr {[llength $ask] ? $ask : $candidates}]]
	set focusState [focusState $review]
	set gateState [symbolGateState $review]
	set state "review_summary: $focusState\n$tpState\n$gateState"

	set questions [dict create \
		review_focus [focusQuestion] \
		review_symbol_gate [symbolGateQuestion]]
	if {[llength $ask]} {
		dict set questions review_turning_point [turningPointQuestion $ask 0]
	}

	if {[catch {
		::ai::systemone::evaluateAsync $state $questions \
			[namespace code [list OnJudgeReply $script $ask $engineTP $review]]
	} err]} {
		after 0 [list {*}$script $fallbackResult]
	}
	return
}


proc ::gamereview::OnJudgeReply {script ask engineTP review result} {
	set fbTP $engineTP
	set fbFocus [focusFallback $review]
	set fbGate [symbolGateFallback $review]

	if {![dict exists $result ok] || ![dict get $result ok] || ![dict exists $result answers]} {
		uplevel #0 [list {*}$script [dict create ok 1 source rules \
			turning_point $fbTP turning_point_source engine \
			focus $fbFocus focus_source rules \
			symbol_gate $fbGate symbol_gate_source rules]]
		return
	}

	set answers [dict get $result answers]
	set qTP [turningPointQuestion $ask 0]
	set qFocus [focusQuestion]
	set qGate [symbolGateQuestion]

	set tp $fbTP
	set tpSrc engine
	set tpConf {}
	if {[llength $ask] && [dict exists $answers review_turning_point]} {
		set a [dict get $answers review_turning_point]
		set th [::ai::systemone::threshold review_turning_point 0.6]
		if {[::ai::systemone::valid $qTP $a] && [dict get $a confidence] >= $th} {
			set tp [dict get $a choice]
			set tpSrc classifier
			set tpConf [dict get $a confidence]
		}
	}

	set focus $fbFocus
	set focusSrc rules
	set focusConf {}
	if {[dict exists $answers review_focus]} {
		set a [dict get $answers review_focus]
		set th [::ai::systemone::threshold review_focus 0.6]
		if {[::ai::systemone::valid $qFocus $a] && [dict get $a confidence] >= $th} {
			set focus [dict get $a choice]
			set focusSrc classifier
			set focusConf [dict get $a confidence]
		}
	}

	set gate $fbGate
	set gateSrc rules
	set gateConf {}
	if {[dict exists $answers review_symbol_gate]} {
		set a [dict get $answers review_symbol_gate]
		set th [::ai::systemone::threshold review_symbol_gate 0.6]
		if {[::ai::systemone::valid $qGate $a] && [dict get $a confidence] >= $th} {
			set gate [dict get $a choice]
			set gateSrc classifier
			set gateConf [dict get $a confidence]
		}
	}

	set overallSource [expr {($tpSrc eq "classifier" || $focusSrc eq "classifier" || $gateSrc eq "classifier") ? "classifier" : "rules"}]

	uplevel #0 [list {*}$script [dict create \
		ok 1 source $overallSource \
		turning_point $tp turning_point_source $tpSrc turning_point_conf $tpConf \
		focus $focus focus_source $focusSrc focus_conf $focusConf \
		symbol_gate $gate symbol_gate_source $gateSrc symbol_gate_conf $gateConf]]
	return
}


# Synchronous bounded query for the review decisions.
proc ::gamereview::judgeReviewSync {review args} {
	set candidates [turningPointCandidates $review]
	lassign [turningPointEngine $review $candidates] engineTP close
	set ask [expr {[llength $close] ? [candidatesTagged $candidates [list $engineTP {*}$close]] : {}}]
	set fbFocus [focusFallback $review]
	set fbGate [symbolGateFallback $review]

	set out [dict create ok 1 source rules \
		turning_point $engineTP turning_point_source engine \
		focus $fbFocus focus_source rules \
		symbol_gate $fbGate symbol_gate_source rules]

	if {[llength [info commands ::ai::systemone::chooseManySync]] == 0
	 || ![::ai::systemone::enabled]
	 || ([llength [info commands ::ai::systemone::qualified]] && ![::ai::systemone::qualified review_turning_point])} {
		return $out
	}

	set tpState [turningPointState $review [expr {[llength $ask] ? $ask : $candidates}]]
	set focusState [focusState $review]
	set gateState [symbolGateState $review]
	set state "review_summary: $focusState\n$tpState\n$gateState"

	set questions [dict create \
		review_focus [focusQuestion] \
		review_symbol_gate [symbolGateQuestion]]
	if {[llength $ask]} {
		dict set questions review_turning_point [turningPointQuestion $ask 0]
	}

	set chosen [::ai::systemone::chooseManySync review_turning_point $state $questions {*}$args]
	if {[dict exists $chosen review_turning_point]} {
		dict set out turning_point [dict get $chosen review_turning_point]
		dict set out turning_point_source classifier
		dict set out source classifier
	}
	if {[dict exists $chosen review_focus]} {
		dict set out focus [dict get $chosen review_focus]
		dict set out focus_source classifier
		dict set out source classifier
	}
	if {[dict exists $chosen review_symbol_gate]} {
		dict set out symbol_gate [dict get $chosen review_symbol_gate]
		dict set out symbol_gate_source classifier
		dict set out source classifier
	}
	return $out
}


# ======================================================================
# The run.
# ======================================================================

# Analyse the current game's mainline at a fixed depth per position and
# show the review window. Reuses ::ai::engine::classify for the engine
# facts; a progress dialog with Cancel is shown while it works.
proc ::gamereview::run {parent args} {
	variable Priv
	variable Options
	variable MaxPlies
	variable mc

	array set opts [list -depth $Options(depth) -done {}]
	array set opts $args

	if {$Priv(running)} { return 0 }
	if {[llength [info commands ::ai::engine::available]] == 0
	 || ![::ai::engine::available]} {
		::dialog::info -parent $parent -message $mc::NoEngine
		return 0
	}
	if {[catch { set plies [::scidb::game::query mainline] }] || ![llength $plies]} {
		::dialog::info -parent $parent -message $mc::NoGame
		return 0
	}
	if {[llength $plies] > $MaxPlies} {
		set plies [lrange $plies 0 [expr {$MaxPlies - 1}]]
	}

	set Priv(running) 1
	set Priv(cancel) 0
	set Priv(plies) $plies
	set Priv(index) 0
	set Priv(total) [llength $plies]
	set Priv(depth) $opts(-depth)
	set Priv(done) $opts(-done)
	set Priv(parent) $parent
	set Priv(results) {}
	set Priv(rows) {}
	catch { set Priv(savedKey) [::scidb::game::position key] }

	ShowProgress $parent
	after 50 [namespace code NextPly]
	return 1
}


proc ::gamereview::cancel {} {
	variable Priv
	if {!$Priv(running)} { return 0 }
	set Priv(cancel) 1
	return 1
}


proc ::gamereview::NextPly {} {
	variable Priv
	variable mc

	if {!$Priv(running)} { return }
	if {$Priv(cancel) || $Priv(index) >= $Priv(total)} {
		Finish
		return
	}

	lassign [lindex $Priv(plies) $Priv(index)] key san fen
	incr Priv(index)

	Progress [format $mc::Reviewing $Priv(index) $Priv(total) $san]
	update idletasks

	set side [expr {($Priv(index) - 1) % 2 == 0 ? "White" : "Black"}]

	if {[catch { ::ai::engine::classify $fen $san -depth $Priv(depth) } result]} {
		lappend Priv(results) [list error $san $key $fen $result]
		after 1 [namespace code NextPly]
		return
	}

	set before   [dict get $result evalBeforeCp]
	set after    [dict get $result evalAfterCp]
	set uci      [dict get $result uci]
	set bestMove [dict get $result bestMove]
	set best     [expr {$uci eq $bestMove}]

	# the better move, as SAN, for the mistakes list
	set bestSan ""
	if {$bestMove ne "" && $bestMove ne $uci} {
		if {![catch { ::scidb::ai::moveFacts $bestMove $fen } facts]
		 && [regexp {"san":"([^"]+)"} $facts -> bs]} { set bestSan $bs }
	}

	lappend Priv(results) [list ok [dict create \
		san $san key $key uci $uci bestMove $bestMove bestSan $bestSan \
		best $best before $before after $after side $side fen $fen]]

	after 1 [namespace code NextPly]
}


proc ::gamereview::Finish {} {
	variable Priv
	variable mc

	set Priv(running) 0
	if {[info exists Priv(dialog)] && [winfo exists $Priv(dialog)]} {
		destroy $Priv(dialog)
	}
	# put the board back where the user left it
	if {[info exists Priv(savedKey)] && [string length $Priv(savedKey)]} {
		catch { ::scidb::game::go key $Priv(savedKey) }
		set Priv(savedKey) {}
	}

	set plies {}
	set errors {}
	foreach r $Priv(results) {
		if {[lindex $r 0] eq "ok"} {
			lappend plies [lindex $r 1]
		} else {
			lappend errors [lrange $r 1 end]
		}
	}
	set review [classify $plies]
	set cancelled $Priv(cancel)
	set done $Priv(done)
	set parent $Priv(parent)
	set Priv(done) {}

	if {[winfo exists $parent]} {
		ShowWindow $parent $review $errors $cancelled
	}
	if {[llength $done]} {
		catch { {*}$done [dict create review $review errors $errors \
			cancelled $cancelled plies [llength $plies]] }
	}
	return
}


proc ::gamereview::Progress {text} {
	variable Priv
	if {[info exists Priv(bar)] && [winfo exists $Priv(bar)]} {
		$Priv(bar) configure -value $Priv(index)
	}
	if {[info exists Priv(status)] && [winfo exists $Priv(status)]} {
		$Priv(status) configure -text $text
	}
	update idletasks
}


proc ::gamereview::ShowProgress {parent} {
	variable Priv
	variable mc

	set dlg "$parent.__gamereview_progress"
	if {[winfo exists $dlg]} { destroy $dlg }
	if {![winfo exists [winfo toplevel $parent]]} { return }
	toplevel $dlg -class Scidb
	wm title $dlg $mc::Title
	wm transient $dlg [winfo toplevel $parent]

	set top [ttk::frame $dlg.top]
	pack $top -fill both -expand yes -padx $::theme::padx -pady $::theme::pady
	ttk::label $top.label -text $mc::Title
	pack $top.label -anchor w
	set bar [ttk::progressbar $top.bar -mode determinate -maximum $Priv(total)]
	pack $top.bar -fill x -pady [list $::theme::pady 0]
	ttk::label $top.status -text ""
	pack $top.status -anchor w -pady [list $::theme::pady 0]
	ttk::button $top.cancel -text $mc::Cancel -command [namespace code cancel]
	pack $top.cancel -anchor e -pady [list $::theme::pady 0]

	set Priv(dialog) $dlg
	set Priv(bar) $bar
	set Priv(status) $top.status
	::util::place::besideBoard $dlg $parent
	update idletasks
}


# "12." for White's move, "12..." for Black's.
proc ::gamereview::moveLabel {move} {
	set ply [dict get $move ply]
	set num [expr {$ply / 2 + 1}]
	if {[dict get $move side] eq "White"} { return "$num." }
	return "$num..."
}


proc ::gamereview::summaryLine {side summary} {
	variable mc
	set counts [dict get $summary counts]
	set parts {}
	foreach c {Best Excellent Good Inaccuracy Mistake Blunder} {
		if {[dict get $counts $c] > 0} {
			lappend parts "[set mc::$c] [dict get $counts $c]"
		}
	}
	set text [format "%s: %s%%" [set mc::$side] [dict get $summary accuracy]]
	if {[llength $parts]} { append text " \u2014 [join $parts {, }]" }
	return $text
}


proc ::gamereview::PopulateListbox {lb review {turningPointTag ""}} {
	variable Priv
	variable mc

	$lb delete 0 end
	set rows {}
	foreach m [dict get $review moves] {
		set cls [dict get $m class]
		if {$cls ni {Inaccuracy Mistake Blunder}} { continue }
		set tag "ply_[dict get $m ply]"
		set isTP [expr {$tag eq $turningPointTag}]
		set prefix [expr {$isTP ? "\[$mc::TurningPoint\] " : ""}]
		set text "$prefix[moveLabel $m] [dict get $m san] \u2014 $cls"
		if {[dict exists $m bestSan] && [dict get $m bestSan] ne ""} {
			append text " ($mc::BetterMove [dict get $m bestSan])"
		}
		$lb insert end $text
		set key [expr {[dict exists $m key] ? [dict get $m key] : ""}]
		lappend rows [list $key $text]
	}
	if {![llength $rows]} {
		$lb insert end $mc::NoKeyMoves
	}
	set Priv(rows) $rows
}


proc ::gamereview::OnJudged {dlg lb focusLabel result} {
	variable Priv
	variable mc

	if {![winfo exists $dlg]} { return }
	if {![dict exists $result ok] || ![dict get $result ok]} { return }

	if {[dict exists $result turning_point]} {
		set Priv(turning_point) [dict get $result turning_point]
	}
	if {[dict exists $result focus]} {
		set Priv(focus) [dict get $result focus]
	}
	if {[dict exists $result symbol_gate]} {
		set Priv(symbol_gate) [dict get $result symbol_gate]
	}

	set ftext "$mc::Focus: [focusLabel $Priv(focus)]"
	if {[dict exists $result focus_source] && [dict get $result focus_source] eq "classifier"} {
		if {[dict exists $result focus_conf] && [dict get $result focus_conf] ne ""} {
			set pct [expr {int([dict get $result focus_conf] * 100)}]
			append ftext " ([::ai::systemone::describe], $pct%)"
		}
	}
	$focusLabel configure -text $ftext

	PopulateListbox $lb $Priv(review) $Priv(turning_point)
}


proc ::gamereview::ShowWindow {parent review errors cancelled} {
	variable Priv
	variable mc

	set dlg "$parent.__gamereview"
	if {[winfo exists $dlg]} { destroy $dlg }
	toplevel $dlg -class Scidb
	wm title $dlg $mc::Title
	wm transient $dlg [winfo toplevel $parent]
	wm protocol $dlg WM_DELETE_WINDOW [list destroy $dlg]

	set top [ttk::frame $dlg.top]
	pack $top -fill both -expand yes -padx $::theme::padx -pady $::theme::pady

	ttk::label $top.white -text [summaryLine White [dict get $review white]] -anchor w
	pack $top.white -fill x
	ttk::label $top.black -text [summaryLine Black [dict get $review black]] -anchor w
	pack $top.black -fill x

	set candidates [turningPointCandidates $review]
	set fbTP [turningPointFallback $candidates]
	set fbFocus [focusFallback $review]
	set fbGate [symbolGateFallback $review]

	set Priv(turning_point) $fbTP
	set Priv(focus) $fbFocus
	set Priv(symbol_gate) $fbGate
	set Priv(review) $review

	ttk::label $top.focus -text "$mc::Focus: [focusLabel $fbFocus]" -anchor w
	pack $top.focus -fill x -pady [list $::theme::pady 0]

	if {[llength $errors]} {
		ttk::label $top.err -text [join $errors "\n"] -anchor w -wraplength 420
		pack $top.err -fill x -pady [list $::theme::pady 0]
	}

	ttk::label $top.head -text $mc::KeyMoves -anchor w
	pack $top.head -fill x -pady [list $::theme::pady 0]

	set frame [ttk::frame $top.list]
	# 54 columns keep the dialog inside a strip beside a board-only pane
	# at 1000x600, so no control is squeezed (VAL-DLG-016).
	set lb [listbox $frame.list -height 10 -width 54 -exportselection false]
	set vs [ttk::scrollbar $frame.vs -orient vertical -command [list $lb yview]]
	$lb configure -yscrollcommand [list $vs set]
	pack $lb -side left -fill both -expand yes
	pack $vs -side right -fill y
	pack $frame -fill both -expand yes

	PopulateListbox $lb $review $fbTP
	bind $lb <<ListboxSelect>> [namespace code [list GoTo $lb]]

	set buttons [ttk::frame $top.buttons]
	ttk::button $buttons.add -text $mc::AddSymbols \
		-command [namespace code [list AddSymbols [dict get $review moves] $dlg]]
	ttk::button $buttons.close -text $mc::Close -command [list destroy $dlg]
	pack $buttons.add -side left
	pack $buttons.close -side left -padx [list $::theme::padx 0]
	pack $buttons -fill x -pady [list $::theme::pady 0]

	judgeReviewAsync $review [namespace code [list OnJudged $dlg $lb $top.focus]]

	::util::place::besideBoard $dlg $parent
}


# Clicking a mistake row steps the board to that move.
proc ::gamereview::GoTo {lb} {
	variable Priv
	set idx [$lb curselection]
	if {$idx eq "" || $idx >= [llength $Priv(rows)]} { return }
	set key [lindex [lindex $Priv(rows) $idx] 0]
	if {[string length $key]} {
		catch { ::scidb::game::go key $key }
	}
}


# Write the NAGs (?!, ?, ??) onto the game's non-good moves, merging with
# any marks already there. The game is left *modified*; saving stays the
# user's decision.
proc ::gamereview::AddSymbols {moves {dlg {}} {gate ""}} {
	variable Priv
	variable mc

	if {$gate eq ""} {
		set gate [expr {[info exists Priv(symbol_gate)] ? $Priv(symbol_gate) : "all_errors"}]
	}
	if {$gate eq "skip"} {
		if {[string length $dlg] && [winfo exists $dlg]} {
			::dialog::info -parent $dlg -message [format $mc::AddedSymbols 0]
		}
		return 0
	}

	set added 0
	foreach m $moves {
		set cls [dict get $m class]
		if {$gate eq "critical_only" && $cls eq "Inaccuracy"} {
			continue
		}
		set nag [nagFor $cls]
		if {![string length $nag]} { continue }
		if {![dict exists $m key]} { continue }
		set key [dict get $m key]
		set existing ""
		catch { set existing [::scidb::game::query marks $key] }
		catch { ::scidb::game::update annotation $key [mergeNags $existing $nag] }
		incr added
	}
	if {[string length $dlg] && [winfo exists $dlg]} {
		::dialog::info -parent $dlg -message [format $mc::AddedSymbols $added]
	}
	return $added
}


proc ::gamereview::WriteOptions {chan} {
	::options::writeItem $chan [namespace current]::Options
}

::options::hookWriter ::gamereview::WriteOptions

# vi:set ts=3 sw=3:
