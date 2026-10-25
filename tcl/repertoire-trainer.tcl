# ======================================================================
# Repertoire trainer with spaced repetition.
#
# Drills the moves of a repertoire until they are known, the way
# Chessable or Chess Position Trainer do: a card is one position where
# the trained side is to move plus the repertoire move(s) played there
# (the mainline and every variation; the key is the FEN without clocks,
# so transpositions meet on one card), and an SM-2 scheduler decides
# when a card comes back.
#
#   ::reptrainer::open $parent ?$base? ?$variant?
#       The Extras menu entry and the database tab's context menu for
#       repertoire databases. The dialog picks the source (every open
#       opening database, or the current game) and the side to train.
#
# The deck -- one file per source database, <home>/training/<name>.deck,
# a Tcl dict written atomically (tmp file, then rename) -- keeps each
# card's scheduling state between sessions. Positions of the other side
# keep their state untouched, so the same deck can train White and
# Black.
#
# The drill shows the card's position on the main board (a scratch
# game); the move played on the board is the answer. While a card waits
# for it, ::move::addMove hands the move to ::reptrainer::answered
# instead of adding it to the game. A correct answer asks for a grade
# (Hard/Good/Easy); a wrong answer shows the expected move and grades
# Again, and the card returns later in the same session.
#
# The scheduler core (newCard, review, due, counters, mergeCards, the
# deck file helpers) is UI-free and covered by
# tests/test_app_repertoire_trainer.tcl.
# ======================================================================

::util::source repertoire-trainer

namespace eval reptrainer {
namespace eval mc {

set Title					"Repertoire Training"
set TrainRepertoire			"Train &Repertoire..."
set Source					"Repertoire:"
set TrainSide					"Train as:"
set White						"White"
set Black						"Black"
set CurrentGame				"Current game"
set FlipBoard					"Flip the board to the trained side"
set Start						"Start"
set Stop						"Stop"
set Close						"Close"
set YourMove					"Play the repertoire move for %s."
set Correct					"%s is right. How well did you know it?"
set CorrectSuggested		"%s is right. How well did you know it? (Suggested: %s)"
set Wrong						"%s is not in the repertoire. Expected: %s."
set Hard						"Hard"
set Good						"Good"
set Easy						"Easy"
set Counter					"due: %d, new: %d, done today: %d"
set Done						"No cards are due. Repertoire training finished."
set Stopped					"Training stopped."
set LeftBoard					"The drill board was closed; training stopped."
set Empty						"The repertoire has no moves for %s."
set EmptyDetail				"Add moves for that side to the source, or train the other side."
set NoScratch					"No free game slot for the drill board."
set NoScratchDetail			"Close a game in the game bar and start again."

} ;# namespace mc

array set Options {
	flipBoard 1
}

variable Slot 28			;# scratch game for card building (29-31 are taken)
variable Delay 1200		;# how long a wrong answer is shown before the next card
variable Day 86400		;# seconds per day
variable Version 1		;# deck file format
variable NewEase 250		;# starting ease 2.50, in hundredths
variable MinEase 130		;# ease floor 1.30
variable MaxEase 300		;# ease ceiling 3.00

variable SideCriteria [dict create \
	white	"a White opening repertoire (e.g. London System, Catalan, Queen's Gambit, Scotch, Italian, English, 1.e4 or 1.d4 for White)" \
	black	"a Black opening defense or repertoire (e.g. Sicilian, Caro-Kann, French, King's Indian, Nimzo-Indian, Grunfeld, Slav, Pirc, Berlin)" \
	unsure	"a general collection, both sides, or not enough information to tell" \
]

variable NoteCriteria [dict create \
	hint			"context or line selection that is safe to show BEFORE the player moves without giving away which piece moves or where" \
	explanation	"explains why the repertoire move is played, names or describes the move in words, or discusses what follows -- show only AFTER the player answers" \
	noise			"clock times, engine evaluations, tournament headers, or non-instructive metadata -- do not show" \
]

variable GradeCriteria [dict create \
	hard	"slow recall, repeated lapses, or a hesitant recovery that needs a short interval" \
	good	"normal recall at a steady pace for this stage of learning" \
	easy	"fast, effortless recall with a clean history that can jump to a longer interval" \
]

array set Vars {
	running			0
	state				{}
	dlg				{}
	deck				{}
	deckFile		{}
	side				white
	sourceBase	{}
	sideChoice	white
	built				{}
	card				{}
	instruction	{}
	queue				{}
	index				0
	gameSlot		-1
	startFen		{}
	after				{}
	wasRotated	0
	sources			{}
	sourceIndex	0
	sourceLabel	{}
	seq				0
	cardSeq			0
	shownAt			0
	lastSan			{}
	suggestedGrade	{}
	noteRole		{}
	noteText		{}
}

} ;# namespace reptrainer


# ----------------------------------------------------------------------
# Scheduler core (pure).
# ----------------------------------------------------------------------

# The position key: the FEN without the clocks (tablebase::Key's rule).
proc ::reptrainer::Key {fen} {
	return [join [lrange $fen 0 3] " "]
}


# A new, never seen card for <fen> (the full FEN of the position before
# the move) with the expected move(s) <moves>; it is due right away.
proc ::reptrainer::newCard {fen moves now {comment ""}} {
	variable NewEase

	set card [dict create \
		fen $fen \
		moves $moves \
		interval 0 \
		ease $NewEase \
		reps 0 \
		lapses 0 \
		due $now \
	]
	set comment [string trim $comment]
	if {$comment ne ""} {
		dict set card comment $comment
	}
	return $card
}


# SM-2 with four buttons.  <card> is a card dict, <grade> one of
# 0 again / 1 hard / 2 good / 3 easy, <now> unix seconds.  Returns the
# reviewed card.  The formula:
#
#   q = grade + 2                    SM-2 quality (again 2, easy 5)
#   ease' = ease + 10*(0.1 - (5-q)*(0.08 + (5-q)*0.02))      [in hundredths]
#        = ease - 32 (again), - 14 (hard), + 0 (good), + 10 (easy),
#   clamped to [1.30, 3.00].
#
#   again: interval 0 -- the card is due now and comes back within the
#          same session; reps restarts from zero, lapses grows by one.
#   hard:  1 day on the first pass, else the old interval times 1.2.
#   good:  1 day on the first pass, 6 days after one remembered answer
#          (SM-2's I(2)), else the old interval times ease'.
#   easy:  4 days on the first pass, else the old interval times ease'
#          times 1.3 (the easy bonus).
#   hard/good/easy count one repetition; due = now + interval days.
proc ::reptrainer::review {card grade now} {
	variable Day
	variable MinEase
	variable MaxEase

	if {![string is integer -strict $grade] || $grade < 0 || $grade > 3} {
		return -code error "invalid grade \"$grade\": must be 0..3"
	}

	set q [expr {$grade + 2}]
	# SM-2's EF update, in hundredths: again -32, hard -14, good 0, easy +10
	set ease [expr {max($MinEase, min($MaxEase, \
		[dict get $card ease] + (10 - (5 - $q)*(8 + (5 - $q)*2))))}]
	set reps [dict get $card reps]
	set interval [dict get $card interval]

	if {$grade == 0} {
		set interval 0
		set reps 0
		dict incr card lapses
	} else {
		switch -- $grade {
			1 { set interval [expr {$reps == 0 ? 1 : max(1, round($interval*1.2))}] }
			2 { set interval [expr {$reps == 0 ? 1 : $reps == 1 ? 6 : round($interval*$ease/100.0)}] }
			3 { set interval [expr {$reps == 0 ? 4 : round($interval*$ease/100.0*1.3)}] }
		}
		incr reps
	}

	dict set card ease $ease
	dict set card interval $interval
	dict set card reps $reps
	dict set card reviewed $now
	dict set card due [expr {$now + $interval*$Day}]
	return $card
}


# The due cards out of <cards>, most overdue first; <limit> caps the
# count (0 or less: no cap).  New cards are due now (newCard made them
# due at build time).
proc ::reptrainer::due {cards now {limit 0}} {
	set pairs {}
	set i -1
	foreach card $cards {
		incr i
		if {[dict get $card due] <= $now} {
			lappend pairs [list [dict get $card due] $i $card]
		}
	}
	# lsort is stable: sort by the secondary key (deck order) first, then
	# by due, so equally due cards keep their deck order
	set pairs [lsort -integer -index 0 [lsort -integer -index 1 $pairs]]
	set result {}
	foreach pair $pairs { lappend result [lindex $pair 2] }
	if {$limit > 0 && [llength $result] > $limit} {
		set result [lrange $result 0 [expr {$limit - 1}]]
	}
	return $result
}


# {due new done}: cards due now that were seen before, never seen cards,
# and cards reviewed today.  The first two partition the drill queue.
proc ::reptrainer::counters {cards now} {
	set nDue 0
	set nNew 0
	set nDone 0
	set today [clock format $now -format %Y-%m-%d]

	foreach card $cards {
		set seen [expr {[dict get $card reps] > 0 || [dict get $card lapses] > 0}]
		if {[dict get $card due] <= $now && $seen} { incr nDue }
		if {!$seen && [dict get $card due] <= $now} { incr nNew }
		if {[dict exists $card reviewed] \
			&& [clock format [dict get $card reviewed] -format %Y-%m-%d] eq $today} {
			incr nDone
		}
	}

	return [list $nDue $nNew $nDone]
}


# The cards of <cards> (a dict keyed by position) where <side> is to
# move; a deck can hold White's and Black's cards at once.
proc ::reptrainer::cardsOfSide {cards side} {
	set letter [string index $side 0]
	set result {}
	dict for {_ card} $cards {
		if {[lindex [dict get $card fen] 1] eq $letter} { lappend result $card }
	}
	return $result
}


# One deck out of the freshly built <new> cards and the <old> ones: new
# positions start unscheduled, known positions keep their scheduling
# state (with the moves grown or shrunk to what the repertoire plays
# now), positions of the other side are kept untouched, and positions
# of <side> that the repertoire no longer reaches are dropped.
proc ::reptrainer::mergeCards {old new side} {
	set result {}
	dict for {key card} $new {
		if {[dict exists $old $key]} {
			set prev [dict get $old $key]
			dict set card interval [dict get $prev interval]
			dict set card ease [dict get $prev ease]
			dict set card reps [dict get $prev reps]
			dict set card lapses [dict get $prev lapses]
			dict set card due [dict get $prev due]
			if {[dict exists $prev reviewed]} {
				dict set card reviewed [dict get $prev reviewed]
			}
		}
		dict set result $key $card
	}
	set letter [string index $side 0]
	dict for {key card} $old {
		if {![dict exists $result $key] && [lindex [dict get $card fen] 1] ne $letter} {
			dict set result $key $card
		}
	}
	return $result
}


# ----------------------------------------------------------------------
# Deck file (pure).
# ----------------------------------------------------------------------

# The deck file of <base> (a database path, or the "current-game"
# pseudo base): <home>/training/<name>.deck.
proc ::reptrainer::deckFile {base} {
	return [file join $::scidb::dir::home training \
		"[string map {: _ . _ / _ { } _} [file tail $base]].deck"]
}


# Writes <deck> to <file> atomically: the tmp file is renamed over the
# deck, so a crash never leaves a half-written deck behind.
proc ::reptrainer::saveDeck {deck file} {
	set dir [file dirname $file]
	if {![file isdirectory $dir]} { file mkdir $dir }
	set tmp "$file.tmp"
	set chan [::open $tmp w]
	puts $chan $deck
	close $chan
	file rename -force $tmp $file
}


# The deck stored in <file>, or {} if there is none (or it is not one
# of ours).
proc ::reptrainer::loadDeck {file} {
	variable Version

	if {![file readable $file]} { return {} }
	set chan [::open $file r]
	set deck [string trim [read $chan]]
	close $chan
	if {[catch { dict get $deck version } version] || $version != $Version} { return {} }
	return $deck
}


# ----------------------------------------------------------------------
# Building cards.
# ----------------------------------------------------------------------

# The cards of the game in slot <position>: every position where <side>
# is to move, with all moves played there.  The game in <position> must
# be a scratch slot without subscribers; the walk navigates it.
proc ::reptrainer::cardsFromGame {position side now} {
	set cards {}
	Walk $position [::scidb::game::query $position start] [string index $side 0] $now cards
	return $cards
}


# Depth-first over the mainline and the variations: <key> is the move
# played from the position before it, so the position where the trained
# side moves becomes a card with that move.
proc ::reptrainer::Walk {position key letter now cardsName} {
	upvar 1 $cardsName cards

	::scidb::game::moveto $position $key
	foreach k [::scidb::game::next keys $position] {
		set fen [::scidb::game::query $position movefen $k]
		set san [::scidb::game::query $position move $k]
		if {$fen ne "" && $san ne "" && [lindex $fen 1] eq $letter} {
			set comment [MoveComment $position $k]
			set ckey [Key $fen]
			if {[dict exists $cards $ckey]} {
				set card [dict get $cards $ckey]
				if {[Norm $san] ni [lmap m [dict get $card moves] { Norm $m }]} {
					dict lappend card moves $san
				}
				if {$comment ne "" && ![dict exists $card comment]} {
					dict set card comment $comment
				}
				dict set cards $ckey $card
			} else {
				dict set cards $ckey [newCard $fen [list $san] $now $comment]
			}
		}
		Walk $position $k $letter $now $cardsName
	}
}


# The plain text of any comment attached before or after <key> in
# scratch slot <position>, or "".
proc ::reptrainer::MoveComment {position key} {
	if {[catch { ::scidb::game::moveto $position $key }]} { return "" }
	set parts {}
	foreach which {before after} {
		if {![catch { ::scidb::game::query $position comment $which } xml] && $xml ne ""} {
			set text [PlainComment $xml]
			if {$text ne ""} { lappend parts $text }
		}
	}
	return [join $parts " "]
}


proc ::reptrainer::PlainComment {xml} {
	if {[llength [info commands ::ai::factcheck::plain]]} {
		if {![catch { ::ai::factcheck::plain $xml } text]} {
			return [string trim $text]
		}
	}
	regsub -all {<[^>]*>} $xml " " text
	regsub -all {\s+} [string trim $text] " " text
	return $text
}


# The cards of all games of the repertoire database <base>.
proc ::reptrainer::buildFromBase {base variant side now} {
	variable Slot

	set cards {}
	set count [::scidb::db::count games $base $variant]
	if {$count == 0} { return $cards }

	if {![::scidb::game::query $Slot open?]} { ::scidb::game::new $Slot $variant }
	for {set number 0} {$number < $count} {incr number} {
		if {[catch { ::scidb::game::load $Slot $base $variant $number } err]} {
			puts stderr "reptrainer: game $number of $base: $err"
			continue
		}
		Walk $Slot [::scidb::game::query $Slot start] [string index $side 0] $now cards
	}
	catch { ::scidb::game::release $Slot }
	return $cards
}


# The cards of the current game.  The game is duplicated into the
# scratch slot for the walk; the visible game is not disturbed.
proc ::reptrainer::buildFromCurrentGame {side now} {
	variable Slot

	if {[::scidb::game::query $Slot open?]} {
		catch { ::scidb::game::release $Slot }
	}
	if {[catch {
		::scidb::game::duplicate $Slot [::scidb::game::current] modified
		cardsFromGame $Slot $side $now
	} result]} {
		catch { ::scidb::game::release $Slot }
		return -code error $result
	}
	catch { ::scidb::game::release $Slot }
	return $result
}


# ----------------------------------------------------------------------
# System One decisions (Jev).
# ----------------------------------------------------------------------

# 1. Default training side (reptrainer_side) for an opening source whose
# database type is not already OpeningsWhite or OpeningsBlack.  Explicit
# "white" / "black" words decide by rule; opening names ("Caro-Kann",
# "London System") ask the classifier via chooseSync.
proc ::reptrainer::sideRule {clue} {
	set t [string tolower [string trim $clue]]
	if {$t eq ""} { return "" }
	set w [regexp {\ywhite\y} $t]
	set b [regexp {\yblack\y} $t]
	if {$w && !$b} { return white }
	if {$b && !$w} { return black }
	return ""
}


proc ::reptrainer::sideState {clue} {
	return "source=[string trim $clue]"
}


proc ::reptrainer::sideQuestion {} {
	variable SideCriteria

	return [dict create type choice \
		instructions "A chess player is opening a repertoire source with this name or header to drill opening moves. Which side (white or black) is this repertoire for? Answer unsure if the name does not indicate a White or Black opening repertoire." \
		criteria $SideCriteria]
}


proc ::reptrainer::inferSide {clue {fallback white}} {
	set rule [sideRule $clue]
	if {$rule ne ""} { return $rule }
	set clue [string trim $clue]
	if {$clue eq ""} { return $fallback }
	if {[llength [info commands ::ai::systemone::chooseSync]] == 0} { return $fallback }
	set pick [::ai::systemone::chooseSync reptrainer_side [sideState $clue] [sideQuestion] \
		-timeout 1500 -threshold 0.7]
	if {$pick in {white black}} { return $pick }
	return $fallback
}


# 2. Repertoire comment role (reptrainer_note): whether a move comment
# is a safe pre-move hint, a post-answer explanation, or non-instructive
# noise.  A comment that literally contains an expected move's SAN is
# never allowed to be a pre-move hint.
proc ::reptrainer::CleanNote {comment} {
	regsub -all {\[%[^\]]*\]} $comment " " s
	regsub -all {\s+} [string trim $s] " " s
	return $s
}


proc ::reptrainer::noteContainsMove {comment moves} {
	foreach m $moves {
		set bare [Norm $m]
		if {$bare eq ""} { continue }
		set esc [regsub -all {([\\.*+?^$()\[\]{}|])} $bare {\\\1}]
		set pat [format {(?:^|[^[:alnum:]])%s(?:$|[^[:alnum:]])} $esc]
		if {[regexp $pat $comment]} {
			return 1
		}
	}
	return 0
}


proc ::reptrainer::noteRule {comment {moves {}}} {
	set clean [CleanNote $comment]
	if {$clean eq ""} { return none }
	set rest $clean
	regsub -all {(?:^|\s)[+-]?\d+(?:\.\d+)?/\d+(?=\s|$)} $rest " " rest
	regsub -all {(?:^|\s)\d+:\d+(?::\d+)?(?=\s|$)} $rest " " rest
	if {![regexp {[[:alpha:]]{3,}} $rest]} { return noise }
	return ""
}


proc ::reptrainer::noteState {fen moves comment} {
	return "fen=$fen moves=[join $moves ,] comment=[CleanNote $comment]"
}


proc ::reptrainer::noteQuestion {} {
	variable NoteCriteria

	return [dict create type choice \
		instructions "A chess opening repertoire card has this comment on the repertoire move(s). Decide whether the comment is a non-spoiling pre-move hint, a post-move explanation (or anything that names or gives away the move), or non-instructive noise." \
		criteria $NoteCriteria]
}


proc ::reptrainer::NoteFallback {} {
	return none
}


proc ::reptrainer::decideNote {fen moves comment script} {
	set rule [noteRule $comment $moves]
	if {$rule ne ""} {
		after 0 [list {*}$script [list ok 1 label $rule confidence 1.0 source rules]]
		return
	}
	if {[llength [info commands ::ai::decide]] == 0} {
		after 0 [list {*}$script [list ok 1 label [NoteFallback] confidence {} source rules]]
		return
	}
	::ai::decide reptrainer_note [noteState $fen $moves $comment] [noteQuestion] \
		[namespace code [list OnNoteDecided $comment $moves $script]] \
		-fallback [namespace code NoteFallback]
}


proc ::reptrainer::OnNoteDecided {comment moves script decision} {
	if {[dict get $decision ok] && [dict get $decision label] eq "hint"
		&& [noteContainsMove $comment $moves]} {
		# Hard firewall: a comment that literally names an expected move
		# must never appear before the player answers.
		dict set decision label explanation
	}
	uplevel #0 [list {*}$script $decision]
}


# 3. SM-2 self-grade recommendation (reptrainer_grade): after a right
# answer, suggests hard/good/easy from response time, card history and
# position context without taking the grade choice away from the user.
proc ::reptrainer::gradeState {card san elapsedMs} {
	set fen [dict get $card fen]
	set moves [dict get $card moves]
	set fullmove [expr {[llength $fen] >= 6 && [string is integer -strict [lindex $fen 5]] ? [lindex $fen 5] : 1}]
	return [format "fen=%s move=%s moves=%s fullmove=%d alternatives=%d elapsed_ms=%d reps=%d lapses=%d interval=%d ease=%d" \
		$fen [Norm $san] [join $moves ,] $fullmove [llength $moves] \
		$elapsedMs [dict get $card reps] [dict get $card lapses] \
		[dict get $card interval] [dict get $card ease]]
}


proc ::reptrainer::gradeQuestion {} {
	variable GradeCriteria

	return [dict create type choice \
		instructions "The player answered a chess opening repertoire flashcard. Recommend the SM-2 self-grade (hard, good, or easy) from the response time, the card's review history, and the position." \
		criteria $GradeCriteria]
}


proc ::reptrainer::GradeFallback {} {
	return ""
}


proc ::reptrainer::decideGrade {card san elapsedMs script} {
	if {[llength [info commands ::ai::decide]] == 0} {
		after 0 [list {*}$script [list ok 1 label [GradeFallback] confidence {} source rules]]
		return
	}
	::ai::decide reptrainer_grade [gradeState $card $san $elapsedMs] [gradeQuestion] \
		[namespace code [list OnGradeDecided $card $script]] \
		-fallback [namespace code GradeFallback]
}


proc ::reptrainer::OnGradeDecided {card script decision} {
	if {[dict get $decision ok] && [dict get $decision label] eq "easy"
		&& [dict get $card reps] == 0 && [dict get $card lapses] > 0} {
		# A card that already lapsed and has not yet completed a clean
		# repetition must not jump straight to Easy's 4-day interval.
		dict set decision label good
	}
	uplevel #0 [list {*}$script $decision]
}


# ----------------------------------------------------------------------
# Drill.
# ----------------------------------------------------------------------

# True while the drill waits for the board's move; ::move::addMove then
# routes the move to ::reptrainer::answered.  Only moves on the drill's
# own game are taken (the user may have switched to another game).
proc ::reptrainer::active {} {
	variable Vars

	return [expr {$Vars(running)
		&& $Vars(state) eq "answer"
		&& [::scidb::game::current] == $Vars(gameSlot)}]
}


# The answer to the current card, as SAN played on the board.
proc ::reptrainer::answered {san} {
	variable Vars
	variable Delay
	variable mc

	if {![active]} { return }
	set san [Norm $san]
	if {$san eq ""} { return }

	set elapsed [expr {$Vars(shownAt) > 0 ? max(0, [clock milliseconds] - $Vars(shownAt)) : 0}]
	set Vars(lastSan) $san
	set expected [dict get $Vars(card) moves]
	if {$san in [lmap m $expected { Norm $m }]} {
		set Vars(state) grade
		GradeButtons normal
		Instruction [GradeInstruction $san $Vars(suggestedGrade) [PostNote]]
		decideGrade $Vars(card) $san $elapsed \
			[namespace code [list OnSuggestedGrade $Vars(cardSeq) $san]]
	} else {
		set Vars(state) show
		GradeButtons disabled
		ApplyGrade 0
		PlayExpected [lindex $expected 0]
		Instruction [WrongInstruction $san $expected [PostNote]]
		CancelPending
		set Vars(after) [after $Delay [namespace code NextCard]]
	}
}


proc ::reptrainer::OnSuggestedGrade {seq san decision} {
	variable Vars

	if {!$Vars(running) || $seq != $Vars(cardSeq) || $Vars(state) ne "grade"} { return }
	set grade [expr {[dict get $decision ok] ? [dict get $decision label] : ""}]
	if {$grade ni {hard good easy}} { return }
	set Vars(suggestedGrade) $grade
	Instruction [GradeInstruction $san $grade [PostNote]]
	if {[winfo exists [::util::place::playingBody $Vars(dlg)].drill.grades.$grade]} {
		catch { focus [::util::place::playingBody $Vars(dlg)].drill.grades.$grade }
	}
}


proc ::reptrainer::OnCardNote {seq comment decision} {
	variable Vars
	variable mc

	if {!$Vars(running) || $seq != $Vars(cardSeq)} { return }
	set role [expr {[dict get $decision ok] ? [dict get $decision label] : "none"}]
	set clean [CleanNote $comment]
	if {$clean eq "" || $role ni {hint explanation}} { return }
	set Vars(noteRole) $role
	set Vars(noteText) $clean
	if {$role eq "hint" && $Vars(state) eq "answer"} {
		Instruction "[format $mc::YourMove [SideName $Vars(side)]] -- $clean"
	} elseif {$role eq "explanation" && $Vars(state) eq "grade"} {
		Instruction [GradeInstruction $Vars(lastSan) $Vars(suggestedGrade) $clean]
	} elseif {$role eq "explanation" && $Vars(state) eq "show"} {
		Instruction [WrongInstruction $Vars(lastSan) [dict get $Vars(card) moves] $clean]
	}
}


proc ::reptrainer::PostNote {} {
	variable Vars

	return [expr {$Vars(noteRole) eq "explanation" ? $Vars(noteText) : ""}]
}


proc ::reptrainer::GradeLabel {grade} {
	variable mc

	switch -- $grade {
		hard { return $mc::Hard }
		good { return $mc::Good }
		easy { return $mc::Easy }
		default { return $grade }
	}
}


proc ::reptrainer::GradeInstruction {san suggested note} {
	variable mc

	if {$suggested in {hard good easy}} {
		set text [format $mc::CorrectSuggested $san [GradeLabel $suggested]]
	} else {
		set text [format $mc::Correct $san]
	}
	if {$note ne ""} { append text " -- $note" }
	return $text
}


proc ::reptrainer::WrongInstruction {san expected note} {
	variable mc

	set text [format $mc::Wrong $san [join $expected {, }]]
	if {$note ne ""} { append text " -- $note" }
	return $text
}


# A grade button (1 hard, 2 good, 3 easy) for the correctly answered
# card; a wrong answer has already been graded Again in answered.
proc ::reptrainer::grade {n} {
	variable Vars

	if {$Vars(state) ne "grade"} { return }
	ApplyGrade $n
	NextCard
}


# Grades the current card, stores it in the deck and saves the deck.
proc ::reptrainer::ApplyGrade {n} {
	variable Vars

	set card [review $Vars(card) $n [clock seconds]]
	set key [Key [dict get $card fen]]
	dict set Vars(deck) cards $key $card
	set Vars(card) $card
	if {$n == 0} {
		# Again: the card returns within this session
		lappend Vars(queue) $card
	}
	saveDeck $Vars(deck) $Vars(deckFile)
	UpdateCounter
}


# Shows the next card, or finishes the session.
proc ::reptrainer::NextCard {} {
	variable Vars
	variable mc

	if {!$Vars(running)} { return }

	if {$Vars(index) >= [llength $Vars(queue)]} {
		set Vars(running) 0
		set Vars(state) done
		GradeButtons disabled
		Instruction $mc::Done
		UpdateCounter
		return
	}

	set Vars(card) [lindex $Vars(queue) $Vars(index)]
	incr Vars(index)
	set seq [incr Vars(seq)]
	set Vars(cardSeq) $seq
	set Vars(shownAt) [clock milliseconds]
	set Vars(lastSan) {}
	set Vars(suggestedGrade) {}
	set Vars(noteRole) {}
	set Vars(noteText) {}
	set Vars(state) answer
	GradeButtons disabled
	if {![ShowBoard [dict get $Vars(card) fen]]} { return }
	Instruction [format $mc::YourMove [SideName $Vars(side)]]
	if {[dict exists $Vars(card) comment] && [dict get $Vars(card) comment] ne ""} {
		set comment [dict get $Vars(card) comment]
		decideNote [dict get $Vars(card) fen] [dict get $Vars(card) moves] $comment \
			[namespace code [list OnCardNote $seq $comment]]
	}
}


# Puts <fen> on the drill board.  Only the drill's own scratch game is
# ever cleared; if the user switched to another game, the drill stops.
proc ::reptrainer::ShowBoard {fen} {
	variable Vars
	variable mc

	if {[::scidb::game::current] != $Vars(gameSlot)} {
		catch { ::application::pgn::select $Vars(gameSlot) }
	}
	if {[::scidb::game::current] != $Vars(gameSlot)} {
		set Vars(running) 0
		set Vars(state) done
		GradeButtons disabled
		Instruction $mc::LeftBoard
		return 0
	}
	catch { ::scidb::game::clear $fen }
	return 1
}


# Plays the expected move on the board after a wrong answer.
proc ::reptrainer::PlayExpected {san} {
	variable Vars

	if {[::scidb::game::current] != $Vars(gameSlot)} { return }
	catch { ::scidb::game::move $san ; ::scidb::game::go 1 }
}


# Ends the session: the deck is saved, the drill board is left empty
# and reusable, the board orientation is restored.
proc ::reptrainer::stop {} {
	variable Vars
	variable Options
	variable mc

	CancelPending
	incr Vars(seq)
	if {$Vars(running) && [info exists Vars(deck)] && [llength $Vars(deck)] && [llength $Vars(deckFile)]} {
		saveDeck $Vars(deck) $Vars(deckFile)
	}
	if {$Vars(state) ne {}} {
		set Vars(state) {}
		GradeButtons disabled
		Instruction $mc::Stopped
	}
	set Vars(running) 0

	if {$Vars(gameSlot) >= 0
		&& [::scidb::game::query $Vars(gameSlot) open?]
		&& [::scidb::game::current] == $Vars(gameSlot)
		&& [llength $Vars(startFen)]} {
		catch { ::scidb::game::clear $Vars(startFen) }
		catch { ::game::stateChanged $Vars(gameSlot) 0 }
		catch { ::game::lockChanged $Vars(gameSlot) 0 }
	}
	if {$Options(flipBoard)
		&& [::board::diagram::rotated? $::application::board::board] != $Vars(wasRotated)} {
		catch { ::application::board::Rotate $::application::board::Vars(widget:frame) }
	}
	set Vars(gameSlot) -1
}


# Starts drilling the freshly built <cards> as <side> (variant
# <variant>): merges them into the deck, opens the drill board (a
# scratch game) and shows the first card.
proc ::reptrainer::drill {parent cards side variant} {
	variable Vars
	variable mc

	if {![dict size $cards]} {
		::dialog::info \
			-parent $parent \
			-message [format $mc::Empty [SideName $side]] \
			-detail $mc::EmptyDetail \
			;
		return
	}

	stop

	set now [clock seconds]
	set file [deckFile [expr {$Vars(sourceBase) eq "" ? "current-game" : $Vars(sourceBase)}]]
	set old [expr {[dict exists [set deck [loadDeck $file]] cards] ? [dict get $deck cards] : {}}]
	set deck [dict create \
		version 1 \
		source $Vars(sourceBase) \
		side $side \
		built $now \
		cards [mergeCards $old $cards $side] \
	]

	set slot [::game::new $parent -variant $variant]
	if {$slot < 0} {
		::dialog::info -parent $parent -message $mc::NoScratch -detail $mc::NoScratchDetail
		return
	}
	::application::switchTab board

	set Vars(deck) $deck
	set Vars(deckFile) $file
	set Vars(side) $side
	set Vars(gameSlot) $slot
	set Vars(startFen) [::scidb::game::query fen]
	set Vars(wasRotated) [::board::diagram::rotated? $::application::board::board]
	Orient $side
	set Vars(queue) [due [cardsOfSide [dict get $deck cards] $side] $now]
	set Vars(index) 0
	set Vars(running) 1
	saveDeck $deck $file
	UpdateCounter
	NextCard
}


# ----------------------------------------------------------------------
# Trainer dialog.
# ----------------------------------------------------------------------

# Opens the trainer: the dialog picks the source and the side, Start
# builds the cards and drills them.  <base> (and its <variant>) preselect
# a repertoire database; without it the current base is used if it is
# one, else the sole open repertoire database, else the current game.
proc ::reptrainer::open {parent {base ""} {variant Normal}} {
	variable Vars
	variable mc

	set dlg $parent.__reptrainer__
	if {[winfo exists $dlg]} {
		raise $dlg
		return
	}
	set Vars(dlg) $dlg

	set sources {}
	if {$base ne ""} {
		lappend sources [list [::util::databaseName $base] $base $variant [DefaultSide $base]]
	}
	foreach b [::application::database::repertoireBases [expr {$base ne ""}] $variant] {
		lappend sources [list [::util::databaseName $b] $b $variant [DefaultSide $b]]
	}
	# The read-only sample also supplies positions for a first training session.
	set sample [::application::sample::location]
	if {$sample ne $base && [::scidb::db::get open? $sample]
		&& $variant in [::scidb::db::get variants $sample]
		&& [::scidb::db::count games $sample $variant] > 0} {
		lappend sources [list [::util::databaseName $sample] $sample $variant white]
	}
	lappend sources [list $mc::CurrentGame "" [::scidb::game::query variant?] [DefaultGameSide]]
	set Vars(sources) $sources

	# preselect: the asked base, else the current base if it is a
	# repertoire, else the only repertoire database, else the current game
	set Vars(sourceIndex) [expr {[llength $sources] - 1}]
	if {$base ne ""} {
		set i [lsearch -exact -index 1 $sources $base]
		if {$i >= 0} { set Vars(sourceIndex) $i }
	} else {
		set current [::scidb::db::get name]
		if {![catch { ::scidb::db::get type $current } type] && $type in {Openings OpeningsWhite OpeningsBlack}} {
			set i [lsearch -exact -index 1 $sources $current]
			if {$i >= 0} { set Vars(sourceIndex) $i }
		} elseif {[llength $sources] > 1} {
			set Vars(sourceIndex) 0
		}
	}
	lassign [lindex $sources $Vars(sourceIndex)] Vars(sourceLabel) _ _ Vars(sideChoice)

	toplevel $dlg -class Scidb
	wm title $dlg $mc::Title
	wm transient $dlg [winfo toplevel $parent]
	wm withdraw $dlg
	wm protocol $dlg WM_DELETE_WINDOW [namespace code [list Close $dlg]]
	bind $dlg <Escape> [namespace code [list Close $dlg]]

	set setup [ttk::frame [::util::place::playingBody $dlg].setup]
	set drill [ttk::frame [::util::place::playingBody $dlg].drill]
	pack $setup -side top -fill x -padx $::theme::padx -pady $::theme::pady
	pack $drill -side top -fill x -padx $::theme::padx -pady [list 0 $::theme::pady]

	ttk::label $setup.lsource -text $mc::Source
	ttk::combobox $setup.source \
		-state readonly \
		-textvariable [namespace current]::Vars(sourceLabel) \
		-values [lmap s $sources { lindex $s 0 }] \
		;
	bind $setup.source <<ComboboxSelected>> [namespace code SourceChanged]

	ttk::label $setup.lside -text $mc::TrainSide
	ttk::radiobutton $setup.white \
		-text $mc::White -value white -variable [namespace current]::Vars(sideChoice)
	ttk::radiobutton $setup.black \
		-text $mc::Black -value black -variable [namespace current]::Vars(sideChoice)

	ttk::checkbutton $setup.flip \
		-text $mc::FlipBoard \
		-variable [namespace current]::Options(flipBoard) \
		;

	ttk::button $setup.start -text $mc::Start -command [namespace code StartFromDialog]
	ttk::button $setup.close -text $mc::Close -command [namespace code [list Close $dlg]]

	grid $setup.lsource -row 0 -column 0 -sticky w
	grid $setup.source -row 0 -column 1 -columnspan 5 -sticky ew -padx [list 8 0]
	grid $setup.lside -row 1 -column 0 -sticky w -pady [list 6 0]
	grid $setup.white -row 1 -column 1 -sticky w -padx [list 8 0] -pady [list 6 0]
	grid $setup.black -row 1 -column 2 -sticky w -pady [list 6 0]
	grid $setup.flip -row 2 -column 1 -columnspan 2 -sticky w -padx [list 8 0]
	grid $setup.start -row 3 -column 5 -sticky e -pady [list 8 0]
	grid $setup.close -row 3 -column 0 -sticky w -pady [list 8 0]
	grid columnconfigure $setup 5 -weight 1

	ttk::label $drill.counter -text "" -anchor w
	ttk::label $drill.instruction \
		-text "" -anchor w -justify left -wraplength 420 -font TkDefaultFont
	set grades [ttk::frame $drill.grades]
	ttk::button $grades.hard \
		-text $mc::Hard -state disabled -command [namespace code { grade 1 }]
	ttk::button $grades.good \
		-text $mc::Good -state disabled -command [namespace code { grade 2 }]
	ttk::button $grades.easy \
		-text $mc::Easy -state disabled -command [namespace code { grade 3 }]
	ttk::button $drill.stop -text $mc::Stop -command [namespace code stop]
	pack $grades.hard $grades.good $grades.easy -side left
	pack $drill.stop -side right
	pack $drill.counter -side top -fill x -pady [list 0 4]
	pack $drill.instruction -side top -fill x -pady [list 0 6]
	pack $grades -side left

	::util::place::besideBoard $dlg [winfo toplevel $parent]
	wm deiconify $dlg
	raise $dlg
	focus $dlg
}


proc ::reptrainer::SourceChanged {} {
	variable Vars

	set i [lsearch -exact [lmap s $Vars(sources) { lindex $s 0 }] $Vars(sourceLabel)]
	if {$i < 0} { return }
	set Vars(sourceIndex) $i
	lassign [lindex $Vars(sources) $i] _ _ _ Vars(sideChoice)
}


proc ::reptrainer::StartFromDialog {} {
	variable Vars

	if {![winfo exists $Vars(dlg)]} { return }
	lassign [lindex $Vars(sources) $Vars(sourceIndex)] _ base variant _
	set Vars(sourceBase) $base
	set Vars(built) {}
	::widget::busyOperation [namespace code [list Build $base $variant $Vars(sideChoice)]]
	drill $Vars(dlg) $Vars(built) $Vars(sideChoice) $variant
}


# Builds the cards of the source (inside the busy cursor).
proc ::reptrainer::Build {base variant side} {
	variable Vars

	set now [clock seconds]
	if {$base eq ""} {
		set Vars(built) [buildFromCurrentGame $side $now]
	} else {
		set Vars(built) [buildFromBase $base $variant $side $now]
	}
}


proc ::reptrainer::Close {dlg} {
	variable Vars

	if {$dlg ne $Vars(dlg)} { return }
	stop
	set Vars(dlg) {}
	set Vars(deckFile) {}
	set Vars(instruction) {}
	destroy $dlg
}


# ----------------------------------------------------------------------
# Helpers.
# ----------------------------------------------------------------------

# SAN without the check/mate suffix; both sides of the comparison come
# from Scidb's own SAN, so the bare move is enough.
proc ::reptrainer::Norm {san} {
	return [string trimright [string map {+ {} # {}} $san]]
}


proc ::reptrainer::SideName {side} {
	variable mc

	return [expr {$side eq "black" ? $mc::Black : $mc::White}]
}


# The side a repertoire database is for; plain opening databases infer
# the side from the name or let the last choice stand.
proc ::reptrainer::DefaultSide {base} {
	variable Vars

	set type ""
	catch { set type [::scidb::db::get type $base] }
	switch -- $type {
		OpeningsWhite { return white }
		OpeningsBlack { return black }
		default {
			set name [file rootname [file tail $base]]
			catch { set name [::util::databaseName $base] }
			return [inferSide $name $Vars(sideChoice)]
		}
	}
}


proc ::reptrainer::GameClue {} {
	if {[catch { ::scidb::game::tags -userSuppliedOnly 1 } pairs]} { return "" }
	set parts {}
	foreach pair $pairs {
		lassign $pair tag value
		set value [string trim $value]
		if {$tag in {Event Opening Variation White Black} && $value ni {"" "?"}} {
			lappend parts "$tag=$value"
		}
	}
	return [join $parts " "]
}


proc ::reptrainer::DefaultGameSide {} {
	variable Vars

	return [inferSide [GameClue] $Vars(side)]
}


# Rotates the board so the trained side is at the bottom.
proc ::reptrainer::Orient {side} {
	variable Options

	if {!$Options(flipBoard)} { return }
	set want [expr {$side eq "black"}]
	if {$want != [::board::diagram::rotated? $::application::board::board]} {
		catch { ::application::board::Rotate $::application::board::Vars(widget:frame) }
	}
}


proc ::reptrainer::CancelPending {} {
	variable Vars

	if {$Vars(after) ne {}} {
		after cancel $Vars(after)
		set Vars(after) {}
	}
}


proc ::reptrainer::GradeButtons {state} {
	variable Vars

	set dlg $Vars(dlg)
	if {![winfo exists $dlg]} { return }
	foreach b {hard good easy} {
		catch { [::util::place::playingBody $dlg].drill.grades.$b configure -state $state }
	}
}


proc ::reptrainer::Instruction {text} {
	variable Vars

	set Vars(instruction) $text
	set dlg $Vars(dlg)
	if {![winfo exists $dlg]} { return }
	catch { [::util::place::playingBody $dlg].drill.instruction configure -text $text }
}


proc ::reptrainer::UpdateCounter {} {
	variable Vars
	variable mc

	if {![llength $Vars(deck)]} { return }
	lassign [counters [cardsOfSide [dict get $Vars(deck) cards] $Vars(side)] [clock seconds]] \
		nDue nNew nDone
	set text [format $mc::Counter $nDue $nNew $nDone]
	set dlg $Vars(dlg)
	if {[winfo exists $dlg]} {
		catch { [::util::place::playingBody $dlg].drill.counter configure -text $text }
	}
}


proc ::reptrainer::WriteOptions {chan} {
	::options::writeItem $chan [namespace current]::Options
}

::options::hookWriter ::reptrainer::WriteOptions

# vi:set ts=3 sw=3:
