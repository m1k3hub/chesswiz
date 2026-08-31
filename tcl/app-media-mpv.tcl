# ======================================================================
# mpv transport for the media panel — Tier-2b backend
# ======================================================================
# Implements the same delegate contract as tkvlc but uses the mpv
# player (JSON-IPC via Unix socket) for command/control.
#
# Advantages over tkvlc:
#   * WMV/VC-1 decoding without host codec installation
#   * frame-accurate seeking + property-push events
#   * OSD/render-script layer for future annotation overlays
#
# Requires: mpv >= 0.30 (the binary in $PATH) and Tcl 8.6 (Unix sockets).
# The transport engine is selected by the media panel; the state
# machine delegates are the same regardless of engine.
#
# The media file is unmodified: the player reads the stream.
#
# NOTE: this module lives in ::media::mpv (the engine family, next to
# ::media::sync and ::media::cm).  All procs are defined INSIDE
# "namespace eval ::media::mpv" so their bodies execute in this
# namespace.  A proc defined with a qualified name at global scope
# (e.g. "proc ::media::mpv::foo ...") runs its body in "::" and
# cannot resolve its siblings — the previous version of this file
# failed exactly like that ("invalid command name MediaDebug").
# ======================================================================

namespace eval ::media::mpv {

variable Seq       0
variable Chan      {}
variable Pid       0
variable Time     0.0  ;# playback position (ms, cached from property events)
variable Duration 0.0  ;# file duration (ms, cached from property events)
variable SockFile /tmp/scidb_mpv.ipc
variable PollAfter {}

# MediaDebug lives in the GUI layer (::application::media).  Route all
# diagnostics through this wrapper so the fully-qualified call is spelled
# out exactly once.
proc debug {msg} {
	catch { ::application::media::MediaDebug $msg }
}

# Launch mpv with the media file embedded in the given window.
#   wmvPath  media file
#   wid      Tk widget path OR raw X window id
#   startMs  initial position (ms); 0 = start from the beginning
# Returns 1 on success, 0 if mpv could not be started or attached.
proc launch {wmvPath wid {startMs 0}} {
	variable Chan
	variable SockFile
	variable Pid
	variable Time
	variable Duration

	# Release any previous transport first.
	if {$Chan ne "" || $Pid > 0} { stop }

	# Accept either a Tk widget path or a raw X window id.
	if {![string is integer -strict $wid]} {
		if {[catch { winfo id $wid } id]} {
			debug "mpv::launch: cannot get window id of $wid: $id"
			return 0
		}
		set wid $id
	}

	# normalize hex XIDs (Tk's winfo id returns 0x...) to decimal for mpv
	if {[catch { set wid [expr {wide($wid)}] } err]} {
		debug "mpv::launch: bad window id: $err"
		return 0
	}

	file delete $SockFile
	set cmdline [list mpv \
		--no-terminal \
		--wid=$wid \
		--input-ipc-server=$SockFile \
		--keep-open=yes \
		--volume=50 \
	]
	if {[string is double -strict $startMs] && $startMs > 0} {
		lappend cmdline [format --start=%.3f [expr {$startMs/1000.0}]]
	}
	lappend cmdline [file normalize $wmvPath]

	# --wid embedding is X11-only.  When running inside a Wayland session
	# mpv would attach to the Wayland compositor and reject --wid, so strip
	# the Wayland display from the child environment and let it attach
	# through XWayland instead.
	set envcmd {}
	if {[info exists ::env(WAYLAND_DISPLAY)]} {
		set envcmd [list env -u WAYLAND_DISPLAY]
	}

	debug "mpv::launch: [file tail $wmvPath] wid=$wid startMs=$startMs"
	if {[catch { exec -- {*}$envcmd {*}$cmdline & } pid]} {
		debug "mpv::launch: exec failed: $pid"
		return 0
	}
	set Pid $pid
	set Time 0.0
	set Duration 0.0

	# Wait for the IPC socket (and stop early if mpv exits).
	for {set i 0} {$i < 30} {incr i} {
		if {[file exists $SockFile]} break
		if {[catch { exec kill -0 $Pid }]} { break }
		after 100
	}
	if {![file exists $SockFile]} {
		debug "mpv::launch: IPC socket $SockFile not created"
		stop
		return 0
	}

	# Tcl core cannot connect to Unix domain sockets (open(2) gives ENXIO);
	# bridge through nc (netcat-openbsd supports -U).  Without nc the mpv
	# tier cannot do IPC at all.
	if {![llength [auto_execok nc]]} {
		debug "mpv::launch: nc missing - Unix-socket bridge unavailable"
		stop
		return 0
	}
	if {[catch { open [concat "|" nc -U $SockFile] r+ } chan]} {
		debug "mpv::launch: cannot open IPC bridge: $chan"
		stop
		return 0
	}
	set Chan $chan
	fconfigure $Chan -translation binary -buffering none -blocking 0
	fileevent $Chan readable [namespace code OnReadable]

	# Subscribe to property changes so the position/duration cache used
	# by the follow-sync stays fresh without blocking IPC round-trips.
	command observe_property 1 time-pos
	command observe_property 2 duration

	debug "mpv::launch: IPC connected (pid=$Pid)"
	return 1
}

# Drain asynchronous IPC input: refresh the position/duration cache
# from property-change events and discard command replies.
proc OnReadable {} {
	variable Chan
	variable Time
	variable Duration

	if {$Chan eq ""} { return }
	set data {}
	while {![catch { gets $Chan line } n] && $n >= 0} {
		if {![string match {*"event":"property-change"*} $line]} { continue }
		if {![regexp {"data":(-?[0-9]+\.?[0-9]*)} $line -> data]} { continue }
		if {[regexp {"name":"time-pos"} $line]} {
			set Time [expr {$data*1000.0}]
		} elseif {[regexp {"name":"duration"} $line]} {
			set Duration [expr {$data*1000.0}]
		}
	}
	if {$Chan ne "" && [eof $Chan]} {
		# mpv exited and the nc bridge closed the pipe
		catch { ::close $Chan }
		set Chan {}
		debug "mpv::OnReadable: IPC closed (mpv exited)"
	}
}

# ---------------------------------------------------------------------
# IPC: send a JSON command
# ---------------------------------------------------------------------

proc command {args} {
	variable Chan
	if {$Chan eq ""} { return }
	set parts {}
	foreach v $args {
		# numbers and JSON literals are emitted unquoted, strings quoted
		if {[string is double -strict $v] || $v eq "true" || $v eq "false" || $v eq "null"} {
			lappend parts $v
		} else {
			set esc [string map {\\ \\\\ \" \\" \n \\n \t \\t \r \\r} $v]
			lappend parts "\"$esc\""
		}
	}
	set msg "\{\"command\": \[[join $parts {,}]\]\}\n"
	if {[catch { puts $Chan $msg } err]} {
		debug "mpv::command: write failed: $err"
	}
}

# Query a numeric property via the JSON-IPC channel.  Short bounded
# wait; returns 0.0 when the channel is gone or the property is unknown.
# (Position and duration normally come from the property-push events
# handled by OnReadable; this is for ad-hoc queries.)
proc query_property {prop} {
	variable Chan
	variable Seq

	if {$Chan eq ""} { return 0.0 }
	incr Seq
	set msg [format {{"command": ["get_property", "%s"], "request_id": %d}} $prop $Seq]\n
	if {[catch { puts $Chan $msg }]} { return 0.0 }
	set deadline [expr {[clock milliseconds] + 150}]
	while {[clock milliseconds] < $deadline} {
		if {[catch { gets $Chan line } n] || $n < 0} {
			after 5
			continue
		}
		if {	[regexp {"request_id":\s*$Seq} $line]
				&& [regexp {"data":\s*(-?[0-9]+\.?[0-9]*)} $line -> val]} {
			return $val
		}
	}
	return 0.0
}

# ---------------------------------------------------------------------
# Delegate contract (same shape as the tkvlc handle)
#   getPlaybackTime / getDuration return MILLISECONDS
# ---------------------------------------------------------------------

proc getPlaybackTime {} {
	variable Time
	return $Time
}

proc getDuration {} {
	variable Duration
	return $Duration
}

proc play {} {
	command set_property pause false
}

proc pause {} {
	command set_property pause true
}

# Seek to an absolute position given in MILLISECONDS.
proc seek {ms} {
	command seek [expr {$ms/1000.0}] absolute
}

# Stop the mpv process and release the IPC connection.
proc stop {} {
	variable Chan
	variable Pid
	variable Time
	variable Duration

	if {$Chan ne ""} {
		catch { command quit }
		catch { fileevent $Chan readable {} }
		catch { ::close $Chan }   ;# ::close — don't rely on builtin resolution inside this namespace
		set Chan {}
	}
	if {$Pid > 0} {
		set pid $Pid
		after 500 [list ::media::mpv::kill $pid]
	}
	set Pid 0
	set Time 0.0
	set Duration 0.0
}

proc kill {pid} {
	catch { exec kill $pid }
}

# True while the mpv process exists (transport health check).
proc alive? {} {
	variable Pid
	if {$Pid <= 0} { return 0 }
	return [expr {![catch { exec kill -0 $Pid }]}]
}

} ;# namespace eval ::media::mpv

# vi:set ts=3 sw=3:
