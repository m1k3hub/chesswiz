# ======================================================================
# AI: move novelty (System One, grounded in the precedent index)
# ======================================================================
# Is a move a novelty, or something masters already play? The
# master-practice precedent index (scripts/corpus_precedent.py over a PGN
# corpus, read through tcl/ai-precedent.tcl) is the ground: a position the
# index knows is never a novelty, whatever the classifier thinks of the
# move. Only a position the index does not know goes to the bounded
# classifier (::ai::decide, type choice over {novelty side_line
# transposition }); when the classifier does not settle the move,
# the label is 'unknown' -- never a guess.
#
#   ::ai::novelty::known <fen>              -> 1 with precedent, else 0
#   ::ai::novelty::label <fen> <san> <script>
#   ::ai::novelty::describe <label>         -> a human phrase
#
# Firewall: this only labels a move against master practice; it never
# evaluates the position, never plays a move and never writes a comment.
# Nothing blocks: the rules answer through after 0, the rest through the
# classifier's asynchronous callback.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-novelty
}

package require Tcl 8.5

namespace eval ::ai::novelty {

	# the classifier's answer set (choice criteria name -> description)
	variable Criteria [dict create \
		novelty       "not a line the masters play: new to the master-practice index" \
		side_line     "a side line of known opening theory" \
		transposition "a transposition of a position the masters reach by another move order" \
		]

	# label -> English phrase (known and unknown come from the rules)
	variable Names [dict create \
		known         "played by the masters (in the precedent index)" \
		novelty       "a novelty: not a line the masters play" \
		side_line     "a side line of known opening theory" \
		transposition "a transposition of well-known practice" \
		unknown       "undecided (the classifier did not settle the move)"]
}


# 1 when ::ai::precedent::lookup finds the position in the master-practice
# index, else 0 -- a missing index, a failed query or no precedent moves
# are all "not in the index".
proc ::ai::novelty::known {fen} {
	if {[llength [info commands ::ai::precedent::lookup]] == 0} { return 0 }
	if {[catch { set found [::ai::precedent::lookup $fen -limit 1] }]} { return 0 }
	return [expr {[llength $found] > 0 ? 1 : 0}]
}


# The state string handed to the classifier: the position, the move and
# whether the precedent index knows the position.
proc ::ai::novelty::State {fen san known} {
	return "fen=$fen move=$san known=$known"
}


# The label when the index does not know the position and the classifier
# does not settle the move either: the fallback of ::ai::decide
# (source rules).
proc ::ai::novelty::Unknown {} {
	return unknown
}


# <script> gets {ok 1 label L confidence C source S}:
#   L = known   for a position in the index (confidence 1.0, source rules);
#   L = novelty side_line transposition   (source classifier);
#   L = unknown when the classifier did not settle the move (source rules).
# Otherwise {ok 0}.
proc ::ai::novelty::label {fen san script} {
	set known [known $fen]

	if {$known} {
		after 0 [list {*}$script [list ok 1 label known confidence 1.0 source rules]]
		return
	}

	set question [dict create type choice \
		instructions "In this position, is the move a novelty, a side line or a transposition?" \
		criteria $::ai::novelty::Criteria]

	if {[llength [info commands ::ai::decide]] == 0} {
		after 0 [list {*}$script [list ok 1 label [Unknown] confidence {} source rules]]
		return
	}

	::ai::decide novelty [State $fen $san $known] $question $script \
		-fallback [namespace code Unknown]
	return
}


proc ::ai::novelty::describe {label} {
	variable Names
	return [expr {[dict exists $Names $label] ? [dict get $Names $label] : $label}]
}


# vi:set ts=3 sw=3:
