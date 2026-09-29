# ======================================================================
# AI: cloud egress gate (System One)
# ======================================================================
# What would leave this machine inside an outgoing prompt? A prompt that
# carries a game -- a PGN movetext block with tags such as
# [White "Kasparov, Garry"], or a comment / clock run ({The only move},
# [%clk 0:05:00]) -- is private. So is a position pinned to a person (a
# FEN plus a player name). A prompt that carries only a position and the
# facts derived from it (a FEN, the position fact sheet) is public.
#
# The deterministic rule answers those two cases; everything else is
# asked of the bounded classifier (::ai::decide, type choice over the
# closed set {private public}). When the classifier does not settle the
# prompt either, the answer is 'send': that is today's behaviour, and a
# gate that is unsure must not cost the user their request. A hold is
# only ever decided on data the prompt actually names.
#
#   ::ai::egress::rule <prompt>    -> private | public | ""
#   ::ai::egress::Question         -> the classifier question
#   ::ai::egress::decide <prompt> <script>
#                                   -> label send | hold
#
# <script> gets {ok 1 label send|hold confidence C source S}:
#   rule private       -> hold (confidence 1.0, source rules)
#   rule public        -> send (confidence 1.0, source rules)
#   classifier private -> hold (source classifier)
#   classifier public  -> send (source classifier)
#   nothing decides    -> send (source rules) -- today's behaviour
# Otherwise {ok 0}.
#
# Firewall: this only labels a prompt. It never blocks a send itself,
# never edits or redacts the prompt, and never talks to a provider --
# holding a prompt is the caller's decision.
# ======================================================================

package require Tcl 8.5

namespace eval ::ai::egress {

	# the classifier's answer set (choice criteria name -> description)
	variable Criteria [dict create \
		private "the prompt carries private data: a game's movetext or its header (player names), a comment or a clock run" \
		public  "the prompt carries only a position and the facts derived from it: a FEN and/or a position fact sheet" \
		]

	# label -> English phrase (private/public from the classifier and the
	# rule, send/hold from decide; an unknown label echoes itself)
	variable Names [dict create \
		private "private: the prompt carries games, comments or players" \
		public  "public: the prompt carries only a position and its facts" \
		send    "send: the prompt may leave this machine" \
		hold    "hold: the prompt may carry private games or comments" \
		]

	# A PGN tag pair names a game: players, event, site, date, result.
	# (No leading \y: a tag opens on a bracket, and a boundary needs a
	# word character on one side.)
	variable Tags {(?:^|\s)\[(?:white|black|event|site|round|date|result|eco|annotator|gameid)\y\s+"}

	# A time or evaluation annotation run.
	variable Annotations {(?:^|\s)\[%(?:clk|eval|emt|calt)\y}

	# One comment run: braced, and not a JSON object (those quote their
	# keys, so their runs stop at the first quote). Matches {The only
	# move}, never {"material":{...}}. Written with \x7b/\x7d so the
	# pattern holds no unbalanced brace of its own; the repetition count
	# stays under the engine's limit (a 300 would not compile).
	variable Comments {\x7b[^\x7d"]{2,255}\x7d}

	# One numbered move: 12. Nf3, 3...exd5, 4. O-O. The move must look
	# like SAN, so a numbered instruction ("1. Read the rules") is not
	# mistaken for movetext.
	variable Moves {(?:^|\s)\d{1,3}\.+\s*(?:O-O(?:-O)?|[KQRBN][a-h]?[1-8]?x?[a-h][1-8]|[a-h]x?[a-h]?[1-8](?:=[QRBN])?)[+#]?(?:\s|$)}

	# A FEN: eight rank fields, whatever the piece letters are.
	variable Fen {(?:[rnbqkpRNBQKP1-8]{1,8}/){7}[rnbqkpRNBQKP1-8]{1,8}}

	# A position fact sheet: the FACTS block or one line of the anatomy
	# ::scidb::ai::text prints.
	variable Facts {\y(?:FACTS|material|pawns|pieces|king)\y[ \t]+(?:JSON|white|black)\y}

	# A player name as the databases spell it: Surname, Given.
	variable Player {\y[A-Z][A-Za-z'.-]+,\s*[A-Z][A-Za-z'.-]*}
}


# 1 when the text names a game through a PGN tag pair.
proc ::ai::egress::HasTags {text} {
	variable Tags
	return [regexp -nocase -- $Tags $text]
}


# 1 when the text carries a [%clk ...] or [%eval ...] run.
proc ::ai::egress::HasAnnotation {text} {
	variable Annotations
	return [regexp -nocase -- $Annotations $text]
}


# 1 when the text carries a braced comment that is not a JSON object.
proc ::ai::egress::HasComment {text} {
	variable Comments
	return [regexp -- $Comments $text]
}


# 1 when the text carries at least one numbered move.
proc ::ai::egress::HasMoves {text} {
	variable Moves
	return [regexp -- $Moves $text]
}


# 1 when the text carries a FEN.
proc ::ai::egress::HasFen {text} {
	variable Fen
	return [regexp -- $Fen $text]
}


# 1 when the text carries a position fact sheet.
proc ::ai::egress::HasFacts {text} {
	variable Facts
	return [regexp -- $Facts $text]
}


# 1 when the text carries a player name (Surname, Given).
proc ::ai::egress::HasPlayer {text} {
	variable Player
	return [regexp -- $Player $text]
}


# The deterministic verdict: private | public | "" (the classifier's).
# Empty or malformed input abstains -- never a guess.
proc ::ai::egress::rule {prompt} {
	if {[catch { set text [string trim $prompt] }]} { return "" }
	if {$text eq ""} { return "" }

	# a game record, a comment on a game or a clock run
	if {[HasTags $text]} { return private }
	if {[HasAnnotation $text]} { return private }
	if {[HasComment $text] && [HasMoves $text]} { return private }

	# a position pinned to a person: a game's moves without its tags
	if {[HasPlayer $text] && [HasFen $text]} { return private }

	# a position and nothing else: the FEN and the facts derived from it
	if {[HasFen $text] || [HasFacts $text]} { return public }

	return ""
}


# The answer when nothing decides the prompt: send, today's behaviour.
# A gate must not cost the user their request on its own uncertainty.
proc ::ai::egress::Send {} {
	return send
}


# The classifier question, in one place so calibration asks exactly what
# production asks.
proc ::ai::egress::Question {} {
	variable Criteria
	return [dict create type choice \
		instructions "Does this outgoing request carry private data -- a game's movetext or header (player names), a comment, an annotation or a clock run -- or only a position and the facts derived from it? Answer private when it names games, comments or players." \
		criteria $Criteria]
}


# <script> gets {ok 1 label send|hold confidence C source rules|classifier}.
# The classifier sees the prompt itself: judging what a prompt carries
# takes the prompt.
proc ::ai::egress::decide {prompt script} {
	set rule [rule $prompt]

	if {$rule ne ""} {
		set label [expr {$rule eq "private" ? [Hold] : [Send]}]
		after 0 [list {*}$script [list ok 1 label $label confidence 1.0 source rules]]
		return
	}

	if {[llength [info commands ::ai::decide]] == 0} {
		after 0 [list {*}$script [list ok 1 label [Send] confidence {} source rules]]
		return
	}

	::ai::decide egress $prompt [Question] \
		[namespace code [list OnClassified $script]] \
		-fallback [namespace code Send]
	return
}


# The classifier answers over the egress classes; the caller's script is
# handed the answer in send/hold. Only a confident 'private' becomes a
# hold: everything else -- 'public' or an unreadable label -- is sent.
proc ::ai::egress::OnClassified {script decision} {
	if {[dict get $decision ok]} {
		dict set decision label \
			[expr {[dict get $decision label] eq "private" ? [Hold] : [Send]}]
	}
	uplevel #0 [list {*}$script $decision]
	return
}


proc ::ai::egress::describe {label} {
	variable Names
	return [expr {[dict exists $Names $label] ? [dict get $Names $label] : $label}]
}


proc ::ai::egress::Hold {} {
	return hold
}


# vi:set ts=3 sw=3:
