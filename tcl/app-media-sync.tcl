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
#     the main board advances through the game, mapped linearly over the
#     video duration (no per-move timecodes exist in the ChessBase media
#     refs, so the mapping is linear by construction).
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
		follow    0
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
	# Config: transport sync on by default; follow (board driven by the
	# media timeline) is opt-in.
	variable State
	array set State {
		transport 1
		follow    0
		autoplay  0
		playing   0
		lastgoal  -1
	}

	# Delegate procs, set via ::media::sync::configure. Each is optional;
	# missing delegates degrade to no-ops.
	variable Delegates
	array set Delegates {
		transport     {}
		boardforward  {}
		boardstart    {}
		boardlength   {}
		boardply      {}
	}

	namespace export configure set-config autoplay step drive \
		onPlaybackStarted onPlaybackStopped
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
}


proc ::media::sync::onPlaybackStopped {} {
	variable State
	set State(playing) 0
	set State(autoplay) 0
	set State(lastgoal) -1
}


# One "board follows video" tick: <timeMs>/<durationMs> maps linearly
# onto the game's ply range; step the board forward when the mapped
# target has advanced past the board's position. Handles at most 4
# plies per tick. A mapped rewind (media seeked backwards) restarts
# the game from the beginning to stay consistent.
proc ::media::sync::drive {timeMs durationMs} {
	variable State

	if {!$State(follow) || !$State(playing)} { return }

	set len [BoardLength]
	if {$len <= 1} { return }

	set dur [expr {double($durationMs)}]
	if {$dur < 500.0} { return }
	set frac [expr {double($timeMs)/$dur}]
	if {$frac < 0.0} { set frac 0.0 }
	if {$frac > 1.0} { set frac 1.0 }

	set goal [expr {min(int($frac*$len), $len - 1)}]

	if {$goal < $State(lastgoal)} {
		# media jumped backwards: replay the game from the start
		BoardStart
	}

	# drive the board forward, at most 4 plies per tick
	set guard 0
	while {[BoardPly] < $goal && $guard < 4} {
		BoardForward
		incr guard
	}
	set State(lastgoal) $goal
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
