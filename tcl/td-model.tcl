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
	if {$result ni {1-0 0-1 1/2-1/2 0-0}} { error "invalid result '$result'" }
	set category [dg $domain category played]
	if {$category ni {played forfeit forfeit-loss double-forfeit}} { error "invalid manual result category '$category'" }
	if {$category eq "double-forfeit"} { set result 0-0 }
	if {$category in {forfeit forfeit-loss double-forfeit}} { dict set p played 0 } else { dict set p played 1 }
	if {[dg $p result *] ni {* {}}} {
		dict lappend p result_history [dict create result [dict get $p result] category [dg $p category played] corrected [clock seconds]]
	}
	dict set p result $result
	dict set p category $category
	dict set p status complete
	dict set p termination [expr {$category eq "played" ? "normal" : "abandoned"}]
	dict set p count_standings 1
	dict set p rating [dict get $p played]
	lset pairings $index $p
	dict set state pairings $pairings
	set state [PublishCorrection $state]
	return [list $state [dict create entered 1 corrected $correct pairing [dict get $p id] result $result] {} 1]
}

proc ::td::model::Withdraw {state domain} {
	set id [FindPlayer $state [dg $domain player {}]]
	set round [dg $domain round [dg $state current_round 1]]
	set pairings [dg $state pairings {}]
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
				unrated_policy [dg $domain unrated_policy drop] publication_revision 0 published 0 publications {} withdrawals {} \
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
		register {
			if {[dg $state status setup] ne "setup" || [llength [dg $state pairings {}]]} { error "registration is closed after pairing starts" }
			set players [MakePlayers [dg $domain players {}] [dg $domain kind human] [expr {[llength [dg $state players {}]]+1}]]
			dict lappend state players {*}$players
			dict set state rounds [Rounds [llength [dict get $state players]] [Double [dict get $state system]]]
			return [list $state [dict create registered [llength $players]] $target $history]
		}
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
			set white [FindPlayer $state [dg $domain white {}]]
			set black [FindPlayer $state [dg $domain black {}]]
			if {$white eq $black} { error "a player cannot play itself" }
			set reason [string trim [dg $domain reason {}]]
			if {$reason eq ""} { error "a pairing override requires a reason" }
			dict set p override [dict create white [dict get $p white] black [dict get $p black] reason $reason created [clock seconds]]
			dict set p white $white
			dict set p black $black
			lset pairings $index $p
			dict set state pairings $pairings
			return [list $state [dict create overridden [dict get $p id]] $target $history]
		}
		withdraw { return [Withdraw $state $domain] }
		bye {
			set id [FindPlayer $state [dg $domain player {}]]
			set category [dg $domain category requested-bye]
			if {$category ni {requested-bye full-point-bye pairing-bye}} { error "invalid bye category" }
			set points [dg $domain points [expr {$category eq "requested-bye" ? 1 : 2}]]
			set round [dg $domain round [dg $state current_round 1]]
			set p [dict create id "bye-$id-r$round-[llength [dg $state pairings {}]]" round $round board 0 white $id black {} result * status complete \
				category $category played 0 count_standings 1 rating 0 points $points attempt 0 game_id {} pgn {}]
			dict lappend state pairings $p
			return [list $state [dict create bye $id round $round] $target $history]
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
			if {[dict get $record command] eq "create"} { error "cannot undo event creation" }
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
