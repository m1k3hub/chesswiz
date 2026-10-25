# ======================================================================
# Guess the Move -- replay the game on the board and guess each move of
# one side; Chesswiz scores the guesses.
#
# The board's context menu ("Guess the Move...") or the Extras menu
# starts a round on the game currently on the board, from the current
# position. While a round is active a small training window shows the
# score, the verdict of the last guess and the buttons Hint (flashes the
# from-square of the game move for two seconds), Show Move (counts as a
# miss) and Stop. The notation keeps the moves already played visible;
# the following ones stay hidden because the round's own stepping is the
# only way the position advances. At the end of the game or after Stop
# the window shows the final score.
#
# Moves played on the board never reach the game while a round runs:
# ::move::addMove passes them to ::guessmove::guessed instead (the hook
# checks $::guessmove::active). A right guess scores one point; either
# way the game is stepped over the real move and over the opponent's
# reply, so it is the user's turn again.
#
#   ::guessmove::start ?side?    side is white|black|auto (side to move)
#   ::guessmove::stop
#
# System One (Jev) typed judgments (through ::ai::decide / ::ai::systemone):
#   1. guess_hint     (choice) -- conceptual coaching cue when Hint is pressed,
#                                 from position and move-delta facts without
#                                 naming the target move or square.
#   2. guess_feedback (choice) -- engine-first explanation theme when a guess
#                                 differs from the game move: ::ai::engine::evaluate
#                                 evaluates both resulting positions and
#                                 deterministically decides the verdict from
#                                 win-probability loss (close_alternative <= 3,
#                                 slightly_worse 3..15, worse >= 15); Jev only
#                                 chooses the wording/theme (tactics, material,
#                                 king_safety, development, structure) among
#                                 themes consistent with the engine's verdict
#                                 and C++/engine facts.
#   3. guess_review   (score)  -- end-of-round assessment over ordered levels
#                                 {needs_study steady sharp master_like} from
#                                 accuracy, hints/reveals, phase split and miss
#                                 verdicts.
#
# Firewall: whether a guess matches the game move, the score, the engine's
# close_alternative / slightly_worse / worse verdict, and the board's
# from-square highlight are hard facts that a model never overrides. When no
# engine is available, or when the classifier is off, unreachable, abstains or
# is below threshold, deterministic rules run and the UI behaves identically
# to before.
#
# tests/test_app_guess_move.tcl drives a round with stubbed guesses.
# ======================================================================

::util::source guess-move

namespace eval ::guessmove {
namespace eval mc {

set Title			"Guess the Move"
set GuessTheMove	"Guess the Move..."
set SideGuessing	"You are guessing the moves of %s."
set White			"White"
set Black			"Black"
set Score			"Score: %d of %d"
set Correct			"Correct"
set NotTheGameMove	"Not the game move (%s)"
set MoveWas			"The move was %s"
set Summary			"%d of %d moves guessed (%d%%)"
set Hint			"Hint"
set ShowMove		"Show Move"
set Stop			"Stop"
set Close			"Close"
set NoMoves			"Load a game and step back from its end before starting Guess the Move."

set HintNotes [dict create \
	development	"Hint: develop a piece and bring it into the game." \
	king_safety	"Hint: look at king safety -- castling, shelter, or the enemy king." \
	tactics		"Hint: look for a tactical blow -- a check, pin, fork, or loose piece." \
	material	"Hint: look for a favourable capture or exchange." \
	structure	"Hint: fight for the centre, open files, or better pawn structure." \
	endgame		"Hint: activate the king or work with a passed pawn." \
]

set FeedbackNotes [dict create \
	close_alternative [dict create \
		development	"%s is about as good as %s (a close developing alternative)." \
		king_safety	"%s is about as good as %s (a close alternative for king safety)." \
		structure	"%s is about as good as %s (a close positional alternative)." \
		default		"%s is about as good as the game move %s." \
	] \
	slightly_worse [dict create \
		tactics		"%s is slightly worse than %s and overlooks a tactical idea." \
		material	"%s is slightly worse than %s and concedes material." \
		king_safety	"%s is slightly worse than %s for king safety." \
		development	"%s is slightly worse than %s, delaying development." \
		structure	"%s is slightly worse than %s for the centre or pawn structure." \
		default		"%s is slightly worse than the game move %s." \
	] \
	worse [dict create \
		tactics		"%s is worse than %s and misses a tactical blow." \
		material	"%s is worse than %s and loses material." \
		king_safety	"%s is worse than %s, leaving the king exposed." \
		development	"%s is worse than %s, falling behind in development." \
		structure	"%s is worse than %s, weakening the position's structure." \
		default		"%s is worse than the game move %s." \
	] \
]

set ReviewNotes [dict create \
	needs_study	"Assessment: needs study -- replay the key moments and check the tactical misses." \
	steady		"Assessment: steady round -- solid grasp of the game's main ideas." \
	sharp		"Assessment: sharp round -- found most of the game's critical moves." \
	master_like	"Assessment: master-like round -- matched the game moves with high precision." \
]

} ;# namespace mc

variable active 0
variable HintTime 2000

variable HintThreshold 0.6
variable FeedbackThreshold 0.6
variable ReviewThreshold 0.6
variable FeedbackDepth 10
variable FeedbackEngineTimeout 2500

variable HintCriteria [dict create \
	development	"develop a minor piece from its starting square or connect the rooks" \
	king_safety	"castle, shelter the king, or launch a direct attack against an exposed enemy king" \
	tactics		"execute or meet a tactical threat: check, mate, fork, pin, skewer, discovered attack, or hanging piece" \
	material	"win material with a favourable capture or exchange" \
	structure	"improve the pawn structure, fight for the centre, or contest an open file" \
	endgame		"activate the king, advance or blockade a passed pawn, or simplify in the endgame" \
]

variable FeedbackCriteria [dict create \
	tactics		"the engine's PV and evaluation swing show a tactical refutation or missed tactical blow (check, mate, fork, pin, discovered attack, removing a defender)" \
	material	"the C++ exchange facts (seeCp/losesMaterial) and engine evaluation show the guess loses material or misses winning material" \
	king_safety	"the game move castles, shelters the king, or handles king safety better than the guess" \
	development	"the game move develops a piece or activates pieces more effectively than the guess" \
	structure	"the game move fights for the centre, open files, or better pawn structure compared with the guess" \
]

variable ReviewLevels {needs_study steady sharp master_like}

array set Priv {
	side			white
	score			0
	total			0
	last			{}
	summary			{}
	dialog			{}
	hint			{}
	hintSquare		-1
	hintsUsed		0
	showsUsed		0
	turnHinted		0
	history			{}
	hintKind		{}
	hintSource		{}
	verdict			{}
	feedbackVerdict	{}
	feedbackLoss	{}
	feedbackTheme	{}
	feedback		{}
	feedbackSource	{}
	review			{}
	reviewSource	{}
	note			{}
	turnSeq			0
	hintSeq			0
	feedbackSeq		0
	reviewSeq		0
}

} ;# namespace guessmove


# Start a round on the board's game from the current position; <side> is
# white, black or auto (the side to move). Returns whether the round
# started.
proc ::guessmove::start {{side auto}} {
	variable Priv
	variable active
	variable mc

	if {$active} { stop }
	if {[::application::pgn::empty?] || [::scidb::game::position atEnd?]} {
		::dialog::info -parent .application -message $mc::NoMoves
		return 0
	}
	switch -- $side {
		white	{ set side white }
		black	{ set side black }
		auto	{ set side [::scidb::game::query stm] }
		default	{ error "usage: ::guessmove::start ?white|black|auto?" }
	}

	incr Priv(turnSeq)
	incr Priv(hintSeq)
	incr Priv(feedbackSeq)
	incr Priv(reviewSeq)
	array set Priv [list \
		side			$side \
		score			0 \
		total			0 \
		last			{} \
		summary			{} \
		hint			{} \
		hintSquare		-1 \
		hintsUsed		0 \
		showsUsed		0 \
		turnHinted		0 \
		history			{} \
		hintKind		{} \
		hintSource		{} \
		verdict			{} \
		feedbackVerdict	{} \
		feedbackLoss	{} \
		feedbackTheme	{} \
		feedback		{} \
		feedbackSource	{} \
		review			{} \
		reviewSource	{} \
		note			{} \
	]
	set active 1
	::application::switchTab board
	BuildWindow .application
	Advance
	return 1
}


# End the round; the window stays up with the final score until Close.
proc ::guessmove::stop {} {
	variable Priv
	variable active

	incr Priv(hintSeq)
	incr Priv(feedbackSeq)
	if {$active} {
		Finish
	} elseif {[winfo exists $Priv(dialog)]} {
		destroy $Priv(dialog)
	}
}


# The ::move::addMove hook: the played move is a guess on the game move of
# the user's side; the game itself is not changed. The round's stepping
# always leaves the position on the user's turn (or at the end of the
# game), so anything played while another side is to move is ignored.
proc ::guessmove::guessed {san} {
	variable Priv
	variable active
	variable mc

	if {!$active} { return "" }
	if {[::scidb::game::query stm] ne $Priv(side)} { return "" }
	set move [GameMove]
	if {$move eq ""} { Finish; return "" }
	set fen [CurrentFen]
	set phase [PositionPhase $fen]
	set hinted $Priv(turnHinted)
	set Priv(turnHinted) 0
	ClearHint
	incr Priv(turnSeq)
	set tseq $Priv(turnSeq)
	set Priv(note) {}
	incr Priv(total)
	if {$san eq $move} {
		incr Priv(score)
		set Priv(last) $mc::Correct
		set Priv(verdict) exact
		set Priv(feedbackVerdict) exact
		set Priv(feedbackLoss) 0.0
		set Priv(feedbackTheme) correct
		set Priv(feedback) correct
		set Priv(feedbackSource) rules
		lappend Priv(history) [dict create \
			ply $Priv(total) phase $phase guess $san move $move \
			outcome correct hint $hinted verdict exact feedback correct]
		::application::board::goto +1
		Advance
	} else {
		set Priv(last) [format $mc::NotTheGameMove $move]
		set ruleFb [feedbackRule $fen $san $move]
		set Priv(verdict) {}
		set Priv(feedbackVerdict) {}
		set Priv(feedbackLoss) {}
		set Priv(feedbackTheme) $ruleFb
		set Priv(feedback) $ruleFb
		set Priv(feedbackSource) rules
		lappend Priv(history) [dict create \
			ply $Priv(total) phase $phase guess $san move $move \
			outcome miss hint $hinted verdict {} feedback $ruleFb]
		set idx [expr {[llength $Priv(history)] - 1}]
		incr Priv(feedbackSeq)
		set fseq $Priv(feedbackSeq)
		::application::board::goto +1
		Advance
		after 0 [namespace code [list GuardedDecideFeedback $fseq $tseq $idx $fen $san $move]]
	}
	return ""
}


proc ::guessmove::GuardedDecideFeedback {fseq tseq idx fen guessSan gameSan} {
	variable Priv

	if {$fseq != $Priv(feedbackSeq)} { return }
	decideFeedback $fen $guessSan $gameSan \
		[namespace code [list OnFeedbackDecided $fseq $tseq $idx $guessSan $gameSan]]
}


# Flash the from-square of the game move for HintTime milliseconds, and
# ask the System One classifier for a conceptual coaching cue.
proc ::guessmove::hint {} {
	variable Priv
	variable active
	variable HintTime

	if {!$active} { return }
	set move [GameMove]
	if {$move eq ""} { return }
	set square [fromSquare $move]
	if {$square < 0} { return }
	set fen [CurrentFen]
	ClearHint
	::board::diagram::hilite $::application::board::board $square suggested
	set Priv(hintSquare) $square
	set Priv(hint) [after $HintTime [namespace code ClearHint]]
	set Priv(turnHinted) 1
	incr Priv(hintsUsed)
	set Priv(hintKind) [hintRule $fen $move]
	set Priv(hintSource) rules
	incr Priv(hintSeq)
	set hseq $Priv(hintSeq)
	set tseq $Priv(turnSeq)
	decideHint $fen $move [namespace code [list OnHintDecided $hseq $tseq]]
}


# Reveal the game move; it counts as a miss.
proc ::guessmove::showMove {} {
	variable Priv
	variable active
	variable mc

	if {!$active} { return }
	set move [GameMove]
	if {$move eq ""} { return }
	set fen [CurrentFen]
	set phase [PositionPhase $fen]
	set hinted $Priv(turnHinted)
	set Priv(turnHinted) 0
	ClearHint
	incr Priv(turnSeq)
	set Priv(note) {}
	incr Priv(total)
	incr Priv(showsUsed)
	set Priv(last) [format $mc::MoveWas $move]
	lappend Priv(history) [dict create \
		ply $Priv(total) phase $phase guess "" move $move \
		outcome show hint $hinted feedback revealed]
	::application::board::goto +1
	Advance
}


# The from-square (0..63) of the legal move whose SAN is <san>; -1 if the
# SAN cannot be found (an unusual promotion, for instance).
proc ::guessmove::fromSquare {san} {
	for {set from 0} {$from < 64} {incr from} {
		for {set to 0} {$to < 64} {incr to} {
			if {$from == $to} { continue }
			if {![::scidb::pos::legal? $from $to no]} { continue }
			set s [::scidb::pos::san $from $to]
			if {$s eq $san} { return $from }
			# promotions: san tried the queen, match the other pieces too
			if {[string first = $s] >= 0} {
				foreach p {r b n} {
					if {[::scidb::pos::san $from $to $p] eq $san} { return $from }
				}
			}
		}
	}
	return -1
}


# ----------------------------------------------------------------------
# System One (Jev) typed judgments and deterministic fallbacks.
# ----------------------------------------------------------------------

proc ::guessmove::HintQuestion {} {
	variable HintCriteria
	return [dict create type choice \
		instructions "Which conceptual coaching hint best nudges the player toward the game move in this position without giving away the move itself?" \
		criteria $HintCriteria]
}


# Build the guess_feedback question restricted to the themes consistent with
# the engine's verdict and facts.
proc ::guessmove::FeedbackQuestion {{verdict worse} {themes ""}} {
	variable FeedbackCriteria

	if {$themes eq ""} {
		if {$verdict eq "close_alternative"} {
			set themes {development king_safety structure}
		} else {
			set themes {tactics material king_safety development structure}
		}
	}
	set crit [dict create]
	foreach t $themes {
		if {[dict exists $FeedbackCriteria $t]} {
			dict set crit $t [dict get $FeedbackCriteria $t]
		}
	}
	switch -- $verdict {
		close_alternative {
			set instr "The chess engine evaluated the guessed move as a close_alternative (about as good as the game move). Without calling the guess a mistake, which positional theme best explains how the game move's plan differs from the guess?"
		}
		slightly_worse {
			set instr "The chess engine evaluated the guessed move as slightly_worse than the game move. Which theme consistent with the engine's verdict best explains why the game move is slightly better?"
		}
		default {
			set instr "The chess engine evaluated the guessed move as worse than the game move. Which theme consistent with the engine's verdict best explains why the guess is worse than the game move?"
		}
	}
	return [dict create type choice instructions $instr criteria $crit]
}


proc ::guessmove::ReviewQuestion {} {
	variable ReviewLevels
	return [dict create type score \
		instructions "Rate this Guess-the-Move training session from needs_study (low accuracy, tactical blunders, or heavy reliance on hints and reveals) through steady and sharp to master_like (high accuracy across phases with little or no help)." \
		criteria $ReviewLevels]
}


proc ::guessmove::describeHint {label} {
	variable mc
	return [expr {[dict exists $mc::HintNotes $label] ? [dict get $mc::HintNotes $label] : ""}]
}


# Format the coaching explanation from the engine's verdict (close_alternative,
# slightly_worse, worse) and the chosen theme (tactics, material, king_safety,
# development, structure). Accepts either:
#   describeFeedback <verdict> <theme> <guessSan> <gameSan>
#   describeFeedback <verdictOrTheme> <guessSan> <gameSan>
proc ::guessmove::describeFeedback {verdict args} {
	variable mc

	if {[llength $args] == 2} {
		lassign $args guessSan gameSan
		set theme default
		if {[string first : $verdict] >= 0} {
			lassign [split $verdict :] verdict theme
		} elseif {![dict exists $mc::FeedbackNotes $verdict]} {
			set theme $verdict
			set verdict worse
		}
	} elseif {[llength $args] == 3} {
		lassign $args theme guessSan gameSan
	} else {
		error "usage: ::guessmove::describeFeedback verdict ?theme? guessSan gameSan"
	}
	if {![dict exists $mc::FeedbackNotes $verdict]} { return "" }
	set byTheme [dict get $mc::FeedbackNotes $verdict]
	if {[dict exists $byTheme $theme]} {
		set fmt [dict get $byTheme $theme]
	} elseif {[dict exists $byTheme default]} {
		set fmt [dict get $byTheme default]
	} else {
		return ""
	}
	return [format $fmt $guessSan $gameSan]
}


proc ::guessmove::describeReview {label} {
	variable mc
	return [expr {[dict exists $mc::ReviewNotes $label] ? [dict get $mc::ReviewNotes $label] : ""}]
}


# Lichess win-probability in [0,100] from centipawns (or #N mate marker)
# from the mover's perspective. Delegates to ::gamereview::wp when loaded.
proc ::guessmove::wp {score} {
	if {[llength [info commands ::gamereview::wp]]} {
		return [::gamereview::wp $score]
	}
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


# Win-probability loss of the guess (<guessCp>) against the game move (<gameCp>),
# both from the mover's perspective. Never negative.
proc ::guessmove::wpLoss {gameCp guessCp} {
	set l [expr {[wp $gameCp] - [wp $guessCp]}]
	if {$l < 0.0} { set l 0.0 }
	return $l
}


# Deterministic engine verdict from win-probability loss:
#   loss <= 3  -> close_alternative
#   loss >= 15 -> worse
#   between    -> slightly_worse
proc ::guessmove::engineVerdict {loss} {
	if {$loss <= 3.0} { return close_alternative }
	if {$loss >= 15.0} { return worse }
	return slightly_worse
}


# Extract mover-perspective centipawns from an ::ai::engine::evaluate dict
# on a resulting position (where the opponent is side to move).
proc ::guessmove::EvalMoverCp {evalDict {isMate 0}} {
	if {[dict exists $evalDict cpl]} {
		set cp [expr {-[dict get $evalDict cpl]}]
	} elseif {[dict exists $evalDict kind] && [dict exists $evalDict value]} {
		if {[dict get $evalDict kind] eq "mate"} {
			set v [dict get $evalDict value]
			set oppCp [expr {$v > 0 ? 10000 - 10 * $v : -10000 - 10 * $v}]
			set cp [expr {-$oppCp}]
		} else {
			set cp [expr {-[dict get $evalDict value]}]
		}
	} elseif {[dict exists $evalDict score]} {
		set cp [expr {-[dict get $evalDict score]}]
	} else {
		set cp 0
	}
	if {$isMate && $cp < 9900} { set cp 10000 }
	return $cp
}


# Evaluate the resulting positions of <guessSan> and <gameSan> from <fen>
# with ::ai::engine::evaluate, compute the win-probability loss and the
# deterministic engine verdict, and filter the candidate themes consistent
# with the verdict, C++ material facts, and engine PV/eval swing.
proc ::guessmove::evaluateFeedback {fen guessSan gameSan} {
	variable FeedbackDepth
	variable FeedbackEngineTimeout

	if {[llength [info commands ::ai::engine::evaluate]] == 0} {
		return [dict create ok 0]
	}
	set pf [PosFacts $fen]
	set gmf [MoveFacts $fen $guessSan]
	set tmf [MoveFacts $fen $gameSan]
	set guessFen [Fact $gmf fenAfter]
	set gameFen  [Fact $tmf fenAfter]
	if {$guessFen eq "" || $gameFen eq ""} {
		return [dict create ok 0]
	}
	if {[catch {
		set guessEval [::ai::engine::evaluate $guessFen -depth $FeedbackDepth -timeout $FeedbackEngineTimeout]
		set gameEval  [::ai::engine::evaluate $gameFen  -depth $FeedbackDepth -timeout $FeedbackEngineTimeout]
	}]} {
		return [dict create ok 0]
	}

	set side [expr {[Fact $pf sideToMove] ne "" ? [Fact $pf sideToMove] : "white"}]
	set opp  [expr {$side eq "white" ? "black" : "white"}]

	set guessCp [EvalMoverCp $guessEval [Bool [Fact $gmf mate]]]
	set gameCp  [EvalMoverCp $gameEval  [Bool [Fact $tmf mate]]]
	set loss    [wpLoss $gameCp $guessCp]
	set cpLoss  [expr {$gameCp - $guessCp}]
	if {$cpLoss < 0} { set cpLoss 0 }
	set verdict [engineVerdict $loss]

	set guessPv [expr {[dict exists $guessEval pv] ? [dict get $guessEval pv] : {}}]
	set gamePv  [expr {[dict exists $gameEval pv]  ? [dict get $gameEval pv]  : {}}]

	set gSee [Fact $gmf seeCp]
	set gMatDelta [expr {[Fact $gmf materialChangeCp] ne "" ? [Fact $gmf materialChangeCp] : 0}]
	set gLoses [expr {
		[Bool [Fact $gmf losesMaterial]]
		|| ($gSee ne "" && $gSee ne "null" && $gSee < 0)
		|| $gMatDelta < 0
		|| [llength [Fact $gmf newEnPrise $side]] > 0
	}]
	set tSee [Fact $tmf seeCp]
	set tMatDelta [expr {[Fact $tmf materialChangeCp] ne "" ? [Fact $tmf materialChangeCp] : 0}]
	set tWins [expr {
		[Bool [Fact $tmf capture]] && ![Bool [Fact $tmf mate]] && ![Bool [Fact $tmf losesMaterial]]
		&& (($tSee ne "" && $tSee ne "null" && $tSee > 0) || $tMatDelta > 0)
	}]
	set cppMaterial [expr {$gLoses || ($tWins && ![Bool [Fact $gmf capture]])}]

	set hasMate [expr {
		[Bool [Fact $tmf mate]] || [Bool [Fact $gmf mate]]
		|| abs($gameCp) >= 9900 || abs($guessCp) >= 9900
		|| ([dict exists $gameEval kind]  && [dict get $gameEval kind]  eq "mate")
		|| ([dict exists $guessEval kind] && [dict get $guessEval kind] eq "mate")
	}]
	set cppTactic [expr {
		[Bool [Fact $tmf mate]] || [Bool [Fact $tmf check]]
		|| [llength [Fact $tmf discoveredAttacks]] > 0
		|| [llength [Fact $tmf removesDefender]] > 0
		|| [llength [Fact $tmf newPins $opp]] > 0
	}]

	if {$verdict eq "close_alternative"} {
		set materialFact 0
		set tacticalFact 0
		set themes {development king_safety structure}
	} else {
		set materialFact [expr {$cppMaterial || $cpLoss >= 100}]
		set tacticalFact [expr {
			$hasMate
			|| $loss >= 15.0
			|| (([llength $guessPv] >= 2 || [llength $gamePv] >= 2) && ($cpLoss >= 80 || $cppTactic))
		}]
		set themes {}
		if {$tacticalFact} { lappend themes tactics }
		if {$materialFact} { lappend themes material }
		lappend themes king_safety development structure
	}

	return [dict create \
		ok           1 \
		verdict      $verdict \
		loss         $loss \
		cpLoss       $cpLoss \
		guessCp      $guessCp \
		gameCp       $gameCp \
		guessPv      $guessPv \
		gamePv       $gamePv \
		cppMaterial  $cppMaterial \
		materialFact $materialFact \
		tacticalFact $tacticalFact \
		hasMate      $hasMate \
		themes       $themes \
	]
}


# Compact state for guess_hint: position anatomy and target-move deltas,
# omitting the target move's SAN and square names.
proc ::guessmove::hintState {fen san {comment ""}} {
	set pf [PosFacts $fen]
	set mf [MoveFacts $fen $san]
	set side [expr {[Fact $pf sideToMove] ne "" ? [Fact $pf sideToMove] : "white"}]
	set opp [expr {$side eq "white" ? "black" : "white"}]
	set phase [expr {[Fact $pf phase] ne "" ? [Fact $pf phase] : "middlegame"}]
	set ply [expr {[Fact $pf ply] ne "" ? [Fact $pf ply] : 0}]
	set inCheck [Bool [Fact $pf inCheck]]
	set balance [expr {[Fact $pf material balanceCp] ne "" ? [Fact $pf material balanceCp] : 0}]
	set oppAtk [expr {[Fact $pf kingSafety $opp attackers] ne "" ? [Fact $pf kingSafety $opp attackers] : 0}]
	set ownAtk [expr {[Fact $pf kingSafety $side attackers] ne "" ? [Fact $pf kingSafety $side attackers] : 0}]

	set piece [Fact $mf piece]
	set capture [Bool [Fact $mf capture]]
	set check [Bool [Fact $mf check]]
	set mate [Bool [Fact $mf mate]]
	set castling [Bool [Fact $mf castling]]
	set developed [Bool [Fact $mf developed]]
	set matDelta [expr {[Fact $mf materialChangeCp] ne "" ? [Fact $mf materialChangeCp] : 0}]
	set seeCp [Fact $mf seeCp]
	if {$seeCp eq "" || $seeCp eq "null"} { set seeCp none }
	set losesMat [Bool [Fact $mf losesMaterial]]
	set discovered [llength [Fact $mf discoveredAttacks]]
	set remDef [join [Fact $mf removesDefender] ,]
	set newPins [join [Fact $mf newPins $opp] ,]
	set newEnPrise [join [Fact $mf newEnPrise $opp] ,]
	set passedDelta [expr {[Fact $mf structureDelta $side passed] ne "" ? [Fact $mf structureDelta $side passed] : 0}]

	set out "fen=$fen\n"
	append out "position: phase=$phase ply=$ply stm=$side inCheck=$inCheck balanceCp=$balance"
	append out " oppKingAttackers=$oppAtk ownKingAttackers=$ownAtk\n"
	append out "move: piece=$piece capture=$capture check=$check mate=$mate castling=$castling"
	append out " developed=$developed materialChangeCp=$matDelta seeCp=$seeCp losesMaterial=$losesMat"
	append out " discovered=$discovered removesDefender=$remDef newPins=$newPins"
	append out " newEnPrise=$newEnPrise passedDelta=$passedDelta"
	if {[string trim $comment] ne ""} {
		append out "\ncomment: [string range [string trim $comment] 0 300]"
	}
	return $out
}


# Deterministic fallback for guess_hint, over the C++ position and move facts.
proc ::guessmove::hintRule {fen san} {
	set pf [PosFacts $fen]
	set mf [MoveFacts $fen $san]
	set side [expr {[Fact $pf sideToMove] ne "" ? [Fact $pf sideToMove] : "white"}]
	set opp [expr {$side eq "white" ? "black" : "white"}]
	set phase [expr {[Fact $pf phase] ne "" ? [Fact $pf phase] : "middlegame"}]

	if {[Bool [Fact $mf castling]]} {
		return king_safety
	}
	if {[Bool [Fact $mf mate]] || [Bool [Fact $mf check]]
	 || [llength [Fact $mf discoveredAttacks]] > 0
	 || [llength [Fact $mf removesDefender]] > 0
	 || [llength [Fact $mf newPins $opp]] > 0} {
		return tactics
	}
	if {([Fact $pf kingSafety $opp attackers] ne "" && [Fact $pf kingSafety $opp attackers] >= 2)
	 || ([Fact $pf kingSafety $side attackers] ne "" && [Fact $pf kingSafety $side attackers] >= 2)} {
		return king_safety
	}
	set seeCp [Fact $mf seeCp]
	set matDelta [expr {[Fact $mf materialChangeCp] ne "" ? [Fact $mf materialChangeCp] : 0}]
	if {[Bool [Fact $mf capture]] && ![Bool [Fact $mf losesMaterial]]
	 && (($seeCp ne "" && $seeCp ne "null" && $seeCp > 0) || $matDelta > 0)} {
		return material
	}
	if {$phase eq "endgame"} { return endgame }
	if {[Bool [Fact $mf developed]]} { return development }
	return structure
}


proc ::guessmove::decideHint {fen san script {comment ""}} {
	variable HintThreshold

	set fallback [namespace code [list hintRule $fen $san]]
	if {[llength [info commands ::ai::decide]] == 0} {
		after 0 [list {*}$script [list ok 1 label [hintRule $fen $san] confidence {} source rules]]
		return
	}
	::ai::decide guess_hint [hintState $fen $san $comment] [HintQuestion] $script \
		-threshold $HintThreshold \
		-fallback $fallback
	return
}


proc ::guessmove::MoveSummary {san mf side opp} {
	set piece [Fact $mf piece]
	set capture [Bool [Fact $mf capture]]
	set check [Bool [Fact $mf check]]
	set mate [Bool [Fact $mf mate]]
	set castling [Bool [Fact $mf castling]]
	set developed [Bool [Fact $mf developed]]
	set matDelta [expr {[Fact $mf materialChangeCp] ne "" ? [Fact $mf materialChangeCp] : 0}]
	set seeCp [Fact $mf seeCp]
	if {$seeCp eq "" || $seeCp eq "null"} { set seeCp none }
	set losesMat [Bool [Fact $mf losesMaterial]]
	set discovered [llength [Fact $mf discoveredAttacks]]
	set remDef [join [Fact $mf removesDefender] ,]
	set ownHang [join [Fact $mf newUndefended $side] ,]
	set ownEnPrise [join [Fact $mf newEnPrise $side] ,]
	set oppPins [join [Fact $mf newPins $opp] ,]
	set oppEnPrise [join [Fact $mf newEnPrise $opp] ,]
	return "san=$san piece=$piece capture=$capture check=$check mate=$mate castling=$castling developed=$developed materialChangeCp=$matDelta seeCp=$seeCp losesMaterial=$losesMat discovered=$discovered removesDefender=$remDef ownNewUndefended=$ownHang ownNewEnPrise=$ownEnPrise oppNewPins=$oppPins oppNewEnPrise=$oppEnPrise"
}


# Compact state for guess_feedback: position facts, engine verdict/evals/PVs,
# and side-by-side move facts for the guessed move and the game move.
proc ::guessmove::feedbackState {fen guessSan gameSan {engineFacts ""} {comment ""}} {
	set pf [PosFacts $fen]
	set gmf [MoveFacts $fen $guessSan]
	set tmf [MoveFacts $fen $gameSan]
	set side [expr {[Fact $pf sideToMove] ne "" ? [Fact $pf sideToMove] : "white"}]
	set opp [expr {$side eq "white" ? "black" : "white"}]
	set phase [expr {[Fact $pf phase] ne "" ? [Fact $pf phase] : "middlegame"}]
	set ply [expr {[Fact $pf ply] ne "" ? [Fact $pf ply] : 0}]
	set inCheck [Bool [Fact $pf inCheck]]

	set out "fen=$fen\n"
	append out "position: phase=$phase ply=$ply stm=$side inCheck=$inCheck\n"
	if {[dict exists $engineFacts ok] && [dict get $engineFacts ok]} {
		append out [format "engine: verdict=%s wpLoss=%.2f cpLoss=%d guessCp=%d gameCp=%d materialLoss=%d tacticalSwing=%d guessPv=%s gamePv=%s\n" \
			[dict get $engineFacts verdict] \
			[dict get $engineFacts loss] \
			[dict get $engineFacts cpLoss] \
			[dict get $engineFacts guessCp] \
			[dict get $engineFacts gameCp] \
			[dict get $engineFacts materialFact] \
			[dict get $engineFacts tacticalFact] \
			[join [dict get $engineFacts guessPv] ,] \
			[join [dict get $engineFacts gamePv] ,]]
	}
	append out "guess: [MoveSummary $guessSan $gmf $side $opp]\n"
	append out "game_move: [MoveSummary $gameSan $tmf $side $opp]"
	if {[string trim $comment] ne ""} {
		append out "\ncomment: [string range [string trim $comment] 0 300]"
	}
	return $out
}


# Deterministic theme selection for guess_feedback, constrained by the
# engine's verdict/facts when available and C++ facts otherwise.
# Material is claimed only when C++ facts (seeCp/losesMaterial) and the
# engine's eval show material loss; tactics only when the engine's PV/eval
# swing shows them.
proc ::guessmove::feedbackRule {fen guessSan gameSan {engineFacts ""}} {
	set pf [PosFacts $fen]
	set gmf [MoveFacts $fen $guessSan]
	set tmf [MoveFacts $fen $gameSan]
	set side [expr {[Fact $pf sideToMove] ne "" ? [Fact $pf sideToMove] : "white"}]
	set opp [expr {$side eq "white" ? "black" : "white"}]

	set hasEngine [expr {[dict exists $engineFacts ok] && [dict get $engineFacts ok]}]
	set verdict   [expr {$hasEngine ? [dict get $engineFacts verdict] : ""}]

	if {$verdict ne "close_alternative"} {
		set gSee [Fact $gmf seeCp]
		set gMatDelta [expr {[Fact $gmf materialChangeCp] ne "" ? [Fact $gmf materialChangeCp] : 0}]
		set gLoses [expr {
			[Bool [Fact $gmf losesMaterial]]
			|| ($gSee ne "" && $gSee ne "null" && $gSee < 0)
			|| $gMatDelta < 0
			|| [llength [Fact $gmf newEnPrise $side]] > 0
		}]
		set tSee [Fact $tmf seeCp]
		set tMatDelta [expr {[Fact $tmf materialChangeCp] ne "" ? [Fact $tmf materialChangeCp] : 0}]
		set tWins [expr {
			[Bool [Fact $tmf capture]] && ![Bool [Fact $tmf mate]] && ![Bool [Fact $tmf losesMaterial]]
			&& (($tSee ne "" && $tSee ne "null" && $tSee > 0) || $tMatDelta > 0)
		}]
		set cppMaterial [expr {$gLoses || ($tWins && ![Bool [Fact $gmf capture]])}]

		if {$hasEngine} {
			if {[dict get $engineFacts hasMate]} {
				return tactics
			}
			if {$cppMaterial && [dict get $engineFacts materialFact]} {
				return material
			}
			if {[dict get $engineFacts tacticalFact]
			 && ([llength [dict get $engineFacts guessPv]] >= 2
			     || [llength [dict get $engineFacts gamePv]] >= 2
			     || [Bool [Fact $tmf check]]
			     || [llength [Fact $tmf discoveredAttacks]] > 0
			     || [llength [Fact $tmf removesDefender]] > 0
			     || [llength [Fact $tmf newPins $opp]] > 0)} {
				return tactics
			}
		} else {
			if {[Bool [Fact $tmf mate]]} {
				return tactics
			}
			if {$cppMaterial} {
				return material
			}
		}
	}

	if {[Bool [Fact $tmf castling]] && ![Bool [Fact $gmf castling]]} {
		return king_safety
	}
	if {[Bool [Fact $tmf developed]] && ![Bool [Fact $gmf developed]]} {
		return development
	}
	return structure
}


proc ::guessmove::decideFeedback {fen guessSan gameSan script {comment ""}} {
	variable FeedbackThreshold

	set ef [evaluateFeedback $fen $guessSan $gameSan]
	if {![dict get $ef ok]} {
		set label [feedbackRule $fen $guessSan $gameSan]
		after 0 [list {*}$script [dict create \
			ok 1 verdict {} loss {} label $label theme $label confidence {} source rules]]
		return
	}

	set verdict  [dict get $ef verdict]
	set loss     [dict get $ef loss]
	set themes   [dict get $ef themes]
	set fallback [namespace code [list feedbackRule $fen $guessSan $gameSan $ef]]
	if {[llength [info commands ::ai::decide]] == 0} {
		set label [feedbackRule $fen $guessSan $gameSan $ef]
		after 0 [list {*}$script [dict create \
			ok 1 verdict $verdict loss $loss label $label theme $label confidence {} source rules]]
		return
	}
	::ai::decide guess_feedback \
		[feedbackState $fen $guessSan $gameSan $ef $comment] \
		[FeedbackQuestion $verdict $themes] \
		[namespace code [list WrapFeedbackDecision $verdict $loss $themes $fallback $script]] \
		-threshold $FeedbackThreshold \
		-fallback $fallback
	return
}


# Enforce the engine-first firewall on Jev's feedback answer: the engine's
# verdict and loss are preserved unconditionally, and the theme must belong
# to the engine-validated theme list.
proc ::guessmove::WrapFeedbackDecision {verdict loss themes fallback script decision} {
	if {![dict exists $decision ok] || ![dict get $decision ok]} {
		set label [uplevel #0 $fallback]
		set out [dict create ok 1 verdict $verdict loss $loss label $label theme $label confidence {} source rules]
	} else {
		set label  [dict get $decision label]
		set source [dict get $decision source]
		set conf   [expr {[dict exists $decision confidence] ? [dict get $decision confidence] : {}}]
		if {$label ni $themes} {
			set label  [uplevel #0 $fallback]
			set source rules
			set conf   {}
		}
		set out [dict create ok 1 verdict $verdict loss $loss label $label theme $label confidence $conf source $source]
	}
	uplevel #0 [list {*}$script $out]
}


# Structured round profile for guess_review.
proc ::guessmove::roundStats {} {
	variable Priv

	set score $Priv(score)
	set total $Priv(total)
	set pct [expr {$total ? int(round(100.0 * $score / $total)) : 0}]
	set phases [dict create opening {0 0} middlegame {0 0} endgame {0 0}]
	set verdicts [dict create \
		close_alternative	0 \
		slightly_worse		0 \
		worse				0 \
	]
	set misses [dict create \
		tactics		0 \
		material	0 \
		king_safety	0 \
		development	0 \
		structure	0 \
	]
	foreach item $Priv(history) {
		set ph [expr {[dict exists $item phase] ? [dict get $item phase] : "middlegame"}]
		if {![dict exists $phases $ph]} { set ph middlegame }
		lassign [dict get $phases $ph] hit tot
		incr tot
		if {[dict get $item outcome] eq "correct"} {
			incr hit
		} else {
			if {[dict exists $item verdict]} {
				set v [dict get $item verdict]
				if {[dict exists $verdicts $v]} { dict incr verdicts $v }
			}
			if {[dict exists $item feedback]} {
				set fb [dict get $item feedback]
				if {[dict exists $misses $fb]} { dict incr misses $fb }
			}
		}
		dict set phases $ph [list $hit $tot]
	}
	return [dict create \
		side		$Priv(side) \
		score		$score \
		total		$total \
		pct			$pct \
		hints		$Priv(hintsUsed) \
		reveals		$Priv(showsUsed) \
		phases		$phases \
		verdicts	$verdicts \
		misses		$misses \
	]
}


proc ::guessmove::reviewState {{stats ""}} {
	if {$stats eq ""} { set stats [roundStats] }
	set side    [expr {[dict exists $stats side]    ? [dict get $stats side]    : "white"}]
	set score   [expr {[dict exists $stats score]   ? [dict get $stats score]   : 0}]
	set total   [expr {[dict exists $stats total]   ? [dict get $stats total]   : 0}]
	set pct     [expr {[dict exists $stats pct]     ? [dict get $stats pct]     : ($total ? int(round(100.0 * $score / $total)) : 0)}]
	set hints   [expr {[dict exists $stats hints]   ? [dict get $stats hints]   : 0}]
	set reveals [expr {[dict exists $stats reveals] ? [dict get $stats reveals] : 0}]

	set phaseParts {}
	foreach ph {opening middlegame endgame} {
		set pair [expr {[dict exists $stats phases $ph] ? [dict get $stats phases $ph] : {0 0}}]
		lassign $pair hit tot
		lappend phaseParts "$ph=$hit/$tot"
	}
	set verdictParts {}
	foreach v {close_alternative slightly_worse worse} {
		set n [expr {[dict exists $stats verdicts $v] ? [dict get $stats verdicts $v] : 0}]
		lappend verdictParts "$v=$n"
	}
	set missParts {}
	foreach k {tactics material king_safety development structure} {
		set n [expr {[dict exists $stats misses $k] ? [dict get $stats misses $k] : 0}]
		lappend missParts "$k=$n"
	}
	return "side=$side score=$score total=$total pct=$pct hints=$hints reveals=$reveals [join $phaseParts { }] [join $verdictParts { }] [join $missParts { }]"
}


# Deterministic fallback for guess_review.
proc ::guessmove::reviewRule {{stats ""}} {
	if {$stats eq ""} { set stats [roundStats] }
	set score   [expr {[dict exists $stats score]   ? [dict get $stats score]   : 0}]
	set total   [expr {[dict exists $stats total]   ? [dict get $stats total]   : 0}]
	set hints   [expr {[dict exists $stats hints]   ? [dict get $stats hints]   : 0}]
	set reveals [expr {[dict exists $stats reveals] ? [dict get $stats reveals] : 0}]
	if {$total <= 0} { return needs_study }

	set matMiss 0
	if {[dict exists $stats misses material]} {
		incr matMiss [dict get $stats misses material]
	}
	if {[dict exists $stats misses blundered_material]} {
		incr matMiss [dict get $stats misses blundered_material]
	}
	set tacMiss 0
	if {[dict exists $stats misses tactics]} {
		incr tacMiss [dict get $stats misses tactics]
	}
	if {[dict exists $stats misses missed_tactic]} {
		incr tacMiss [dict get $stats misses missed_tactic]
	}
	set eff [expr {100.0 * ($score - 0.5 * $hints - 0.25 * ($matMiss + $tacMiss)) / $total}]

	if {$eff >= 85.0 && $reveals == 0} { return master_like }
	if {$eff >= 65.0} { return sharp }
	if {$eff >= 40.0} { return steady }
	return needs_study
}


proc ::guessmove::decideReview {stats script} {
	variable ReviewThreshold

	if {$stats eq ""} { set stats [roundStats] }
	set fallback [namespace code [list reviewRule $stats]]
	if {[llength [info commands ::ai::decide]] == 0} {
		after 0 [list {*}$script [list ok 1 label [reviewRule $stats] confidence {} source rules]]
		return
	}
	::ai::decide guess_review [reviewState $stats] [ReviewQuestion] $script \
		-threshold $ReviewThreshold \
		-fallback $fallback
	return
}


proc ::guessmove::OnHintDecided {hseq tseq decision} {
	variable Priv
	variable active

	if {!$active || $hseq != $Priv(hintSeq) || $tseq != $Priv(turnSeq)} { return }
	if {![dict exists $decision ok] || ![dict get $decision ok]} { return }
	set label [dict get $decision label]
	set source [dict get $decision source]
	set Priv(hintKind) $label
	set Priv(hintSource) $source
	if {$source eq "classifier"} {
		set Priv(note) [describeHint $label]
		Refresh
	}
}


proc ::guessmove::OnFeedbackDecided {fseq tseq idx guessSan gameSan decision} {
	variable Priv
	variable active

	if {$fseq != $Priv(feedbackSeq)} { return }
	if {![dict exists $decision ok] || ![dict get $decision ok]} { return }
	set verdict [expr {[dict exists $decision verdict] ? [dict get $decision verdict] : ""}]
	set loss    [expr {[dict exists $decision loss]    ? [dict get $decision loss]    : ""}]
	set label   [dict get $decision label]
	set source  [dict get $decision source]
	set Priv(verdict)         $verdict
	set Priv(feedbackVerdict) $verdict
	set Priv(feedbackLoss)    $loss
	set Priv(feedbackTheme)   $label
	set Priv(feedback)        $label
	set Priv(feedbackSource)  $source
	if {$idx >= 0 && $idx < [llength $Priv(history)]} {
		set item [lindex $Priv(history) $idx]
		dict set item verdict  $verdict
		dict set item loss     $loss
		dict set item feedback $label
		lset Priv(history) $idx $item
	}
	if {$active && $tseq == $Priv(turnSeq) && $source eq "classifier" && $verdict ne ""} {
		set Priv(note) [describeFeedback $verdict $label $guessSan $gameSan]
		Refresh
	}
}


proc ::guessmove::OnReviewDecided {rseq decision} {
	variable Priv
	variable active

	if {$active || $rseq != $Priv(reviewSeq)} { return }
	if {![dict exists $decision ok] || ![dict get $decision ok]} { return }
	set label [dict get $decision label]
	set source [dict get $decision source]
	set Priv(review) $label
	set Priv(reviewSource) $source
	if {$source eq "classifier"} {
		set Priv(note) [describeReview $label]
		set dlg $Priv(dialog)
		if {[winfo exists $dlg] && [winfo exists [::util::place::playingBody $dlg].top.note]} {
			[::util::place::playingBody $dlg].top.note configure -text $Priv(note)
		}
	}
}


# ----------------------------------------------------------------------
# Internals.
# ----------------------------------------------------------------------

proc ::guessmove::CurrentFen {} {
	if {![catch { ::scidb::pos::fen } fen] && $fen ne ""} { return $fen }
	return "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
}


proc ::guessmove::PosFacts {fen} {
	if {[llength [info commands ::scidb::ai::facts]] == 0} { return {} }
	if {[catch { package require json }]} { return {} }
	if {[catch { ::json::json2dict [::scidb::ai::facts $fen] } d]} { return {} }
	return $d
}


proc ::guessmove::MoveFacts {fen san} {
	if {[llength [info commands ::scidb::ai::moveFacts]] == 0} { return {} }
	if {[catch { package require json }]} { return {} }
	if {[catch { ::json::json2dict [::scidb::ai::moveFacts $san $fen] } d]} { return {} }
	return $d
}


proc ::guessmove::Fact {d args} {
	set node $d
	foreach key $args {
		if {![catch { dict get $node $key } node]} { continue }
		return {}
	}
	return $node
}


proc ::guessmove::Bool {v} {
	return [expr {[string is true -strict $v] ? 1 : 0}]
}


proc ::guessmove::PositionPhase {fen} {
	set pf [PosFacts $fen]
	set ph [Fact $pf phase]
	return [expr {$ph ne "" ? $ph : "middlegame"}]
}


# The SAN of the next move on the current line; "" at the end of it.
proc ::guessmove::GameMove {} {
	if {[::scidb::game::position atEnd?]} { return "" }
	return [::scidb::game::next move -ascii]
}


# Step over the opponent's moves until the user is to move again; at the
# end of the game the round is finished.
proc ::guessmove::Advance {} {
	variable Priv

	while {	![::scidb::game::position atEnd?]
		&& [::scidb::game::query stm] ne $Priv(side)} {
		::application::board::goto +1
	}
	if {[::scidb::game::position atEnd?]} { Finish } else { Refresh }
}


# End of the game or Stop: lock the score, show the summary, and ask the
# System One classifier for an overall training assessment.
proc ::guessmove::Finish {} {
	variable Priv
	variable active
	variable mc

	set active 0
	ClearHint
	incr Priv(turnSeq)
	set Priv(note) {}
	set pct [expr {$Priv(total) ? int(round(100.0 * $Priv(score) / $Priv(total))) : 0}]
	set Priv(summary) [format $mc::Summary $Priv(score) $Priv(total) $pct]

	set stats [roundStats]
	set Priv(review) [reviewRule $stats]
	set Priv(reviewSource) rules
	incr Priv(reviewSeq)
	set rseq $Priv(reviewSeq)

	set dlg $Priv(dialog)
	if {[winfo exists $dlg]} {
		[::util::place::playingBody $dlg].top.score configure -text [ScoreText]
		[::util::place::playingBody $dlg].top.last configure -text $Priv(summary)
		[::util::place::playingBody $dlg].top.note configure -text $Priv(note)
		[::util::place::playingBody $dlg].top.buttons.hint configure -state disabled
		[::util::place::playingBody $dlg].top.buttons.show configure -state disabled
		[::util::place::playingBody $dlg].top.buttons.stop configure \
			-text $mc::Close \
			-command [list destroy $dlg] \
			;
	}
	if {$Priv(total) > 0} {
		decideReview $stats [namespace code [list OnReviewDecided $rseq]]
	}
}


proc ::guessmove::Refresh {} {
	variable Priv

	set dlg $Priv(dialog)
	if {![winfo exists $dlg]} { return }
	[::util::place::playingBody $dlg].top.score configure -text [ScoreText]
	[::util::place::playingBody $dlg].top.last configure -text $Priv(last)
	if {[winfo exists [::util::place::playingBody $dlg].top.note]} {
		[::util::place::playingBody $dlg].top.note configure -text $Priv(note)
	}
}


proc ::guessmove::ScoreText {} {
	variable Priv
	variable mc

	return [format $mc::Score $Priv(score) $Priv(total)]
}


proc ::guessmove::ClearHint {} {
	variable Priv

	after cancel $Priv(hint)
	set Priv(hint) {}
	if {$Priv(hintSquare) != -1} {
		catch { ::board::diagram::hilite $::application::board::board $Priv(hintSquare) off }
		set Priv(hintSquare) -1
	}
}


proc ::guessmove::BuildWindow {parent} {
	variable Priv
	variable mc

	set dlg $parent.__guessmove__
	if {[winfo exists $dlg]} { destroy $dlg }
	toplevel $dlg -class Scidb
	wm title $dlg $mc::Title
	wm transient $dlg [winfo toplevel $parent]
	wm withdraw $dlg
	wm protocol $dlg WM_DELETE_WINDOW [namespace code stop]
	bind $dlg <Escape> [namespace code stop]

	set top [ttk::frame [::util::place::playingBody $dlg].top]
	pack $top -fill both -expand yes -padx $::theme::padx -pady $::theme::pady

	set side $mc::White
	if {$Priv(side) eq "black"} { set side $mc::Black }
	ttk::label $top.side -text [format $mc::SideGuessing $side]
	ttk::label $top.score -text [ScoreText]
	ttk::label $top.last -wraplength 320 -justify left
	ttk::label $top.note -wraplength 320 -justify left

	set buttons [ttk::frame $top.buttons]
	ttk::button $buttons.hint -text $mc::Hint -command [namespace code hint]
	ttk::button $buttons.show -text $mc::ShowMove -command [namespace code showMove]
	ttk::button $buttons.stop -text $mc::Stop -command [namespace code stop]
	pack $buttons.hint $buttons.show $buttons.stop -side left -padx [list 0 $::theme::padx]

	pack $top.side -anchor w
	pack $top.score -anchor w -pady [list $::theme::pady 0]
	pack $top.last -anchor w -pady [list $::theme::pady 0]
	pack $top.note -anchor w -pady [list $::theme::pady 0]
	pack $buttons -anchor e -pady [list $::theme::pady 0]

	set Priv(dialog) $dlg
	::util::place::besideBoard $dlg $parent
	wm deiconify $dlg
	return $dlg
}

# vi:set ts=3 sw=3:
