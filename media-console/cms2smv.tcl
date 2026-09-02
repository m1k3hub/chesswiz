#!/usr/bin/env tclsh
# ======================================================================
# cms2smv — port a ChessBase interactive-video index (.cms) into the
# scidb media manifest grammar ([Interactive] sections, see
# SCM_FORMAT_DESIGN.md §1.5).
#
# Usage: tclsh cms2smv.tcl "<db>.html/<name>.cms" [out.smv] [gameId]
#
# The .cms layout (FULLY DECODED 2026-09-02, see CHESSBASE_MEDIA_RE.md):
#   header: u32be body length, u32le record count, u32le base-name length
#   + base name.  Records (4 shapes):
#     kind=1 (drill):  [kind][0][dur-s][0][len][FEN][len][base clip name]
#     kind=2 (video):  [kind][0][dur-s][0][5][len][base video name]
#     kind=3 (alt):    [kind][0][dur-s][2][0][len][clip name]
#     kind=4 (main):   [kind][0][dur-s][0][0][len][clip name]
#   The last kind=2 record omits its name (equals the header base name).
#   Clip names embed the FEN (z for /) plus x/y/v/u selectors:
#     x = from-square of the key move (file-major 0-based, a1=0)
#     y = to-square of the key move (same encoding)
#     v, u = structural constants ((3,2) primary, (2,5) alternative)
#   x->y is a fully legal move in the FEN position (109/109 corpus).
#   sibling directory <name>/ holds
#     <name>*000.wmv                       base video
#     <FEN with '/' as 'z'>x{X}y{Y}.wmv   hotspot clips

#   sibling directory <name>/ holds
#     <name>*000.wmv                       base video
#     <FEN with '/' as 'z'>x{X}y{Y}…​.wmv  hotspot clips
# Output .smv (written next to the .cms unless out.smv is given):
#   [Media "V0"] + [Interactive "Vn"] per hotspot, Kind: clip.
# ======================================================================

package require Tcl 8.5

# Convert a file-major 0-based square index to algebraic notation.
proc squareName {idx} {
	return [lindex {a b c d e f g h} [expr {$idx / 8}]][expr {$idx % 8 + 1}]
}

proc main {argv} {
	if {[llength $argv] < 1} {
		puts stderr "usage: cms2smv.tcl <db>.html/<name>.cms \[out.smv\] \[gameId\]"
		exit 1
	}
	set cms [lindex $argv 0]
	if {![file exists $cms]} { puts stderr "no such file: $cms"; exit 1 }
	set ext [file rootname $cms]                       ;# <db>.html/<name>
	set dir $ext
	set baselang [file tail $ext]

	set out [expr {[llength $argv] >= 2 ? [lindex $argv 1] : "$ext.smv"}]
	set gameId [expr {[llength $argv] >= 3 ? [lindex $argv 2] : ""}]

	# --- parse hotspot entries ------------------------------------------
	set fh [open $cms rb]; set data [read $fh]; close $fh
	set entries {}
	set pairs [regexp -all -inline -- {([pnbrqkPNBRQKz0-9]+ [bw] - - 0 1)x(\d+)y(\d+)v(\d+)u(\d+)} $data]
	foreach {whole fen x y v u} $pairs {
		set clip [file join $dir "${whole}.wmv"]
		if {[file exists $clip]} {
			lappend entries [list $fen $clip $x $y [squareName $x]-[squareName $y]]
		}
	}
	set base [lindex [glob -nocomplain -directory $dir *000.wmv] 0]
	if {![string length $base]} {
		set base [lindex [glob -nocomplain -directory $dir *.wmv] 0]
	}

	# --- emit ------------------------------------------------------------
	set lines {}
	lappend lines "# scidb media manifest — generated from [file tail $cms]"
	lappend lines "# version 1"
	lappend lines "\[MediaDir \".\"\]"
	lappend lines ""
	set vid 0
	if {[string length $base]} {
		incr vid
		lappend lines "# base video"
		lappend lines "\[Media \"V[format %02d $vid]\"\]"
		lappend lines "Type: video"
		lappend lines "Path: [file join [file tail $dir] [file tail $base]]"
		lappend lines ""
	}
	set ids {}
	foreach e $entries {
		lassign $e fen clip x y hotspot
		incr vid
		lappend lines "\[Interactive \"V[format %02d $vid]\"\]"
		lappend lines "Fen: $fen"
		lappend lines "Kind: clip"
		lappend lines "Clip: [file join [file tail $dir] [file tail $clip]]"
		lappend lines "Label: \"hotspot x$x y$y\""
		if {[info exists hotspot] && [string length $hotspot]} {
			lappend lines "Hotspot: $hotspot"
		}
		lappend lines ""
		lappend ids "V[format %02d $vid]"
	}
	if {[string length $gameId] && [llength $ids]} {
		lappend lines "\[Game \"$gameId\"\]"
		lappend lines "Interactive: [join $ids {, }]"
		lappend lines ""
	} elseif {[llength $ids]} {
		lappend lines "# no gameId given — position-keyed segments usable by any game of the companion db"
		lappend lines ""
	}

	set fh [open $out w]
	puts $fh [join $lines "\n"]
	close $fh
	puts "wrote $out ([llength $entries] interactive clips, [expr {[string length $base] ? "base video yes" : "no base video"}])"
}

main $argv