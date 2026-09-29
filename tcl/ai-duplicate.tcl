# ======================================================================
# AI: duplicate-merge arbitration (System One)
# ======================================================================
# Two records that the database scan reports as duplicate candidates
# (::scidb::db::findDuplicates, consumed by
# tcl/app-database-maintenance.tcl) need an arbiter before anything is
# merged: are they the same game, or two different games? A
# deterministic rule answers the obvious cases: the four identity facts
# -- players (both sides), date, result, move count -- all known and
# equal say 'same'; a known result that differs, or players whose
# surnames clearly differ, say 'different'. The rest is asked of the
# bounded classifier (::ai::decide, type choice over the closed set
# {same different unsure}; eco and event go into the state as extra
# evidence). When the classifier does not settle the pair either, the
# label is 'unsure' -- today's behaviour, in which the deterministic
# dedup has found the candidates and nothing is merged.
#
#   ::ai::duplicate::rule <pairFacts>       -> same | different | ""
#   ::ai::duplicate::Question               -> the classifier question
#   ::ai::duplicate::decide <pairFacts> <script>
#   ::ai::duplicate::describe <label>       -> a human phrase
#   ::ai::duplicate::factsOfTags <tags>     -> one record's seven header facts
#   ::ai::duplicate::reviewGroup <base> <variant> <numbers> <script> ?-reader CMD?
#       the first game of a duplicate group against each other one; <script>
#       gets {{number label source} ...}
#
# <pairFacts> is a dict with two keys, 1 and 2, each mapping to the
# seven header facts of one record: white black date result eco moves
# event, where moves is the move count. All lookups tolerate missing or
# malformed facts by abstaining: a record that says nothing never turns
# into a guess, and two equal unknowns are not proof of anything (a
# placeholder date, an unset result or an absent move count only
# withhold the rule's verdict; they never make a 'different').
#
# Firewall: this only labels a candidate pair; it never mutates
# anything -- no database writes, no deletions, no moves, no comments.
# A 'same' answer is advice; acting on it is the caller's decision.
# The classifier's confidence threshold is the usual
# SCIDB_AI_DUPLICATE_MIN_CONFIDENCE (default 0.6, set by ::ai::decide).
# ======================================================================

package require Tcl 8.5

namespace eval ::ai::duplicate {

	# reviews in flight: key -> {pending N results {...} script CMD}
	variable Review
	variable ReviewSeq 0

	# the classifier's answer set (choice criteria name -> description)
	variable Criteria [dict create \
		same      "the two records are the same game, entered twice by accident" \
		different "two different games: another round, another pairing or another event" \
		unsure    "the records do not say enough to decide" \
		]

	# label -> English phrase ('' from the rule never reaches a caller)
	variable Names [dict create \
		same      "the same game (a duplicate record)" \
		different "a different game" \
		unsure    "undecided (the classifier did not settle the pair)" \
		]

	# result spellings -> one of the three canonical results; anything
	# else (unset, '*', junk) is not a result and never decides alone
	variable Results [dict create \
		"1-0"     "1-0"  "1:0" "1-0" \
		"0-1"     "0-1"  "0:1" "0-1" \
		"1/2-1/2" "1/2-1/2"  "1/2" "1/2-1/2"  "draw" "1/2-1/2"  "drawn" "1/2-1/2" \
		]
}


# Trim, lowercase and squeeze whitespace, so spellings compare by
# content: "KASPAROV,\tGary" and "kasparov, gary" are one name.
proc ::ai::duplicate::Canon {s} {
	set s [string tolower [string trim $s]]
	regsub -all {\s+} $s { } s
	return $s
}


# One canonical field of one record, or "" when the record does not
# have it -- a missing key, a malformed dict and an empty field all
# abstain rather than raise.
proc ::ai::duplicate::Field {pairFacts game field} {
	if {[catch { dict get [dict get $pairFacts $game] $field } value]} {
		return ""
	}
	return [Canon $value]
}


# A canonical date, or "" when the record says none: separators become
# '.', and a value without a single digit ("????.??.??") is as absent
# as an empty one.
proc ::ai::duplicate::CanonDate {d} {
	set d [Canon $d]
	if {$d eq "" || ![regexp {[0-9]} $d]} { return "" }
	regsub -all {[-./]} $d {.} d
	return $d
}


# One of the three canonical results, or "" when it is not a result.
proc ::ai::duplicate::CanonResult {r} {
	variable Results
	set r [Canon $r]
	return [expr {[dict exists $Results $r] ? [dict get $Results $r] : ""}]
}


# The move count as a number, or "" when the record does not give one.
proc ::ai::duplicate::CanonMoves {n} {
	set n [string trim $n]
	if {![string is integer -strict $n]} { return "" }
	return [expr {$n + 0}]
}


# A player is known when the name is not empty and not a placeholder.
proc ::ai::duplicate::NameKnown {name} {
	return [expr {$name ne "" && ![regexp {^[?.\s]*$} $name]}]
}


# The surname of a canonical "surname, given" name, else "". Two
# records of one game are written in the same style, so only comma form
# is allowed to speak about players.
proc ::ai::duplicate::Surname {name} {
	set i [string first {,} $name]
	if {$i <= 0} { return "" }
	return [string trimright [string range $name 0 [expr {$i - 1}]] { }]
}


# A clear player mismatch: both names in comma form, with different
# surnames. "Kasparov, G." against "Kasparov, Gary" is not a mismatch;
# that is what the classifier is for.
proc ::ai::duplicate::SurnameConflict {a b} {
	set sa [Surname $a]
	set sb [Surname $b]
	if {$sa eq "" || $sb eq ""} { return 0 }
	return [expr {$sa ne $sb ? 1 : 0}]
}


# The deterministic verdict over the four identity facts: 'same' when
# the players (known, both sides, in this order), the date, the result
# and the move count are all known and equal; 'different' when a known
# result differs or a surname makes the players clearly different;
# "" otherwise -- equal-but-unknown facts and near-miss names are proof
# of nothing, and neither is a differing date or move count on its own
# (a correction in one record is not a different game).
proc ::ai::duplicate::rule {pairFacts} {
	if {[catch { dict size $pairFacts }]} { return "" }

	foreach game {1 2} {
		set w($game)  [Field $pairFacts $game white]
		set b($game)  [Field $pairFacts $game black]
		set d($game)  [CanonDate [Field $pairFacts $game date]]
		set r($game)  [CanonResult [Field $pairFacts $game result]]
		set m($game)  [CanonMoves [Field $pairFacts $game moves]]
	}

	set samePlayers [expr {
		[NameKnown $w(1)] && [NameKnown $w(2)]
		&& [NameKnown $b(1)] && [NameKnown $b(2)]
		&& $w(1) eq $w(2) && $b(1) eq $b(2)}]
	set sameDate [expr {
		[regexp {^[0-9]{4}\.[0-9]{1,2}\.[0-9]{1,2}$} $d(1)]
		&& $d(1) eq $d(2)}]
	set sameResult [expr {$r(1) ne "" && $r(1) eq $r(2)}]
	set sameMoves [expr {$m(1) ne "" && $m(1) eq $m(2)}]

	if {$samePlayers && $sameDate && $sameResult && $sameMoves} { return same }

	if {($r(1) ne "" && $r(2) ne "" && $r(1) ne $r(2))
		|| [SurnameConflict $w(1) $w(2)]
		|| [SurnameConflict $b(1) $b(2)]} {
		return different
	}
	return ""
}


# The classifier question, in one place so calibration asks exactly
# what production asks.
proc ::ai::duplicate::Question {} {
	return [dict create type choice \
		instructions "Are these two chess records the same game, or two different games?" \
		criteria $::ai::duplicate::Criteria]
}


# The state string handed to the classifier: both records, field by
# field, in a fixed order.
proc ::ai::duplicate::State {pairFacts} {
	set records {}
	foreach game {1 2} {
		set fields {}
		foreach field {white black date result eco moves event} {
			lappend fields "$game:$field=[Field $pairFacts $game $field]"
		}
		lappend records [join $fields { }]
	}
	return [join $records { ; }]
}


# The label when the rule abstained and the classifier does not settle
# the pair either: nothing is merged (today's behaviour). The fallback
# of ::ai::decide (source rules).
proc ::ai::duplicate::Unsure {} {
	return unsure
}


proc ::ai::duplicate::describe {label} {
	variable Names
	return [expr {[dict exists $Names $label] ? [dict get $Names $label] : $label}]
}


# <script> gets {ok 1 label L confidence C source S}:
#   L = same | different   (confidence 1.0, source rules) when the rule
#       settles the pair -- the classifier is never asked;
#   L = same | different   (source classifier) when it answers;
#   L = unsure when the rule abstained and the classifier did not
#       settle the pair (source rules) -- nothing is merged.
# Otherwise {ok 0}.
proc ::ai::duplicate::decide {pairFacts script} {
	set rule [rule $pairFacts]

	if {$rule ne ""} {
		after 0 [list {*}$script [list ok 1 label $rule confidence 1.0 source rules]]
		return
	}

	if {[llength [info commands ::ai::decide]] == 0} {
		after 0 [list {*}$script [list ok 1 label [Unsure] confidence {} source rules]]
		return
	}

	::ai::decide duplicate [State $pairFacts] [Question] $script \
		-fallback [namespace code Unsure]
	return
}

# The seven header facts of one game (its tags), for a pair. The move
# count is the PlyCount tag halved, rounded up; a game without the tag
# leaves it empty, so the rule never calls it 'same' on the moves alone.
proc ::ai::duplicate::factsOfTags {tags} {
	set facts [dict create]
	foreach {field tag} {white White black Black date Date result Result eco ECO event Event} {
		dict set facts $field [expr {[dict exists $tags $tag] ? [dict get $tags $tag] : ""}]
	}
	set moves ""
	if {[dict exists $tags PlyCount] && [string is integer -strict [dict get $tags PlyCount]]} {
		set moves [expr {([dict get $tags PlyCount] + 1) / 2}]
	}
	dict set facts moves $moves
	return $facts
}


# Review one duplicate group: the first game against each other one.
# <numbers> are game numbers of <base>. <script> gets, once, a list of
# {number label source} for the other games. Reads only.
proc ::ai::duplicate::ReadTags {base variant number} {
	set tags {}
	catch { foreach pair [::scidb::db::get tags $number $base $variant] { dict set tags {*}$pair } }
	return $tags
}


proc ::ai::duplicate::reviewGroup {base variant numbers script args} {
	array set opts [list -reader ::ai::duplicate::ReadTags]
	array set opts $args

	set first [lindex $numbers 0]
	set rest [lrange $numbers 1 end]
	if {[llength $rest] == 0} {
		after 0 [list {*}$script {}]
		return
	}
	set tags1 [{*}$opts(-reader) $base $variant $first]

	variable Review
	set key [incr ::ai::duplicate::ReviewSeq]
	set Review($key) [dict create pending [llength $rest] results {} script $script]
	foreach n $rest {
		set tags2 [{*}$opts(-reader) $base $variant $n]
		set pair [dict create 1 [factsOfTags $tags1] 2 [factsOfTags $tags2]]
		decide $pair [namespace code [list ReviewStep $key $n]]
	}
	return
}


proc ::ai::duplicate::ReviewStep {key number decision} {
	variable Review
	if {![info exists Review($key)]} { return }
	set state $Review($key)
	set label [expr {[dict get $decision ok] ? [dict get $decision label] : "unsure"}]
	set source [expr {[dict exists $decision source] ? [dict get $decision source] : "rules"}]
	dict lappend state results [list $number $label $source]
	dict incr state pending -1
	if {[dict get $state pending] > 0} {
		set Review($key) $state
		return
	}
	unset Review($key)
	uplevel #0 [list {*}[dict get $state script] \
		[lsort -integer -index 0 [dict get $state results]]]
	return
}

# vi:set ts=3 sw=3:
