# ======================================================================
# AI: comment kind (System One)
# ======================================================================
# What a comment is *about*: opening theory, a tactic, an endgame, a plan,
# a bare evaluation, or a warning. A deterministic keyword rule answers the
# obvious cases; the bounded classifier is asked for the rest. Read-only:
# it never changes the comment.
#
# Firewall: this only labels what a comment talks about; it never speaks
# about the position itself.
# ======================================================================

namespace eval ::ai::comment {
	variable Kinds {opening tactics endgame plan evaluation warning other}

	variable Names [dict create \
		opening    "opening theory" \
		tactics    "a tactic" \
		endgame    "the endgame" \
		plan       "a plan" \
		evaluation "an evaluation" \
		warning    "a warning or a critical moment" \
		other      "something else"]

	variable Criteria [dict create \
		opening    "opening development, book theory or a named line" \
		tactics    "a tactic: a fork, pin, skewer, sacrifice, mate or trap" \
		endgame    "an endgame: technique, promotion, zugzwang or tablebases" \
		plan       "a plan, an idea, a target or a positional manoeuvre" \
		evaluation "an assessment of the position, not a move or idea" \
		warning    "a warning, a blunder, a mistake or a forced move" \
		other      "none of these"]
}

proc ::ai::comment::Name {kind} {
	variable Names
	return [expr {[dict exists $Names $kind] ? [dict get $Names $kind] : $kind}]
}

# The deterministic keyword hint, or "" when the words do not say.
proc ::ai::comment::Rule {text} {
	set t [string tolower $text]

	foreach entry {
		{warning    {\y(blunder\w*|mistake\w*|only move|forced|careful\w*|must|trap\w*|lose\w*|hang\w*)\y}}
		{tactics    {\y(fork\w*|pin\w*|skewer\w*|sacrifice\w*|combo\w*|tactic\w*|mate|check\w*|discovered|deflect\w*|decoy\w*|x-ray)\y}}
		{endgame    {\y(endgame\w*|king and pawn|pawn ending\w*|zugzwang|promotion\w*|passed pawn\w*|rook ending\w*|bishop ending\w*|opposite-colou?red|fortress\w*|tablebase\w*)\y}}
		{opening    {\y(opening\w*|develop\w*|castl\w*|gambit\w*|theor\w*|book move|novelt\w*|fianchetto\w*|sicilian|najdorf|centre|center)\y}}
		{evaluation {\y(winning|better|worse|equal|advantage\w*|compensation|unclear|\+[-=]|[-=]\+|\+\-|-\+)\y}}
		{plan       {\y(plan\w*|idea\w*|aim\w*|threat\w*|pressure\w*|target\w*|initiative|manoeuvre\w*|maneuver\w*|attack\w*)\y}}
	} {
		lassign $entry kind pattern
		if {[regexp $pattern $t]} { return $kind }
	}
	return ""
}


proc ::ai::comment::Other {} {
	return other
}


# <script> gets {ok 1 label KIND confidence C source S}.
proc ::ai::comment::kind {text script} {
	set rule [Rule $text]

	if {$rule ne ""} {
		after 0 [list {*}$script [list ok 1 label $rule confidence 1.0 source rules]]
		return
	}

	set question [dict create type choice \
		instructions "What is this chess annotation comment about?" \
		criteria $::ai::comment::Criteria]

	::ai::decide comment_kind $text $question $script -fallback [namespace code Other]
	return
}

# vi:set ts=3 sw=3:
