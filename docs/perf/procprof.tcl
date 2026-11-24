# Proc-level profiler: inclusive wall time + calls per proc during startup.
# Usage: PROFOUT=file src/tkchesswiz -encoding utf-8 docs/perf/procprof.tcl [args]
#        then: send Chesswiz procprofdump
set ::PP_T0 [clock microseconds]
array set ::PP_T {}; array set ::PP_N {}; set ::PP_STACK {}
proc ::PP_enter {cmd op} {
	lappend ::PP_STACK [clock microseconds]
}
proc ::PP_leave {cmd code res op} {
	set t [lindex $::PP_STACK end]; set ::PP_STACK [lrange $::PP_STACK 0 end-1]
	set name [lindex $cmd 0]
	set d [expr {[clock microseconds]-$t}]
	if {[info exists ::PP_T($name)]} { incr ::PP_T($name) $d; incr ::PP_N($name) } else { set ::PP_T($name) $d; set ::PP_N($name) 1 }
}
rename ::proc ::PP_proc
::PP_proc ::proc {name args body} {
	uplevel 1 [list ::PP_proc $name $args $body]
	set q [uplevel 1 [list namespace which -command $name]]
	if {$q ne "" && ![string match ::PP_* $q]} {
		catch { trace add execution $q enter ::PP_enter; trace add execution $q leave ::PP_leave }
	}
}
::PP_proc ::procprofdump {{n 80}} {
	set l {}
	foreach k [array names ::PP_T] { lappend l [list $::PP_T($k) $::PP_N($k) $k] }
	set f [open $::env(PROFOUT) w]
	foreach e [lrange [lsort -integer -decreasing -index 0 $l] 0 $n] {
		puts $f [format "%9.1f ms %7d  %s" [expr {[lindex $e 0]/1000.0}] [lindex $e 1] [lindex $e 2]]
	}
	close $f
}
set ::argv0 [file normalize src/tkchesswiz]
source tcl/chesswiz
