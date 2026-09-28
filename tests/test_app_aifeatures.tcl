# ======================================================================
# Scidb App Test — study plan (tcl/ai-studyplan.tcl) and annotation
# fact-check (tcl/ai-factcheck.tcl)
# ======================================================================
# The engine, the game access, the classifier and the model are stubbed;
# the claim checker and the fact layer are real (they are the point).
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::aifeat {
	variable Saved {}
	variable Seq 0
	variable Games {1 2 3}
	variable Plys {}
	variable Classifications {}
	variable Facts {}
	variable Comments {}
	variable Result {}
	variable Saved2 {}
}

proc ::scidb::test::aifeat::stub {name body} {
	variable Saved

	if {[llength [info commands $name]]} {
		set real "$name.__saved[incr ::scidb::test::aifeat::Seq]"
		rename $name $real
		lappend Saved [list $name $real]
	}
	proc $name {*}$body
	return
}

proc ::scidb::test::aifeat::restoreAll {} {
	variable Saved

	foreach pair [lreverse $Saved] {
		lassign $pair name real
		catch { rename $name {} }
		catch { rename $real $name }
	}
	set Saved {}
	return
}

proc ::scidb::test::aifeat::wait {cond ms} {
	set n 0
	while {![uplevel #1 [list expr $cond]] && $n < $ms} { update ; after 10 ; incr n }
	return [uplevel #1 [list expr $cond]]
}

proc ::scidb::test::aifeat::facts {phase args} {
	set facts [dict create phase $phase \
		motifs [dict create enPrise {white {} black {}} forks {white {} black {}}] \
		tactics [dict create whiteUndefended {} blackUndefended {} whitePinned {} blackPinned {}] \
		kingSafety [dict create white {attackers 0} black {attackers 0}]]
	foreach {key value} $args { dict set facts $key $value }
	return $facts
}

# ----------------------------------------------------------------------
# The pattern rules
# ----------------------------------------------------------------------
tcltest::test plan-pattern-rules {the pattern comes from the position facts} -body {
	set hanging [::scidb::test::aifeat::facts opening \
		motifs [dict create enPrise {white {d5} black {}} forks {white {} black {}}]]
	set endgame [::scidb::test::aifeat::facts endgame]
	set attack  [::scidb::test::aifeat::facts middlegame \
		kingSafety [dict create white {attackers 3} black {attackers 0}]]
	set quiet   [::scidb::test::aifeat::facts middlegame]
	list \
		[::ai::studyplan::pattern $hanging white Blunder 300] \
		[::ai::studyplan::pattern $endgame white Mistake 100] \
		[::ai::studyplan::pattern $attack white Mistake 100] \
		[::ai::studyplan::pattern $quiet black Mistake 100] \
		[::ai::studyplan::pattern [::scidb::test::aifeat::facts opening] black Inaccuracy 60]
} -result {tactical endgame kingsafety positional opening}

tcltest::test plan-clusters-rank {clusters rank by count, then by damage} -body {
	set ::ai::studyplan::Priv(mistakes) [list \
		[dict create pattern tactical cpLoss 300 game 1 ply 2 key m-0.2 san Nf6 side white class Blunder best Nf3] \
		[dict create pattern tactical cpLoss 100 game 1 ply 4 key m-0.4 san Bc4 side white class Mistake best d4] \
		[dict create pattern endgame cpLoss 900 game 2 ply 9 key m-0.9 san Ke3 side white class Blunder best Kd4]]
	set clusters [::ai::studyplan::Clusters]
	set result [lmap c $clusters { list [lindex $c 0] [lindex $c 1] [lindex $c 2] }]
	set text [::ai::studyplan::PlanText]
	list $result [string match {*tactical: 2 mistake*} $text] [string match {*game #2 move 9*} $text]
} -cleanup {
	set ::ai::studyplan::Priv(mistakes) {}
} -result [list [list {tactical 2 400} {endgame 1 900}] 1 1]

tcltest::test plan-classifier-opinion {a confident classifier label is used, rules otherwise} -setup {
	::scidb::test::aifeat::stub ::ai::systemone::enabled {{} {return 1}}
	::scidb::test::aifeat::stub ::ai::systemone::evaluateAsync {{state questions script} {
		uplevel #0 [list {*}$script $::scidb::test::aifeat::Result]
	}}
} -body {
	set facts [::scidb::test::aifeat::facts middlegame]
	set confident {}
	::ai::studyplan::OnClassified $facts white Blunder 300 \
		{apply {{r} {set ::scidb::test::aifeat::Confident $r}}} \
		[dict create ok 1 answers [dict create pattern [dict create type choice choice kingsafety confidence 0.81]]]
	update ;# the answer arrives through the event loop
	set unsure {}
	::ai::studyplan::OnClassified $facts white Blunder 300 \
		{apply {{r} {set ::scidb::test::aifeat::Unsure $r}}} \
		[dict create ok 1 answers [dict create pattern [dict create type choice choice kingsafety confidence 0.4]]]
	update
	set noClassifier {}
	proc ::ai::systemone::enabled {} { return 0 }
	::ai::studyplan::classifyPattern $facts white Blunder 300 {apply {{r} {set ::scidb::test::aifeat::None $r}}}
	update
	list [dict get $::scidb::test::aifeat::Confident pattern] [dict get $::scidb::test::aifeat::Confident source] \
		[dict get $::scidb::test::aifeat::Unsure pattern] [dict get $::scidb::test::aifeat::Unsure source] \
		[dict get $::scidb::test::aifeat::None source]
} -cleanup {
	::scidb::test::aifeat::restoreAll
} -result {kingsafety classifier positional rules rules}

# ----------------------------------------------------------------------
# The audit run
# ----------------------------------------------------------------------
# ----------------------------------------------------------------------
# The annotation fact-checker (real claim checker, real fact layer)
# ----------------------------------------------------------------------
tcltest::test factcheck-text {a contradicting claim is caught, a true one is not} -body {
	set iqp   {r1bq1rk1/pp2bppp/2n1pn2/2pp4/3P4/5NP1/PP3PBP/RNBQ1RK1 w - - 0 1}
	set start {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}
	set honest [::ai::factcheck::text $iqp "White has an isolated queen's pawn."]
	set wrong [::ai::factcheck::text $start "White has an isolated queen's pawn."]
	set illegal [::ai::factcheck::text $start "White plays Qh5 here."]
	list [llength [dict get $honest problems]] \
		[llength [dict get $wrong problems]] \
		[string match {*ungrounded*} [join [dict get $wrong problems] {; }]] \
		[llength [dict get $illegal problems]]
} -result {0 2 1 1}   ;# both the isolatedPawn and iqp vocabulary terms are contradicted

tcltest::cleanupTests