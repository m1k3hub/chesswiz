# ======================================================================
# ::ai::similar -- positions like the one on the board (find_similar;
# docs/ASSISTANT_COVERAGE_MAP.md §5).
#
# The application writes this CQL 6.2 script, not a model: from the FEN
# and the aspects, pawn tolerance and colour choice the player picked it
# is a fully determined translation, and everything a search runs the
# player sees and edits as usual (::ai::positions::search runs it the
# way find_positions does).
#
#   ::ai::similar::script <fen> ?-aspects LIST? ?-tolerance N?
#                         ?-colours same|both? ?-tomove 0|1?
#       -> the CQL 6.2 script that finds positions like <fen>.
#       Aspects (default {pawns material}):
#         material  the same number of each piece type per side
#                   (#Q == 1 #q == 0 ... for Q R B N P q r b n p)
#         pawns     every white and every black pawn square; -tolerance
#                   N lets up to N pawns per side stand elsewhere
#         pieces    the kings on the same squares and every Q R B N of
#                   both colours on the same squares, counts equal
#       -colours both wraps the whole condition in flipcolor { ... }, so
#       the same structure with the colours reversed is found too;
#       -tomove 1 adds the FEN's wtm or btm. An invalid FEN or option
#       raises a Tcl error with a plain message.
#   ::ai::similar::describe <fen> ?the same options?
#       -> one plain sentence of what the script matches.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-similar-positions
}

package require Tcl 8.5

namespace eval ai {
namespace eval similar {

# The aspects a script can ask for; see the header.
variable Aspects {material pawns pieces}

} ;# namespace similar
} ;# namespace ai


# The FEN -> a dict of every piece letter's square list plus {tomove w|b}.
# Anything that is not a real position is refused: the script is only as
# good as the board it is derived from.
proc ::ai::similar::parseFen {fen} {
	set fields [split [string trim $fen]]
	if {[llength $fields] < 2} { error "not a FEN: '$fen'" }
	lassign $fields board tomove
	if {$tomove ni {w b}} {
		error "the side to move in a FEN is w or b, not '$tomove': '$fen'"
	}
	array set on {K {} Q {} R {} B {} N {} P {} k {} q {} r {} b {} n {} p {}}
	set ranks [split $board /]
	if {[llength $ranks] != 8} {
		error "a FEN board has 8 ranks, this has [llength $ranks]: '$board'"
	}
	set rank 8
	foreach row $ranks {
		set file 0
		foreach ch [split $row {}] {
			if {[string is digit -strict $ch]} {
				incr file $ch
			} elseif {[info exists on($ch)]} {
				lappend on($ch) [format %c%d [expr {97 + $file}] $rank]
				incr file
			} else {
				error "'$ch' is not a piece or a count of empty squares: '$board'"
			}
			if {$file > 8} { error "rank $rank of the board is too wide: '$board'" }
		}
		if {$file != 8} { error "rank $rank of the board has $file squares, not 8: '$board'" }
		incr rank -1
	}
	if {[llength $on(K)] != 1 || [llength $on(k)] != 1} {
		error "a position needs exactly one white and one black king: '$fen'"
	}
	# board order (file, then rank): the order scripts and sentences show
	foreach letter [array names on] { set on($letter) [lsort $on($letter)] }
	return [dict create {*}[array get on] tomove $tomove]
}


# The checked options as a dict; every entry point reads them the same way.
proc ::ai::similar::Options {args} {
	variable Aspects

	if {[llength $args] % 2} { error "option without a value: [join $args { }]" }
	array set opts {-aspects {pawns material} -tolerance 0 -colours same -tomove 0}
	foreach {key value} $args {
		if {$key ni {-aspects -tolerance -colours -tomove}} {
			error "no such option '$key' (use -aspects, -tolerance, -colours or -tomove)"
		}
		set opts($key) $value
	}
	# deduplicated, in the order asked for; the order shapes the sentence
	set seen {}
	foreach aspect $opts(-aspects) {
		if {$aspect ni $Aspects} {
			error "no such aspect '$aspect' (use material, pawns or pieces)"
		}
		if {$aspect in $seen} continue
		lappend seen $aspect
	}
	if {$seen eq {}} { error "at least one aspect is needed: material, pawns or pieces" }
	if {![string is integer -strict $opts(-tolerance)] || $opts(-tolerance) < 0} {
		error "the pawn tolerance is a number of pawns, 0 or more, not '$opts(-tolerance)'"
	}
	if {$opts(-colours) ni {same both}} { error "-colours is same or both, not '$opts(-colours)'" }
	if {$opts(-tomove) ni {0 1}} { error "-tomove is 0 or 1, not '$opts(-tomove)'" }
	return [list -aspects $seen -tolerance $opts(-tolerance) \
		-colours $opts(-colours) -tomove $opts(-tomove)]
}


# One piece letter on exactly these squares: "#Q[a1,h1] == 2 #Q == 2";
# an absent letter is a count of zero.
proc ::ai::similar::Exact {letter squares} {
	set n [llength $squares]
	if {$n == 0} { return "#$letter == 0" }
	return "#$letter\[[join $squares ,]\] == $n #$letter == $n"
}


# One side's pawn structure: every square named, and up to <tol> pawns of
# that side allowed elsewhere. With tolerance 0 the squares and the count
# are exact; with tolerance at least n-tol of the listed squares hold a pawn
# and at most tol of the side's pawns stand on other squares (a total cap
# alone would let an opening's eight pawns pass). An empty side is a count.
proc ::ai::similar::PawnTerm {letter squares tol} {
	set n [llength $squares]
	if {$n == 0} { return [expr {$tol > 0 ? "#$letter <= $tol" : "#$letter == 0"}] }
	if {$tol <= 0} { return [Exact $letter $squares] }
	set on "#$letter\[[join $squares ,]\]"
	set terms {}
	set lo [expr {$n - $tol}]
	if {$lo > 0} { lappend terms "$on >= $lo" }
	lappend terms "#$letter <= $on + $tol"
	return [join $terms { }]
}


proc ::ai::similar::script {fen args} {
	set opts [Options {*}$args]
	set on [parseFen $fen]
	set tol [dict get $opts -tolerance]

	set terms {}
	foreach aspect [dict get $opts -aspects] {
		switch -- $aspect {
			material {
				foreach letter {Q R B N P q r b n p} {
					lappend terms "#$letter == [llength [dict get $on $letter]]"
				}
			}
			pawns {
				lappend terms [PawnTerm P [dict get $on P] $tol]
				lappend terms [PawnTerm p [dict get $on p] $tol]
			}
			pieces {
				lappend terms [Exact K [dict get $on K]] [Exact k [dict get $on k]]
				foreach letter {Q R B N q r b n} {
					lappend terms [Exact $letter [dict get $on $letter]]
				}
			}
		}
	}
	if {[dict get $opts -tomove]} {
		lappend terms [expr {[dict get $on tomove] eq "w" ? "wtm" : "btm"}]
	}

	# a block is an AND; flipcolor also finds the structure colour-reversed
	set body "\t[join $terms "\n\t"]"
	if {[dict get $opts -colours] eq "both"} {
		return "cql()\nflipcolor {\n$body\n}"
	}
	return "cql()\n{\n$body\n}"
}


# The square list of a describe() phrase; "none" keeps it one sentence.
proc ::ai::similar::Phrase {squares} {
	return [expr {[llength $squares] ? [join $squares { }] : "none"}]
}


# "A", "A and B", "A, B, and C".
proc ::ai::similar::Sentence {parts} {
	set n [llength $parts]
	if {$n == 1} { return [lindex $parts 0] }
	if {$n == 2} { return "[lindex $parts 0] and [lindex $parts 1]" }
	return "[join [lrange $parts 0 end-1] {, }], and [lindex $parts end]"
}


# One plain sentence of what script matches, in the aspects' order.
proc ::ai::similar::describe {fen args} {
	set opts [Options {*}$args]
	set on [parseFen $fen]

	set parts {}
	foreach aspect [dict get $opts -aspects] {
		switch -- $aspect {
			material { lappend parts "the same material" }
			pawns {
				lappend parts "the same pawn structure (White: [Phrase [dict get $on P]];\
					Black: [Phrase [dict get $on p]])"
				set tol [dict get $opts -tolerance]
				if {$tol > 0} {
					lappend parts "at most $tol pawn[expr {$tol == 1 ? {} : {s}}] per side elsewhere"
				}
			}
			pieces {
				lappend parts "every king and piece (Q R B N of both colours) on the same squares"
			}
		}
	}
	set sentence [Sentence $parts]
	if {[dict get $opts -tomove]} {
		set side [expr {[dict get $on tomove] eq "w" ? "White" : "Black"}]
		append sentence ", with $side to move"
	}
	if {[dict get $opts -colours] eq "both"} {
		append sentence ", or the same with the colours reversed"
	}
	return $sentence
}
