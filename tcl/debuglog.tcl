# Optional diagnostics for test VMs. Keep the disabled path free of I/O and traces.
namespace eval ::debuglog {
variable enabled [expr {[info exists ::env(CHESSWIZ_LOG)] && $::env(CHESSWIZ_LOG) in {debug trace}}]
if {$enabled} {
	variable started [clock milliseconds]
	variable wall [clock format [clock seconds] -gmt 1 -format {%Y-%m-%dT%H:%M:%SZ}]
}
variable maxSize [expr {5*1024*1024}]
variable file ""
variable initialized 0
variable opening
variable created

proc log {category message} {
	variable file
	variable started
	variable maxSize
	if {$file eq ""} { return }
	# Diagnostics must never cause a background error or interrupt engine I/O.
	catch {
		if {[file exists $file] && [file size $file] >= $maxSize} {
			file rename -force $file $file.1
		}
		set fd [open $file a]
		catch {
			fconfigure $fd -encoding utf-8 -translation lf
			set message [string map [list \\ \\\\ \r \\r \n \\n] $message]
			puts $fd "[expr {[clock milliseconds] - $started}]ms \[$category\] $message"
		}
		close $fd
	}
}

proc engine {unused message} {
	foreach line [split [string trimright $message \r\n] \n] {
		log engine [string trimright $line \r]
	}
}

proc toplevelTrace {command args} {
	variable opening
	variable created
	set w [lindex $command 1]
	if {[lindex $args end] eq "enter"} {
		set opening($w) [clock milliseconds]
	} elseif {[lindex $args 0] == 0 && [info exists opening($w)]} {
		set created($w) $opening($w)
		unset opening($w)
		log dialog "open $w class=[winfo class $w]"
		bindtags $w [linsert [bindtags $w] 0 DebuglogToplevel]
	} else {
		unset -nocomplain opening($w)
	}
}

# Startup gaps: top-level code between two proc definitions that ran long.
# The trace on ::proc must survive this namespace going away (tests do that).
variable ProcTraceCmd [list apply {args { catch { ::debuglog::procTrace {*}$args } }}]
proc procTrace {command args} {
	variable lastProc
	variable lastProcTime
	set now [clock milliseconds]
	if {$now - $lastProcTime >= 250} {
		log startup "slow [expr {$now - $lastProcTime}]ms after proc $lastProc, before proc [lindex $command 1]"
	}
	set lastProc [lindex $command 1]
	set lastProcTime $now
}

proc stopProcTrace {} {
	variable lastProc
	variable lastProcTime
	variable ProcTraceCmd
	catch { trace remove execution ::proc enter $ProcTraceCmd }
	set gap [expr {[clock milliseconds] - $lastProcTime}]
	if {$gap >= 250} { log startup "slow ${gap}ms after proc $lastProc, before the main window" }
}

proc mapped {w target} {
	variable created
	if {$w ne $target || ![info exists created($w)]} { return }
	if {$w eq ".application"} { stopProcTrace }
	log dialog "mapped $w after [expr {[clock milliseconds] - $created($w)}]ms"
	unset created($w)
}

proc destroyed {w target} {
	variable created
	if {$w eq $target} { unset -nocomplain created($w) }
}

proc init {} {
	variable file
	variable initialized
	variable wall
	if {$initialized || ![info exists ::scidb::dir::user]} { return }
	set initialized 1
	set file [file join $::scidb::dir::user log debug.log]
	catch { file mkdir [file dirname $file] }
	log startup "start=$wall platform=$::tcl_platform(os) $::tcl_platform(osVersion) Tcl=[info patchlevel]"
	foreach name {app version gitSha} {
		if {[info exists ::scidb::$name]} { log startup "$name=[set ::scidb::$name]" }
	}
	# ::scidb::revision is still the options file's revision here (83 on a
	# first start); the binary's own is ::scidb::misc::revision.
	if {[llength [info commands ::scidb::misc::revision]]} {
		log startup "revision=[::scidb::misc::revision]"
	}
	foreach name {user share exec engines config log} {
		if {[info exists ::scidb::dir::$name]} { log startup "$name=[set ::scidb::dir::$name]" }
	}
	log startup "executable=[info nameofexecutable]"
	if {[llength [info commands tk]]} {
		log startup "Tk=[package provide Tk] windowing=[tk windowingsystem] screen=[winfo screenwidth .]x[winfo screenheight .] scaling=[tk scaling]"
		# Trace the constructors: dialogs use many different Tk classes, and
		# ::toplevel and ::tk::toplevel are separate commands (both are used).
		bind DebuglogToplevel <Map> {::debuglog::mapped %W %W}
		bind DebuglogToplevel <Destroy> {::debuglog::destroyed %W %W}
		foreach constructor {::toplevel ::tk::toplevel} {
			if {[llength [info commands $constructor]]} {
				trace add execution $constructor {enter leave} ::debuglog::toplevelTrace
			}
		}
	}
	variable lastProc init
	variable lastProcTime [clock milliseconds]
	variable ProcTraceCmd
	trace add execution ::proc enter $ProcTraceCmd
	if {[llength [info commands ::scidb::engine::log]]} {
		if {[catch {::scidb::engine::log debug ::debuglog::engine {}} err]} {
			log startup "engine logging unavailable: $err"
		}
	}
}

if {!$enabled} {
	foreach name {log engine toplevelTrace procTrace stopProcTrace mapped destroyed init} {
		proc $name {args} {}
	}
}
} ;# namespace debuglog
