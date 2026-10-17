# ======================================================================
# ::ai::setup -- put a position on the board from a FEN or a line of moves
# (the assistant's set_position; docs/ASSISTANT_COVERAGE_MAP.md phase 2).
#
# Always in a NEW game: the game on the board is never changed (it may be
# a correspondence game, whose moves are sent when made). The whole line is
# checked before anything happens, so a bad move leaves the board as it was.
#
#   ::ai::setup::validate ?-fen FEN? ?-moves MOVES?
#       -> {fen FINAL plies N sans {SAN ...}}, or an error naming the first
#       move that is not legal ("move 7 (Bg4) is not legal here")
#   ::ai::setup::position ?-fen FEN? ?-moves MOVES? ?-variant Normal?
#       the same, after putting the new game on the board at the end
#
# MOVES is a list of SAN moves or a PGN-like string: move numbers ("12.",
# "12..."), results and annotation marks are ignored.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-setup-position
}

package require Tcl 8.5

namespace eval ai {
namespace eval setup {

variable Start {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}

} ;# namespace setup
} ;# namespace ai


# The SAN tokens of <moves>.
proc ::ai::setup::Tokens {moves} {
	set sans {}
	foreach token [regexp -all -inline {\S+} $moves] {
		# "12.e4" and "12...e5" carry the number on the move
		regsub {^\d+\.+} $token {} token
		regsub {[!?]+$} $token {} token
		if {$token eq "" || $token in {1-0 0-1 1/2-1/2 * ...}} { continue }
		lappend sans $token
	}
	return $sans
}


proc ::ai::setup::validate {args} {
	variable Start
	array set opts [list -fen $Start -moves {}]
	array set opts $args
	set fen [expr {[string trim $opts(-fen)] eq "" ? $Start : [string trim $opts(-fen)]}]

	if {[catch { ::scidb::board::isValidFen $fen } valid] || !$valid} {
		error "not a valid position: '$fen'"
	}
	set sans [Tokens $opts(-moves)]
	set ply 0
	foreach san $sans {
		set number [expr {[lindex $fen 5] eq "" ? 1 : [lindex $fen 5]}]
		set dots [expr {[lindex $fen 1] eq "b" ? "..." : "."}]
		if {[catch { ::scidb::ai::moveFacts $san $fen } facts]
		 || ![regexp {"fenAfter":"([^"]+)"} $facts -> after]} {
			error "move $number$dots$san is not legal here"
		}
		set fen $after
		incr ply
	}
	return [dict create fen $fen plies $ply sans $sans start \
		[expr {[string trim $opts(-fen)] eq "" ? $Start : [string trim $opts(-fen)]}]]
}


proc ::ai::setup::position {args} {
	array set opts {-variant Normal}
	array set opts $args
	set checked [validate {*}[array get opts -fen] {*}[array get opts -moves]]

	if {[::game::new .application -variant $opts(-variant)] < 0} {
		error "no free game slot on the board"
	}
	::scidb::game::clear [dict get $checked start]
	foreach san [dict get $checked sans] {
		::scidb::game::move $san
		::scidb::game::go 1
	}
	return $checked
}
