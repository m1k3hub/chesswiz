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
#   ::gamereview::cancel
#   ::gamereview::running?
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

} ;# namespace mc

array set Options {
	depth	12
}

variable MaxPlies 200

variable Priv
array set Priv {
	running	0
	cancel	0
	plies		{}
	index		0
	total		0
	results	{}
	done		{}
	parent	{}
	rows		{}
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
	::util::place $dlg -parent $parent -position center
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

	if {[llength $errors]} {
		ttk::label $top.err -text [join $errors "\n"] -anchor w -wraplength 420
		pack $top.err -fill x -pady [list $::theme::pady 0]
	}

	ttk::label $top.head -text $mc::KeyMoves -anchor w
	pack $top.head -fill x -pady [list $::theme::pady 0]

	set frame [ttk::frame $top.list]
	set lb [listbox $frame.list -height 10 -width 60 -exportselection false]
	set vs [ttk::scrollbar $frame.vs -orient vertical -command [list $lb yview]]
	$lb configure -yscrollcommand [list $vs set]
	pack $lb -side left -fill both -expand yes
	pack $vs -side right -fill y
	pack $frame -fill both -expand yes

	set rows {}
	foreach m [dict get $review moves] {
		set cls [dict get $m class]
		if {$cls ni {Inaccuracy Mistake Blunder}} { continue }
		set text "[moveLabel $m] [dict get $m san] \u2014 $cls"
		if {[dict exists $m bestSan] && [dict get $m bestSan] ne ""} {
			append text " ($mc::BetterMove [dict get $m bestSan])"
		}
		$lb insert end $text
		lappend rows [list [dict get $m key] $text]
	}
	if {![llength $rows]} {
		$lb insert end $mc::NoKeyMoves
	}
	set Priv(rows) $rows
	bind $lb <<ListboxSelect>> [namespace code [list GoTo $lb]]

	set buttons [ttk::frame $top.buttons]
	ttk::button $buttons.add -text $mc::AddSymbols \
		-command [namespace code [list AddSymbols [dict get $review moves] $dlg]]
	ttk::button $buttons.close -text $mc::Close -command [list destroy $dlg]
	pack $buttons.add -side left
	pack $buttons.close -side left -padx [list $::theme::padx 0]
	pack $buttons -fill x -pady [list $::theme::pady 0]

	::util::place $dlg -parent $parent -position center
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
proc ::gamereview::AddSymbols {moves {dlg {}}} {
	variable mc

	set added 0
	foreach m $moves {
		set nag [nagFor [dict get $m class]]
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
