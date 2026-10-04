# ======================================================================
# ::ai::search -- plain-language game search (PLAIN_LANGUAGE_SEARCH.md).
#
# A request becomes the fixed fields of the assistant's search_games tool
# (player, color, result, opponent, eco, from, to, event, min_elo) plus an
# optional *pattern*: the id of a vetted CQL template in Patterns. No model
# writes query text or CQL; the application validates every field
# (::application::assistant::CheckArgs) and builds the query itself.
#
#   ::ai::search::interpret <request> <script> ?-model 0|1? ?-classifier 0|1?
#       <script> gets {ok 1 criteria C pattern P sources S}: C the
#       search_games fields (empty when not understood), P a pattern id or
#       "", S a dict field -> text|model|classifier. Never fails: without a
#       model or a classifier the extraction alone answers.
#   ::ai::search::extract <request>      -> the deterministic part, same shape
#   ::ai::search::patternIds ?event|structure? -> the ids of the library
#   ::ai::search::pattern <id>           -> dict {label description cql kind}
#       (cql is the legacy engine's template, "" for the CQL 6.2-only ones)
#   ::ai::search::pattern6 <id>          -> the CQL 6.2 template
#   ::ai::search::structures <fen>       -> the structure patterns a position shows
#   ::ai::search::match6 <fen> <ids> ?<uci>? -> the patterns of <ids> a position
#       (or the move from it) shows, by the CQL 6.2 engine
#   ::ai::search::engine6                -> whether CQL 6.2 runs in this build
#
# The query is built by ::application::assistant::BuildQuery, which appends
# the template as a `cql` term last in the AND, so the header terms narrow
# the games before any is decoded.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-search
}

package require Tcl 8.5

namespace eval ai {
namespace eval search {

# id {label description aliases cql kind} -- kind is event (something that
# happens), structure (a kind of position, used by the brief and the study
# plan) or phase (a stage of the game, for searches only: too broad to be a
# fact about a position); every template is checked against fixture games and positions in
# tests/test_app_nlsearch.tcl. The entries with an empty legacy cql run on
# CQL 6.2 only (Patterns6; tests/test_app_pattern_library.tcl): the
# instructional canon, beginner to master -- Renaud & Kahn's mates,
# Vukovic's attack, Nimzowitsch, Kmoch and Soltis on structure, Dvoretsky's
# endgames.
variable Patterns {
	checkmate {
		"checkmate" "the game ends in checkmate"
		{checkmate mate mates mated}
		{(match (position :terminal :mate))}
		event
	}
	smothered_mate {
		"smothered mate" "a knight mates a king boxed in by its own pieces"
		{smothered}
		{(match (position :flipcolor :attackcount k [A.] 0 :btm :mate))}
		event
	}
	stalemate {
		"stalemate" "the game ends in stalemate"
		{stalemate stalemated}
		{(match (position :terminal :stalemate))}
		event
	}
	en_passant {
		"en passant" "an en-passant capture is played"
		{{en passant} en-passant e.p.}
		{(match (position :enpassant))}
		event
	}
	underpromotion {
		"underpromotion" "a pawn promotes to a rook, bishop or knight"
		{underpromotion underpromotes underpromoted {promotes to a knight} {knight promotion}}
		{(match (position :promote [RBNrbn][a-h1,a-h8]))}
		event
	}
	double_check {
		"double check" "a double check is given"
		{{double check} double-check}
		{(match (position :doublecheck))}
		event
	}
	opposite_castling {
		"kings on opposite wings" "the kings stand on opposite wings (opposite-side castling)"
		{{opposite castling} {opposite-side castling} {opposite side castling} {castled on opposite sides} {opposite wings}}
		{(match (position :flipcolor Ka-c1 kg-h8))}
		structure
	}
	rook_endgame {
		"rook ending" "a rook ending: rooks and pawns only"
		{{rook ending} {rook endings} {rook endgame} {rook endgames}}
		{(match (position :piececount [QBNqbn] 0 :piececount R 1 8 :piececount r 1 8))}
		structure
	}
	pawn_endgame {
		"pawn ending" "a pawn ending: kings and pawns only"
		{{pawn ending} {pawn endings} {pawn endgame} {pawn endgames} {king and pawn}}
		{(match (position :piececount [QRBNqrbn] 0 :piececount [Pp] 1 16))}
		structure
	}
	endgame {
		"endgame" "an endgame: each side has at most two pieces besides king and pawns"
		{{endgame} {endgames} {ending} {endings} {end game} {end games}}
		{(match (position :piececount [QRBN] 0 2 :piececount [qrbn] 0 2))}
		phase
	}
	isolated_queen_pawn {
		"isolated queen's pawn" "a side has an isolated d-pawn on d4 (d5 for Black): no own pawn on the c- or e-file"
		{{isolated queen pawn} {isolated queen's pawn} {isolated queens pawn} iqp isolani}
		{(match (position :flipcolor Pd4 :piececount P[c2-7,e2-7] 0))}
		structure
	}
	opposite_bishops {
		"opposite-coloured bishops" "each side has one bishop, and they run on squares of opposite colours"
		{{opposite-coloured bishops} {opposite colored bishops} {opposite coloured bishops} {opposite-colored bishops} {opposite bishops}}
		{(match (position :piececount B 1 :piececount b 1 :or ((position :piececount BL? 1 :piececount bD? 1) (position :piececount BD? 1 :piececount bL? 1))))}
		structure
	}
	queenless {
		"queenless middlegame" "the queens are off, with at least four other pieces left"
		{queenless {queens off} {queens traded} {queens exchanged} {without queens}}
		{(match (position :piececount [Qq] 0 :piececount [RBNrbn] 4 12))}
		structure
	}

	back_rank_mate {
		"back-rank mate" "a rook or queen mates the king on its back rank"
		{{back-rank mate} {back rank mate} {back-rank mates} {back rank} back-rank {mate on the back rank}}
		{} event
	}
	boden_mate {
		"two-bishop mate (Boden's mate)" "two bishops mate, and no other piece covers the king or its squares"
		{{boden's mate} {bodens mate} {boden mate} boden {two-bishop mate} {two bishop mate} {mate with two bishops}}
		{} event
	}
	anastasia_mate {
		"Anastasia's mate" "a rook or queen mates the king on the edge file (not in the corner) while a knight covers its flight squares"
		{{anastasia's mate} {anastasias mate} {anastasia mate} anastasia}
		{} event
	}
	arabian_mate {
		"Arabian mate" "a rook next to the cornered king mates it, defended by a knight"
		{{arabian mate} {arab mate} arabian}
		{} event
	}
	knight_fork {
		"knight fork" "a knight checks the king and attacks a queen or rook at the same time"
		{{knight fork} {knight forks} {family fork} {royal fork} fork forks}
		{} event
	}
	greek_gift {
		"Greek gift (Bxh7+)" "a bishop takes the h7 pawn with check in front of the king on g8 (h2 against g1)"
		{{greek gift} {greek gift sacrifice} {classic bishop sacrifice} bxh7+ bxh7 bxh2+ bxh2}
		{} event
	}
	rook_seventh {
		"rook on the seventh" "a rook on the 7th rank with the enemy king on its back rank (the 2nd and 1st for Black)"
		{{rook on the seventh} {rook on the 7th} {rook on seventh} {seventh rank} {7th rank} {rook on the seventh rank}}
		{} structure
	}
	doubled_rooks_seventh {
		"doubled rooks on the seventh" "both rooks of one side on the 7th rank (the 2nd for Black)"
		{{doubled rooks on the seventh} {doubled rooks on the 7th} {two rooks on the seventh} {two rooks on the 7th} {rooks on the seventh} {rooks on the 7th} {pigs on the seventh}}
		{} structure
	}
	knight_outpost {
		"knight outpost" "a knight on the 5th or 6th rank, defended by a pawn, that no enemy pawn can ever attack"
		{outpost outposts {knight outpost} {outpost knight} {knight on an outpost}}
		{} structure
	}
	hanging_pawns {
		"hanging pawns" "pawns on c4 and d4 with no own pawns on the b- and e-files and no enemy c- or d-pawns (c5 and d5 for Black)"
		{{hanging pawns} {hanging pawn}}
		{} structure
	}
	carlsbad {
		"Carlsbad structure" "the Queen's Gambit Exchange structure: d4 and e3 against d5 and c6/c7, White without a c-pawn and Black without an e-pawn (or colours reversed, as in the Caro-Kann Exchange)"
		{carlsbad {carlsbad structure} karlsbad {qgd exchange structure} {exchange queen's gambit structure}}
		{} structure
	}
	maroczy_bind {
		"Maroczy bind" "pawns on c4 and e4 without a d-pawn, against a d6/d7 pawn and no c-pawn (or colours reversed)"
		{{maroczy bind} {maróczy bind} maroczy maróczy}
		{} structure
	}
	stonewall {
		"Stonewall" "pawns on c3, d4, e3 and f4 (c6, d5, e6 and f5 for Black)"
		{stonewall {stonewall structure} {stonewall dutch} {stonewall attack}}
		{} structure
	}
	queen_vs_rook {
		"queen against rook" "king and queen against king and rook, nothing else"
		{{queen against rook} {queen vs rook} {queen versus rook} {queen v rook} {q vs r}}
		{} structure
	}
	wrong_bishop {
		"wrong-coloured bishop" "king, bishop and rook's pawn against a lone king, the bishop not controlling the queening square"
		{{wrong bishop} {wrong-coloured bishop} {wrong colored bishop} {wrong coloured bishop} {wrong-colored bishop} {wrong rook pawn}}
		{} structure
	}
	lucena {
		"Lucena position" "rook and pawn against rook: the pawn (not a rook's pawn) on the 7th, its king on the queening square, the defending king at least two files away"
		{lucena {lucena position} {building a bridge}}
		{} structure
	}
	epaulette_mate {
		"epaulette mate" "a queen mates the king on its back rank along its file, both squares beside the king blocked by its own pieces"
		{{epaulette mate} {epaulette mates} epaulette {epaulet mate}}
		{} event
	}
	queen_pawn_mate {
		"queen-and-pawn mate (Damiano's, Lolli's)" "a queen next to the king mates it, defended by a pawn"
		{{damiano's mate} {damianos mate} {damiano mate} damiano {lolli's mate} {lollis mate} {lolli mate} {queen and pawn mate} {queen-and-pawn mate}}
		{} event
	}
	skewer {
		"skewer" "a bishop, rook or queen checks the king, with a queen or rook behind the king on the same line"
		{skewer skewers skewered {x-ray check}}
		{} event
	}
	discovered_check {
		"discovered check" "a piece moves off the line between its own bishop, rook or queen and the enemy king, which is then in check"
		{{discovered check} {discovered checks} {discovered attack on the king} {discovery check}}
		{} event
	}
	double_bishop_sacrifice {
		"double bishop sacrifice (Lasker-Bauer)" "a bishop takes on h7 in front of the king on g8, and within three moves a bishop takes on g7 (h2 and g2 against g1)"
		{{double bishop sacrifice} {two bishop sacrifice} {two-bishop sacrifice} {lasker's sacrifice} {lasker sacrifice} {lasker-bauer} {lasker bauer} {sacrifice of both bishops}}
		{} event
	}
	alekhines_gun {
		"Alekhine's gun" "the queen behind both rooks on one file, nothing between them (the rooks in front)"
		{{alekhine's gun} {alekhines gun} {alekhine gun} {queen behind the rooks}}
		{} structure
	}
	minority_attack {
		"minority attack" "in the Carlsbad structure the b-pawn has reached b5 against c6 (b4 against c3 for Black)"
		{{minority attack} {minority attacks}}
		{} structure
	}
	hedgehog {
		"hedgehog" "pawns on a6, b6, d6 and e6 without a c-pawn, against c4 and e4 without a d-pawn (or colours reversed)"
		{hedgehog hedgehogs {hedgehog structure} {hedgehog system}}
		{} structure
	}
	protected_passed_pawn {
		"protected passed pawn" "a passed pawn on the 4th rank or beyond, defended by a pawn"
		{{protected passed pawn} {protected passed pawns} {protected passer} {protected passers} {defended passed pawn}}
		{} structure
	}
	weakened_fianchetto {
		"weakened fianchetto" "a king castled short behind f2, g3 and h2 without its light-squared bishop, the opponent keeping a queen or a light-squared bishop (f7, g6, h7 and the dark-squared bishop for Black)"
		{{weakened fianchetto} {fianchetto without the bishop} {missing fianchetto bishop} {weak fianchetto} {holes around the king}}
		{} structure
	}
	pawn_fork {
		"pawn fork" "a pawn move after which a pawn attacks two of king, queen, rook, bishop and knight"
		{{pawn fork} {pawn forks} {fork with a pawn}}
		{} event
	}
	legals_mate {
		"Legal's mate (minor-piece mate)" "a mate given and covered by bishops and knights alone, at least three of them, as in Legal's mate"
		{{legal's mate} {legals mate} {legal mate} {de legal} {mate with minor pieces} {minor piece mate}}
		{} event
	}
	blackburne_mate {
		"Blackburne's mate" "a bishop on h7 mates the king on g8, defended by a knight, while the other bishop covers g7 (h2, g1 and g2 for Black)"
		{{blackburne's mate} {blackburnes mate} {blackburne mate}}
		{} event
	}
	pin_attacked_by_pawn {
		"pinned piece attacked by a pawn" "a piece pinned to its king is attacked by an enemy pawn (it usually falls)"
		{{pin and win} {attack the pinned piece} {pinned piece attacked} {pile on the pin} {pinned piece}}
		{} event
	}
	double_attack_loose {
		"double attack on loose pieces" "a move after which one piece attacks two enemy pieces that nothing defends"
		{{double attack} {double attacks} {loose pieces} {two loose pieces} {undefended pieces}}
		{} event
	}
	philidor_position {
		"Philidor position" "rook and pawn against rook: the pawn not beyond the 5th, the defending king on the file in front of it, the defending rook on its 3rd rank"
		{{philidor position} {philidor defence} {philidor defense} {philidor} {third-rank defence} {third rank defence}}
		{} structure
	}
	vancura_position {
		"Vancura position" "rook and rook pawn against rook: the pawn on the 6th, its rook in front of it, the defending rook attacking the pawn from the side"
		{{vancura position} {vancura} {vancura defence} {vancura defense}}
		{} structure
	}
	backward_pawn {
		"backward pawn" "a pawn whose neighbours have all advanced past it, on a half-open file, its stop square attacked by an enemy pawn (Nimzowitsch)"
		{{backward pawn} {backward pawns} {backward d-pawn}}
		{} structure
	}
	bad_bishop {
		"bad bishop" "a bishop with at least three of its own pawns blocked by enemy pawns on its colour"
		{{bad bishop} {bad bishops} {bishop behind its pawns}}
		{} structure
	}
	closed_center {
		"closed centre" "the d- and e-pawns of one side are both blocked by enemy pawns"
		{{closed centre} {closed center} {locked centre} {locked center} {blocked centre} {blocked center} {pawn chain} {pawn chains}}
		{} structure
	}
	trebuchet {
		"trebuchet" "king and pawn each, the pawns blocking each other, and each king attacking the enemy pawn (mutual zugzwang)"
		{{trebuchet} {mutual zugzwang}}
		{} structure
	}
	boleslavsky_hole {
		"Boleslavsky hole" "pawns on d6 and e5 without a c-pawn, against e4 without a d-pawn: the d5 square (or colours reversed)"
		{{boleslavsky hole} {boleslavsky structure} {boleslavsky} {hole on d5}}
		{} structure
	}
	botvinnik_formation {
		"Botvinnik formation" "pawns on c4, d3, e4 and g3 (c5, d6, e5 and g6 for Black)"
		{{botvinnik formation} {botvinnik system} {botvinnik english} {botvinnik setup} {botvinnik set-up}}
		{} structure
	}
	rook_behind_passed_pawn {
		"rook behind a passed pawn (Tarrasch)" "a rook behind its own passed pawn on the 5th rank or beyond, on the same file with nothing between"
		{{rook behind the passed pawn} {rook behind a passed pawn} {rook behind passed pawn} {tarrasch rule} {tarrasch's rule} {rooks behind passed pawns}}
		{} structure
	}
}

variable Fields {player color result opponent eco from to event min_elo}

# Application-owned CQL 6.2 templates. Models select only a Pattern id.
variable Patterns6 {
    checkmate {cql() terminal and mate}
    smothered_mate {cql() flipcolor (btm and mate and not (k attacks (A | _)))}
    stalemate {cql() terminal and stalemate}
    en_passant {cql() enpassant}
    underpromotion {cql() move previous promote [RBNrbn]}
    double_check {cql() flipcolor (btm and #(A attacks k) == 2)}
    opposite_castling {cql() flipcolor (Ka-c1 and kg-h8)}
    rook_endgame {cql() not [QBNqbn] and R and r}
    pawn_endgame {cql() not [QRBNqrbn] and [Pp]}
    endgame {cql() #[QRBN] <= 2 and #[qrbn] <= 2}
    isolated_queen_pawn {cql() flipcolor (Pd4 and not (Pc2-7 or Pe2-7))}
    opposite_bishops {cql() #B == 1 and #b == 1 and ((light B and dark b) or (dark B and light b))}
    queenless {cql() not [Qq] and #[RBNrbn] >= 4 and #[RBNrbn] <= 12}
    back_rank_mate {cql() flipcolor (btm and mate and ka-h8 and [RQ]a-h8 attacks k)}
    boden_mate {cql() flipcolor (btm and mate and #(B attacks (k | (. attackedby k))) == 2 and not ([KQRNP] attacks (k | (. attackedby k))))}
    anastasia_mate {cql() flipcolor (btm and mate and N attacks (. attackedby k) and ((kh2-7 and [RQ]h1-8 attacks k) or (ka2-7 and [RQ]a1-8 attacks k)))}
    arabian_mate {cql() flipcolor flip (btm and mate and kh8 and ((R[g8,h7] attacks k) attackedby N))}
    knight_fork {cql() flipcolor (btm and square x in N {x attacks k x attacks [qr]})}
    greek_gift {cql() flipcolor line --> (kg8 and move from B capture ph7) --> check}
    rook_seventh {cql() flipcolor (Ra-h7 and ka-h8)}
    doubled_rooks_seventh {cql() flipcolor #Ra-h7 == 2}
    knight_outpost {cql() flipcolor square x in (Na-h5-6 attackedby P) {not (p & up horizontal 1 x)}}
    hanging_pawns {cql() flipcolor {Pc4 Pd4 not (Pb2-7 | Pe2-7) not (pc2-7 | pd2-7)}}
    carlsbad {cql() flipcolor {Pd4 Pe2-3 not Pc2-7 pd5 pc6-7 not pe2-7}}
    maroczy_bind {cql() flipcolor {Pc4 Pe4 not Pd2-7 not pc2-7 pd6-7 not pd2-5}}
    stonewall {cql() flipcolor {Pc3 Pd4 Pe3 Pf4}}
    queen_vs_rook {cql() flipcolor {#A == 2 Q #a == 2 r}}
    wrong_bishop {cql() {#a == 1 #A == 3 ((Pa2-7 and dark B) or (Ph2-7 and light B))} or {#A == 1 #a == 3 ((pa2-7 and light b) or (ph2-7 and dark b))}}
    lucena {cql() flipcolor {#A == 3 #a == 2 R r square x in Pb-g7 {K & up 1 x not (k & (x | horizontal 1 x | vertical (x | horizontal 1 x)))}}}
    epaulette_mate {cql() flipcolor (btm and mate and kb-g8 and #(a & horizontal 1 k) == 2 and (Q & vertical k) attacks k)}
    queen_pawn_mate {cql() flipcolor (btm and mate and ((Q & (. attackedby k)) attackedby P))}
    skewer {cql() flipcolor (btm and check and (ray orthogonal ([RQ] k [qr]) or ray diagonal ([BQ] k [qr])))}
    discovered_check {cql() flipcolor square y in [QRB] square x in A line --> (wtm and move from x and (ray orthogonal ((y & [QR]) x k) or ray diagonal ((y & [QB]) x k))) --> (btm and y attacks k)}
    double_bishop_sacrifice {cql() flipcolor line --> (kg8 and move from B capture ph7) --> .{1,6} --> move from B capture pg7}
    alekhines_gun {cql() flipcolor ray up (Q R R)}
    minority_attack {cql() flipcolor {Pd4 not Pc2-7 pd5 pc6 not pe2-7 Pb5}}
    hedgehog {cql() flipcolor {pa6 pb6 pd6 pe6 not pc2-7 Pc4 Pe4 not Pd2-7}}
    protected_passed_pawn {cql() flipcolor ((passedpawns & Pa-h4-7) attackedby P)}
    weakened_fianchetto {cql() flipcolor {K[g1,h1] Pf2 Pg3 Ph2 not light B (q or light b)}}
    pawn_fork {cql() flipcolor line --> move from P --> (btm and square x in P {#([kqrbn] attackedby x) >= 2})}
    legals_mate {cql() flipcolor (btm and mate and not ([KQRP] attacks (k | (. attackedby k))) and #([BN] attacks (k | (. attackedby k))) >= 3)}
    blackburne_mate {cql() flipcolor (btm and mate and kg8 and ((Bh7 attacks k) attackedby N) and B attacks g7)}
    pin_attacked_by_pawn {cql() flipcolor ((pin through [qrbn]) attackedby P)}
    double_attack_loose {cql() flipcolor line --> move from A --> (btm and square x in A {#(([qrbn] attackedby x) & ~([qrbn] attackedby a)) >= 2})}
    philidor_position {cql() flipcolor {#A == 3 #a == 2 R r square x in Pa-h2-5 {k & up x} ra-h6}}
    vancura_position {cql() flipcolor {#A == 3 #a == 2 R r ((Pa6 and Ra7-8 and ra-h6 attacks Pa6) or (Ph6 and Rh7-8 and ra-h6 attacks Ph6))}}
    backward_pawn {cql() flipcolor square x in Pa-h2-6 {not (P & (horizontal 1 x | down horizontal 1 x)) (P & up horizontal 1 x) ((up 1 x) attackedby p) not (p & up x)}}
    bad_bishop {cql() flipcolor square x in B {(light x and #(light (P & down 1 p)) >= 3) or (dark x and #(dark (P & down 1 p)) >= 3)}}
    closed_center {cql() #(Pd-e2-7 & down 1 p) == 2}
    trebuchet {cql() {#A == 2 #a == 2 P p (P & down 1 p) (p attackedby K) (P attackedby k)}}
    boleslavsky_hole {cql() flipcolor {pd6 pe5 not pc2-7 not Pd2-7 Pe4}}
    botvinnik_formation {cql() flipcolor {Pc4 Pd3 Pe4 Pg3}}
    rook_behind_passed_pawn {cql() flipcolor square x in (passedpawns & Pa-h5-7) {ray up (R x)}}
}

# The event patterns whose match is the position BEFORE their move (a
# CQL "line" from the move on); the others match the position after it.
variable MatchBefore {greek_gift discovered_check double_bishop_sacrifice pawn_fork double_attack_loose}

# the classifier's gate for choosing a pattern (SCIDB_AI_PATTERN_SEARCH_MIN_CONFIDENCE)
variable ClassifierThreshold 0.6

variable System {You turn a request for chess games into search fields. Answer with one JSON object and nothing else:
{"player":"","color":"","result":"","opponent":"","eco":"","from":"","to":"","event":"","min_elo":"","pattern":"","positional":""}
Rules: leave a field "" when the request does not say it. color is white, black or "" (the player's colour). result is win, draw or loss from the player's side, or 1-0, 0-1, 1/2-1/2 without a player. eco is an ECO code or range such as B90 or B90-B99 (map an opening name to its ECO code yourself). from and to are YYYY, YYYY.MM or YYYY.MM.DD. min_elo is the minimum average rating. pattern is one of the ids listed below or "". positional is the part of the request about a position, pattern, tactic or structure that none of the ids covers, in a few plain words (e.g. "knight fork of king and queen", "rook sacrifice on h7"); "" when an id covers it or the request asks for none. Never write anything else.}

} ;# namespace search
} ;# namespace ai


proc ::ai::search::patternIds {{kind ""}} {
	variable Patterns
	if {$kind eq ""} { return [dict keys $Patterns] }
	return [dict keys [dict filter $Patterns script {id entry} { expr {[lindex $entry 4] eq $kind} }]]
}


proc ::ai::search::pattern {id} {
	variable Patterns
	lassign [dict get $Patterns $id] label description aliases cql kind
	return [dict create label $label description $description cql $cql kind $kind]
}

proc ::ai::search::pattern6 {id} {
    variable Patterns6
    return [dict get $Patterns6 $id]
}


# Whether the CQL 6.2 engine runs here (not the stub of a build without it).
proc ::ai::search::engine6 {} {
	expr {[llength [info commands ::scidb::cql6::position]] && [::scidb::cql6::version] ne "cql6 stub 6.2"}
}


# Whether event pattern <id> matches the position before its move.
proc ::ai::search::matchBefore {id} {
	variable MatchBefore
	return [expr {$id in $MatchBefore}]
}


# The patterns of <ids> whose CQL 6.2 template matches <fen>, in library
# order. With <uci>, the move played from <fen>: an event counts only when
# it is that move's (the position after it, or the position before it for
# the patterns in MatchBefore).
proc ::ai::search::match6 {fen ids {uci ""}} {
	if {![llength $ids]} { return {} }
	set scripts [lmap id $ids { pattern6 $id }]
	set opts {}
	if {[llength $scripts] > 1} { lappend opts -scripts [lrange $scripts 1 end] }
	if {$uci ne ""} { lappend opts -move $uci }
	set found {}
	foreach {i ply} [::scidb::cql6::position $fen [lindex $scripts 0] {*}$opts] {
		set id [lindex $ids $i]
		if {$uci ne "" && $ply != ([matchBefore $id] ? 0 : 1)} { continue }
		lappend found $id
	}
	return [lmap id $ids { if {$id ni $found} continue; set id }]
}


# The ids of the structure patterns <fen> shows (the position alone).
proc ::ai::search::structures {fen} {
	if {[engine6]} {
		if {[catch { match6 $fen [patternIds structure] } found]} { return {} }
		return $found
	}
	set found {}
	foreach id [patternIds structure] {
		set cql [dict get [pattern $id] cql]
		if {$cql eq ""} continue
		if {![catch { ::scidb::cql::position $fen $cql } hit] && $hit} {
			lappend found $id
		}
	}
	return $found
}


# An empty interpretation.
proc ::ai::search::Empty {} {
	variable Fields
	set criteria {}
	foreach key $Fields { dict set criteria $key "" }
	return [dict create criteria $criteria pattern "" positional "" sources {}]
}


# ----------------------------------------------------------------------
# The deterministic part: what can be read off the words exactly.
# ----------------------------------------------------------------------
proc ::ai::search::extract {request} {
	variable Patterns

	set result [Empty]
	set text " [string tolower $request] "

	# years
	if {[regexp {(?:between|from)\s+(\d{4})\s+(?:and|to|-)\s+(\d{4})} $text -> a b]
	 || [regexp {\m(\d{4})\s*-\s*(\d{4})\M} $text -> a b]} {
		Set result from [expr {min($a, $b)}]
		Set result to [expr {max($a, $b)}]
	} elseif {[regexp {(?:since|after)\s+(\d{4})} $text -> a]
			 || [regexp {from\s+(\d{4})\s+(?:on|onwards|onward)\M} $text -> a]} {
		Set result from [expr {[string match *after* $text] ? $a + 1 : $a}]
	} elseif {[regexp {(?:before|until|till|up to)\s+(\d{4})} $text -> a]} {
		Set result to [expr {[string match *before* $text] ? $a - 1 : $a}]
	} elseif {[regexp {\m(?:in|of|during|from)\s+(\d{4})\M} $text -> a]} {
		Set result from $a
		Set result to $a
	}

	# the result: absolute first, then from the player's side
	if {[regexp {\m1-0\M|white wins|white won|wins? (?:for|by) white} $text]} {
		Set result result 1-0
	} elseif {[regexp {\m0-1\M|black wins|black won|wins? (?:for|by) black} $text]} {
		Set result result 0-1
	} elseif {[regexp {1/2-1/2|\mdraws?\M|\mdrawn\M} $text]} {
		Set result result draw
	} elseif {[regexp {\mloss(?:es)?\M|\mlost\M|\mlosing\M|\mdefeats?\M} $text]} {
		Set result result loss
	} elseif {[regexp {\mwins?\M|\mwon\M|\mvictor(?:y|ies)\M} $text]} {
		Set result result win
	}

	# the player's colour
	if {[regexp {(?:as|with)\s+(?:the\s+)?(white|black)(?:\s+pieces)?} $text -> side]} {
		Set result color $side
	}

	# an ECO code or range
	if {[regexp -nocase {\m([a-e]\d\d)(?:\s*-\s*([a-e]\d\d))?\M} $request -> a b]} {
		Set result eco [string toupper [expr {$b ne "" ? "$a-$b" : $a}]]
	}

	# a rating floor
	if {[regexp {(\d{4})\s*\+} $text -> elo]
	 || [regexp {(?:rated|elo|rating)\s+(?:of\s+)?(?:at least|above|over|>=?)?\s*(\d{4})} $text -> elo]
	 || [regexp {(?:above|over|at least)\s+(\d{4})\s*(?:elo|rating)?} $text -> elo]} {
		if {$elo >= 1000 && $elo <= 3000
		 && $elo ne [dict get $result criteria from] && $elo ne [dict get $result criteria to]} {
			Set result min_elo $elo
		}
	}

	# a pattern named by one of its aliases (the longest alias wins)
	set best ""
	set bestLength 0
	dict for {id entry} $Patterns {
		foreach alias [lindex $entry 2] {
			# a plural counts too: "stalemates", "underpromotions"
			if {[regexp "\\m[string map {. \\.} $alias](?:s|es)?\\M" $text]
			 && [string length $alias] > $bestLength} {
				set best $id
				set bestLength [string length $alias]
			}
		}
	}
	if {$best ne ""} {
		dict set result pattern $best
		dict set result sources pattern text
	}

	return $result
}


proc ::ai::search::Set {resultVar key value} {
	upvar $resultVar result
	dict set result criteria $key $value
	dict set result sources $key text
}


# ----------------------------------------------------------------------
# The whole interpretation: extraction, then the model and the classifier
# where they are available. Asynchronous; never fails.
# ----------------------------------------------------------------------
proc ::ai::search::interpret {request script args} {
	array set opts {-model 1 -classifier 1}
	array set opts $args

	set state [dict create request $request script $script \
		extracted [extract $request] model {} classifier {} pending 0]

	set useModel [expr {$opts(-model) && [ModelAvailable]}]
	set useClassifier [expr {$opts(-classifier)
		&& [llength [info commands ::ai::systemone::enabled]] && [::ai::systemone::enabled]}]

	variable Runs
	set id [incr Runs(id)]
	set Runs($id) $state

	if {$useModel} {
		dict incr Runs($id) pending
		if {[catch {
			::ai::provider::completeAsync [ModelPrompt $request] \
				[namespace code [list OnModel $id]] -system [ModelSystem]
		}]} {
			dict incr Runs($id) pending -1
		}
	}
	# the classifier only matters when the words named no pattern
	if {$useClassifier && [dict get $state extracted pattern] eq ""} {
		dict incr Runs($id) pending
		ClassifyPattern $request [namespace code [list OnClassifier $id]]
	}
	if {[dict get $Runs($id) pending] == 0} {
		after 0 [namespace code [list Finish $id]]
	}
	return
}


proc ::ai::search::ModelAvailable {} {
	if {[llength [info commands ::ai::provider::completeAsync]] == 0} { return 0 }
	return [expr {$::ai::provider::Config(name) in {stub ollama}}]
}


proc ::ai::search::ModelSystem {} {
	variable System
	variable Patterns
	set lines {}
	dict for {id entry} $Patterns { lappend lines "$id: [lindex $entry 1]" }
	return "$System\nPatterns:\n[join $lines \n]"
}


proc ::ai::search::ModelPrompt {request} {
	return "Request: $request"
}


proc ::ai::search::ClassifyPattern {request script} {
	variable Patterns
	variable ClassifierThreshold

	set criteria [dict create none "no particular position or pattern is asked for"]
	dict for {id entry} $Patterns { dict set criteria $id [lindex $entry 1] }
	::ai::decide pattern_search "SEARCH REQUEST: [string range $request 0 400]" \
		[dict create type choice \
			instructions "Which position pattern must the games contain?" \
			criteria $criteria] \
		$script -threshold $ClassifierThreshold
}


proc ::ai::search::OnModel {id result} {
	variable Runs
	if {![info exists Runs($id)]} { return }
	if {[dict get $result ok]} {
		dict set Runs($id) model [ParseModel [dict get $result text]]
	}
	Done $id
}


proc ::ai::search::OnClassifier {id decision} {
	variable Runs
	if {![info exists Runs($id)]} { return }
	if {[dict get $decision ok] && [dict get $decision source] eq "classifier"
	 && [dict get $decision label] ne "none"} {
		dict set Runs($id) classifier $decision
	}
	Done $id
}


proc ::ai::search::Done {id} {
	variable Runs
	dict incr Runs($id) pending -1
	if {[dict get $Runs($id) pending] <= 0} { Finish $id }
}


# The model's JSON, reduced to the known fields with string values; a
# pattern must be one of ours. Anything unreadable is no answer.
proc ::ai::search::ParseModel {text} {
	variable Fields
	variable Patterns

	if {![regexp {\{.*\}} $text json]} { return {} }
	::ai::provider::need json
	if {[catch { json::json2dict $json } reply] || [catch { dict size $reply }]} { return {} }

	set out {}
	foreach key [concat $Fields pattern positional] {
		if {[dict exists $reply $key]} {
			set value [string trim [dict get $reply $key]]
			if {$value ne "" && $value ne "null"} { dict set out $key $value }
		}
	}
	if {[dict exists $out pattern] && ![dict exists $Patterns [dict get $out pattern]]} {
		dict unset out pattern
	}
	return $out
}


# Merge: a model field beats an extracted one when it passes the same
# validation as the assistant's search_games; so does the model's pattern
# (it can only name one of the library), then the words', then the
# classifier's.
proc ::ai::search::Finish {id} {
	variable Runs
	variable Fields

	if {![info exists Runs($id)]} { return }
	set state $Runs($id)
	unset Runs($id)

	set result [dict get $state extracted]
	set model [dict get $state model]

	foreach key $Fields {
		if {![dict exists $model $key]} { continue }
		set trial [dict get $result criteria]
		dict set trial $key [dict get $model $key]
		if {[Valid $trial]} {
			dict set result criteria $trial
			dict set result sources $key model
		}
	}

	# the pattern: the model's (validated against the library), then the
	# words', then the classifier's
	if {[dict exists $model pattern]} {
		dict set result pattern [dict get $model pattern]
		dict set result sources pattern model
	} elseif {[dict get $result pattern] eq ""} {
		if {[dict size [dict get $state classifier]]} {
			set decision [dict get $state classifier]
			dict set result pattern [dict get $decision label]
			dict set result sources pattern [format "classifier %.2f" [dict get $decision confidence]]
		}
	}

	# a positional request no library pattern covers goes to the position
	# finder (ASSISTANT_COVERAGE_MAP.md §5): words here, never CQL
	if {[dict exists $model positional] && [dict get $result pattern] eq ""} {
		dict set result positional [dict get $model positional]
		dict set result sources positional model
	}

	# without a player, a draw is 1/2-1/2, and a win, a loss or a colour
	# has no side to belong to
	if {[dict get $result criteria player] eq ""} {
		switch -- [dict get $result criteria result] {
			draw		{ dict set result criteria result 1/2-1/2 }
			win - loss	{ dict set result criteria result ""; dict unset result sources result }
		}
		if {[dict get $result criteria color] ne ""} {
			dict set result criteria color ""
			dict unset result sources color
		}
	}

	# a combination the validation refuses keeps only what it accepts
	if {![Valid [dict get $result criteria] [dict get $result pattern]]} {
		set result [Reduce $result]
	}

	after 0 [list {*}[dict get $state script] [dict merge [dict create ok 1] $result]]
}


# Whether search_games would accept <criteria> (an empty one counts as valid:
# it is only incomplete).
proc ::ai::search::Valid {criteria {pattern ""}} {
	if {[llength [info commands ::application::assistant::CheckArgs]] == 0} { return 1 }
	set args [dict filter $criteria value ?*]
	if {$pattern ne ""} { dict set args pattern $pattern }
	if {![dict size $args]} { return 1 }
	return [expr {![catch { ::application::assistant::CheckArgs search_games $args }]}]
}


# Drop the fields that make the combination invalid, the least certain
# (model) ones first.
proc ::ai::search::Reduce {result} {
	variable Fields
	foreach wanted {model text} {
		foreach key $Fields {
			if {[dict exists $result sources $key] && [dict get $result sources $key] eq $wanted} {
				dict set result criteria $key ""
				dict unset result sources $key
				if {[Valid [dict get $result criteria] [dict get $result pattern]]} { return $result }
			}
		}
	}
	return $result
}


# The search_games arguments of an interpretation (only the fields given).
proc ::ai::search::arguments {interpretation} {
	set args [dict filter [dict get $interpretation criteria] value ?*]
	if {[dict get $interpretation pattern] ne ""} {
		dict set args pattern [dict get $interpretation pattern]
	}
	return $args
}

# vi:set ts=3 sw=3:
