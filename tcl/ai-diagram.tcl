# ======================================================================
# AI: chess diagrams for the report pane
# ======================================================================
# Renders a position as an HTML fragment the report pane (the tkhtml
# widget behind ::application::report) already draws: a table of
# colored cells, Unicode chess glyphs (U+2654..U+265F) and <font>
# sizes -- no JavaScript, no external images, no attributes the
# scidb HTML sanitizer strips (tables, cells with bgcolor/width/
# height, fonts with color/size only; see src/html/html_sanitize.h).
#
#   ::ai::diagram::html <fen> ?-size PX? ?-flip 0|1? ?-caption TEXT?
#       ?-highlight {squares}? ?-coords 0|1?   -> HTML fragment
#   ::ai::diagram::grid <fen>                  -> 8 strings of 8
#       characters (FEN letters, '.' for empty), rank 8 first
#
# <fen> is a placement field with an optional side-to-move field; the
# remaining fields (castling, ep, clocks) are ignored. -size is the
# board edge in pixels (default 320, clamped to 64..1920); -flip shows
# Black at the bottom (rank 1 on top, file h at the left); -highlight
# is a list of squares ({e4 d5}, unknown tokens ignored) drawn in the
# highlight color; -caption adds a line under the board; -coords (on
# by default) adds file letters and rank numbers at the edge. A small
# filled dot in the marker column shows the side to move at its own
# edge (rank 1 for White, rank 8 for Black); '-' means no side and no
# dot.
#
# Robust: html never raises -- a bad FEN, a bad option or a bad
# option value returns a short HTML error line instead. grid answers
# {} for a FEN it cannot parse, so callers can check it before use.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source ai-diagram
}

package require Tcl 8.5

namespace eval ::ai::diagram {

	# The glyphs are built from their code points, not written into
	# this file: white pieces use the outline forms (U+2654..U+2659),
	# black pieces the solid forms (U+265A..U+265F).
	variable Glyph [dict create \
		K [format %c 0x2654] Q [format %c 0x2655] R [format %c 0x2656] \
		B [format %c 0x2657] N [format %c 0x2658] P [format %c 0x2659] \
		k [format %c 0x265A] q [format %c 0x265B] r [format %c 0x265C] \
		b [format %c 0x265D] n [format %c 0x265E] p [format %c 0x265F]]

	# Two muted square colors, the highlight and the coordinate ink.
	# Piece colors (#3a3a3a outline glyphs for White, #1e1e1e filled for Black) and the side-to-move dot
	# (#f5f5f5 / #101010) are deliberately distinct hex values so
	# tests (and readers of the markup) can tell them apart.
	variable Light		#f0d9b5
	variable Dark		#b58863
	variable Hi			#c9d66e
	variable Grid		#7a6a52
	variable CoordInk	#494034
	variable MarkerBg	#808080
}


# The placement field as 8 strings of 8 characters, rank 8 first;
# {} when the FEN does not parse.
proc ::ai::diagram::grid {fen} {
	set d [Parse $fen]
	if {[dict get $d reason] ne ""} { return {} }
	return [dict get $d rows]
}


# The HTML fragment; a short error line when anything about the call
# is bad. Build does the work and is wrapped so that even an
# unexpected failure (an option value out of Tcl's integer range,
# say) answers markup and never a Tcl error.
proc ::ai::diagram::html {fen args} {
	if {[catch {Build $fen $args} out msg]} { return [Error diagram $msg] }
	return $out
}


# ----------------------------------------------------------------------
# FEN
# ----------------------------------------------------------------------

# The permissive parse of both entry points: {rows side reason}, with
# rows empty and reason non-empty on a bad FEN. Only the placement and
# side-to-move fields are read; a missing side defaults to white
# ('-' keeps the dot away).
proc ::ai::diagram::Parse {fen} {
	set fields [split [string trim $fen]]
	set rows {}
	set rank 8

	foreach row [split [lindex $fields 0] /] {
		set line ""
		set n 0

		foreach ch [split $row ""] {
			if {[string match {[1-8]} $ch]} {
				if {$n + $ch > 8} {
					return [dict create reason "rank $rank has too many squares"]
				}
				append line [string repeat "." $ch]
				incr n $ch
			} elseif {[string match {[KQRBNPkqrbnp]} $ch]} {
				if {$n >= 8} {
					return [dict create reason "rank $rank has too many squares"]
				}
				append line $ch
				incr n
			} else {
				return [dict create reason "bad character '$ch' in rank $rank"]
			}
		}

		if {$n != 8} { return [dict create reason "rank $rank is not 8 squares"] }
		lappend rows $line
		incr rank -1
	}

	if {[llength $rows] != 8} {
		return [dict create reason "expected 8 ranks, found [llength $rows]"]
	}

	set side "w"
	if {[llength $fields] > 1} {
		set s [string tolower [lindex $fields 1]]
		if {$s ni {w b -}} {
			return [dict create reason "bad side to move '[lindex $fields 1]'"]
		}
		set side $s
	}

	return [dict create rows $rows side $side reason ""]
}


# ----------------------------------------------------------------------
# The fragment
# ----------------------------------------------------------------------

proc ::ai::diagram::Build {fen argl} {
	variable Light
	variable Dark
	variable Hi
	variable Grid
	variable CoordInk
	variable MarkerBg
	variable Glyph

	# --- options ---------------------------------------------------------
	array set opts {-size 320 -flip 0 -caption {} -highlight {} -coords 1}

	if {[llength $argl] % 2} { return [Error diagram "options come in -flag value pairs"] }
	foreach {flag value} $argl {
		switch -- $flag {
			-size {
				if {![string is integer -strict $value]} {
					return [Error diagram "-size wants a pixel count"]
				}
				set opts(-size) [expr {max(64, min(1920, int($value)))}]
			}
			-flip - -coords {
				if {![string is boolean -strict $value]} {
					return [Error diagram "$flag wants 0 or 1"]
				}
				set opts($flag) [expr {bool($value)}]
			}
			-caption - -highlight { set opts($flag) $value }
			default { return [Error diagram "unknown option '$flag'"] }
		}
	}

	# The highlight set, with unknown tokens dropped rather than
	# making the whole diagram fail.
	set mark [dict create]
	if {[catch {set tokens $opts(-highlight)}] || ![string is list -strict $tokens]} {
		set tokens {}
	}
	foreach sq $tokens {
		set sq [string tolower $sq]
		if {[string match {[a-h][1-8]} $sq]} { dict set mark $sq 1 }
	}

	# --- board -------------------------------------------------------------
	set d [Parse $fen]
	if {[dict get $d reason] ne ""} { return [Error {Invalid FEN} [dict get $d reason]] }
	set rows [dict get $d rows]
	set side [dict get $d side]
	set flip $opts(-flip)
	set coords $opts(-coords)

	set px [expr {$opts(-size) / 8}]
	set font [FontFor $px]
	set cw [expr {max(10, $px / 3)}]	;# coordinate columns/rows
	set mw [expr {max(8, $px / 4)}]		;# the side-to-move marker column
	set dot [format %c 0x25CF]

	set html "<table border=\"0\" cellpadding=\"0\" cellspacing=\"1\" bgcolor=\"$Grid\">"

	for {set k 0} {$k < 8} {incr k} {
		# Display row <k> is rows index <i>; -flip turns the board
		# (rank 1 on top, file h at the left).
		set i [expr {$flip ? 7 - $k : $k}]
		set rank [expr {8 - $i}]
		append html "<tr>"

		if {$coords} {
			append html "<td width=\"$cw\" height=\"$px\" bgcolor=\"$Light\" " \
				"align=\"right\" valign=\"middle\">" \
				"<font size=\"2\" color=\"$CoordInk\">$rank</font></td>"
		}

		for {set c 0} {$c < 8} {incr c} {
			set f [expr {$flip ? 7 - $c : $c}]
			set sq "[string index abcdefgh $f]$rank"
			set ch [string index [lindex $rows $i] $f]
			# a1 is dark: light squares are file+rank even (file a=0).
			set bg [expr {($f + $rank) % 2 == 0 ? $Light : $Dark}]
			if {[dict exists $mark $sq]} { set bg $Hi }

			set piece ""
			if {$ch ne "."} {
				set ink [expr {[string is upper $ch] ? "#3a3a3a" : "#1e1e1e"}]
				set piece "<font size=\"$font\" color=\"$ink\">[dict get $Glyph $ch]</font>"
			} else {
				set piece "&nbsp;"
			}
			append html "<td width=\"$px\" height=\"$px\" bgcolor=\"$bg\" " \
				"align=\"center\" valign=\"middle\">$piece</td>"
		}

		# The dot sits at the side's own edge: rank 1 for White, rank
		# 8 for Black; '-' has no side and no dot.
		set here [expr {($side eq "w" && $rank == 1) || ($side eq "b" && $rank == 8)}]
		set dotInk [expr {$side eq "b" ? "#101010" : "#f5f5f5"}]
		append html "<td width=\"$mw\" height=\"$px\" bgcolor=\"$MarkerBg\" " \
			"align=\"center\" valign=\"middle\">"
		append html [expr {$here ? "<font size=\"$font\" color=\"$dotInk\">$dot</font>" : "&nbsp;"}]
		append html "</td></tr>"
	}

	if {$coords} {
		append html "<tr><td width=\"$cw\" height=\"$cw\" bgcolor=\"$Grid\">&nbsp;</td>"
		for {set c 0} {$c < 8} {incr c} {
			set f [expr {$flip ? 7 - $c : $c}]
			append html "<td width=\"$px\" height=\"$cw\" bgcolor=\"$Light\" " \
				"align=\"center\" valign=\"middle\">" \
				"<font size=\"2\" color=\"$CoordInk\">[string index abcdefgh $f]</font></td>"
		}
		append html "<td width=\"$mw\" height=\"$cw\" bgcolor=\"$Grid\">&nbsp;</td></tr>"
	}

	append html "</table>"

	if {[string trim $opts(-caption)] ne ""} {
		append html "<p><font size=\"2\"><i>[Escape $opts(-caption)]</i></font></p>"
	}

	return $html
}


# The <font> size that fills a cell of <px> edge width.
proc ::ai::diagram::FontFor {px} {
	if {$px < 20} { return 3 }
	if {$px < 28} { return 4 }
	if {$px < 36} { return 5 }
	if {$px < 48} { return 6 }
	return 7
}


# The short error line: <label> is 'Invalid FEN' for a bad position,
# 'diagram' for a bad call; both are escaped and kept short.
proc ::ai::diagram::Error {label reason} {
	if {[string length $reason] > 120} { set reason "[string range $reason 0 116]..." }
	return "<p><font color=\"#9c3b3b\"><b>[Escape $label]:</b> [Escape $reason]</font></p>"
}


proc ::ai::diagram::Escape {text} {
	return [string map {& &amp; < &lt; > &gt; \" &quot;} $text]
}

# vi:set ts=3 sw=3:
