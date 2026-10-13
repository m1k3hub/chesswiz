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

proc mapped {w target} {
	variable created
	if {$w ne $target || ![info exists created($w)]} { return }
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
	foreach name {app version revision gitSha} {
		if {[info exists ::scidb::$name]} { log startup "$name=[set ::scidb::$name]" }
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
	if {[llength [info commands ::scidb::engine::log]]} {
		if {[catch {::scidb::engine::log debug ::debuglog::engine {}} err]} {
			log startup "engine logging unavailable: $err"
		}
	}
}

if {!$enabled} {
	foreach name {log engine toplevelTrace mapped destroyed init} {
		proc $name {args} {}
	}
}
} ;# namespace debuglog
