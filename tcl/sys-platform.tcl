# ======================================================================
# ::platform::sys -- Cross-platform OS helpers for Chesswiz
#
# Routes platform-specific process, CPU, URL/file opening, and speech
# commands across Linux, Windows, and macOS based on tcl_platform.
# ======================================================================

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
		if {![catch { exec sysctl -n hw.ncpu } out] && [string is integer -strict [string trim $out]]} {
			return [string trim $out]
		}
		return 2
	} else {
		# Linux as now
		return [string trim [exec nproc]]
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
				catch { exec {*}$cmd /PID $p /F }
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
			exec kill {*}$sigArgs {*}$pids
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
		if {[catch { exec {*}$cmd /FI "PID eq $pid" /NH } out]} {
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
		return [expr {![catch { exec kill -0 $pid }]}]
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

# Text-to-speech synthesis.
# Windows: PowerShell System.Speech SpeechSynthesizer
# macOS: say
# Linux: espeak-ng
# If wav is specified, writes audio to the specified WAV file.
proc speak {text {wav ""}} {
	set text [string trim $text]
	if {![string length $text]} { return 0 }
	if {$::tcl_platform(platform) eq "windows"} {
		if {$wav ne ""} {
			exec powershell -NoProfile -Command \
				{Add-Type -AssemblyName System.Speech; $s = New-Object System.Speech.Synthesis.SpeechSynthesizer; $s.SetOutputToWaveFile($args[0]); $s.Speak($args[1]); $s.Dispose()} \
				$wav $text
		} else {
			exec powershell -NoProfile -Command \
				{Add-Type -AssemblyName System.Speech; $s = New-Object System.Speech.Synthesis.SpeechSynthesizer; $s.Speak($args[0]); $s.Dispose()} \
				$text
		}
		return 1
	} elseif {$::tcl_platform(os) eq "Darwin"} {
		if {$wav ne ""} {
			exec say -o $wav --data-format=LEI16@22050 $text
		} else {
			exec say $text
		}
		return 1
	} else {
		# Linux as now
		if {$wav ne ""} {
			exec espeak-ng -w $wav -s 165 $text
		} else {
			exec espeak-ng -s 165 $text
		}
		return 1
	}
}

# List child process lines for a given parent PID.
# Linux: exec pgrep -a -P pid
# macOS: exec pgrep -l -P pid
# Windows: CIM query via PowerShell
proc children {{pid ""}} {
	if {$pid eq ""} { set pid [pid] }
	if {$::tcl_platform(platform) eq "windows"} {
		if {[catch {
			set out [exec powershell -NoProfile -Command \
				"Get-CimInstance Win32_Process | Where-Object { \$_.ParentProcessId -eq $pid } | ForEach-Object { \"\$(\$_.ProcessId) \$(\$_.CommandLine)\" }"]
			set out [string trim $out]
		} res] || $out eq ""} {
			return "no child processes"
		}
		return $out
	} elseif {$::tcl_platform(os) eq "Darwin"} {
		if {[catch { exec pgrep -l -P $pid } out]} { return "no child processes" }
		return [string trim $out]
	} else {
		# Linux as now
		if {[catch { exec pgrep -a -P $pid } out]} { return "no child processes" }
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
		return [exec readlink $path]
	}
}

# Find a working Python interpreter binary (python3, python, py).
proc python {} {
	if {![catch { exec python3 -c {import sys} }]} {
		return "python3"
	} elseif {![catch { exec python -c {import sys} }]} {
		return "python"
	}
	if {$::tcl_platform(platform) eq "windows"} {
		if {![catch { exec py -c {import sys} }]} {
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
		if {![catch { exec $py -c "import $module" 2> $null }]} {
			return $py
		}
	}
	return ""
}

# Probe if a Python interpreter has an importable module without leaking stderr.
proc pythonHasModule {py module} {
	set null [expr {$::tcl_platform(platform) eq "windows" ? "NUL" : "/dev/null"}]
	return [expr {![catch { exec $py -c "import $module" 2> $null }]}]
}

# Run a command piping 'yes' on stdin for confirmations (such as xdg-mime).
proc execWithYes {args} {
	if {$::tcl_platform(platform) eq "windows"} {
		catch { exec cmd /c "echo y | {*}$args" }
	} else {
		# Linux as now
		exec yes | {*}$args
	}
}

proc pipeYes {args} {
	execWithYes {*}$args
}

# Touch a file (update mtime or create if absent).
proc touch {path} {
	if {$::tcl_platform(platform) eq "unix"} {
		exec touch $path
	} else {
		if {[file exists $path]} {
			file mtime $path [clock seconds]
		} else {
			close [open $path a]
		}
	}
}

} ;# namespace ::platform::sys
