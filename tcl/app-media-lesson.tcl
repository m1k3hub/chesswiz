# ======================================================================
# ::media::lesson — the coupled media-lesson datatype
# ======================================================================
# A media lesson is ONE datatype: video commentary + game moves + the
# board-sync timeline coupling them.  Neither part is playable without
# the other (::application::media::PlayLesson enforces the coupling).
#
# The lesson is BUILT ONCE per video (script-stream decode via
# ::media::decoder) and cached here; a later phase persists it into the
# .cms [BoardSync] section (SCM_FORMAT_DESIGN.md §1.6) so the decode
# never runs again for the same entry.
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

# Fetch (or build) the lesson for a video.
proc get {videoPath} {
	variable Cache
	set k [key $videoPath]
	if {[info exists Cache($k)]} { return $Cache($k) }
	return [build $videoPath]
}

# Drop a cached lesson (e.g. after the media file changed).
proc flush {videoPath} {
	variable Cache
	set k [key $videoPath]
	catch { unset Cache($k) }
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
	catch {
		::application::media::MediaDebug \
			"lesson::build: [llength $timeline] timeline marks, [llength $events] events from [file tail $k]"
	}
	return $lesson
}

} ;# namespace eval ::media::lesson

# vi:set ts=3 sw=3:
