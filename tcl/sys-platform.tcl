# ======================================================================
# ::platform::sys -- Cross-platform OS helpers for Chesswiz
#
# Routes platform-specific process, CPU, URL/file opening, and speech
# commands across Linux, Windows, and macOS based on tcl_platform.
# ======================================================================

namespace eval ::util {

# Robust foreground exec wrapper.
# When background pipeline children (such as an engine, media stream, or AI
# process) terminate during a foreground exec, Tcl's waitpid wait can be
# reaped by the SIGCHLD handler or event loop, causing Tcl's exec to raise
# a spurious "child process lost" error with errorCode POSIX ECHILD {no children}.
#
# ::util::execSafe runs foreground commands redirecting output to a temporary file
# (> $tmp 2>@1). This avoids pipe buffering races in Tcl, and if ECHILD occurs
# while the command completed, returns the captured output rather than raising.
# Real non-zero exit statuses (CHILDSTATUS), signals (CHILDKILLED), and missing
# commands (POSIX ENOENT) are preserved and raised normally.
proc execSafe {args} {
	set switches {}
	set cmdArgs {}
	set parsingSwitches 1
	for {set i 0} {$i < [llength $args]} {incr i} {
		set a [lindex $args $i]
		if {$parsingSwitches && [string match "-*" $a]} {
			if {$a eq "--"} {
				set parsingSwitches 0
				continue
			} elseif {$a in {-keepnewline -ignorestderr}} {
				lappend switches $a
				continue
			}
		}
		set parsingSwitches 0
		lappend cmdArgs $a
	}

	# Background commands (& at end) return PID list immediately; run directly
	if {[lindex $cmdArgs end] eq "&"} {
		return [exec {*}$switches {*}$cmdArgs]
	}

	# Check if caller already specified 2>@1 at the end
	set had2at1 0
	if {[lindex $cmdArgs end] eq "2>@1"} {
		set had2at1 1
		set cmdArgs [lrange $cmdArgs 0 end-1]
	}

	# Check if caller already has stdout redirection (> or >& or >>)
	set hasStdoutRedir 0
	foreach token $cmdArgs {
		if {[string match ">*" $token]} {
			set hasStdoutRedir 1
			break
		}
	}

	# Check if caller already has stderr redirection (2> or 2>>)
	set hasStderrRedir 0
	foreach token $cmdArgs {
		if {[string match "2>*" $token]} {
			set hasStderrRedir 1
			break
		}
	}

	set tmp {}
	if {!$hasStdoutRedir} {
		if {[catch { close [file tempfile tmp] }]} {
			set tmp [file join [expr {[info exists ::env(TEMP)] ? $::env(TEMP) : "/tmp"}] "exec_[pid]_[clock microseconds]"]
		}
		lappend cmdArgs ">" $tmp
		if {$had2at1 || (!$hasStderrRedir && !("-ignorestderr" in $switches))} {
			lappend cmdArgs "2>@1"
		}
	} elseif {$had2at1} {
		# the caller redirects stdout itself: keep its stderr redirection
		lappend cmdArgs "2>@1"
	}

	try {
		set rc [catch {exec {*}$switches {*}$cmdArgs} out opts]
		set captured ""
		if {$tmp ne ""} {
			if {[file exists $tmp]} {
				set fh [open $tmp r]
				if {"-keepnewline" in $switches} {
					set captured [read $fh]
				} else {
					set captured [read -nonewline $fh]
				}
				close $fh
			}
		} else {
			set captured $out
		}

		if {$rc == 0} {
			return $captured
		}

		set ec {}
		if {[dict exists $opts -errorcode]} {
			set ec [dict get $opts -errorcode]
		}

		# ECHILD: child process wait was reaped by SIGCHLD trap or event loop.
		# The process executed to completion and its output was captured in $tmp.
		if {[lindex $ec 0] eq "POSIX" && [lindex $ec 1] eq "ECHILD"} {
			return $captured
		}

		# Real failure: preserve CHILDSTATUS, CHILDKILLED, POSIX ENOENT, etc.
		if {$tmp ne "" && $captured ne ""} {
			dict set opts -errorinfo $captured
			return -options $opts $captured
		}
		return -options $opts $out
	} finally {
		if {$tmp ne ""} {
			catch {file delete -force $tmp}
		}
	}
}

} ;# namespace ::util

namespace eval util {
	namespace export execSafe
}

namespace eval ::platform::sys {

# Number of available logical processor cores.
# Linux: exec nproc (identical to legacy behavior)
# Windows: $::env(NUMBER_OF_PROCESSORS)
# macOS: sysctl -n hw.ncpu
proc cpus {} {
	if {$::tcl_platform(platform) eq "windows"} {
		if {[info exists ::env(NUMBER_OF_PROCESSORS)] && [string is integer -strict $::env(NUMBER_OF_PROCESSORS)]} {
			return $::env(NUMBER_OF_PROCESSORS)
		}
		return 2
	} elseif {$::tcl_platform(os) eq "Darwin"} {
		if {![catch { ::util::execSafe sysctl -n hw.ncpu } out] && [string is integer -strict [string trim $out]]} {
			return [string trim $out]
		}
		return 2
	} else {
		# Linux as now
		return [string trim [::util::execSafe nproc]]
	}
}

# Terminate process(es) by PID.
# Windows: taskkill /PID pid /F
# Linux/macOS: exec kill ?signal? pid...
proc kill {pid {signal ""}} {
	if {$::tcl_platform(platform) eq "windows"} {
		set cmd [auto_execok taskkill]
		if {$cmd eq {}} { set cmd "taskkill" }
		foreach p $pid {
			if {[string length $p]} {
				catch { ::util::execSafe {*}$cmd /PID $p /F }
			}
		}
	} else {
		set sigArgs {}
		if {$signal ne ""} {
			if {[string index $signal 0] eq "-"} {
				set sigArgs [list $signal]
			} else {
				set sigArgs [list -$signal]
			}
		}
		set pids {}
		foreach p $pid {
			if {[string length $p]} {
				lappend pids $p
			}
		}
		if {[llength $pids]} {
			::util::execSafe kill {*}$sigArgs {*}$pids
		}
	}
}

# Test whether a process is alive.
# Returns 1 if running, 0 otherwise.
proc alive {pid} {
	if {![string length $pid] || ![string is integer -strict $pid]} {
		return 0
	}
	if {$::tcl_platform(platform) eq "windows"} {
		set cmd [auto_execok tasklist]
		if {$cmd eq {}} { set cmd "tasklist" }
		if {[catch { ::util::execSafe {*}$cmd /FI "PID eq $pid" /NH } out]} {
			return 0
		}
		if {[string match "*INFO:*" $out]} {
			return 0
		}
		foreach line [split $out "\n"] {
			set trimmed [string trim $line]
			if {[regexp "^\[^ \t\r\n\]+\[ \t\]+$pid\[ \t\]" $trimmed]} {
				return 1
			}
		}
		return 0
	} else {
		# Linux / Unix as now
		return [expr {![catch { ::util::execSafe kill -0 $pid }]}]
	}
}

# Open a URL or file path in the default desktop handler / browser.
# Windows: exec {*}[auto_execok start] "" $x &
# macOS: exec open $x &
# Linux: exec xdg-open $x &
proc openURL {x} {
	if {$::tcl_platform(platform) eq "windows"} {
		set start [auto_execok start]
		if {$start eq {}} {
			if {[info exists ::env(COMSPEC)]} {
				set start [list $::env(COMSPEC) /c start]
			} else {
				set start [list cmd.exe /c start]
			}
		}
		exec {*}$start "" $x &
	} elseif {$::tcl_platform(os) eq "Darwin"} {
		exec open $x &
	} else {
		# Linux as now
		exec xdg-open $x &
	}
}

# Windows helper scripts run by the Windows Script Host.
#
# tkchesswiz.exe is a GUI-subsystem program, so Tcl's exec starts console
# programs detached (no console); powershell.exe then exits at once without
# running anything. wscript.exe is a GUI program and cscript.exe works
# without a console, so the Windows helpers are VBScript. Each script is
# written once per session into the temporary directory.
proc WinScript {name body} {
	variable WinScripts
	if {[info exists WinScripts($name)] && [file isfile $WinScripts($name)]} {
		return $WinScripts($name)
	}
	set dir [expr {[info exists ::env(TEMP)] ? $::env(TEMP) : [pwd]}]
	set path [file join $dir chesswiz-$name.vbs]
	set chan [open $path w]
	try { puts -nonewline $chan $body } finally { close $chan }
	return [set WinScripts($name) $path]
}

# SAPI voice; the text comes from CHESSWIZ_TTS_TEXT, so no quoting can
# break it; an optional argument is a WAV file to write instead of playing.
variable SpeakVbs {Set v = CreateObject("SAPI.SpVoice")
t = CreateObject("WScript.Shell").Environment("PROCESS")("CHESSWIZ_TTS_TEXT")
If WScript.Arguments.Count > 0 Then
	Set st = CreateObject("SAPI.SpFileStream")
	st.Open WScript.Arguments(0), 3
	Set v.AudioOutputStream = st
End If
v.Speak t
If WScript.Arguments.Count > 0 Then st.Close
}

proc WinSpeak {text wav async} {
	variable SpeakVbs
	set argv [list wscript //nologo //B [file nativename [WinScript speak $SpeakVbs]]]
	if {$wav ne ""} { lappend argv [file nativename $wav] }
	set ::env(CHESSWIZ_TTS_TEXT) $text
	try {
		if {$async} { exec {*}$argv & } else { ::util::execSafe {*}$argv }
	} finally {
		unset -nocomplain ::env(CHESSWIZ_TTS_TEXT)
	}
	return 1
}

# Text-to-speech synthesis.
# Windows: SAPI through wscript (see WinScript)
# macOS: say
# Linux: espeak-ng
# If wav is specified, writes audio to the specified WAV file.
proc speak {text {wav ""}} {
	set text [string trim $text]
	if {![string length $text]} { return 0 }
	if {$::tcl_platform(platform) eq "windows"} {
		return [WinSpeak $text $wav 0]
	} elseif {$::tcl_platform(os) eq "Darwin"} {
		if {$wav ne ""} {
			::util::execSafe say -o $wav --data-format=LEI16@22050 $text
		} else {
			::util::execSafe say $text
		}
		return 1
	} else {
		# Linux as now
		if {$wav ne ""} {
			::util::execSafe espeak-ng -w $wav -s 165 $text
		} else {
			::util::execSafe espeak-ng -s 165 $text
		}
		return 1
	}
}

# Speak through the OS voice without blocking the GUI.
# Windows: SAPI through wscript; macOS: say.
# Returns 0 where there is no OS voice (Linux).
proc speakAsync {text} {
	set text [string trim $text]
	if {![string length $text]} { return 0 }
	if {$::tcl_platform(platform) eq "windows"} {
		return [WinSpeak $text "" 1]
	} elseif {$::tcl_platform(os) eq "Darwin"} {
		exec say -- $text &
		return 1
	}
	return 0
}

variable ChildrenVbs {Set w = GetObject("winmgmts:\\.\root\cimv2")
For Each p In w.ExecQuery("SELECT ProcessId, CommandLine FROM Win32_Process WHERE ParentProcessId = " & WScript.Arguments(0))
	WScript.Echo p.ProcessId & " " & p.CommandLine
Next
}

# List child process lines for a given parent PID.
# Linux: exec pgrep -a -P pid
# macOS: exec pgrep -l -P pid
# Windows: WMI query through cscript (see WinScript)
proc children {{pid ""}} {
	variable ChildrenVbs
	if {$pid eq ""} { set pid [pid] }
	if {$::tcl_platform(platform) eq "windows"} {
		if {[catch {
			set out [::util::execSafe cscript //nologo [file nativename [WinScript children $ChildrenVbs]] $pid]
			set out [string trim $out]
		} res] || $out eq ""} {
			return "no child processes"
		}
		return $out
	} elseif {$::tcl_platform(os) eq "Darwin"} {
		if {[catch { ::util::execSafe pgrep -l -P $pid } out]} { return "no child processes" }
		return [string trim $out]
	} else {
		# Linux as now
		if {[catch { ::util::execSafe pgrep -a -P $pid } out]} { return "no child processes" }
		return [string trim $out]
	}
}

# Read target of symbolic link (or Windows file link).
# Linux / macOS: exec readlink $path
# Windows: file readlink $path
proc readlink {path} {
	if {$::tcl_platform(platform) eq "windows"} {
		return [file readlink $path]
	} else {
		# Linux / Unix as now
		return [::util::execSafe readlink $path]
	}
}

# Find a working Python interpreter binary (python3, python, py).
proc python {} {
	if {![catch { ::util::execSafe python3 -c {import sys} }]} {
		return "python3"
	} elseif {![catch { ::util::execSafe python -c {import sys} }]} {
		return "python"
	}
	if {$::tcl_platform(platform) eq "windows"} {
		if {![catch { ::util::execSafe py -c {import sys} }]} {
			return "py"
		}
	}
	return ""
}

# Find a Python interpreter capable of importing the given module.
proc hasPythonModule {module} {
	set candidates {python3 python}
	if {$::tcl_platform(platform) eq "windows"} { lappend candidates py }
	set null [expr {$::tcl_platform(platform) eq "windows" ? "NUL" : "/dev/null"}]
	foreach py $candidates {
		if {![llength [auto_execok $py]]} { continue }
		if {![catch { ::util::execSafe $py -c "import $module" 2> $null }]} {
			return $py
		}
	}
	return ""
}

# Probe if a Python interpreter has an importable module without leaking stderr.
proc pythonHasModule {py module} {
	set null [expr {$::tcl_platform(platform) eq "windows" ? "NUL" : "/dev/null"}]
	return [expr {![catch { ::util::execSafe $py -c "import $module" 2> $null }]}]
}

# Run a command piping 'yes' on stdin for confirmations (such as xdg-mime).
proc execWithYes {args} {
	if {$::tcl_platform(platform) eq "windows"} {
		catch { ::util::execSafe cmd /c "echo y | {*}$args" }
	} else {
		# Linux as now
		::util::execSafe yes | {*}$args
	}
}

proc pipeYes {args} {
	execWithYes {*}$args
}

# Are file names case-insensitive on this system?
# Windows always is; macOS' default volumes are, but a volume may be
# case-sensitive, so the answer is only a first step (see sameFile).
proc caseInsensitivePaths? {} {
	if {$::tcl_platform(platform) eq "windows"} { return 1 }
	if {$::tcl_platform(os) eq "Darwin"} { return 1 }
	return 0
}

# Do two spellings name the same file?
# Paths reach the application in whatever form the source gave them: the
# file dialog, a drop, the single-instance hand-off, an options file
# written by an older build. On Windows the drive letter's case and the
# separators are not part of the name, and a link or a hard link is the
# same database. Used by the recent list, which must not lose an entry
# because it was written down differently.
proc sameFile {a b} {
	if {[string equal $a $b]} { return 1 }
	if {![string length $a] || ![string length $b]} { return 0 }

	if {[catch { set a [file normalize $a]; set b [file normalize $b] }]} {
		return 0
	}
	if {[string equal $a $b]} { return 1 }

	if {[caseInsensitivePaths?] && [string equal -nocase $a $b]} {
		# Same name up to case: the same file, unless the volume is
		# case-sensitive and both spellings really exist (two files).
		if {[catch { file stat $a sa }] || [catch { file stat $b sb }]} {
			return 1
		}
		return [expr {$sa(dev) == $sb(dev) && $sa(ino) == $sb(ino)}]
	}

	# Different spelling of one path (a link, a hard link, "x/../x"):
	# the disk decides, one inode is one database.
	if {[catch { file stat $a sa }] || [catch { file stat $b sb }]} { return 0 }
	if {!$sa(ino) || !$sb(ino)} { return 0 } ;# no usable identity here
	return [expr {$sa(dev) == $sb(dev) && $sa(ino) == $sb(ino)}]
}

# Touch a file (update mtime or create if absent).
proc touch {path} {
	if {$::tcl_platform(platform) eq "unix"} {
		::util::execSafe touch $path
	} else {
		if {[file exists $path]} {
			file mtime $path [clock seconds]
		} else {
			close [open $path a]
		}
	}
}

# Call after `package require tls`, before https requests. Packaged Windows
# and Aqua builds carry Mozilla roots for their private OpenSSL library.
proc tlsInit {} {
	if {$::tcl_platform(platform) eq "windows"} {
		set cafile [file join [file dirname [info nameofexecutable]] cacert.pem]
	} elseif {$::tcl_platform(os) eq "Darwin"} {
		set cafile [file join [file dirname [info nameofexecutable]] .. Resources cacert.pem]
	} else { return }
	if {[file isfile $cafile]} { ::tls::init -cafile $cafile -require 1 }
}

# HTTP invokes this command as ?socket options? host port. Derive SNI for
# each connection: the protocol registry is global, not specific to a host.
proc tlsSocket {args} {
	set host [lindex $args end-1]
	set port [lindex $args end]
	set opts [lrange $args 0 end-2]
	return [::tls::socket -servername $host {*}$opts $host $port]
}

# Call immediately before each HTTPS request. Other users of the global
# HTTP registry may replace or remove the handler; no module-local flag
# can establish that the current registration is still valid.
proc tlsRegister {} {
	package require http
	package require tls
	tlsInit
	::http::register https 443 ::platform::sys::tlsSocket
}

} ;# namespace ::platform::sys
