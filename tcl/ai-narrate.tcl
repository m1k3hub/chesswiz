# ======================================================================
# ::ai::narrate -- engine-native position anatomy from the custom Stockfish.
#
# The fork's `narrate` UCI command reports the engine's own view of a position
# (material, pawn structure, control/mobility, king safety) as JSON.  This
# module drives that binary and exposes the facts to the language layer,
# including before/after deltas for a move.
#
#   ::ai::narrate::configure -engine /path/to/stockfish  (fork, not system SF)
#   ::ai::narrate::lookup  <fen>            -> dict (or {} when unavailable)
#   ::ai::narrate::summary <fen>            -> one-line text
#   ::ai::narrate::compare <fen> <san>      -> anatomy deltas for a move
#
# Shadow-only: the engine's `narrate` never influences search or evaluation.
# A missing binary yields {} rather than an error.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-narrate
}

package require Tcl 8.5

namespace eval ai {
namespace eval narrate {

variable Config
array set Config {
	engine  "stockfish"
	timeout 20000
}

# Auto-discovery: point at the custom fork that implements `narrate`.
if {[info exists ::env(SCIDB_AI_NARRATE_ENGINE)]} { set Config(engine) $::env(SCIDB_AI_NARRATE_ENGINE) }

} ;# namespace narrate
} ;# namespace ai


proc ::ai::narrate::configure {args} {
	variable Config

	foreach {key value} $args {
		switch -- $key {
			-engine  { set Config(engine) $value }
			-timeout { set Config(timeout) $value }
			default  { error "unknown option $key" }
		}
	}
	return
}


proc ::ai::narrate::available {} {
	variable Config
	set exe $Config(engine)
	if {[file exists $exe] && [file executable $exe]} { return 1 }
	if {[llength [file split $exe]] == 1} {
		set path [expr {[info exists ::env(PATH)] ? $::env(PATH) : ""}]
		foreach dir [split $path :] {
			if {[file executable [file join $dir $exe]]} { return 1 }
		}
	}
	return 0
}


# Read the engine's reply without blocking the event loop: a slow or hung
# engine must not freeze the interface, so the pipe is non-blocking and bounded
# by Config(timeout).
proc ::ai::narrate::onReadable {chan} {
	variable State

	while {[gets $chan candidate] >= 0} {
		incr State(count)
		if {[string match "\{*" $candidate]} {
			set State(line) $candidate
			set State(done) 1
			return
		}
		if {$State(count) >= 64} { break }
	}
	if {[eof $chan] || $State(count) >= 64} { set State(done) 1 }
}


proc ::ai::narrate::onTimeout {} {
	variable State
	set State(done) 1
	return
}


proc ::ai::narrate::lookup {fen} {
	variable Config
	variable State

	if {![available]} { return {} }
	if {[catch {package require json}]} { return {} }

	set chan ""
	set line ""

	if {[catch {
		set chan [open "|$Config(engine)" r+]
		fconfigure $chan -blocking 0 -buffering line

		puts $chan "position fen $fen"
		puts $chan "narrate"
		# Queue "quit" now: an engine without `narrate` (e.g. stock Stockfish)
		# only prints "Unknown command" and would otherwise wait for input
		# forever.
		puts $chan "quit"
		flush $chan

		set State(done) 0
		set State(line) ""
		set State(count) 0
		fileevent $chan readable [namespace code [list ::ai::narrate::onReadable $chan]]
		set token [after $Config(timeout) ::ai::narrate::onTimeout]
		vwait ::ai::narrate::State(done)
		after cancel $token
		catch { fileevent $chan readable {} }
		catch { close $chan }
		set line $State(line)
	}]} {
		if {$chan ne ""} {
			catch { fileevent $chan readable {} }
			catch { close $chan }
		}
		return {}
	}

	if {![string match "\{*" $line]} { return {} }
	if {[catch {set d [json::json2dict $line]}]} { return {} }
	return $d
}


proc ::ai::narrate::summary {fen} {
	set d [lookup $fen]
	if {[llength $d] == 0} { return "" }

	set w [dict get $d material white]
	set b [dict get $d material black]
	set wp [dict get $d pawns white]
	set bp [dict get $d pawns black]

	return "balance [dict get $d material balanceCp]cp; white mobility [dict get $d pieces white mobility], \
pawn islands [dict get $wp islands], isolated [dict get $wp isolated], passed [dict get $wp passed]; \
black mobility [dict get $d pieces black mobility], pawn islands [dict get $bp islands]"
}


proc ::ai::narrate::compare {fen san} {
	set before [lookup $fen]
	if {[llength $before] == 0} { return {} }

	set facts [::scidb::ai::moveFacts $san $fen]
	if {![regexp {"fenAfter":"([^"]+)"} $facts -> fenAfter]} { return {} }
	if {![regexp {"uci":"([^"]+)"} $facts -> uci]} { return {} }
	if {![dict exists $before material white]} { return {} }

	set after [lookup $fenAfter]
	if {[llength $after] == 0} { return {} }

	set delta [dict create san $san uci $uci side [dict get $before sideToMove]]

	dict set delta balanceCp \
		[expr {[dict get $after material balanceCp] - [dict get $before material balanceCp]}]

	foreach c {white black} {
		dict set delta mobility $c \
			[expr {[dict get $after pieces $c mobility] - [dict get $before pieces $c mobility]}]
		dict set delta isolated $c \
			[expr {[dict get $after pawns $c isolated] - [dict get $before pawns $c isolated]}]
		dict set delta passed $c \
			[expr {[dict get $after pawns $c passed] - [dict get $before pawns $c passed]}]
	}

	return $delta
}
