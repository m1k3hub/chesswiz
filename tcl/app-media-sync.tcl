# ======================================================================
# Media ⇄ Board playback synchronization (state machine)
# ======================================================================
# Couples the media panel's transport (audio/video via tkvlc) with the
# chess-board replay:
#
#   * transport sync — when the board autoplays a game the media plays
#     along; stopping/pausing the autoplay pauses the media; manual
#     navigation pauses the media (it no longer matches the position).
#
#   * follow mode — the board follows the media: while the video plays,
#     the main board advances through the game. With a per-move timeline
#     loaded (load-timeline) the mapping follows the ChessBase script
#     stream's own replay order (real per-move timecodes recovered from
#     the media's script stream, see media-console/wmv2timeline.py);
#     without one, the mapping is linear over the video duration.
#
#   * annotation layer — with board events loaded (load-events), the
#     state machine fires arrow/mark/comment/symbol/reset callbacks as
#     the media time passes each event's timestamp.
#
# The state machine is UI-free: the media panel wires it to tkvlc handles
# and the scidb board commands (see application::media::SyncTransport,
# application::media::SyncBoard*), while tests inject stubs. Board code
# reports playback events through ::media::sync::autoplay / ::step.
# ======================================================================

::util::source media-sync

# UI-facing state (checkbutton variables + accessor used by the media
# panel; see tcl/app-media.tcl).
namespace eval ::mediasync {
	variable opts
	array set opts {
		transport 1
		follow    1
	}
}

proc ::mediasync::config {} {
	variable opts
	return [list $opts(transport) $opts(follow)]
}

proc ::mediasync::set-config {transport follow} {
	variable opts
	set opts(transport) [expr {$transport ? 1 : 0}]
	set opts(follow) [expr {$follow ? 1 : 0}]
}

namespace eval ::media::sync {
	variable State
	array set State {
		transport 1
		follow    1
		autoplay  0
		playing   0
		driving   0
		lastgoal  -1
		timeline  {}
		tlidx     0
		events    {}
		evidx     0
	}

	variable Delegates
	array set Delegates {
		transport     {}
		boardforward  {}
		boardstart    {}
		boardlength   {}
		boardply      {}
		annotate      {}
		clearann      {}
	}

	namespace export configure set-config autoplay step drive driving? \
		onPlaybackStarted onPlaybackStopped load-timeline load-events
}

proc ::media::sync::configure {args} {
	variable Delegates
	foreach {key value} $args {
		switch -- $key {
			transport-cmd     { set Delegates(transport) $value }
			boardforward-cmd  { set Delegates(boardforward) $value }
			boardstart-cmd    { set Delegates(boardstart) $value }
			boardlength-cmd   { set Delegates(boardlength) $value }
			boardply-cmd      { set Delegates(boardply) $value }
			annotate-cmd      { set Delegates(annotate) $value }
			clearann-cmd      { set Delegates(clearann) $value }
			default {
				return -code error "media::sync::configure: unknown option $key"
			}
		}
	}
}


proc ::media::sync::set-config {transport follow} {
	variable State
	set State(transport) [expr {$transport ? 1 : 0}]
	set State(follow) [expr {$follow ? 1 : 0}]
	set State(lastgoal) -1
}


proc ::media::sync::config {} {
	variable State
	return [list $State(transport) $State(follow)]
}


# Called by board code when game-board autoplay starts (state 1) or
# stops (state 0).
proc ::media::sync::autoplay {state} {
	variable State
	set State(autoplay) [expr {$state ? 1 : 0}]

	if {!$State(transport) || !$State(playing)} { return }
	if {$State(autoplay)} {
		Transport play
	} else {
		Transport pause
	}
}


# Called by board code after the board navigated one step (any direction,
# any distance). During autoplay the media keeps playing; manual
# navigation pauses the media (with transport sync on).
proc ::media::sync::step {} {
	variable State

	if {!$State(transport) || !$State(playing)} { return }
	if {$State(autoplay)} { return }
	Transport pause
}


# The media player started/stopped playing (any file).
proc ::media::sync::onPlaybackStarted {} {
	variable State
	set State(playing) 1
	set State(lastgoal) -1
	set State(tlidx) 0
	set State(evidx) 0
}


proc ::media::sync::onPlaybackStopped {} {
	variable State
	set State(playing) 0
	set State(autoplay) 0
	set State(lastgoal) -1
	set State(tlidx) 0
	set State(evidx) 0
}


# Load/replace the optional per-move timeline: media→board timecodes
# recovered from a ChessBase script stream (media-console/wmv2timeline.py
# writes them one per line). One entry = the media ms at which the board
# advances one navigation step, in replay order. An empty list falls back
# to the linear ply mapping.
proc ::media::sync::load-timeline {msList} {
	variable State
	set State(timeline) [list]
	foreach ms $msList {
		if {[string is integer -strict $ms]} {
			lappend State(timeline) $ms
		}
	}
	set State(tlidx) 0
	set State(lastgoal) -1
}


# Load/replace the board annotation events: a Tcl list of triples
# {ms kind payload} — kind = arrow|mark|comment|symbol|reset, payload
# is kind-specific.  An empty list clears them.
proc ::media::sync::load-events {eventList} {
	variable State
	set State(events) [list]
	foreach ev $eventList {
		if {[llength $ev] >= 3 && [string is integer -strict [lindex $ev 0]]} {
			lappend State(events) [list [lindex $ev 0] [lindex $ev 1] [lrange $ev 2 end]]
		}
	}
	set State(evidx) 0
}


# True while drive() is advancing the board as a consequence of media time.
proc ::media::sync::driving? {} {
	variable State
	return $State(driving)
}


# One "board follows video" tick. Fires annotation events that fall in
# the [prev_ms, timeMs] window, then advances the board via the timeline
# or the linear mapping.
proc ::media::sync::drive {timeMs durationMs} {
	variable State

	if {!$State(follow) || !$State(playing)} { return }

	# fire board annotation events in this time window
	if {[llength $State(events)]} {
		::media::sync::_fire_events $timeMs
	}

	set len [BoardLength]
	if {$len <= 1} { return }

	if {[llength $State(timeline)]} {
		set goal 0
		foreach mark $State(timeline) {
			if {$mark <= $timeMs} { incr goal } else { break }
		}
		set goal [expr {min($goal, $len - 1)}]
		if {$goal < $State(lastgoal)} {
			set State(tlidx) $goal
			set State(evidx) 0
			BoardStart
			BoardClearAnnotations
		}
		# drive the board forward, at most 4 plies per tick
		set guard 0
		set State(driving) 1
		while {[BoardPly] < $goal && $guard < 4} {
			BoardForward
			incr guard
		}
		set State(driving) 0
		set State(lastgoal) $goal
		return
	}

	set dur [expr {double($durationMs)}]
	if {$dur < 500.0} { return }
	set frac [expr {double($timeMs)/$dur}]
	if {$frac < 0.0} { set frac 0.0 }
	if {$frac > 1.0} { set frac 1.0 }
	set goal [expr {min(int($frac*$len), $len - 1)}]
	if {$goal < $State(lastgoal)} {
		BoardStart
		BoardClearAnnotations
	}
	set guard 0
	set State(driving) 1
	while {[BoardPly] < $goal && $guard < 4} {
		BoardForward
		incr guard
	}
	set State(driving) 0
	set State(lastgoal) $goal
}


# Fire board annotation events whose media-ms has elapsed.
proc ::media::sync::_fire_events {timeMs} {
	variable State
	set n [llength $State(events)]
	while {$State(evidx) < $n} {
		lassign [lindex $State(events) $State(evidx)] ms kind data
		if {$ms > $timeMs} { break }
		if {$kind eq "reset"} {
			BoardClearAnnotations
		} else {
			BoardAnnotate $kind $data
		}
		incr State(evidx)
	}
}


# --- internal helpers ---------------------------------------------------

proc ::media::sync::Transport {what} {
	variable Delegates
	if {[llength $Delegates(transport)]} {
		catch { uplevel #0 $Delegates(transport) [list $what] }
	}
}


proc ::media::sync::BoardForward {} {
	variable Delegates
	if {[llength $Delegates(boardforward)]} {
		catch { uplevel #0 $Delegates(boardforward) }
	}
}


proc ::media::sync::BoardStart {} {
	variable Delegates
	if {[llength $Delegates(boardstart)]} {
		catch { uplevel #0 $Delegates(boardstart) }
	}
}


proc ::media::sync::BoardAnnotate {kind data} {
	variable Delegates
	if {[llength $Delegates(annotate)]} {
		catch { uplevel #0 $Delegates(annotate) [list $kind $data] }
	}
}


proc ::media::sync::BoardClearAnnotations {} {
	variable Delegates
	if {[llength $Delegates(clearann)]} {
		catch { uplevel #0 $Delegates(clearann) }
	}
}


proc ::media::sync::BoardPly {} {
	variable Delegates
	if {[llength $Delegates(boardply)]} {
		if {[catch { uplevel #0 $Delegates(boardply) } ply]} { return 0 }
		if {[string is integer -strict $ply]} { return $ply }
		return 0
	}
	return 0
}


proc ::media::sync::BoardLength {} {
	variable Delegates
	if {[llength $Delegates(boardlength)]} {
		if {[catch { uplevel #0 $Delegates(boardlength) } len]} { return 0 }
		if {[string is integer -strict $len]} { return $len }
		return 0
	}
	return 0
}

# vi:set ts=3 sw=3:
