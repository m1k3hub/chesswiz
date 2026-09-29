# ======================================================================
# ::ai::openingprep -- a read-only, grounded narrative of an opening-prep
# table (audit B3).
#
# The rows are the candidate moves Extras > Opening Prep computed for the
# current position (::scidb::tree::describe): games, score, draws, average
# rating, last year played and the best player of each. The numbers are
# already computed, so this is summarization only: the language model
# phrases them through the ordinary grounded pipeline of ::ai::trend
# (fact block -> prompt -> provider -> claim check -> one retry).
#
#   ::ai::openingprep::facts <fen> <rows> ?-limit N?
#       -> dict {fen F games N moves ROWS} with ROWS the N most played
#          candidate moves, each {move eco games score draws rating year player}
#          (score and draws in percent, one decimal)
#   ::ai::openingprep::factsText <facts>  -> the deterministic fact block
#   ::ai::openingprep::narrate <parent> <facts> ?-done CMD?
#
# Firewall: the counts and percentages are Scidb's; a move named in the
# narrative is judged by the claim checker against the position the table
# belongs to, so a move that is not legal there fails the check. Without a
# language model, without a report pane and on a provider error, the fact
# block is the report. Nothing is written.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-openingprep
}

package require Tcl 8.5

namespace eval ::ai::openingprep {
	# how many candidate moves the facts carry
	variable Moves 8
}


# The rows arrive most played first; a stable sort by games makes the
# order independent of that, ties broken by the move text.
proc ::ai::openingprep::Compare {a b} {
	set n [expr {[lindex $b 2] - [lindex $a 2]}]
	if {$n != 0} { return $n }
	return [string compare [lindex $a 0] [lindex $b 0]]
}


proc ::ai::openingprep::Percent {permille} {
	if {![string is double -strict $permille]} { return "?" }
	return [format %.1f [expr {$permille/10.0}]]
}


proc ::ai::openingprep::facts {fen rows args} {
	variable Moves
	array set opts [list -limit $Moves]
	array set opts $args

	set games 0
	set moves {}
	foreach row $rows {
		set n [dict get $row frequency]
		incr games $n
		if {!$n} { continue }
		set year [dict get $row lastYear]
		lappend moves [list \
			[dict get $row move] [dict get $row eco] $n \
			[Percent [dict get $row score]] [Percent [dict get $row draws]] \
			[dict get $row averageRating] \
			[expr {$year eq "" || $year == 0 ? "?" : $year}] \
			[dict get $row bestPlayer]]
	}
	set moves [lrange [lsort -command Compare $moves] 0 [expr {$opts(-limit) - 1}]]

	return [dict create fen $fen games $games moves $moves]
}


proc ::ai::openingprep::factsText {facts} {
	set lines [list "position: [dict get $facts fen]" \
		"games: [dict get $facts games]"]
	if {![llength [dict get $facts moves]]} {
		lappend lines "no candidate moves"
		return [join $lines \n]
	}
	lappend lines "candidate moves, most played first:"
	foreach row [dict get $facts moves] {
		lassign $row move eco n score draws rating year player
		lappend lines "  $move ($eco): $n games, score $score%, draws $draws%,\
			average rating $rating, last played $year, best player $player"
	}
	return [join $lines \n]
}


proc ::ai::openingprep::prompt {block} {
	return "A chess opening-preparation table lists these candidate moves for one position:\n\n$block\n\nWrite a short preparation note: which moves are played most, which score best for the side that plays them, which draw most often, and where the rare lines are. Use only the moves, ECO codes, numbers and names in the facts; repeat counts and percentages exactly; invent nothing, give no evaluation and no variation beyond the listed moves."
}


proc ::ai::openingprep::system {} {
	return "You summarise an opening-preparation table for a chess player. Every move, ECO code, number and name you mention must come from the table you were given: rephrase it, never add to it. Do not evaluate the position, do not say who stands better, and do not extend any move into a variation."
}


proc ::ai::openingprep::narrate {parent facts args} {
	array set opts [list -done {}]
	array set opts $args

	set block [factsText $facts]
	if {![llength [info commands ::ai::trend::narrate]]} {
		if {[llength $opts(-done)]} {
			after 0 [list {*}$opts(-done) [dict create ok 1 text $block claims {} grounded 1]]
		}
		return $block
	}
	::ai::trend::narrate $parent $facts -done $opts(-done) -block $block \
		-prompt [prompt $block] -system [system] \
		-title "AI: opening preparation" -fen [dict get $facts fen]
	return $block
}

# vi:set ts=3 sw=3:
