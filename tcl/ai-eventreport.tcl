# ======================================================================
# ::ai::eventreport -- a read-only, grounded narrative of an event and
# its crosstable (audit B5).
#
# The rows are the final standings the crosstable/event view already
# computed (::scidb::crosstable::get playerName/playerInfo, the event's
# game count from ::scidb::db::get eventInfo): each player's name, score
# and number of games. The numbers are already computed, so this is
# summarization only: the language model phrases them through the
# ordinary grounded pipeline of ::ai::trend (fact block -> prompt ->
# provider -> claim check -> one retry).
#
#   ::ai::eventreport::facts <event> <rows> ?-limit N? ?-games G?
#       -> dict {event E players N games G standings ROWS} with ROWS the
#          N best-placed players, each {name points games} (points as the
#          table reports them)
#   ::ai::eventreport::standingsFromTags <tagDicts> -> {event ROWS}, points from Result tags
#   ::ai::eventreport::report <parent> <base> <variant> <view>
#       -> the crosstable window's entry: read the view's games, narrate
#   ::ai::eventreport::factsText <facts>  -> the deterministic fact block
#   ::ai::eventreport::narrate <parent> <facts> ?-done CMD?
#
# Firewall: the names, scores and counts are Scidb's. This is about
# *counts* only -- no position is involved, so no -fen is handed to the
# claim checker: any move-like or placement claim in the narrative fails
# the check, which is the strict side. Without a language model, without
# a report pane and on a provider error, the fact block is the report.
# Nothing is written.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-eventreport
}

package require Tcl 8.5

namespace eval ::ai::eventreport {
	# how many players the facts carry
	variable Players 12
}

# The points a row reports, as a number (0 if it is not one), so the
# standings sort never fails over a malformed table.
proc ::ai::eventreport::Num {value} {
	if {[string is double -strict $value]} { return $value }
	return 0
}

# One row, read either as a dict {name points games} (the crosstable's
# own shape) or as the plain list {name points games}.
proc ::ai::eventreport::Row {row} {
	if {[dict exists $row name]} {
		return [list [dict get $row name] [dict get $row points] [dict get $row games]]
	}
	return [lrange $row 0 2]
}

# Most points first; ties broken by the player's name, so the order never
# wavers. The standings arrive in that order already; a stable sort makes
# the block independent of that. Points are fractional, so the comparison
# answers with the sign only (lsort demands an integer).
proc ::ai::eventreport::Compare {a b} {
	set d [expr {[Num [lindex $b 1]] - [Num [lindex $a 1]]}]
	if {$d > 0} { return 1 }
	if {$d < 0} { return -1 }
	return [string compare [lindex $a 0] [lindex $b 0]]
}

# The event facts: the event's name, its player and game counts and the
# final standings. -games states the event's game count (::scidb::db::get
# eventInfo frequency); without it the games column is totalled.
proc ::ai::eventreport::facts {event rows args} {
	variable Players
	array set opts [list -limit $Players -games ""]
	array set opts $args

	set standings {}
	set games 0
	foreach row $rows {
		lassign [Row $row] name points n
		if {![string is integer -strict $n]} { set n 0 }
		incr games $n
		lappend standings [list $name $points $n]
	}
	set standings [lsort -command Compare $standings]
	set standings [lrange $standings 0 [expr {$opts(-limit) - 1}]]

	if {[string is integer -strict $opts(-games)]} { set games $opts(-games) }

	return [dict create \
		event $event players [llength $rows] games $games standings $standings]
}


# The standings of a list of games' tag dicts (White, Black, Result, Event):
# a win scores 1, a draw 1/2, and a game without a decided result scores
# nothing but still counts as played. -> {event ROWS} with ROWS {name points games}.
proc ::ai::eventreport::standingsFromTags {tagList} {
	set event ""
	array set points {}
	array set played {}
	foreach tags $tagList {
		if {$event eq "" && [dict exists $tags Event]} { set event [dict get $tags Event] }
		foreach {side other} {White 1-0 Black 0-1} {
			if {![dict exists $tags $side]} { continue }
			set name [dict get $tags $side]
			if {![info exists points($name)]} { set points($name) 0 ; set played($name) 0 }
			incr played($name)
			set result [expr {[dict exists $tags Result] ? [dict get $tags Result] : "*"}]
			if {$result eq $other} {
				set points($name) [expr {$points($name) + 1}]
			} elseif {$result eq "1/2-1/2"} {
				set points($name) [expr {$points($name) + 0.5}]
			}
		}
	}
	set rows {}
	foreach name [array names points] {
		set pts $points($name)
		if {$pts == int($pts)} { set pts [expr {int($pts)}] }
		lappend rows [list $name $pts $played($name)]
	}
	return [list $event $rows]
}


# The games of the event a crosstable window shows: <view> is the window's
# own view (it holds exactly the event's games). Reads only.
proc ::ai::eventreport::Tags {base variant view} {
	set list {}
	set count [::scidb::view::count games $base $variant $view]
	for {set row 0} {$row < $count} {incr row} {
		set number [::scidb::db::get gameNumber $base $variant $row $view]
		set tags {}
		foreach pair [::scidb::db::get tags $number $base $variant] { dict set tags {*}$pair }
		lappend list $tags
	}
	return $list
}


# The crosstable window's menu entry: the standings of the games of its view,
# narrated (or, without a model, listed). Entirely read-only.
proc ::ai::eventreport::report {parent base variant view} {
	if {[catch { standingsFromTags [Tags $base $variant $view] } result]} { return "" }
	lassign $result event rows
	set facts [facts $event $rows -games [::scidb::view::count games $base $variant $view]]
	return [narrate $parent $facts]
}


proc ::ai::eventreport::factsText {facts} {
	set lines [list "event: [dict get $facts event]" \
		"players: [dict get $facts players]" \
		"games: [dict get $facts games]"]
	if {![llength [dict get $facts standings]]} {
		lappend lines "no players"
		return [join $lines \n]
	}
	lappend lines "final standings, most points first:"
	foreach row [dict get $facts standings] {
		lassign $row name points games
		lappend lines "  $name: $points points from $games games"
	}
	return [join $lines \n]
}


proc ::ai::eventreport::prompt {block} {
	return "A chess event reports these crosstable facts:\n\n$block\n\nWrite a short event report for the event's organiser: who finished at the top, how the points are spread among the leading players, and how many games each of them played. Use only the names, scores and numbers in the facts; repeat points and counts exactly; invent nothing, describe no position and name no move."
}


proc ::ai::eventreport::system {} {
	return "You summarise an event's crosstable for its organiser. Every player name, score and number you mention must come from the facts you were given: rephrase them, never add to them. Do not name a move, an opening or an evaluation, and do not describe any position on the board."
}


proc ::ai::eventreport::narrate {parent facts args} {
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
		-title "AI: event report"
	return $block
}

# vi:set ts=3 sw=3:
