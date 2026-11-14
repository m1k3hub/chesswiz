# ======================================================================
# FIDE C.05 Berger round robins. Pure Tcl, no UI or model dependency.
# ======================================================================

if {[llength [info commands ::util::source]]} { ::util::source td-pair }
package require Tcl 8.6

namespace eval ::td::pair {}

proc ::td::pair::dg {d key {default {}}} { if {[dict exists $d $key]} { return [dict get $d $key] }; return $default }
proc ::td::pair::Mod {a n} { return [expr {(($a % $n) + $n) % $n}] }

# One Berger cycle. The round number r is one-based. Pairing-number n is the
# fixed table seat; with an odd field it is the annex's bye seat.
proc ::td::pair::BergerRound {count r} {
	set n $count
	set odd [expr {$r % 2}]
	set s [expr {$odd ? ($r + 1) / 2 : $n / 2 + $r / 2}]
	set threshold [expr {$r / 2}]
	set pairs {}
	# The table's special pairing (or the bye when n is a virtual seat).
	if {$odd} { lappend pairs [list $s $n] } else { lappend pairs [list $n $s] }
	set seen {}
	for {set a 1} {$a < $n} {incr a} {
		if {$a == $s} { continue }
		set b [expr {[Mod [expr {2*$s - $a - 1}] [expr {$n-1}]] + 1}]
		if {$b == $a || $b == $s} { continue }
		set lo [expr {min($a,$b)}]
		set hi [expr {max($a,$b)}]
		if {$lo in $seen} { continue }
		lappend seen $lo
		set side [expr {$a <= $threshold ? "low" : "high"}]
		# Low seats reverse on odd rounds; high seats reverse on even rounds.
		if {($side eq "low" && $odd) || ($side eq "high" && !$odd)} {
			lappend pairs [list $b $a $side $a]
		} else {
			lappend pairs [list $a $b $side $a]
		}
	}
	# Annex ordering: odd rounds low descending then high ascending; even
	# rounds high descending then low ascending. The special pair leads.
	set ordered [list [lindex $pairs 0]]
	foreach side [expr {$odd ? {low high} : {high low}}] {
		set rows {}
		foreach row [lrange $pairs 1 end] {
			if {[lindex $row 2] eq $side} { lappend rows $row }
		}
		if {($odd && $side eq "low") || (!$odd && $side eq "high")} {
			set rows [lsort -integer -decreasing -index 3 $rows]
		} else {
			set rows [lsort -integer -increasing -index 3 $rows]
		}
		foreach row $rows { lappend ordered [lrange $row 0 1] }
	}
	return $ordered
}

proc ::td::pair::CycleOrder {rounds double} {
	set order {}
	for {set r 1} {$r <= $rounds} {incr r} { lappend order $r }
	if {$double && $rounds >= 2} {
		set a [lindex $order end]
		set order [lreplace $order end end]
		set b [lindex $order end]
		set order [lreplace $order end end]
		lappend order $a $b
	}
	return $order
}

# players is a list of dicts with stable id and number. Returns pairing dicts.
proc ::td::pair::RoundRobin {players double {colourLot white} {openings {}} {openingName {}}} {
	set count [llength $players]
	if {$count < 2} { error "a round robin needs at least two players" }
	if {$colourLot ni {white black}} { error "colour lot must be white or black" }
	set working $count
	if {$working % 2} { incr working }
	set cycleRounds [expr {$working - 1}]
	set order [CycleOrder $cycleRounds $double]
	set cycles [expr {$double ? 2 : 1}]
	set out {}
	set round 0
	for {set cycle 0} {$cycle < $cycles} {incr cycle} {
		foreach tableRound $order {
			incr round
			set rows [BergerRound $working $tableRound]
			set board 0
			foreach row $rows {
				lassign $row whiteNo blackNo
				set whitePlayer [lindex $players [expr {$whiteNo - 1}]]
				set white [dict get $whitePlayer id]
				set black {}
				set isBye [expr {$blackNo > $count}]
				if {!$isBye} { set black [dict get [lindex $players [expr {$blackNo - 1}]] id] }
				if {!$isBye && $colourLot eq "black"} { lassign [list $black $white] white black }
				if {!$isBye && $cycle == 1} { lassign [list $black $white] white black }
				set opening {}
				if {!$isBye && [llength $openings]} {
					set opening [lindex $openings [expr {$board % [llength $openings]}]]
				}
				set status pending
				set category {}
				set result *
				set countStandings 1
				if {$isBye} {
					set status complete
					set category pairing-bye
					set countStandings 0
				}
				lappend out [dict create id "r${round}b${board}" round $round board $board \
					table_round $tableRound cycle [expr {$cycle+1}] white $white black $black \
					result $result result_history {} termination {} status $status category $category \
					played 0 count_standings $countStandings rating 1 attempt 0 game_id {} pgn {} \
					opening $opening opening_name $openingName]
				incr board
			}
		}
	}
	return $out
}

proc ::td::pair::Validate {players pairings double} {
	set errors {}
	set seenPair [dict create]
	set count [llength $players]
	set expectedGames [expr {$double ? $count * ($count-1) : $count * ($count-1) / 2}]
	set games 0
	foreach p $pairings {
		set white [dict get $p white]
		set black [dict get $p black]
		if {[dict get $p category] eq "pairing-bye"} { continue }
		incr games
		if {$white eq $black || $white eq "" || $black eq ""} { lappend errors "invalid seats in [dict get $p id]" }
		set key [list $white $black]
		set reverse [list $black $white]
		if {[dict exists $seenPair $key] || (!$double && [dict exists $seenPair $reverse])} {
			lappend errors "duplicate pairing $white-$black"
		}
		dict set seenPair $key 1
	}
	if {$games != $expectedGames} { lappend errors "expected $expectedGames games, found $games" }
	return $errors
}

# vi:set ts=3 sw=3:
