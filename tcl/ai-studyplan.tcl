# ======================================================================
# ::ai::studyplan -- audit your games and turn the mistakes into a plan.
#
# Walk a sample of the games in the active database (the player's, if a
# player is given), let Stockfish classify every move of the side being
# studied, and collect the mistakes.  Each mistake carries the engine's
# verdict (class, centipawn loss, best move) plus the position facts the
# C++ layer already computes (phase, material, pawn structure, king
# safety, mobility, and the tactical motifs: undefended pieces, pins,
# forks, en prise).  Those features decide a *pattern*:
#
#   tactical   material was hanging or a motif was on the board
#   opening    the mistake happened while developing
#   endgame    low material
#   kingsafety an attack was forming
#   positional anything else: slow losses of a healthy position
#
# The System One classifier may pick the pattern instead, with the same
# features as its state and a confidence gate; below the threshold, or
# with no classifier at all, the deterministic rules above decide.  Either
# way the classifier only *labels*: the engine owns what happened, and the
# examples in the plan are the engine's own verdicts.
#
#   ::ai::studyplan::run $parent ?-player NAME? ?-games 10? ?-colour both?
#       ?-depth 10? ?-minCpLoss 50? ?-prose 1? ?-done CMD?
#   ::ai::studyplan::cancel
#   ::ai::studyplan::running?
#
# Cost: one engine search per studied move (blocking, a fraction of a
# second each at depth 10).  The run walks the game list, so the board
# follows the audit; the game the user was on is reloaded at the end.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-studyplan
}

package require Tcl 8.5
package require Tk 8.5

namespace eval ai {
namespace eval studyplan {
namespace eval mc {

set Title			"Study plan"
set NoGames		"No games to study."
set NoEngine		"No chess engine is available for the audit."
set Progress		"Studying game %d of %d (#%s)..."
set Done			"Studied %d move(s) in %d game(s): %d mistake(s)."
set Cancelled		"Cancelled after %d game(s) and %d mistake(s)."
set Patterns		{tactical opening endgame kingsafety positional}
set Advice(tactical) \
	"Tactics: before every move, look for undefended pieces and one-move captures. Puzzles in short bursts, then the same checks at the board."
set Advice(opening) \
	"Opening: the errors come while the pieces are still being placed. Review the first moves of these games, and decide the plan before move ten."
set Advice(endgame) \
	"Endgames: the losses are technical, not tactical. King activity, pawn races and the basic theoretical endings."
set Advice(kingsafety) \
	"King safety: the errors come when the king is under pressure. Watch castling, the pawn shield, and how many attackers reach the king."
set Advice(positional) \
	"Position: the moves are not blunders but they slowly give the position away. Compare each move with the engine's choice and name the change it prevents."

} ;# namespace mc

variable Settings
array set Settings {
	depth			10
	games			10
	colour		both
	prose			1
	minCpLoss	50
	maxPlies		60
}

# the game slot the audited games are read into (the merge dialog uses 20
# and 21, the training set 31), so the user's board is untouched
variable Slot 30

variable Priv
array set Priv {
	running	0
	cancel	0
	done		{}
	parent	{}
	mistakes	{}
	gameIndex	0
	gameTotal	0
	moveIndex	0
	moveTotal	0
	saved		{}
	prose	1
	player	""
	colour	both
}

} ;# namespace studyplan
} ;# namespace ai


proc ::ai::studyplan::configure {args} {
	variable Settings

	foreach {key value} $args {
		set key [string trimleft $key -]
		if {![info exists Settings($key)]} { error "unknown study-plan setting '$key'" }
		set Settings($key) $value
	}
	return
}


proc ::ai::studyplan::running? {} {
	variable Priv
	return $Priv(running)
}


# ======================================================================
# The pattern of a mistake: deterministic first, the classifier as a
# second opinion.
# ======================================================================

# <facts> is the parsed ::scidb::ai::facts dict for the position the move
# was played from; <side> is the side that moved.
proc ::ai::studyplan::Fact {facts args} {
	# walks a path through the fact JSON, returning {} when it is absent
	set node $facts
	foreach key $args {
		if {![catch { dict get $node $key } node]} { continue }
		return {}
	}
	return $node
}


proc ::ai::studyplan::pattern {facts side classification cpLoss} {
	# material already hanging, or a motif on the board
	foreach path [list [list motifs enPrise $side] [list motifs forks $side] \
	              [list tactics ${side}Undefended] [list tactics ${side}Pinned]] {
		if {[llength [Fact $facts {*}$path]]} { return tactical }
	}

	set phase [expr {[Fact $facts phase] ne "" ? [Fact $facts phase] : "middlegame"}]
	if {$phase eq "endgame"} { return endgame }

	if {[Fact $facts kingSafety $side attackers] >= 2} { return kingsafety }

	if {$phase eq "opening"} { return opening }
	return positional
}


# The classifier's opinion on the same features, gated, with the rules as
# the fallback.  <script> gets {ok 1 pattern P source classifier|rules}.
proc ::ai::studyplan::classifyPattern {facts side classification cpLoss script} {
	set state "ENGINE VERDICT: $classification, losing $cpLoss centipawns.\n\
		POSITION FACTS (JSON):\n$facts"
	set question [dict create type choice \
		instructions "Why did the side that moved most likely lose material or the advantage here?" \
		criteria [dict create \
			tactical   "a piece or pawn was hanging, or a fork, pin or skewer was available" \
			opening    "the position is still in the opening; development is unfinished" \
			endgame    "little material is left; this is technique, not tactics" \
			kingsafety "the king is exposed or under attack" \
			positional "no tactic was missed; the move slowly gives the position away"]]

	::ai::decide pattern $state $question [namespace code [list OnClassified $script]] \
		-fallback [namespace code [list pattern $facts $side $classification $cpLoss]]
	return
}


proc ::ai::studyplan::OnClassified {script decision} {
	uplevel #0 [list {*}$script [list ok 1 pattern [dict get $decision label] \
		source [dict get $decision source]]]
}


# ======================================================================
# The audit
# ======================================================================
proc ::ai::studyplan::run {parent args} {
	variable Priv
	variable Settings
	variable mc

	array set opts [list -player "" -games $Settings(games) -colour $Settings(colour) \
		-depth $Settings(depth) -minCpLoss $Settings(minCpLoss) -prose $Settings(prose) -done {}]
	array set opts $args

	if {$Priv(running)} { return 0 }
	if {[llength [info commands ::ai::engine::available]] == 0 || ![::ai::engine::available]} {
		::dialog::info -parent $parent -message $mc::NoEngine
		return 0
	}

	lassign [GamesToStudy $opts(-player) $opts(-games)] base variant numbers
	if {![llength $numbers]} {
		::dialog::info -parent $parent -message $mc::NoGames
		return 0
	}

	set Priv(running) 1
	set Priv(cancel) 0
	set Priv(done) $opts(-done)
	set Priv(parent) $parent
	set Priv(prose) $opts(-prose)
	set Priv(player) $opts(-player)
	set Priv(colour) $opts(-colour)
	set Priv(depth) $opts(-depth)
	set Priv(minCpLoss) $opts(-minCpLoss)
	set Priv(mistakes) {}
	set Priv(gameTotal) [llength $numbers]
	set Priv(gameIndex) 0
	set Priv(moveIndex) 0
	set Priv(moveTotal) 0
	set Priv(base) $base
	set Priv(variant) $variant
	set Priv(games) $numbers

	Report [Progress [dict create]]
	after 50 [namespace code NextGame]
	return 1
}


proc ::ai::studyplan::cancel {} {
	variable Priv

	if {!$Priv(running)} { return 0 }
	set Priv(cancel) 1
	return 1
}


# The game numbers to study: the player's games when a player is given,
# the most recent games otherwise.  Uses the app's own search machinery.
proc ::ai::studyplan::GamesToStudy {player games} {
	set criteria {}
	if {[string length $player]} { dict set criteria player $player }

	set query {}
	if {[catch {
		lassign [::application::assistant::ActiveBase] base variant
		if {[dict size $criteria]} {
			# BuildQuery wants every search_games field; CheckArgs fills them in
			set criteria [dict get [::application::assistant::CheckArgs search_games $criteria] criteria]
			lassign [::application::assistant::BuildQuery $base $variant $criteria] query summary
		}
	}]} {
		# an unknown player: nothing to study.  With no player asked for, fall
		# back to the whole database (an empty query restricts nothing).
		if {[string length $player]} { return [list {} Normal {}] }
		catch { lassign [::application::assistant::ActiveBase] base variant }
		set base [expr {[info exists base] ? $base : ""}]
		set variant [expr {[info exists variant] ? $variant : ""}]
		if {$base eq ""} { return [list {} Normal {}] }
		set query {}
	}

	set view [::scidb::view::new $base $variant unused unused unused unused master slave]
	set numbers {}
	set rc [catch {
		::scidb::view::search $base $variant $view null none $query
		set count [::scidb::view::count games $base $variant $view]
		set from [expr {$count > $games ? $count - $games : 0}]
		for {set row $from} {$row < $count} {incr row} {
			lappend numbers [::scidb::db::get gameNumber $base $variant $row $view]
		}
	} err]
	catch { ::scidb::view::close $base $variant $view }
	if {$rc} { return [list $base $variant {}] }
	return [list $base $variant $numbers]
}


# ----------------------------------------------------------------------
# One game at a time; one move at a time inside a game.
# ----------------------------------------------------------------------
proc ::ai::studyplan::NextGame {} {
	variable Priv
	variable Slot
	variable mc

	if {!$Priv(running)} { return }
	if {$Priv(cancel) || $Priv(gameIndex) >= [llength $Priv(games)]} {
		Finish
		return
	}

	set number [lindex $Priv(games) $Priv(gameIndex)]
	incr Priv(gameIndex)
	Report [Progress [dict create text [format $mc::Progress $Priv(gameIndex) $Priv(gameTotal) $number]]]
	update idletasks

	if {[catch {
		# a slot of its own: the user's board is untouched
		if {![::scidb::game::query $Slot open?]} { ::scidb::game::new $Slot }
		::scidb::game::load $Slot $Priv(base) $Priv(variant) $number
		set Priv(plies) [::scidb::game::query $Slot mainline]
	}]} {
		after 1 [namespace code NextGame]
		return
	}
	set Priv(plyIndex) 0
	set Priv(moveIndex) 0
	set Priv(moveTotal) [llength $Priv(plies)]
	NextPly
	return
}


proc ::ai::studyplan::NextPly {} {
	variable Priv
	variable Settings

	if {!$Priv(running)} { return }
	if {$Priv(cancel) || $Priv(plyIndex) >= [llength $Priv(plies)]} {
		after 1 [namespace code NextGame]
		return
	}

	lassign [lindex $Priv(plies) $Priv(plyIndex)] key san fen
	incr Priv(plyIndex)
	incr Priv(moveIndex)
	if {$Priv(plyIndex) > $Settings(maxPlies)} {
		after 1 [namespace code NextGame]
		return
	}
	update idletasks

	# whose move is it?  the FEN's side to move is the mover
	set side [expr {[lindex [split $fen] 1] eq "b" ? "black" : "white"}]
	if {$Priv(colour) ne "both" && $side ne $Priv(colour)} {
		after 1 [namespace code NextPly]
		return
	}

	if {[catch { ::ai::engine::classify $fen $san -depth $Priv(depth) } verdict]} {
		after 1 [namespace code NextPly]
		return
	}
	set class [dict get $verdict classification]
	set cpLoss [expr {[dict exists $verdict cpLoss] ? [dict get $verdict cpLoss] : 0}]
	if {$class ni {Blunder Mistake Inaccuracy} || $cpLoss < $Priv(minCpLoss)} {
		after 1 [namespace code NextPly]
		return
	}

	set facts {}
	catch { set facts [::json::json2dict [::scidb::ai::facts $fen]] }
	if {![llength $facts]} {
		after 1 [namespace code NextPly]
		return
	}

	classifyPattern $facts $side $class $cpLoss [namespace code [list OnPattern $key $san $fen $side $class $cpLoss $verdict]]
	return
}


proc ::ai::studyplan::OnPattern {key san fen side class cpLoss verdict result} {
	variable Priv

	if {[dict get $result ok]} {
		lappend Priv(mistakes) [dict create \
			game [lindex $Priv(games) [expr {$Priv(gameIndex) - 1}]] \
			ply $Priv(plyIndex) key $key san $san fen $fen side $side \
			class $class cpLoss $cpLoss \
			best [expr {[dict exists $verdict bestMove] ? [dict get $verdict bestMove] : ""}] \
			pattern [dict get $result pattern] source [dict get $result source] \
			structures [Structures $fen]]
	}
	after 1 [namespace code NextPly]
	return
}


# The structure patterns of the position the mistake was played from
# (CQL, exact): a second dimension next to the pattern label.
proc ::ai::studyplan::Structures {fen} {
	if {[llength [info commands ::ai::search::structures]] == 0} { return {} }
	if {[catch { ::ai::search::structures $fen } found]} { return {} }
	return $found
}


proc ::ai::studyplan::StructureLabel {id} {
	return [dict get [::ai::search::pattern $id] label]
}


# ----------------------------------------------------------------------
# The plan
# ----------------------------------------------------------------------
proc ::ai::studyplan::Clusters {} {
	variable Priv

	set out {}
	foreach m $Priv(mistakes) {
		set p [dict get $m pattern]
		if {![dict exists $out $p]} { dict set out $p [list] }
		dict lappend out $p $m
	}
	# biggest cluster first, then by the damage done
	set ranked {}
	foreach {pattern rows} $out {
		set loss 0
		foreach m $rows { incr loss [dict get $m cpLoss] }
		lappend ranked [list $pattern [llength $rows] $loss $rows]
	}
	return [lsort -decreasing -command [namespace code [list CompareCluster]] $ranked]
}


proc ::ai::studyplan::CompareCluster {a b} {
	if {[lindex $a 1] != [lindex $b 1]} { return [expr {[lindex $a 1] - [lindex $b 1]}] }
	return [expr {[lindex $a 2] - [lindex $b 2]}]
}


proc ::ai::studyplan::PlanText {} {
	variable Priv
	variable mc

	set lines {}
	foreach cluster [Clusters] {
		lassign $cluster pattern count loss rows
		lappend lines [format "%s: %d mistake(s), about %.1f pawns in total -- %s" \
			$pattern $count [expr {$loss / 100.0}] $mc::Advice($pattern)]
		set where [StructureCounts $rows]
		if {[dict size $where]} {
			lappend lines "   positions: [join [lmap {id c} $where { format "%d in %s" $c [StructureLabel $id] }] {, }]"
		}
		foreach m [lrange $rows 0 2] {
			lappend lines [format "   game #%s move %d %s %s: %s (best %s)" \
				[dict get $m game] [dict get $m ply] [dict get $m side] [dict get $m san] \
				[dict get $m class] [dict get $m best]]
		}
	}

	# the same mistakes by the kind of position they were played in
	set total [llength $Priv(mistakes)]
	set by {}
	foreach m $Priv(mistakes) {
		if {![dict exists $m structures]} { continue }
		foreach id [dict get $m structures] {
			if {![dict exists $by $id]} { dict set by $id {0 0} }
			lassign [dict get $by $id] c loss
			dict set by $id [list [incr c] [expr {$loss + [dict get $m cpLoss]}]]
		}
	}
	if {[dict size $by]} {
		lappend lines "By structure (found by CQL in the position before the move):"
		foreach id [lsort -command [list apply {{by a b} {
				expr {[lindex [dict get $by $b] 0] - [lindex [dict get $by $a] 0]}
			}} $by] [dict keys $by]] {
			lassign [dict get $by $id] c loss
			lappend lines [format "   %s: %d of %d mistake(s), about %.1f pawns" \
				[StructureLabel $id] $c $total [expr {$loss / 100.0}]]
		}
	}
	return [join $lines \n]
}


# {id count ...} of the structures among <rows>, the most frequent first.
proc ::ai::studyplan::StructureCounts {rows} {
	set counts {}
	foreach m $rows {
		if {![dict exists $m structures]} { continue }
		foreach id [dict get $m structures] { dict incr counts $id }
	}
	set out {}
	foreach pair [lsort -integer -decreasing -index 1 [lmap {k v} $counts { list $k $v }]] {
		lappend out {*}$pair
	}
	return $out
}


proc ::ai::studyplan::Report {html} {
	variable Priv

	if {[llength [info commands ::application::ai::showReport]] == 0} { return }
	catch { ::application::ai::showReport $Priv(parent) "AI: study plan" \
		[::application::ai::htmlData $html] }
	return
}


proc ::ai::studyplan::Progress {state} {
	variable Priv
	variable mc

	set html "<p><b>$mc::Title</b></p>"
	if {[dict exists $state text]} {
		append html "<p>[::application::ai::escape [dict get $state text]]</p>"
	}
	append html "<p>[llength $Priv(mistakes)] mistake(s) so far.</p>"
	return $html
}


proc ::ai::studyplan::Finish {} {
	variable Priv
	variable mc

	set Priv(running) 0
	set cancelled $Priv(cancel)
	set Priv(cancel) 0

	variable Slot
	catch { ::scidb::game::release $Slot }

	set summary [expr {$cancelled
		? [format $mc::Cancelled $Priv(gameIndex) [llength $Priv(mistakes)]]
		: [format $mc::Done $Priv(moveIndex) $Priv(gameIndex) [llength $Priv(mistakes)]]}]

	set plan [PlanText]
	set html "<p><b>$mc::Title</b></p><p>[::application::ai::escape $summary]</p>"
	if {[string length $plan]} {
		append html "<p><b>What the audit found</b></p><pre>[::application::ai::escape $plan]</pre>"
	}
	Report $html

	if {$Priv(prose) && [llength $Priv(mistakes)]} { Summarize $summary $plan }

	set done $Priv(done)
	set Priv(done) {}
	if {[llength $done]} {
		catch { {*}$done [dict create ok 1 summary $summary mistakes [llength $Priv(mistakes)] \
			games $Priv(gameIndex) plan $plan] }
	}
	return $summary
}


# The narrative summary: the model phrases the audit, grounded in the
# cluster numbers, audited by the claim checker (which has nothing to
# check here but legality of any move it names -- so the facts are also
# spelled out in the prompt).
proc ::ai::studyplan::Summarize {summary plan} {
	variable Priv

	if {[llength [info commands ::ai::provider::completeAsync]] == 0} { return }
	if {[info exists ::application::ai::Config(provider)]} {
		::ai::provider::configure -name $::application::ai::Config(provider) \
			-model $::application::ai::Config(model) -timeout 300000 \
			-options [list num_predict 400]
	}
	set prompt "A chess database audited these games with an engine and found:\n\
		$summary\n\n$plan\n\n\
		Write four short paragraphs for the player: what to fix first, what the pattern says, \
		and a concrete training routine. Use only these numbers and moves; invent nothing."
	::ai::provider::completeAsync $prompt [namespace code OnSummary] \
		-system "You summarise a chess audit for the player. Every number and move you\
			mention must come from the audit text. Do not invent games, moves or counts."
	return
}


proc ::ai::studyplan::OnSummary {result} {
	if {![dict get $result ok]} { return }
	set text [string trim [dict get $result text]]
	if {![string length $text]} { return }
	Report "<p><b>Study plan</b></p><p>[::application::ai::escape $text]</p>"
	return
}

# vi:set ts=3 sw=3:
