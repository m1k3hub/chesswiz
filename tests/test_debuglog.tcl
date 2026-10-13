# Headless diagnostics tests; run with tclsh tests/test_debuglog.tcl.
package require Tcl 8.5
package require tcltest 2.5

set script [file normalize [file join [file dirname [info script]] .. tcl debuglog.tcl]]
set scratch [file join [::tcltest::temporaryDirectory] debuglog-[pid]]
namespace eval ::scidb::dir {}
set ::scidb::dir::user $scratch
set savedEnv [array get ::env CHESSWIZ_LOG]

proc loadDebug {mode} {
	if {[namespace exists ::debuglog]} { namespace delete ::debuglog }
	unset -nocomplain ::env(CHESSWIZ_LOG)
	if {$mode ne "absent"} { set ::env(CHESSWIZ_LOG) $mode }
	source $::script
	::debuglog::init
}
proc readLog {{suffix ""}} {
	set fd [open [file join $::scratch log debug.log$suffix]]
	set text [read $fd]
	close $fd
	return $text
}

foreach mode {absent {} info DEBUG 1} {
	tcltest::test disabled-$mode {disabled procs do not create files or hooks} -body {
		loadDebug $mode
		::debuglog::log test ignored
		list $::debuglog::enabled [file exists $scratch] [info body ::debuglog::log]
	} -result {0 0 {}}
}
foreach mode {debug trace} {
	tcltest::test enabled-$mode {enabled modes record ISO session start and timestamped lines} -body {
		loadDebug $mode
		::debuglog::log engine {> uci}
		set text [readLog]
		list $::debuglog::enabled \
			[regexp {\d+ms \[startup\] start=\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z platform=} $text] \
			[regexp {\d+ms \[engine\] > uci\n$} $text]
	} -cleanup { file delete -force $scratch } -result {1 1 1}
}
tcltest::test format-escaping {arbitrary error details stay on one physical line} -body {
	loadDebug debug
	::debuglog::log bgerror "bad {value}\nstack\r\\path\t雪"
	set line [lindex [split [string trimright [readLog] \n] \n] end]
	list [regexp {^\d+ms \[bgerror\] } $line] \
		[expr {[string range $line [expr {[string first {] } $line] + 2}] end] eq "bad {value}\\nstack\\r\\\\path\t雪"}]
} -cleanup { file delete -force $scratch } -result {1 1}

tcltest::test rotation {5 MiB rotates, replaces the previous backup, and continues logging} -body {
	loadDebug debug
	set fd [open $::debuglog::file w]
	puts -nonewline $fd [string repeat x [expr {5*1024*1024}]]
	close $fd
	set fd [open $::debuglog::file.1 w]; puts $fd old; close $fd
	::debuglog::log twm dock
	list [file size $::debuglog::file.1] \
		[regexp {^\d+ms \[twm\] dock\n$} [readLog]]
} -cleanup { file delete -force $scratch } -result {5242880 1}

tcltest::test unwritable {filesystem failures do not escape into app callbacks} -body {
	loadDebug debug
	file delete -force $scratch
	set fd [open $scratch w]; close $fd
	list [catch {::debuglog::log bgerror failure}] [catch {::debuglog::init}]
} -cleanup { file delete -force $scratch } -result {0 0}

tcltest::test engine-lines {all engine lines, including info, are logged individually} -body {
	loadDebug trace
	::debuglog::engine {} "> uci\n< info depth 1\n< uciok\r\n"
	set lines [split [string trimright [readLog] \n] \n]
	list [regexp {\d+ms \[engine\] > uci$} [lindex $lines end-2]] \
		[regexp {\d+ms \[engine\] < info depth 1$} [lindex $lines end-1]] \
		[regexp {\d+ms \[engine\] < uciok$} [lindex $lines end]]
} -cleanup { file delete -force $scratch } -result {1 1 1}

tcltest::test bgerror-stack {actual handler captures full -errorinfo before ignoring a benign error} -body {
	loadDebug debug
	set fd [open [file join [file dirname $script] start.tcl]]
	set text [read $fd]; close $fd
	set start [string first {proc bgerror } $text]
	set body {}
	foreach line [split [string range $text $start end] \n] {
		append body $line \n
		if {[info complete $body]} { break }
	}
	namespace eval ::scidb::intern {}
	namespace eval ::scidb $body
	set ::errorInfo {global stack}
	::scidb::bgerror {selection doesn't exist} [dict create -errorinfo "full stack\nframe two"]
	set log [readLog]
	list [expr {[string first {full stack\nframe two} $log] >= 0}] \
		[expr {[string first {global stack} $log] < 0}]
} -cleanup { file delete -force $scratch } -result {1 1}

tcltest::test append-session {starting again preserves prior records and adds one wall time} -body {
	loadDebug debug
	::debuglog::log twm previous
	loadDebug debug
	::debuglog::init
	list [regexp -all {\[startup\] start=} [readLog]] \
		[expr {[string first {[twm] previous} [readLog]] >= 0}] \
		[file exists $::debuglog::file.1]
} -cleanup { file delete -force $scratch } -result {2 1 0}

unset -nocomplain ::env(CHESSWIZ_LOG)
array set ::env $savedEnv
::tcltest::cleanupTests
