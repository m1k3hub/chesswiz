# ======================================================================
# ::ai::cql -- features on top of the CQL matcher (CQL_FEATURES.md).
#
# CQL is exact: it finds and labels positions. The engine decides what a
# move is worth, the database what happened; no model is involved here.
#
#   ::ai::cql::profile <base> <variant> <player> ?-colour white|black? ?-games 200?
#       -> dict {player NAME games N structures {id {games n points p numbers {..}}}}
#          how often the player's games reach each structure pattern, and
#          the player's score in them
#   ::ai::cql::profileText <profile> ?-min 3?  -> the facts as text lines
#   ::ai::cql::themes <fen> ?<san>?
#       -> dict {events {ids} structures {ids}}: the event patterns the move
#          satisfies (with <san>) and the structures of the position after it
#   ::ai::cql::quality <base> <variant>
#       -> dict {check {game ...}}: games whose result contradicts their end
#   ::ai::cql::qualityReport <parent> ?<base> <variant>?
#   ::ai::cql::training <parent> ?-patterns ids? ?-player P? ?-max 20?
#       ?-scan 300? ?-depth 14? ?-done CMD?
#       puzzles from the database's games, each solution certified by the
#       engine, written as a PGN file under the user directory
#
# In standard chess all of this runs on the CQL 6.2 engine and the whole
# pattern library (one pass per set of games, ::ai::search::match6 for one
# position); other variants keep the legacy engine and its 12 patterns.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-cql
}

package require Tcl 8.5

namespace eval ai {
namespace eval cql {

# Results that contradict how the game ended. Checked in
# tests/test_app_cqlfeatures.tcl.
variable Checks {
	mate_scored_draw {
		"checkmate scored as a draw"
		{(match :result 1/2-1/2 (position :terminal :mate))}
	}
	white_mated_scored_1-0 {
		"White is mated, but the result is 1-0"
		{(match :result 1-0 (position :terminal :wtm :mate))}
	}
	black_mated_scored_0-1 {
		"Black is mated, but the result is 0-1"
		{(match :result 0-1 (position :terminal :btm :mate))}
	}
	stalemate_scored_1-0 {
		"stalemate scored as a White win"
		{(match :result 1-0 (position :terminal :stalemate))}
	}
	stalemate_scored_0-1 {
		"stalemate scored as a Black win"
		{(match :result 0-1 (position :terminal :stalemate))}
	}
}

# the events a puzzle can be made of: each turns on one decisive move
variable TrainingPatterns {
	checkmate smothered_mate back_rank_mate boden_mate anastasia_mate arabian_mate
	epaulette_mate queen_pawn_mate double_check discovered_check knight_fork skewer
	greek_gift double_bishop_sacrifice underpromotion
}
# without CQL 6.2 (variants): the legacy engine's
variable LegacyTrainingPatterns {checkmate smothered_mate double_check underpromotion}

# the latest games of a view searched for training positions when the
# database has no pattern index
variable TrainingScanGames 20000

# the game slot candidates are read into, so the user's board is untouched
# (the merge dialog uses 20 and 21, the study plan 30)
variable Slot 31

# a solution must be the engine's best move and a forced mate, or this much
# (centipawns) better than the second-best move
variable UniqueGapCp 150

variable Priv
array set Priv {
	running	0
	cancel	0
}

} ;# namespace cql
} ;# namespace ai


# ======================================================================
# A player's games
# ======================================================================

# The resolved name and the numbers of the player's latest <max> games
# (with <colour>, if given), each as {number side points}: the player's
# side and score in it (1, 0.5, 0; {} for an unfinished game).
proc ::ai::cql::PlayerGames {base variant player colour max} {
	lassign [::application::assistant::ResolvePlayer $base $variant $player] _ name

	set criteria [dict create player $name]
	if {$colour ne ""} { dict set criteria color $colour }
	set criteria [dict get [::application::assistant::CheckArgs search_games $criteria] criteria]
	lassign [::application::assistant::BuildQuery $base $variant $criteria] query

	set view [::scidb::view::new $base $variant unused unused unused unused master slave]
	set games {}
	set rc [catch {
		::scidb::view::search $base $variant $view null none $query
		set count [::scidb::view::count games $base $variant $view]
		for {set row [expr {max(0, $count - $max)}]} {$row < $count} {incr row} {
			set number [::scidb::db::get gameNumber $base $variant $row $view]
			set tags {}
			foreach pair [::scidb::db::get tags $number $base $variant] { dict set tags {*}$pair }
			set side [expr {[dict exists $tags White] && [dict get $tags White] eq $name ? "white" : "black"}]
			set result [expr {[dict exists $tags Result] ? [dict get $tags Result] : "*"}]
			switch -- $result {
				1-0		{ set points [expr {$side eq "white" ? 1.0 : 0.0}] }
				0-1		{ set points [expr {$side eq "black" ? 1.0 : 0.0}] }
				1/2-1/2	{ set points 0.5 }
				default	{ set points {} }
			}
			lappend games [list $number $side $points]
		}
	} err opts]
	catch { ::scidb::view::close $base $variant $view }
	if {$rc} { return -options $opts $err }
	return [list $name $games]
}


# Whether <variant> searches with CQL 6.2.
proc ::ai::cql::Engine6 {variant} {
	return [expr {$variant eq "Normal" && [::ai::search::engine6]}]
}


# Library patterns <ids> over the games <numbers>, in one CQL 6.2 pass
# (waiting for it in a nested event loop): dict id -> {game first_ply ...}.
proc ::ai::cql::Matches6 {base variant numbers ids} {
	variable Wait
	variable WaitSerial

	set out [dict create]
	foreach id $ids { dict set out $id {} }
	if {![llength $numbers] || ![llength $ids]} { return $out }
	set scripts [lmap id $ids { ::ai::search::pattern6 $id }]
	set more [expr {[llength $scripts] > 1 ? [list -scripts [lrange $scripts 1 end]] : {}}]
	if {![info exists WaitSerial]} { set WaitSerial 0 }
	set token [incr WaitSerial]
	set view [::scidb::view::new $base $variant unused unused unused unused master slave]
	try {
		::scidb::view::setGames $base $variant $view $numbers
		::scidb::cql6::search $base $variant [lindex $scripts 0] {*}$more -view $view -compact 1 \
			-command [list set [namespace current]::Wait($token)]
		vwait [namespace current]::Wait($token)
		set result $Wait($token)
	} finally {
		unset -nocomplain Wait($token)
		catch { ::scidb::view::close $base $variant $view }
	}
	if {![dict get $result ok]} { error [dict get $result error] }
	if {[dict get $result cancelled]} { error "the CQL search was cancelled" }
	if {[llength $scripts] > 1} {
		foreach {game ply i} [dict get $result matches] { dict lappend out [lindex $ids $i] $game $ply }
	} else {
		dict set out [lindex $ids 0] [dict get $result matches]
	}
	return $out
}


# ======================================================================
# 1. Structure profile
# ======================================================================
proc ::ai::cql::profile {base variant player args} {
	array set opts {-colour "" -games 200}
	array set opts $args

	lassign [PlayerGames $base $variant $player $opts(-colour) $opts(-games)] name games

	set ids [::ai::search::patternIds structure]
	if {[Engine6 $variant]} {
		set found [Matches6 $base $variant [lmap g $games { lindex $g 0 }] $ids]
		set hit [dict create]
		dict for {id pairs} $found {
			foreach {game ply} $pairs { dict set hit $id $game 1 }
		}
	}

	set structures {}
	foreach id $ids {
		set cql [dict get [::ai::search::pattern $id] cql]
		if {![info exists hit] && $cql eq ""} continue
		set n 0
		set scored 0
		set points 0.0
		set numbers {}
		foreach g $games {
			lassign $g number side score
			if {[info exists hit]} {
				if {![dict exists $hit $id $number]} { continue }
			} elseif {[catch { ::scidb::cql::match $base $variant $number $cql } ply] || $ply < 0} {
				continue
			}
			incr n
			lappend numbers $number
			if {$score ne ""} {
				incr scored
				set points [expr {$points + $score}]
			}
		}
		dict set structures $id [dict create games $n scored $scored points $points numbers $numbers]
	}
	return [dict create player $name colour $opts(-colour) games [llength $games] structures $structures]
}


# The profile as fact lines. A structure needs <min> games to be shown; the
# lowest score among those with at least 5 scored games under 40% is marked
# as the weakest structure.
proc ::ai::cql::profileText {profile args} {
	array set opts {-min 3}
	array set opts $args

	set total [dict get $profile games]
	if {$total == 0} { return "" }

	set rows {}
	dict for {id s} [dict get $profile structures] {
		if {[dict get $s games] < $opts(-min)} { continue }
		set score [expr {[dict get $s scored] ? round(100.0 * [dict get $s points] / [dict get $s scored]) : -1}]
		lappend rows [list $id [dict get $s games] [dict get $s scored] $score]
	}
	if {![llength $rows]} { return "" }

	set weakest ""
	set low 40
	foreach row $rows {
		lassign $row id n scored score
		if {$scored >= 5 && $score >= 0 && $score < $low} {
			set weakest $id
			set low $score
		}
	}

	set colour [dict get $profile colour]
	set lines [list [format "POSITION TYPES in %s's latest %d games%s (found by CQL):" \
		[dict get $profile player] $total [expr {$colour ne "" ? " with $colour" : ""}]]]
	foreach row [lsort -integer -decreasing -index 1 $rows] {
		lassign $row id n scored score
		set line [format "  %s: %d games (%d%%)" [dict get [::ai::search::pattern $id] label] \
			$n [expr {round(100.0 * $n / $total)}]]
		if {$score >= 0} { append line [format ", scores %d%%" $score] }
		if {$id eq $weakest} { append line " -- their weakest structure" }
		lappend lines $line
	}
	return [join $lines \n]
}


# ======================================================================
# 2. Themes of a move or a position
# ======================================================================
proc ::ai::cql::themes {fen {san ""}} {
	if {[::ai::search::engine6]} {
		set events {}
		set after $fen
		if {$san ne ""} {
			if {[catch { ::scidb::ai::moveFacts $san $fen } facts]
			 || ![regexp {"fenAfter":"([^"]+)"} $facts -> after]
			 || ![regexp {"uci":"([^"]+)"} $facts -> uci]} {
				return [dict create events {} structures {}]
			}
			if {[catch { ::ai::search::match6 $fen [::ai::search::patternIds event] $uci } events]} {
				set events {}
			}
			# a named mate says more than "checkmate"
			if {"checkmate" in $events && [llength [lsearch -all -glob $events *_mate]]} {
				set events [lsearch -all -inline -not -exact $events checkmate]
			}
		}
		return [dict create events $events structures [::ai::search::structures $after]]
	}
	set events {}
	set after $fen
	if {$san ne ""} {
		foreach id [::ai::search::patternIds event] {
			set cql [dict get [::ai::search::pattern $id] cql]
			if {$cql eq ""} continue
			if {![catch { ::scidb::cql::position $fen $cql $san } hit] && $hit} { lappend events $id }
		}
		if {[catch { ::scidb::ai::moveFacts $san $fen } facts]
		 || ![regexp {"fenAfter":"([^"]+)"} $facts -> after]} {
			set after ""
		}
	}
	set structures [expr {$after eq "" ? {} : [::ai::search::structures $after]}]
	return [dict create events $events structures $structures]
}


# One line for a prompt, or "" when nothing was found.
proc ::ai::cql::themesText {themes} {
	set labels {}
	foreach id [concat [dict get $themes events] [dict get $themes structures]] {
		lappend labels [dict get [::ai::search::pattern $id] label]
	}
	if {![llength $labels]} { return "" }
	return "THEMES (found by CQL, exact): [join $labels {, }]"
}


# ======================================================================
# 4. Data quality
# ======================================================================
proc ::ai::cql::quality {base variant} {
	variable Checks
	set out {}
	dict for {id check} $Checks {
		set games [::scidb::cql::search $base $variant [lindex $check 1]]
		if {[llength $games]} { dict set out $id $games }
	}
	return $out
}


# The game-list query for the failing checks of <found>.
proc ::ai::cql::qualityQuery {found} {
	variable Checks
	set terms [lmap id [dict keys $found] { list cql [lindex [dict get $Checks $id] 1] }]
	if {[llength $terms] == 1} { return [lindex $terms 0] }
	return [list OR {*}$terms]
}


proc ::ai::cql::qualityText {base variant found} {
	variable Checks
	if {![dict size $found]} { return "no result contradicts how its game ended" }
	set lines {}
	dict for {id games} $found {
		lappend lines "[lindex [dict get $Checks $id] 0]: [llength $games] game(s)"
		foreach number [lrange $games 0 19] {
			set tags {}
			foreach pair [::scidb::db::get tags $number $base $variant] { dict set tags {*}$pair }
			set line "  #[expr {$number + 1}]"
			foreach tag {White Black Result Date} {
				append line " " [expr {[dict exists $tags $tag] ? [dict get $tags $tag] : "?"}]
			}
			lappend lines $line
		}
		if {[llength $games] > 20} { lappend lines "  ..." }
	}
	return [join $lines \n]
}


# Run the checks on the active database, report them, and filter the game
# list to the games that failed. Returns the text.
proc ::ai::cql::qualityReport {parent {base ""} {variant ""}} {
	if {$base eq ""} { lassign [::application::assistant::ActiveBase] base variant }

	set found [quality $base $variant]
	set text [qualityText $base $variant $found]
	if {[dict size $found]} {
		::scidb::view::search $base $variant 0 null none [qualityQuery $found]
		append text "\nThe game list now shows these games; Clear Search shows all again."
	}
	if {[llength [info commands ::application::ai::showReport]]} {
		catch { ::application::ai::showReport $parent "AI: result check" \
			[::application::ai::htmlData "<p><b>Result check</b></p><pre>[::application::ai::escape $text]</pre>"] }
	}
	return $text
}


# ======================================================================
# 3. Training sets
# ======================================================================
proc ::ai::cql::running? {} {
	variable Priv
	return $Priv(running)
}


proc ::ai::cql::cancel {} {
	variable Priv
	if {$Priv(running)} { set Priv(cancel) 1 }
}


proc ::ai::cql::training {parent args} {
	variable Priv
	variable TrainingPatterns
	variable LegacyTrainingPatterns

	array set opts [list -patterns {} -player "" -max 20 -scan 300 -depth 14 -done {} -file ""]
	array set opts $args

	if {$Priv(running)} { error "a training set is already being built" }
	if {[llength [info commands ::ai::engine::available]] == 0 || ![::ai::engine::available]} {
		error "no chess engine is available to certify the solutions"
	}
	lassign [::application::assistant::ActiveBase] base variant
	set allowed [expr {[Engine6 $variant] ? $TrainingPatterns : $LegacyTrainingPatterns}]
	if {![llength $opts(-patterns)]} { set opts(-patterns) $allowed }
	foreach id $opts(-patterns) {
		if {$id ni $allowed} {
			error "pattern must be one of: [join $allowed {, }]"
		}
	}

	set candidates {}
	if {[Engine6 $variant]} {
		set candidates [Candidates6 $base $variant $opts(-patterns) $opts(-player) $opts(-scan)]
	} else {
		foreach id $opts(-patterns) {
			set criteria [dict create pattern $id]
			if {$opts(-player) ne ""} {
				lassign [::application::assistant::ResolvePlayer $base $variant $opts(-player)] _ name
				dict set criteria player $name
			}
			set criteria [dict get [::application::assistant::CheckArgs search_games $criteria] criteria]
			lassign [::application::assistant::BuildQuery $base $variant $criteria] query
			set view [::scidb::view::new $base $variant unused unused unused unused master slave]
			catch {
				::scidb::view::search $base $variant $view null none $query
				set count [::scidb::view::count games $base $variant $view]
				# the latest games first
				for {set row [expr {$count - 1}]} {$row >= max(0, $count - $opts(-scan))} {incr row -1} {
					lappend candidates [list $id [::scidb::db::get gameNumber $base $variant $row $view]]
				}
			}
			catch { ::scidb::view::close $base $variant $view }
		}
	}

	set file $opts(-file)
	if {$file eq ""} {
		set dir [file join $::scidb::dir::user training]
		set file [file join $dir "training-[clock format [clock seconds] -format %Y%m%d-%H%M%S].pgn"]
	}

	array set Priv [list running 1 cancel 0 parent $parent base $base variant $variant \
		candidates $candidates index 0 depth $opts(-depth) max $opts(-max) done $opts(-done) \
		file $file puzzles {} rejected {}]

	Progress "Looking for positions in [llength $candidates] candidate game(s)..."
	after 50 [namespace code NextCandidate]
	return $file
}


# Training candidates {id number ply} for the patterns <ids>: the latest
# <scan> matches of each in the player's games (or the whole database),
# taken in turns so that a set mixes the patterns. From the pattern index
# when the database has one, otherwise from the latest TrainingScanGames
# games.
proc ::ai::cql::Candidates6 {base variant ids player scan} {
	variable TrainingScanGames

	set view [::scidb::view::new $base $variant unused unused unused unused master slave]
	try {
		if {$player ne ""} {
			lassign [::application::assistant::ResolvePlayer $base $variant $player] _ name
			set criteria [dict get [::application::assistant::CheckArgs search_games \
				[dict create player $name]] criteria]
			lassign [::application::assistant::BuildQuery $base $variant $criteria] query
			::scidb::view::search $base $variant $view null none $query
		} else {
			::scidb::view::search $base $variant $view reset none
		}
		set count [::scidb::view::count games $base $variant $view]
		set all [expr {$count == [::scidb::db::count games $base $variant]}]
		set indexed [expr {[llength [info commands ::ai::patternIndex::has]] > 0}]
		foreach id $ids {
			if {!$indexed || ![::ai::patternIndex::has $base $variant $id]} { set indexed 0; break }
		}
		if {$indexed} {
			set inView [dict create]
			if {!$all} {
				for {set row 0} {$row < $count} {incr row} {
					dict set inView [::scidb::db::get gameNumber $base $variant $row $view] 1
				}
			}
			set found [dict create]
			foreach id $ids {
				set pairs {}
				foreach {game ply} [::ai::patternIndex::lookup $base $variant $id] {
					if {$all || [dict exists $inView $game]} { lappend pairs $game $ply }
				}
				dict set found $id $pairs
			}
		} else {
			set numbers {}
			for {set row [expr {max(0, $count - $TrainingScanGames)}]} {$row < $count} {incr row} {
				lappend numbers [::scidb::db::get gameNumber $base $variant $row $view]
			}
			set found [Matches6 $base $variant $numbers $ids]
		}
	} finally {
		catch { ::scidb::view::close $base $variant $view }
	}

	# per pattern the latest games first, then in turns
	set lists {}
	foreach id $ids {
		set games [lsort -integer -decreasing -stride 2 -index 0 [dict get $found $id]]
		lappend lists [lmap {game ply} [lrange $games 0 [expr {2 * $scan - 1}]] { list $id $game $ply }]
	}
	set candidates {}
	for {set i 0} {$i < $scan} {incr i} {
		foreach list $lists {
			if {$i < [llength $list]} { lappend candidates [lindex $list $i] }
		}
	}
	return $candidates
}


proc ::ai::cql::Progress {text} {
	variable Priv
	if {[llength [info commands ::application::ai::showReport]] == 0} { return }
	catch { ::application::ai::showReport $Priv(parent) "AI: training set" \
		[::application::ai::htmlData "<p><b>Training set</b></p><p>[::application::ai::escape $text]</p>"] }
}


proc ::ai::cql::Reject {why} {
	variable Priv
	if {![dict exists $Priv(rejected) $why]} { dict set Priv(rejected) $why 0 }
	dict incr Priv(rejected) $why
}


proc ::ai::cql::NextCandidate {} {
	variable Priv

	if {!$Priv(running)} { return }
	if {$Priv(cancel) || $Priv(index) >= [llength $Priv(candidates)]
	 || [llength $Priv(puzzles)] >= $Priv(max)} {
		TrainingFinish
		return
	}

	lassign [lindex $Priv(candidates) $Priv(index)] id number ply
	incr Priv(index)
	Progress [format "Candidate %d of %d (game #%d), %d puzzle(s) so far." \
		$Priv(index) [llength $Priv(candidates)] [expr {$number + 1}] [llength $Priv(puzzles)]]
	update idletasks

	if {[catch { MakePuzzle $id $number $ply } puzzle]} {
		Reject "failed: $puzzle"
	} elseif {[dict exists $puzzle rejected]} {
		Reject [dict get $puzzle rejected]
	} elseif {[lsearch -exact [lmap p $Priv(puzzles) { dict get $p fen }] [dict get $puzzle fen]] >= 0} {
		# the same position from another copy of the game, or another pattern
		Reject "the same position again"
	} else {
		lappend Priv(puzzles) $puzzle
	}
	after 1 [namespace code NextCandidate]
}


# The position before the pattern's decisive move, and that move, certified
# by the engine; or {rejected WHY}. <ply> is the CQL 6.2 match (the
# position after the move, or before it for the MatchBefore patterns); ""
# asks the legacy engine.
proc ::ai::cql::MakePuzzle {id number {ply ""}} {
	variable Priv
	variable UniqueGapCp

	if {$ply eq ""} {
		set cql [dict get [::ai::search::pattern $id] cql]
		set ply [::scidb::cql::match $Priv(base) $Priv(variant) $number $cql]
	} elseif {[::ai::search::matchBefore $id]} {
		# the move is the one played from the matched position
		incr ply
	}
	if {$ply < 1} { return [dict create rejected "no decisive move"] }

	variable Slot
	if {![::scidb::game::query $Slot open?]} { ::scidb::game::new $Slot }
	::scidb::game::load $Slot $Priv(base) $Priv(variant) $number
	set plies [::scidb::game::query $Slot mainline]
	if {$ply > [llength $plies]} { return [dict create rejected "no decisive move"] }
	lassign [lindex $plies [expr {$ply - 1}]] key san fen

	set facts [::scidb::ai::moveFacts $san $fen]
	if {![regexp {"uci":"([^"]+)"} $facts -> uci]} { return [dict create rejected "unreadable move"] }

	set eval [::ai::engine::evaluate $fen -depth $Priv(depth) -multipv 2]
	set pv [dict get $eval pv]
	if {[lindex $pv 0] ne $uci} { return [dict create rejected "the move played is not the engine's best"] }

	set mate [expr {[dict get $eval kind] eq "mate" && [dict get $eval value] > 0}]
	set gap [expr {[dict exists $eval gapCp] ? [dict get $eval gapCp] : 100000}]
	if {!$mate && $gap < $UniqueGapCp} { return [dict create rejected "the solution is not unique"] }

	set tags {}
	foreach pair [::scidb::db::get tags $number $Priv(base) $Priv(variant)] { dict set tags {*}$pair }
	return [dict create pattern $id number $number fen $fen san $san pv [lrange $pv 0 4] \
		mate $mate gap $gap tags $tags]
}


# One puzzle as a PGN game: the solution move, then the engine's line.
proc ::ai::cql::PuzzlePGN {p} {
	set tags [dict get $p tags]
	set label [dict get [::ai::search::pattern [dict get $p pattern]] label]
	set fen [dict get $p fen]
	set out ""
	append out "\[Event \"Training: $label\"\]\n"
	append out "\[Site \"[Tag $tags Event]\"\]\n"
	append out "\[Date \"[Tag $tags Date]\"\]\n"
	append out "\[Round \"?\"\]\n"
	append out "\[White \"[Tag $tags White]\"\]\n"
	append out "\[Black \"[Tag $tags Black]\"\]\n"
	append out "\[Result \"*\"\]\n"
	append out "\[Annotator \"Scidb training set (CQL + engine)\"\]\n"
	append out "\[SetUp \"1\"\]\n"
	append out "\[FEN \"$fen\"\]\n\n"

	set why [expr {[dict get $p mate] ? "forces mate" : [format "is %.1f pawns better than any other move" \
		[expr {[dict get $p gap] / 100.0}]]}]
	set side [expr {[lindex [split $fen] 1] eq "w" ? "White" : "Black"}]
	set moveNo [lindex [split $fen] 5]
	append out "\{$side to move: find the $label. From [Tag $tags White] - [Tag $tags Black], [Tag $tags Date]; the solution $why.\} "
	# not through expr: it would read "6. " as the number 6.0
	if {$side eq "White"} { append out "$moveNo. " } else { append out "$moveNo... " }
	append out "[dict get $p san] \{engine line: [join [dict get $p pv] { }]\} *\n\n"
	return $out
}


proc ::ai::cql::Tag {tags name} {
	return [expr {[dict exists $tags $name] ? [dict get $tags $name] : "?"}]
}


proc ::ai::cql::TrainingFinish {} {
	variable Priv

	set Priv(running) 0
	set cancelled $Priv(cancel)
	set Priv(cancel) 0

	variable Slot
	catch { ::scidb::game::release $Slot }

	set n [llength $Priv(puzzles)]
	set lines [list [format "%s %d puzzle(s) from %d candidate game(s)." \
		[expr {$cancelled ? "Cancelled after" : "Built"}] $n $Priv(index)]]
	if {$n} {
		file mkdir [file dirname $Priv(file)]
		set fh [open $Priv(file) w]
		fconfigure $fh -encoding utf-8
		foreach p $Priv(puzzles) { puts -nonewline $fh [PuzzlePGN $p] }
		close $fh
		lappend lines "Written to $Priv(file); open it as a database to train."
		set counts {}
		foreach p $Priv(puzzles) { dict incr counts [dict get $p pattern] }
		dict for {id c} $counts { lappend lines "  [dict get [::ai::search::pattern $id] label]: $c" }
	}
	if {[dict size $Priv(rejected)]} {
		lappend lines "Not used (the engine did not certify a unique solution, or the position was unusable):"
		dict for {why c} $Priv(rejected) { lappend lines "  $why: $c" }
	}
	set text [join $lines \n]
	if {[llength [info commands ::application::ai::showReport]]} {
		catch { ::application::ai::showReport $Priv(parent) "AI: training set" \
			[::application::ai::htmlData "<p><b>Training set</b></p><pre>[::application::ai::escape $text]</pre>"] }
	}

	set done $Priv(done)
	set Priv(done) {}
	if {[llength $done]} {
		catch { {*}$done [dict create ok 1 puzzles $n file [expr {$n ? $Priv(file) : ""}] text $text] }
	}
	return $text
}

# vi:set ts=3 sw=3:
