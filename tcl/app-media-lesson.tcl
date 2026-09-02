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
# Lesson dict:
#   valid      1|0
#   reason     {} | human-readable failure reason
#   video      normalized video path
#   timeline   list of {mediaMs gotoIndex} pairs, ascending by mediaMs
#   events     list of {ms arrow from to class modifier} board events
#              (payload order matches SyncAnnotate: lassign data from to
#              style, with class = the SyncColors style key)
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

# Build the lesson from the video's script stream (decode ONCE, cache).
proc build {videoPath} {
	variable Cache
	set k [key $videoPath]

	set lesson [dict create \
		valid    0 \
		reason   {} \
		video    $k \
		timeline {} \
		events   {} \
	]

	if {![file exists $k]} {
		dict set lesson reason "video file missing"
		set Cache($k) $lesson
		return $lesson
	}

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
