# Tournament Director P0/P1 store, commands, scoring and workspace tests.
package require tcltest 2.5

namespace eval ::scidb::test::td {
	namespace export *
	variable Dir [file join [file dirname [file normalize [info script]]] tmp-app td-store-[pid]]
	variable Counter 0
}
proc ::scidb::test::td::fresh {} { variable Dir; variable Counter; file mkdir $Dir; return [file join $Dir event-[incr Counter].tdj] }
proc ::scidb::test::td::call {id arguments} { return [::knowledge::RunAction $id $arguments] }
proc ::scidb::test::td::commit {id arguments} {
	set reply [call $id $arguments]
	if {[string match "error:*" $reply]} { error $reply }
	return $reply
}
proc ::scidb::test::td::create {path names {start 0}} {
	return [commit td.create [dict create path $path name {Generated TD test} kind human players $names start $start opening {} system round-robin \
		time_control 3+2 tablebase 0 commit 1 expected_revision 0 idempotency "create-[pid]-[incr ::scidb::test::td::Counter]"]]
}
proc ::scidb::test::td::revision {path} { return [dict get [::td::store::Read $path] revision] }
proc ::scidb::test::td::mutate {id path domain} {
	variable Counter
	return [commit $id [dict merge $domain [dict create path $path expected_revision [revision $path] commit 1 idempotency "$id-[pid]-[incr Counter]"]]]
}
proc ::scidb::test::td::pairAll {path} { return [mutate td.pair_round $path {round 0}] }
proc ::scidb::test::td::enter {path pairing result} { return [mutate td.enter_result $path [dict create pairing $pairing result $result category played]] }
proc ::scidb::test::td::state {path} { return [dict get [::td::store::Read $path] state] }
proc ::scidb::test::td::standingsText {path} { return [::td::score::StandingsText [::td::score::Compute [state $path]]] }
namespace import ::scidb::test::td::*

tcltest::test td-preview-idempotency-adversarial {preview is clean; replay/stale/key mismatch and adversarial names are safe} -body {
	set path [fresh]
	set names [list "A\nnewline" "B \} brace" {C "quote"} "D\\backslash"]
	set key "create-adversarial-[pid]"
	set args [dict create path $path name "Event\n{*}[]\"'" kind human players $names start 0 opening {} tablebase 0 commit 0 expected_revision 0 idempotency $key]
	set preview [call td.create $args]
	set existsBefore [file exists $path]
	dict set args commit 1
	set created [commit td.create $args]
	set replay [commit td.create $args]
	set mismatch [call td.create [dict replace $args name Different]]
	set stale [call td.pair_round [dict create path $path round 0 commit 1 expected_revision 0 idempotency stale-pair]]
	set loaded [dict get [::td::store::Read $path] state]
	list [dict get $preview preview] $existsBefore [dict get $created revision] [dict get $replay idempotent] \
		[llength [::td::store::Audit $path]] [string match *different* $mismatch] [string match *stale* $stale] \
		[expr {[lmap p [dict get $loaded players] {dict get $p name}] eq $names}] [dict get $loaded name]
} -result [list 1 0 1 1 1 1 1 1 "Event\n{*}[]\"'"]

tcltest::test td-capability-gate {td actions are refused when capability is absent} -setup {
	::capability::Override td 0
} -body {
	::knowledge::RunAction td.status {}
} -cleanup {
	::capability::ClearOverrides
} -match glob -result {error:*td*unavailable*}

tcltest::test td-berger-exact {Berger tables match C.05 annex order and colours} -body {
	set players {}
	for {set i 1} {$i <= 10} {incr i} { lappend players [dict create id p$i number $i name P$i] }
	set pairings [::td::pair::RoundRobin $players 0]
	set rounds [dict create]
	foreach p $pairings { dict lappend rounds [dict get $p round] "[dict get $p white]-[dict get $p black]" }
	list [dict get $rounds 1] [dict get $rounds 2] [dict get $rounds 9] [::td::pair::Validate $players $pairings 0]
} -result {{p1-p10 p2-p9 p3-p8 p4-p7 p5-p6} {p10-p6 p7-p5 p8-p4 p9-p3 p1-p2} {p5-p10 p6-p4 p7-p3 p8-p2 p9-p1} {}}

tcltest::test td-standings-exact {C.07 values, direct encounter and breakdowns match independent arithmetic} -body {
	set path [fresh]
	create $path {A B C D}
	pairAll $path
	foreach {id result} {r1b0 1/2-1/2 r1b1 1-0 r2b0 0-1 r2b1 1-0 r3b0 0-1 r3b1 0-1} { enter $path $id $result }
	set rows [::td::score::Compute [state $path]]
	set out {}
	foreach row $rows {
		lappend out [list [dict get $row name] [dict get $row score text] [dict get $row tiebreaks sonnebornBerger text] \
			[dict get $row tiebreaks directEncounter text] [dict get $row tiebreaks progressive text] \
			[llength [dict get $row score breakdown]]]
	}
	return $out
} -result {{A 2.5 2.75 0 4.5 3} {D 1.5 2.25 0 2.5 3} {B 1 1 1 3 3} {C 1 1.5 0 2 3}}

tcltest::test td-publication-undo-redo {correction creates publication revision and Ask replay undo/redo is byte-identical} -body {
	set path [fresh]
	create $path {A B C D}
	pairAll $path
	foreach {id result} {r1b0 1/2-1/2 r1b1 1-0 r2b0 0-1 r2b1 1-0 r3b0 0-1 r3b1 0-1} { enter $path $id $result }
	set before [standingsText $path]
	mutate td.publish $path {}
	set published [state $path]
	mutate td.correct_result $path {pairing r1b1 result 0-1 category played}
	set correctedState [state $path]
	set corrected [standingsText $path]
	mutate td.undo $path {}
	set undone [standingsText $path]
	mutate td.redo $path {}
	set redone [standingsText $path]
	list [dict get $published publication_revision] [dict get $correctedState publication_revision] \
		[llength [dict get $correctedState publications]] [expr {$before ne $corrected}] \
		[expr {$before eq $undone}] [expr {$corrected eq $redone}]
} -result {1 2 2 1 1 1}

tcltest::test td-withdraw-annulled {RR withdrawal below 50 percent annuls standings but preserves played history} -body {
	set path [fresh]
	set names {}
	for {set i 1} {$i <= 10} {incr i} { lappend names P$i }
	create $path $names
	pairAll $path
	foreach p [::td::model::Pairings [state $path] 0] {
		if {[dict get $p round] <= 4 && ![::td::model::IsBye $p]} { enter $path [dict get $p id] 1/2-1/2 }
	}
	set result [mutate td.withdraw $path {player p1 round 5}]
	set state [state $path]
	set pastAnnulled 0
	set futureAnnulled 0
	foreach p [dict get $state pairings] {
		if {[dict get $p white] ne "p1" && [dict get $p black] ne "p1"} { continue }
		if {[dict get $p round] <= 4 && [dict get $p category] eq "annulled"} { incr pastAnnulled }
		if {[dict get $p round] > 4 && [dict get $p category] eq "withdrawal-annulled" && ![dict get $p count_standings]} { incr futureAnnulled }
	}
	list [dict get $result policy] $pastAnnulled $futureAnnulled [llength [dict get $state withdrawals]]
} -result {annulled 4 5 1}

tcltest::test td-withdraw-forfeits {RR withdrawal at 50 percent preserves results and forfeits remaining games} -body {
	set path [fresh]
	set names {}
	for {set i 1} {$i <= 10} {incr i} { lappend names P$i }
	create $path $names
	pairAll $path
	foreach p [::td::model::Pairings [state $path] 0] {
		if {[dict get $p round] <= 6 && ![::td::model::IsBye $p]} { enter $path [dict get $p id] 1/2-1/2 }
	}
	set result [mutate td.withdraw $path {player p1 round 7}]
	set state [state $path]
	set forfeits 0
	foreach p [dict get $state pairings] {
		if {[dict get $p round] > 6 && ([dict get $p white] eq "p1" || [dict get $p black] eq "p1") && [dict get $p category] eq "forfeit"} {
			if {([dict get $p white] eq "p1" && [dict get $p result] eq "0-1") || ([dict get $p black] eq "p1" && [dict get $p result] eq "1-0")} { incr forfeits }
		}
	}
	list [dict get $result policy] $forfeits
} -result {forfeits 3}

tcltest::test td-tail-recovery {a partial final write is ignored, repaired before append, and never loses committed state} -body {
	set path [fresh]
	create $path {A B C D}
	pairAll $path
	set before [standingsText $path]
	set out [open $path ab]; puts -nonewline $out "1 2 partial"; close $out
	set info [::td::store::Read $path]
	set recovered [dict get $info repair]
	enter $path r1b0 1-0
	set after [standingsText $path]
	set records [::td::store::Audit $path]
	list $recovered [expr {$before ne $after}] [dict get [lindex $records end] command] [dict get [lindex $records end] revision]
} -result {1 1 enter_result 3}

tcltest::test td-swiss-dummy {C.07 16.4 dummy caps are exact rationals} -body {
	list [::td::score::DummyScore {12 1} 9 pairing-bye {}] \
		[::td::score::DummyScore {7 1} 9 pairing-bye {}] \
		[::td::score::DummyScore {12 1} 9 forfeit {7 1}]
} -result {{9 1} {7 1} {7 1}}

tcltest::test td-workspace {all five TD tabs and journal crosstable are reachable through actions} -body {
	set path [fresh]
	create $path {A B C D}
	pairAll $path
	set dlg [commit td.workspace [dict create operation open path $path tab players]]
	set tabs [winfo children $dlg.tabs]
	commit td.workspace {operation select tab standings}
	set selected [$dlg.tabs select]
	set cross [commit td.crosstable [dict create path $path open 1]]
	set window [dict get $cross window]
	set exists [winfo exists $window]
	::crosstable::RefreshTD $window.top.canv.html $path
	destroy $window
	commit td.workspace {operation close}
	list [llength $tabs] $selected $exists [winfo exists $dlg]
} -result {5 .application.tournamentDirector.tabs.standings 1 0}

tcltest::test td-workspace-buttons {workspace buttons commit through Mutate with the current revision} -body {
	set path [fresh]
	create $path {A B C D}
	commit td.workspace [dict create operation open path $path tab pairings]
	set r0 [dict get [state $path] revision]
	set ::td::ui::Fields(pair_round) 1
	::td::ui::PairRound
	set r1 [dict get [state $path] revision]
	::td::ui::Undo
	set r2 [dict get [state $path] revision]
	commit td.workspace {operation close}
	list [expr {$r1 > $r0}] [expr {$r2 > $r1}]
} -result {1 1}

tcltest::test td-withdraw-combined {single 10-player RR event with withdrawal after round 4 (<50% annulled) and round 6 (>=50% forfeits)} -body {
	set path [fresh]
	set names {}
	for {set i 1} {$i <= 10} {incr i} { lappend names P$i }
	create $path $names
	pairAll $path
	foreach p [::td::model::Pairings [state $path] 0] {
		if {[dict get $p round] <= 4 && ![::td::model::IsBye $p]} { enter $path [dict get $p id] 1/2-1/2 }
	}
	set w1 [mutate td.withdraw $path {player p1 round 5}]
	foreach p [::td::model::Pairings [state $path] 0] {
		if {[dict get $p round] in {5 6} && [dict get $p status] eq "pending" && ![::td::model::IsBye $p]} {
			enter $path [dict get $p id] 1/2-1/2
		}
	}
	set w2 [mutate td.withdraw $path {player p2 round 7}]
	set st [state $path]
	set p1Annulled 0
	set p1FutureAnnulled 0
	set p2Forfeits 0
	foreach p [dict get $st pairings] {
		if {[dict get $p white] eq "p1" || [dict get $p black] eq "p1"} {
			if {[dict get $p round] <= 4 && [dict get $p category] eq "annulled" && ![dict get $p count_standings]} { incr p1Annulled }
			if {[dict get $p round] > 4 && [dict get $p category] eq "withdrawal-annulled" && ![dict get $p count_standings]} { incr p1FutureAnnulled }
		}
		if {[dict get $p round] > 6 && ([dict get $p white] eq "p2" || [dict get $p black] eq "p2") && [dict get $p category] eq "forfeit"} {
			if {([dict get $p white] eq "p2" && [dict get $p result] eq "0-1") || ([dict get $p black] eq "p2" && [dict get $p result] eq "1-0")} { incr p2Forfeits }
		}
	}
	list [dict get $w1 policy] [dict get $w2 policy] $p1Annulled $p1FutureAnnulled $p2Forfeits [llength [dict get $st withdrawals]]
} -result {annulled forfeits 4 5 3 2}

tcltest::test td-interrupt-every-boundary {interrupt or truncation at every persistence boundary recovers consistently without losing prior commits} -body {
	set path [fresh]
	create $path {A B C D}
	pairAll $path
	enter $path r1b0 1-0
	enter $path r1b1 0-1
	mutate td.publish $path {}
	mutate td.correct_result $path {pairing r1b0 result 1/2-1/2 category played}
	mutate td.undo $path {}
	mutate td.redo $path {}
	set chan [open $path rb]
	set full [read $chan]
	close $chan
	set lines [split [string trimright $full "\n"] "\n"]
	set header "[lindex $lines 0]\n"
	set recordLines [lrange $lines 1 end]
	set count [llength $recordLines]
	set ok 1
	for {set k 1} {$k <= $count} {incr k} {
		set prefix $header
		if {$k > 1} {
			append prefix "[join [lrange $recordLines 0 [expr {$k-2}]] "\n"]\n"
		}
		set targetLine [lindex $recordLines [expr {$k-1}]]
		foreach cut [list 0 1 5 [expr {[string length $targetLine]/2}] [expr {[string length $targetLine]-1}]] {
			set tpath [fresh]
			set out [open $tpath wb]
			set tail [expr {$cut > 0 ? [string range $targetLine 0 [expr {$cut-1}]] : ""}]
			puts -nonewline $out $prefix$tail
			close $out
			set info [::td::store::Read $tpath]
			if {[dict get $info revision] != $k - 1} { set ok 0 }
			if {$cut > 0 && ![dict get $info repair]} { set ok 0 }
			if {$k > 1} {
				set st [dict get $info state]
				if {[dict get $st id] eq ""} { set ok 0 }
			}
		}
	}
	list $count $ok
} -result {8 1}

proc ::scidb::test::td::makeMockEngine {scriptPath mode} {
	file mkdir [file dirname $scriptPath]
	set f [open $scriptPath w]
	fconfigure $f -translation lf
	puts $f "#!/usr/bin/env tclsh"
	puts $f "fconfigure stdin -buffering line"
	puts $f "fconfigure stdout -buffering line"
	puts $f [format {set mode %s} [list $mode]]
	puts $f {
		if {$mode eq "hang"} {
			while {[gets stdin line] >= 0} {
				if {$line eq "uci"} { puts "id name HangMock"; puts "uciok" }
				if {$line eq "isready"} { puts "readyok" }
				if {$line eq "quit"} { exit 0 }
			}
			exit 0
		}
		while {[gets stdin line] >= 0} {
			switch -glob -- $line {
				uci {
					puts "id name FastMock"
					puts "option name Threads type spin default 1 min 1 max 16"
					puts "option name Hash type spin default 16 min 1 max 1024"
					puts "option name Move Overhead type spin default 10 min 0 max 5000"
					puts "uciok"
				}
				isready { puts "readyok" }
				position* {
					set fen [lrange $line 2 end]
					set stm [lindex $fen 1]
				}
				go* {
					puts "info depth 4 score cp 950"
					if {$stm eq "w"} {
						if {![info exists wtoggle] || !$wtoggle} {
							set wtoggle 1
							puts "bestmove g1h3"
						} else {
							set wtoggle 0
							puts "bestmove h3g1"
						}
					} else {
						if {![info exists btoggle] || !$btoggle} {
							set btoggle 1
							puts "bestmove g8h6"
						} else {
							set btoggle 0
							puts "bestmove h6g8"
						}
					}
				}
				quit { exit 0 }
			}
		}
	}
	close $f
	file attributes $scriptPath -permissions 0o755
}

tcltest::test td-ask-london-double-rr {Ask prompt runs a thematic London System 3+2 double round robin between 4 engines to completion} -setup {
	catch { update }
	::application::assistant::show
	catch { update }
	set savedEngines $::engine::Engines
	set savedConfirm $::application::assistant::Priv(confirm)
	set mockPath [file join $::scidb::test::td::Dir fast-mock.tcl]
	::scidb::test::td::makeMockEngine $mockPath fast
	set ::engine::Engines [list [dict merge $::engine::EmptyEngine [dict create Name FastMock Identifier fastmock Command $mockPath Parameters {} Protocol {UCI}]]]
} -body {
	set path [fresh]
	set prompt "run a thematic London System 3+2 double round robin between 4 engines"
	set callMsg [dict create role assistant content "" tool_calls [list [dict create function [dict create name td.create arguments [dict create \
		path $path name {London Double RR} system double-round-robin kind engine engine_count 4 time_control 3+2 opening {London System} \
		concurrency 4 max_plies 10 tablebase 0 start 1 commit 1 expected_revision 0 idempotency "ask-london-[pid]"]]]]]
	set finalMsg [dict create role assistant content "The London System double round robin finished and standings are recorded."]
	set cfg ::application::ai::Config
	set savedProvider [array get $cfg provider]
	set ${cfg}(provider) stub
	::ai::provider::configure -name stub -chatResponses [list $callMsg $finalMsg]
	::application::assistant::ask $prompt
	set deadline [expr {[clock milliseconds] + 20000}]
	while {$::application::assistant::Priv(busy) && [clock milliseconds] < $deadline} {
		vwait ::application::assistant::Priv(busy)
	}
	array set $cfg $savedProvider
	set st [state $path]
	set games [dict get $st games]
	set expectedLine [lindex [dict get $st opening] 0]
	set allLondon [expr {[llength $expectedLine] > 0}]
	foreach g $games {
		set movetext {}
		foreach line [split [dict get $g pgn] "\n"] {
			if {![string match {\[*} [string trim $line]]} { append movetext $line "\n" }
		}
		set parsed [::enginematch::parsePgnMoves $movetext [llength $expectedLine]]
		if {$parsed ne $expectedLine} {
			set allLondon 0
		}
	}
	set rows [::td::score::Compute $st]
	list [dict get $st status] [llength [dict get $st players]] [dict get $st rounds] [llength $games] $allLondon [llength $rows]
} -cleanup {
	::td::event::Shutdown
	catch {::application::assistant::clear}
	catch { update }
	set ::engine::Engines $savedEngines
	set ::application::assistant::Priv(confirm) $savedConfirm
} -result {finished 4 6 12 1 4}

tcltest::test td-jitter-50-games-n8 {50 games at 0+0.1 with N=8 using instant mock engine has 0 false flag falls} -setup {
	set savedEngines $::engine::Engines
	set mockPath [file join $::scidb::test::td::Dir jitter-mock.tcl]
	::scidb::test::td::makeMockEngine $mockPath fast
	set ::engine::Engines [list [dict merge $::engine::EmptyEngine [dict create Name JitterMock Identifier jittermock Command $mockPath Parameters {} Protocol {UCI}]]]
} -body {
	set total 50
	set concurrency 8
	set started 0
	set completed 0
	set running 0
	set timeForfeits 0
	set ::scidb::test::td::jitterDone 0
	proc ::scidb::test::td::pumpJitter {} {
		upvar 1 total total concurrency concurrency started started completed completed running running timeForfeits timeForfeits
		while {$running < $concurrency && $started < $total} {
			incr started
			incr running
			::td::runner::Start [list -white JitterMock -black "JitterMock #2" -base {} -event JitterTest -round $started \
				-base_ms 100 -increment_ms 100 -overhead_ms 100 -max_plies 2 -tb 0 -online 0 -threads 1 -hash 1 \
				-onComplete ::scidb::test::td::onJitterComplete]
		}
	}
	proc ::scidb::test::td::onJitterComplete {id outcome} {
		::td::runner::Release $id
		upvar #0 ::scidb::test::td::jitterState JS
		incr JS(running) -1
		incr JS(completed)
		if {[dict get $outcome termination] eq "time"} { incr JS(timeForfeits) }
		if {$JS(completed) >= $JS(total)} {
			set ::scidb::test::td::jitterDone 1
			return
		}
		while {$JS(running) < $JS(concurrency) && $JS(started) < $JS(total)} {
			incr JS(started)
			incr JS(running)
			::td::runner::Start [list -white JitterMock -black "JitterMock #2" -base {} -event JitterTest -round $JS(started) \
				-base_ms 100 -increment_ms 100 -overhead_ms 100 -max_plies 2 -tb 0 -online 0 -threads 1 -hash 1 \
				-onComplete ::scidb::test::td::onJitterComplete]
		}
	}
	array set ::scidb::test::td::jitterState [list total $total concurrency $concurrency started 0 completed 0 running 0 timeForfeits 0]
	for {set i 0} {$i < $concurrency} {incr i} {
		incr ::scidb::test::td::jitterState(started)
		incr ::scidb::test::td::jitterState(running)
		::td::runner::Start [list -white JitterMock -black "JitterMock #2" -base {} -event JitterTest -round $::scidb::test::td::jitterState(started) \
			-base_ms 100 -increment_ms 100 -overhead_ms 100 -max_plies 2 -tb 0 -online 0 -threads 1 -hash 1 \
			-onComplete ::scidb::test::td::onJitterComplete]
	}
	if {!$::scidb::test::td::jitterDone} {
		vwait ::scidb::test::td::jitterDone
	}
	list $::scidb::test::td::jitterState(completed) $::scidb::test::td::jitterState(timeForfeits)
} -cleanup {
	::td::runner::StopAll
	unset -nocomplain ::scidb::test::td::jitterState ::scidb::test::td::jitterDone
	set ::engine::Engines $savedEngines
} -result {50 0}

tcltest::test td-sigkill-mid-round-recovery {SIGKILL in middle of a round with 4 games running preserves completed games and finishes with no missing or duplicate results} -setup {
	set savedEngines $::engine::Engines
	set fastPath [file join $::scidb::test::td::Dir sig-fast.tcl]
	set hangPath [file join $::scidb::test::td::Dir sig-hang.tcl]
	::scidb::test::td::makeMockEngine $fastPath fast
	::scidb::test::td::makeMockEngine $hangPath hang
	set ::engine::Engines [list \
		[dict merge $::engine::EmptyEngine [dict create Name FastSig Identifier fastsig Command $fastPath Parameters {} Protocol {UCI}]] \
		[dict merge $::engine::EmptyEngine [dict create Name HangSig Identifier hangsig Command $hangPath Parameters {} Protocol {UCI}]]]
} -body {
	set path [fresh]
	# 8 engines -> 4 boards in round 1: p1-p8, p2-p7, p3-p6, p4-p5.
	# Make p1,p8,p2,p7 FastSig so boards 1 and 2 complete quickly, and p3..p6 HangSig so boards 3 and 4 stay running.
	commit td.create [dict create path $path name {SIGKILL Recovery} system round-robin kind engine \
		engines {FastSig FastSig HangSig HangSig HangSig HangSig FastSig FastSig} engine_count 0 \
		time_control 3+2 concurrency 4 max_plies 2 tablebase 0 start 1 commit 1 expected_revision 0 idempotency "sigkill-[pid]"]
	# Wait until 2 games in round 1 are complete and 2 are running.
	set deadline [expr {[clock milliseconds] + 10000}]
	while {[clock milliseconds] < $deadline} {
		update
		set st [state $path]
		set c 0
		set r 0
		foreach p [::td::model::Pairings $st 1] {
			if {[dict get $p status] eq "complete"} { incr c }
			if {[dict get $p status] eq "running"} { incr r }
		}
		if {$c >= 2 && $r >= 1} { break }
		after 20
	}
	set completedBefore [llength [dict get [state $path] games]]
	# Simulate abrupt SIGKILL of the running child processes and runner crash without normal stop.
	set killedPids {}
	foreach ns [namespace children ::td::runner] {
		if {![regexp {^game[0-9]+$} [namespace tail $ns]]} { continue }
		upvar 0 ${ns}::State S
		foreach side {w b} {
			if {$S(pipe:$side) ne ""} {
				catch {
					foreach p [pid $S(pipe:$side)] {
						exec kill -9 $p
						lappend killedPids $p
					}
				}
				catch {fileevent $S(pipe:$side) readable {}}
				catch {close $S(pipe:$side)}
				set S(pipe:$side) {}
			}
		}
		after cancel $S(watchdog)
		set S(active) 0
		::td::runner::Release [namespace tail $ns]
	}
	dict unset ::td::event::Runs $path
	# Switch HangSig to fast engine so recovery + resume can play to completion.
	set ::engine::Engines [list \
		[dict merge $::engine::EmptyEngine [dict create Name FastSig Identifier fastsig Command $fastPath Parameters {} Protocol {UCI}]] \
		[dict merge $::engine::EmptyEngine [dict create Name HangSig Identifier hangsig Command $fastPath Parameters {} Protocol {UCI}]]]
	set reopened [::td::event::Open $path]
	set statusAfterRecover [dict get $reopened status]
	mutate td.start $path {round 1}
	set deadline [expr {[clock milliseconds] + 20000}]
	while {[clock milliseconds] < $deadline} {
		update
		if {[dict get [state $path] status] eq "finished"} { break }
		after 20
	}
	set final [state $path]
	set pairings [dict get $final pairings]
	set games [dict get $final games]
	set seenPairings {}
	set dup 0
	foreach g $games {
		set pid [dict get $g pairing]
		if {$pid in $seenPairings} { set dup 1 }
		lappend seenPairings $pid
	}
	list [expr {$completedBefore >= 1}] $statusAfterRecover [dict get $final status] [llength $pairings] [llength $games] $dup
} -cleanup {
	::td::event::Shutdown
	update idletasks
	set ::engine::Engines $savedEngines
} -result {1 paused finished 28 28 0}

tcltest::test td-live-stockfish-smoke {live 4-engine Stockfish smoke run at 0+0.5 with threads=1 finishes cleanly} -setup {
	set sf [auto_execok stockfish]
	if {$sf eq "" && [file executable /usr/games/stockfish]} { set sf /usr/games/stockfish }
	set savedEngines $::engine::Engines
	set ::engine::Engines [list [dict merge $::engine::EmptyEngine [dict create Name StockfishLive Identifier stockfishlive Command $sf Parameters {} Protocol {UCI}]]]
} -body {
	set path [fresh]
	commit td.create [dict create path $path name {Stockfish Smoke} system round-robin kind engine engine_count 4 \
		time_control 0+0.5 opening {London System} concurrency 2 max_plies 8 tablebase 0 start 1 commit 1 expected_revision 0 idempotency "sf-smoke-[pid]"]
	set deadline [expr {[clock milliseconds] + 30000}]
	while {[clock milliseconds] < $deadline} {
		update
		if {[dict get [state $path] status] eq "finished"} { break }
		after 25
	}
	set final [state $path]
	set activeRunners 0
	foreach ns [namespace children ::td::runner] {
		if {[regexp {^game[0-9]+$} [namespace tail $ns]]} { incr activeRunners }
	}
	list [dict get $final status] [llength [dict get $final games]] [dict get $final threads] $activeRunners
} -cleanup {
	::td::event::Shutdown
	update idletasks
	set ::engine::Engines $savedEngines
} -result {finished 6 1 0}

tcltest::cleanupTests
catch { update }
catch {file delete -force $::scidb::test::td::Dir}
