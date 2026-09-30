# ======================================================================
# ::application::diagnose -- look inside the running program.
#
# Introspection for the assistant's debug mode (app-assistant.tcl) and for
# anyone who sends the process a signal:
#
#   kill -USR1 PID   write the Tcl stack of the interpreter to
#                    <user>/log/hang-<time>.txt (works for any Tcl-level
#                    stall: a busy-wait loop, a long proc, a blocking exec)
#   kill -USR2 PID   write a native backtrace of the main thread to
#                    <user>/log/hang-native.txt (works even when the thread
#                    never returns to the interpreter)
#
# The event loop gets a heartbeat and a watchdog (src/tcl/tcl_diag.cpp) in
# debug mode or with SCIDB_HANG_WATCHDOG=<seconds>: when the loop stops
# ticking for that long, both dumps are written on their own.
#
# Every function returns text. Nothing here changes the program except
# releaseGrab and cancelTimer, which the assistant only runs after the user
# has confirmed them.
# ======================================================================

if {[llength [info commands ::util::source]]} {
	::util::source app-diagnose
}

package require Tcl 8.5
package require Tk 8.5

namespace eval application {
namespace eval diagnose {

variable Beat 100			;# heartbeat period, ms
variable Slow 300			;# a gap this long between beats is recorded, ms
variable MaxGaps 20
variable MaxDumps 20		;# hang files kept
variable Priv
array set Priv {
	started		0
	after			{}
	last			0
	gaps			{}
	worst			0
	beats			0
	watchdog		0
}


# ----------------------------------------------------------------------
# start-up
# ----------------------------------------------------------------------

proc logDir {} {
	if {[info exists ::scidb::dir::user]} {
		set dir [file join $::scidb::dir::user log]
	} else {
		set dir [file join [pwd] log]
	}
	catch { file mkdir $dir }
	return $dir
}


# The signal handlers cost nothing until a signal arrives, so they are
# always installed. The heartbeat and the watchdog run only in debug mode
# or when SCIDB_HANG_WATCHDOG asks for them.
proc autostart {} {
	variable Priv

	if {$Priv(started)} { return }
	set Priv(started) 1

	if {[llength [info commands ::diag::install]]} {
		catch { ::diag::install [file join [logDir] hang-native.txt] }
	}

	set seconds 0
	if {[info exists ::env(SCIDB_HANG_WATCHDOG)]
	 && [string is integer -strict $::env(SCIDB_HANG_WATCHDOG)]} {
		set seconds $::env(SCIDB_HANG_WATCHDOG)
	} elseif {[info exists ::application::assistant::Priv(debug)] && $::application::assistant::Priv(debug)} {
		set seconds 8
	}
	if {$seconds > 0} { watch $seconds }
}


proc watch {seconds} {
	variable Priv

	startHeartbeat
	if {[llength [info commands ::diag::watchdog]]} {
		if {![catch { ::diag::watchdog $seconds }]} { set Priv(watchdog) $seconds }
	}
}


proc startHeartbeat {} {
	variable Priv
	variable Beat

	if {$Priv(after) ne ""} { return }
	set Priv(last) [clock milliseconds]
	set Priv(after) [after $Beat [namespace code Heartbeat]]
}


proc Heartbeat {} {
	variable Priv
	variable Beat
	variable Slow
	variable MaxGaps

	set now [clock milliseconds]
	set gap [expr {$now - $Priv(last) - $Beat}]
	set Priv(last) $now
	incr Priv(beats)
	if {[llength [info commands ::diag::tick]]} { ::diag::tick }
	if {$gap >= $Slow} {
		lappend Priv(gaps) [list $now $gap]
		if {[llength $Priv(gaps)] > $MaxGaps} {
			set Priv(gaps) [lrange $Priv(gaps) end-[expr {$MaxGaps - 1}] end]
		}
		if {$gap > $Priv(worst)} { set Priv(worst) $gap }
	}
	set Priv(after) [after $Beat [namespace code Heartbeat]]
}


# ----------------------------------------------------------------------
# hang dump (signal handler target)
# ----------------------------------------------------------------------

# The Tcl stack of the interpreter as it is right now. Called from the
# async handler of tcl_diag.cpp, i.e. in the middle of whatever was running:
# the frames below this one are the stalled code.
proc dumpStack {{reason manual}} {
	variable Priv
	variable MaxDumps

	set file [file join [logDir] hang-[clock format [clock seconds] -format %Y%m%d-%H%M%S].txt]
	set out [list "hang dump ($reason) at [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}], pid [pid]"]
	if {$Priv(after) ne ""} {
		lappend out "event loop: last heartbeat [expr {[clock milliseconds] - $Priv(last)}] ms ago"
	}
	lappend out "" "Tcl stack (innermost first):"
	lappend out [stackText]
	lappend out "" "pending timers:" [timers]
	lappend out "" [uiState]

	if {![catch { open $file w } fh]} {
		puts $fh [join $out \n]
		close $fh
		pruneDumps
	}
	return $file
}


proc stackText {} {
	set lines {}
	set top [info frame]
	# frame 1 is the outermost; skip the frames of this dump itself
	for {set i $top} {$i >= 1} {incr i -1} {
		if {[catch { info frame $i } f]} { continue }
		set where [expr {[dict exists $f proc] ? [dict get $f proc] : [dict get $f type]}]
		# the frames of the dump itself are not the stalled code
		if {[string match ::application::diagnose::* $where]
		 || ([dict exists $f cmd] && [string match "*::application::diagnose::dumpStack*" [dict get $f cmd]])} { continue }
		set cmd [string map {\n " "} [string range [expr {[dict exists $f cmd] ? [dict get $f cmd] : ""}] 0 140]]
		set at ""
		if {[dict exists $f file]} { set at " ([file tail [dict get $f file]]:[expr {[dict exists $f line] ? [dict get $f line] : "?"}])" }
		lappend lines "  $where$at: $cmd"
	}
	return [join $lines \n]
}


proc pruneDumps {} {
	variable MaxDumps
	set files [lsort [glob -nocomplain -directory [logDir] hang-2*.txt]]
	if {[llength $files] > $MaxDumps} {
		foreach f [lrange $files 0 end-$MaxDumps] { catch { file delete $f } }
	}
}


# The newest hang dumps, newest first, with the content of the newest one.
proc hangDumps {{count 3}} {
	set files [lsort -decreasing [glob -nocomplain -directory [logDir] hang-2*.txt]]
	set native [file join [logDir] hang-native.txt]
	if {![llength $files] && ![file exists $native]} {
		return "no hang dumps. Run 'kill -USR1 [pid]' while the program is stalled, or start it with SCIDB_HANG_WATCHDOG=8."
	}
	set out {}
	foreach f [lrange $files 0 $count-1] {
		lappend out "[file tail $f] ([clock format [file mtime $f] -format %T], [file size $f] bytes)"
	}
	if {[file exists $native]} {
		lappend out "hang-native.txt ([clock format [file mtime $native] -format %T], [file size $native] bytes)"
	}
	if {[llength $files]} {
		set fh [open [lindex $files 0] r]
		set text [read $fh 6000]
		close $fh
		lappend out "" "newest dump:" $text
	}
	return [join $out \n]
}


# ----------------------------------------------------------------------
# read-only introspection
# ----------------------------------------------------------------------

# The toplevels, the focus and -- the usual cause of a GUI that ignores
# clicks -- whoever holds a grab.
proc uiState {} {
	set lines {}
	foreach w [toplevels .] {
		set title ""
		catch { set title [wm title $w] }
		set state ""
		catch { set state [wm state $w] }
		lappend lines [format "  %-44s %-9s %s  \"%s\"" $w $state [winfo geometry $w] $title]
	}
	set out [list "toplevels (path, state, geometry, title):"]
	lappend out {*}$lines
	set focus [focus]
	lappend out "focus: [expr {$focus eq "" ? "none" : "$focus ([winfo class $focus])"}]"

	set grabs [grab current]
	if {![llength $grabs]} {
		lappend out "grab: none"
	} else {
		foreach g $grabs {
			lappend out "grab: $g ([winfo class $g], [grab status $g], [expr {[winfo ismapped $g] ? "mapped" : "NOT mapped"}])"
			set why [grabLeak $g]
			if {$why ne ""} { lappend out "  LIKELY STUCK: $why" }
		}
	}
	return [join $out \n]
}


proc toplevels {w} {
	set list {}
	if {[winfo toplevel $w] eq $w} { lappend list $w }
	foreach c [winfo children $w] {
		lappend list {*}[toplevels $c]
	}
	return $list
}


# Why a grab holder looks like a leak, or "".
proc grabLeak {g} {
	if {![winfo exists $g]} { return "the window no longer exists" }
	if {![winfo ismapped $g]} { return "the holder is not mapped, so nothing it shows can be clicked" }
	if {[winfo class $g] eq "Menubutton"} {
		set menu ""
		catch { set menu [$g cget -menu] }
		if {$menu eq "" || ![winfo exists $menu] || ![winfo ismapped $menu]} {
			return "a menubutton holds the grab but its menu is not posted; release_grab frees it"
		}
	}
	return ""
}


proc timers {} {
	set ids [after info]
	if {![llength $ids]} { return "  (none)" }
	set lines {}
	foreach id $ids {
		if {[catch { after info $id } info]} { continue }
		lassign $info script type
		lappend lines [format "  %-10s %-5s %s" $id $type \
			[string map {\n " "} [string range $script 0 100]]]
	}
	return [join $lines \n]
}


proc channels {} {
	set lines {}
	foreach ch [lsort [chan names]] {
		set info ""
		catch { set info "blocking=[chan configure $ch -blocking]" }
		lappend lines "  $ch  $info"
	}
	return [join $lines \n]
}


proc timersAndChannels {} {
	return "pending timers ([llength [after info]]):\n[timers]\n\nopen channels:\n[channels]"
}


proc loopHealth {} {
	variable Priv
	variable Beat

	if {$Priv(after) eq ""} {
		return "the event-loop heartbeat is not running (debug mode or SCIDB_HANG_WATCHDOG=<seconds> starts it)"
	}
	set out [list "heartbeat every $Beat ms, $Priv(beats) beats, last [expr {[clock milliseconds] - $Priv(last)}] ms ago"]
	lappend out "watchdog: [expr {$Priv(watchdog) > 0 ? "dumps after $Priv(watchdog) s without a beat" : "off"}]"
	lappend out "worst stall seen: $Priv(worst) ms"
	if {[llength $Priv(gaps)]} {
		lappend out "recent stalls (time, ms the GUI was unresponsive):"
		foreach g $Priv(gaps) {
			lappend out "  [clock format [expr {[lindex $g 0] / 1000}] -format %T]  [lindex $g 1] ms"
		}
	} else {
		lappend out "no stall of [set ::application::diagnose::Slow] ms or more"
	}
	return [join $out \n]
}


proc mediaState {} {
	set out {}
	foreach key {inprocess lastMedia statusbar followafter seektick} {
		if {[info exists ::application::media::Priv($key)]} {
			lappend out "$key: $::application::media::Priv($key)"
		}
	}
	if {![llength [info commands ::media::mpv::state]]} {
		return "media panel not loaded"
	}
	lappend out "libmpv linked: [::media::mpv::available?]"
	if {[info exists ::application::media::Priv(inprocess)] && $::application::media::Priv(inprocess)} {
		lappend out "player: state [::media::mpv::state], time [::media::mpv::time] s of [::media::mpv::duration] s, volume [::media::mpv::volume]"
	} else {
		lappend out "player: not playing"
	}
	return [join $out \n]
}


proc children {} {
	if {[catch { exec pgrep -a -P [pid] } out]} { return "no child processes" }
	return [string trim $out]
}


# ----------------------------------------------------------------------
# actions (run by the assistant only after the user confirmed)
# ----------------------------------------------------------------------

proc releaseGrab {window} {
	if {$window ni [grab current]} {
		error "$window does not hold a grab (holders: [grab current])"
	}
	set kind [grab status $window]
	grab release $window
	return "released the $kind grab of $window; grab now: [expr {[llength [grab current]] ? [grab current] : "none"}]"
}


proc cancelTimer {id} {
	if {$id ni [after info]} { error "no pending timer $id" }
	set info [after info $id]
	after cancel $id
	return "cancelled $id: [string range [lindex $info 0] 0 100]"
}


# ----------------------------------------------------------------------
# keep secrets away from the model
# ----------------------------------------------------------------------

# Every value of an environment variable that names a credential, replaced
# by its variable name wherever it occurs in <text>. Debug tools read
# arbitrary variables and the model may be a remote one.
proc scrub {text} {
	set map {}
	foreach name [array names ::env] {
		if {![regexp -nocase {key|token|secret|passw|credential|auth} $name]} { continue }
		set value $::env($name)
		if {[string length $value] >= 8} { lappend map $value "<redacted:$name>" }
	}
	if {![llength $map]} { return $text }
	return [string map $map $text]
}

} ;# namespace diagnose
} ;# namespace application

after idle ::application::diagnose::autostart

# vi:set ts=3 sw=3:
