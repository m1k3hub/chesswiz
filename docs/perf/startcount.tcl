# Log calls (with ms since start and args) of selected procs during startup.
set ::SC_T0 [clock milliseconds]; set ::SC_LOG {}
set ::SC_PROCS {RebuildBoardNow MakePieces}
rename ::proc ::SC_proc
::SC_proc ::proc {name args body} {
	uplevel 1 [list ::SC_proc $name $args $body]
	if {[namespace tail $name] in $::SC_PROCS} {
		set q [uplevel 1 [list namespace which -command $name]]
		trace add execution $q enter [list ::apply {{q cmd op} {
			set st {}; for {set l [expr {[info level]-1}]} {$l > 0} {incr l -1} { lappend st [lindex [info level $l] 0] }
			lappend ::SC_LOG "[expr {[clock milliseconds]-$::SC_T0}] $q [lrange $cmd 1 3] <- [join $st { <- }]" }} $q]
	}
}
set ::argv0 [file normalize src/tkchesswiz]
source tcl/chesswiz
