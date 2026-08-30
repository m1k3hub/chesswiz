#!/usr/bin/env tclsh
# ======================================================================
# cms2smv — port a ChessBase interactive-video index (.cms) into the
# scidb media manifest grammar ([Interactive] sections, see
# SCM_FORMAT_DESIGN.md §1.5).
#
# Usage: tclsh cms2smv.tcl "<db>.html/<name>.cms" [out.smv] [gameId]
#
# The .cms layout (reverse-engineered, CBM_FORMAT_DESIGN.md §7):
#   sibling directory <name>/ holds
#     <name>*000.wmv                       base video
#     <FEN with '/' as 'z'>x{X}y{Y}…​.wmv  hotspot clips
# Output .smv (written next to the .cms unless out.smv is given):
#   [Media "V0"] + [Interactive "Vn"] per hotspot, Kind: clip.
# ======================================================================

package require Tcl 8.5

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
			lappend entries [list $fen $clip $x $y]
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
		lassign $e fen clip x y
		incr vid
		lappend lines "\[Interactive \"V[format %02d $vid]\"\]"
		lappend lines "Fen: $fen"
		lappend lines "Kind: clip"
		lappend lines "Clip: [file join [file tail $dir] [file tail $clip]]"
		lappend lines "Label: \"hotspot x$x y$y\""
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