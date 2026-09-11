# ======================================================================
# ::media::mpv — mpv JSON-IPC transport (Tier-2b backend)
# ======================================================================
# mpv is the preferred embedded playback backend (MEDIA_PANEL_DESIGN.md
# §4): precise seek, sub-100ms time queries, reliable state reporting,
# and solid WMV demuxing.  The player is spawned with --wid (X11
# embedding into the media pane's canvas) and driven over the
# --input-ipc-server unix socket with one connection per command;
# responses are matched by request_id (mpv events on the same
# connection are skipped).
#
# Vocabulary used by the panel wrappers (SyncTransport/FollowTick):
#   state  -> playing | paused | ended | idle | error
#   time   -> seconds (double), duration -> seconds (double)
#
# NOTE ON TCL QUOTING: response parsing deliberately avoids brace-
# quoted regular expressions - a brace-quoted pattern containing a
# literal close brace corrupts the Tcl grouping.  All matchingrse.
# All matching is done with string-first operations instead.
# ======================================================================

::util::source media-mpv

namespace eval ::media::mpv {
	variable Priv
	array set Priv {
		handle		{}
		pid			{}
		bridgepid	{}
		port		{}
		sockpath	{}
		seq			0
		bridgelog	/tmp/scidb-mpv-bridge.log
	}
	# capture at load time: info script is dynamic and would resolve to
	# the caller's script inside launch()
	set Priv(bridge) [file join [file dirname [info script]] mpv_ipc_bridge.py]

	namespace export launch stop time duration state play pause seek available?
}

# mpv binary present?
proc ::media::mpv::available? {} {
	return [expr {[auto_execok mpv] ne ""}]
}

# Launch mpv embedded into window wid playing path from startMs.
# Returns 1 on success (ipc socket answering, time-pos queryable).
proc ::media::mpv::launch {path wid {startMs 0}} {
	variable Priv

	stop	;# release any previous instance

	set sockpath /tmp/scidb-mpv-[pid]-[incr Priv(seq)].sock
	set Priv(sockpath) $sockpath
	set startSec [expr {$startMs > 0 ? $startMs / 1000.0 : 0}]

	# mpv parses --wid as a DECIMAL window id; winfo id returns hex
	# (0x00200006) - an unparsable wid silently falls back to mpv's own
	# toplevel window instead of embedding
	if {[scan $wid "0x%x" widDec] != 1} {
		if {$wid eq "0"} {
			set widDec 0
		} else {
			set widDec [string trimleft $wid "0"]
			if {![string is integer -strict $widDec]} { return 0 }
		}
	}
	set wid $widDec

	set cmd [list mpv \
		--no-terminal \
		--no-config \
		--input-ipc-server=$sockpath \
		--wid=$wid \
		--vo=x11 \
		--keep-open=always \
		--osd-level=0 \
		--pause=no \
		--start=$startSec \
		-- \
		$path]

	# clear leaked instances from crashed prior sessions (both mpv,
	# --input-ipc-server=/tmp/scidb-mpv-*.sock, and our bridges carry
	# the scidb-mpv- tag in their command lines)
	catch { exec pkill -f scidb-mpv- }
	after 200

	set Priv(mpvid) [incr Priv(seq)]
	set Priv(pid) [exec {*}$cmd > /tmp/scidb-mpv-stderr-$Priv(mpvid).log 2>&1 &]

	# Tcl core has no unix sockets: the bridge (python3) listens on a
	# loopback TCP port and forwards to mpv's --input-ipc-server unix
	# socket; it reports the port in <sockpath>.port
	set bridge $Priv(bridge)
	set Priv(bridgepid) [exec python3 $bridge $sockpath 2>> $Priv(bridgelog) &]

	# the bridge writes its port to <sockpath>.port once listening
	set portfile $sockpath.port
	set port {}
	for {set i 0} {$i < 30} {incr i} {
		after 100
		if {[file exists $portfile]} {
			set pf [open $portfile r]
			set line [gets $pf]
			close $pf
			if {[string match "ready*" $line]} { set port [lindex $line 1]; break }
		}
	}
	if {![string is integer -strict $port]} {
		catch { ::application::media::MediaDebug "mpv bridge portfile never appeared" }
		stop
		return 0
	}
	set Priv(port) $port
	# a launch is only good if properties are queryable
	for {set i 0} {$i < 30} {incr i} {
		after 100
		set d [::media::mpv::_get duration]
			if {[string length $d]} {
			set Priv(handle) $path
			return 1
		}
		# mpv died (bad file)?
		if {[catch { exec kill -0 $Priv(pid) }]} {
					break
		}
	}
	stop
	return 0
}

# a free loopback port for the bridge (best effort: bind, note, close)
proc ::media::mpv::_freePort {} {
	set s [socket -server {} 0]
	set port [lindex [fconfigure $s -sockname] 2]
	close $s
	return $port
}

# One IPC command; returns the raw response line or {}.
proc ::media::mpv::_cmd {args} {
	variable Priv
	if {![string length $Priv(sockpath)]} { return {} }

	set id [incr Priv(seq)]
	# build the JSON by hand - flat commands with string/number args only
	set jargs {}
	foreach a $args {
		if {[string is integer -strict $a] || [string is double -strict $a]
			|| $a eq "true" || $a eq "false"} {
			# numbers and JSON booleans go unquoted (flag properties
			# reject string values: "unsupported format")
			lappend jargs $a
		} else {
			set a [string map [list \\ \\\\ \" \\\" ] $a]
			lappend jargs "\"$a\""
		}
	}
	set json "{\"command\": \[[join $jargs ,]\], \"request_id\": $id}\n"

	set response {}
	if {[catch {
		set s [socket 127.0.0.1 $Priv(port)]
		fconfigure $s -blocking 0 -buffering line
		puts -nonewline $s $json
		flush $s
		set deadline [expr {[clock milliseconds] + 1000}]
		while {[clock milliseconds] < $deadline} {
			set got [gets $s line]
			if {$got >= 0} {
				# match our request_id; skip mpv events
				if {[string first "\"request_id\": $id" $line] >= 0
					|| [string first "\"request_id\":$id" $line] >= 0} {
					set response $line
					break
				}
			} else {
				after 10
			}
			if {[eof $s]} { break }
		}
		close $s
	} emsg]} {
		catch { ::application::media::MediaDebug "mpv _cmd error: $emsg" }
	}
	return $response
}

# Extract the value of "data": <value> from a response line.
proc ::media::mpv::_extractData {line} {
	set idx [string first "\"data\"" $line]
	if {$idx < 0} { return {} }
	set rest [string range $line [expr {$idx + 6}] end]
	set rest [string trimleft $rest " :\t"]
	# value ends at the first comma or close brace - whichever comes first
	set c1 [string first , $rest]
	set c2 [string first "\}" $rest]
	if {$c1 < 0 || ($c2 >= 0 && $c2 < $c1)} { set c1 $c2 }
	if {$c1 < 0} { return {} }
	set v [string trim [string range $rest 0 [expr {$c1 - 1}]] "\" "]
	return [string map [list \\\" \" \\\\ \\ ] $v]
}

proc ::media::mpv::_get {property} {
	return [_extractData [_cmd get_property $property]]
}

proc ::media::mpv::_set {property value} {
	set r [_cmd set_property $property $value]
	# set_property responses carry error:"success" (no success flag)
	if {[string first "\"error\": \"success\"" $r] >= 0
		|| [string first "\"error\":\"success\"" $r] >= 0} { return 1 }
	return 0
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

proc ::media::mpv::state {} {
	set paused [_get pause]
	if {$paused eq "true"} { return paused }
	set idle [_get core-idle]
	if {$idle eq "false"} { return playing }
	set eof [_get eof-reached]
	if {$eof eq "true"} { return ended }
	if {$idle eq "true"} { return idle }
	return error
}

proc ::media::mpv::play {}  { _set pause false }
proc ::media::mpv::pause {} { _set pause true }

# seek to milliseconds
proc ::media::mpv::seek {ms} {
	_set time-pos [expr {$ms / 1000.0}]
}

proc ::media::mpv::stop {} {
	variable Priv
	if {[string length $Priv(sockpath)]} {
		catch { _cmd quit }
	}
	if {[string length $Priv(pid)]} {
		catch { exec kill $Priv(pid) }
	}
	if {[info exists Priv(bridgepipe)] && [string length $Priv(bridgepipe)]} {
		catch { close $Priv(bridgepipe) }
	}
	if {[string length $Priv(bridgepid)]} {
		catch { exec kill $Priv(bridgepid) }
	}
	set Priv(handle) {}
	set Priv(pid) {}
	set Priv(bridgepid) {}
	set Priv(port) {}
	set Priv(sockpath) {}
}

# vi:set ts=3 sw=3:
