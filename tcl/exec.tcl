#!/bin/sh
#! ======================================================================
#! $RCSfile: tk_init.h,v $
#! $Revision: 1507 $
#! $Date: 2018-08-13 08:17:53 -0400 (Mon, 13 Aug 2018) $
#! $Author: gregor $
#! ======================================================================

#! ======================================================================
#!    _/|            __
#!   // o\         /    )           ,        /    /
#!   || ._)    ----\---------__----------__-/----/__-
#!   //__\          \      /   '  /    /   /    /   )
#!   )___(     _(____/____(___ __/____(___/____(___/_
#! ======================================================================

#! ======================================================================
#! Copyright: (C) 2009-2013 Gregor Cramer
#! ======================================================================

#! ======================================================================
#! This program is free software; you can redistribute it and/or modify
#! it under the terms of the GNU General Public License as published by
#! the Free Software Foundation; either version 2 of the License, or
#! (at your option) any later version.
#! ======================================================================

#! The "\" at the end of the comment line below is necessary! It means
#! that the "exec" line is a comment to Tcl/Tk, but not to /bin/sh.
#! The next line restarts using the binary named at build time, found beside the real script (symlinks followed): \
self=$0; while [ -h "$self" ]; do link=`readlink "$self"`; case $link in /*) self=$link;; *) self=`dirname "$self"`/$link;; esac; done; exec_dir=`dirname "$self"`; exec_base="%TKPROGRAM%"; case $exec_base in ?TKPROGRAM?) exec_base=tk`basename "$self"`;; esac; if [ -x "$exec_dir/$exec_base" ]; then exec "$exec_dir/$exec_base" "$self" ${1+"$@"}; else exec "$exec_dir/../src/$exec_base" "$self" ${1+"$@"}; fi

package require Tcl 8.5
package require Tk  8.5
package require Ttk
package require tkscidb

# ----------------------------------------------------------------------
# Dynamic HiDPI / Retina display scaling calibration:
# Calculate true monitor DPI and calibrate Tk's font/geometry scaling.
# ----------------------------------------------------------------------
if {[tk windowingsystem] ne "aqua"} {
	catch {
		set _sWidth [winfo screenwidth .]
		set _sMmWidth [winfo screenmmwidth .]
		if {$_sWidth > 0 && $_sMmWidth > 0} {
			set _calcDpi [expr {round(($_sWidth * 25.4) / $_sMmWidth)}]
			# Clamp to sensible boundaries (84 to 288 DPI)
			if {$_calcDpi >= 84 && $_calcDpi <= 288} {
				set _scale [expr {$_calcDpi / 72.0}]
				# Do not downscale below standard 1.0 (96 DPI = 1.3333 scaling)
				if {$_scale > [tk scaling]} {
					tk scaling $_scale
				}
			}
		}
		unset _sWidth _sMmWidth _calcDpi _scale
	}
}


namespace eval scidb {
	set app		Chesswiz
	set version "1.0 BETA"
	set gitSha "unknown"
	set commitDate "unknown"
	set buildDate "unknown"
	catch {
		set _bi [::scidb::misc::buildInfo]
		if {[dict exists $_bi gitSha]} { set gitSha [dict get $_bi gitSha] }
		if {[dict exists $_bi commitDate]} { set commitDate [dict get $_bi commitDate] }
		if {[dict exists $_bi buildDate]} { set buildDate [dict get $_bi buildDate] }
		unset _bi
	}
}


wm withdraw .


set nameofexecutable [info nameofexecutable]
if {[llength $nameofexecutable] == 0} {
	if {$tcl_platform(platform) eq "unix"} {
		catch {
			if {![llength [info commands ::platform::sys::readlink]]} {
				set _spf [file join [file dirname [info script]] sys-platform.tcl]
				if {[file exists $_spf]} { source $_spf }
				unset -nocomplain _spf
			}
			set nameofexecutable [::platform::sys::readlink /proc/[pid]/exe]
		}
	}
	if {[llength $nameofexecutable] == 0} {
		# broken Tk library, e.g. 8.6b2
		append msg "You've installed a broken Tcl/Tk library (version [info patchlevel]). "
		append msg "Please change the version (8.5.6 is recommended)."
		tk_messageBox -type ok -icon error -title "$scidb::app: broken library" -message $msg
		exit 1
	}
}
set nameofexecutable [file normalize $nameofexecutable]


if {[::scidb::misc::version] ne $scidb::version} {
	wm withdraw .
	if {$tcl_platform(platform) eq "windows"} {
		append msg "This is $scidb::app version [::scidb::misc::version], but the scidb.gui "
		append msg "data file has the version number $scidb::version."
	} else {
		append msg "This is $scidb::app version '$scidb::version', but the "
		append msg "[file tail $nameofexecutable] program it uses is "
		append msg "version '[::scidb::misc::version]'."
	}
	tk_messageBox -type ok -icon error -title "$scidb::app: version error" -message $msg
	exit 1
}


if {[info patchlevel] eq "8.5.10"} {
	# broken Tk library (e.g. Ubuntu 11.10)
	append msg "You've installed a broken Tk library (patch level [info patchlevel]). "
	append msg "Some crashes may occur with this Tk library.\n\n"
	append msg "It is recommended to use a different patch level of this library."
	append msg "(Version 8.5.6 is recommended.)"
	tk_messageBox -type ok -icon error -title "$scidb::app: broken library" -message $msg
}


namespace eval process {

set ProgramOptions [list                                                                     \
	[list "--"                      "Only file names after this"]                             \
	[list "--help"                  "Print help (this message) and exit"]                     \
	[list "--version"               "Print version information and exit"]                     \
	[list "--full-screen"           "Start program with full-screen modus"]                   \
	[list "--initial-layout"        "Start program with intitial layout"]                     \
	[list "--reset-fonts"           "Reset all fonts to default size"]                        \
	[list "--show-board"            "Switch to board tab immediately after startup"]          \
	[list "--re-open"               "Re-open databases from last session"]                    \
	[list "--fast-load"             "Do only load the mandatory files at startup"]            \
	[list "--first-time"            "Delete option file and recovery files at startup"        \
	                                "(starting $::scidb::app as it would be the first time)"] \
	[list "--recover-options"       "Recover option files deleted with last '--first-time'"]  \
	[list "--elo-only"              "Do not load rating files except ELO rating"]             \
	[list "--print-recovery-files"  "Print recovery files from last session and exit"]        \
	[list "--delete-recovery-files" "Delete recovery files and exit"]                         \
	[list "--dont-recover-files"    "Do not recover unsaved games from last session"]         \
	[list "--recover-old-files"     "Recover games from older sessions"                       \
	                                "(will skip games from last session)"]                    \
	[list "--single-process"        "Forcing a single process of $::scidb::app"               \
	                                "(you shouldn't use this option; only for testing)"]      \
	[list "--update-themes"         "Update themes (from shared directory)"]                  \
	[list "--force-grab"            "Do not suppress grabs in debug mode"                     \
	                                "(only for debugging)"]                                   \
	[list "--ai-model=MODEL"        "Use MODEL for the AI features (this session only)"]      \
	[list "--ai-provider=NAME"      "Use provider NAME for the AI features (ollama, ...)"]    \
	[list "--ai-classifier=NAME"    "Use System One classifier NAME (kev, simple-jev, plumb," \
	                                "jev, or off; this session only)"]                        \
	[list "--ai-debug"              "Enable the assistant's debugging tools"]                 \
	[list "--ask=REQUEST"           "Send REQUEST to the assistant of the running $::scidb::app," \
	                                "print the reply and exit"]                               \
	[list "--chat"                  "Chat with the assistant in this terminal (starts"        \
	                                "$::scidb::app when it is not running)"]                  \
]

# Options that take a value: --name=value, or --name value.
variable ValueOptions {ask ai-model ai-provider ai-classifier}

array set Options {}
array set Valued {}
variable Arguments {}


proc arguments {} { return [set [namespace current]::Arguments] }


# The value of an option given as --name=value, or {}.
proc optionValue {arg} {
	set value {}
	catch { set value [set [namespace current]::Options($arg)] }
	if {$value eq "1" && ![info exists [namespace current]::Valued($arg)]} { return {} }
	return $value
}


# Whether option <arg> was given.
proc testOption {arg} {
	set rc 0
	catch { set rc [set [namespace current]::Options($arg)] }
	if {[info exists [namespace current]::Valued($arg)]} { return 1 }
	return $rc
}


proc setOption {arg {value 1}} {
	set [namespace current]::Options($arg) $value
}


proc ParseArgs {} {
	global argc argv
	variable Options
	variable Valued
	variable Arguments
	variable ProgramOptions
	variable ValueOptions

	for {set i 0} {$i < $argc} {incr i} {
		set arg [lindex $argv $i]
		if {$arg eq "--"} {
			incr i
			break
		}
		if {$arg eq "--session-id"} {
			incr i
			continue
		}
		if {[string range $arg 0 1] ne "--"} {
			break
		}

		set option [string range $arg 2 end]
		set name $arg
		if {[set k [string first = $option]] >= 0} {
			# --name=value
			set name --[string range $option 0 [expr {$k - 1}]]
			set option [string range $option 0 [expr {$k - 1}]]
			set Options($option) [string range $arg [expr {$k + 3}] end]
			set Valued($option) 1
		} elseif {$option in $ValueOptions && $i + 1 < $argc} {
			# --name value
			set Options($option) [lindex $argv [incr i]]
			set Valued($option) 1
		} else {
			set Options($option) 1
		}

		set known [lmap entry $ProgramOptions { lindex [split [lindex $entry 0] =] 0 }]
		if {$name ni $known} {
			puts stderr "Unrecognized option: $arg"
		}
	}

	if {[::scidb::misc::debug?]} {
		set Options(single-process) 1
	}

	set Arguments [lrange $argv $i end]
}

ParseArgs


if {[testOption help]} {
	puts "$::scidb::app version $::scidb::version"
	puts ""
	puts "Usage: $::argv0 \[options ...] \[database ...]"
	puts ""
	puts "Options:"

	set maxlen 0
	foreach opts $ProgramOptions {
		set maxlen [expr {max($maxlen, [string length [lindex $opts 0]])}]
	}
	foreach opts $ProgramOptions {
		set i 0
		foreach s $opts {
			if {$i == 0} {
				puts -nonewline "  "
				puts -nonewline $s
				set spaces [expr {$maxlen + 1 - [string length $s]}]
			} else {
				puts -nonewline [string repeat " " $spaces]
				puts $s
				set spaces [expr {$maxlen + 3}]
			}
			incr i
		}
	}

	puts ""
	puts "Options recognised by GUI (Tk) library:"
	puts "  -geometry GEOMETRY      Use GEOMETRY for initial geometry"
	puts "  -display DISPLAY        Run $::scidb::app on DISPLAY"
	puts "  -sync                   Use synchronous mode for display server"
	exit 0
}

unset ProgramOptions

} ;# namespace process


namespace eval remote {
namespace eval mc {

set PostponedMessage "Opening of database \"%s\" is postponed until current operation will be finished."

}


array set Vars {
	after		{}
	pending	{}
	busy		0
}


proc blocked? {} {
	return $::scidb::intern::blocked
}


proc pending? {} {
	variable Vars
	return [expr {!$::scidb::intern::blocked && !$Vars(busy) && $::scidb::intern::postponed}]
}


proc busyOperation {cmd} {
	variable Vars

	incr Vars(busy)
	set code [catch {uplevel 1 $cmd} result options]
	incr Vars(busy) -1
	if {$::scidb::intern::postponed} {
		after idle [namespace code update]
	}
	if {$code == 0} {
		return $result
	}
	array set opts $options
	return \
		-code $opts(-code) \
		-errorcode $opts(-errorcode) \
		-errorinfo $opts(-errorinfo) \
		-rethrow 1 \
		$result \
	;
}


proc update {} {
	variable Vars

	if {[pending?]} {
		after cancel $Vars(after)
		set Vars(after) [after idle [namespace code Update]]
	}
}


proc cleanup {} {
	set [namespace current]::Vars(pending) {}
}


proc requestOpenBases {pathList} {
	variable Vars

	if {[llength $pathList]} {
		if {$::scidb::intern::blocked} {
			foreach path $pathList {
				if {![info exists Vars(infoBox:$path)]} {
					set ::scidb::intern::postponed 1
					lappend Vars(pending) $path
					set msg [format $mc::PostponedMessage $path]
					set Vars(infoBox:$path) \
						[::dialog::info -buttons {} -title $::scidb::app -message $msg -topmost yes]
				}
			}
		} else {
			openBases $pathList
		}
	}
}


proc Update {} {
	variable Vars

	if {[llength $Vars(pending)] == 0} { return }

	foreach path $Vars(pending) {
		if {[info exists Vars(infoBox:$path)]} {
			if {[winfo exists $Vars(infoBox:$path)]} {
				destroy $Vars(infoBox:$path)
			}
			unset Vars(infoBox:$path)
		}
	}

	set files $Vars(pending)
	set Vars(pending) {}
	set ::scidb::intern::postponed 0
	openBases $files
}


proc SendPath {port} {
	global argc
	global argv

	set args {}

	for {set i 0} {$i < $argc} {incr i} {
		set arg [lindex $argv $i]

		if {[string index $arg 0] ne "-"} {
			lappend args $arg
		}
	}
	
	set chan [socket 127.0.0.1 $port]
	puts $chan $args
	flush $chan
	close $chan
}


# ----------------------------------------------------------------------
# Assistant client: --ask and --chat talk to the assistant of a running
# instance over the single-instance socket. The session opens with the
# line [list --assistant] (paths never start with "-"); then each line is
# a Tcl list, client -> server:  ask TEXT | confirm 0|1 | clear
#                 server -> client:  hello MODEL DEBUG | tool NAME REPLY |
#                                    confirm WHAT | reply TEXT | error TEXT |
#                                    ready
# The client is event driven, so it runs in a separate process (vwait) and
# inside a running instance alike. <done> is called with the exit status.
# ----------------------------------------------------------------------

array set Client {}


# One message per line: a Tcl list with newlines and backslashes escaped
# (tool replies and answers are multi-line).
proc encodeLine {args} {
	return [string map {\\ \\\\ \n \\n \r \\r} $args]
}


proc decodeLine {line} {
	return [string map {\\\\ \\ \\n \n \\r \r} $line]
}


proc ClientSend {args} {
	variable Client
	puts $Client(sock) [encodeLine {*}$args]
}

proc assistantClient {port mode request done} {
	variable Client

	if {$mode eq "ask" && ![string length [string trim $request]]} {
		puts stderr "usage: $::scidb::app --ask \"REQUEST\""
		{*}$done 1
		return
	}

	if {[catch { set sock [socket 127.0.0.1 $port] } err]} {
		puts stderr "cannot reach $::scidb::app: $err"
		{*}$done 2
		return
	}
	fconfigure $sock -blocking 0 -buffering line -encoding utf-8
	fconfigure stdout -buffering none -encoding utf-8
	array set Client [list sock $sock mode $mode request $request done $done \
		confirming 0 status 0 stdin 0]

	puts $sock [list --assistant]
	fileevent $sock readable [namespace code ClientRead]
}


proc ClientRead {} {
	variable Client

	set sock $Client(sock)
	if {[gets $sock line] < 0} {
		if {[eof $sock]} { ClientDone 1 "connection closed by $::scidb::app" }
		return
	}
	if {[catch { set args [lassign [decodeLine $line] kind] }]} {
		ClientDone 1 "garbled message from $::scidb::app: $line"
		return
	}

	switch -- $kind {
		hello {
			lassign $args model debug
			if {$Client(mode) eq "ask"} {
				ClientSend ask $Client(request)
			} else {
				set dbg [expr {$debug ? ", debug tools on" : ""}]
				puts "$::scidb::app assistant ($model$dbg). /clear resets, /quit or Ctrl-D leaves."
				ClientListen
			}
		}
		tool {
			lassign $args name reply
			set first [lindex [split $reply \n] 0]
			if {[string length $first] > 160} { set first "[string range $first 0 156]..." }
			puts "  \[$name\] $first"
		}
		confirm {
			set Client(confirming) 1
			puts -nonewline "The assistant wants to: [lindex $args 0]\nAllow? \[y/N\] "
			ClientListen 1
		}
		reply { puts [lindex $args 0] }
		error {
			puts stderr "error: [lindex $args 0]"
			set Client(status) 1
		}
		ready {
			if {$Client(mode) eq "ask"} {
				ClientDone $Client(status)
			} else {
				set Client(status) 0
				ClientListen
			}
		}
	}
}


# Read stdin only while waiting for the user: the prompt of a chat, or a
# confirmation. Piped input is then consumed one request at a time.
proc ClientListen {{confirm 0}} {
	variable Client

	if {!$confirm} { puts -nonewline "> " }
	fconfigure stdin -blocking 0 -encoding utf-8
	fileevent stdin readable [namespace code ClientStdin]
}


proc ClientPause {} {
	catch { fileevent stdin readable {} }
}


proc ClientStdin {} {
	variable Client

	if {[gets stdin line] < 0} {
		if {![eof stdin]} { return }
		ClientPause
		puts ""
		# no terminal, or Ctrl-D: deny a pending confirmation, leave a chat
		if {$Client(confirming)} {
			set Client(confirming) 0
			ClientSend confirm 0
		} elseif {$Client(mode) eq "chat"} {
			ClientDone 0
		}
		return
	}
	set line [string trim $line]

	if {$Client(confirming)} {
		set Client(confirming) 0
		if {![ClientTerminal]} { puts $line }
		ClientPause
		ClientSend confirm [string match -nocase y* $line]
		return
	}

	switch -- $line {
		"" { puts -nonewline "> " }
		/quit - /exit { ClientDone 0 }
		/clear {
			if {![ClientTerminal]} { puts $line }
			puts "(conversation cleared)"
			ClientPause
			ClientSend clear
		}
		default {
			# a piped chat echoes its requests, so the transcript reads well
			if {![ClientTerminal]} { puts $line }
			ClientPause
			ClientSend ask $line
		}
	}
}


proc ClientTerminal {} {
	return [expr {![catch { fconfigure stdin -mode }]}]
}


proc ClientDone {status {message ""}} {
	variable Client

	if {![info exists Client(sock)]} { return }
	if {[string length $message]} { puts stderr $message }
	catch { fileevent stdin readable {} }
	catch { close $Client(sock) }
	set done $Client(done)
	array unset Client
	{*}$done $status
}


# Where assistant sessions go in a running instance; defined by the app.
proc IncomingAssistant {chan} {
	if {[llength [info commands ::application::assistant::attach]]} {
		::application::assistant::attach $chan
	} else {
		fconfigure $chan -blocking 1
		puts $chan [encodeLine error "$::scidb::app is still starting, try again"]
		puts $chan [encodeLine ready]
		close $chan
	}
}


proc Incoming {chan addr port} {
	# Non-blocking: a peer that sends a partial line must not freeze the GUI.
	fconfigure $chan -blocking 0
	fileevent $chan readable [namespace code [list IncomingOffered $chan]]
}


proc IncomingOffered {chan} {
	if {[gets $chan pathList] >= 0} {
		if {[lindex $pathList 0] eq "--assistant"} {
			fileevent $chan readable {}
			IncomingAssistant $chan
			return
		}
		catch { close $chan }
		after idle [namespace code [list requestOpenBases $pathList]]
	} elseif {[eof $chan]} {
		# Peer went away without a full line; without closing here the
		# readable event would fire forever (busy loop + leaked socket).
		catch { close $chan }
	}
}


#proc Vwait {varname} {
#	set ::scidb::intern::blocked 1
#	set code [catch {uplevel 1 [list ::remote::VwaitOrig $varname]} res]
#	set ::scidb::intern::blocked 0
#
#	after idle ::remote::update
#	return -code $code $res
#}
#
#rename ::vwait ::remote::VwaitOrig
#rename ::remote::Vwait ::vwait


if {	![::process::testOption single-process]
	&& ![::process::testOption version]
	&& ![::process::testOption print-recovery-files]} {

	# Pick a port number based on the name of the main script executing
	set port [expr {1024 + [::scidb::misc::crc32 [file normalize $::argv0]] % 30000}]
	set Vars(port) $port

	if {[catch {socket -server [namespace code Incoming] -myaddr localhost $port} err]} {
		lassign $::errorCode cls name
		if {$cls eq "POSIX" && $name eq "EADDRINUSE"} {
			if {[::process::testOption ask] || [::process::testOption chat]} {
				# talk to the running instance's assistant, then leave
				catch { wm withdraw . }
				set mode [expr {[::process::testOption chat] ? "chat" : "ask"}]
				assistantClient $port $mode [::process::optionValue ask] \
					[list apply {{status args} { set ::remote::Vars(exit) $status }}]
				if {![info exists Vars(exit)]} { vwait ::remote::Vars(exit) }
				exit $Vars(exit)
			}
			SendPath $port
			exit 1
		}
	} elseif {[::process::testOption ask]} {
		puts stderr "$::scidb::app is not running; start it first, or use --chat"
		exit 2
	}
	unset -nocomplain err
}

} ;# namespace remote

# vi:set ts=3 sw=3:
