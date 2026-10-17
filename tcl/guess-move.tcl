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
#   2. guess_feedback (choice) -- why a wrong guess differed from the game move
#                                 (close_alternative, missed_tactic,
#                                 blundered_material, missed_development,
#                                 missed_king_safety).
#   3. guess_review   (score)  -- end-of-round assessment over ordered levels
#                                 {needs_study steady sharp master_like} from
#                                 accuracy, hints/reveals, phase split and miss
#                                 verdicts.
#
# Firewall: whether a guess matches the game move, the score, and the board's
# from-square highlight are hard facts that a model never overrides. When the
# classifier is off, unreachable, abstains or is below threshold, deterministic
# rules over ::scidb::ai::facts / ::scidb::ai::moveFacts run and the UI behaves
# identically to before.
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
	close_alternative	"%s is a playable alternative; the game chose %s." \
	missed_tactic		"%s missed a tactical idea in the game move (%s)." \
	blundered_material	"%s loses material or leaves a piece loose (game: %s)." \
	missed_development	"%s delays development compared with %s." \
	missed_king_safety	"%s neglects king safety compared with %s." \
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

variable HintCriteria [dict create \
	development	"develop a minor piece from its starting square or connect the rooks" \
	king_safety	"castle, shelter the king, or launch a direct attack against an exposed enemy king" \
	tactics		"execute or meet a tactical threat: check, mate, fork, pin, skewer, discovered attack, or hanging piece" \
	material	"win material with a favourable capture or exchange" \
	structure	"improve the pawn structure, fight for the centre, or contest an open file" \
	endgame		"activate the king, advance or blockade a passed pawn, or simplify in the endgame" \
]

variable FeedbackCriteria [dict create \
	close_alternative	"the guessed move is a sound positional or developing alternative that does not lose material or miss a tactical blow" \
	missed_tactic		"the game move executes or refutes a concrete tactical blow (check, mate, winning capture, fork, pin, discovered attack, removing a defender) that the guess missed" \
	blundered_material	"the guessed move loses material in an exchange or leaves a piece or pawn undefended or en prise" \
	missed_development	"in the opening, the game move develops a minor piece or connects rooks while the guess delays development" \
	missed_king_safety	"the game move castles or addresses king safety while the guess leaves the king exposed" \
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
		set Priv(feedback) correct
		set Priv(feedbackSource) rules
		lappend Priv(history) [dict create \
			ply $Priv(total) phase $phase guess $san move $move \
			outcome correct hint $hinted feedback correct]
		::application::board::goto +1
		Advance
	} else {
		set Priv(last) [format $mc::NotTheGameMove $move]
		set ruleFb [feedbackRule $fen $san $move]
		set Priv(feedback) $ruleFb
		set Priv(feedbackSource) rules
		lappend Priv(history) [dict create \
			ply $Priv(total) phase $phase guess $san move $move \
			outcome miss hint $hinted feedback $ruleFb]
		set idx [expr {[llength $Priv(history)] - 1}]
		incr Priv(feedbackSeq)
		set fseq $Priv(feedbackSeq)
		::application::board::goto +1
		Advance
		decideFeedback $fen $san $move \
			[namespace code [list OnFeedbackDecided $fseq $tseq $idx $san $move]]
	}
	return ""
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


proc ::guessmove::FeedbackQuestion {} {
	variable FeedbackCriteria
	return [dict create type choice \
		instructions "The player guessed a different move than the game move in this chess position. From the position and move facts for both moves, why did the guess differ from the game move?" \
		criteria $FeedbackCriteria]
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


proc ::guessmove::describeFeedback {label guessSan gameSan} {
	variable mc
	if {![dict exists $mc::FeedbackNotes $label]} { return "" }
	return [format [dict get $mc::FeedbackNotes $label] $guessSan $gameSan]
}


proc ::guessmove::describeReview {label} {
	variable mc
	return [expr {[dict exists $mc::ReviewNotes $label] ? [dict get $mc::ReviewNotes $label] : ""}]
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


# Compact state for guess_feedback: position facts plus side-by-side move
# facts for the guessed move and the game move.
proc ::guessmove::feedbackState {fen guessSan gameSan {comment ""}} {
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
	append out "guess: [MoveSummary $guessSan $gmf $side $opp]\n"
	append out "game_move: [MoveSummary $gameSan $tmf $side $opp]"
	if {[string trim $comment] ne ""} {
		append out "\ncomment: [string range [string trim $comment] 0 300]"
	}
	return $out
}


# Deterministic fallback for guess_feedback, comparing the two moves' facts.
proc ::guessmove::feedbackRule {fen guessSan gameSan} {
	set pf [PosFacts $fen]
	set gmf [MoveFacts $fen $guessSan]
	set tmf [MoveFacts $fen $gameSan]
	set side [expr {[Fact $pf sideToMove] ne "" ? [Fact $pf sideToMove] : "white"}]
	set opp [expr {$side eq "white" ? "black" : "white"}]
	set phase [expr {[Fact $pf phase] ne "" ? [Fact $pf phase] : "middlegame"}]

	set gMatDelta [expr {[Fact $gmf materialChangeCp] ne "" ? [Fact $gmf materialChangeCp] : 0}]
	if {[Bool [Fact $gmf losesMaterial]]
	 || $gMatDelta < 0
	 || [llength [Fact $gmf newEnPrise $side]] > 0} {
		return blundered_material
	}

	set tSee [Fact $tmf seeCp]
	set tWinsMat [expr {[Bool [Fact $tmf capture]] && ![Bool [Fact $tmf losesMaterial]]
		&& (($tSee ne "" && $tSee ne "null" && $tSee > 0)
		    || ([Fact $tmf materialChangeCp] ne "" && [Fact $tmf materialChangeCp] > 0))}]
	if {[Bool [Fact $tmf mate]] || [Bool [Fact $tmf check]]
	 || [llength [Fact $tmf discoveredAttacks]] > 0
	 || [llength [Fact $tmf removesDefender]] > 0
	 || [llength [Fact $tmf newPins $opp]] > 0
	 || ($tWinsMat && ![Bool [Fact $gmf capture]])} {
		return missed_tactic
	}

	if {[Bool [Fact $tmf castling]] && ![Bool [Fact $gmf castling]]} {
		return missed_king_safety
	}
	if {$phase eq "opening" && [Bool [Fact $tmf developed]] && ![Bool [Fact $gmf developed]]} {
		return missed_development
	}
	return close_alternative
}


proc ::guessmove::decideFeedback {fen guessSan gameSan script {comment ""}} {
	variable FeedbackThreshold

	set fallback [namespace code [list feedbackRule $fen $guessSan $gameSan]]
	if {[llength [info commands ::ai::decide]] == 0} {
		after 0 [list {*}$script [list ok 1 label [feedbackRule $fen $guessSan $gameSan] confidence {} source rules]]
		return
	}
	::ai::decide guess_feedback [feedbackState $fen $guessSan $gameSan $comment] [FeedbackQuestion] $script \
		-threshold $FeedbackThreshold \
		-fallback $fallback
	return
}


# Structured round profile for guess_review.
proc ::guessmove::roundStats {} {
	variable Priv

	set score $Priv(score)
	set total $Priv(total)
	set pct [expr {$total ? int(round(100.0 * $score / $total)) : 0}]
	set phases [dict create opening {0 0} middlegame {0 0} endgame {0 0}]
	set misses [dict create \
		close_alternative	0 \
		missed_tactic		0 \
		blundered_material	0 \
		missed_development	0 \
		missed_king_safety	0 \
	]
	foreach item $Priv(history) {
		set ph [expr {[dict exists $item phase] ? [dict get $item phase] : "middlegame"}]
		if {![dict exists $phases $ph]} { set ph middlegame }
		lassign [dict get $phases $ph] hit tot
		incr tot
		if {[dict get $item outcome] eq "correct"} {
			incr hit
		} elseif {[dict exists $item feedback]} {
			set fb [dict get $item feedback]
			if {[dict exists $misses $fb]} { dict incr misses $fb }
		}
		dict set phases $ph [list $hit $tot]
	}
	return [dict create \
		side	$Priv(side) \
		score	$score \
		total	$total \
		pct		$pct \
		hints	$Priv(hintsUsed) \
		reveals	$Priv(showsUsed) \
		phases	$phases \
		misses	$misses \
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
	set missParts {}
	foreach k {close_alternative missed_tactic blundered_material missed_development missed_king_safety} {
		set n [expr {[dict exists $stats misses $k] ? [dict get $stats misses $k] : 0}]
		lappend missParts "$k=$n"
	}
	return "side=$side score=$score total=$total pct=$pct hints=$hints reveals=$reveals [join $phaseParts { }] [join $missParts { }]"
}


# Deterministic fallback for guess_review.
proc ::guessmove::reviewRule {{stats ""}} {
	if {$stats eq ""} { set stats [roundStats] }
	set score   [expr {[dict exists $stats score]   ? [dict get $stats score]   : 0}]
	set total   [expr {[dict exists $stats total]   ? [dict get $stats total]   : 0}]
	set hints   [expr {[dict exists $stats hints]   ? [dict get $stats hints]   : 0}]
	set reveals [expr {[dict exists $stats reveals] ? [dict get $stats reveals] : 0}]
	if {$total <= 0} { return needs_study }

	set blunders [expr {[dict exists $stats misses blundered_material] ? [dict get $stats misses blundered_material] : 0}]
	set tactics  [expr {[dict exists $stats misses missed_tactic]      ? [dict get $stats misses missed_tactic]      : 0}]
	set eff [expr {100.0 * ($score - 0.5 * $hints - 0.25 * ($blunders + $tactics)) / $total}]

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
	set label [dict get $decision label]
	set source [dict get $decision source]
	set Priv(feedback) $label
	set Priv(feedbackSource) $source
	if {$idx >= 0 && $idx < [llength $Priv(history)]} {
		set item [lindex $Priv(history) $idx]
		dict set item feedback $label
		lset Priv(history) $idx $item
	}
	if {$active && $tseq == $Priv(turnSeq) && $source eq "classifier"} {
		set Priv(note) [describeFeedback $label $guessSan $gameSan]
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
		if {[winfo exists $dlg] && [winfo exists $dlg.top.note]} {
			$dlg.top.note configure -text $Priv(note)
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
		$dlg.top.score configure -text [ScoreText]
		$dlg.top.last configure -text $Priv(summary)
		$dlg.top.note configure -text $Priv(note)
		$dlg.top.buttons.hint configure -state disabled
		$dlg.top.buttons.show configure -state disabled
		$dlg.top.buttons.stop configure \
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
	$dlg.top.score configure -text [ScoreText]
	$dlg.top.last configure -text $Priv(last)
	if {[winfo exists $dlg.top.note]} {
		$dlg.top.note configure -text $Priv(note)
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

	set top [ttk::frame $dlg.top]
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
	::util::place $dlg -parent $parent -position center
	wm deiconify $dlg
	return $dlg
}

# vi:set ts=3 sw=3:
