# ======================================================================
# Endgame trainer -- practise standard endings against the engine with a
# tablebase as the referee (the Lichess / Chess.com / Fritz practice idea).
#
# The Extras menu's "Endgame Trainer..." opens a window listing the built-in
# endings by theme (basic mates, pawn endings, rook endings, queen vs pawn).
# Starting one puts its FEN on the board; the user plays the side to move,
# which is the side that has to win (goal win) or to hold the draw (goal
# draw). The engine defends.
#
# After every user move the position is probed: local Syzygy tables first
# (::tablebase::LocalAnswer), else the Lichess tablebase server when online
# lookups are allowed. If the move changes the result the trainer says so at
# once ("This move lets the win slip.") and stops for Retry Move, which takes
# the move back. The engine (pluggable, via ::ai::engine) prefers a
# tablebase-best defence whenever the tablebase covers its position, so it
# never blunders the ending away; without a tablebase answer it searches as
# usual. A win goal is met by mate; a draw goal once the defender has kept
# the draw for HoldMoves of its own moves (or the game ends drawn). Progress
# (solved / attempts per ending) is kept in <Scidb home>/training/endgames.dat.
#
#   ::endtrainer::open .application        the trainer window (Extras menu)
#   ::endtrainer::Start <id> ?<index>?     start an ending programmatically
#   ::endtrainer::UserMove <san>           a user move (the board does this)
#   ::endtrainer::Retry                    take the last move back
#
# The pure helpers (VerdictOf, MoveFault, BestMove, Load/SaveProgress, the
# catalog) are covered by tests/test_app_endtrainer.tcl; the FENs were
# verified against tablebase.lichess.ovh with tests/verify_endgame_fens.tcl.
# ======================================================================

::util::source endgame-trainer

namespace eval ::endtrainer {
namespace eval mc {

set Title			"Endgame Trainer"
set Ending			"Ending"
set Solved			"Solved"
set Progress		"%d/%d"
set Start			"Start"
set Close			"Close"
set Retry			"Retry Move"
set Continue		"Continue"
set Next			"Next Position"
set GiveUp			"Give Up"
set WinGoal			"Goal: win this position."
set DrawGoal		"Goal: hold the draw for %d moves."
set HoldMoves		"%d of %d moves held."
set YourMove		"Your move."
set Thinking		"The engine is defending..."
set NotYourTurn		"It is not your turn."
set NotAtEnd		"Return to the end of the game to move."
set LetWinSlip		"This move lets the win slip."
set LetDrawSlip		"This move lets the draw slip."
set NowLosing		"This move loses the position."
set SolvedMate		"Checkmate - the goal is reached."
set SolvedDraw		"Draw held - the goal is reached."
set Failed			"The goal was not reached (%s)."
set Mated			"you have been mated"
set NoGoalReached	"the game is over"
set Stalemate		"stalemate"
set FiftyMoves		"the fifty-move rule"
set Repetition		"threefold repetition"
set Material		"insufficient mating material"
set EngineGone		"The engine did not answer; the session is over."
set NoSlot			"No free game slot; close a game on the board first."
set NoTables		"No tablebase answer for this position; the engine plays on its own."

} ;# namespace mc

# Persisted across sessions (WriteOptions below).
array set Options {
	online	1
	movetime	600
}

# A draw goal is met once the defender has kept the draw for this many of
# its own moves (or the game ends drawn).  A win goal is met by mate.
variable HoldMoves 8
variable CacheSize 400

# The {fen verdict} pairs of one ending; used to build Catalog below (a proc
# so the FEN lists stay readable).
proc Positions {verdict fens} {
	set out {}
	foreach fen $fens { lappend out [list $fen $verdict] }
	return $out
}

# The themes, in menu order: {id title}.
variable ThemeOrder {
	{mates	"Basic Mates"}
	{pawns	"Pawn Endings"}
	{rooks	"Rook Endings"}
	{queen	"Queen Endings"}
}

# All the endings.  Each is a dict: id, theme, title, goal (win|draw) and
# positions, a list of {fen verdict} pairs.  The verdict is the tablebase
# category of the side to move, as returned for the position (verified
# online; tests/verify_endgame_fens.tcl re-checks it when run).
variable Catalog [list \
	[dict create id kqk theme mates title "King and Queen vs King" goal win positions [Positions win {
		{8/8/8/4k3/8/8/8/4KQ2 w - - 0 1}
		{8/8/8/8/3k4/8/8/KQ6 w - - 0 1}
		{8/8/4k3/8/8/8/8/K5Q1 w - - 0 1}
		{8/8/8/8/4k3/8/8/3QK3 w - - 0 1}
	}]] \
	[dict create id krk theme mates title "King and Rook vs King" goal win positions [Positions win {
		{8/8/8/4k3/8/8/8/4KR2 w - - 0 1}
		{8/8/8/8/3k4/8/8/KR6 w - - 0 1}
		{8/4k3/8/8/8/8/8/K6R w - - 0 1}
		{8/8/4k3/8/8/8/8/2KR4 w - - 0 1}
	}]] \
	[dict create id kbbk theme mates title "Two Bishops vs King" goal win positions [Positions win {
		{8/8/8/4k3/8/8/8/2B1KB2 w - - 0 1}
		{8/8/8/8/4k3/8/8/2B1KB2 w - - 0 1}
		{8/8/8/8/8/5k2/8/2B1KB2 w - - 0 1}
		{8/8/8/8/5k2/8/8/1B2K1B1 w - - 0 1}
	}]] \
	[dict create id kbnk theme mates title "Bishop and Knight vs King" goal win positions [Positions win {
		{8/8/8/4k3/8/8/8/2B1KN2 w - - 0 1}
		{8/8/8/8/4k3/8/8/2B1KN2 w - - 0 1}
		{8/8/8/8/3k4/8/8/2B1KN2 w - - 0 1}
		{8/8/8/8/6k1/8/8/2B1KN2 w - - 0 1}
	}]] \
	[dict create id kpk-win theme pawns title "King and Pawn: the key squares" goal win positions [Positions win {
		{8/8/8/3P4/3K4/8/8/7k w - - 0 1}
		{8/8/8/8/3K4/3P4/8/7k w - - 0 1}
		{8/8/8/8/4K3/4P3/8/7k w - - 0 1}
		{8/8/8/8/2K5/2P5/8/7k w - - 0 1}
	}]] \
	[dict create id kpk-draw theme pawns title "King and Pawn: the opposition" goal draw positions [Positions draw {
		{8/8/8/3k4/3P4/3K4/8/8 w - - 0 1}
		{8/8/3k4/3P4/3K4/8/8/8 b - - 0 1}
		{8/8/8/4k3/4P3/4K3/8/8 b - - 0 1}
		{k7/8/K7/P7/8/8/8/8 b - - 0 1}
	}]] \
	[dict create id lucena theme rooks title "Lucena: building a bridge" goal win positions [Positions win {
		{3K4/3P2k1/8/8/8/8/2r5/5R2 w - - 0 1}
		{4K3/4P1k1/8/8/8/1r6/8/5R2 w - - 0 1}
		{K7/P3k3/8/8/8/8/r7/3R4 w - - 0 1}
		{4K3/1k2P3/8/8/8/8/5r2/2R5 w - - 0 1}
	}]] \
	[dict create id philidor theme rooks title "Philidor: the third-rank defence" goal draw positions [Positions draw {
		{8/8/8/8/4pk2/R7/7r/4K3 w - - 0 1}
		{8/8/8/8/3pk3/R7/7r/3K4 w - - 0 1}
		{8/8/8/8/2pk4/R7/7r/2K5 w - - 0 1}
		{4k3/7R/r7/4PK2/8/8/8/8 w - - 0 1}
		{4k3/7R/r7/4PK2/8/8/8/8 b - - 0 1}
	}]] \
	[dict create id qpk-win theme queen title "Queen vs Pawn: winning" goal win positions [Positions win {
		{8/8/8/8/3k4/8/3p4/3K1Q2 w - - 0 1}
		{8/8/8/3k4/8/8/3p4/3K1Q2 w - - 0 1}
		{8/8/8/8/3k4/8/3p4/3KQ3 w - - 0 1}
		{5Q2/8/8/8/8/2k5/2p5/2K5 w - - 0 1}
	}]] \
	[dict create id qpk-draw theme queen title "Queen vs Pawn: holding" goal draw positions [Positions draw {
		{7Q/8/8/8/8/2k5/2p5/7K b - - 0 1}
		{8/8/8/8/8/2k5/2p4Q/7K b - - 0 1}
		{Q7/8/8/8/8/1k6/1p6/7K b - - 0 1}
		{Q7/8/8/8/8/3k4/3p4/7K b - - 0 1}
	}]] \
]

variable Index [dict create]
foreach e $Catalog { dict set Index [dict get $e id] $e }

variable Cache [dict create]

array set Priv {
	dialog			{}
	active			0
	busy			0
	pos				0
	endingId		{}
	goal			win
	index			0
	userSide		w
	engineSide		b
	phase			idle
	fault			{}
	held			0
	verdict			{}
	recorded		0
	status			""
	treeIds			{}
}

} ;# namespace endtrainer


# ----------------------------------------------------------------------
# The catalog
# ----------------------------------------------------------------------

proc ::endtrainer::Themes {} {
	variable ThemeOrder
	return $ThemeOrder
}


proc ::endtrainer::Endings {theme} {
	variable Catalog
	set out {}
	foreach e $Catalog {
		if {[dict get $e theme] eq $theme} { lappend out $e }
	}
	return $out
}


proc ::endtrainer::Ending {id} {
	variable Index
	if {[dict exists $Index $id]} { return [dict get $Index $id] }
	return ""
}


# The {fen verdict} pairs of an ending ({} for an unknown id).
proc ::endtrainer::PositionsOf {id} {
	set ending [Ending $id]
	if {$ending eq ""} { return {} }
	return [dict get $ending positions]
}


# ----------------------------------------------------------------------
# Progress: solved / attempts per ending, in
# <Scidb home>/training/endgames.dat.
# ----------------------------------------------------------------------

proc ::endtrainer::ProgressPath {} {
	return [file join $::scidb::dir::home training endgames.dat]
}


# The progress file as a dict: ending id -> {attempts N done M}.
proc ::endtrainer::LoadProgress {{file ""}} {
	if {$file eq ""} { set file [ProgressPath] }
	set progress [dict create]
	if {![file readable $file]} { return $progress }
	if {[catch {
		set chan [::open $file r]
		set data [read $chan]
		close $chan
	}]} { return $progress }
	foreach line [split $data "\n"] {
		set line [string trim $line]
		if {$line eq "" || [string match "#*" $line]} { continue }
		lassign [split $line] id attempts done
		if {$id eq "" || ![string is integer -strict $attempts]} { continue }
		if {![string is integer -strict $done]} { set done 0 }
		dict set progress $id [list attempts $attempts done $done]
	}
	return $progress
}


# Writes <progress> to <file> atomically (a crash never leaves a half file).
proc ::endtrainer::SaveProgress {progress {file ""}} {
	if {$file eq ""} { set file [ProgressPath] }
	set dir [file dirname $file]
	if {![file isdirectory $dir]} { file mkdir $dir }
	set tmp "$file.tmp"
	set chan [::open $tmp w]
	foreach id [lsort [dict keys $progress]] {
		set e [dict get $progress $id]
		puts $chan [format "%s %d %d" $id [dict get $e attempts] [dict get $e done]]
	}
	close $chan
	file rename -force $tmp $file
}


# {attempts N done M} for an ending, {attempts 0 done 0} when untouched.
proc ::endtrainer::Progress {{id ""}} {
	set progress [LoadProgress]
	if {$id eq ""} { return $progress }
	if {[dict exists $progress $id]} { return [dict get $progress $id] }
	return [list attempts 0 done 0]
}


# Counts one attempt, solved when <success> (callers decide when a session
# ends; RecordAttempt applies the once-per-session guard).
proc ::endtrainer::RecordResult {id success} {
	if {$id eq ""} { return }
	set progress [LoadProgress]
	set e [list attempts 0 done 0]
	if {[dict exists $progress $id]} { set e [dict get $progress $id] }
	dict set e attempts [expr {[dict get $e attempts] + 1}]
	if {$success} { dict set e done [expr {[dict get $e done] + 1}] }
	dict set progress $id $e
	SaveProgress $progress
	return $e
}


# Records the running session once (an attempt, solved when <success>) and
# refreshes the ending list.
proc ::endtrainer::RecordAttempt {success} {
	variable Priv

	if {$Priv(endingId) eq "" || $Priv(recorded)} { return }
	set Priv(recorded) 1
	RecordResult $Priv(endingId) $success
	RefreshTree
}


# ----------------------------------------------------------------------
# Verdicts (pure)
# ----------------------------------------------------------------------

# The verdict of the side to move of a tablebase answer: win, draw, loss or
# "" when there is none.  A cursed win / blessed loss can be held to a draw
# by the fifty-move rule, so it counts as a draw.
proc ::endtrainer::VerdictOf {answer} {
	if {$answer eq ""} { return "" }
	if {[dict exists $answer category]} {
		switch -- [dict get $answer category] {
			win - maybe-win			{ return win }
			loss - maybe-loss		{ return loss }
			draw					{ return draw }
			cursed-win - blessed-loss	{ return draw }
		}
	}
	if {[dict exists $answer checkmate] && [dict get $answer checkmate] eq "true"} { return loss }
	if {[dict exists $answer stalemate] && [dict get $answer stalemate] eq "true"} { return draw }
	return ""
}


# How good an opponent category is for the side to move, lowest first: a
# move that leaves the opponent lost is the mover's best.
proc ::endtrainer::RankOf {category} {
	switch -- $category {
		loss			{ return 0 }
		maybe-loss		{ return 1 }
		blessed-loss	{ return 2 }
		draw			{ return 3 }
		cursed-win		{ return 4 }
		maybe-win		{ return 5 }
		win				{ return 6 }
		default			{ return 7 }
	}
}


# The distance of a move (dtm when the server gives it, else dtz; 0 when
# neither is known).
proc ::endtrainer::Distance {move} {
	foreach key {dtm dtz} {
		if {[dict exists $move $key] && [string is integer -strict [dict get $move $key]]} {
			return [dict get $move $key]
		}
	}
	return 0
}


# The best move of a tablebase answer for the side to move: the one that
# leaves the opponent in the worst category; when the opponent wins either
# way, the longest defence, and when the opponent is lost, the shortest
# mate.  Returns the move dict, or "" without an answer.
proc ::endtrainer::BestMove {answer} {
	if {$answer eq "" || ![dict exists $answer moves]} { return "" }
	set best ""
	set bestRank 99
	set bestD 0
	foreach move [dict get $answer moves] {
		set category "unknown"
		if {[dict exists $move category]} { set category [dict get $move category] }
		set rank [RankOf $category]
		set d [Distance $move]
		if {[BetterMove $rank $d $bestRank $bestD]} {
			set best $move
			set bestRank $rank
			set bestD $d
		}
	}
	return $best
}


# Is a move of <rank>/<d> better than the standing <bestRank>/<bestD>?
proc ::endtrainer::BetterMove {rank d bestRank bestD} {
	if {$rank < $bestRank} { return 1 }
	if {$rank > $bestRank} { return 0 }
	if {$rank >= 5} { return [expr {abs($d) > abs($bestD)}] } ;# lost: resist longest
	if {$rank <= 2} { return [expr {abs($d) < abs($bestD)}] } ;# won: mate soonest
	return 0
}


# The SAN of the best move of an answer (converting UCI when needed).
proc ::endtrainer::BestMoveSan {answer} {
	set move [BestMove $answer]
	if {$move eq ""} { return "" }
	if {[dict exists $move san]} { return [dict get $move san] }
	if {[dict exists $move uci]} { return [UciToSan [dict get $move uci]] }
	return ""
}


# A UCI move ("e2e4", "e7e8q") as SAN in the current position, "" when it
# cannot be resolved.
proc ::endtrainer::UciToSan {uci} {
	if {![regexp {^([a-h][1-8])([a-h][1-8])([qrbnQRBN])?$} $uci -> from to promo]} { return "" }
	if {$promo eq ""} { return [::scidb::pos::san $from $to] }
	return [::scidb::pos::san $from $to [string tolower $promo]]
}


# Did the user's move, whose resulting position (the opponent to move) has
# verdict <after>, keep the goal?  "" is fine; otherwise the fault keyword,
# so the caller can offer Retry.
proc ::endtrainer::MoveFault {goal after} {
	if {$after eq ""} { return "" }
	if {$goal eq "win"} {
		switch -- $after {
			loss	{ return "" }
			draw	{ return letWinSlip }
			win		{ return nowLosing }
		}
		return ""
	}
	if {$after eq "win"} { return letDrawSlip }
	return ""
}


proc ::endtrainer::FaultText {fault} {
	variable mc
	switch -- $fault {
		letWinSlip	{ return $mc::LetWinSlip }
		letDrawSlip	{ return $mc::LetDrawSlip }
		nowLosing	{ return $mc::NowLosing }
	}
	return ""
}


# ----------------------------------------------------------------------
# The tablebase referee: local tables first, else the server (cached).
# ----------------------------------------------------------------------

proc ::endtrainer::Key {fen} {
	return [join [lrange $fen 0 3] " "]
}


# Asks the tablebase for <fen> and calls <done> with the answer dict ("" if
# there is none).  Local answers arrive synchronously; server answers are
# asynchronous through ::application::download::Get.
proc ::endtrainer::Probe {fen done} {
	variable Options
	variable Cache
	variable CacheSize

	set key [Key $fen]
	if {[dict exists $Cache $key]} {
		{*}$done [dict get $Cache $key]
		return
	}
	set local ""
	if {[llength [info commands ::tablebase::LocalAnswer]]} {
		catch { set local [::tablebase::LocalAnswer $fen] }
	}
	if {$local ne ""} {
		dict set Cache $key $local
		{*}$done $local
		return
	}
	if {!$Options(online)
	 || [llength [info commands ::application::download::Get]] == 0
	 || [llength [info commands ::tablebase::url]] == 0} {
		dict set Cache $key ""
		{*}$done ""
		return
	}
	::application::download::Get [::tablebase::url $fen] [list ::endtrainer::OnProbe $key $done]
}


proc ::endtrainer::OnProbe {key done result} {
	variable Cache
	variable CacheSize

	if {![dict get $result ok]} { {*}$done ""; return }
	set answer ""
	if {[catch { package require json; set answer [::json::json2dict [dict get $result data]] }]} {
		{*}$done ""
		return
	}
	if {[dict size $Cache] >= $CacheSize} { set Cache [dict create] }
	dict set Cache $key $answer
	{*}$done $answer
}


# ----------------------------------------------------------------------
# The session
# ----------------------------------------------------------------------

# Starts ending <id> at position <index> on the board in a new game.
# Returns 1 when the session is up.
proc ::endtrainer::Start {id {index 0}} {
	variable Priv
	variable Cache
	variable mc

	set ending [Ending $id]
	if {$ending eq ""} { return 0 }
	set positions [dict get $ending positions]
	if {![string is integer -strict $index] || $index < 0 || $index >= [llength $positions]} {
		set index 0
	}
	lassign [lindex $positions $index] fen verdict

	Finish
	set Cache [dict create]
	# a new game, so the position (and the moves played from it) is tracked
	# and can be taken back; a full house is reported, never clobbered
	if {[::game::new .application -variant Normal] < 0} {
		Status $mc::NoSlot
		return 0
	}
	set pos [::scidb::game::current]
	::scidb::game::clear $fen
	catch { ::application::switchTab board }

	array set Priv [list \
		pos			$pos \
		endingId	$id \
		goal		[dict get $ending goal] \
		index		$index \
		userSide	[lindex $fen 1] \
		engineSide	[expr {[lindex $fen 1] eq "w" ? "b" : "w"}] \
		phase		user \
		fault		{} \
		held		0 \
		verdict		$verdict \
		recorded	0 \
		active		1 \
		busy		0 \
	]
	::scidb::game::subscribe board $pos [namespace code Update]
	::scidb::db::subscribe gameClose [namespace code GameClosed]
	::scidb::db::subscribe gameSwitch [namespace code GameSwitched]

	ShowPanel
	Status [GoalText]
	BoardInput on
	if {[::scidb::pos::stm] ne $Priv(userSide)} {
		set Priv(phase) engine
		Status $mc::Thinking
		BoardInput off
		RequestEngineMove
	}
	return 1
}


# Ends the session (an unfinished one counts as an attempt).
proc ::endtrainer::Finish {} {
	variable Priv

	if {$Priv(active)} {
		if {!$Priv(recorded)} { RecordAttempt 0 }
		catch { ::scidb::game::unsubscribe board $Priv(pos) [namespace code Update] }
		catch { ::scidb::db::unsubscribe gameClose [namespace code GameClosed] }
		catch { ::scidb::db::unsubscribe gameSwitch [namespace code GameSwitched] }
	}
	set Priv(active) 0
	set Priv(phase) idle
	BoardInput on
}


proc ::endtrainer::GameClosed {position} {
	variable Priv
	if {$Priv(active) && $position == $Priv(pos)} { Finish }
}


proc ::endtrainer::GameSwitched {oldPos newPos} {
	variable Priv
	if {$Priv(active) && $newPos != $Priv(pos)} { Finish }
}


# The board subscription of the session's game.
proc ::endtrainer::Update {position cmd data promoted} {
	variable Priv
	variable mc

	if {!$Priv(active) || $Priv(busy) || $position != $Priv(pos)} { return }
	if {$cmd ne "move"} { return }
	if {[llength $data] && ![lindex $data end]} { return } ;# backward navigation

	if {$Priv(phase) eq "user"} {
		if {![::scidb::game::position atEnd?] || ![::scidb::game::position isMainline?]} {
			RejectMove $mc::NotAtEnd
			return
		}
		AfterUserMove
	} else {
		RejectMove $mc::NotYourTurn
	}
}


# A move via the keyboard or a test instead of the board; like a drag it
# answers whether it went in.
proc ::endtrainer::UserMove {san} {
	variable Priv
	variable mc

	if {!$Priv(active) || $Priv(phase) ne "user"} { return 0 }
	if {![::scidb::game::position atEnd?] || ![::scidb::game::position isMainline?]} {
		Status $mc::NotAtEnd
		return 0
	}
	set plies [::scidb::game::query length]
	::move::addMove menu $san
	return [expr {[::scidb::game::query length] > $plies}]
}


# A move out of turn (or off the mainline): put the position back.
proc ::endtrainer::RejectMove {why} {
	variable Priv

	set Priv(busy) 1
	catch { ::scidb::game::go -1 }
	catch { ::scidb::game::strip truncate }
	set Priv(busy) 0
	Status $why
}


# The user has moved: the game end first, then the tablebase verdict.
proc ::endtrainer::AfterUserMove {} {
	variable Priv

	if {[CheckGoal]} { return }
	set fen [::scidb::pos::fen]
	Probe $fen [list ::endtrainer::JudgeMove $fen]
}


# The verdict of the position the user moved into (the engine to move).
proc ::endtrainer::JudgeMove {fen answer} {
	variable Priv
	variable HoldMoves
	variable mc

	if {!$Priv(active) || $Priv(phase) ne "user"} { return }
	if {[::scidb::pos::fen] ne $fen} { return }

	set after [VerdictOf $answer]
	set fault [MoveFault $Priv(goal) $after]
	if {$fault ne ""} {
		set Priv(fault) $fault
		set Priv(phase) fault
		BoardInput off
		Status [FaultText $fault]
		RefreshButtons
		return
	}
	if {$after eq ""} {
		Status $mc::NoTables
	} elseif {$Priv(goal) eq "draw"} {
		incr Priv(held)
		if {$Priv(held) >= $HoldMoves} {
			FinishSession 1 $mc::SolvedDraw
			return
		}
		Status [format $mc::HoldMoves $Priv(held) $HoldMoves]
	} else {
		Status $mc::YourMove
	}
	set Priv(phase) engine
	BoardInput off
	EngineReply $answer
}


# The engine's turn.  A tablebase answer for its position is preferred (a
# tablebase-best defence); without one the configured engine searches.
proc ::endtrainer::EngineReply {answer} {
	if {[llength $answer]} {
		set san [BestMoveSan $answer]
		if {$san ne ""} {
			after 0 [namespace code [list PlayEngineMove $san]]
			return
		}
	}
	EngineMove
}


# The seam the tests replace: the move the configured engine plays, as SAN.
# Single evaluation through ::ai::engine (the bundled Stockfish by default,
# the user's choice otherwise).
proc ::endtrainer::EngineMove {} {
	variable Priv
	variable Options
	variable mc

	set fen [::scidb::pos::fen]
	set san ""
	if {![catch { ::ai::engine::evaluate $fen -movetime $Options(movetime) } facts]} {
		if {[dict exists $facts bestMove]} { set san [UciToSan [dict get $facts bestMove]] }
	}
	if {$san eq ""} {
		set Priv(phase) over
		RecordAttempt 0
		Status $mc::EngineGone
		return
	}
	PlayEngineMove $san
}


proc ::endtrainer::RequestEngineMove {} {
	Probe [::scidb::pos::fen] [list ::endtrainer::EngineReply]
}


# Plays the engine's SAN, then is the user's turn (or the goal is decided).
proc ::endtrainer::PlayEngineMove {san} {
	variable Priv
	variable mc

	if {!$Priv(active) || $Priv(phase) ne "engine"} { return }
	set plies [::scidb::game::query length]
	set Priv(busy) 1
	catch { ::scidb::game::move $san; ::scidb::game::go 1 }
	set Priv(busy) 0
	if {[::scidb::game::query length] <= $plies} {
		set Priv(phase) over
		RecordAttempt 0
		Status $mc::EngineGone
		return
	}
	if {[CheckGoal]} { return }
	set Priv(phase) user
	BoardInput on
	Status $mc::YourMove
	RefreshButtons
}


# Retry Move: takes the user's last move back, back to the user's turn.
proc ::endtrainer::Retry {} {
	variable Priv

	if {!$Priv(active) || $Priv(phase) ne "fault"} { return }
	set Priv(busy) 1
	while {[::scidb::game::query length] > 0 && [::scidb::pos::stm] ne $Priv(userSide)} {
		catch { ::scidb::game::go -1 }
		catch { ::scidb::game::strip truncate }
	}
	set Priv(busy) 0
	set Priv(fault) {}
	set Priv(phase) user
	BoardInput on
	Status [GoalText]
	RefreshButtons
}


# Continue after a fault: the engine now answers the faulty move.
proc ::endtrainer::Continue {} {
	variable Priv
	variable mc

	if {!$Priv(active) || $Priv(phase) ne "fault"} { return }
	set Priv(fault) {}
	set Priv(phase) engine
	BoardInput off
	Status $mc::Thinking
	RefreshButtons
	RequestEngineMove
}


proc ::endtrainer::Next {} {
	variable Priv

	if {$Priv(endingId) eq ""} { return }
	set positions [PositionsOf $Priv(endingId)]
	set index [expr {$Priv(index) + 1}]
	if {$index >= [llength $positions]} { set index 0 }
	Start $Priv(endingId) $index
}


# ----------------------------------------------------------------------
# End of an attempt
# ----------------------------------------------------------------------

# {result reason} when the game is over, {} otherwise; result is the user's
# view: win, loss or draw.
proc ::endtrainer::GameOver {} {
	variable Priv

	set over 0
	catch { set over [::scidb::game::query over?] }
	if {$over} {
		if {[InCheck [::scidb::pos::fen]]} {
			set result [expr {[::scidb::pos::stm] eq $Priv(userSide) ? "loss" : "win"}]
			return [list $result mate]
		}
		return [list draw stalemate]
	}
	set fen [::scidb::pos::fen]
	if {$fen eq ""} { return {} }
	if {[FiftyMoves $fen]} { return [list draw fifty] }
	if {[Repetition]} { return [list draw repetition] }
	if {[InsufficientMaterial $fen]} { return [list draw material] }
	return {}
}


# Decides the attempt when the game is over; 1 when it is.
proc ::endtrainer::CheckGoal {} {
	variable Priv
	variable mc

	set over [GameOver]
	if {![llength $over]} { return 0 }
	lassign $over result reason
	if {$Priv(goal) eq "win" && $result eq "win"} {
		FinishSession 1 $mc::SolvedMate
		return 1
	}
	if {$Priv(goal) eq "draw" && $result eq "draw"} {
		FinishSession 1 $mc::SolvedDraw
		return 1
	}
	FinishSession 0 [format $mc::Failed [ReasonText $reason]]
	return 1
}


proc ::endtrainer::ReasonText {reason} {
	variable mc
	switch -- $reason {
		mate		{ return $mc::Mated }
		stalemate	{ return $mc::Stalemate }
		fifty		{ return $mc::FiftyMoves }
		repetition	{ return $mc::Repetition }
		material	{ return $mc::Material }
	}
	return $mc::NoGoalReached
}


# Ends the attempt: the progress is recorded and the panel reports it.
proc ::endtrainer::FinishSession {success reason} {
	variable Priv

	if {$Priv(phase) eq "idle"} { return }
	set Priv(phase) over
	set Priv(fault) {}
	BoardInput off
	RecordAttempt $success
	Status $reason
	RefreshButtons
}


proc ::endtrainer::GoalText {} {
	variable Priv
	variable HoldMoves
	variable mc

	if {$Priv(goal) eq "draw"} { return [format $mc::DrawGoal $HoldMoves] }
	return $mc::WinGoal
}


proc ::endtrainer::BoardInput {on} {
	if {$on} {
		catch { ::move::enable }
	} else {
		catch { ::move::disable }
	}
}


# ----------------------------------------------------------------------
# End-of-game helpers (pure; a board is not needed)
# ----------------------------------------------------------------------

# Half-move clock >= 100: the automatic end of the fifty-move rule.
proc ::endtrainer::FiftyMoves {fen} {
	set clock [lindex $fen 4]
	return [expr {[string is integer -strict $clock] && $clock >= 100}]
}


# Occurrence count of the current position (placement, side, castling and
# ep squares all match) across the game; the third is the repetition.
proc ::endtrainer::Repetition {} {
	if {[catch { ::scidb::game::query mainline } plies]} { return 0 }
	set key [Key [::scidb::pos::fen]]
	set count 1
	foreach ply $plies {
		if {[Key [lindex $ply 2]] eq $key} { incr count }
	}
	return [expr {$count >= 3}]
}


# No side can mate: no queens, rooks or pawns, and at most one minor piece
# per side (the two bishops share a colour only when they are the same).
proc ::endtrainer::InsufficientMaterial {fen} {
	set board [lindex $fen 0]
	if {[regexp {[qQrRpP]} $board]} { return 0 }
	set bishops {}
	set minors 0
	set y 7
	set n 0
	foreach ch [split $board {}] {
		if {[string is digit -strict $ch]} {
			incr n $ch
			continue
		}
		if {$ch eq "/"} { incr y -1; set n 0; continue }
		set x $n
		incr n
		if {$ch in {B b N n}} {
			incr minors
			if {$ch in {B b}} { lappend bishops [expr {($x + $y) % 2}] }
		}
	}
	if {$minors <= 1} { return 1 }
	return [expr {[llength $bishops] == 2 && [lindex $bishops 0] == [lindex $bishops 1]}]
}


# Is the side to move of <fen> in check?
proc ::endtrainer::InCheck {fen} {
	lassign $fen board stm
	set squares {}
	set y 7
	set n 0
	foreach ch [split $board {}] {
		if {[string is digit -strict $ch]} {
			incr n $ch
			continue
		}
		if {$ch eq "/"} { incr y -1; set n 0; continue }
		lappend squares $ch $n $y
		incr n
	}
	set own [expr {$stm eq "b" ? "k" : "K"}]
	array set grid {}
	set kx -1
	set ky -1
	foreach {piece x y} $squares {
		set grid($x,$y) $piece
		if {$piece eq $own} { set kx $x; set ky $y }
	}
	if {$kx < 0} { return 0 }
	set opp [expr {$stm eq "b" ? 1 : 0}]

	foreach {piece x y} $squares {
		set white [string is upper -strict $piece]
		if {$white != $opp} { continue }
		set dx [expr {$kx - $x}]
		set dy [expr {$ky - $y}]
		switch -- [string toupper $piece] {
			P {
				set fwd [expr {$white ? 1 : -1}]
				if {abs($dx) == 1 && $dy == $fwd} { return 1 }
			}
			N {
				if {(abs($dx) == 1 && abs($dy) == 2) || (abs($dx) == 2 && abs($dy) == 1)} { return 1 }
			}
			K {
				if {max(abs($dx), abs($dy)) == 1} { return 1 }
			}
			B - R - Q {
				if {[Step grid $piece $x $y $dx $dy]} { return 1 }
			}
		}
	}
	return 0
}


# Sliders only: does <piece> at x,y run along the clear line to dx,dy?
proc ::endtrainer::Step {gridArr piece x y dx dy} {
	upvar $gridArr grid

	switch -- [string toupper $piece] {
		B { if {abs($dx) != abs($dy) || $dx == 0} { return 0 } }
		R { if {$dx != 0 && $dy != 0} { return 0 } }
		Q { if {abs($dx) != abs($dy) && $dx != 0 && $dy != 0} { return 0 } }
		default { return 0 }
	}
	if {$dx == 0 && $dy == 0} { return 0 }
	set stepx [expr {$dx == 0 ? 0 : $dx / abs($dx)}]
	set stepy [expr {$dy == 0 ? 0 : $dy / abs($dy)}]
	set nx [expr {$x + $stepx}]
	set ny [expr {$y + $stepy}]
	while {$nx != $x + $dx || $ny != $y + $dy} {
		if {[info exists grid($nx,$ny)]} { return 0 }
		incr nx $stepx
		incr ny $stepy
	}
	return 1
}


# ----------------------------------------------------------------------
# The window
# ----------------------------------------------------------------------

proc ::endtrainer::open {parent} {
	variable Priv
	variable mc

	set dlg $parent.__endtrainer__
	if {[winfo exists $dlg]} {
		raise $dlg
		return $dlg
	}
	set Priv(dialog) $dlg

	toplevel $dlg -class Scidb
	wm title $dlg $mc::Title
	wm transient $dlg [winfo toplevel $parent]
	wm withdraw $dlg
	wm protocol $dlg WM_DELETE_WINDOW [namespace code Close]
	bind $dlg <Escape> [namespace code Close]

	set top [ttk::frame $dlg.top]
	pack $top -fill both -expand yes -padx $::theme::padx -pady $::theme::pady

	### the ending list ####################################################
	set setup [ttk::frame $top.setup]
	set tree [ttk::treeview $setup.tree -columns {solved} -show {tree headings} \
		-selectmode browse -height 14]
	$tree heading #0 -text $mc::Ending
	$tree heading solved -text $mc::Solved
	$tree column #0 -width 260
	$tree column solved -width 70 -anchor e
	ttk::scrollbar $setup.vs -orient vertical -command [list $tree yview]
	$tree configure -yscrollcommand [list $setup.vs set]
	pack $tree -side left -fill both -expand yes
	pack $setup.vs -side right -fill y
	bind $tree <Double-1> [namespace code StartSelected]
	pack $setup -fill both -expand yes

	### the session panel ##################################################
	set panel [ttk::frame $top.panel]
	ttk::label $panel.goal -wraplength 320 -justify left
	ttk::label $panel.status -wraplength 320 -justify left
	set buttons [ttk::frame $panel.buttons]
	ttk::button $buttons.retry -text $mc::Retry -command [namespace code Retry]
	ttk::button $buttons.continue -text $mc::Continue -command [namespace code Continue]
	ttk::button $buttons.giveup -text $mc::GiveUp -command [namespace code GiveUp]
	pack $buttons.retry $buttons.continue $buttons.giveup -side left -padx [list 0 $::theme::padx]
	pack $panel.goal -anchor w
	pack $panel.status -anchor w -pady [list $::theme::pady 0]
	pack $buttons -anchor w -pady [list 0 $::theme::pady]

	::widget::dialogButtons $dlg {ok cancel}
	$dlg.ok configure -text $mc::Start -command [namespace code StartSelected]
	$dlg.cancel configure -text $mc::Close -command [namespace code Close]

	set Priv(widget:setup) $setup
	set Priv(widget:panel) $panel
	set Priv(widget:tree) $tree
	set Priv(widget:goal) $panel.goal
	set Priv(widget:status) $panel.status
	set Priv(widget:buttons) $buttons
	set Priv(widget:ok) $dlg.ok
	set Priv(widget:cancel) $dlg.cancel
	set Priv(treeIds) [dict create]

	RefreshTree
	Status ""
	::util::place::besideBoard $dlg $parent
	wm deiconify $dlg
	return $dlg
}


proc ::endtrainer::Close {} {
	variable Priv

	Finish
	if {[winfo exists $Priv(dialog)]} { destroy $Priv(dialog) }
	set Priv(dialog) {}
}


proc ::endtrainer::GiveUp {} {
	Finish
	Status ""
	ShowSetup
}


# Populates the ending list: a node per theme, the endings under it with
# their done/attempts.
proc ::endtrainer::RefreshTree {} {
	variable Priv
	variable mc

	set dlg $Priv(dialog)
	if {$dlg eq "" || ![winfo exists $dlg]} { return }
	set tree $Priv(widget:tree)
	$tree delete [$tree children {}]
	set progress [LoadProgress]
	set Priv(treeIds) [dict create]
	foreach theme [Themes] {
		lassign $theme tid ttitle
		set node [$tree insert {} end -text $ttitle -open 1]
		foreach ending [Endings $tid] {
			set id [dict get $ending id]
			set e [list attempts 0 done 0]
			if {[dict exists $progress $id]} { set e [dict get $progress $id] }
			set item [$tree insert $node end \
				-text [dict get $ending title] \
				-values [list [format $mc::Progress [dict get $e done] [dict get $e attempts]]]]
			dict set Priv(treeIds) $item $id
		}
	}
}


proc ::endtrainer::StartSelected {} {
	variable Priv

	set dlg $Priv(dialog)
	if {$dlg eq "" || ![winfo exists $dlg]} { return }
	set sel [$Priv(widget:tree) selection]
	if {![llength $sel]} { return }
	set item [lindex $sel 0]
	if {![dict exists $Priv(treeIds) $item]} { return }
	Start [dict get $Priv(treeIds) $item] 0
}


# The list gives way to the session panel while an attempt runs.
proc ::endtrainer::ShowPanel {} {
	variable Priv
	variable mc

	set dlg $Priv(dialog)
	if {$dlg eq "" || ![winfo exists $dlg]} { return }
	pack forget $Priv(widget:setup)
	pack $Priv(widget:panel) -fill both -expand yes
	if {[winfo exists $Priv(widget:ok)]} {
		$Priv(widget:ok) configure -text $mc::Next -command [namespace code Next]
	}
	$Priv(widget:goal) configure -text [GoalText]
	RefreshButtons
}


proc ::endtrainer::ShowSetup {} {
	variable Priv
	variable mc

	set dlg $Priv(dialog)
	if {$dlg eq "" || ![winfo exists $dlg]} { return }
	pack forget $Priv(widget:panel)
	pack $Priv(widget:setup) -fill both -expand yes
	if {[winfo exists $Priv(widget:ok)]} {
		$Priv(widget:ok) configure -text $mc::Start -command [namespace code StartSelected]
	}
	RefreshTree
}


proc ::endtrainer::RefreshButtons {} {
	variable Priv

	if {$Priv(dialog) eq "" || ![winfo exists $Priv(dialog)]} { return }
	set buttons $Priv(widget:buttons)
	set fault [expr {$Priv(phase) eq "fault"}]
	foreach {name state} [list retry [expr {$fault ? "normal" : "disabled"}] \
		continue [expr {$fault ? "normal" : "disabled"}] \
		giveup [expr {$Priv(phase) in {over fault} ? "normal" : "disabled"}]] {
		if {[winfo exists $buttons.$name]} { $buttons.$name configure -state $state }
	}
}


proc ::endtrainer::Status {text} {
	variable Priv
	if {$Priv(dialog) ne "" && [winfo exists $Priv(widget:status)]} {
		$Priv(widget:status) configure -text $text
	}
	set Priv(status) $text
}


proc ::endtrainer::WriteOptions {chan} {
	::options::writeItem $chan [namespace current]::Options
}

::options::hookWriter ::endtrainer::WriteOptions

# vi:set ts=3 sw=3:
