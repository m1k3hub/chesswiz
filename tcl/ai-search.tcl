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
#   ::ai::search::structures <fen>       -> the structure patterns a position shows
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
# happens) or structure (a kind of position, used by the brief and the study
# plan); every template is checked against fixture games and positions in
# tests/test_app_nlsearch.tcl
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
    isolated_queen_pawn {cql() flipcolor (Pd4 and not (Pc2-7 or Pe2-7))}
    opposite_bishops {cql() #B == 1 and #b == 1 and ((light B and dark b) or (dark B and light b))}
    queenless {cql() not [Qq] and #[RBNrbn] >= 4 and #[RBNrbn] <= 12}
}

# the classifier's gate for choosing a pattern (SCIDB_AI_PATTERN_SEARCH_MIN_CONFIDENCE)
variable ClassifierThreshold 0.6

variable System {You turn a request for chess games into search fields. Answer with one JSON object and nothing else:
{"player":"","color":"","result":"","opponent":"","eco":"","from":"","to":"","event":"","min_elo":"","pattern":""}
Rules: leave a field "" when the request does not say it. color is white, black or "" (the player's colour). result is win, draw or loss from the player's side, or 1-0, 0-1, 1/2-1/2 without a player. eco is an ECO code or range such as B90 or B90-B99 (map an opening name to its ECO code yourself). from and to are YYYY, YYYY.MM or YYYY.MM.DD. min_elo is the minimum average rating. pattern is one of the ids listed below or "". Never write anything else.}

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


# The ids of the structure patterns <fen> shows (the position alone).
proc ::ai::search::structures {fen} {
	set found {}
	foreach id [patternIds structure] {
		if {![catch { ::scidb::cql::position $fen [dict get [pattern $id] cql] } hit] && $hit} {
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
	return [dict create criteria $criteria pattern "" sources {}]
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
	foreach key [concat $Fields pattern] {
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
