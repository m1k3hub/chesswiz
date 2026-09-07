# ======================================================================
# ChessBase script-stream decoder — ::media::decoder
# ======================================================================
# Decodes the "script stream" (ffprobe stream 2) of a ChessBase media
# lesson into replay/timeline entries.  This is the ONE place where raw
# WMV script packets are parsed; the resulting lesson (timeline + board
# events) is built/cached by ::media::lesson and, in a later phase,
# persisted into the .cms [BoardSync] section (SCM_FORMAT_DESIGN.md
# §1.6) so the decode never runs twice for the same entry.
#
# Grammar: SCM_FORMAT_DESIGN.md (script-stream RE, from the WMV/CBase26
# reverse-engineering).  Six-bit transport: chars '?'..'~' (0x3F..0x7E)
# encode 6 bits, 4 chars -> 3 bytes.
#
# NOTE: all procs are defined INSIDE "namespace eval ::media::decoder"
# so their bodies execute in this namespace.  Procs defined with a
# qualified name at global scope run their bodies in "::" and cannot
# resolve their siblings — the previous version of this file failed
# exactly like that.
# ======================================================================

namespace eval ::media::decoder {

# ffprobe -show_data emits an xxd-style hexdump (JSON-escaped newlines,
# offsets, 2-byte word groups, ASCII gutter); reduce it to clean
# contiguous hex so the GA/six-bit forms can be detected.
proc hexdump2hex {dump} {
	set out {}
	foreach ln [split [string map {"\\n" "\n"} $dump] "\n"] {
		if {![regexp {^[0-9a-f]{8}: } $ln]} { continue }
		set body [string range $ln 10 end]
		set cut [string first {  } $body]
		if {$cut >= 0} { set body [string range $body 0 [expr {$cut - 1}]] }
		regsub -all { } $body {} body
		append out $body
	}
	return $out
}

proc log {msg} {
	catch { ::application::media::MediaDebug "Decoder: $msg" }
}

proc jsonObjects {s} {
	set out {}; set start -1; set depth 0; set quoted 0; set escaped 0
	for {set i 0} {$i < [string length $s]} {incr i} {
		set c [string index $s $i]
		if {$quoted} {
			if {$escaped} { set escaped 0 } elseif {$c eq "\\"} { set escaped 1 } elseif {$c eq "\""} { set quoted 0 }
			continue
		}
		if {$c eq "\""} { set quoted 1; continue }
		if {$c eq "\{"} { if {$depth == 0} { set start $i }; incr depth
		} elseif {$c eq "\}" && $depth > 0} {
			incr depth -1
			if {$depth == 0} { lappend out [string range $s $start $i]; set start -1 }
		}
	}
	return $out
}

# ---------------------------------------------------------------------
# logical trim: fixed-size opcodes carry zero padding after their
# payload; cut it so payload offsets stay meaningful
# ---------------------------------------------------------------------

proc _trim {out} {
	if {[llength $out] < 4} { return $out }
	binary scan [binary format H* [join [lrange $out 0 3] {}]] i opcode
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

# six-bit codes (list of char codes 0x3F..0x7E) -> record (hex-byte list)
proc sixbit-decode {codes} {
	set record {}
	set value 0
	set bitcount 0
	foreach c $codes {
		set value [expr {(($value << 6) | ($c - 0x3F)) & 0x3FFFFF}]
		incr bitcount 6
		if {$bitcount >= 8} {
			incr bitcount -8
			set byte [expr {($value >> $bitcount) & 0xFF}]
			lappend record [format %02x $byte]
		}
	}
	if {[llength $record] < 4} { return {} }
	return [_trim $record]
}

# ---------------------------------------------------------------------
# opcode name (from the CBase26 decompilation)
# ---------------------------------------------------------------------

proc opcodeName {opcode} {
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
# one six-bit square (file-major) -> algebraic, e.g. 19 -> d3
# ---------------------------------------------------------------------

proc sq0 {v} {
	if {$v >= 64} { return "?" }
	return [string index "abcdefgh" [expr {$v >> 3}]][expr {($v & 7) + 1}]
}

# ---------------------------------------------------------------------
# decode one packet's hex payload into a record (hex-byte list)
#
# Known forms (see SCM_FORMAT_DESIGN.md):
#   UTF-16LE "GA" prefix: 47 00 41 00, six-bit wide chars from +6
#   ASCII     "GA"/"GA:" prefix: 47 41 (3a), six-bit chars from +2/+3
#   bare six-bit transport: the payload bytes are six-bit chars
# ---------------------------------------------------------------------

proc decodeCommand {hexstr} {
	if {[string length $hexstr] < 8} { return {} }

	if {[string length $hexstr] % 2} { append hexstr 0 }
	set b {}
	binary scan [binary format H* $hexstr] c* b
	set nb [llength $b]
	if {$nb < 2} { return {} }

	# UTF-16LE "GA" form: G A 0 0, then wide six-bit chars from +6
	if {	$nb >= 4
			&& [lindex $b 0] == 0x47 && [lindex $b 1] == 0
			&& [lindex $b 2] == 0x41 && [lindex $b 3] == 0} {
		set codes {}
		for {set i 6} {$i + 1 < $nb} {incr i 2} {
			set lo [lindex $b $i]
			set hi [lindex $b [expr {$i + 1}]]
			if {$lo >= 0x3F && $lo <= 0x7E && $hi == 0} {
				lappend codes $lo
			} else {
				break
			}
		}
		return [sixbit-decode $codes]
	}

	# ASCII "GA:" form
	if {[lindex $b 0] == 0x47 && [lindex $b 1] == 0x41} {
		set begin 2
		if {$nb >= 3 && [lindex $b 2] == 0x3A} { set begin 3 }
		set codes {}
		foreach lo [lrange $b $begin end] {
			if {$lo >= 0x3F && $lo <= 0x7E} {
				lappend codes $lo
			} else {
				break
			}
		}
		return [sixbit-decode $codes]
	}

	# bare six-bit transport: payload bytes themselves
	set codes {}
	foreach lo $b {
		if {$lo >= 0x3F && $lo <= 0x7E} {
			lappend codes $lo
		} else {
			break
		}
	}
	return [sixbit-decode $codes]
}

# ---------------------------------------------------------------------
# decode one record (hex-byte list) into an event dict (unused by the
# main flow — kept as a documented per-record helper)
# ---------------------------------------------------------------------

proc parseRecord {rec} {
	if {[llength $rec] < 4} { return {} }
	binary scan [binary format H* [join [lrange $rec 0 3] {}]] i opcode

	set result [dict create opcode $opcode name [opcodeName $opcode]]

	switch -- $opcode {
		3 {
			# GotoIndex: index at +4 (pad the trimmed tail with zeros)
			set tail [join [lrange $rec 4 end] {}]
			if {[string length $tail] > 8} { set tail [string range $tail 0 7] }
			append tail [string repeat 0 [expr {max(0, 8 - [string length $tail])}]]
			binary scan [binary format H* $tail] i idx
			dict set result gotoIndex $idx
		}
		4 {
			# board action: class u32le + 2 file-major squares + modifier u16le
			if {[llength $rec] >= 12} {
				binary scan [binary format H* [join [lrange $rec 4 11] {}]] iccs class s0 s1 mod
				dict set result class [format %x $class]
				dict set result from [sq0 $s0]
				dict set result to [sq0 $s1]
				dict set result modifier $mod
			}
		}
	}
	return $result
}

# ---------------------------------------------------------------------
# main entry: decode the script stream from a media-lesson video.
# Returns a list of entry dicts:
#   {opcode name pkt ms type gotoIndex from to class modifier}
# ms = packet pts (media milliseconds); type = navigate|board-action|
# annotation|{}; pkt = packet index (diagnostics).
# ---------------------------------------------------------------------

# ---------------------------------------------------------------------
# WP1 (Media Lesson v2): parse a CBase26 .txt sidecar export.
#
# Format (verified against the Biel 2015 round-08 fixture): one event per
# two lines - an "H:MM:SS.d:" timestamp line, then "GA:" + the six-bit
# transport payload (chars '?'..'~' = 0x3F..0x7E, 6 bits each, MSB-first,
# 4 chars -> 3 bytes).  The payload decodes to [u32le opcode][payload].
#
# Returns a dict:
#   events      list of {ms opcode hex} in file order (hex = payload
#               bytes after the opcode word)
#   gotos       {ms cursor} for opcode 3
#   actions     {ms class from to modifier} for opcode 4 (file-major
#               squares, algebraic)
#   annotations {ms count}
#   checkpoints list of {ms size hex} for opcode 2 (cumulative game
#               snapshots; the LAST one is the authoritative state -
#               Reader renders from checkpoints, not deltas - see
#               CHESSBASE_MEDIA_RE.md "Reader14 on genuine Windows")
#   counts      {total goto action annotation sync checkpoint other}
# ---------------------------------------------------------------------

proc sidecar-parse {txtPath} {
	set fh [open $txtPath r]
	fconfigure $fh -encoding utf-8 -translation auto
	set lines [split [read $fh] "\n"]
	close $fh

	set events {}
	set gotos {}
	set actions {}
	set annotations {}
	set checkpoints {}
	set cTotal 0; set cGoto 0; set cAction 0; set cAnn 0; set cSync 0; set cCp 0; set cOther 0

	set pendingMs -1
	foreach line $lines {
		set line [string trim $line]
		if {$line eq ""} { continue }

		if {[string index $line end] eq ":" && [string index $line 0] ne "G"} {
			# timestamp line: H:MM:SS.d:
			if {[regexp {^(\d+):(\d+):(\d+)\.(\d+):$} $line -> h m s d]} {
				scan $h %d h; scan $m %d m; scan $s %d s; scan $d %d d
				set pendingMs [expr {(($h * 60 + $m) * 60 + $s) * 1000 + $d * 100}]
			}
			continue
		}

		if {![string match "GA:*" $line]} { continue }
		if {$pendingMs < 0} { continue }

		# six-bit transport, char-direct: the payload after "GA:"
		set codes {}
		foreach ch [split [string range $line 3 end] ""] {
			scan $ch %c code
			if {$code < 0x3F || $code > 0x7E} { break }
			lappend codes $code
		}
		if {[llength $codes] < 4} { continue }

		set bytes {}
		set value 0
		set bitcount 0
		foreach c $codes {
			set value [expr {(($value << 6) | ($c - 0x3F)) & 0xFFFFFFFF}]
			incr bitcount 6
			if {$bitcount >= 8} {
				incr bitcount -8
				lappend bytes [format %02x [expr {($value >> $bitcount) & 0xFF}]]
			}
		}
		if {[llength $bytes] < 4} { continue }

		binary scan [binary format H* [join [lrange $bytes 0 3] {}]] i opcode
		if {$opcode < 0} { set opcode [expr {$opcode + 4294967296}] }

		set payload [lrange $bytes 4 end]
		incr cTotal

		set type other
		switch -- $opcode {
			2 {
				set type checkpoint
				incr cCp
				lappend checkpoints [list $pendingMs [llength $bytes] [join $bytes {}]]
			}
			3 {
				set type goto
				incr cGoto
				set tail [join $payload {}]
				if {[string length $tail] > 8} { set tail [string range $tail 0 7] }
				append tail [string repeat 0 [expr {max(0, 8 - [string length $tail])}]]
				binary scan [binary format H* $tail] i cursor
				if {$cursor < 0} { set cursor [expr {$cursor + 4294967296}] }
				lappend gotos [list $pendingMs $cursor]
			}
			4 {
				set type board-action
				incr cAction
				if {[llength $payload] >= 8} {
					binary scan [binary format H* [join [lrange $payload 0 7] {}]] iccs class from to mod
					if {$class < 0} { set class [expr {$class + 4294967296}] }
					lappend actions [list $pendingMs [format %x $class] [sq0 $from] [sq0 $to] $mod]
				}
			}
			6 {
				set type annotation
				incr cAnn
				lappend annotations $pendingMs
			}
			14 {
				set type sync
				incr cSync
			}
		}

		if {$type eq "other"} { incr cOther }
		lappend events [list $pendingMs $type [join $bytes {}]]
		set pendingMs -1
	}

	return [dict create \
		events $events gotos $gotos actions $actions \
		annotations $annotations checkpoints $checkpoints \
		counts [dict create total $cTotal goto $cGoto action $cAction \
			annotation $cAnn sync $cSync checkpoint $cCp other $cOther]]
}



proc decode {wmvPath} {
	set cmdline [list ffprobe -v error -select_streams d \
		-show_packets -show_data -of json [file normalize $wmvPath]]
	if {[catch { set fh [open [concat | $cmdline] r] } err]} {
		log "ffprobe pipeline failed: $err"
		return [list]
	}
	set json [read $fh]
	catch { ::close $fh }

	# ffprobe -of json emits one flat object per packet; pair each
	# packet's data hex with its pts_time (media seconds)
	set packets {}
	foreach obj [jsonObjects $json] {
		set data {}
		regexp {"data":\s*"([^"]*)"} $obj -> data
		if {![string length $data]} { continue }
		set data [hexdump2hex $data]
		set pt {}
		regexp {"pts_time":\s*"?([0-9][0-9.eE+-]*)"?} $obj -> pt
		set ms 0
		if {[string length $pt] && ![catch { set ms [expr {int($pt*1000.0)}] }]} {
			if {$ms < 0} { set ms 0 }
		}
		lappend packets [list $ms $data]
	}

	set decoded {}
	set lastMs 0
	set pktIdx 0
	foreach p $packets {
		lassign $p ms datahex
		if {$ms > 0} { set lastMs $ms } else { set ms $lastMs }
		incr pktIdx

		set record [decodeCommand $datahex]
		if {[llength $record] < 4} { continue }

		binary scan [binary format H* [join [lrange $record 0 3] {}]] i opcode
		set entry [dict create \
			opcode $opcode \
			name   [opcodeName $opcode] \
			pkt    $pktIdx \
			ms     $ms \
		]

		switch -- $opcode {
			3 {
				# navigate: absolute replay-step target at this media-ms
				set tail [join [lrange $record 4 end] {}]
				if {[string length $tail] > 8} { set tail [string range $tail 0 7] }
				append tail [string repeat 0 [expr {max(0, 8 - [string length $tail])}]]
				binary scan [binary format H* $tail] i gotoIdx
				if {$gotoIdx < 0} { set gotoIdx [expr {$gotoIdx + 4294967296}] }
				dict set entry gotoIndex $gotoIdx
				dict set entry type navigate
			}
			4 {
				# board action: class u32le + 2 file-major squares + modifier u16le
				set rec2 [_trim $record]
				if {[llength $rec2] >= 12} {
					binary scan [binary format H* [join [lrange $rec2 4 11] {}]] iccs class from to mod
					dict set entry from [sq0 $from]
					dict set entry to [sq0 $to]
					dict set entry class [format %x $class]
					dict set entry modifier $mod
					dict set entry type board-action
				}
			}
			6 {
				# annotation: count u16le at +8, sub-records from +10:
				# u16 length + u32 type + payload
				if {[llength $record] >= 10} {
					binary scan [binary format H* [join [lrange $record 8 9] {}]] S cnt
					set rpos 10
					set anns 0
					for {set r 0} {$r < $cnt && $rpos + 2 <= [llength $record]} {incr r} {
						binary scan [binary format H* [join [lrange $record $rpos [expr {$rpos + 1}]] {}]] S recLen
						if {$recLen < 6 || $rpos + 2 + $recLen > [llength $record]} { break }
						incr anns
						set rpos [expr {$rpos + 2 + $recLen}]
					}
					if {$anns} {
						dict set entry type annotation
						dict set entry count $anns
					}
				}
			}
		}
		lappend decoded $entry
	}
	return $decoded
}

} ;# namespace eval ::media::decoder

# vi:set ts=3 sw=3:
# ARCHIVED EXPERIMENT — not loaded by Scidb; RE reference only.
