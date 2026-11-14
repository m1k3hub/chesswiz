# ======================================================================
# Tournament event scheduler, recovery, assistant completion and observers.
# Persistence is serialized through td-command; every runner result is an
# attempt-scoped, idempotent command.
# ======================================================================

if {[llength [info commands ::util::source]]} { ::util::source td-event }
package require Tcl 8.6

namespace eval ::td::event {
	variable Runs [dict create]
	variable Pending [dict create]
	variable Observers [dict create]
}

proc ::td::event::dg {d key {default {}}} { if {[dict exists $d $key]} { return [dict get $d $key] }; return $default }
proc ::td::event::EnginesOnly {state} { foreach p [dg $state players {}] { if {[dict get $p kind] ne "engine"} { return 0 } }; return 1 }

proc ::td::event::Commit {path command domain key} {
	set info [::td::store::Read $path]
	set args [dict merge $domain [dict create path $path commit 0 expected_revision [dict get $info revision] idempotency $key]]
	set preview [::td::command::Execute $command $args]
	dict set args commit 1
	set result [::td::command::Execute $command $args]
	if {[dict exists $result state]} { Notify $path [dict get $result state] }
	return $result
}

proc ::td::event::Execute {command arguments} {
	set path [::td::store::Resolve $arguments]
	set result [::td::command::Execute $command $arguments]
	if {![dg $result commit 0] || [dg $result idempotent 0]} { return $result }
	set state [dg $result state {}]
	if {$command eq "stop"} { StopRunners $path }
	if {$command eq "withdraw"} { StopRunners $path 1 }
	if {$command in {create start pair_round} && [dg $state status setup] eq "active" && [EnginesOnly $state]} {
		SchedulePump $path
	}
	if {$command eq "advance" && [dg $state status setup] eq "finished"} { ResolveAssistant $path }
	Notify $path $state
	return $result
}

proc ::td::event::WaitForAssistant {path result} {
	set state [dg $result state {}]
	if {![dg $result commit 0] || [dg $result idempotent 0] || [dg $state status setup] ne "active" || ![EnginesOnly $state]} { return $result }
	if {![info exists ::application::assistant::Priv(busy)] || !$::application::assistant::Priv(busy)} { return $result }
	if {![llength [info commands ::application::assistant::Later]]} { return $result }
	variable Pending
	set token [::application::assistant::Later]
	dict set Pending $token $path
	return $token
}

proc ::td::event::ResolveAssistant {path} {
	variable Pending
	foreach token [dict keys $Pending] {
		if {[dict get $Pending $token] ne $path} { continue }
		dict unset Pending $token
		set state [dict get [::td::store::Read $path] state]
		set rows [::td::score::Compute $state]
		set reply "Tournament '[dict get $state name]' finished.\n[::td::score::StandingsText $rows]"
		catch {::application::assistant::Resolve $token $reply}
	}
}

proc ::td::event::StopRunners {path {onlyFinished 0}} {
	variable Runs
	if {!$onlyFinished} { after cancel [list ::td::event::Pump $path] }
	if {![dict exists $Runs $path]} { if {!$onlyFinished} { ResolveStopped $path }; return }
	set run [dict get $Runs $path]
	dict for {pairing id} [dg $run handles {}] {
		if {$onlyFinished} {
			set state [dict get [::td::store::Read $path] state]
			set keep 0
			foreach q [dg $state pairings {}] { if {[dict get $q id] eq $pairing && [dg $q status pending] eq "running"} { set keep 1 } }
			if {$keep} { continue }
		}
		catch {::td::runner::Release $id}
		dict unset run handles $pairing
	}
	dict set Runs $path $run
	if {!$onlyFinished} { ResolveStopped $path }
}

proc ::td::event::ResolveStopped {path} {
	variable Pending
	foreach token [dict keys $Pending] {
		if {[dict get $Pending $token] eq $path} {
			dict unset Pending $token
			catch {::application::assistant::Resolve $token "error: tournament stopped; completed games are preserved"}
		}
	}
}

proc ::td::event::HashBudget {state} {
	set concurrency [expr {max(1, [dg $state concurrency 1])}]
	set total 2048
	catch {set total [::engine::MemTotal]}
	return [expr {max(1,min(16,$total/(4*$concurrency)))}]
}

proc ::td::event::StartPairing {path p} {
	set state [dict get [::td::store::Read $path] state]
	set pairing [dict get $p id]
	set committed [Commit $path mark_running [dict create pairing $pairing] "running:$pairing:[expr {[dg $p attempt 0]+1}]"]
	set marked [dg $committed state $state]
	set index [::td::model::FindPairing $marked [dict create pairing $pairing]]
	set p [lindex [dict get $marked pairings] $index]
	set attempt [dict get $p attempt]
	set white [dict get [::td::model::Player $marked [dict get $p white]] engine]
	set black [dict get [::td::model::Player $marked [dict get $p black]] engine]
	set tc [dict get $marked time_control]
	set spec [list -white $white -black $black -opening [dg $p opening {}] \
		-base $::scidb::clipbaseName -event [dict get $marked name] -round [dict get $p round] \
		-game_id [dict get $p game_id] -base_ms [dict get $tc base_ms] -increment_ms [dict get $tc increment_ms] \
		-overhead_ms [dg $marked overhead_ms 100] -max_plies [dg $marked max_plies 0] \
		-tb [dg $marked tablebase 0] -online 0 -threads [dg $marked threads 1] -hash [HashBudget $marked] \
		-onComplete [list ::td::event::OnComplete $path $pairing $attempt]]
	if {[catch {::td::runner::Start $spec} id err]} {
		Commit $path complete [dict create pairing $pairing attempt $attempt result 0-0 category double-forfeit played 0 termination abandoned pgn {}] \
			"result:$pairing:$attempt"
		SchedulePump $path
		return {}
	}
	variable Runs
	set run [dg $Runs $path [dict create handles {}]]
	if {[dict exists [::td::runner::Status $id] active] && ![dict get [::td::runner::Status $id] active]} { return $id }
	dict set run handles $pairing $id
	dict set Runs $path $run
	return $id
}

proc ::td::event::OnComplete {path pairing attempt id outcome} {
	variable Runs
	if {[dict exists $Runs $path]} {
		set run [dict get $Runs $path]
		if {[dict exists $run handles $pairing]} { dict unset run handles $pairing }
		dict set Runs $path $run
	}
	set domain [dict create pairing $pairing attempt $attempt result [dict get $outcome result] \
		termination [dict get $outcome termination] played [expr {[dict get $outcome result] ne "*"}] category played pgn [dg $outcome pgn {}]]
	if {[catch {Commit $path complete $domain "result:$pairing:$attempt"} result]} {
		# A recovered/stopped/replaced attempt cannot write a duplicate result.
		::td::runner::Release $id
		return
	}
	::td::runner::Release $id
	SchedulePump $path
}

proc ::td::event::SchedulePump {path} {
	after cancel [list ::td::event::Pump $path]
	after idle [list ::td::event::Pump $path]
}

proc ::td::event::Pump {path} {
	if {[catch {PumpBody $path} err]} {
		variable Pending
		foreach token [dict keys $Pending] {
			if {[dict get $Pending $token] eq $path} {
			dict unset Pending $token
			catch {::application::assistant::Resolve $token "error: $err"}
			}
		}
	}
}

proc ::td::event::PumpBody {path} {
	set state [dict get [::td::store::Read $path] state]
	if {[dg $state status setup] ne "active" || ![EnginesOnly $state]} { return }
	set round [dg $state current_round 1]
	if {$round > [dg $state rounds 0]} {
		if {[dg $state status setup] ne "finished"} { Execute finish [dict create path $path commit 1 expected_revision [dict get $state revision] idempotency "finish:[dict get $state revision]"] }
		ResolveAssistant $path
		return
	}
	set pending {}
	set running 0
	set roundDone 1
	foreach p [::td::model::Pairings $state $round] {
		if {[::td::model::IsBye $p]} { continue }
		switch -- [dg $p status pending] {
			pending - failed { lappend pending $p }
			running { incr running }
			default {}
		}
		if {[dg $p status pending] ne "complete"} { set roundDone 0 }
	}
	if {$roundDone && ![llength $pending] && !$running} {
		set committed [Commit $path advance [dict create round $round] "advance:$round:[dict get $state revision]"]
		set state [dict get $committed state]
		if {[dg $state status setup] eq "finished"} { ResolveAssistant $path; return }
		SchedulePump $path
		return
	}
	set available [expr {max(1, [dg $state concurrency 2]) - $running}]
	foreach p $pending {
		if {$available <= 0} { break }
		StartPairing $path $p
		incr available -1
	}
}

proc ::td::event::Open {path} {
	set path [file normalize $path]
	set info [::td::store::Read $path]
	set state [dict get $info state]
	if {$state eq ""} { error "no tournament exists at $path" }
	set running 0
	foreach p [dg $state pairings {}] { if {[dg $p status pending] eq "running"} { incr running } }
	if {$running} {
		set result [Commit $path recover {} "recover:[llength [dict get $info records]]"]
		set state [dict get $result state]
	}
	::td::store::Register $state $path
	::td::store::SetCurrent $path
	Notify $path $state
	return $state
}

proc ::td::event::Status {path} {
	set info [::td::store::Read $path]
	set state [dict get $info state]
	if {$state eq ""} { error "no tournament exists at $path" }
	set counts [dict create pending 0 running 0 complete 0]
	foreach p [dg $state pairings {}] { if {[dict exists $counts [dg $p status pending]]} { dict incr counts [dg $p status pending] } }
	return [dict create event [dict get $state id] path $path name [dict get $state name] revision [dict get $state revision] \
		status [dict get $state status] current_round [dg $state current_round 1] rounds [dg $state rounds 0] counts $counts \
		players [llength [dg $state players {}]] backend [::td::store::Backend] undo [llength [dict get $info undo]] redo [llength [dict get $info redo]]]
}

proc ::td::event::ExportPGN {path filename} {
	set state [dict get [::td::store::Read $path] state]
	set out [open $filename w]
	fconfigure $out -encoding utf-8 -translation lf
	foreach game [dg $state games {}] { puts $out [dg $game pgn {}] }
	close $out
	return [dict create filename $filename games [llength [dg $state games {}]]]
}

proc ::td::event::Observe {path command} { variable Observers; dict lappend Observers $path $command }
proc ::td::event::Unobserve {path command} { variable Observers; set rows [dg $Observers $path {}]; dict set Observers $path [lsearch -all -inline -not -exact $rows $command] }
proc ::td::event::Notify {path state} {
	variable Observers
	foreach command [dg $Observers $path {}] { catch {uplevel #0 [list {*}$command $path $state]} }
	if {[llength [info commands ::td::ui::RefreshPath]]} { catch {::td::ui::RefreshPath $path} }
}

proc ::td::event::Shutdown {} {
	variable Runs
	foreach path [dict keys $Runs] { StopRunners $path }
	::td::runner::StopAll
}

# vi:set ts=3 sw=3:
