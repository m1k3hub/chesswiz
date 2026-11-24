# Top-level load profiler: logs gaps between successive proc definitions.
# Usage: PROFOUT=file src/tkchesswiz -encoding utf-8 docs/perf/gaps.tcl ; send Chesswiz gapsdump
set ::G_last [clock microseconds]; set ::G_lastp start; set ::G_list {}
proc ::G_tr {cmd op} {
	set now [clock microseconds]
	set d [expr {$now - $::G_last}]
	if {$d > 8000} { lappend ::G_list [list $d $::G_lastp [lindex $cmd 1]] }
	set ::G_last $now; set ::G_lastp [lindex $cmd 1]
}
trace add execution ::proc enter ::G_tr
proc ::gapsdump {} {
	set f [open $::env(PROFOUT) w]
	set tot 0
	foreach e [lsort -integer -decreasing -index 0 $::G_list] { incr tot [lindex $e 0]; puts $f [format "%7.1f ms after %s before %s" [expr {[lindex $e 0]/1000.0}] [lindex $e 1] [lindex $e 2]] }
	puts $f "total gaps>8ms: [expr {$tot/1000}] ms"
	close $f
}
set ::argv0 [file normalize src/tkchesswiz]
source tcl/chesswiz
