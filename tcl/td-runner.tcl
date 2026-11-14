# ======================================================================
# Per-game UCI runner used by Tournament Director and Engine Match.
# Every running game owns a namespace, game slot, clocks, pipes and timers.
# No chess decision is delegated to a model; online tablebases are opt-in.
# ======================================================================

if {[llength [info commands ::util::source]]} { ::util::source td-runner }

package require Tcl 8.5
package require Tk 8.5

namespace eval ::td::runner {
	variable Counter 0
	variable NextSlot 200
	variable FreeSlots {}
	variable SentinelSlot 199
	variable StartFen {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}
	variable MoveTimeout 2000
	variable StartTimeout 30000
	variable MateCap 10000
	variable ResignCp 800
	variable ResignPlies 5
	variable DrawCp 10
	variable DrawPlies 10
	variable DrawMinMove 40
}

proc ::td::runner::Defaults {} {
	return [dict create \
		-white {} -black {} -pos -1 -base $::scidb::clipbaseName \
		-event {Engine match} -site ? -round 1 -game_id {} -opening {} \
		-base_ms 300000 -increment_ms 2000 -noclock 0 -movetime 1000 \
		-overhead_ms 0 -max_plies 0 -tb 1 -online 0 \
		-threads 0 -hash 0 -resign_plies 5 -draw_plies 10 -draw_min_move 40 \
		-request {} -connect {} -onComplete {} -onState {} -onStatus {} \
		-manage_subscriptions 1 -watch_switch 0]
}

proc ::td::runner::StateName {id} { return "::td::runner::${id}::State" }

proc ::td::runner::UseSlot {id} {
	upvar 0 [StateName $id] S
	if {$S(pos) >= 0 && [::scidb::game::current] != $S(pos)} {
		::scidb::game::switch $S(pos)
	}
}

proc ::td::runner::StateChanged {id args} {
	set ns "::td::runner::$id"
	if {![namespace exists $ns]} { return }
	upvar 0 ${ns}::State S
	if {$S(onState) ne ""} { catch { uplevel #0 [list {*}$S(onState) $id] } }
}

proc ::td::runner::Status {id} {
	set ns "::td::runner::$id"
	if {![namespace exists $ns]} { return {} }
	upvar 0 ${ns}::State S
	set out [dict create id $id]
	foreach key {active phase pos white black side token clock:w clock:b pipe:w pipe:b result termination reason saved} {
		if {[info exists S($key)]} { dict set out $key $S($key) }
	}
	dict set out pgn [expr {[info exists S(pgn)] && $S(pgn) ne "" ? $S(pgn) : ($S(phase) eq "over" && $S(pos) >= 0 ? [ExportPgn $id] : "")}]
	return $out
}

proc ::td::runner::ExportPgn {id} {
	upvar 0 [StateName $id] S
	set moves [expr {[info exists S(moves)] ? $S(moves) : {}}]
	set res [expr {[info exists S(result)] && $S(result) ne "" ? $S(result) : "*"}]
	set term [termTag [expr {[info exists S(termination)] ? $S(termination) : "normal"}]]
	set date [clock format [clock seconds] -format {%Y.%m.%d}]
	set tc [TimeControlText $S(noclock) $S(base_ms) $S(increment_ms) $S(movetime)]
	set lines [list \
		"\[Event \"$S(event)\"\]" \
		"\[Site \"$S(site)\"\]" \
		"\[Date \"$date\"\]" \
		"\[Round \"$S(round)\"\]" \
		"\[White \"$S(white)\"\]" \
		"\[Black \"$S(black)\"\]" \
		"\[Result \"$res\"\]" \
		"\[TimeControl \"$tc\"\]" \
		"\[Termination \"$term\"\]" \
		""]
	set movetext {}
	set plyIdx 0
	foreach san $moves {
		if {$plyIdx % 2 == 0} {
			lappend movetext "[expr {$plyIdx / 2 + 1}]. $san"
		} else {
			lappend movetext $san
		}
		incr plyIdx
	}
	lappend movetext $res
	lappend lines [join $movetext " "]
	return "[join $lines "\n"]\n"
}

proc ::td::runner::Snapshot {id} { return [Status $id] }

proc ::td::runner::EnsureSentinel {} {
	variable SentinelSlot
	if {[catch {::scidb::game::query $SentinelSlot open?} open] || !$open} {
		::scidb::game::new $SentinelSlot Normal
		::scidb::game::subscribe board $SentinelSlot ::td::runner::LogSink
	}
	return $SentinelSlot
}

proc ::td::runner::ClaimSlot {id} {
	variable NextSlot
	variable FreeSlots
	upvar 0 [StateName $id] S
	if {$S(pos) >= 0} {
		if {![catch {::scidb::game::query $S(pos) open?} open] && $open} {
			return $S(pos)
		}
	}
	EnsureSentinel
	while {[llength $FreeSlots]} {
		set pos [lindex $FreeSlots 0]
		set FreeSlots [lrange $FreeSlots 1 end]
		if {![catch {::scidb::game::query $pos open?} open] && $open} {
			if {[::scidb::game::current] == $pos} {
				catch {::scidb::game::switch [EnsureSentinel]}
			}
			catch {::scidb::game::release $pos}
		}
		::scidb::game::new $pos Normal
		set S(ownSlot) 1
		return $pos
	}
	set pos [incr NextSlot]
	while {![catch {::scidb::game::query $pos open?} open] && $open} {
		set pos [incr NextSlot]
	}
	::scidb::game::new $pos Normal
	set S(ownSlot) 1
	return $pos
}

proc ::td::runner::ReleaseSlot {id} {
	variable FreeSlots
	upvar 0 [StateName $id] S
	if {![info exists S(ownSlot)] || !$S(ownSlot) || $S(pos) < 0} { return }
	set pos $S(pos)
	set S(ownSlot) 0
	if {[::scidb::game::current] == $pos || [::scidb::game::current] < 0} {
		set switched 0
		foreach ns [namespace children ::td::runner] {
			if {![regexp {^game[0-9]+$} [namespace tail $ns]] || [namespace tail $ns] eq $id} { continue }
			upvar 0 ${ns}::State O
			if {[info exists O(pos)] && $O(pos) >= 0 && $O(pos) != $pos} {
				catch {::scidb::game::switch $O(pos)}
				if {[::scidb::game::current] == $O(pos)} { set switched 1; break }
			}
		}
		if {!$switched || [::scidb::game::current] == $pos} {
			catch {::scidb::game::switch [EnsureSentinel]}
		}
	}
	if {[::scidb::game::current] != $pos && ![catch {::scidb::game::query $pos open?} open] && $open} {
		catch {::scidb::game::release $pos}
	}
	if {$pos ni $FreeSlots} { lappend FreeSlots $pos }
}

proc ::td::runner::Start {spec} {
	variable Counter
	set cfg [dict merge [Defaults] $spec]
	foreach key {-white -black} {
		if {[string trim [dict get $cfg $key]] eq ""} { error "both engine seats are required" }
	}
	foreach seat {-white -black} {
		set base [EngineBase [dict get $cfg $seat]]
		if {$base ni [EngineNames]} { error "no UCI engine named '$base'" }
	}
	set id game[incr Counter]
	set ns "::td::runner::$id"
	namespace eval $ns {}
	upvar 0 ${ns}::State S
	array set S {
		active 0 busy 0 phase idle side w token 0 history {} moves {} tbLatch 0 ownSlot 0 pgn {}
		pending:w 0 pending:b 0 pipe:w {} pipe:b {} pipeState:w off pipeState:b off
		watchdog {} handshake:w {} handshake:b {} subscribed 0 result {} termination {} reason {} saved 0
	}
	dict for {key value} $cfg { set S([string range $key 1 end]) $value }
	set S(pos) [ClaimSlot $id]
	set S(clock:w) $S(base_ms)
	set S(clock:b) $S(base_ms)
	set S(minutes) [expr {$S(base_ms) / 60000.0}]
	set S(increment) [expr {$S(increment_ms) / 1000.0}]
	trace add variable ${ns}::State write [list ::td::runner::StateChanged $id]
	if {$S(manage_subscriptions)} {
		::scidb::game::subscribe board $S(pos) [list ::td::runner::Update $id]
		::scidb::db::subscribe gameClose [list ::td::runner::GameClosed $id]
		if {$S(watch_switch)} { ::scidb::db::subscribe gameSwitch [list ::td::runner::GameSwitched $id] }
		set S(subscribed) 1
	}
	UseSlot $id
	set S(active) 1
	Setup $id
	if {$S(phase) eq "play"} { StartTurn $id [::scidb::pos::stm] }
	return $id
}

proc ::td::runner::Setup {id} {
	variable StartFen
	upvar 0 [StateName $id] S
	UseSlot $id
	set S(phase) setup
	set S(moves) {}
	set S(busy) 1
	set failed [catch {
		::scidb::game::clear $StartFen
		foreach san $S(opening) {
			set before [::scidb::game::query length]
			if {[catch {::scidb::game::move $san}] || [::scidb::game::query length] == $before} {
				error "the opening holds the illegal move $san"
			}
			::scidb::game::go 1
			lappend S(moves) $san
		}
		::scidb::game::go end
	} err]
	set S(busy) 0
	if {$failed} { EndGame $id * abandoned $err; return }
	incr S(token)
	set S(phase) play
}

proc ::td::runner::Update {id position cmd data promoted} {
	upvar 0 [StateName $id] S
	if {!$S(active) || $S(busy) || $position != $S(pos) || $cmd ne "move"} { return }
	if {[llength $data] && ![lindex $data end]} { return }
	set S(busy) 1
	UseSlot $id
	::scidb::game::go -1
	::scidb::game::strip truncate
	set S(busy) 0
}

proc ::td::runner::GameClosed {id position} {
	upvar 0 [StateName $id] S
	if {$S(active) && $position == $S(pos)} { EndGame $id * abandoned "the game was closed" }
}

proc ::td::runner::GameSwitched {id oldPos newPos} {
	upvar 0 [StateName $id] S
	if {$S(active) && $S(pos) >= 0 && $newPos != $S(pos)} { EndGame $id * abandoned "another game was selected" }
}

proc ::td::runner::StartTurn {id side} {
	upvar 0 [StateName $id] S
	if {!$S(active) || $S(phase) ne "play"} { return }
	set S(side) $side
	set S(eval:$side) {}
	if {$S(request) ne ""} {
		uplevel #0 [list {*}$S(request) $side]
	} else {
		DriveMove $id $side
	}
}

proc ::td::runner::DriveMove {id side} {
	variable MoveTimeout
	upvar 0 [StateName $id] S
	if {!$S(active) || $S(phase) ne "play" || $S(side) ne $side} { return }
	if {[Connect $id $side]} { set S(pending:$side) 1; return }
	if {$S(pipeState:$side) ne "ready"} { return }
	UseSlot $id
	set fen [::scidb::pos::fen]
	StartSegment $id $side [clock milliseconds]
	if {$S(noclock)} {
		set go "go movetime $S(movetime)"
		set wait [expr {$S(movetime) + $S(overhead_ms) + $MoveTimeout}]
	} else {
		set go "go wtime $S(clock:w) btime $S(clock:b) winc $S(increment_ms) binc $S(increment_ms)"
		set wait [expr {$S(clock:$side) + $S(overhead_ms) + $MoveTimeout}]
	}
	set S(pipeState:$side) busy
	Send $id $side "position fen $fen"
	Send $id $side $go
	set token $S(token)
	set S(watchdog) [after $wait [list ::td::runner::OnTimeout $id $side $token]]
}

proc ::td::runner::EngineCommand {id side} {
	upvar 0 [StateName $id] S
	set name [EngineName $id $side]
	set index [::engine::FindIndex [EngineBase $name]]
	set e [dict merge $::engine::EmptyEngine [lindex $::engine::Engines $index]]
	return [list $name [::engine::Command [dict get $e Command] [dict get $e Parameters]]]
}

proc ::td::runner::AttachPipe {id side pipe} {
	upvar 0 [StateName $id] S
	fconfigure $pipe -blocking 0 -buffering line
	set S(pipe:$side) $pipe
	set S(pipeState:$side) starting
	fileevent $pipe readable [list ::td::runner::OnReadable $id $side]
	Send $id $side uci
	set S(handshake:$side) [after $::td::runner::StartTimeout [list ::td::runner::OnStartTimeout $id $side $pipe]]
	return 1
}

proc ::td::runner::Connect {id side} {
	upvar 0 [StateName $id] S
	if {$S(pipe:$side) ne ""} { return 0 }
	if {$S(pipeState:$side) eq "starting"} { return 1 }
	if {$S(connect) ne ""} { return [uplevel #0 [list {*}$S(connect) $id $side]] }
	lassign [EngineCommand $id $side] name cmd
	if {$cmd eq "" || $cmd eq "no-wine"} { EngineDied $id $side "the program of $name is missing"; return 1 }
	if {[catch {set pipe [::open "|[list {*}$cmd]" r+]} err]} { EngineDied $id $side $err; return 1 }
	return [AttachPipe $id $side $pipe]
}

proc ::td::runner::OnStartTimeout {id side pipe} {
	upvar 0 [StateName $id] S
	if {$S(pipe:$side) ne $pipe || $S(pipeState:$side) ne "starting"} { return }
	EngineDied $id $side "[EngineName $id $side] started but did not answer"
}

proc ::td::runner::Send {id side line} {
	upvar 0 [StateName $id] S
	if {[catch {puts $S(pipe:$side) $line; flush $S(pipe:$side)}]} { EngineDied $id $side "" }
}

proc ::td::runner::SendOptions {id side} {
	upvar 0 [StateName $id] S
	if {$S(threads) > 0} { Send $id $side "setoption name Threads value $S(threads)" }
	if {$S(hash) > 0} { Send $id $side "setoption name Hash value $S(hash)" }
	if {$S(overhead_ms) > 0} { Send $id $side "setoption name Move Overhead value $S(overhead_ms)" }
}

proc ::td::runner::OnReadable {id side} {
	if {![namespace exists "::td::runner::$id"]} { return }
	upvar 0 [StateName $id] S
	if {[catch {
		while {[namespace exists "::td::runner::$id"] && $S(pipe:$side) ne "" && [gets $S(pipe:$side) line] >= 0} {
			if {$line ne ""} { OnEngineLine $id $side $line }
		}
	}]} {
		if {[namespace exists "::td::runner::$id"]} { EngineDied $id $side "" }
		return
	}
	if {![namespace exists "::td::runner::$id"] || $S(pipe:$side) eq ""} { return }
	if {[catch {eof $S(pipe:$side)} atEof] || $atEof} { EngineDied $id $side "" }
}

proc ::td::runner::OnEngineLine {id side line} {
	if {![namespace exists "::td::runner::$id"]} { return }
	upvar 0 [StateName $id] S
	switch -glob -- $line {
		uciok {
			SendOptions $id $side
			Send $id $side ucinewgame
			Send $id $side isready
		}
		readyok {
			if {[namespace exists "::td::runner::$id"] && $S(pipeState:$side) eq "starting"} {
				after cancel $S(handshake:$side)
				set S(handshake:$side) {}
				set S(pipeState:$side) ready
				if {$S(pending:$side) && $S(phase) eq "play" && $S(side) eq $side} {
					set S(pending:$side) 0
					DriveMove $id $side
				}
			}
		}
		info* {
			lassign [::playengine::infoScore $line] kind value
			if {$kind ne "" && [namespace exists "::td::runner::$id"]} { set S(eval:$side) [list $kind $value] }
		}
		bestmove* {
			set move [lindex $line 1]
			if {[namespace exists "::td::runner::$id"]} { set S(pipeState:$side) ready }
			GotMove $id $side $move
		}
	}
}

proc ::td::runner::GotMove {id side uci} {
	upvar 0 [StateName $id] S
	if {[namespace exists "::td::runner::$id"]} { set S(pipeState:$side) ready }
	if {!$S(active) || $S(phase) ne "play" || $S(side) ne $side} { return }
	after cancel $S(watchdog)
	set S(watchdog) {}
	if {[::scidb::game::current] != $S(pos)} { ::scidb::game::switch $S(pos) }
	if {!$S(noclock) && [SettleClock $id $side [clock milliseconds]] <= 0} { FlagFall $id $side; return }
	lappend S(history) [NormScore $side $S(eval:$side)]
	if {$uci eq "" || $uci eq "(none)"} {
		set end [NaturalEnd $id]
		if {[llength $end]} { EndGame $id {*}$end } else {
			EndGame $id [expr {$side eq "w" ? "0-1" : "1-0"}] rulesinfraction "[EngineName $id $side] gave no move"
		}
		return
	}
	set san [::playengine::uciToSan $uci]
	if {$san eq ""} {
		EndGame $id [expr {$side eq "w" ? "0-1" : "1-0"}] rulesinfraction "[EngineName $id $side] played the illegal move $uci"
		return
	}
	set S(busy) 1
	catch {::scidb::game::move $san; ::scidb::game::go 1}
	lappend S(moves) $san
	set S(busy) 0
	set end [NaturalEnd $id]
	if {[llength $end]} { EndGame $id {*}$end; return }
	if {[TryAdjudicate $id]} { return }
	StartTurn $id [expr {$side eq "w" ? "b" : "w"}]
}

proc ::td::runner::NaturalEnd {id} {
	upvar 0 [StateName $id] S
	if {[catch {::scidb::game::query over?} over] || !$over} {
		set fen [::scidb::pos::fen]
		if {![string length $fen]} { return {} }
		if {[::playengine::fiftyMoves $fen]} { return [list 1/2-1/2 normal "fifty-move rule"] }
		if {[::playengine::repetition]} { return [list 1/2-1/2 normal "threefold repetition"] }
		if {[::playengine::insufficientMaterial $fen]} { return [list 1/2-1/2 normal "insufficient mating material"] }
		return {}
	}
	if {[::playengine::inCheck [::scidb::pos::fen]]} {
		return [list [expr {[::scidb::pos::stm] eq "w" ? "0-1" : "1-0"}] normal checkmate]
	}
	return [list 1/2-1/2 normal stalemate]
}

proc ::td::runner::TryAdjudicate {id} {
	upvar 0 [StateName $id] S
	set fen [::scidb::pos::fen]
	set plies [::scidb::game::query length]
	if {$S(max_plies) > 0 && $plies >= $S(max_plies)} {
		EndGame $id 1/2-1/2 adjudication "configured move limit"
		return 1
	}
	if {$S(tb) && [::tablebase::pieceCount $fen] <= 7} {
		set verdict [TbLocal $fen]
		if {$verdict ne ""} { EndGame $id $verdict adjudication "tablebase adjudication"; return 1 }
		if {$S(online) && !$S(tbLatch)} {
			set token $S(token)
			set S(phase) tbwait
			::application::download::Get [::tablebase::url $fen] [list ::td::runner::TbAnswer $id $fen $token]
			return 1
		}
	}
	set resign [resignRule $S(history) $S(resign_plies)]
	if {$resign ne ""} { EndGame $id $resign adjudication "agreed heavy score"; return 1 }
	if {[drawRule $plies $S(history) $S(draw_plies) $S(draw_min_move)]} {
		EndGame $id 1/2-1/2 adjudication "flat scores"; return 1
	}
	return 0
}

proc ::td::runner::TbAnswer {id fen token result} {
	upvar 0 [StateName $id] S
	if {!$S(active) || $S(phase) ne "tbwait" || $token != $S(token)} { return }
	set S(phase) play
	set S(tbLatch) 1
	if {[::scidb::game::current] != $S(pos)} { ::scidb::game::switch $S(pos) }
	set category unknown
	if {[dict get $result ok] && ![catch {package require json; ::json::json2dict [dict get $result data]} answer]
	 && [dict exists $answer category]} { set category [dict get $answer category] }
	set verdict [tbVerdict $category [lindex $fen 1]]
	if {$verdict ne ""} { EndGame $id $verdict adjudication "tablebase adjudication"; return }
	StartTurn $id [::scidb::pos::stm]
}

proc ::td::runner::SaveGame {id result termKey} {
	upvar 0 [StateName $id] S
	if {$S(base) eq ""} { return 0 }
	UseSlot $id
	set tags [list Event $S(event) Site $S(site) Date [clock format [clock seconds] -format {%Y.%m.%d}] \
		Round $S(round) White $S(white) Black $S(black) Result $result \
		TimeControl [TimeControlText $S(noclock) $S(base_ms) $S(increment_ms) $S(movetime)] \
		Termination [termTag $termKey]]
	set ok [::scidb::game::save $S(base) Normal $tags {} {} ::td::runner::LogSink {} -position $S(pos)]
	if {$ok} { set S(saved) 1; catch {::application::database::refreshBase $S(base)} }
	return $ok
}

proc ::td::runner::LogSink {args} { return }

proc ::td::runner::EndGame {id result termKey reason} {
	upvar 0 [StateName $id] S
	if {!$S(active) || $S(phase) eq "over"} { return }
	set S(phase) over
	set S(result) $result
	set S(termination) $termKey
	set S(reason) $reason
	after cancel $S(watchdog)
	set S(watchdog) {}
	ShutdownPipes $id
	UseSlot $id
	set S(saved) [expr {$result in {1-0 0-1 1/2-1/2} ? [SaveGame $id $result $termKey] : 0}]
	set S(pgn) [expr {$S(pos) >= 0 ? [ExportPgn $id] : ""}]
	set outcome [Status $id]
	set S(active) 0
	if {$S(onComplete) ne ""} { uplevel #0 [list {*}$S(onComplete) $id $outcome] }
}

proc ::td::runner::StartSegment {id side now} {
	upvar 0 [StateName $id] S
	set S(seg:$side) $now
}

proc ::td::runner::SettleClockVar {arrayName side now} {
	upvar 0 $arrayName S
	if {$S(noclock) || ![info exists S(seg:$side)]} { return 1 }
	set overhead [expr {[info exists S(overhead_ms)] ? $S(overhead_ms) : 0}]
	set elapsed [expr {max(0, $now - $S(seg:$side) - $overhead)}]
	set increment [expr {[info exists S(increment_ms)] ? $S(increment_ms) : $S(increment) * 1000}]
	set left [expr {$S(clock:$side) - $elapsed + $increment}]
	set S(clock:$side) $left
	unset S(seg:$side)
	return $left
}

proc ::td::runner::SettleClock {id side now} { return [SettleClockVar [StateName $id] $side $now] }

proc ::td::runner::RemainingVar {arrayName side now} {
	upvar 0 $arrayName S
	set ms $S(clock:$side)
	if {[info exists S(seg:$side)]} {
		set overhead [expr {[info exists S(overhead_ms)] ? $S(overhead_ms) : 0}]
		set ms [expr {$ms - max(0, $now - $S(seg:$side) - $overhead)}]
	}
	return $ms
}

proc ::td::runner::Remaining {id side now} { return [RemainingVar [StateName $id] $side $now] }

proc ::td::runner::FlagFall {id side} {
	upvar 0 [StateName $id] S
	UseSlot $id
	set name [EngineName $id $side]
	if {[::playengine::insufficientMaterial [::scidb::pos::fen]]} {
		EndGame $id 1/2-1/2 time "$name ran out of time, but the opponent cannot mate"
	} else {
		EndGame $id [expr {$side eq "w" ? "0-1" : "1-0"}] time "$name loses on time"
	}
}

proc ::td::runner::OnTimeout {id side token} {
	upvar 0 [StateName $id] S
	set S(watchdog) {}
	if {!$S(active) || $token != $S(token) || $S(phase) ne "play" || $S(side) ne $side} { return }
	if {$S(noclock)} { EngineDied $id $side "" } else { FlagFall $id $side }
}

proc ::td::runner::EngineDied {id side {why ""}} {
	upvar 0 [StateName $id] S
	if {!$S(active) || $S(phase) ni {play tbwait}} { return }
	if {$why eq ""} { set why "[EngineName $id $side] disappeared" }
	EndGame $id [expr {$side eq "w" ? "0-1" : "1-0"}] abandoned $why
}

proc ::td::runner::ShutdownPipes {id} {
	upvar 0 [StateName $id] S
	foreach side {w b} {
		after cancel $S(handshake:$side)
		set S(handshake:$side) {}
		if {$S(pipe:$side) ne ""} {
			catch {fileevent $S(pipe:$side) readable {}}
			catch {puts $S(pipe:$side) quit; flush $S(pipe:$side)}
			catch {close $S(pipe:$side)}
			set S(pipe:$side) {}
		}
		set S(pipeState:$side) off
		set S(pending:$side) 0
	}
}

proc ::td::runner::Stop {id} {
	set ns "::td::runner::$id"
	if {![namespace exists $ns]} { return }
	upvar 0 ${ns}::State S
	after cancel $S(watchdog)
	set S(watchdog) {}
	set S(active) 0
	set S(phase) idle
	ShutdownPipes $id
	if {$S(subscribed)} {
		catch {::scidb::game::unsubscribe board $S(pos) [list ::td::runner::Update $id]}
		catch {::scidb::db::unsubscribe gameClose [list ::td::runner::GameClosed $id]}
		if {$S(watch_switch)} { catch {::scidb::db::unsubscribe gameSwitch [list ::td::runner::GameSwitched $id]} }
		set S(subscribed) 0
	}
}

proc ::td::runner::Release {id} {
	Stop $id
	set ns "::td::runner::$id"
	if {[namespace exists $ns]} {
		ReleaseSlot $id
		namespace delete $ns
	}
}

proc ::td::runner::StopAll {} {
	foreach ns [namespace children ::td::runner] {
		if {[regexp {^game[0-9]+$} [namespace tail $ns]]} { Release [namespace tail $ns] }
	}
}

proc ::td::runner::EngineBase {label} { regsub { #[0-9]+$} $label {} base; return $base }
proc ::td::runner::EngineName {id side} { upvar 0 [StateName $id] S; return [expr {$side eq "w" ? $S(white) : $S(black)}] }
proc ::td::runner::EngineNames {} {
	set out {}
	foreach e $::engine::Engines { if {"UCI" in [dict get $e Protocol]} { lappend out [dict get $e Name] } }
	return $out
}

proc ::td::runner::NormScore {side eval} {
	variable MateCap
	if {$eval eq ""} { return 0 }
	lassign $eval kind value
	if {$kind eq "mate"} { return [expr {($side eq "w" ? 1 : -1) * $MateCap * ($value >= 0 ? 1 : -1)}] }
	return [expr {$side eq "w" ? $value : -$value}]
}

proc ::td::runner::resignRule {evals {pliesWanted 5}} {
	variable ResignCp
	set n [llength $evals]
	if {$n < $pliesWanted || $pliesWanted < 1} { return {} }
	set white 1
	set black 1
	foreach e [lrange $evals end-[expr {$pliesWanted - 1}] end] {
		if {$e < $ResignCp} { set white 0 }
		if {$e > -$ResignCp} { set black 0 }
	}
	if {$white} { return 1-0 }
	if {$black} { return 0-1 }
	return {}
}

proc ::td::runner::drawRule {plies evals {pliesWanted 10} {minMove 40}} {
	variable DrawCp
	if {$plies < $minMove * 2 || [llength $evals] < $pliesWanted} { return 0 }
	foreach v [lrange $evals end-[expr {$pliesWanted - 1}] end] { if {abs($v) >= $DrawCp} { return 0 } }
	return 1
}

proc ::td::runner::tbVerdict {category stm} {
	switch -- $category {
		win { return [expr {$stm eq "w" ? "1-0" : "0-1"}] }
		loss { return [expr {$stm eq "w" ? "0-1" : "1-0"}] }
		draw - cursed-win - blessed-loss { return 1/2-1/2 }
	}
	return {}
}

proc ::td::runner::TbLocal {fen} {
	if {![info exists ::tablebase::Options(local)]} { return {} }
	set answer [::tablebase::LocalAnswer $fen]
	if {$answer eq "" || ![dict exists $answer category]} { return {} }
	return [tbVerdict [dict get $answer category] [lindex $fen 1]]
}

proc ::td::runner::timeControlText {noclock baseMs incrementMs movetime} {
	if {$noclock} { return "movetime $movetime" }
	return "[format %g [expr {$baseMs / 1000.0}]]+[format %g [expr {$incrementMs / 1000.0}]]"
}
proc ::td::runner::TimeControlText {noclock baseMs incrementMs movetime} { return [timeControlText $noclock $baseMs $incrementMs $movetime] }

proc ::td::runner::termTag {key} {
	switch -- $key {
		normal { return Normal }
		time { return TimeForfeit }
		adjudication { return Adjudication }
		abandoned { return Abandoned }
		rulesinfraction { return RulesInfraction }
		default { return Unplayed }
	}
}

proc ::td::runner::eloDiff {w d l} {
	set n [expr {$w + $d + $l}]
	if {$n == 0 || ($w == 0 && $d == 0) || ($l == 0 && $d == 0)} { return {} }
	set score [expr {($w + $d / 2.0) / $n}]
	if {$score <= 0.0} { return -inf }
	if {$score >= 1.0} { return inf }
	return [expr {-400.0 * log10((1.0 - $score) / $score)}]
}
proc ::td::runner::eloError {w d l} {
	set n [expr {$w + $d + $l}]
	if {$n == 0} { return {} }
	set sigma [expr {sqrt(($w + $d / 4.0) / ($n * $n))}]
	if {$sigma == 0.0} { return inf }
	return [expr {400.0 / log(10.0) * $sigma / (($w + $d / 2.0) / $n * (1.0 - ($w + $d / 2.0) / $n))}]
}
proc ::td::runner::eloText {w d l} {
	set diff [eloDiff $w $d $l]
	set err [eloError $w $d $l]
	if {$diff eq "" || $err eq "" || $diff in {inf -inf} || $err eq "inf"} { return {} }
	return [format {%+d ± %d} [expr {round($diff)}] [expr {round($err)}]]
}

# vi:set ts=3 sw=3:
