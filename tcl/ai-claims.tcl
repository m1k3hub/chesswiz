# ======================================================================
# ::ai::claims -- verify generated chess prose against the grounded facts.
#
# The language layer is allowed to *describe* facts; this module checks that
# it did not invent any.  Every structural phrase is mapped to a named claim
# answered by ::scidb::ai::claimFor (deterministic C++), and every move-like
# token is checked for legality with ::scidb::ai::moveFacts.
#
#   ::ai::claims::check <fen> <text>   -> list of ungrounded claims ("" if clean)
#
# This is deliberately conservative: it flags a claim only when the facts
# positively contradict it, so a clean result is meaningful.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-claims
}

package require Tcl 8.5

namespace eval ai {
namespace eval claims {

# label, regexp, named claim
variable Terms {
	{isolatedPawn       {\misolated (?:queen'?s )?pawns?\M}        isolatedPawn}
	{iqp                {\misolated queen'?s? pawns?\M}            iqp}
	{doubledPawns       {\mdoubled pawns?\M}                       doubledPawns}
	{backwardPawn       {\mbackward pawns?\M}                      backwardPawn}
	{passedPawn         {\mpassed pawns?\M}                        passedPawn}
	{hangingPawns       {\mhanging pawns?\M}                       hangingPawns}
	{bishopPair         {\mbishop pairs?\M}                        bishopPair}
	{oppositeBishops    {\mopposite[- ]colou?red bishops?\M}       oppositeBishops}
	{openFile           {\mopen files?\M}                          openFile}
	{semiOpenFile       {\msemi[- ]open files?\M}                  semiOpenFile}
	{outpost            {\moutposts?\M}                            outpost}
	{castled            {\mcastl(?:ed|ing)\M}                      castled}
	{backRankWeakness   {\mback[- ]ranks?(?:\s+weak(?:ness(?:es)?)?)?\M}   backRank}
	{fork               {\mfork(?:s|ed|ing)?\M}                    fork}
	{pin                {\mpinn?(?:ed|ing|s)?\M}                   pin}
	{skewer             {\mskewers?(?:ed|ing)?\M}                  skewer}
	{enPrise            {\men prise\M}                             enPrise}
	{hangingPiece       {\m(?:piece|knight|bishop|rook|queen|pawn) (?:is )?hanging\M} enPrise}
}

# A move-like token: a piece move, a capture, castling, or a promotion.
variable MovePattern {\m(?:[KQRBN][a-h]?[1-8]?x?[a-h][1-8](?:=[QRBN])?[+#]?|O-O(?:-O)?|[a-h]x[a-h][1-8](?:=[QRBN])?[+#]?|[a-h][1-8]=[QRBN][+#]?)\M}

} ;# namespace claims
} ;# namespace ai


# ----------------------------------------------------------------------
# The side named within a short window before the match, or "" if none.
# ----------------------------------------------------------------------
proc ai::claims::sideBefore {text start} {
	set from [expr {$start - 48}]
	if {$from < 0} { set from 0 }
	set window [string range $text $from [expr {$start - 1}]]

	set last {}
	foreach {whole color} [regexp -all -inline -nocase {\m(white|black)\M} $window] {
		set last [string tolower $color]
	}
	return $last
}


proc ai::claims::pieceLetterOf {name} {
	switch -nocase -- $name {
		k - king   { return K }
		q - queen  { return Q }
		r - rook   { return R }
		b - bishop { return B }
		n - knight { return N }
		p - pawn   { return P }
	}
	return {}
}


# Square -> piece-letter map, from the FEN placement field.
proc ai::claims::pieceMap {fen} {	set map [dict create]
	set rank 8

	foreach row [split [lindex [split $fen] 0] /] {
		set file 0

		foreach ch [split $row ""] {
			if {[string is digit -strict $ch]} {
				incr file $ch
			} else {
				dict set map "[string index abcdefgh $file]$rank" $ch
				incr file
			}
		}
		incr rank -1
	}
	return $map
}


# Negation that follows the term: "Opposite-coloured bishops: false",
# "Opposite-coloured bishops is/are false".
proc ai::claims::postNegated {text end} {
	set window [string tolower [string range $text [expr {$end + 1}] [expr {$end + 18}]]]
	return [regexp {^\s*[:=]?\s*(?:(?:is|are|was|were|seems?|remains?)\s+)?(false|no|none|0)\M(?!\.?\d)} $window]
}


# Describe a piece-placement mismatch, or "" when it is correct.
proc ai::claims::placementProblem {map name sq {side {}}} {
	set want [pieceLetterOf $name]
	set have [expr {[dict exists $map $sq] ? [dict get $map $sq] : ""}]
	if {$side eq "black"} { set want [string tolower $want] }
	if {$side eq {}} { set have [string toupper $have] }
	if {$have ne $want} {
		return "ungrounded $name placement: $sq is [expr {[string length $have] ? $have : {empty}}], not $want"
	}
	return {}
}


# True when a negator ("no", "not", ...) precedes the match.
proc ai::claims::negated {text start} {
	set from [expr {$start - 28}]
	if {$from < 0} { set from 0 }
	set window [string tolower [string range $text $from [expr {$start - 1}]]]

	# immediate negator: "no isolated pawns", "0 open files",
	# "no white pinned pieces", "Neither king is castled" (short words may sit
	# between the negator and the term)
	if {[regexp {(?:^|[^a-z0-9])(no|not|without|none|neither|0|zero|false|n't)(?:\s+(?:white|black|king|kings|side|player|is|are|was|were|has|have|the|a|an|any))*\s*$} $window]} {
		return 1
	}

	# list negation: "no pins, forks, skewers, or back-rank weakness" -- the
	# term is preceded by a list separator and the negator governs the list.
	# "and" is deliberately NOT a separator: it usually joins an independent
	# clause ("the king is not castled, and opposite-coloured bishops exist"),
	# and treating it as a list would suppress a genuine claim. A finite verb
	# between the negator and the term also disqualifies the list reading.
	if {[regexp {(?:,|\mor|\mnor)\s*$} $window]} {
		set from2 [expr {$start - 120}]
		if {$from2 < 0} { set from2 0 }
		set clause [string tolower [string range $text $from2 [expr {$start - 1}]]]
		set clause [lindex [split $clause {.;:!?}] end]
		if {[regexp -indices {\m(?:no|not|without|none|neither|0|zero)\M} $clause mrange]} {
			lassign $mrange ns ne
			set tail [string range $clause [expr {$ne + 1}] end]
			if {![regexp {\m(?:is|are|was|were|be|been|being|exist|exists|has|have|had|can|could|do|does|did|will|would|shall|should|may|might|must)\M} $tail]} {
				return 1
			}
		}
	}

	return 0
}


# True when the match sits in a hypothetical or general statement rather than an
# assertion about this position ("with a pawn on c6 instead of c7", "opposite-
# coloured bishops tend to be strong"). Such text must not be verified.
proc ai::claims::hypothetical {text start end} {
	set from [expr {$start - 40}]
	if {$from < 0} { set from 0 }
	set pre [string tolower [string range $text $from [expr {$start - 1}]]]
	if {[regexp {\m(instead of|if|would|could|might|may|tend to|tends to|generally|usually|typically|rather than|otherwise|in such positions)\M} $pre]} {
		return 1
	}
	# the marker can also follow the term: "a pawn on c6 instead of c7",
	# "opposite-coloured bishops tend to be strong"
	set post [string tolower [string range $text [expr {$end + 1}] [expr {$end + 40}]]]
	if {[regexp {^\s*[:=]?\s*(?:(?:is|are|was|were)\s+)?(instead of|rather than|tend(?:s)? to|generally|usually|typically|in general|as a rule)\M} $post]} {
		return 1
	}
	return 0
}


# Prose names moves for either side ("Black threatens ...Qxh2" with White to
# move).  The move must be legal for the side the text attributes it to -- a
# "..." prefix or a nearby "White"/"Black" -- or, when none is named, for
# either side.
# A move token without the check/mate and annotation suffixes, for comparison
# with the engine's line.
proc ai::claims::bareMove {move} {
	return [string trim [string map {+ "" "#" "" "!" "" "?" ""} $move]]
}


# A move named in the engine's principal variation is grounded even when it is
# not legal in the current position (it belongs to a later ply of the line).
proc ai::claims::inLine {move line} {
	set m [bareMove $move]
	foreach lm $line {
		if {$m eq [bareMove $lm]} { return 1 }
	}
	return 0
}


proc ai::claims::legalMove {fen move side {line ""}} {
	if {[llength $line] && [inLine $move $line]} { return 1 }

	set fields [split [string trim $fen]]
	if {[llength $fields] < 2} { return 0 }
	set stm [expr {[lindex $fields 1] eq "b" ? "black" : "white"}]

	if {$side eq "" || $side eq $stm} {
		if {![catch {::scidb::ai::moveFacts $move $fen}]} { return 1 }
		if {$side ne ""} { return 0 }
	}

	# pass the turn to the opponent (en passant belongs to the mover)
	lset fields 1 [expr {$stm eq "white" ? "b" : "w"}]
	if {[llength $fields] >= 4} { lset fields 3 - }
	return [expr {![catch {::scidb::ai::moveFacts $move [join $fields]}]}]
}


# ----------------------------------------------------------------------
# ::ai::claims::check <fen> <text> -> list of ungrounded claims
# ----------------------------------------------------------------------
proc ai::claims::check {fen text {line ""}} {
	variable Terms
	variable MovePattern

	set problems {}

	# -- structural vocabulary ------------------------------------------
	foreach entry $Terms {
		lassign $entry label pattern term

		foreach match [regexp -all -inline -indices -nocase $pattern $text] {
			lassign $match start end

			# skip compound matches such as "semi-open" for the "open file" term
			if {$start > 0 && [string match {[A-Za-z-]} [string index $text [expr {$start - 1}]]]} {
				continue
			}

			set side [sideBefore $text $start]

			set ok 0
			if {[catch {
				set prefix [string range $text [expr {max(0, $start - 48)}] [expr {$start - 1}]]
				if {[regexp -nocase {\mboth\s+(?:sides|players)\M[^.!?;]*$} $prefix]} {
					set side both
					set ok [expr {[::scidb::ai::claimFor $fen $term white] && [::scidb::ai::claimFor $fen $term black]}]
				} elseif {$side eq {}} {
					set ok [::scidb::ai::claimFor $fen $term]
				} else {
					set ok [::scidb::ai::claimFor $fen $term $side]
				}
			}]} {
				# unknown term is a programmer error, not a text problem
				continue
			}

			# A phrase like "0 rooks on open files" locates pieces on a feature;
			# it does not claim the feature exists, so it is not a claim to check.
			set preFrom [expr {$start - 24}]
			if {$preFrom < 0} { set preFrom 0 }
			set pre [string tolower [string range $text $preFrom [expr {$start - 1}]]]

			if {[regexp {(?:rooks?|knights?|bishops?|queens?|pieces?|kings?|pawns?)\s+on\s+$} $pre]} {
				continue
			}

			# Hypothetical/general statements are not claims about this position.
			if {[hypothetical $text $start $end]} {
				continue
			}

			set neg [expr {[negated $text $start] || [postNegated $text $end]}]

			# flag when the polarity of the claim is contradicted by the facts
			if {[expr {$neg == $ok}]} {
				set phrase [string range $text $start $end]
				set kind [expr {$neg ? "negated " : ""}]

				if {$side eq {}} {
					lappend problems "ungrounded ${kind}${label}: \"$phrase\""
				} else {
					lappend problems "ungrounded ${kind}${label} for $side: \"$phrase\""
				}
			}
		}
	}

	# -- move legality ---------------------------------------------------
	foreach m [regexp -all -inline -indices -nocase $MovePattern $text] {
		lassign $m ws we

		if {[hypothetical $text $ws $we]} {
			continue
		}

		set move [string range $text $ws $we]
		if {[string range $text [expr {$ws - 3}] [expr {$ws - 1}]] eq "..."} {
			set side black
		} else {
			set side [sideBefore $text $ws]
		}
		if {![legalMove $fen $move $side $line]} {
			lappend problems "illegal move: \"$move\""
		}
	}

	# -- piece placement --------------------------------------------------
	set map [pieceMap $fen]

	# "<piece> on <square>"
	foreach {w n s} [regexp -all -inline -indices -nocase \
		{\m(king|queen|rook|bishop|knight|pawn)s?\s+(?:is\s+|are\s+)?(?:on|at)\s+([a-h][1-8])} $text] {
		if {[hypothetical $text [lindex $w 0] [lindex $w 1]]} {
			continue
		}

		set p [placementProblem $map \
			[string range $text [lindex $n 0] [lindex $n 1]] \
			[string range $text [lindex $s 0] [lindex $s 1]] [sideBefore $text [lindex $w 0]]]
		if {$p ne {}} { lappend problems $p }
	}

	# "<piece>s (<sq>, <sq>, ...)"
	foreach {whole name list} [regexp -all -inline -indices -nocase \
		{\m(king|queen|rook|bishop|knight|pawn)s?\s*\(([^)]*)\)} $text] {
		set side [sideBefore $text [lindex $whole 0]]
		set name [string range $text {*}$name]
		foreach sq [regexp -all -inline {[a-h][1-8]} [string range $text {*}$list]] {
			set p [placementProblem $map $name $sq $side]
			if {$p ne {}} { lappend problems $p }
		}
	}

	return $problems
}


# ----------------------------------------------------------------------
# Convenience: raise if the text makes any ungrounded claim.
# ----------------------------------------------------------------------
proc ai::claims::verify {fen text} {
	set problems [check $fen $text]
	if {[llength $problems]} {
		error "ungrounded chess claims: [join $problems {; }]"
	}
	return
}
