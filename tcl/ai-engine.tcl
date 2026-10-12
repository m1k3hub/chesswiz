# ======================================================================
# ::ai::engine -- deterministic engine facts for the language layer.
#
# The grounding rule is that the model never reasons about the board, and
# that evaluations come from a real engine, not from prose.  This module
# drives a UCI engine (Stockfish by default) over a bidirectional pipe and
# returns structured facts:
#
#   ::ai::engine::evaluate <fen> ?-depth N? ?-multipv N? ?-movetime MS?
#       -> dict: kind/value (cp|mate), bestMove, pv, multipv lines
#
#   ::ai::engine::classify <fen> <san> ?-depth N?
#       -> dict: evalBeforeCp, evalAfterCp, cpLoss, winPercentLoss,
#                bestMove, classification (Best|Excellent|Good|Inaccuracy|
#                Mistake|Blunder)
#
# `classify` resolves SAN to UCI and gets the resulting FEN from the C++
# fact layer (::scidb::ai::moveFacts); it adds no chess of its own.
#
# Blocking note: reads use fileevent + vwait with a timeout, so a crashed
# engine raises instead of freezing.  A search still occupies the Tcl thread
# for its duration -- callers doing UI work should run it as a background job.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-engine
}
if {![namespace exists ::platform::sys]} {
	catch { source [file join [file dirname [file normalize [info script]]] sys-platform.tcl] }
}

package require Tcl 8.5

namespace eval ai {
namespace eval engine {

variable Config
array set Config {
	engine     stockfish
	depth      16
	multipv    1
	timeoutMs  60000
	onlyMoveCp 150
}

variable Proc ""
variable State

} ;# namespace engine
} ;# namespace ai


# ----------------------------------------------------------------------
# Configuration and lifecycle
# ----------------------------------------------------------------------

proc ::ai::engine::configure {args} {
	variable Config
	foreach {key value} $args {
		switch -- $key {
			-engine     { set Config(engine) $value }
			-depth      { set Config(depth) $value }
			-multipv    { set Config(multipv) $value }
			-timeout    { set Config(timeoutMs) $value }
			-onlyMoveCp { set Config(onlyMoveCp) $value }
			default     { error "unknown option $key" }
		}
	}
	return
}


# The Stockfish that ships with Scidb (stockfish-chesswiz in the engines
# directory) is preferred over one on PATH, unless an engine was configured.
proc ::ai::engine::Bundled {} {
	variable Config
	if {$Config(engine) ne "stockfish" || ![info exists ::scidb::dir::engines]} { return }
	set exe [file join $::scidb::dir::engines stockfish-chesswiz]
	if {![file exists $exe] && [file exists $exe.exe]} { append exe .exe }
	if {[file executable $exe]} { set Config(engine) $exe }
}


proc ::ai::engine::available {} {
	variable Config
	Bundled
	set exe $Config(engine)
	if {[file exists $exe] && [file executable $exe]} { return 1 }
	# bare name: search PATH
	if {[llength [file split $exe]] == 1} {
		foreach dir [split $::env(PATH) :] {
			if {[file executable [file join $dir $exe]]} { return 1 }
		}
	}
	return 0
}


proc ::ai::engine::shutdown {} {
	variable Proc
	if {$Proc ne ""} {
		catch { puts $Proc "quit" ; flush $Proc }
		catch { close $Proc }
		set Proc ""
	}
	return
}


# Discard the engine process without talking to it (after a crash or a
# timeout, when it may still be searching and would answer late).
proc ::ai::engine::kill {} {
	variable Proc
	if {$Proc ne ""} {
		catch { fileevent $Proc readable {} }
		catch { close $Proc }
		set Proc ""
	}
	return
}


proc ::ai::engine::ensure {} {
	variable Proc
	variable Config

	if {$Proc ne "" && [catch {eof $Proc} dead] == 0 && !$dead} { return }
	kill
	if {![available]} {
		error "no UCI engine: set ::ai::engine::configure -engine /path/to/stockfish"
	}

	set Proc [open "|[list $Config(engine)]" r+]
	fconfigure $Proc -blocking 0 -buffering line

	send "uci"
	readUntil "uciok"
	# the engine's minimum (1 thread, 16 MB) makes every answer slow: use
	# part of the machine, leaving cores for the GUI and analysis panes
	set cores 2
	catch { set cores [::platform::sys::cpus] }
	send "setoption name Threads value [expr {max(1, min(8, $cores / 2))}]"
	send "setoption name Hash value 256"
	# endgame tablebases: the folder set on the Stockfish profile (Engine
	# options, SyzygyPath), so the facts are perfect in endgames too
	if {![catch { lassign [::engine::profileOptions Stockfish Default] _ _ options }]} {
		foreach opt $options {
			lassign $opt name _ value
			if {$name eq "SyzygyPath" && $value ni {"" <empty>}} {
				send "setoption name SyzygyPath value $value"
			}
		}
	}
	send "isready"
	readUntil "readyok"
	return
}


# ----------------------------------------------------------------------
# Pipe I/O (non-blocking, with timeout)
# ----------------------------------------------------------------------

proc ::ai::engine::send {line} {
	variable Proc
	puts $Proc $line
	flush $Proc
}


proc ::ai::engine::readUntil {pattern} {
	variable Proc
	variable State
	variable Config

	set State(done) 0
	set State(result) ""
	set State(error) ""

	fileevent $Proc readable [namespace code [list ::ai::engine::onReadable $pattern]]
	set token [after $Config(timeoutMs) [namespace code {::ai::engine::onTimeout}]]
	vwait ::ai::engine::State(done)
	after cancel $token

	if {$State(error) ne ""} {
		kill
		error $State(error)
	}
	fileevent $Proc readable {}
	return $State(result)
}


proc ::ai::engine::onReadable {pattern} {
	variable Proc
	variable State

	while {[gets $Proc line] >= 0} {
		if {[string match "${pattern}*" $line]} {
			set State(result) $line
			set State(done) 1
			return
		}
	}
	if {[eof $Proc]} {
		kill
		set State(error) "engine closed the pipe"
		set State(done) 1
	}
}


proc ::ai::engine::onTimeout {} {
	variable State
	set State(error) "engine timed out"
	set State(done) 1
}


# ----------------------------------------------------------------------
# Search
# ----------------------------------------------------------------------

proc ::ai::engine::onSearchLine {} {
	variable Proc
	variable State

	while {[gets $Proc line] >= 0} {
		if {[string match "info*" $line]} {
			if {[string first " score " " $line "] >= 0} { lappend State(lines) $line }
		} elseif {[string match "bestmove*" $line]} {
			set State(result) [lindex $line 1]
			set State(done) 1
			return
		}
	}
	if {[eof $Proc]} {
		kill
		set State(error) "engine closed the pipe"
		set State(done) 1
	}
}


proc ::ai::engine::search {fen depth multipv {movetime 0}} {
	variable Proc
	variable State
	variable Config

	set State(lines) {}
	set State(done) 0
	set State(error) ""
	set State(result) ""

	send "setoption name MultiPV value $multipv"
	send "position fen $fen"
	if {$movetime > 0} {
		send "go movetime $movetime"
	} else {
		send "go depth $depth"
	}

	fileevent $Proc readable [namespace code {::ai::engine::onSearchLine}]
	set token [after $Config(timeoutMs) [namespace code {::ai::engine::onTimeout}]]
	vwait ::ai::engine::State(done)
	after cancel $token

	if {$State(error) ne ""} {
		# a timed-out engine is still searching; its late bestmove would be
		# taken as the answer to the next position, so restart it instead
		kill
		error $State(error)
	}
	fileevent $Proc readable {}
	return [list $State(lines) $State(result)]
}


# ----------------------------------------------------------------------
# Parsing
# ----------------------------------------------------------------------

proc ::ai::engine::parseInfo {line} {
	set tok [split [string trim $line]]
	set d [dict create depth 0 multipv 1 kind "" value 0 pv {}]

	for {set i 0} {$i < [llength $tok]} {incr i} {
		switch -- [lindex $tok $i] {
			depth   { dict set d depth [lindex $tok [incr i]] }
			multipv { dict set d multipv [lindex $tok [incr i]] }
			score {
				dict set d kind [lindex $tok [incr i]]
				dict set d value [lindex $tok [incr i]]
			}
			pv {
				dict set d pv [lrange $tok [incr i] end]
				set i [llength $tok]
			}
		}
	}

	if {[dict get $d kind] eq ""} { return {} }
	return $d
}


# centipawn-equivalent of an engine line, from the side-to-move perspective
proc ::ai::engine::cpOf {d} {
	set kind [dict get $d kind]
	set value [dict get $d value]
	if {$kind eq "cp"} { return $value }
	if {$kind eq "mate"} {
		# Stockfish reports mate in moves; positive = side to move mates
		return [expr {$value > 0 ? 10000 - 10 * $value : -10000 - 10 * $value}]
	}
	return 0
}


# ----------------------------------------------------------------------
# Public API
# ----------------------------------------------------------------------

# An engine handed something that is not a position may simply die
# ("engine closed the pipe"): refuse it here, with the reason.
proc ::ai::engine::CheckFen {fen} {
	set fields [split [string trim $fen]]
	lassign $fields board tomove
	if {[llength $fields] < 2 || $tomove ni {w b}} { error "not a position (FEN): '$fen'" }
	set ranks [split $board /]
	if {[llength $ranks] != 8} { error "a position has 8 ranks, this has [llength $ranks]: '$fen'" }
	set kings {}
	set r 8
	foreach row $ranks {
		set n 0
		foreach ch [split $row {}] {
			if {[string is digit -strict $ch]} {
				incr n $ch
			} elseif {[string first $ch KQRBNPkqrbnp] >= 0} {
				incr n
				if {$ch in {K k}} { lappend kings $ch }
				if {$ch in {P p} && $r in {1 8}} { error "a pawn on rank $r: '$fen'" }
			} else {
				error "'$ch' is not a piece: '$fen'"
			}
		}
		if {$n != 8} { error "rank $r has $n squares: '$fen'" }
		incr r -1
	}
	if {[lsort $kings] ne {K k}} { error "a position needs one king a side: '$fen'" }
}


proc ::ai::engine::evaluate {fen args} {
	variable Config
	variable State

	CheckFen $fen
	array set opts [list -depth $Config(depth) -multipv $Config(multipv) -timeout $Config(timeoutMs) -movetime 0]
	array set opts $args
	if {![string is integer -strict $opts(-movetime)] || $opts(-movetime) < 0} {
		error "movetime must be a non-negative integer in milliseconds"
	}

	# evaluate() pumps the event loop (vwait on State(done)), so a second
	# concurrent call would clobber State(done)/State(lines) and can hang or
	# hand back the wrong position's evaluation. Refuse rather than corrupt.
	if {[info exists State(busy)] && $State(busy)} {
		error "engine is busy: a previous evaluation is still running"
	}

	# -timeout applies to this call only
	set savedTimeout $Config(timeoutMs)
	set Config(timeoutMs) $opts(-timeout)
	set State(busy) 1
	set rc [catch {
		ensure
		search $fen $opts(-depth) $opts(-multipv) $opts(-movetime)
	} res opts2]
	set State(busy) 0
	set Config(timeoutMs) $savedTimeout
	if {$rc} { return -options $opts2 $res }
	lassign $res lines best

	# keep the deepest line per multipv index
	array set chosen {}
	array set chosenDepth {}
	foreach line $lines {
		set d [parseInfo $line]
		if {[llength $d] == 0} { continue }
		set mp [dict get $d multipv]
		if {![info exists chosen($mp)] || [dict get $d depth] >= $chosenDepth($mp)} {
			set chosen($mp) $d
			set chosenDepth($mp) [dict get $d depth]
		}
	}

	set out [dict create fen $fen bestMove $best multipv {}]
	for {set mp 1} {$mp <= $opts(-multipv)} {incr mp} {
		if {![info exists chosen($mp)]} { continue }
		set d $chosen($mp)
		dict lappend out multipv [dict create \
			move [lindex [dict get $d pv] 0] \
			kind [dict get $d kind] \
			value [dict get $d value] \
			cpl [cpOf $d] \
			pv [dict get $d pv]]
	}

	if {[llength [dict get $out multipv]] == 0} {
		error "engine returned no evaluation for $fen"
	}
	set first [lindex [dict get $out multipv] 0]
	dict set out kind  [dict get $first kind]
	dict set out value [dict get $first value]
	dict set out cpl   [dict get $first cpl]
	dict set out pv    [dict get $first pv]
	dict set out depth $chosenDepth(1)

	# runner-up, for the "only move" gap
	if {[llength [dict get $out multipv]] >= 2} {
		set second [lindex [dict get $out multipv] 1]
		dict set out secondMove [dict get $second move]
		dict set out secondCpl  [dict get $second cpl]
		dict set out gapCp      [expr {[dict get $out cpl] - [dict get $second cpl]}]
	}
	return $out
}


proc ::ai::engine::winPercent {cp} {
	if {$cp > 1000}  { set cp 1000 }
	if {$cp < -1000} { set cp -1000 }
	return [expr {50.0 + 50.0 * (2.0 / (1.0 + exp(-0.00368208 * $cp)) - 1.0)}]
}


proc ::ai::engine::classify {fen san args} {
	CheckFen $fen
	variable Config
	array set opts [list -depth $Config(depth)]
	array set opts $args

	# SAN -> UCI and the resulting position come from the C++ fact layer
	set facts [::scidb::ai::moveFacts $san $fen]
	if {![regexp {"uci":"([^"]+)"} $facts -> uci]} {
		error "cannot resolve move '$san' in the given position"
	}
	if {![regexp {"fenAfter":"([^"]+)"} $facts -> fenAfter]} {
		error "no resulting position for move '$san'"
	}

	set before [evaluate $fen     -depth $opts(-depth) -multipv 2]
	set after  [evaluate $fenAfter -depth $opts(-depth) -multipv 1]

	set cpBefore [dict get $before cpl]
	# opponent is to move in the resulting position, so negate its eval
	set cpAfter [expr {-[dict get $after cpl]}]
	set best    [dict get $before bestMove]

	set cpLoss   [expr {$cpBefore - $cpAfter}]
	if {$cpLoss < 0} { set cpLoss 0 }
	set wpLoss   [expr {[winPercent $cpBefore] - [winPercent $cpAfter]}]
	if {$wpLoss < 0} { set wpLoss 0 }

	if {$uci eq $best} {
		set class Best
	} elseif {$wpLoss >= 20} {
		set class Blunder
	} elseif {$wpLoss >= 10} {
		set class Mistake
	} elseif {$wpLoss >= 5} {
		set class Inaccuracy
	} elseif {$wpLoss >= 2} {
		set class Good
	} else {
		set class Excellent
	}

	set gapCp 0
	set onlyMove 0
	if {[dict exists $before gapCp]} {
		set gapCp [dict get $before gapCp]
		set onlyMove [expr {$gapCp >= $Config(onlyMoveCp)}]
	}

	return [dict create \
		san $san uci $uci bestMove $best \
		evalBeforeCp $cpBefore evalAfterCp $cpAfter \
		cpLoss $cpLoss winPercentLoss $wpLoss classification $class \
		gapCp $gapCp onlyMove $onlyMove depth $opts(-depth)]
}
