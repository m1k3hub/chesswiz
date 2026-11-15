# ======================================================================
# C.07 2026 standings with exact rational arithmetic and contributions.
# Predetermined-pairing forfeits follow Article 15.2; the Article 16 dummy
# algorithm is applied only to Swiss records. No floating-point tiebreaks.
# ======================================================================

if {[llength [info commands ::util::source]]} { ::util::source td-score }
package require Tcl 8.6

namespace eval ::td::score {}
proc ::td::score::dg {d key {default {}}} { if {[dict exists $d $key]} { return [dict get $d $key] }; return $default }

proc ::td::score::Gcd {a b} { set a [expr {abs($a)}]; set b [expr {abs($b)}]; while {$b} { set t [expr {$a % $b}]; set a $b; set b $t }; return $a }
proc ::td::score::Rat {n {d 1}} { if {$d == 0} { error "zero rational denominator" }; if {$d < 0} { set n [expr {-$n}]; set d [expr {-$d}] }; set g [Gcd $n $d]; if {$g} { set n [expr {$n/$g}]; set d [expr {$d/$g}] }; return [list $n $d] }
proc ::td::score::Add {a b} { lassign $a an ad; lassign $b bn bd; return [Rat [expr {$an*$bd+$bn*$ad}] [expr {$ad*$bd}]] }
proc ::td::score::Sub {a b} { lassign $b n d; return [Add $a [list [expr {-$n}] $d]] }
proc ::td::score::Mul {a args} { set result $a; foreach b $args { lassign $result an ad; lassign $b bn bd; set result [Rat [expr {$an*$bn}] [expr {$ad*$bd}]] }; return $result }
proc ::td::score::Div {a b} { lassign $b n d; if {$n == 0} { error "rational division by zero" }; return [Mul $a [list $d $n]] }
proc ::td::score::Cmp {a b} { lassign $a an ad; lassign $b bn bd; set delta [expr {$an*$bd-$bn*$ad}]; return [expr {$delta < 0 ? -1 : $delta > 0 ? 1 : 0}] }
proc ::td::score::Text {r} { lassign [Rat {*}$r] n d; if {$d == 1} { return $n }; if {$d == 2} { return [format %.1f [expr {$n/2.0}]] }; return [format "%g" [expr {double($n)/$d}]] }
proc ::td::score::Value {r breakdown} { return [dict create n [lindex $r 0] d [lindex $r 1] text [Text $r] breakdown $breakdown] }
proc ::td::score::Sum {values} { set total {0 1}; foreach value $values { set total [Add $total $value] }; return $total }
proc ::td::score::RoundRating {r} { lassign $r n d; return [expr {($n < 0 ? -1 : 1) * ((2*abs($n)+$d)/(2*$d))}] }

proc ::td::score::Player {state id} { foreach p [dg $state players {}] { if {[dict get $p id] eq $id} { return $p } }; error "unknown player '$id'" }
proc ::td::score::PlayerName {state id} { if {$id eq ""} { return "BYE" }; return [dict get [Player $state $id] name] }
proc ::td::score::IsBye {p} { return [expr {[dg $p category {}] eq "pairing-bye" || [dict get $p black] eq ""}] }
proc ::td::score::Complete {p} { return [expr {[dg $p status pending] eq "complete" || [dg $p result *] ni {* {}}}] }
proc ::td::score::Annulled {p} { return [expr {[dg $p category {}] eq "annulled" || ![dg $p count_standings 1]}] }
proc ::td::score::ForfeitLoss {p player} { return [expr {[dg $p category {}] in {forfeit forfeit-loss double-forfeit withdrawal withdrawal-annulled} && ![dg $p played 1] && [Points $p $player] eq "0 1"}] }

proc ::td::score::Points {p player} {
	if {[dg $p category {}] eq "annulled" || ![dg $p count_standings 1]} { return {0 1} }
	if {[dict exists $p points] && ([dict get $p white] eq $player || [dict get $p black] eq $player)} {
		return [Rat [dict get $p points] 1]
	}
	set result [dg $p result *]
	if {$result in {* {}}} { return {0 1} }
	if {$result eq "0-0"} { return {0 1} }
	set white [expr {$result eq "1-0" ? 2 : $result eq "1/2-1/2" ? 1 : 0}]
	if {[dict get $p white] eq $player} { return [Rat $white 1] }
	if {[dict get $p black] eq $player} { return [Rat [expr {2-$white}] 1] }
	error "player '$player' is not in pairing [dict get $p id]"
}

proc ::td::score::BaseRows {state} {
	set rows [dict create]
	foreach p [dg $state players {}] {
		set id [dict get $p id]
		dict set rows $id [dict create id $id number [dg $p number 0] name [dict get $p name] \
			rating [dg $p rating {}] score2 {0 1} games 0 wins 0 won 0 bwg 0 bpg 0 score_breakdown {}]
	}
	set pairings {}
	foreach p [dg $state pairings {}] { if {[Complete $p]} { lappend pairings $p } }
	set pairings [lsort -integer -index 0 [lmap p $pairings {list [dict get $p round] [dict get $p board] $p}]]
	foreach item $pairings {
		set p [lindex $item 2]
		if {[Annulled $p]} { continue }
		foreach side {white black} {
			set id [dict get $p $side]
			if {$id eq ""} { continue }
			set points [Points $p $id]
			set row [dict get $rows $id]
			dict set row score2 [Add [dict get $row score2] $points]
			set played [expr {[dg $p played 1] && ![IsBye $p] && [dg $p category {}] ni {forfeit forfeit-loss withdrawal withdrawal-annulled requested-bye full-point-bye pairing-bye double-forfeit}}]
			if {$played} {
				dict incr row games
				if {$points eq "2 1"} {
					dict incr row won
					dict incr row wins
				}
				if {$side eq "black"} {
					dict incr row bpg
					if {$points eq "2 1"} { dict incr row bwg }
				}
			}
			set entry [dict create pairing [dict get $p id] round [dict get $p round] result [dg $p result *] points $points played $played category [dg $p category played]]
			dict lappend row score_breakdown $entry
			dict set rows $id $row
		}
	}
	# Progressive score adds the tournament score after every scheduled round.
	set rounds [dg $state rounds 0]
	dict for {id row} $rows {
		set progressive {0 1}
		for {set round 1} {$round <= $rounds} {incr round} {
			set score {0 1}
			foreach item $pairings {
				set p [lindex $item 2]
				if {[dict get $p round] > $round} { continue }
				if {[Annulled $p] || ([dict get $p white] ne $id && [dict get $p black] ne $id)} { continue }
				set score [Add $score [Points $p $id]]
			}
			set progressive [Add $progressive $score]
		}
		dict set row progressive $progressive
		dict set rows $id $row
	}
	return $rows
}

proc ::td::score::AdjustedScores {state rows} {
	set adjusted [dict create]
	set maxCompleteRound 0
	foreach q [dg $state pairings {}] {
		if {[Complete $q] && ([dict get $q black] ne "" || [dg $q category {}] eq "pairing-bye")} {
			set maxCompleteRound [expr {max($maxCompleteRound, [dict get $q round])}]
		}
	}
	dict for {id row} $rows {
		set score [dict get $row score2]
		set pairedRounds [dict create]
		foreach p [dg $state pairings {}] {
			if {[dict get $p white] eq $id || [dict get $p black] eq $id} {
				dict set pairedRounds [dict get $p round] 1
			}
			if {![Complete $p] || ([dict get $p white] ne $id && [dict get $p black] ne $id)} { continue }
			set category [dg $p category {}]
			if {$category ni {requested-bye zero-point-bye trailing-bye}} { continue }
			# C.07 16.2.5: a requested bye followed only by VURs, or in the
			# last round, is a draw for opponents' tiebreak calculations.
			set laterNonVur 0
			foreach q [dg $state pairings {}] {
				if {[dict get $q round] <= [dict get $p round] || ([dict get $q white] ne $id && [dict get $q black] ne $id)} { continue }
				if {[dg $q category {}] ni {requested-bye zero-point-bye forfeit forfeit-loss double-forfeit withdrawal trailing-bye}} { set laterNonVur 1 }
			}
			if {[dict get $p round] == [dg $state rounds 0] || !$laterNonVur} {
				set score [Add $score [Sub {1 1} [Points $p $id]]]
			}
		}
		if {[dg $state system round-robin] eq "swiss"} {
			set player [::td::model::Player $state $id]
			set wRound [dg $player withdrawn 0]
			if {$wRound > 0} {
				# C.07 16.1.1: any unpaired round after a participant withdraws is a zero-point-bye.
				for {set r $wRound} {$r <= $maxCompleteRound} {incr r} {
					if {[dict exists $pairedRounds $r]} { continue }
					set laterNonVur 0
					foreach q [dg $state pairings {}] {
						if {[dict get $q round] <= $r || ([dict get $q white] ne $id && [dict get $q black] ne $id)} { continue }
						if {[dg $q category {}] ni {requested-bye zero-point-bye forfeit forfeit-loss double-forfeit withdrawal trailing-bye}} { set laterNonVur 1 }
					}
					if {$r == [dg $state rounds 0] || !$laterNonVur} {
						set score [Add $score {1 1}]
					}
				}
			}
		}
		dict set adjusted $id $score
	}
	return $adjusted
}

proc ::td::score::DummyScore {own rounds category {scheduled {}}} {
	set cap [Rat $rounds 1]
	if {$category in {forfeit forfeit-loss} && $scheduled ne ""} { set cap $scheduled }
	set values [list $own $cap]
	return [lindex $values [expr {[Cmp $own $cap] <= 0 ? 0 : 1}]]
}

proc ::td::score::Contributions {state rows} {
	set adjusted [AdjustedScores $state $rows]
	set out [dict create]
	set system [dg $state system round-robin]
	foreach id [dict keys $rows] { dict set out $id {} }
	foreach p [dg $state pairings {}] {
		if {![Complete $p] || [Annulled $p] || [IsBye $p] && [dg $p count_standings 1] == 0} { continue }
		foreach side {white black} {
			set other [expr {$side eq "white" ? "black" : "white"}]
			set id [dict get $p $side]
			set opponent [dict get $p $other]
			if {$id eq ""} { continue }
			set category [dg $p category played]
			set played [dg $p played 1]
			set points [Points $p $id]
			if {$opponent ne ""} {
				set score [dict get $adjusted $opponent]
				set opponentName [PlayerName $state $opponent]
			} else {
				set score {0 1}
				set opponentName BYE
			}
			set dummy 0
			if {!$played && $system ni {round-robin double-round-robin}} {
				set scheduled [expr {$opponent ne "" ? [dict get $adjusted $opponent] : ""}]
				set score [DummyScore [dict get $rows $id score2] [dg $state rounds 0] $category $scheduled]
				set opponentName "dummy for round [dict get $p round]"
				set dummy 1
			}
			set vur [expr {$category in {requested-bye zero-point-bye trailing-bye} || [ForfeitLoss $p $id]}]
			set entry [dict create pairing [dict get $p id] round [dict get $p round] opponent $opponent opponent_name $opponentName \
				points $points opponent_score $score category $category played $played dummy $dummy vur $vur]
			dict lappend out $id $entry
		}
	}
	return $out
}

proc ::td::score::CutLeast {entries field {vurException 0}} {
	if {![llength $entries]} { return $entries }
	set index 0
	set chosen [lindex $entries 0]
	set i 0
	foreach entry $entries {
		if {[Cmp [dict get $entry $field] [dict get $chosen $field]] < 0} { set chosen $entry; set index $i }
		incr i
	}
	if {$vurException} {
		set vurIndex -1
		set vurChosen {}
		set i 0
		foreach entry $entries {
			if {[dict get $entry vur]} {
				if {$vurIndex < 0 || [Cmp [dict get $entry $field] [dict get $vurChosen $field]] < 0} {
					set vurChosen $entry
					set vurIndex $i
				}
			}
			incr i
		}
		if {$vurIndex >= 0} {
			set index $vurIndex
		}
	}
	return [lreplace $entries $index $index]
}

proc ::td::score::RatingDifference {fraction} {
	# FIDE B.02 (2024), table 8.1.1. Choose the nearest published p;
	# exact half steps round upward. Zero and one have notional +/-800.
	set table [list 800 677 589 538 501 470 444 422 401 383 366 351 336 322 309 296 284 273 262 251 240 230 220 211 202 193 184 175 166 158 149 141 133 125 117 110 102 95 87 80 72 65 57 50 43 36 29 21 14 7 0 -7 -14 -21 -29 -36 -43 -50 -57 -65 -72 -80 -87 -95 -102 -110 -117 -125 -133 -141 -149 -158 -166 -175 -184 -193 -202 -211 -220 -230 -240 -251 -262 -273 -284 -296 -309 -322 -336 -351 -366 -383 -401 -422 -444 -470 -501 -538 -589 -677 -800]
	lassign $fraction n d
	if {$n <= 0} { return -800 }
	if {$n >= $d} { return 800 }
	set percent [expr {(200*$n+$d)/(2*$d)}]
	return [lindex $table [expr {100-$percent}]]
}

proc ::td::score::Compute {state} {
	set rows [BaseRows $state]
	set contributions [Contributions $state $rows]
	set rounds [dg $state rounds 0]
	set players [dg $state players {}]
	set anyUnrated [expr {[lsearch -exact [lmap p $players {expr {[string is integer -strict [dg $p rating {}]] && [dg $p rating {}] > 0 ? 1 : 0}}] 0] >= 0}]
	set ratingPolicy [dg $state unrated_policy drop]
	dict for {id row} $rows {
		set entries [dict get $contributions $id]
		set bh [Sum [lmap e $entries {Mul [dict get $e opponent_score] {1 2}}]]
		set bhCut [Sum [lmap e [CutLeast $entries opponent_score 1] {Mul [dict get $e opponent_score] {1 2}}]]
		set medianEntries [CutLeast $entries opponent_score 1]
		set medianEntries [CutLeast $medianEntries opponent_score 0]
		# The second cut is the most significant value for median.
		set medianEntries [CutLeast $entries opponent_score 1]
		if {[llength $medianEntries]} {
			set highest 0
			for {set i 1} {$i < [llength $medianEntries]} {incr i} { if {[Cmp [dict get [lindex $medianEntries $i] opponent_score] [dict get [lindex $medianEntries $highest] opponent_score]] > 0} { set highest $i } }
			set medianEntries [lreplace $medianEntries $highest $highest]
		}
		set sbEntries {}
		foreach e $entries {
			set product [Mul [dict get $e points] [dict get $e opponent_score] {1 4}]
			dict set e product $product
			lappend sbEntries $e
		}
		set sb [Sum [lmap e $sbEntries {dict get $e product}]]
		set koya {0 1}
		set koyaBreak {}
		set maximumGames 0
		foreach p [dg $state pairings {}] {
			if {![IsBye $p] && ([dict get $p white] eq $id || [dict get $p black] eq $id)} { incr maximumGames }
		}
		set maximum [expr {2*$maximumGames}]
		foreach e $entries {
			set opponent [dict get $e opponent]
			if {$opponent eq ""} { continue }
			set oppScore [dict get $rows $opponent score2]
			if {[Cmp [Mul $oppScore {2 1}] [Rat $maximum 1]] >= 0} {
				set koya [Add $koya [dict get $e points]]
				lappend koyaBreak $e
			}
		}
		set ratings {}
		set ratingSum 0
		foreach e $entries {
			if {![dict get $e played] || [dict get $e opponent] eq ""} { continue }
			set rating [dict get $rows [dict get $e opponent] rating]
			if {[string is integer -strict $rating] && $rating > 0} { lappend ratings $rating; incr ratingSum $rating }
		}
		set aroValue {}
		set tprValue {}
		if {(!$anyUnrated || $ratingPolicy eq "exclude") && [llength $ratings]} {
			set aro [Div [Rat $ratingSum 1] [Rat [llength $ratings] 1]]
			set aroValue [Value [Rat [RoundRating $aro] 1] $ratings]
			set playedGames [dict get $row games]
			if {$playedGames} {
				set fraction [Div [dict get $row score2] [Rat [expr {2*$playedGames}] 1]]
				set rd [RatingDifference $fraction]
				set tprValue [Value [Rat [expr {[RoundRating $aro] + $rd}] 1] [dict create aro [Text $aro] fraction $fraction rating_difference $rd]]
			}
		}
		dict set row tiebreaks [dict create \
			buchholz [Value $bh $entries] buchholzCut1 [Value $bhCut $entries] \
			buchholzMedian [Value [Sum [lmap e $medianEntries {Mul [dict get $e opponent_score] {1 2}}]] $medianEntries] \
			sonnebornBerger [Value $sb $sbEntries] koya [Value [Mul $koya {1 2}] $koyaBreak] \
			gamesWon [Value [Rat [dict get $row won] 1] [dg $row score_breakdown {}]] wins [Value [Rat [dict get $row wins] 1] [dg $row score_breakdown {}]] \
			gamesWonWithBlack [Value [Rat [dict get $row bwg] 1] [dg $row score_breakdown {}]] gamesPlayedBlack [Value [Rat [dict get $row bpg] 1] [dg $row score_breakdown {}]] \
			progressive [Value [Mul [dict get $row progressive] {1 2}] {}] aro $aroValue tpr $tprValue]
		dict set rows $id $row
	}
	set order {}
	foreach scoreGroup [RankByScore $rows [dict keys $rows]] {
		set groupIds [lindex $scoreGroup 1]
		if {[llength $groupIds] > 1} {
			set direct [DirectValues $state $rows $groupIds]
			foreach id $groupIds {
				if {[dict exists $direct $id]} { dict set rows $id tiebreaks directEncounter [dict get $direct $id] }
			}
		} else {
			set id [lindex $groupIds 0]
			dict set rows $id tiebreaks directEncounter [Value {0 1} {}]
		}
		lappend order {*}[RankGroup $state $rows $groupIds [dg $state tiebreaks {directEncounter sonnebornBerger koya gamesWon gamesWonWithBlack progressive}]]
	}
	set result {}
	set rank 0
	foreach id $order {
		set row [dict get $rows $id]
		dict set row rank [incr rank]
		dict set row score [Value [Mul [dict get $row score2] {1 2}] [dict get $row score_breakdown]]
		lappend result $row
	}
	return $result
}

proc ::td::score::RankByScore {rows ids} {
	set groups {}
	foreach id $ids {
		set score [dict get $rows $id score2]
		set found 0
		for {set i 0} {$i < [llength $groups]} {incr i} {
			if {[Cmp $score [lindex $groups $i 0]] == 0} {
				set members [lindex $groups $i 1]
				lappend members $id
				lset groups $i 1 $members
				set found 1
				break
			}
		}
		if {!$found} { lappend groups [list $score [list $id]] }
	}
	for {set i 0} {$i < [llength $groups]} {incr i} {
		for {set j [expr {$i+1}]} {$j < [llength $groups]} {incr j} {
			if {[Cmp [lindex $groups $i 0] [lindex $groups $j 0]] < 0} {
				set tmp [lindex $groups $i]
				lset groups $i [lindex $groups $j]
				lset groups $j $tmp
			}
		}
	}
	return $groups
}

proc ::td::score::DirectValues {state rows ids} {
	set values [dict create]
	set n [llength $ids]
	foreach a $ids {
		set total {0 1}
		set breakdown {}
		foreach b $ids {
			if {$a eq $b} { continue }
			set games {}
			foreach p [dg $state pairings {}] {
				if {![Complete $p] || [Annulled $p] || [IsBye $p]} { continue }
				if {([dict get $p white] eq $a && [dict get $p black] eq $b) || ([dict get $p white] eq $b && [dict get $p black] eq $a)} {
					lappend games $p
				}
			}
			if {![llength $games]} { return {} }
			set sum {0 1}
			foreach p $games { set sum [Add $sum [Points $p $a]] }
			set average [Div $sum [Rat [llength $games] 1]]
			set total [Add $total $average]
			lappend breakdown [dict create opponent $b games $games average $average]
		}
		dict set values $a [Value [Mul $total {1 2}] $breakdown]
	}
	return $values
}

proc ::td::score::ValuesFor {state rows ids rule} {
	if {$rule eq "directEncounter"} { return [DirectValues $state $rows $ids] }
	set values [dict create]
	foreach id $ids {
		if {![dict exists $rows $id tiebreaks $rule]} { return {} }
		set value [dict get $rows $id tiebreaks $rule]
		if {$value eq ""} { return {} }
		dict set values $id $value
	}
	return $values
}

proc ::td::score::RankGroup {state rows ids rules} {
	if {[llength $ids] <= 1} { return $ids }
	if {![llength $rules]} {
		return [lmap item [lsort -integer -increasing -index 0 [lmap id $ids {list [dict get $rows $id number] $id}]] {lindex $item 1}]
	}
	set rule [lindex $rules 0]
	set values [ValuesFor $state $rows $ids $rule]
	if {![dict size $values]} { return [RankGroup $state $rows $ids [lrange $rules 1 end]] }
	set decorated {}
	foreach id $ids {
		set value [dict get $values $id]
		dict set rows $id tiebreaks $rule $value
		lappend decorated [list [list [dict get $value n] [dict get $value d]] $id]
	}
	set groups {}
	foreach item $decorated {
		set value [lindex $item 0]
		set found 0
		for {set i 0} {$i < [llength $groups]} {incr i} {
			if {[Cmp $value [lindex $groups $i 0]] == 0} {
				set members [lindex $groups $i 1]
				lappend members [lindex $item 1]
				lset groups $i 1 $members
				set found 1
				break
			}
		}
		if {!$found} { lappend groups [list $value [list [lindex $item 1]]] }
	}
	for {set i 0} {$i < [llength $groups]} {incr i} {
		for {set j [expr {$i+1}]} {$j < [llength $groups]} {incr j} {
			if {[Cmp [lindex $groups $i 0] [lindex $groups $j 0]] < 0} { set tmp [lindex $groups $i]; lset groups $i [lindex $groups $j]; lset groups $j $tmp }
		}
	}
	set out {}
	foreach group $groups {
		set subgroup [lindex $group 1]
		if {[llength $subgroup] == 1} { lappend out {*}$subgroup; continue }
		if {$rule eq "directEncounter" && [llength $groups] > 1} {
			lappend out {*}[RankGroup $state $rows $subgroup $rules]
		} else {
			lappend out {*}[RankGroup $state $rows $subgroup [lrange $rules 1 end]]
		}
	}
	return $out
}

proc ::td::score::StandingsText {rows} {
	set lines [list "Rank Player Score Tiebreaks"]
	foreach row $rows {
		set values {}
		dict for {name value} [dg $row tiebreaks {}] { if {$value ne ""} { lappend values "$name=[dict get $value text]" } }
		lappend lines [join [list [dict get $row rank] [dict get $row name] [dict get $row score text] [join [lsort $values] ,]] " | "]
	}
	return [join $lines \n]
}

proc ::td::score::PairingsText {state {round 0}} {
	if {!$round} { set round [dg $state current_round 1] }
	set lines [list "Board White Black Result Status Category"]
	foreach p [::td::model::Pairings $state $round] {
		set w [PlayerName $state [dict get $p white]]
		set b [expr {[dict get $p black] eq "" ? "BYE" : [PlayerName $state [dict get $p black]]}]
		lappend lines [join [list [dict get $p board] $w $b [dg $p result *] [dg $p status pending] [dg $p category {}]] " | "]
	}
	return [join $lines \n]
}

proc ::td::score::PairingsHTML {state {round 0}} {
	if {!$round} { set round [dg $state current_round 1] }
	append html "<html><head><meta charset=\"utf-8\"><style>body{font-family:sans-serif}table{border-collapse:collapse}td,th{border:1px solid #999;padding:.3em;text-align:left}</style></head><body>"
	append html "<h1>[Escape [dg $state name Tournament]] — Round $round Pairings</h1><table><tr><th>Board</th><th>White</th><th>Black</th><th>Result</th><th>Status</th><th>Category</th></tr>"
	foreach p [::td::model::Pairings $state $round] {
		set w [PlayerName $state [dict get $p white]]
		set b [expr {[dict get $p black] eq "" ? "BYE" : [PlayerName $state [dict get $p black]]}]
		append html "<tr><td>[dict get $p board]</td><td>[Escape $w]</td><td>[Escape $b]</td><td>[Escape [dg $p result *]]</td><td>[Escape [dg $p status pending]]</td><td>[Escape [dg $p category {}]]</td></tr>"
	}
	append html "</table></body></html>"
	return $html
}

proc ::td::score::StandingsHTML {state rows} {
	set rules [dg $state tiebreaks {directEncounter sonnebornBerger koya gamesWon gamesWonWithBlack progressive}]
	append html "<html><head><meta charset=\"utf-8\"><style>body{font-family:sans-serif}table{border-collapse:collapse}td,th{border:1px solid #999;padding:.3em;text-align:center}td.player,th.player{text-align:left}.score{font-weight:bold}</style></head><body>"
	append html "<h1>[Escape [dg $state name Tournament]] — Standings</h1><table><tr><th>Rank</th><th class=\"player\">Player</th><th>Score</th>"
	foreach rule $rules { append html "<th>[Escape $rule]</th>" }
	append html "</tr>"
	foreach row $rows {
		append html "<tr><td>[dict get $row rank]</td><td class=\"player\">[Escape [dict get $row name]]</td><td class=\"score\">[dict get $row score text]</td>"
		foreach rule $rules {
			set val [dg [dg $row tiebreaks {}] $rule {}]
			append html "<td>[Escape [expr {$val eq "" ? "" : [dict get $val text]}]]</td>"
		}
		append html "</tr>"
	}
	append html "</table></body></html>"
	return $html
}

proc ::td::score::SimplePdf {title bodyText} {
	set bodyLines [split $bodyText \n]
	set perPage 55
	set totalBody [llength $bodyLines]
	set pageCount [expr {$totalBody == 0 ? 1 : ($totalBody + $perPage - 1) / $perPage}]
	set obj1 "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n"
	set obj3 "3 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Courier >>\nendobj\n"
	set kids {}
	set pageObjs {}
	for {set p 0} {$p < $pageCount} {incr p} {
		set pageObjId [expr {4 + 2 * $p}]
		set contentObjId [expr {5 + 2 * $p}]
		lappend kids "$pageObjId 0 R"
		set start [expr {$p * $perPage}]
		set chunk [lrange $bodyLines $start [expr {$start + $perPage - 1}]]
		set hdr [expr {$pageCount > 1 ? [format "%s (Page %d of %d)" $title [expr {$p + 1}] $pageCount] : $title}]
		set pageLines [concat [list $hdr ""] $chunk]
		set stream "BT\n/F1 10 Tf\n36 756 Td\n12 TL\n"
		foreach line $pageLines {
			set safe [string map {\\ \\\\ ( \\( ) \\)} [regsub -all {[^\x20-\x7e]} $line ?]]
			append stream "($safe) Tj T*\n"
		}
		append stream "ET\n"
		lappend pageObjs "$pageObjId 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox \[0 0 612 792\] /Resources << /Font << /F1 3 0 R >> >> /Contents $contentObjId 0 R >>\nendobj\n"
		lappend pageObjs "$contentObjId 0 obj\n<< /Length [string length $stream] >>\nstream\n${stream}endstream\nendobj\n"
	}
	set obj2 "2 0 obj\n<< /Type /Pages /Kids \[[join $kids { }]\] /Count $pageCount >>\nendobj\n"
	set allObjs [concat [list $obj1 $obj2 $obj3] $pageObjs]
	set pdf "%PDF-1.4\n"
	set offsets {}
	foreach obj $allObjs {
		lappend offsets [string length $pdf]
		append pdf $obj
	}
	set size [expr {[llength $allObjs] + 1}]
	set xrefPos [string length $pdf]
	append pdf "xref\n0 $size\n0000000000 65535 f \n"
	foreach off $offsets { append pdf [format "%010d 00000 n \n" $off] }
	append pdf "trailer\n<< /Size $size /Root 1 0 R >>\nstartxref\n$xrefPos\n%%EOF\n"
	return $pdf
}

proc ::td::score::Crosstable {state rows} {
	set ids [lmap row $rows {dict get $row id}]
	set matrix [dict create]
	foreach a $ids {
		foreach b $ids {
			if {$a eq $b} { dict set matrix $a $b —; continue }
			set results {}
			foreach p [dg $state pairings {}] {
				if {![Complete $p] || ([dict get $p white] ne $a || [dict get $p black] ne $b) && ([dict get $p white] ne $b || [dict get $p black] ne $a)} { continue }
				set result [dg $p result *]
				if {[dict get $p white] eq $b} { set result [dict get {1-0 0-1 0-1 1-0 1/2-1/2 1/2-1/2 0-0 0-0 * *} $result] }
				if {[Annulled $p]} { append result " (annulled)" }
				lappend results $result
			}
			dict set matrix $a $b [join $results {, }]
		}
	}
	return [dict create players $rows matrix $matrix]
}

proc ::td::score::CrosstableText {state rows} {
	set table [Crosstable $state $rows]
	set ids [lmap row $rows {dict get $row id}]
	set lines [join [concat Rank Player $ids] \t]
	foreach row $rows {
		set id [dict get $row id]
		set line [list [dict get $row rank] [dict get $row name]]
		foreach other $ids { lappend line [dict get $table matrix $id $other] }
		lappend lines [join $line \t]
	}
	return [join $lines \n]
}

proc ::td::score::Escape {text} { return [string map {& &amp; < &lt; > &gt; \" &quot;} $text] }
proc ::td::score::CrosstableHTML {state rows} {
	set table [Crosstable $state $rows]
	set ids [lmap row $rows {dict get $row id}]
	append html "<html><head><meta charset=\"utf-8\"><style>body{font-family:sans-serif}table{border-collapse:collapse}td,th{border:1px solid #999;padding:.3em;text-align:center}td.player,th.player{text-align:left}.score{font-weight:bold}</style></head><body>"
	append html "<h1>[Escape [dg $state name Tournament]]</h1><table><tr><th>Rank</th><th class=\"player\">Player</th>"
	foreach id $ids { append html "<th>[Escape [PlayerName $state $id]]</th>" }
	append html "<th>Score</th></tr>"
	foreach row $rows {
		set id [dict get $row id]
		append html "<tr><td>[dict get $row rank]</td><td class=\"player\">[Escape [dict get $row name]]</td>"
		foreach other $ids { append html "<td>[Escape [dict get $table matrix $id $other]]</td>" }
		append html "<td class=\"score\">[dict get $row score text]</td></tr>"
	}
	append html "</table><h2>Tiebreak breakdowns</h2>"
	foreach row $rows {
		append html "<h3>[Escape [dict get $row name]]</h3><pre>[Escape [StandingsText [list $row]]]</pre>"
	}
	return $html
}

proc ::td::score::CategoryEligible {snap cat} {
	set rating [dg $snap rating {}]
	set hasRating [expr {[string is integer -strict $rating] && $rating > 0}]
	if {[dg $cat unrated_only 0]} {
		if {$hasRating} { return 0 }
	}
	if {[dg $cat max_rating {}] ne ""} {
		set maxR [dict get $cat max_rating]
		if {![string is integer -strict $maxR]} { error "category max_rating must be an integer" }
		if {!$hasRating} {
			if {![dg $cat include_unrated 0]} { return 0 }
		} elseif {$rating > $maxR} {
			return 0
		}
	}
	if {[dg $cat min_rating {}] ne ""} {
		set minR [dict get $cat min_rating]
		if {![string is integer -strict $minR]} { error "category min_rating must be an integer" }
		if {!$hasRating || $rating < $minR} { return 0 }
	}
	if {[dg $cat sex {}] ne ""} {
		if {[string tolower [dg $snap sex {}]] ne [string tolower [dict get $cat sex]]} { return 0 }
	}
	if {[dg $cat min_born {}] ne ""} {
		set born [dg $snap born {}]
		if {![string is integer -strict $born] || $born < [dict get $cat min_born]} { return 0 }
	}
	if {[dg $cat max_born {}] ne ""} {
		set born [dg $snap born {}]
		if {![string is integer -strict $born] || $born > [dict get $cat max_born]} { return 0 }
	}
	if {[llength [dg $cat federation {}]]} {
		set feds [lmap f [dict get $cat federation] {string toupper $f}]
		if {[string toupper [dg $snap federation {}]] ni $feds} { return 0 }
	}
	if {[llength [dg $cat title {}]]} {
		set titles [lmap t [dict get $cat title] {string toupper $t}]
		if {[string toupper [dg $snap title {}]] ni $titles} { return 0 }
	}
	return 1
}

proc ::td::score::ComputePoolPrizes {poolName prizes poolRows system rounding} {
	if {![llength $prizes] || ![llength $poolRows]} { return {} }
	set groups {}
	foreach row $poolRows {
		set s [list [dict get $row score n] [dict get $row score d]]
		set found 0
		for {set i 0} {$i < [llength $groups]} {incr i} {
			if {[Cmp $s [lindex $groups $i 0]] == 0} {
				set g [lindex $groups $i 1]
				lappend g $row
				lset groups $i 1 $g
				set found 1
				break
			}
		}
		if {!$found} { lappend groups [list $s [list $row]] }
	}
	set payouts {}
	set pIdx 0
	set poolRank 0
	foreach group $groups {
		if {$pIdx >= [llength $prizes]} { break }
		set gRows [lindex $group 1]
		set k [llength $gRows]
		set slice [lrange $prizes $pIdx [expr {$pIdx + $k - 1}]]
		while {[llength $slice] < $k} { lappend slice 0 }
		incr pIdx $k
		set pool {0 1}
		foreach amt $slice { set pool [Add $pool [Rat [expr {int(round(double($amt)*100))}] 100]] }
		for {set j 0} {$j < $k} {incr j} {
			incr poolRank
			set row [lindex $gRows $j]
			set pid [dict get $row id]
			set rankPrize [Rat [expr {int(round(double([lindex $slice $j])*100))}] 100]
			if {$k == 1 || $system eq "indivisible"} {
				set share $rankPrize
			} elseif {$system eq "split"} {
				set share [Div $pool [Rat $k 1]]
			} else {
				# Hort system: 50% by tiebreak rank + 50% shared equally among tied group
				set halfRank [Mul $rankPrize {1 2}]
				set halfPool [Div [Mul $pool {1 2}] [Rat $k 1]]
				set share [Add $halfRank $halfPool]
			}
			if {[Cmp $share {0 1}] <= 0} { continue }
			lassign $share sn sd
			if {$rounding eq "integer"} {
				set amountText [format "%d" [expr {int(round(double($sn)/$sd))}]]
			} elseif {$rounding eq "cent"} {
				set amountText [format "%.2f" [expr {round(double($sn)*100.0/$sd)/100.0}]]
			} else {
				set amountText [Text $share]
			}
			lappend payouts [dict create category $poolName player $pid name [dict get $row name] \
				rank [dict get $row rank] pool_rank $poolRank score [dict get $row score text] \
				tied_count $k system $system rounding $rounding exact_n $sn exact_d $sd amount $amountText paid 0]
		}
	}
	return $payouts
}

proc ::td::score::ComputePrizes {state rows domain} {
	set prizes [dg $domain prizes {1000 500 250}]
	set categories [dg $domain categories {}]
	set system [dg $domain system hort]
	set rounding [dg $domain rounding cent]
	set onePerPlayer [expr {[dg $domain one_prize_per_player 1] ? 1 : 0}]
	if {$system ni {hort split indivisible}} { error "prize system must be hort, split or indivisible" }
	if {$rounding ni {exact cent integer}} { error "prize rounding must be exact, cent or integer" }

	set eligMap [dg $state prize_eligibility {}]
	set nonWithdrawn {}
	foreach row $rows {
		set pid [dict get $row id]
		set p [::td::model::Player $state $pid]
		if {[dg $p withdrawn 0]} { continue }
		if {![dict exists $eligMap $pid]} {
			dict set eligMap $pid [dict create rating [dg $p rating {}] sex [dg $p sex {}] \
				born [dg $p born {}] federation [dg $p federation {}] title [dg $p title {}]]
		}
		lappend nonWithdrawn $row
	}

	set pools {}
	set poolIdx 0
	if {[llength $prizes]} {
		lappend pools [dict create idx [incr poolIdx] name Open prizes $prizes system $system eligible $nonWithdrawn]
	}
	foreach cat $categories {
		set catName [string trim [dg $cat name {}]]
		if {$catName eq ""} { error "prize category requires a non-empty name" }
		set catSys [dg $cat system $system]
		if {$catSys ni {hort split indivisible}} { error "category '$catName' system must be hort, split or indivisible" }
		set catRows {}
		foreach row $nonWithdrawn {
			set pid [dict get $row id]
			if {[CategoryEligible [dict get $eligMap $pid] $cat]} { lappend catRows $row }
		}
		lappend pools [dict create idx [incr poolIdx] name $catName prizes [dg $cat prizes {}] system $catSys eligible $catRows]
	}

	if {!$onePerPlayer} {
		set out {}
		foreach pool $pools {
			lappend out {*}[ComputePoolPrizes [dict get $pool name] [dict get $pool prizes] [dict get $pool eligible] [dict get $pool system] $rounding]
		}
		return $out
	}

	set excluded [dict create]
	set maxIter [expr {[llength $nonWithdrawn] * [llength $pools] + 2}]
	set tentative {}
	for {set iter 0} {$iter < $maxIter} {incr iter} {
		set tentative {}
		set winsByPlayer [dict create]
		foreach pool $pools {
			set pIdx [dict get $pool idx]
			set avail {}
			foreach row [dict get $pool eligible] {
				if {![dict exists $excluded "$pIdx:[dict get $row id]"]} { lappend avail $row }
			}
			set poolOut [ComputePoolPrizes [dict get $pool name] [dict get $pool prizes] $avail [dict get $pool system] $rounding]
			foreach entry $poolOut {
				dict lappend winsByPlayer [dict get $entry player] [list $pIdx $entry]
				lappend tentative $entry
			}
		}
		set conflictPid {}
		foreach row $nonWithdrawn {
			set pid [dict get $row id]
			if {[dict exists $winsByPlayer $pid] && [llength [dict get $winsByPlayer $pid]] > 1} {
				set conflictPid $pid
				break
			}
		}
		if {$conflictPid eq ""} { break }
		set wins [dict get $winsByPlayer $conflictPid]
		set bestPool [lindex $wins 0 0]
		set bestEntry [lindex $wins 0 1]
		set bestRat [list [dict get $bestEntry exact_n] [dict get $bestEntry exact_d]]
		foreach item [lrange $wins 1 end] {
			lassign $item candPool candEntry
			set candRat [list [dict get $candEntry exact_n] [dict get $candEntry exact_d]]
			if {[Cmp $candRat $bestRat] > 0} {
				set bestPool $candPool
				set bestRat $candRat
			}
		}
		foreach item $wins {
			set candPool [lindex $item 0]
			if {$candPool != $bestPool} {
				dict set excluded "$candPool:$conflictPid" 1
			}
		}
	}
	return $tentative
}

# vi:set ts=3 sw=3:
