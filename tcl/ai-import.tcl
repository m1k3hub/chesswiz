# ======================================================================
# AI: import doctor (System One)
# ======================================================================
# Turn the importer's error/warning codes into a short diagnosis: what
# most likely went wrong and what to do about it. A deterministic rule
# maps the known PGN codes of scidb's reader to a cause category (plus a
# concrete fix); the bounded classifier is asked only when a code is not
# in the table. Read-only.
#
# Firewall: this only explains import messages; it never touches the board.
# ======================================================================

namespace eval ::ai::import {
	# category -> what it means
	variable Categories [dict create \
		encoding      "the file's character encoding is wrong" \
		not-pgn       "the file does not look like PGN" \
		illegal-moves "some moves could not be played" \
		bad-fen       "a game's start position (FEN) is malformed" \
		missing-tags  "required player or result tags are missing" \
		bad-tags      "some tag values are malformed" \
		truncated     "the file is truncated or malformed" \
		variant       "a game is a chess variant" \
		other         "an unclassified problem"]

	# category -> the concrete fix
	variable Fix [dict create \
		encoding      "pick the source's character encoding in the import dialog" \
		not-pgn       "if it is a Scid, CBH or ChessBase file, open it as a database instead of importing it" \
		illegal-moves "the PGN is corrupt, or the game is a variant; check the moves" \
		bad-fen       "check the FEN and SetUp tags of the affected games" \
		missing-tags  "add the missing tags at the source, or accept empty tags" \
		bad-tags      "clean the affected tag values at the source" \
		truncated     "the file ends in the middle of a game; re-download or re-export it" \
		variant       "open the games with the right variant selected" \
		other         "review the messages above"]

	# scidb importer code -> category
	variable Rules [dict create \
		EncodingFailed encoding \
		SeemsNotToBePgnText not-pgn \
		InvalidMove illegal-moves \
		IllegalMove illegal-moves \
		IllegalCastling illegal-moves \
		CastlingCorrection illegal-moves \
		UnexpectedCastling variant \
		VariantChangedToGiveaway variant \
		VariantChangedToSuicide variant \
		NotSuicideNotGiveaway variant \
		InvalidFen bad-fen \
		MissingFen bad-fen \
		FixedInvalidFen bad-fen \
		MissingWhitePlayerTag missing-tags \
		MissingBlackPlayerTag missing-tags \
		MissingPlayerTags missing-tags \
		MissingResult missing-tags \
		MissingResultTag missing-tags \
		InvalidResultTag bad-tags \
		InvalidRoundTag bad-tags \
		InvalidDateTag bad-tags \
		InvalidEventDateTag bad-tags \
		InvalidTimeModeTag bad-tags \
		InvalidEcoTag bad-tags \
		InvalidTagName bad-tags \
		InvalidCountryCode bad-tags \
		InvalidRating bad-tags \
		RatingTooHigh bad-tags \
		InvalidNag bad-tags \
		UnexpectedTag bad-tags \
		UnexpectedResultToken bad-tags \
		ResultDidNotMatchHeaderResult bad-tags \
		ResultCorrection bad-tags \
		InvalidToken truncated \
		UnexpectedSymbol truncated \
		UnexpectedEndOfInput truncated \
		UnexpectedEndOfGame truncated \
		ContinuationsNotSupported truncated \
		TagNameExpected truncated \
		TagValueExpected truncated \
		UnterminatedString truncated \
		UnterminatedVariation truncated]
}

proc ::ai::import::Rule {code} {
	variable Rules
	return [expr {[dict exists $Rules $code] ? [dict get $Rules $code] : ""}]
}

proc ::ai::import::Unknown {} {
	return other
}


# The distinct codes of a list, in order.
proc ::ai::import::Codes {codes} {
	set seen {}
	foreach code $codes {
		if {$code ne "" && $code ni $seen} { lappend seen $code }
	}
	return $seen
}


# The rule-only diagnosis, as text. Codes the table does not know count as
# "other" (the classifier is only used by ::ai::import::diagnose).
proc ::ai::import::Text {codes} {
	variable Categories
	variable Fix

	set counts {}
	foreach code [Codes $codes] {
		set cat [Rule $code]
		if {$cat eq ""} { set cat other }
		dict incr counts $cat
	}
	if {![dict size $counts]} { return "" }

	set lines {}
	foreach cat {not-pgn encoding truncated bad-fen illegal-moves missing-tags bad-tags variant other} {
		if {[dict exists $counts $cat]} {
			set n [dict get $counts $cat]
			lappend lines "  [dict get $Categories $cat] ($n message(s)): [dict get $Fix $cat]"
		}
	}
	return "Import doctor:\n[join $lines \n]"
}


# <script> gets {ok 1 label CATEGORY confidence C source S} or {ok 0}. The
# rule decides when every code is known; otherwise the classifier picks the
# most likely category, falling back to "other".
proc ::ai::import::diagnose {codes script} {
	set known 1
	foreach code [Codes $codes] {
		if {[Rule $code] eq ""} { set known 0 ; break }
	}

	if {$known} {
		after 0 [list {*}$script [list ok 1 label {} confidence 1.0 source rules]]
		return
	}

	set question [dict create type choice \
		instructions "Scidb, a chess database, reported these import messages. What is the most likely cause?" \
		criteria $::ai::import::Categories]

	::ai::decide import_diagnosis [join [Codes $codes] " "] $question $script \
		-fallback [namespace code Unknown]
	return
}

# vi:set ts=3 sw=3:
