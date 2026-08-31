# ======================================================================
# mpv transport for the media panel — Tier-2b backend
# ======================================================================
# Implements the same delegate contract as tkvlc but uses libmpv
# (JSON-IPC via Unix socket) for command/control.
#
# Advantages over tkvlc:
#   * WMV/VC-1 decoding without host codec installation
#   * frame-accurate seeking + property-push events
#   * OSD/render-script layer for future annotation overlays
#
# Requires: mpv >= 0.30 (the binary in $PATH) and Tcl 8.6 (TCP sockets).
# The transport engine is selected by ::media::sync::configure — the
# state machine delegates are the same regardless of engine.
#
# The media file is unmodified: the decoder reads the stream in-process.
# ======================================================================


namespace eval ::application::media::mpv {
	variable Seq    0
	variable Chan   {}
	variable Pid    0
	variable Time   0.0
	variable Duration  0.0
	variable SockFile  /tmp/scidb_mpv.ipc
	variable PollAfter {}
}

# Launch mpv with the media file embedded in the Tk canvas
proc ::application::media::mpv::launch {wmvPath wid {startMs 0}} {
	variable Chan
	variable SockFile
	variable Pid

	file delete $SockFile
	set cmdline [list mpv \
		--wid=$wid \
		--input-ipc-server=$SockFile \
		--keep-open=yes \
		--audio-device=auto \
		--vo=libmpv,gl, \
		--hwdec=auto \
		--volume=50 \
		--script-opt=--osc=no \
		--load-scripts=no \
		[file normalize $wmvPath] \
	]
	log "mpv::launch: [file tail $wmvPath] wid=$wid"
	set pid [exec -- {*}$cmdline &]
	set Pid $pid

	# wait for the IPC socket
	for {set i 0} {$i < 30} {incr i} {
		if {[file exists $SockFile]} break
		after 100
	}
	if {![file exists $SockFile]} {
		log "IPC socket not created"
		return 0
	}

	# connect the IPC socket
	set Chan [open $SockFile r+]
	fconfigure $Chan -translation binary -buffering none -blocking 0
	log "IPC connected"
	return 1
}

# close the mpv process and IPC connection
proc ::application::media::mpv::close {} {
	variable Chan
	variable Pid
	if {$Chan ne ""} {
		command quit
		catch { close $Chan }
	}
	if {$Pid > 0} {
		catch { exec kill $Pid }
	}
	set Chan {}
	set Pid 0
}

# ---------------------------------------------------------------------
# IPC: send a JSON command
# ---------------------------------------------------------------------

proc ::application::media::mpv::command {args} {
	variable Chan
	if {$Chan eq ""} return
	# build the JSON command array
	set parts {}
	foreach v $args {
		if {[string is double -strict $v]} { lappend parts $v }
		else {
			set esc [string map {\\ \\\\ \" \\" \n \\n / \\/} $v]
			lappend parts "\"$esc\""
		}
	}
	set msg "\[\{\"command\": \[[join $parts {,}]\]\}\]\n"
	catch { puts $Chan $msg } err
}


proc ::application::media::mpv::play {} {
	command set_property pause false
}

proc ::application::media::mpv::pause {} {
	command set_property pause true
}

proc ::application::media::mpv::seek {ms} {
	command seek $ms absolute
}

proc ::application::media::mpv::getPlaybackTime {} {
	command get_property playback-time
}

proc ::application::media::mpv::getDuration {} {
	command get_property duration
}

proc ::application::media::mpv::stop {} {
	command quit
}
