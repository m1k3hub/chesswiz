# ======================================================================
# ::ai::cqlref -- the CQL 6.2 reference the assistant reads before it
# drafts a position-finder script (cql_help; docs/ai/ASSISTANT_COVERAGE_MAP.md §5).
#
# Models know little CQL, and their mistakes are quiet: a script that
# parses can mean something else. The card states the semantics that
# matter, as this build of CQL 6.2 implements them, and every example is
# checked by tests/test_app_cql_reference.tcl: each one parses, and most
# match a position that shows the request and miss one that does not.
#
#   ::ai::cqlref::card              -> the card (plain text)
#   ::ai::cqlref::examples ?-ids?   -> {id request cql} triples, or the ids
#   ::ai::cqlref::example <id>      -> the script of one example
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-cql-reference
}

namespace eval ai {
namespace eval cqlref {

variable Card {CQL 6.2 REFERENCE (the engine in this application)

A script is "cql()" followed by filters. CQL runs the script on every
position of every game and the game matches when some position passes.
Write only the chess pattern. Players, colours of the player, results,
dates, events, ECO and Elo are NOT written in CQL: put them in the tool's
other fields, which select the games before any is read.

PIECES AND SQUARES (a piece designator is the set of squares it stands on)
  K Q R B N P        white king, queen, rook, bishop, knight, pawn
  k q r b n p        the black pieces
  A  a  _            any white piece, any black piece, an empty square
  [QR]  [Qq]  [RBN]  any of these pieces
  e4  a-h7  c-f3-6  d-e4-5   squares: one square, a rank, a rectangle
  Pa-h7  ra-h2  Nd5  K[a1,h8]   pieces on squares
  Not valid: [a1-h8], Pa2-h2, P[a-h]2, _2

COMBINING
  {f g h}      all of f, g and h hold (a block is an AND)
  f and g      f or g      not f      if f then g else h
  X & Y        squares in both sets          X | Y   squares in either set
  ~X           the squares NOT in X (a set); "not" negates a filter, not a set
  #X           the number of squares in X:   #N == 2   #(A attacks k) >= 2
  comparisons  ==  !=  <  <=  >  >=  only between counts or numbers;
               a bare number is not a filter ("year 2020" is wrong)
  wtm  btm     White / Black to move

ATTACKS (the semantics that decide most scripts)
  X attacks Y    the squares of X that attack something in Y.
                 "N attacks k" is the white knights that give check.
  Y attackedby X the squares of Y attacked by something in X.
                 "#([qr] attackedby P) >= 2" = a pawn attacks two of them
                 (but it may be two different pawns; see SAME PIECE)
  X attacks Y is a set: as a filter it holds when it is not empty.

SAME PIECE: when one piece must do two things, name it.
  square x in N {x attacks k x attacks q}     one knight attacks king and queen
  (N attacks k) & (N attacks q)               the same, as a set
  "N attacks k  N attacks q" is WRONG: two different knights would match.

CHECK, MATE, STALEMATE
  check  mate  stalemate      the side to move is in check / mated / stalemated
  terminal                    the last position of the game
  #(A attacks k) == 2         double check (Black in check from two pieces)

MOVES (true in the position BEFORE the move is played)
  move from N                 the next move is a white knight's
  move to e4    move from R to a-h7    move capture q    move capture [qr]
  move promote [RBN]          an underpromotion is played next
  move enpassant   move o-o   move o-o-o
  move previous capture Q     the move that LED HERE captured a white queen
  move previous promote N     ... promoted to a knight
  Prefer "move previous ..." when the position after the move is the point
  (a sacrifice was just made, a promotion just happened).

SEQUENCES (consecutive positions of the game; the side to move alternates)
  line --> F --> G        a position where F holds, and the next where G holds
  line --> move from N --> (btm and N attacks k)
                          a knight move that gives check
  "line --> check --> check" asks for BOTH sides in check in turn; for checks
  by one side, spell out every position:
  line --> (btm and check) --> wtm --> (btm and check)   two checks by White

TRANSFORMS
  flipcolor F    F, or F with colours swapped (both sides; use it almost
                 always: "a knight fork" means a fork by either side)
  flip F         F under any board symmetry      shift F   F moved on the board

COUNTS AND STRUCTURE
  power A  power a       material in pawn units (Q=9 R=5 B=N=3 P=1)
  passedpawns  isolatedpawns  doubledpawns  connectedpawns  (sets, both colours)
  light X  dark X        the pieces of X on light / dark squares
  movenumber > 30        the move number (not the game's date)
  pin from B through n to k    a bishop pins a black knight to the king

COMMON MISTAKES
  - Header data (player, year, result, event, Elo) in CQL: use the fields.
  - Two separate attacks where one piece must make both: use square x in.
  - Forgetting flipcolor, so only White's patterns are found.
  - "move ..." means the coming move; the result of a move is "move previous".
  - A bare number as a filter ("mate 1", "year 2020") is an error.
  - "X & not Y" is an error: the complement of a set is ~Y.
  - Scripts that match almost every position (e.g. "N attacks _") give
    useless samples: add the condition that makes the request special.}

# {id request cql}: the requests a player makes. Checked by
# tests/test_app_cql_reference.tcl.
variable Examples {
	checkmate		"a checkmate"
		{cql() terminal and mate}
	smothered_mate	"a smothered mate"
		{cql() flipcolor (btm and mate and not (k attacks (A | _)))}
	stalemate		"the game ends in stalemate"
		{cql() terminal and stalemate}
	knight_fork_kq	"a knight forks king and queen"
		{cql() flipcolor square x in N {x attacks k x attacks q}}
	knight_fork_kr	"a knight forks king and rook"
		{cql() flipcolor square x in N {x attacks k x attacks r}}
	royal_fork		"a knight attacks king, queen and rook at once"
		{cql() flipcolor square x in N {x attacks k x attacks q x attacks r}}
	pawn_fork		"a pawn forks two pieces"
		{cql() flipcolor square x in P {#([qrbn] attackedby x) >= 2}}
	queen_fork_kr	"the queen attacks the king and an undefended rook"
		{cql() flipcolor square x in Q {x attacks k x attacks (r & ~(r attackedby a))}}
	double_check	"a double check"
		{cql() flipcolor (btm and #(A attacks k) == 2)}
	knight_mate		"a knight gives mate"
		{cql() flipcolor (btm and mate and N attacks k)}
	back_rank_mate	"a back-rank mate"
		{cql() flipcolor (btm and mate and ka-h8 and [RQ]a-h8 attacks k)}
	mate_in_centre	"the king is mated in the middle of the board"
		{cql() flipcolor (btm and mate and kc-f3-6)}
	underpromotion	"an underpromotion"
		{cql() move previous promote [RBNrbn]}
	knight_promotion	"a pawn promotes to a knight"
		{cql() move previous promote [Nn]}
	en_passant		"an en passant capture"
		{cql() move enpassant}
	queen_taken_by_pawn	"a pawn captures a queen"
		{cql() flipcolor move from P capture q}
	queenside_castling	"queenside castling"
		{cql() move o-o-o}
	opposite_castling	"kings castled on opposite sides"
		{cql() flipcolor (Ka-c1 and kg-h8)}
	rook_seventh		"a rook on the seventh rank"
		{cql() flipcolor Ra-h7}
	two_rooks_seventh	"two rooks on the seventh rank"
		{cql() flipcolor #Ra-h7 == 2}
	passed_pawn_sixth	"a passed pawn on the sixth rank"
		{cql() flipcolor (passedpawns & Pa-h6)}
	knight_outpost_d5	"a knight on d5 that no pawn can chase away"
		{cql() flipcolor {Nd5 not (p attacks d5) not pc-e6-7}}
	isolated_queen_pawn	"an isolated queen's pawn"
		{cql() flipcolor (Pd4 and not (Pc2-7 or Pe2-7))}
	opposite_bishops	"opposite-coloured bishops"
		{cql() #B == 1 and #b == 1 and ((light B and dark b) or (dark B and light b))}
	bishop_pair_vs_knights	"the bishop pair against two knights"
		{cql() flipcolor {#B == 2 #N == 0 #n == 2 #b == 0}}
	queenless		"a queenless middlegame"
		{cql() not [Qq] and #[RBNrbn] >= 4 and #[RBNrbn] <= 12}
	rook_endgame		"a rook endgame"
		{cql() not [QBNqbn] and R and r}
	pawn_endgame		"a pawn endgame"
		{cql() not [QRBNqrbn] and [Pp]}
	endgame			"an endgame (at most two pieces a side besides king and pawns)"
		{cql() #[QRBN] <= 2 and #[qrbn] <= 2}
	queen_vs_rook	"queen against rook (king and queen against king and rook)"
		{cql() flipcolor {#A == 2 Q #a == 2 r}}
	exchange_up		"a side is the exchange up (rook for a minor piece)"
		{cql() flipcolor {#R == #r + 1 #[BN] + 1 == #[bn] #Q == #q #P == #p}}
	three_checks		"three checks in a row by one side"
		{cql() flipcolor line --> (btm and check) --> wtm --> (btm and check) --> wtm --> (btm and check)}
	knight_check_move	"a knight move that gives check"
		{cql() flipcolor line --> move from N --> (btm and N attacks k)}
	pinned_knight	"a knight pinned to its king by a bishop"
		{cql() flipcolor pin from B through n to k}
	doubled_pawns	"doubled pawns"
		{cql() flipcolor #(doubledpawns & P) >= 2}
}

} ;# namespace cqlref
} ;# namespace ai


proc ::ai::cqlref::card {} {
	variable Card
	return $Card
}


proc ::ai::cqlref::examples {args} {
	variable Examples
	if {$args eq "-ids"} { return [lmap {id request cql} $Examples { set id }] }
	return [lmap {id request cql} $Examples { list $id $request $cql }]
}


proc ::ai::cqlref::example {id} {
	variable Examples
	foreach {i request cql} $Examples { if {$i eq $id} { return $cql } }
	error "no CQL example '$id'"
}
