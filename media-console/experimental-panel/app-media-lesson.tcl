# ======================================================================
# ::media::lesson — the coupled media-lesson datatype
# ======================================================================
# A media lesson is ONE datatype: video commentary + game moves + the
# board-sync timeline coupling them.  Neither part is playable without
# the other (::application::media::PlayLesson enforces the coupling).
#
# The lesson is BUILT ONCE per video (script-stream decode via
# ::media::decoder), cached here, and PERSISTED in a sidecar under the
# scidb user directory so the decode never runs again for the same
# entry. ChessBase files are never mutated: the sidecar lives in the
# user config dir, keyed by the normalized video path, and is
# invalidated when the video's mtime passes the sidecar's.
#
# Lesson dict (v2, WP4 - docs/MEDIA_LESSON_V2_PLAN.md):
#   valid      1|0
#   reason     {} | human-readable failure reason
#   video      normalized video path
#   source     sidecar | wmv   (v2: the CBase26 .txt export next to the
#              video is preferred; wmv = the ffprobe fallback, the v1
#              degraded behaviour)
#   edges      list of {from to} FILE-MAJOR 0-based square ints — the
#              checkpoint's serialized game-tree edge stream (WP2)
#   positions  per-node FEN list; index 0 = the start position, index
#              k+1 = the position after edge k (the DFS node id the
#              goto cursors address).  STANDARD FEN dialect — the
#              ScidB R-new2 conversion is a WP6 boundary concern.
#              main-line nodes only: the off-mainline nodes live in
#              patch slots whose per-slot semantics are open (see
#              docs/CHESSBASE_MEDIA_RE.md), so positions covers the walkable
#              tree; gotos beyond it are a WP5 clamp/degrade concern.
#   timeline   list of {mediaMs nodeIndex} pairs, ascending by mediaMs
#   events     list of {ms arrow from to class modifier} board events
#              (payload order matches SyncAnnotate: lassign data from to
#              style.  NOTE: the value in the style slot is the raw
#              opcode-04 CLASS (0x80 = directional arrows, 0x200, ...),
#              NOT an opcode-06 mark style.  It therefore never matches
#              the SyncColors table and every opcode-04 arrow falls back
#              to the default green.  VISUAL-ORACLE CLOSED (Reader14 VM,
#              2026-09-07): script-stream annotations render green
#              regardless of style/class byte - no colour exists in the
#              stream, so the green fallback is provably correct; see
#              docs/CHESSBASE_MEDIA_RE.md "Reader14 on genuine Windows".)
#   nodeTimes  list of {node mediaMs} pairs from type-37 records in the
#              checkpoint collections ({} when the lesson has none)
# ======================================================================

namespace eval ::media::lesson {

variable Cache                     ;# array: key -> lesson dict

proc key {videoPath} {
	return [file normalize $videoPath]
}

# Fetch (or build) the lesson for a video. Order: in-memory cache,
# then a fresh sidecar, then the (expensive) decode.
proc get {videoPath} {
	variable Cache
	set k [key $videoPath]
	if {[info exists Cache($k)]} { return $Cache($k) }
	set lesson [loadFromSidecar $videoPath]
	if {[dict size $lesson]} { return $lesson }
	return [build $videoPath]
}

# Sidecar path for a video: deterministic, derived from the normalized
# video path (every path separator and colon becomes an underscore,
# truncated to 180 chars). Pure - no I/O, safe to call for any path.
# NOTE: the truncation makes collisions theoretically possible for very
# long common prefixes; no ready-made hash utility exists in the Tcl
# layer, so the derivation stays name-based by design.
proc sidecarPath {videoPath} {
	set name [file normalize $videoPath]
	set name [string map {/ _ \\ _ : _} $name]
	if {[string length $name] > 180} {
		set name [string range $name 0 179]
	}
	return [file join $::scidb::dir::user media lessons "$name.lesson"]
}

# Write a valid lesson to its sidecar. Invalid lessons are never
# persisted (they are cheap to re-derive and would poison the cache).
# Returns 1 on success, 0 when nothing was written.
proc persist {videoPath lesson} {
	if {![dict exists $lesson valid] || ![dict get $lesson valid]} { return 0 }

	set path [sidecarPath $videoPath]
	set dir [file dirname $path]
	if {![file isdirectory $dir]} {
		if {[catch { file mkdir $dir }]} { return 0 }
	}

	# serialize the dict verbatim (keeps the shape and the source field
	# if present) + a save timestamp; written as ONE Tcl list
	set row [list]
	dict for {key value} $lesson { lappend row $key $value }
	lappend row saved [clock seconds]

	if {[catch {
		set fh [open $path w]
		fconfigure $fh -encoding utf-8
		puts $fh $row
		close $fh
	}]} { return 0 }

	return 1
}

# Load a lesson from its sidecar. Returns the lesson dict (and fills the
# in-memory cache), or an empty dict when: no sidecar exists, the video
# is newer than the sidecar (the decode is stale), the sidecar does not
# parse, is invalid, or names a different video.
proc loadFromSidecar {videoPath} {
	variable Cache
	set k [key $videoPath]
	set path [sidecarPath $k]

	if {![file exists $path]} { return {} }
	if {![file exists $k]} { return {} }
	if {[file mtime $path] < [file mtime $k]} { return {} }

	set row {}
	if {[catch {
		set fh [open $path r]
		fconfigure $fh -encoding utf-8
		set row [read $fh]
		close $fh
	}]} { return {} }

	if {![string is list -strict $row]} { return {} }
	if {[llength $row] == 0 || [llength $row] % 2 != 0} { return {} }

	set lesson [dict create]
	foreach {key value} $row {
		if {$key eq "saved"} { continue }
		dict set lesson $key $value
	}

	if {![dict exists $lesson valid]} { return {} }
	if {![dict get $lesson valid]} { return {} }
	if {![dict exists $lesson video] || [dict get $lesson video] ne $k} { return {} }
	# v2 shape guard: lessons persisted by the pre-sidecar decoder carry
	# valid=1 with an empty timeline and no positions key - accepting them
	# would cache-hit forever and never decode the script stream
	if {![dict exists $lesson positions]} { return {} }

	set Cache($k) $lesson
	return $lesson
}

# Drop a cached lesson (e.g. after the media file changed). The sidecar
# is deleted as well so the next get() re-decodes from scratch.
proc flush {videoPath} {
	variable Cache
	set k [key $videoPath]
	catch { unset Cache($k) }
	catch {
		set path [sidecarPath $k]
		if {[file exists $path]} { file delete -force $path }
	}
}

# ---------------------------------------------------------------------
# WP3 (Media Lesson v2): pure-Tcl move applier.
#
# Applies the checkpoint's edge stream (file-major 0-based squares,
# DFS-serialized with variations interleaved) from the standard start
# and produces per-node FENs: positions(0) = the start position,
# positions(k+1) = the position after edge k.  The walk is
# tree-structured: an edge either extends the current line or rewinds
# to an ancestor (a variation branch) — the applier pops the line until
# the edge is fully legal, exactly like the python-chess oracle
# (wp2_checkpoint_oracle.py, the proven reference; the WP3 oracle gate
# byte-compares every FEN against it).
#
# Board representation: a 64-char string, index 0 = a1, 63 = h8
# (rank-major: file = idx & 7, rank = idx >> 3), '.' = empty.
# Edge byte v (FILE-MAJOR: file = v>>3, rank = v&7) maps to
# idx = (v & 7) * 8 + (v >> 3).
#
# Castling is the king-two-squares form (e1g1/e1c1/e8g8/e8c8) with
# full python-chess legality: rights present, path empty, king square
# and the passed square not attacked.  En passant and promotion are
# handled; the promotion piece flag is not in the edge stream (open
# RE item — no fixture contains one), so promotions default to the
# queen and are logged — matching the oracle's first-match policy.
#
# FENs are STANDARD dialect; the ScidB R-new2 conversion happens at
# the WP6 boundary (::scidb::game::go), not here.
# ---------------------------------------------------------------------

# edge file-major byte -> board index
proc _sq {v} { return [expr {($v & 7) * 8 + ($v >> 3)}] }

proc _piece-color {p} {
	if {$p eq "."} { return "" }
	if {$p eq [string toupper $p]} { return "w" }
	return "b"
}

proc _start-state {} {
	# index 0 = a1 .. 63 = h8 (rank-major): rank 1 first
	set board "RNBQKBNRPPPPPPPP................................pppppppprnbqkbnr"
	return [list $board w KQkq - 0 1]
}

# index of the given side's king
proc _king-idx {board color} {
	set k [expr {$color eq "w" ? "K" : "k"}]
	set i [string first $k $board]
	return $i
}

# is square sq attacked by side 'by' on board?
proc _attacked {board sq by} {
	set f [expr {$sq & 7}]
	set r [expr {$sq >> 3}]
	# pawns (by-side pawns attack toward sq)
	if {$by eq "w"} {
		if {$r > 0} {
			if {$f > 0 && [string index $board [expr {$sq - 9}]] eq "P"} { return 1 }
			if {$f < 7 && [string index $board [expr {$sq - 7}]] eq "P"} { return 1 }
		}
	} else {
		if {$r < 7} {
			if {$f > 0 && [string index $board [expr {$sq + 7}]] eq "p"} { return 1 }
			if {$f < 7 && [string index $board [expr {$sq + 9}]] eq "p"} { return 1 }
		}
	}
	# knights
	set N [expr {$by eq "w" ? "N" : "n"}]
	foreach {dr df} {1 2 2 1 -1 2 -2 1 1 -2 2 -1 -1 -2 -2 -1} {
		set rr [expr {$r + $dr}]
		set ff [expr {$f + $df}]
		if {$rr >= 0 && $rr <= 7 && $ff >= 0 && $ff <= 7} {
			if {[string index $board [expr {$rr * 8 + $ff}]] eq $N} { return 1 }
		}
	}
	# king
	set K [expr {$by eq "w" ? "K" : "k"}]
	for {set dr -1} {$dr <= 1} {incr dr} {
		for {set df -1} {$df <= 1} {incr df} {
			if {$dr == 0 && $df == 0} { continue }
			set rr [expr {$r + $dr}]
			set ff [expr {$f + $df}]
			if {$rr >= 0 && $rr <= 7 && $ff >= 0 && $ff <= 7} {
				if {[string index $board [expr {$rr * 8 + $ff}]] eq $K} { return 1 }
			}
		}
	}
	# sliding: rook/queen rays
	set R [expr {$by eq "w" ? "R" : "r"}]
	set B [expr {$by eq "w" ? "B" : "b"}]
	set Q [expr {$by eq "w" ? "Q" : "q"}]
	foreach {dr df} {1 0 -1 0 0 1 0 -1} {
		set rr $r ; set ff $f
		while {1} {
			set rr [expr {$rr + $dr}]
			set ff [expr {$ff + $df}]
			if {$rr < 0 || $rr > 7 || $ff < 0 || $ff > 7} { break }
			set q [string index $board [expr {$rr * 8 + $ff}]]
			if {$q eq "."} { continue }
			if {$q eq $R || $q eq $Q} { return 1 }
			break
		}
	}
	# sliding: bishop/queen rays
	foreach {dr df} {1 1 1 -1 -1 1 -1 -1} {
		set rr $r ; set ff $f
		while {1} {
			set rr [expr {$rr + $dr}]
			set ff [expr {$ff + $df}]
			if {$rr < 0 || $rr > 7 || $ff < 0 || $ff > 7} { break }
			set q [string index $board [expr {$rr * 8 + $ff}]]
			if {$q eq "."} { continue }
			if {$q eq $B || $q eq $Q} { return 1 }
			break
		}
	}
	return 0
}

# try to match edge (from,to) at state as a fully legal move.
# returns the move descriptor {from to kind} or "".
proc _find-move {state from to} {
	lassign $state board side castling ep half full
	set p [string index $board $from]
	if {$p eq "."} { return "" }
	set color [_piece-color $p]
	if {$color ne $side} { return "" }
	set q [string index $board $to]
	set capture [expr {$q ne "."}]
	if {$capture && [_piece-color $q] eq $side} { return "" }

	set ff [expr {$from & 7}]
	set fr [expr {$from >> 3}]
	set tf [expr {$to & 7}]
	set tr [expr {$to >> 3}]
	set kind ""

	switch -- [string toupper $p] {
		P {
			set dir [expr {$side eq "w" ? 1 : -1}]
			set start [expr {$side eq "w" ? 1 : 6}]
			set last [expr {$side eq "w" ? 7 : 0}]
			if {!$capture} {
				# push
				if {$tf == $ff && $tr == $fr + $dir} {
					set kind push
				}
				# double push
				if {$tf == $ff && $tr == $fr + 2 * $dir && $fr == $start \
					&& [string index $board [expr {($fr + $dir) * 8 + $ff}]] eq "."} {
					set kind double
				}
				# en passant
				if {$ep ne "-" && $to == [_sq-index $ep] && $tr == $fr + $dir \
					&& ($tf == $ff + 1 || $tf == $ff - 1)} {
					set kind ep
				}
			} else {
				if {$tr == $fr + $dir && ($tf == $ff + 1 || $tf == $ff - 1)} {
					set kind capture
				}
			}
			if {$kind ne "" && $tr == $last} {
				# promotion piece flag is not in the stream (open RE item);
				# default queen, same as the oracle's first-match policy
				catch { ::application::media::MediaDebug "lesson: promotion at [_sq-name $to] defaults to queen (flag not decoded)" }
				set kind "promo-$kind"
			}
		}
		N {
			set dr [expr {abs($tr - $fr)}]
			set df [expr {abs($tf - $ff)}]
			if {($dr == 1 && $df == 2) || ($dr == 2 && $df == 1)} { set kind normal }
		}
		B {
			if {$tr != $fr && abs($tr - $fr) == abs($tf - $ff) \
				&& [_clear $board $from $to 1]} { set kind normal }
		}
		R {
			if {($tr == $fr || $tf == $ff) && [_clear $board $from $to 0]} { set kind normal }
		}
		Q {
			if {(($tr != $fr && abs($tr - $fr) == abs($tf - $ff)) || $tr == $fr || $tf == $ff) \
				&& [_clear $board $from $to -1]} { set kind normal }
		}
		K {
			if {abs($tr - $fr) <= 1 && abs($tf - $ff) <= 1} {
				set kind normal
			} else {
				# castling: king two squares on the home rank with rights,
				# empty path, safe squares (python-chess legality)
				if {$side eq "w" && $from == 4} {
					if {$to == 6 && [string first "K" $castling] >= 0 \
						&& [string index $board 5] eq "." && [string index $board 6] eq "." \
						&& ![_attacked $board 4 b] && ![_attacked $board 5 b] && ![_attacked $board 6 b]} {
						set kind castle-k
					}
					if {$to == 2 && [string first "Q" $castling] >= 0 \
						&& [string index $board 1] eq "." && [string index $board 2] eq "." \
						&& [string index $board 3] eq "." \
						&& ![_attacked $board 4 b] && ![_attacked $board 3 b] && ![_attacked $board 2 b]} {
						set kind castle-q
					}
				}
				if {$side eq "b" && $from == 60} {
					if {$to == 62 && [string first "k" $castling] >= 0 \
						&& [string index $board 61] eq "." && [string index $board 62] eq "." \
						&& ![_attacked $board 60 w] && ![_attacked $board 61 w] && ![_attacked $board 62 w]} {
						set kind castle-k
					}
					if {$to == 58 && [string first "q" $castling] >= 0 \
						&& [string index $board 57] eq "." && [string index $board 58] eq "." \
						&& [string index $board 59] eq "." \
						&& ![_attacked $board 60 w] && ![_attacked $board 59 w] && ![_attacked $board 58 w]} {
						set kind castle-q
					}
				}
			}
		}
	}
	if {$kind eq ""} { return "" }

	# king safety (castling safety already checked on path squares)
	set newstate [_apply-move $state [list $from $to $kind]]
	lassign $newstate newboard newside
	set k [_king-idx $newboard $side]
	if {$k < 0} { return "" }
	if {[_attacked $newboard $k [expr {$side eq "w" ? "b" : "w"}]]} { return "" }

	return [list $from $to $kind]
}

# ray clear between from and to; diagonal 1, orthogonal 0, any -1
proc _clear {board from to mode} {
	set ff [expr {$from & 7}] ; set fr [expr {$from >> 3}]
	set tf [expr {$to & 7}] ; set tr [expr {$to >> 3}]
	set dr [expr {$tr == $fr ? 0 : ($tr > $fr ? 1 : -1)}]
	set df [expr {$tf == $ff ? 0 : ($tf > $ff ? 1 : -1)}]
	if {$mode == 1 && abs($dr) != abs($df)} { return 0 }
	if {$mode == 0 && ($dr != 0 && $df != 0)} { return 0 }
	set rr [expr {$fr + $dr}]
	set cc [expr {$ff + $df}]
	while {$rr != $tr || $cc != $tf} {
		if {[string index $board [expr {$rr * 8 + $cc}]] ne "."} { return 0 }
		set rr [expr {$rr + $dr}]
		set cc [expr {$cc + $df}]
	}
	return 1
}

# algebraic name <-> index
proc _sq-name {idx} {
	return [string index "abcdefgh" [expr {$idx & 7}]][expr {($idx >> 3) + 1}]
}
proc _sq-index {name} {
	set f [string first [string index $name 0] "abcdefgh"]
	scan [string index $name 1] %d r
	return [expr {($r - 1) * 8 + $f}]
}

# apply a move descriptor; returns the new state
proc _apply-move {state mv} {
	lassign $state board side castling ep half full
	lassign $mv from to kind
	set p [string index $board $from]
	set capture [expr {[string index $board $to] ne "." || $kind eq "ep"}]

	# move the piece
	set board [string replace $board $from $from "."]
	set np $p
	if {[string match "promo-*" $kind]} { set np [expr {$side eq "w" ? "Q" : "q"}] }
	set board [string replace $board $to $to $np]

	# en passant: remove the captured pawn
	if {$kind eq "ep"} {
		set capt [expr {$side eq "w" ? $to - 8 : $to + 8}]
		set board [string replace $board $capt $capt "."]
	}
	# castling: move the rook
	if {$kind eq "castle-k"} {
		if {$side eq "w"} {
			set board [string replace $board 7 7 "."]
			set board [string replace $board 5 5 "R"]
		} else {
			set board [string replace $board 63 63 "."]
			set board [string replace $board 61 61 "r"]
		}
	}
	if {$kind eq "castle-q"} {
		if {$side eq "w"} {
			set board [string replace $board 0 0 "."]
			set board [string replace $board 3 3 "R"]
		} else {
			set board [string replace $board 56 56 "."]
			set board [string replace $board 59 59 "r"]
		}
	}

	# castling rights
	if {$p eq "K"} { regsub -all {KQ} $castling "" castling }
	if {$p eq "k"} { regsub -all {kq} $castling "" castling }
	foreach sq {0 7 56 63} {
		if {$from == $sq || ($to == $sq && $capture)} {
			switch -- $sq {
				0 { regsub {Q} $castling "" castling }
				7 { regsub {K} $castling "" castling }
				56 { regsub {q} $castling "" castling }
				63 { regsub {k} $castling "" castling }
			}
		}
	}
	if {$castling eq ""} { set castling "-" }

	# ep target
	if {$kind eq "double"} {
		set ep [_sq-name [expr {$side eq "w" ? $from + 8 : $from - 8}]]
	} else {
		set ep "-"
	}

	# clocks
	if {$p eq "P" || $p eq "p" || $capture} {
		set half 0
	} else {
		incr half
	}
	if {$side eq "b"} { incr full }

	return [list $board [expr {$side eq "w" ? "b" : "w"}] $castling $ep $half $full]
}

# serialize a state to a standard FEN
proc _state-fen {state} {
	lassign $state board side castling ep half full
	set rows {}
	for {set r 7} {$r >= 0} {incr r -1} {
		set row ""
		set empty 0
		for {set f 0} {$f < 8} {incr f} {
			set p [string index $board [expr {$r * 8 + $f}]]
			if {$p eq "."} {
				incr empty
			} else {
				if {$empty} { append row $empty ; set empty 0 }
				append row $p
			}
		}
		if {$empty} { append row $empty }
		lappend rows $row
	}
	if {$castling eq ""} { set castling "-" }
	return "[join $rows /] $side $castling $ep $half $full"
}

# WP3 entry: apply the edge stream, return {positions {}} or
# {positions {}} on success; returns {{} reason} on failure.
proc apply-edges {edges} {
	set state [_start-state]
	set stack [list $state]
	set positions [list [_state-fen $state]]
	set k 0
	foreach edge $edges {
		lassign $edge from to
		set from [_sq $from]
		set to [_sq $to]
		set mv ""
		while {[llength $stack]} {
			set st [lindex $stack end]
			set mv [_find-move $st $from $to]
			if {$mv ne ""} { break }
			set stack [lrange $stack 0 end-1]
		}
		if {$mv eq ""} {
			return [list {} [list "illegal or unresolvable edge at index $k"]]
		}
		set new [_apply-move $st $mv]
		lappend stack $new
		lappend positions [_state-fen $new]
		incr k
	}
	return [list $positions {}]
}


# Build the lesson for a video (decode ONCE, cache + persist).
#
# v2 flow (WP4): prefer the CBase26 .txt sidecar export next to the
# video (source=sidecar): gotos -> timeline, actions -> events, the
# LAST checkpoint -> parse-checkpoint -> edges -> apply-edges ->
# positions.  When no .txt exists, fall back to the v1 ffprobe decode
# (source=wmv; degraded behaviour, documented in the plan's R5/R10).
proc build {videoPath} {
	variable Cache
	set k [key $videoPath]

	set lesson [dict create \
		valid    0 \
		reason   {} \
		video    $k \
		source   wmv \
		timeline {} \
		events   {} \
	]

	if {![file exists $k]} {
		dict set lesson reason "video file missing"
		set Cache($k) $lesson
		return $lesson
	}

	if {![llength [info commands ::media::decoder::sidecar-parse]]} {
		dict set lesson reason "script decoder unavailable"
		set Cache($k) $lesson
		return $lesson
	}

	# ---- v2: the CBase26 .txt export next to the video
	set txt [file rootname $k].txt
	if {[file exists $txt]} {
		set sd {}
		if {[catch { set sd [::media::decoder::sidecar-parse $txt] } err]} {
			dict set lesson reason "sidecar decode failed: $err"
			set Cache($k) $lesson
			return $lesson
		}

		set timeline {}
		foreach g [dict get $sd gotos] {
			lassign $g ms node
			if {$node < 0} { set node 0 }
			lappend timeline [list $ms $node]
		}
		set timeline [lsort -integer -index 0 $timeline]

		set events {}
		foreach a [dict get $sd actions] {
			lassign $a ms class from to mod
			lappend events [list $ms arrow $from $to $class $mod]
		}
		set events [lsort -integer -index 0 $events]

		set cps [dict get $sd checkpoints]
		if {![llength $cps]} {
			dict set lesson reason "sidecar carries no checkpoint"
			set Cache($k) $lesson
			return $lesson
		}
		# cumulative snapshots: the last is the authoritative state
		# (Reader14 renders from checkpoints; docs/CHESSBASE_MEDIA_RE.md)
		set lastCp [lindex $cps end]
		set cp {}
		if {[catch { set cp [::media::decoder::parse-checkpoint [lindex $lastCp 2]] } err]} {
			dict set lesson reason "checkpoint decode failed: $err"
			set Cache($k) $lesson
			return $lesson
		}
		if {[dict exists $cp error]} {
			dict set lesson reason "checkpoint decode failed: [dict get $cp error]"
			set Cache($k) $lesson
			return $lesson
		}

		set edges [dict get $cp edges]
		lassign [apply-edges $edges] positions applyErr
		if {$applyErr ne ""} {
			dict set lesson reason "move applier failed: $applyErr"
			catch { ::application::media::MediaDebug "lesson::build: $applyErr" }
			set Cache($k) $lesson
			return $lesson
		}

		# type-37 per-node times from the checkpoint collections ({} when
		# the lesson has none)
		set nodeTimes {}
		foreach c [dict get $cp collections] {
			lassign $c node rtype ph
			if {$rtype == 37 && [string length $ph] == 8} {
				binary scan [binary format H* $ph] I ms
				lappend nodeTimes [list $node $ms]
			}
		}

		dict set lesson source   sidecar
		dict set lesson edges    $edges
		dict set lesson positions $positions
		dict set lesson nodeTimes $nodeTimes
		dict set lesson cursor    [dict get $cp cursor]
		dict set lesson timeline $timeline
		dict set lesson events   $events
		dict set lesson valid    1
		set Cache($k) $lesson
		catch { persist $k $lesson }
		catch {
			::application::media::MediaDebug \
				"lesson::build: sidecar lesson: [llength $timeline] timeline marks, [llength $positions] positions, [llength $events] events"
		}
		return $lesson
	}

	# ---- v1 fallback: ffprobe decode (source=wmv, degraded)
	if {![llength [info commands ::media::decoder::decode]]} {
		dict set lesson reason "script decoder unavailable"
		set Cache($k) $lesson
		return $lesson
	}

	set decoded {}
	if {[catch { set decoded [::media::decoder::decode $k] } err]} {
		dict set lesson reason "script decode failed: $err"
		catch { ::application::media::MediaDebug "lesson::build: $err" }
		set Cache($k) $lesson
		return $lesson
	}

	set timeline {}
	set events {}
	foreach entry $decoded {
		set op [dict get $entry opcode]
		if {$op == 3} {
			# navigate: absolute replay-step target at this media-ms
			set idx 0
			if {[dict exists $entry gotoIndex]} {
				set idx [dict get $entry gotoIndex]
				if {$idx < 0} { set idx 0 }
			}
			lappend timeline [list [dict get $entry ms] $idx]
		} elseif {[dict exists $entry type] && [dict get $entry type] eq "board-action"} {
			lappend events [list \
				[dict get $entry ms] \
				arrow \
				[dict get $entry from] \
				[dict get $entry to] \
				[dict get $entry class] \
				[dict get $entry modifier] \
			]
		}
	}

	# _fire_events walks both lists with an ascending cursor: sort by ms
	set timeline [lsort -integer -index 0 $timeline]

	dict set lesson timeline $timeline
	dict set lesson events $events
	# v2 shape: node-goal sync requires the positions key even when the
	# degraded v1 decode has no per-node FEN list (an empty list simply
	# disables node resolution)
	dict set lesson positions {}
	dict set lesson valid 1
	set Cache($k) $lesson

	# persist only valid decodes (the sidecar is the cross-restart cache)
	catch { persist $k $lesson }
	catch {
		::application::media::MediaDebug \
			"lesson::build: [llength $timeline] timeline marks, [llength $events] events from [file tail $k]"
	}
	return $lesson
}

} ;# namespace eval ::media::lesson

# vi:set ts=3 sw=3:
# ARCHIVED EXPERIMENT — not loaded by Scidb; RE reference only.
