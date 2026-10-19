# ======================================================================
# ::media::mpv — in-process libmpv transport
# ======================================================================
# The player lives inside the application (src/tcl/tcl_media.cpp provides
# ::mpv::open/get/set/close) and draws into the media pane's canvas
# through --wid. Reading a property is a function call, so the follow
# and seek ticks never wait on a socket or a helper process.
#
# Vocabulary used by the panel wrappers (SyncTransport/FollowTick):
#   state  -> playing | paused | ended | idle | error
#   time   -> seconds (double), duration -> seconds (double); {} if unknown
# ======================================================================

::util::source media-mpv

namespace eval ::media::mpv {
	variable LaunchError {}
	namespace export launch stop time duration state play pause seek available? volume setVolume aspect chapters
}

# Was the native player linked into this build?
proc ::media::mpv::available? {} {
	return [expr {[llength [info commands ::mpv::open]] > 0}]
}

# Start playing path from startMs, embedded into window wid (as given by
# winfo id). Returns 1 once the player accepted the file.
proc ::media::mpv::launch {path wid {startMs 0}} {
	variable LaunchError
	set LaunchError {}
	if {![available?]} { set LaunchError "The media backend is unavailable in this build."; return 0 }
	if {![string is double -strict $startMs] || $startMs < 0} { set startMs 0 }
	if {[catch { ::mpv::open $wid $path [expr {$startMs / 1000.0}] } ok]} {
		set LaunchError $ok
		return 0
	}
	return $ok
}

proc ::media::mpv::_get {property} {
	variable LaunchError
	if {$property eq "error-text" && $LaunchError ne ""} { return $LaunchError }
	if {[catch { ::mpv::get $property } v]} { return {} }
	return $v
}

# seconds (double) or {}
proc ::media::mpv::time {} {
	set t [_get time-pos]
	if {[string is double -strict $t]} { return $t }
	return {}
}

proc ::media::mpv::duration {} {
	set d [_get duration]
	if {[string is double -strict $d]} { return $d }
	return {}
}

# Display aspect (sample aspect ratio included), available after metadata loads.
proc ::media::mpv::aspect {} {
	set a [_get video-params/aspect]
	if {[string is double -strict $a] && $a > 0} { return $a }
	set w [_get dwidth]
	set h [_get dheight]
	if {[string is double -strict $w] && [string is double -strict $h] && $w > 0 && $h > 0} {
		return [expr {double($w)/$h}]
	}
	return {}
}

# Chapter start boundaries in milliseconds for the currently loaded ITEM.
# Read scalar properties so both libmpv and optional native backends can
# report absence without a JSON parser or dependence on the game's gallery.
proc ::media::mpv::chapters {} {
	set count [_get chapters]
	if {![string is integer -strict $count] || $count < 1} { return {} }
	set starts {}
	for {set i 0} {$i < $count} {incr i} {
		set t [_get chapter-list/$i/time]
		if {![string is double -strict $t] || $t < 0} { return {} }
		lappend starts [expr {$t*1000.0}]
	}
	return $starts
}

proc ::media::mpv::state {} {
	set paused [_get pause]
	# No player handle: never started, or ::mpv::close after Stop. That is the
	# stopped state, not a failure; genuine open/decode failures keep the
	# player alive and report load-error yes (checked below).
	if {$paused eq ""} { return idle }
	if {[_get load-error] eq "yes"} { return error }	;# the file would not open or decode
	if {$paused eq "yes"} { return paused }
	if {[_get eof-reached] eq "yes"} { return ended }
	if {[_get core-idle] eq "no"} { return playing }
	return idle	;# opening, buffering or seeking
}

proc ::media::mpv::play {}  { ::mpv::set pause no }
proc ::media::mpv::pause {} { ::mpv::set pause yes }

# seek to milliseconds
proc ::media::mpv::seek {ms} {
	::mpv::set time-pos [expr {$ms / 1000.0}]
}

# 0..100 or {}
proc ::media::mpv::volume {} {
	set v [_get volume]
	if {[string is double -strict $v]} { return [expr {int(round($v))}] }
	return {}
}

proc ::media::mpv::setVolume {v} {
	::mpv::set volume $v
}

proc ::media::mpv::stop {} {
	catch { ::mpv::close }
}

# vi:set ts=3 sw=3:
