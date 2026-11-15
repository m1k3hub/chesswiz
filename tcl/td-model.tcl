# ======================================================================
# Tournament Director domain commands. All mutations are pure state-to-state
# transformations; td-command owns journal persistence and revisions.
# ======================================================================

if {[llength [info commands ::util::source]]} { ::util::source td-model }
package require Tcl 8.6

namespace eval ::td::model {}
proc ::td::model::dg {d key {default {}}} { if {[dict exists $d $key]} { return [dict get $d $key] }; return $default }
proc ::td::model::Double {system} { return [expr {$system eq "double-round-robin"}] }
proc ::td::model::Rounds {count double} { set working [expr {$count + $count % 2}]; return [expr {($working - 1) * ($double ? 2 : 1)}] }

proc ::td::model::DecimalMs {value unit} {
	if {![regexp {^([0-9]+)(?:\.([0-9]+))?$} $value -> whole fraction]} { error "invalid decimal '$value'" }
	set fraction [string trimright $fraction 0]
	set numerator [expr {$whole * $unit}]
	if {$fraction ne ""} {
		set scale [expr {10 ** [string length $fraction]}]
		incr numerator [expr {($fraction * $unit) / $scale}]
	}
	return $numerator
}

proc ::td::model::TimeControl {text} {
	if {![regexp {^([0-9]+(?:\.[0-9]+)?)\+([0-9]+(?:\.[0-9]+)?)$} $text -> base increment]} { error "time control must be BASE+INCREMENT, such as 3+2 or 0+0.5" }
	return [dict create text $text base_ms [DecimalMs $base 60000] increment_ms [DecimalMs $increment 1000]]
}

proc ::td::model::EngineLabel {name existing} {
	set label $name
	for {set n 2} {$label in $existing} {incr n} { set label "$name #$n" }
	return $label
}

proc ::td::model::EngineNames {} {
	if {[llength [info commands ::enginematch::EngineNames]]} { return [::enginematch::EngineNames] }
	return [::td::runner::EngineNames]
}

proc ::td::model::MakePlayers {names kind start} {
	set out {}
	set existing {}
	set configured [EngineNames]
	if {$kind eq "engine" && ![llength $names]} { error "no configured UCI engines" }
	foreach name $names {
		set name [string trim $name]
		if {$name eq ""} { error "player names cannot be empty" }
		if {$kind eq "engine"} {
			set base $name
			regsub { #[0-9]+$} $base {} base
			if {$base ni $configured} { error "no configured UCI engine named '$base'" }
			set name [EngineLabel $name $existing]
		}
		lappend existing $name
		set number [expr {$start + [llength $out]}]
		lappend out [dict create id p$number number $number name $name kind $kind engine [expr {$kind eq "engine" ? $name : ""}] \
			rating {} fide_id {} federation {} title {} withdrawn 0]
	}
	return $out
}

proc ::td::model::NewPlayers {domain} {
	set kind [dg $domain kind human]
	set names [dg $domain players {}]
	if {$kind eq "engine" && [dict exists $domain engines] && [llength [dict get $domain engines]]} { set names [dict get $domain engines] }
	set count [dg $domain engine_count 0]
	if {$kind eq "engine" && ($count > 0 || ![llength $names])} {
		if {$count <= 0} { set count 4 }
		set configured [EngineNames]
		set names {}
		set supplied [dg $domain engines {}]
		if {[llength $supplied]} { set configured $supplied }
		if {![llength $configured]} { error "no configured UCI engines" }
		for {set i 0} {$i < $count} {incr i} { lappend names [lindex $configured [expr {$i % [llength $configured]}]] }
	}
	return [MakePlayers $names $kind 1]
}

proc ::td::model::Pairings {state {round 0}} {
	set out {}
	foreach p [dg $state pairings {}] { if {!$round || [dict get $p round] == $round} { lappend out $p } }
	return $out
}

proc ::td::model::FindPairing {state domain} {
	set pairings [dg $state pairings {}]
	set id [dg $domain pairing {}]
	set round [dg $domain round 0]
	set board [dg $domain board -1]
	for {set i 0} {$i < [llength $pairings]} {incr i} {
		set p [lindex $pairings $i]
		if {($id ne "" && [dict get $p id] eq $id) || ($id eq "" && [dict get $p round] == $round && [dict get $p board] == $board)} { return $i }
	}
	error "no such pairing"
}

proc ::td::model::FindPlayer {state value} {
	foreach p [dg $state players {}] { if {[dict get $p id] eq $value || [dict get $p name] eq $value} { return [dict get $p id] } }
	error "unknown player '$value'"
}

proc ::td::model::HasRunning {state} { foreach p [dg $state pairings {}] { if {[dg $p status pending] eq "running"} { return 1 } }; return 0 }

proc ::td::model::PublishCorrection {state} {
	if {![dg $state published 0]} { return $state }
	set publication [dg $state publication_revision 0]
	incr publication
	dict set state publication_revision $publication
	set snapshot [dict create publication_revision $publication standings [::td::score::StandingsText [::td::score::Compute $state]] created [clock seconds]]
	dict lappend state publications $snapshot
	return $state
}

proc ::td::model::Enter {state domain correct} {
	set index [FindPairing $state $domain]
	set pairings [dg $state pairings {}]
	set p [lindex $pairings $index]
	if {[dg $p status pending] eq "running"} { error "cannot enter a manual result while the runner is active" }
	if {!$correct && [dg $p status pending] eq "complete"} { error "result already exists; use correct_result" }
	if {$correct && [dg $p status pending] ne "complete"} { error "only a completed result can be corrected" }
	set result [dg $domain result *]
	if {$result ni {1-0 0-1 1/2-1/2 0-0 *}} { error "invalid result '$result'" }
	set category [dg $domain category played]
	if {$category ni {played forfeit forfeit-loss double-forfeit adjourned}} { error "invalid manual result category '$category'" }
	if {[dict get $p black] eq ""} { error "use the bye command for an unpaired player" }
    foreach side {white black} {
        if {[dict get [Player $state [dict get $p $side]] kind] eq "engine"} { error "manual OTB results require human seats" }
    }
    if {($result eq "*") != ($category eq "adjourned")} { error "only an adjourned game has an unknown result" }
    set reason [dg $domain reason {}]
    if {$correct && [dg $p signed_by {}] ne "" && [string trim $reason] eq ""} { error "correcting a signed result requires a reason" }
    set deadline [dg $state correction_deadline 0]
    if {$correct && $deadline && [clock seconds] > $deadline} { error "correction deadline passed; a human TD ruling is required" }
    dict set p signed_by [dg $domain signed_by {}]
    dict set p result_reason $reason
    dict set p entered_at [clock seconds]
    if {$category eq "double-forfeit"} { set result 0-0 }
	if {$category in {forfeit forfeit-loss double-forfeit}} { dict set p played 0 } else { dict set p played 1 }
	if {[dg $p result *] ni {* {}}} {
		dict lappend p result_history [dict create result [dict get $p result] category [dg $p category played] corrected [clock seconds]]
	}
	dict set p result $result
	dict set p category $category
	dict set p status [expr {$category eq "adjourned" ? "adjourned" : "complete"}]
	dict set p termination [expr {$category eq "played" ? "normal" : "abandoned"}]
	dict set p count_standings [expr {$category ne "adjourned"}]
	dict set p rating [expr {[dict get $p played] && $category ne "adjourned"}]
	lset pairings $index $p
	dict set state pairings $pairings
	set state [PublishCorrection $state]
	return [list $state [dict create entered 1 corrected $correct pairing [dict get $p id] result $result] {} 1]
}

proc ::td::model::Withdraw {state domain} {
	set id [FindPlayer $state [dg $domain player {}]]
	set round [dg $domain round [dg $state current_round 1]]
	set pairings [dg $state pairings {}]
	if {[dg $state system round-robin] eq "swiss"} {
		set changed 0
		set afterPairing 0
		for {set i 0} {$i < [llength $pairings]} {incr i} {
			set p [lindex $pairings $i]
			if {[IsBye $p] || ([dict get $p white] ne $id && [dict get $p black] ne $id)} { continue }
			if {[dg $p status pending] eq "complete"} { continue }
			set afterPairing 1
			dict lappend p result_history [dict create result [dg $p result *] category [dg $p category {}] withdrawn [clock seconds]]
			set opponent [expr {[dict get $p white] eq $id ? [dict get $p black] : [dict get $p white]}]
			set other [FindPlayer $state $opponent]
			set otherWithdrawn [dg [Player $state $other] withdrawn 0]
			dict set p played 0
			dict set p status complete
			dict set p termination abandoned
			dict set p rating 0
			dict set p count_standings 1
			if {$otherWithdrawn || [dg $domain policy forfeit-win] eq "double-forfeit"} {
				dict set p category double-forfeit
				dict set p result 0-0
			} else {
				dict set p category forfeit
				dict set p result [expr {[dict get $p white] eq $id ? "0-1" : "1-0"}]
			}
			lset pairings $i $p
			incr changed
		}
		set players [dg $state players {}]
		for {set i 0} {$i < [llength $players]} {incr i} {
			set p [lindex $players $i]
			if {[dict get $p id] eq $id} { dict set p withdrawn $round; lset players $i $p }
		}
		set timing [expr {$afterPairing ? "withdrawal-after-pairing" : "withdrawal-before-pairing"}]
		dict set state players $players
		dict set state pairings $pairings
		dict lappend state withdrawals [dict create player $id round $round timing $timing policy [expr {$afterPairing ? "forfeits" : "before-pairing"}] changed $changed]
		set state [PublishCorrection $state]
		return [list $state [dict create withdrawn $id round $round timing $timing policy [expr {$afterPairing ? "forfeits" : "before-pairing"}] changed $changed] {} 1]
	}
	set total 0
	set played 0
	foreach p $pairings {
		if {[IsBye $p]} { continue }
		if {[dict get $p white] ne $id && [dict get $p black] ne $id} { continue }
		incr total
		if {[dg $p status pending] eq "complete" && [dg $p played 0]} { incr played }
	}
	set annul [expr {$total > 0 && $played * 2 < $total}]
	set changed 0
	for {set i 0} {$i < [llength $pairings]} {incr i} {
		set p [lindex $pairings $i]
		if {[IsBye $p] || ([dict get $p white] ne $id && [dict get $p black] ne $id)} { continue }
		set complete [expr {[dg $p status pending] eq "complete"}]
		if {$complete && [dg $p played 0]} {
			if {$annul && [dg $p category played] ne "annulled"} {
				dict lappend p result_history [dict create result [dict get $p result] category [dg $p category played] withdrawn [clock seconds]]
				dict set p category annulled
				dict set p count_standings 0
				dict set p rating 1
				lset pairings $i $p
				incr changed
			}
			continue
		}
		if {$complete} { continue }
		dict lappend p result_history [dict create result [dg $p result *] category [dg $p category {}] withdrawn [clock seconds]]
		set opponent [expr {[dict get $p white] eq $id ? [dict get $p black] : [dict get $p white]}]
		set other [FindPlayer $state $opponent]
		set otherWithdrawn [dg [Player $state $other] withdrawn 0]
		dict set p played 0
		dict set p status complete
		dict set p termination abandoned
		dict set p rating 0
		if {$annul} {
			dict set p result *
			dict set p category withdrawal-annulled
			dict set p count_standings 0
		} else {
			dict set p category forfeit
			dict set p count_standings 1
			if {$otherWithdrawn} {
				dict set p result 0-0
			} elseif {[dict get $p white] eq $id} {
				dict set p result 0-1
			} else {
				dict set p result 1-0
			}
		}
		lset pairings $i $p
		incr changed
	}
	set players [dg $state players {}]
	for {set i 0} {$i < [llength $players]} {incr i} {
		set p [lindex $players $i]
		if {[dict get $p id] eq $id} { dict set p withdrawn $round; lset players $i $p }
	}
	dict set state players $players
	dict set state pairings $pairings
	dict lappend state withdrawals [dict create player $id round $round played $played total $total policy [expr {$annul ? "annulled" : "forfeits"}]]
	set state [PublishCorrection $state]
	return [list $state [dict create withdrawn $id played $played total $total policy [expr {$annul ? "annulled" : "forfeits"}] changed $changed] {} 1]
}

proc ::td::model::IsBye {p} { return [expr {[dg $p category {}] eq "pairing-bye" || [dict get $p black] eq ""}] }
proc ::td::model::Player {state id} { foreach p [dg $state players {}] { if {[dict get $p id] eq $id} { return $p } }; error "unknown player '$id'" }

proc ::td::model::Apply {command info domain} {
	set state [dict get $info state]
	set target {}
	set history 1
	switch -- $command {
		create {
			set name [string trim [dg $domain name Tournament]]
			if {$name eq ""} { error "event name cannot be empty" }
			set system [dg $domain system round-robin]
			if {$system ni {round-robin double-round-robin swiss}} { error "unsupported tournament system" }
			if {$system eq "swiss"} { ::td::swiss::Executable }
			set players [NewPlayers $domain]
			if {[llength $players] < 2 && [dg $domain start 0]} { error "a tournament needs at least two players before it starts" }
			set double [Double $system]
			set rounds [expr {[llength $players] < 2 ? 0 : [Rounds [llength $players] $double]}]
			if {$system eq "swiss"} {
				set rounds [dg $domain rounds 5]
				if {![string is integer -strict $rounds] || $rounds < 1 || $rounds > 99} { error "Swiss rounds must be 1..99" }
				foreach p $players { if {[dict get $p kind] eq "engine"} { error "P2 Swiss requires human players" } }
			}
			set tc [TimeControl [dg $domain time_control 3+2]]
			set path [dict get $info path]
			set id [format "evt-%08x" [zlib crc32 $path]]
			set opening [::td::openings::Resolve $domain]
			set state [dict create schema 1 id $id name $name system $system status setup players $players pairings {} \
				rounds $rounds current_round 1 revision 0 regulations [dict create laws 2023 C05 current C07 2026 C04.3 2026] \
				time_control $tc opening $opening opening_name [dg $domain opening {}] overhead_ms [dg $domain overhead_ms 100] concurrency [dg $domain concurrency 2] \
				threads 1 max_plies [dg $domain max_plies 0] tablebase [dg $domain tablebase 1] online 0 \
				colour_lot [dg $domain colour_lot white] tiebreaks {directEncounter sonnebornBerger koya gamesWon gamesWonWithBlack progressive} \
				unrated_policy [dg $domain unrated_policy drop] publication_revision 0 published 0 publications {} withdrawals {} rulings {} \
				games {} created [clock seconds] updated [clock seconds]]
			if {$system eq "swiss"} { dict set state tiebreaks {buchholzCut1 buchholz sonnebornBerger wins} }
			set start [dg $domain start 0]
			if {$start} {
				if {$system eq "swiss"} {
					dict set state pairings [::td::swiss::Pair $state 1]
				} else {
					dict set state pairings [::td::pair::RoundRobin $players $double [dict get $state colour_lot] $opening [dg $domain opening {}]]
				}
				dict set state status active
			}
			return [list $state [dict create created 1 start $start] $target $history]
		}
		import_trf {
			set filename [dg $domain filename {}]
			set content [dg $domain trf_text {}]
			if {$content eq ""} {
				if {$filename eq "" || ![file exists $filename]} { error "supply an existing TRF filename or trf_text" }
				set f [open $filename r]
				fconfigure $f -encoding utf-8
				set content [read $f]
				close $f
			}
			set parsed [::td::trf::Read $content [dg $domain through 0]]
			set system [dg $domain system swiss]
			set tc [TimeControl [dg $domain time_control 90+30]]
			set path [dict get $info path]
			set id [format "evt-%08x" [zlib crc32 $path]]
			set state [dict create schema 1 id $id name [dict get $parsed name] site [dict get $parsed site] \
				federation [dict get $parsed federation] start_date [dict get $parsed start_date] end_date [dict get $parsed end_date] \
				chief_arbiter [dict get $parsed chief_arbiter] system $system status active \
				players [dict get $parsed players] pairings [dict get $parsed pairings] \
				rounds [dict get $parsed rounds] current_round [dict get $parsed current_round] revision 0 \
				regulations [dict create laws 2023 C05 current C07 2026 C04.3 2026] time_control $tc opening {} opening_name {} \
				overhead_ms 100 concurrency 2 threads 1 max_plies 0 tablebase 1 online 0 \
				colour_lot [dict get $parsed colour_lot] tiebreaks {buchholzCut1 buchholz sonnebornBerger wins} \
				unrated_policy drop publication_revision 0 published 0 publications {} withdrawals {} rulings {} \
				games {} created [clock seconds] updated [clock seconds]]
			return [list $state [dict create imported [llength [dict get $parsed players]] rounds [dict get $parsed rounds] trf_format [dict get $parsed trf_format]] $target $history]
		}
		register { return [::td::registration::Add $state $domain] }
        register_fide { return [::td::registration::Add $state $domain 1] }
		pair_round {
			if {[dict get $state system] eq "swiss"} { return [::td::swiss::PairRound $state $domain] }
			set wanted [dg $domain round 0]
			if {[llength [Pairings $state $wanted]]} { return [list $state [dict create paired 0] $target $history] }
			set opening [dg $state opening {}]
			set all [::td::pair::RoundRobin [dict get $state players] [Double [dict get $state system]] [dg $state colour_lot white] $opening [dg $state opening_name {}]]
			if {$wanted} { set all [lmap p $all {expr {[dict get $p round] == $wanted ? $p : [continue]}}] }
			dict lappend state pairings {*}$all
			return [list $state [dict create paired [llength $all]] $target $history]
		}
		start {
			if {[dict get $state system] eq "swiss"} { return [::td::swiss::PairRound $state $domain] }
			if {[dg $state status setup] eq "active"} { return [list $state [dict create start 0] $target $history] }
			if {![llength [dg $state pairings {}]]} {
				dict set state pairings [::td::pair::RoundRobin [dict get $state players] [Double [dict get $state system]] [dg $state colour_lot white] [dg $state opening {}] [dg $state opening_name {}]]
			}
			dict set state status active
			dict set state current_round [dg $domain round [dg $state current_round 1]]
			return [list $state [dict create start 1] $target $history]
		}
		stop {
			set pairings [dg $state pairings {}]
			for {set i 0} {$i < [llength $pairings]} {incr i} {
				set p [lindex $pairings $i]
				if {[dg $p status pending] eq "running"} { dict set p status pending; dict incr p attempt; lset pairings $i $p }
			}
			dict set state pairings $pairings
			dict set state status paused
			return [list $state [dict create stopped 1] $target $history]
		}
		advance {
			set round [dg $domain round [dg $state current_round 1]]
			if {$round != [dg $state current_round 1]} { error "round advancement is out of sequence" }
			foreach p [Pairings $state $round] { if {![IsBye $p] && [dg $p status pending] ne "complete"} { error "round $round is not complete" } }
			if {$round >= [dg $state rounds 0]} {
				dict set state status finished
			} else {
				dict set state current_round [expr {$round+1}]
			}
			return [list $state [dict create advanced $round finished [expr {[dg $state status setup] eq "finished"}]] $target $history]
		}
		mark_running {
			set index [FindPairing $state $domain]
			set pairings [dg $state pairings {}]
			set p [lindex $pairings $index]
			if {[dg $p status pending] ni {pending failed}} { error "pairing is not pending" }
			dict incr p attempt
			dict set p status running
			dict set p game_id "[dict get $p id]-g[dict get $p attempt]"
			lset pairings $index $p
			dict set state pairings $pairings
			set history 0
			return [list $state [dict create running 1 pairing [dict get $p id] attempt [dict get $p attempt]] $target $history]
		}
		complete {
			set index [FindPairing $state $domain]
			set pairings [dg $state pairings {}]
			set p [lindex $pairings $index]
			if {[dg $p status pending] ne "running" || [dg $p attempt 0] != [dg $domain attempt -1]} { error "stale runner completion" }
			set result [dg $domain result *]
			if {$result ni {1-0 0-1 1/2-1/2 0-0 *}} { error "invalid runner result" }
			dict set p result $result
			dict set p category [dg $domain category played]
			dict set p played [dg $domain played 1]
			dict set p status complete
			dict set p termination [dg $domain termination normal]
			dict set p pgn [dg $domain pgn {}]
			dict set p count_standings 1
			dict set p rating 1
			lset pairings $index $p
			dict set state pairings $pairings
			set game [dict create id [dict get $p game_id] pairing [dict get $p id] result $result pgn [dict get $p pgn] created [clock seconds]]
			dict lappend state games $game
			set roundComplete 1
			foreach q [Pairings $state [dict get $p round]] { if {[dg $q status pending] ni {complete}} { set roundComplete 0 } }
			return [list $state [dict create completed 1 pairing [dict get $p id] round_complete $roundComplete] $target $history]
		}
		enter_result { return [Enter $state $domain 0] }
		correct_result { return [Enter $state $domain 1] }
		override_pairing {
			set index [FindPairing $state $domain]
			set pairings [dg $state pairings {}]
			set p [lindex $pairings $index]
			if {[dg $p status pending] ne "pending"} { error "only a pending pairing can be overridden" }
			set round [dict get $p round]
			set white [FindPlayer $state [dg $domain white {}]]
			set black [FindPlayer $state [dg $domain black {}]]
			if {$white eq $black} { error "a player cannot play itself" }
			set reason [string trim [dg $domain reason {}]]
			if {$reason eq ""} { error "a pairing override requires a reason" }
			set prevWhite [dict get $p white]
			set prevBlack [dict get $p black]
			dict set p white $white
			dict set p black $black
			# If a swapped player was on another pending board in this round, swap the displaced player across so the round stays a valid partition.
			for {set j 0} {$j < [llength $pairings]} {incr j} {
				if {$j == $index} { continue }
				set q [lindex $pairings $j]
				if {[dict get $q round] != $round || [dg $q status pending] ne "pending" || [IsBye $q]} { continue }
				set qChanged 0
				if {[dict get $q white] eq $white && $prevWhite ni [list $white $black]} { dict set q white $prevWhite; set qChanged 1 }
				if {[dict get $q black] eq $white && $prevWhite ni [list $white $black]} { dict set q black $prevWhite; set qChanged 1 }
				if {[dict get $q white] eq $black && $prevBlack ni [list $white $black]} { dict set q white $prevBlack; set qChanged 1 }
				if {[dict get $q black] eq $black && $prevBlack ni [list $white $black]} { dict set q black $prevBlack; set qChanged 1 }
				if {$qChanged} {
					set qOrig [lindex [dict get $info state pairings] $j]
					dict set q override [dict create white [dict get $qOrig white] black [dict get $qOrig black] reason $reason created [clock seconds]]
					lset pairings $j $q
				}
			}
			lset pairings $index $p
			dict set state pairings $pairings
			set check [::td::swiss::CheckRound $state $round]
			set ruling [string trim [dg $domain ruling {}]]
			set absolute [lmap v [dict get $check violations] {expr {[string match C\[1234\]-* [dict get $v code]] ? $v : [continue]}}]
			if {[llength $absolute] && $ruling eq ""} {
				error "prohibited pairing ([join [lmap v $absolute {dict get $v code}] {, }]) requires an explicit TD ruling"
			}
			dict set p override [dict create white $prevWhite black $prevBlack reason $reason ruling $ruling compliant [dict get $check compliant] violations [dict get $check violations] created [clock seconds]]
			lset pairings $index $p
			dict set state pairings $pairings
			if {$ruling ne ""} {
				dict lappend state rulings [dict create kind override-ruling pairing [dict get $p id] round $round reason $reason ruling $ruling compliant [dict get $check compliant] violations [dict get $check violations] created [clock seconds]]
			}
			return [list $state [dict create overridden [dict get $p id] compliant [dict get $check compliant] violations [dict get $check violations] bbp_report [dict get $check bbp_report]] $target $history]
		}
		withdraw { return [Withdraw $state $domain] }
		ruling { return [::td::arbiter::Record $state $domain] }
		bye {
			set id [FindPlayer $state [dg $domain player {}]]
			set category [dg $domain category requested-bye]
			if {$category ni {requested-bye zero-point-bye full-point-bye pairing-bye}} { error "invalid bye category" }
			set defaultPoints [dict get {requested-bye 1 zero-point-bye 0 full-point-bye 2 pairing-bye 2} $category]
			set supplied [dg $domain points -1]
			set points [expr {$supplied < 0 ? $defaultPoints : $supplied}]
			if {$points ni {0 1 2}} { error "bye points must be 0, 1 or 2 half-points" }
			if {$category eq "zero-point-bye"} { set points 0 }
			set round [dg $domain round 0]
			if {$round <= 0} { set round [dg $state current_round 1] }
			if {$round < 1 || ([dg $state rounds 0] > 0 && $round > [dg $state rounds 0])} { error "bye round out of range" }
			foreach q [Pairings $state $round] {
				if {[dict get $q white] eq $id || [dict get $q black] eq $id} {
					error "player already has a pairing or bye in round $round"
				}
			}
			set p [dict create id "bye-$id-r$round-[llength [dg $state pairings {}]]" round $round board 0 white $id black {} result * status complete \
				category $category played 0 count_standings 1 rating 0 points $points attempt 0 game_id {} pgn {}]
			dict lappend state pairings $p
			set state [PublishCorrection $state]
			return [list $state [dict create bye $id round $round category $category points $points] {} 1]
		}
		publish {
			set publication [expr {[dg $state publication_revision 0]+1}]
			dict set state published 1
			dict set state publication_revision $publication
			dict lappend state publications [dict create publication_revision $publication standings [::td::score::StandingsText [::td::score::Compute $state]] created [clock seconds]]
			return [list $state [dict create publication_revision $publication] $target $history]
		}
		finish {
			foreach p [dg $state pairings {}] { if {![IsBye $p] && [dg $p status pending] ne "complete"} { error "not all games are complete" } }
			dict set state status finished
			return [list $state [dict create finished 1 standings [::td::score::StandingsText [::td::score::Compute $state]]] $target $history]
		}
		recover {
			set count 0
			set pairings [dg $state pairings {}]
			for {set i 0} {$i < [llength $pairings]} {incr i} {
				set p [lindex $pairings $i]
				if {[dg $p status pending] eq "running"} { dict set p status pending; dict set p game_id {}; lset pairings $i $p; incr count }
			}
			dict set state pairings $pairings
			if {$count} { dict set state status paused }
			set history 0
			return [list $state [dict create recovered $count] $target $history]
		}
		undo - redo {
			set stack [dict get $info $command]
			if {![llength $stack]} { error "nothing to $command" }
			set target [lindex $stack end]
			set record [lindex [dict get $info records] [expr {$target-1}]]
			if {[dict get $record command] in {create import_trf}} { error "cannot undo event creation" }
			if {[HasRunning $state]} { error "stop active games before undo or redo" }
			set state [dict get $record [expr {$command eq "undo" ? "before" : "after"}]]
			set history 0
			return [list $state [dict create $command $target] $target $history]
		}
		default { error "unknown TD command '$command'" }
	}
	dict set state updated [clock seconds]
	return [list $state $result $target $history]
}

# vi:set ts=3 sw=3:
