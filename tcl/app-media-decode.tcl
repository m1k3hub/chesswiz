# ======================================================================
# ChessBase script-stream decoder (pure Tcl, runtime)
# ======================================================================
# Reads a WMV's script stream (stream 2) via ffprobe, decodes the
# six-bit transport and opcode records, and produces:
#   * a navigation timeline (transition marks, replay order)
#   * board annotation events (arrows/marks/comments/symbols)
#
# Used by ::media::sync::load-timeline and load-events to replace the
# linear ply mapping with real per-move timecodes from the decoded
# ChessBase script stream.  No sidecar files, no media modification.
#
# All findings verified from the CBM 168 fixture corpus and CBase26
# decompilation (see CHESSBASE_MEDIA_RE.md for the full derivation).
# ======================================================================

::util::source media-sync

namespace eval ::media::cm {
	variable cache
}

proc ::media::decoder::log {msg} {
	if {[info commands MediaDebug] ne ""} {
		MediaDebug "Decoder: $msg"
	}
}

# ---------------------------------------------------------------------
# six-bit transport: chars '?'..'~' = 0x3f..0x7e = 6 bits, 4 -> 3 bytes
# ---------------------------------------------------------------------

proc ::media::decoder::decodeTransport {hexstr} {
	set out {}
	set value 0
	set bitcount 0
	foreach ch [split $hexstr ""] {
		scan $ch %c c
		if {$c < 0x3F || $c > 0x7E} { return {} }
		set value [expr {($value << 6) | ($c - 0x3F) & 0x3F}]
		incr bitcount 6
		if {$bitcount >= 8} {
			incr bitcount -8
			set byte [expr {($value >> $bitcount) & 0xFF}]
			lappend out [format {%02x} $byte]
		}
	}
	if {[llength $out] < 4} { return {} }

	# logical trim for fixed-size opcodes
	set opcode 0
	binary scan [binary format H* [join [lrange $out 0 3] {}]] I opcode
	set logical 0
	switch -- $opcode {
		3 - 8 - 14 { set logical 6 }
		4          { set logical 12 }
	}
	if {$logical && $logical <= [llength $out]} {
		set out [lrange $out 0 [expr {$logical - 1}]]
	}
	return $out
}

# ---------------------------------------------------------------------
# strip the command prefix and decode to a hex record
# ---------------------------------------------------------------------

proc ::media::decoder::decodeCommand {hexstr} {
	set n [string length $hexstr]
	if {$n < 4} { return {} }

	# scan the first bytes to detect the form
	set b {}
	for {set i 0} {$i + 1 < [string length $hexstr]} {incr i 2} {
		binary scan [binary format H2 [string range $hexstr $i [expr {$i+1}]]] c c_
		lappend b $c_
	}

	# UTF-16LE: G=0x47 A=0x41 with zero high bytes
	if {[llength $b] >= 3 && [lindex $b 0] == 0x47 && [lindex $b 1] == 0x41
			&& [lindex $b 2] == 0 && [lindex $b 3] == 0} {
		# wide chars: every other byte starting at +6
		set sixbit {}
		for {set i 6} {$i < [llength $b]} {incr i 2} {
			if {[lindex $b $i] >= 0x3F && [lindex $b [expr {$i + 1}]] == 0} {
				lappend sixbit [lindex $b $i]
			} else {
				break
			}
		}

		set record {}
		set value 0 ; set bitcount 0
		foreach ch $sixbit {
			set value [expr {($value << 6) | ($ch - 0x3F)}]
			incr bitcount 6
			if {$bitcount >= 8} {
				incr bitcount -8
				set byte [expr {($value >> $bitcount) & 0xFF}]
				set record [concat $record [format {%02x} $byte]]
			}
		}
		set record [_trim_opcode [string map {" " {}} $record]]
		return $record
	}

	if {[lindex $b 0] == 0x47 && [lindex $b 1] == 0x41} {
		# ASCII "GA:" (G=47 A=41 :=3a)
		set begin 2
		if {[llength $b] >= 3 && [lindex $b 2] == 0x3A} { set begin 3 }
		set sixbit [lrange $b $begin end]

		set record {}
		set value 0 ; set bitcount 0
		foreach ch $sixbit {
			set value [expr {($value << 6) | ($ch - 0x3F)}]
			incr bitcount 6
			if {$bitcount >= 8} {
				incr bitcount -8
				set byte [expr {($value >> $bitcount) & 0xFF}]
				lappend record [format {%02x} $byte]
			}
		}
		set record [_trim $record]
		return $record
	}

	return $hexstr  ;# bare six-bit
}

proc ::media::decoder::_trim {out} {
	if {[llength $out] < 4} { return $out }
	set bytes [lrange $out 0 3]
	binary scan [binary format H* [join $bytes {}]] I opcode
	set logical 0
	switch -- $opcode {
		3 - 8 - 14 { set logical 6 }
		4          { set logical 12 }
	}
	if {$logical && $logical <= [llength $out]} {
		foreach ch [lrange $out $logical end] {
			if {$ch ne "00"} { return $out }
		}
		set out [lrange $out 0 [expr {$logical - 1}]]
	}
	return $out
}

proc ::media::decoder::_trim {out} {
	if {[llength $out] < 4} { return $out }
	set bytes [lrange $out 0 3]
	binary scan [binary format H* [join $bytes {}]] I opcode
	set logical 0
	switch -- $opcode {
		3 - 8 - 14 { set logical 6 }
		4          { set logical 12 }
	}
	if {$logical && $logical <= [llength $out]} {
		foreach ch [lrange $out $logical end] {
			if {$ch ne "00"} { return $out }
		}
		set out [lrange $out 0 [expr {$logical - 1}]]
	}
	return $out
}

# ---------------------------------------------------------------------
# opcode name (from CBase26 decompilation FUN_140da1d70)
# ---------------------------------------------------------------------

proc ::media::decoder::opcodeName {opcode} {
	switch -- $opcode {
		2 - 15 { return "Set Game" }
		3      { return "GotoIndex" }
		4      { return "Board Action" }
		5      { return "Board Action Var" }
		6      { return "Annotation" }
		8      { return "Promote Line" }
		9      { return "Viewer" }
		10     { return "Viewer" }
		11     { return "UnAnnotate" }
		12     { return "Add Annotext" }
		13     { return "Web Origin" }
		14     { return "Sync" }
		16     { return "Set Moves" }
		17     { return "Set Header" }
		default { return "Unknown" }
	}
}

# ---------------------------------------------------------------------
# decode one decoded-record byte list into an event dict
# ---------------------------------------------------------------------

proc ::media::decoder::parseRecord {rec} {
	if {[llength $rec] < 4} { return {} }
	set op [lindex $rec 0]
	binary scan [binary format H* [join [lrange $rec 0 3] {}]] I opcode

	set kind [opcodeName $opcode]
	set result [dict create opcode $opcode name $kind]

	switch -- $opcode {
		3 {
			# GotoIndex: u32le at +4
			set b [lrange $rec 4 7]
			binary scan [binary format H* [join $b {}]] I idx
			dict set result gotoIndex $idx
		}
		4 {
			# board action: class u32le + 2 file-major squares + modifier u16le
			binary scan [binary format H* [join [lrange $rec 4 11] {}]] ivccS class sq0 sq1 mod
			dict set result class [format {%x} $class]
			dict set result from [::media::decoder::sq0 $sq0]
			dict set result to [::media::decoder::sq0 $sq1]
			dict set result modifier $mod
		}
	}
	return $result
}

proc ::media::decoder::sq0 {v} {
	if {$v >= 64} { return "???" }
	return [string index "abcdefgh" [expr {$v >> 3}]] [expr {($v & 7) + 1}]
}

# ---------------------------------------------------------------------
# main entry: decode the script stream from a .wmv file
# ---------------------------------------------------------------------

proc ::media::decoder::decode {wmvPath} {
	variable cache

	# call ffprobe to extract stream 2 packets
	set cmdline [list ffprobe -v error -select_streams 2 \
		-show_packets -show_data -of json [file normalize $wmvPath]]
	if {[catch {set fh [open "|concat $cmdline" r]} err]} {
		log "ffprobe failed: $err"
		return [list]
	}
	set json [read $fh]
	close $fh

	# extract the "data" hex fields
	set packets [list]
	set pos 0
	while 1 {
		set idx [string first {\"data\": \"} $json $pos]
		if {$idx < 0} break
		set start [expr {$idx + 10}]
		set end [string first \" $json $start]
		if {$end < 0} break
		set hexstr [string range $json $start [expr {$end - 1}]]
		lappend packets $hexstr
		set pos [expr {$end + 2}]
	}

	# decode each packet
	set decoded [list]
	set lastMs 0.0
	set pktIdx 0
	foreach hex $packets {
		set record [decodeCommand $hex]
		if {[llength $record] < 4} { incr pktIdx ; continue }

		# extract the opcode and the timestamp
		binary scan [binary format H* [join [lrange $record 0 3] {}]] I opcode
		set kind [opcodeName $opcode]
		set decodedEntry [list opcode $opcode name $kind pkt $pktIdx]

		# per-opcode payload extraction
		if {$opcode == 3} {
			set b [lrange $record 4 7]
			binary scan [binary format H* [join $b {}]] I gotoIdx
			dict set decodedEntry gotoIndex [expr {$gotoIdx < 0x80000000 ? $gotoIdx : $gotoIdx - 4294967296}]
			dict set decodedEntry type navigate
		} elseif {$opcode == 4} {
			binary scan [binary format H* [join [lrange $rec 4 11] {}]] "IccS" class sq0 sq1 mod
			set rec2 [_trim $record]
			binary scan [binary format H* [join [lrange $rec2 8 11] {}]] ccS from to modifier
			dict set decodedEntry from [sq0 $from]
			dict set decodedEntry to [sq0 $to]
			dict set decodedEntry class [format {%x} $class]
			dict set decodedEntry modifier $modifier
			dict set decodedEntry type board-action
		} elseif {$opcode == 6} {
			# walk the annotation records
			set cnt [lindex [lindex $rec 8] [lindex $rec 9]]
			set rpos 10
			set anns 0
			for {set r 0} {$r < $count} {incr r} {
				set lenBytes [lrange $record [expr {$rpos}] [expr {$rpos + 1}]]
				if {[llength $lenBytes] < 2} break
				binary scan [binary format H* [join $lenBytes {}]] S recLen
				if {$recLen < 6 || $rpos + 2 + $recLen > [llength $record]} break
				set typeBytes [lrange $record [expr {$rpos + 2}] [expr {$rpos + 5}]]
				binary scan [binary format H* [join $typeBytes {}]] I recType
				set payloadStart [expr {$rpos + 2 + 6}]
				set payloadLen [expr {$recLen - 6}]
				incr anns
				set rpos [expr {$rpos + 2 + $recLen}]
			}
			if {$anns} {
				dict set decodedEntry type annotation
				dict set decodedEntry count $anns
			}
		}
		lappend decoded $decodedEntry
		incr pktIdx
	}
	return $decoded
}

proc ::media::decoder::sq0 {v} {
	if {$v >= 64} return "?"
	return [string index "abcdefgh" [expr {$v >> 3}]] [expr {($v & 7) + 1}]
}