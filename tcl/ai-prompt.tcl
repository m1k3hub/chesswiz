# ======================================================================
# ::ai::prompt -- build constrained, fact-grounded prompts.
#
# The grounding rules go in the SYSTEM message; the user message carries the
# fact pack and the task.  Keeping them separate stops small models from
# echoing the rules back as if they were content.  Structural vocabulary is
# gated on the corresponding fact, and engine evaluations are only allowed
# when they are supplied.
#
#   ::ai::prompt::rules                      -> system message
#   ::ai::prompt::position <fen> ?options?   -> user message
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-prompt
}

package require Tcl 8.5

namespace eval ai {
namespace eval prompt {

variable Rules {
	"You may ONLY state facts that appear in the FACTS block."
	"Do not invent moves, evaluations, piece locations, or structural features."
	{Use a term such as "isolated pawn", "bishop pair", "open file", "outpost", "fork", "pin", "skewer", "passed pawn", or "backward pawn" only if the corresponding fact is present in FACTS.}
	"You may not give an engine evaluation unless it appears in the ENGINE block."
	"If a fact you want to state is not present, omit the claim."
}

variable Task "Output ONLY the three sections below. Do not repeat or restate these instructions, and do not add any preamble."

} ;# namespace prompt
} ;# namespace ai


proc ::ai::prompt::rules {} {
	variable Rules

	set text "You are a chess analyst. Follow these rules exactly:\n"
	foreach rule $Rules { append text "- $rule\n" }
	return $text
}


proc ::ai::prompt::engineLine {fen depth} {
	if {[llength [info commands ::ai::engine::evaluate]] == 0} { return "" }

	if {[catch {::ai::engine::evaluate $fen -depth $depth -multipv 2} e]} { return "" }

	set line "eval=[dict get $e kind] [dict get $e value] best=[dict get $e bestMove]"
	if {[dict exists $e gapCp]} { append line " gapCp=[dict get $e gapCp]" }
	return $line
}


proc ::ai::prompt::position {fen args} {
	variable Task

	array set opts [list -audience club -perspective neutral -engine 1 -depth 12]
	array set opts $args

	set facts [::scidb::ai::facts $fen]

	set p "Audience: $opts(-audience) player. Perspective: $opts(-perspective).\n\n"
	append p "FACTS (JSON):\n$facts\n\n"

	if {$opts(-engine)} {
		set engine [engineLine $fen $opts(-depth)]
		if {$engine ne ""} { append p "ENGINE: $engine\n\n" }
	}

	if {[llength [info commands ::ai::precedent::summary]]} {
		set master [::ai::precedent::summary $fen]
		if {$master ne ""} { append p "MASTER PRACTICE: $master\n\n" }
	}

	if {[llength [info commands ::ai::annotations::summary]]} {
		set ann [::ai::annotations::summary $fen]
		if {$ann ne ""} { append p "ANNOTATED EXAMPLES: $ann\n\n" }
	}

	append p "$Task\n\n"
	append p "Sections:\n"
	append p "STRUCTURE: pawn structure, space, and weaknesses.\n"
	append p "PIECES: piece activity, good and bad pieces, king safety.\n"
	append p "PLANS: concrete plans for both sides.\n"
	return $p
}
