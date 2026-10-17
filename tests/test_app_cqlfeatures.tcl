# ======================================================================
# Scidb App Test Suite - features on the CQL matcher (tcl/ai-cql.tcl,
# docs/CQL_FEATURES.md): the position primitive, structure patterns, the
# structure profile, move themes, the study plan's structure section, the
# result check, and engine-certified training sets.
# ======================================================================
package require Tcl 8.5
package require tcltest 2.5
namespace eval ::scidb::test::cqlf {
	variable testDir [file dirname [file normalize [info script]]]
	variable Fixture [file join $testDir tmp-app cqlfeatures-[pid].pgn]
	variable Training [file join $testDir tmp-app cqlfeatures-[pid]-training.pgn]
	variable IQP  {r1bq1rk1/pp2bppp/2n1pn2/2pp4/3P4/5NP1/PP3PBP/RNBQ1RK1 w - - 0 1}
	variable IQPb {r1bqkb1r/pp3ppp/2n2n2/3p4/8/2N2N2/PPP2PPP/R1BQKB1R w KQkq - 0 1}
	variable QL   {r1b1kb1r/pppp1ppp/2n2n2/4p3/4P3/2N2N2/PPPP1PPP/R1B1KB1R w KQkq - 0 1}
	variable OCB  {4k3/4b3/8/8/8/8/2B5/4K3 w - - 0 1}
	variable SCB  {4k3/5b2/8/8/8/8/2B5/4K3 w - - 0 1}
	variable START {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}
	variable STALE {k7/8/2K5/8/8/8/8/1Q6 w - - 0 1}
	variable DCHK {4k3/8/8/8/4N3/8/8/4RK2 w - - 0 1}
	variable EP   {rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3}
	# index: white black result fen moves
	variable Games [list \
		"Kovac, Anna" "Rival, One"   0-1     $IQP  {1. Nc3 0-1} \
		"Kovac, Anna" "Rival, Two"   1/2-1/2 $IQP  {1. Nc3 1/2-1/2} \
		"Rival, One"  "Kovac, Anna"  1-0     $IQPb {1. Bb5 1-0} \
		"Kovac, Anna" "Rival, Three" 1-0     $QL   {1. Bb5 1-0} \
		"Rival, Four" "Kovac, Anna"  1/2-1/2 $OCB  {1. Kd2 1/2-1/2} \
		"Other, A" "Other, B" 1/2-1/2 {} {1. f3 e5 2. g4 Qh4# 1/2-1/2} \
		"Other, C" "Other, D" 0-1     {} {1. e4 c6 2. d4 d5 3. Nc3 dxe4 4. Nxe4 Nd7 5. Qe2 Ngf6 6. Nd6# 0-1} \
		"Other, E" "Other, F" 1-0     $STALE {1. Qb6 1-0} \
		"Other, G" "Other, H" 0-1     {} {1. f3 e5 2. g4 Qh4# 0-1} \
		"Other, I" "Other, J" 1-0     {} {1. e4 c6 2. d4 d5 3. Nc3 dxe4 4. Nxe4 Nd7 5. Qe2 Ngf6 6. Nd6# 1-0} \
		"Other, K" "Other, L" *       $DCHK {1. Nd6+ Kd7 *} \
	]
}
proc ::scidb::test::cqlf::nop {args} { return 0 }
proc ::scidb::test::cqlf::openFixture {} {
	variable Fixture
	variable Games
	file mkdir [file dirname $Fixture]
	set fh [open $Fixture w]
	fconfigure $fh -encoding utf-8
	set n 0
	foreach {white black result fen moves} $Games {
		incr n
		puts $fh "\[Event \"CQLF\"\]\n\[Site \"X\"\]\n\[Date \"2021.01.0[expr {$n % 9 + 1}]\"\]\n\[Round \"$n\"\]"
		puts $fh "\[White \"$white\"\]\n\[Black \"$black\"\]\n\[Result \"$result\"\]"
		if {$fen ne ""} { puts $fh "\[SetUp \"1\"\]\n\[FEN \"$fen\"\]" }
		puts $fh "\n$moves\n"
	}
	close $fh
	::scidb::db::open $Fixture ::scidb::test::cqlf::nop {} ::scidb::test::cqlf::nop {}
}
proc ::scidb::test::cqlf::closeFixture {} {
	variable Fixture
	variable Training
	catch { ::scidb::db::close $Fixture }
	catch { file delete $Fixture $Training }
}
::scidb::test::cqlf::openFixture

tcltest::testConstraint engine [expr {[llength [info commands ::ai::engine::available]] && [::ai::engine::available]}]


# --- the position primitive and the structure patterns -------------------------------

tcltest::test cqlf-position {one position, or one move and the position after it} -body {
	set ep $::scidb::test::cqlf::EP
	set start $::scidb::test::cqlf::START
	list [::scidb::cql::position $ep {(match (position :enpassant))} exf6] \
		[::scidb::cql::position $ep {(match (position :enpassant))} e6] \
		[::scidb::cql::position $start {(match (position Ke1 :wtm))}] \
		[catch {::scidb::cql::position $start {(match (position :enpassant))}} e1] $e1 \
		[catch {::scidb::cql::position $start {(match :result 1-0 (position))}} e2] $e2 \
		[catch {::scidb::cql::position $start {(match (position))} Ke2} e3] $e3 \
		[catch {::scidb::cql::position garbage {(match (position))}} e4] $e4
} -result {1 0 1 1 {CQL move filters need a move} 1 {CQL game-information filters need a game} 1 {illegal move 'Ke2'} 1 {invalid FEN 'garbage'}}

tcltest::test cqlf-squarecolour {L/D square-colour designators, bare and bracketed} -body {
	set start $::scidb::test::cqlf::START
	set ocb   $::scidb::test::cqlf::OCB
	set scb   $::scidb::test::cqlf::SCB
	set fens [list $start $start $start $start $start $start $start $start $start $start $ocb $scb $start $start $start]
	set queries {
		{(match (position :piececount BL? 1))}
		{(match (position :piececount BD? 1))}
		{(match (position :piececount bL? 1))}
		{(match (position :piececount bD? 1))}
		{(match (position :piececount [Bb]L? 2))}
		{(match (position :piececount [Bb]D? 2))}
		{(match (position :piececount ?L? 16))}
		{(match (position :piececount [L?] 16))}
		{(match (position :piececount B[D?] 1))}
		{(match (position :piececount BD? 0))}
		{(match (position :piececount BL? 1 :piececount bD? 1))}
		{(match (position :piececount BL? 1 :piececount bD? 1))}
		{(match (position :piececount [Bb]L? 1))}
		{(match (position :piececount [Bb]L? 3))}
		{(match (position :piececount [L?] 17))}
	}
	lmap fen $fens q $queries { ::scidb::cql::position $fen $q }
} -result {1 1 1 1 1 1 1 1 1 0 1 0 0 0 0}

tcltest::test cqlf-colour-error {L/D may not designate both the files and the ranks} -body {
	dict get [::scidb::cql::parse {(match (position :piececount [DL] 1))}] error
} -result Square_Colour_Not_Allowed

tcltest::test cqlf-flips {spatial flip transformations (board reflection)} -body {
	set A {6k1/8/8/8/8/2R3q1/8/6K1 w - - 0 1}   ;# Rc3 qg3
	set B {6k1/8/2R3q1/8/8/8/8/6K1 w - - 0 1}   ;# rank mirror of A
	set C {6k1/8/8/8/8/2R5/8/6K1 w - - 0 1}     ;# no queen
	set D {6k1/2q5/8/8/8/2R5/8/6K1 w - - 0 1}   ;# diagonal mirror of A
	set E {6k1/8/5R2/8/8/8/5q2/6K1 w - - 0 1}   ;# off-diagonal mirror of A
	set fens [list $A $B $C $D $E]
	set out {}
	foreach q {
		{(match (position Rc3 qg3))}
		{(match (position Rc3 qg3 :fliphorizontal))}
		{(match (position Rc3 qg3 :flipvertical))}
		{(match (position Rc3 qg3 :flipdiagonal))}
		{(match (position Rc3 qg3 :flipoffdiagonal))}
		{(match (position Rc3 qg3 :flip))}
	} {
		lappend out [lmap fen $fens { ::scidb::cql::position $fen $q }]
	}
	set out
} -result {{1 0 0 0 0} {1 1 0 0 0} {1 0 0 0 0} {1 0 0 1 1} {1 0 0 0 1} {1 1 0 1 1}}

tcltest::test cqlf-shifts {translation transformations (designator shift)} -body {
	set A {6k1/8/8/8/8/2R3q1/8/6K1 w - - 0 1}   ;# Rc3 qg3
	set G {6k1/8/8/8/8/1R3q2/8/6K1 w - - 0 1}   ;# Rb3 qf3 (shift -1 file)
	set H {6k1/8/8/8/2R3q1/8/8/6K1 w - - 0 1}   ;# Rc4 qg4 (shift +1 rank)
	set I {6k1/8/8/8/3R3q/8/8/6K1 w - - 0 1}    ;# Rd4 qh4 (shift +1,+1)
	set fens [list $A $G $H $I]
	set out {}
	foreach q {
		{(match (position Rc3 qg3))}
		{(match (position Rc3 qg3 :shifthorizontal))}
		{(match (position Rc3 qg3 :shiftvertical))}
		{(match (position Rc3 qg3 :shiftmaindiagonal))}
		{(match (position Rc3 qg3 :shiftdiagonal))}
		{(match (position Rc3 qg3 :shiftoffdiagonal))}
		{(match (position Rc3 qg3 :shift))}
		{(match (position :piececount qL? 1 :shifthorizontal))}
	} {
		lappend out [lmap fen $fens { ::scidb::cql::position $fen $q }]
	}
	set out
} -result {{1 0 0 0} {1 1 0 0} {1 0 1 0} {1 0 0 1} {1 0 0 1} {1 0 0 0} {1 1 1 1} {1 1 1 1}}

tcltest::test cqlf-accumulate {count the matching transformations; :sumrange gates} -body {
	set P0 {4k3/8/8/8/8/8/8/6K1 w - - 0 1}          ;# no rook
	set P2 {4k2R/8/8/8/8/8/8/R5K1 w - - 0 1}        ;# rooks a1, h8
	set P3 {4k2R/8/8/8/3R4/8/8/R5K1 w - - 0 1}      ;# rooks a1, d4, h8
	set fens [list $P0 $P2 $P3]
	set out {}
	foreach q {
		{(match (position Rd4 :shift))}
		{(match (position Rd4 :shift :accumulate rooks))}
		{(match (position Rd4 :shift :accumulate rooks :sumrange rooks 2 3))}
		{(match (position Rd4 :shift :accumulate rooks :sumrange rooks 3 8))}
		{(match (position :reset rooks Rd4 :shift :accumulate rooks :sumrange rooks 3 8))}
		{(match (position :sumrange rooks 3 8 :and ((position Rd4 :shift :accumulate rooks))))}
		{(match (position :sumrange rooks 2 8 :and ((position Rd4 :shift :accumulate rooks))))}
	} {
		lappend out [lmap fen $fens { ::scidb::cql::position $fen $q }]
	}
	set out
} -result {{0 1 1} {0 1 1} {0 1 1} {0 0 1} {0 0 1} {0 0 1} {0 1 1}}

tcltest::test cqlf-exclude {exclude a game when an excluded position list matches anywhere} -body {
	set f $::scidb::test::cqlf::Fixture
	list \
		[::scidb::cql::search $f Normal {(match (position :check))}] \
		[::scidb::cql::search $f Normal {(match (position :mate))}] \
		[::scidb::cql::search $f Normal {(match (position :check :exclude (position :mate)))}] \
		[::scidb::cql::search $f Normal {(match (position :mate :exclude))}] \
		[::scidb::cql::search $f Normal {(match (position :mate :exclude (position :mate)))}]
} -result {{5 6 8 9 10} {5 6 8 9} 10 {} {}}

tcltest::test cqlf-tags {track a piece through the game (:forany / $tag / :tagmatch)} -body {
	set f [file join $::scidb::test::cqlf::testDir tmp-app cql-tags-[pid].pgn]
	file mkdir [file dirname $f]
	set fh [open $f w]
	fconfigure $fh -encoding utf-8
	puts $fh "\[Event \"T\"\]\n\[Site \"X\"\]\n\[Date \"2024.01.01\"\]\n\[Round \"1\"\]"
	puts $fh "\[White \"W\"\]\n\[Black \"B\"\]\n\[Result \"*\"\]"
	puts $fh "\[SetUp \"1\"\]\n\[FEN \"8/8/8/3k4/8/8/6K1/R7 w - - 0 1\"\]\n"
	puts $fh "\n1. Rh1 Ke5 2. Rh8 Kd5 3. Ra8 *\n"
	close $fh
	::scidb::db::open $f ::scidb::test::cqlf::nop {} ::scidb::test::cqlf::nop {}
	set r [list \
		[::scidb::cql::search $f Normal {(match :forany rook [Rr] (position $rook[a1]) (position $rook[h1]) (position $rook[h8]) (position $rook[a8]))}] \
		[::scidb::cql::search $f Normal {(match :forany rook [Rr] (position $rook[a1]) (position $rook[h1]))}] \
		[::scidb::cql::search $f Normal {(match :forany rook [Rr] (position $rook[a1]) (position $rook[b1]))}] \
		[::scidb::cql::search $f Normal {(match (position Ra1))}] \
		[::scidb::cql::search $f Normal {(match :forany knight [Nn] (position $knight[a1]))}] \
		[::scidb::cql::search $f Normal {(match :forany rook [Rr] (position :tagmatch rook [Rr]))}] \
		[::scidb::cql::search $f Normal {(match :forany rook [Rr] (position :tagmatch rook [Qq]))}] \
		[::scidb::cql::search $f Normal {(match :forany rook [Rr] (position :movefrom $rook))}] \
		[::scidb::cql::search $f Normal {(match :forany knight [Nn] (position :movefrom $knight))}]]
	::scidb::db::close $f
	catch { file delete $f }
	set r
} -result {0 0 {} 0 {} 0 {} 0 {}}

tcltest::test cqlf-kinds {events and structures} -body {
	list [::ai::search::patternIds event] [::ai::search::patternIds structure]
} -result {{checkmate smothered_mate stalemate en_passant underpromotion double_check back_rank_mate boden_mate anastasia_mate arabian_mate knight_fork greek_gift epaulette_mate queen_pawn_mate skewer discovered_check double_bishop_sacrifice pawn_fork legals_mate blackburne_mate pin_attacked_by_pawn double_attack_loose} {opposite_castling rook_endgame pawn_endgame isolated_queen_pawn opposite_bishops queenless rook_seventh doubled_rooks_seventh knight_outpost hanging_pawns carlsbad maroczy_bind stonewall queen_vs_rook wrong_bishop lucena alekhines_gun minority_attack hedgehog protected_passed_pawn weakened_fianchetto philidor_position vancura_position backward_pawn bad_bishop closed_center trebuchet boleslavsky_hole botvinnik_formation rook_behind_passed_pawn}}

tcltest::test cqlf-structures {each structure on positions that have it and positions that do not} -body {
	set iqp $::scidb::test::cqlf::IQP
	set iqpb $::scidb::test::cqlf::IQPb
	set ql $::scidb::test::cqlf::QL
	set ocb $::scidb::test::cqlf::OCB
	set scb $::scidb::test::cqlf::SCB
	set start $::scidb::test::cqlf::START
	lmap fen [list $iqp $iqpb $ql $ocb $scb $start] { ::ai::search::structures $fen }
} -result {isolated_queen_pawn isolated_queen_pawn queenless opposite_bishops {} {}}


# --- 1. structure profile ---------------------------------------------------------------

tcltest::test cqlf-profile {how often the player reaches each structure, and the score there} -body {
	set p [::ai::cql::profile $::scidb::test::cqlf::Fixture Normal "Kovac, Anna"]
	set s [dict get $p structures]
	list [dict get $p player] [dict get $p games] \
		[dict get $s isolated_queen_pawn] [dict get $s queenless games] [dict get $s opposite_bishops games] \
		[dict get $s rook_endgame games]
} -result {{Kovac, Anna} 5 {games 3 scored 3 points 0.5 numbers {0 1 2}} 1 1 0}

tcltest::test cqlf-profile-text {the facts as text: small samples hidden, the weakest structure marked} -body {
	set p [::ai::cql::profile $::scidb::test::cqlf::Fixture Normal "Kovac, Anna"]
	set white [::ai::cql::profile $::scidb::test::cqlf::Fixture Normal "Kovac, Anna" -colour white]
	# five scored IQP games under 40% make it the weakest structure
	set weak $p
	dict set weak structures isolated_queen_pawn {games 6 scored 6 points 1.0 numbers {}}
	dict set weak games 8
	list [::ai::cql::profileText $p] [::ai::cql::profileText $p -min 1] [dict get $white games] \
		[::ai::cql::profileText $weak]
} -result {{POSITION TYPES in Kovac, Anna's latest 5 games (found by CQL):
  isolated queen's pawn: 3 games (60%), scores 17%} {POSITION TYPES in Kovac, Anna's latest 5 games (found by CQL):
  isolated queen's pawn: 3 games (60%), scores 17%
  opposite-coloured bishops: 1 games (20%), scores 50%
  queenless middlegame: 1 games (20%), scores 100%} 3 {POSITION TYPES in Kovac, Anna's latest 8 games (found by CQL):
  isolated queen's pawn: 6 games (75%), scores 17% -- their weakest structure}}

tcltest::test cqlf-brief-facts {the brief's facts carry the profile, so the rule stance can use it} -setup {
	set saved [info body ::application::assistant::ActiveBase]
	proc ::application::assistant::ActiveBase {} { return [list $::scidb::test::cqlf::Fixture Normal] }
} -body {
	set facts [::ai::brief::StructureFacts "Kovac, Anna" ""]
	list [string match "\n\nPOSITION TYPES in Kovac, Anna's latest 5 games*" $facts] \
		[::ai::brief::StructureFacts "Nobody, At All" ""] \
		[::ai::brief::ruleStance "their games\n  isolated queen's pawn: 6 games, scores 17% -- their weakest structure"]
} -cleanup {
	proc ::application::assistant::ActiveBase {} $saved
} -result {1 {} punish_weakness}


# --- 2. themes for the annotator, structures for the study plan ---------------------------

tcltest::test cqlf-themes {what a move does, and where it leads} -body {
	set ep $::scidb::test::cqlf::EP
	set dchk $::scidb::test::cqlf::DCHK
	set iqp $::scidb::test::cqlf::IQP
	set smother {r1bqkb1r/pp1npppp/2p2n2/8/3PN3/8/PPP1QPPP/R1B1KBNR w KQkq - 3 6}
	list [::ai::cql::themes $ep exf6] [::ai::cql::themes $dchk Nd6+] \
		[::ai::cql::themesText [::ai::cql::themes $iqp]] [::ai::cql::themes $iqp Nc3] \
		[::ai::cql::themesText [::ai::cql::themes $smother Nd6#]]
} -result {{events en_passant structures {}} {events {double_check discovered_check} structures {}} {THEMES (found by CQL, exact): isolated queen's pawn} {events {} structures isolated_queen_pawn} {THEMES (found by CQL, exact): smothered mate}}

tcltest::test cqlf-annotate-prompt {the annotator's grounded prompt names the themes} -body {
	set dchk $::scidb::test::cqlf::DCHK
	set p [::ai::annotate::prompt Nd6+ Best [dict create classification Best fen $dchk cpLoss 0]]
	list [string match "*\nTHEMES (found by CQL, exact): double check, discovered check" $p] [string match "*THEMES block*" [::ai::annotate::rules]]
} -result {1 1}

tcltest::test cqlf-studyplan {mistakes carry their structures; the plan has a By structure section} -setup {
	set saved $::ai::studyplan::Priv(mistakes)
} -body {
	set iqp $::scidb::test::cqlf::IQP
	set start $::scidb::test::cqlf::START
	set m1 [dict create game 1 ply 5 side white san Nc3 class Mistake cpLoss 150 best Bd3 \
		pattern positional source rules structures [::ai::studyplan::Structures $iqp]]
	set m2 [dict create game 2 ply 9 side white san Nc3 class Blunder cpLoss 300 best Bd3 \
		pattern positional source rules structures [::ai::studyplan::Structures $iqp]]
	set m3 [dict create game 3 ply 4 side black san e5 class Mistake cpLoss 120 best c5 \
		pattern opening source rules structures [::ai::studyplan::Structures $start]]
	set ::ai::studyplan::Priv(mistakes) [list $m1 $m2 $m3]
	set text [::ai::studyplan::PlanText]
	list [string match "*positional: 2 mistake(s)*\n   positions: 2 in isolated queen's pawn\n*" $text] \
		[string match "*By structure (found by CQL in the position before the move):\n   isolated queen's pawn: 2 of 3 mistake(s), about 4.5 pawns" $text]
} -cleanup {
	set ::ai::studyplan::Priv(mistakes) $saved
} -result {1 1}


# --- 4. result check --------------------------------------------------------------------

# The PGN importer corrects a result that contradicts a final checkmate or
# stalemate (games 5, 6 and 7 are stored as 0-1, 1-0 and 1/2-1/2), so this
# fixture has nothing left to find; the game-list path is checked with a
# finding of its own.
tcltest::test cqlf-quality {results that contradict how the game ended} -body {
	set f $::scidb::test::cqlf::Fixture
	set stored [lmap n {5 6 7} {
		set tags {}
		foreach pair [::scidb::db::get tags $n $f Normal] { dict set tags {*}$pair }
		dict get $tags Result
	}]
	set found [::ai::cql::quality $f Normal]
	set fake {stalemate_scored_1-0 {7} mate_scored_draw {5}}
	::scidb::view::search $f Normal 0 null none [::ai::cql::qualityQuery $fake]
	set shown [::scidb::view::count games $f Normal 0]
	::scidb::view::search $f Normal 0 reset none
	list $stored $found [::ai::cql::qualityText $f Normal $found] [lindex [::ai::cql::qualityQuery $fake] 0] $shown
} -result {{0-1 1-0 1/2-1/2} {} {no result contradicts how its game ended} OR 0}

# Board::checkState reports stalemate (it used to look for legal moves only
# when the side to move was in check).
tcltest::test cqlf-stalemate {stalemate is seen; mate and ordinary positions are not stalemate} -body {
	set stale $::scidb::test::cqlf::STALE
	set q {(match (position :stalemate))}
	list [::scidb::cql::position $stale $q Qb6] \
		[::scidb::cql::position $::scidb::test::cqlf::START $q] \
		[::scidb::cql::position {rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3} $q] \
		[::scidb::cql::position {rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3} {(match (position :mate))}]
} -result {1 0 0 1}


# --- 3. training sets ---------------------------------------------------------------------

tcltest::test cqlf-training-args {bad requests are refused before anything runs} -body {
	list [catch {::ai::cql::training . -patterns {stalemate}} e] $e \
		[::application::assistant::CheckArgs training_set {pattern double_check max 5}] \
		[catch {::application::assistant::CheckArgs training_set {pattern en_passant}} e2] $e2
} -result {1 {pattern must be one of: checkmate, smothered_mate, back_rank_mate, boden_mate, anastasia_mate, arabian_mate, epaulette_mate, queen_pawn_mate, double_check, discovered_check, knight_fork, skewer, greek_gift, double_bishop_sacrifice, underpromotion, legals_mate, blackburne_mate, pawn_fork, pin_attacked_by_pawn, double_attack_loose} {pattern double_check player {} max 5} 1 {pattern must be one of: checkmate, smothered_mate, back_rank_mate, boden_mate, anastasia_mate, arabian_mate, epaulette_mate, queen_pawn_mate, double_check, discovered_check, knight_fork, skewer, greek_gift, double_bishop_sacrifice, underpromotion, legals_mate, blackburne_mate, pawn_fork, pin_attacked_by_pawn, double_attack_loose}}

tcltest::test cqlf-training {puzzles are the positions before the decisive move, certified by the engine} -constraints engine -setup {
	set saved [info body ::application::assistant::ActiveBase]
	proc ::application::assistant::ActiveBase {} { return [list $::scidb::test::cqlf::Fixture Normal] }
} -body {
	set ::scidb::test::cqlf::Done {}
	::ai::cql::training . -patterns {checkmate smothered_mate} -depth 8 \
		-file $::scidb::test::cqlf::Training -done {set ::scidb::test::cqlf::Done}
	set timer [after 120000 {set ::scidb::test::cqlf::Done timeout}]
	vwait ::scidb::test::cqlf::Done
	after cancel $timer
	set pgn ""
	catch { set fh [open $::scidb::test::cqlf::Training]; set pgn [read $fh]; close $fh }
	list [dict get $::scidb::test::cqlf::Done puzzles] \
		[regexp -all {\[FEN "} $pgn] \
		[string match "*Black to move: find the checkmate*2... Qh4 \{engine line: d8h4*" $pgn] \
		[string match "*White to move: find the checkmate*6. Nd6 \{engine line: e4d6*" $pgn] \
		[string match "*the same position again: 4*" [dict get $::scidb::test::cqlf::Done text]]
} -cleanup {
	proc ::application::assistant::ActiveBase {} $saved
} -result {2 2 1 1 1}

# The audit reads its games into a slot of its own: before, it called
# ::scidb::game::load without a slot, which failed inside a catch, so no
# game was ever studied.
tcltest::test cqlf-studyplan-run {the audit studies the games and leaves the board alone} -constraints engine -setup {
	set saved [info body ::application::assistant::ActiveBase]
	proc ::application::assistant::ActiveBase {} { return [list $::scidb::test::cqlf::Fixture Normal] }
} -body {
	set before [list [::scidb::game::current] [::scidb::game::position key]]
	set ::scidb::test::cqlf::Done {}
	::ai::studyplan::run . -player "Kovac, Anna" -games 3 -depth 6 -prose 0 \
		-done {set ::scidb::test::cqlf::Done}
	set timer [after 120000 {set ::scidb::test::cqlf::Done timeout}]
	vwait ::scidb::test::cqlf::Done
	after cancel $timer
	list [dict get $::scidb::test::cqlf::Done games] \
		[regexp {^Studied ([1-9]\d*) move} [dict get $::scidb::test::cqlf::Done summary]] \
		[expr {[list [::scidb::game::current] [::scidb::game::position key]] eq $before}]
} -cleanup {
	proc ::application::assistant::ActiveBase {} $saved
} -result {3 1 1}

::scidb::test::cqlf::closeFixture
::tcltest::cleanupTests
