# ======================================================================
# ::ai::similar -- "find games like this + why" (audit B8).
#
# ai-simindex.tcl supplies candidates: exact common mainline ply prefixes
# from the same starting position. Pass candidates to facts with that
# starting FEN (not an arbitrary midgame position). This module ranks
# those counts and phrases the rationale through the grounded pipeline
# of ::ai::trend (fact block -> prompt -> provider -> claim check -> retry).
#
#   ::ai::similar::facts <fen> <candidates> ?-limit N?
#       -> dict {fen F games N rows ROWS} with ROWS the N most similar
#          games, each {white black result year shared}, ranked by shared
#          plies (descending), ties by white then black
#   ::ai::similar::factsText <facts>  -> the deterministic fact block
#   ::ai::similar::narrate <parent> <facts> ?-done CMD?
#
# Firewall: the shared counts, names, results and years are the
# retrieval's; the narrative may use only those overlap facts. A move
# named in the rationale is judged by the claim checker against the
# reference position ( -fen ), so a move that is not legal there fails
# the check. Without a language model, without a report pane and on a
# provider error, the fact block is the report. Nothing is written.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-similar
}

package require Tcl 8.5

namespace eval ::ai::similar {
	# how many similar games the facts carry
	variable Games 10
}


# Most shared plies first; ties broken by the players, so the
# order never wavers.
proc ::ai::similar::Compare {a b} {
	set n [expr {[lindex $b 4] - [lindex $a 4]}]
	if {$n != 0} { return $n }
	set n [string compare [lindex $a 0] [lindex $b 0]]
	if {$n != 0} { return $n }
	return [string compare [lindex $a 1] [lindex $b 1]]
}


proc ::ai::similar::facts {fen candidates args} {
	variable Games
	array set opts [list -limit $Games]
	array set opts $args

	set rows {}
	foreach c $candidates {
		set year [dict get $c year]
		set result [dict get $c result]
		lappend rows [list \
			[dict get $c white] [dict get $c black] \
			[expr {$result eq "" ? "?" : $result}] \
			[expr {$year eq "" || $year == 0 ? "?" : $year}] \
			[dict get $c shared]]
	}
	set rows [lrange [lsort -command Compare $rows] 0 [expr {$opts(-limit) - 1}]]

	return [dict create fen $fen games [llength $candidates] rows $rows]
}


proc ::ai::similar::factsText {facts} {
	set lines [list "position: [dict get $facts fen]" \
		"candidate games: [dict get $facts games]"]
	if {![llength [dict get $facts rows]]} {
		lappend lines "no games share opening plies with this position"
		return [join $lines \n]
	}
	lappend lines "games sharing the most opening plies (half-moves) with it:"
	foreach row [dict get $facts rows] {
		lassign $row white black result year shared
		lappend lines "  $white - $black ($result, $year): shares $shared [expr {$shared == 1 ? "ply" : "plies"}]"
	}
	return [join $lines \n]
}


proc ::ai::similar::prompt {block} {
	return "A chess player's game is compared with games from a database by how many opening plies (half-moves of the main line, from the same start) they share:\n\n$block\n\nWrite a short note explaining why those games are alike: which share the most plies with this game, and how their players, results and years compare. Use only the games, numbers, names, results and years in the overlap facts; repeat counts exactly; invent nothing, give no evaluation and no move or variation beyond the facts."
}


proc ::ai::similar::system {} {
	return "You explain why games in a chess database resemble a given game. Every player, number, result and year you mention must come from the overlap facts you were given: rephrase them, never add to them. Do not evaluate any position, do not describe the board, and do not extend any move into a variation."
}


proc ::ai::similar::narrate {parent facts args} {
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
		-title "AI: similar games" -fen [dict get $facts fen]
	return $block
}

# The GUI/assistant entry: retrieve the games that share the most opening
# plies with database game <number> (zero-based, ai-simindex) and narrate
# them. -done gets {ok 1 text ... claims ... grounded ...} as ::ai::trend does,
# or {ok 0 text MESSAGE} when the retrieval is unavailable or fails. The
# reference starting position is read from the database, including setups
# and Chess960 positions; it is also used by the claim checker.
proc ::ai::similar::report {parent base variant number args} {
	array set opts {-done {} -limit 10 -seconds 3}
	array set opts $args

	if {[llength [info commands ::ai::similar::candidates]] == 0} {
		return [Failed $opts(-done) "similar-game retrieval is not available"]
	}
	if {[catch {
		candidates $base $variant $number -limit $opts(-limit) -seconds $opts(-seconds)
	} rows]} {
		return [Failed $opts(-done) "similar games could not be retrieved: $rows"]
	}
	if {[catch {StartingFen $base $variant $number} start]} {
		return [Failed $opts(-done) "reference starting position could not be read: $start"]
	}
	return [narrate $parent [facts $start $rows -limit $opts(-limit)] -done $opts(-done)]
}


# Decode the reference in a private slot: metadata tags omit synthesized FENs.
# Slots 30 and 31 belong to study plans and training; this reader uses 32.
proc ::ai::similar::StartingFen {base variant number} {
	set slot 32
	if {[::scidb::game::query $slot open?]} { error "reference reader already in use" }
	set code [catch {
		::scidb::game::new $slot
		::scidb::game::load $slot $base $variant $number
		::scidb::game::query $slot fen
	} fen options]
	catch { ::scidb::game::release $slot }
	return -options $options $fen
}

proc ::ai::similar::Failed {done message} {
	if {[llength $done]} {
		after 0 [list {*}$done [dict create ok 0 text $message]]
	}
	return $message
}

# vi:set ts=3 sw=3:
