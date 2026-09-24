# ======================================================================
# test_ai_claims.tcl -- the claim checker against grounded facts.
#
#   xvfb-run -a ./src/tkscidb-beta tests/test_ai_claims.tcl
# ======================================================================

set failures 0

proc check {name cond} {
	global failures
	if {$cond} {
		puts "PASS: $name"
	} else {
		puts "FAIL: $name"
		incr failures
	}
}

set root [file join [file dirname [file normalize [info script]]] ..]
source [file join $root tcl ai-claims.tcl]

# App-backed: needs the tkscidb shell. Skip cleanly if sourced elsewhere.
if {[llength [info commands ::scidb::ai::claimFor]] == 0} {
	puts "SKIP: requires the tkscidb shell (::scidb::ai::* unavailable)"
	puts "AI-CLAIMS-FAILURES: 0"
	exit 0
}

proc clean {fen text} {
	return [expr {[llength [::ai::claims::check $fen $text]] == 0}]
}

proc flagged {fen text} {
	return [expr {[llength [::ai::claims::check $fen $text]] > 0}]
}

set start    "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
set iqp      "r1bq1rk1/pp2bppp/2n1pn2/2pp4/3P4/5NP1/PP3PBP/RNBQ1RK1 w - - 0 1"
set skewer   "7r/6k1/8/8/8/8/1B6/6K1 w - - 0 1"
set fork     "4k3/3r4/2n5/4N3/8/8/8/4K3 w - - 0 1"
set backrank "6k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1"
set oneBish  "4k3/8/8/8/8/8/8/4KB2 w - - 0 1"

# --- structural grounding --------------------------------------------
check "grounded: isolated queen's pawn"  [clean $iqp "White has an isolated queen's pawn."]
check "grounded: bishop pair at start"   [clean $start "Both sides have the bishop pair."]
check "grounded: skewer"                 [clean $skewer "The bishop skewers the king."]
check "grounded: fork"                   [clean $fork "The knight forks the rook and the knight."]
check "grounded: back-rank weakness"     [clean $backrank "Black has a back-rank weakness."]

# --- hallucinations ---------------------------------------------------
check "flagged: no isolated pawn"        [flagged $start "White has an isolated pawn."]
check "flagged: wrong side for IQP"      [flagged $iqp "Black has an isolated queen's pawn."]
check "flagged: no bishop pair"          [flagged $oneBish "White has the bishop pair."]
check "flagged: no fork"                 [flagged $start "White has a fork on e5."]

# --- piece placement --------------------------------------------------
check "flagged: invented pawn squares" \
	[flagged $iqp "White has 2 isolated pawns (g4, c3)."]
check "flagged: invented knight square" \
	[flagged $iqp "The knight on g5 controls the centre."]
check "clean: correct pawn placement" \
	[clean $iqp "A pawn on g3 supports the knight."]
check "clean: correct knight placement" \
	[clean $iqp "The black knight is on f6."]

# --- negation and plurals ---------------------------------------------
check "clean: true negation" [clean $start "There are no doubled pawns."]
check "flagged: false negation" [flagged $iqp "There are no isolated pawns."]
check "clean: plural term matched" [clean $iqp "White has an isolated pawn."]

# --- move legality ----------------------------------------------------
check "clean: legal moves"               [clean $start "White can choose Nf3 or Nc3."]
check "flagged: illegal move"            [flagged $start "White plays Nf6."]
check "flagged: illegal rook move"       [flagged $start "The rook goes Re8."]
check "clean: legal capture"             [clean "r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4" "Qxf7 is the point."]

# --- negation must not leak across clauses (false negatives) ----------
# These sentences ASSERT a claim that is false in the start position, so they
# must be flagged: a "no/not" in an earlier clause must not suppress them.
check "flagged: and-joined clause does not leak" \
	[flagged $start "There are no hanging pieces, and opposite-coloured bishops exist."]
check "flagged: not in earlier clause does not leak" \
	[flagged $start "The king is not castled, and opposite-coloured bishops exist."]
check "flagged: sentence boundary blocks leak" \
	[flagged $start "No pieces are hanging. Opposite-coloured bishops exist."]
# ...but genuine negations of a list must stay clean
check "clean: or-list negation" \
	[clean $start "There are no forks, en prise pieces, or skewers for either side."]
check "clean: repeated no-list negation" \
	[clean $start "There are no open files, no semi-open files, and no passed pawns."]
check "clean: negator with intervening words" \
	[clean $start "Neither side has a back-rank weakness."]

# --- post-term negation: "X are false" --------------------------------
check "clean: copula post-negation"   [clean $start "Opposite-coloured bishops are false."]
check "flagged: copula post-affirm"   [flagged $start "Opposite-coloured bishops are true."]

# --- hypothetical / general statements are not claims about the position ---
check "clean: general principle (tend to)" \
	[clean $start "Opposite-coloured bishops tend to be a strong factor in endgames."]
check "clean: general principle (are generally)" \
	[clean $start "Opposite-coloured bishops are generally strong in endgames."]
check "clean: general principle (usually)" \
	[clean $start "Opposite-coloured bishops usually favour the attacker."]
check "clean: counterfactual (instead of)" \
	[clean $start "With a pawn on c6 instead of c7, Black could have prevented Rd1-d8+."]
check "flagged: general principle still flags the real claim" \
	[flagged $start "Opposite-coloured bishops exist."]

puts "AI-CLAIMS-FAILURES: $failures"
exit $failures
