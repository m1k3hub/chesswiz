# ======================================================================
# AI: comment language tagging (System One)
# ======================================================================
# The language of a comment: a deterministic rule for the scripts a Latin
# heuristic cannot see (Cyrillic, Greek, Hebrew, Arabic, CJK), and the
# bounded classifier for the rest. The answer set is a fixed list of
# languages plus xx (notation/symbols only, language independent) and yy
# (a language we do not offer). Read-only; with no classifier the rule
# alone answers and everything else stays undecided.
#
# Firewall: this only labels a comment's language; it never writes a
# comment and never speaks about the board.
# ======================================================================

namespace eval ::ai::language {
	# code -> English name
	variable Names [dict create \
		en English  de German   fr French  es Spanish  it Italian \
		pt Portuguese nl Dutch  ru Russian pl Polish   cs Czech \
		uk Ukrainian  tr Turkish el Greek  ar Arabic   he Hebrew \
		zh Chinese  ja Japanese  ko Korean \
		xx "language independent"  yy "another language"]

	# the classifier's answer set (code -> description)
	variable Criteria [dict create \
		en "English"  de "German"  fr "French"  es "Spanish"  it "Italian" \
		pt "Portuguese"  nl "Dutch"  ru "Russian"  pl "Polish"  cs "Czech" \
		uk "Ukrainian"  tr "Turkish"  el "Greek"  ar "Arabic"  he "Hebrew" \
		zh "Chinese"  ja "Japanese"  ko "Korean" \
		xx "language independent (chess notation and symbols only)" \
		yy "another language"]
}

proc ::ai::language::Name {code} {
	variable Names
	return [expr {[dict exists $Names $code] ? [dict get $Names $code] : $code}]
}

# The script a text is written in, or "" when the script does not identify
# one language (Cyrillic and Han are shared, and Latin is not a signal).
proc ::ai::language::Rule {text} {
	set t [string trim $text]

	if {[string length $t] < 2} { return xx }
	if {![regexp {[[:alpha:]]} $t]} { return xx }

	if {[regexp {[\u0370-\u03FF\u1F00-\u1FFF]} $t]} { return el }
	if {[regexp {[\u0590-\u05FF]} $t]}              { return he }
	if {[regexp {[\u0600-\u06FF\u0750-\u077F]} $t]} { return ar }
	if {[regexp {[\uAC00-\uD7AF\u1100-\u11FF]} $t]} { return ko }
	if {[regexp {[\u3040-\u30FF]} $t]}              { return ja }

	# Cyrillic (ru/uk) and Han (zh/ja) are ambiguous: the classifier decides
	return ""
}


# <script> gets {ok 1 label L confidence C source S} or {ok 0}.
proc ::ai::language::detect {text script} {
	set rule [Rule $text]

	if {$rule ne ""} {
		after 0 [list {*}$script [list ok 1 label $rule confidence 1.0 source rules]]
		return
	}

	set question [dict create type choice \
		instructions "In which language is this chess annotation written?" \
		criteria $::ai::language::Criteria]

	::ai::decide language $text $question $script -fallback [namespace code Unknown]
	return
}


proc ::ai::language::Unknown {} {
	return yy
}

# vi:set ts=3 sw=3:
