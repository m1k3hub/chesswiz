# ======================================================================
# Scidb App Test — progress callbacks repaint at most every 50 ms. An
# update on Aqua waits for a screen frame (~33 ms), and opening a ChessBase
# archive sends 1139 progress updates: 38 s on the Mac for a 0.1 s load.
# ======================================================================

package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

namespace eval ::scidb::test::progress { variable updates 0 }

# A command that reports progress the way the C++ code does.
proc ::scidb::test::progress::Work {callback parent args} {
	{*}$callback open $parent 1000
	{*}$callback start $parent 1000
	for {set i 1} {$i <= 1000} {incr i} {
		{*}$callback update $parent $i
	}
	{*}$callback finish $parent 1000
	{*}$callback close $parent
	return done
}

tcltest::test progress-update-throttled {1000 progress updates repaint only a few times; the last value is shown} -body {
	set ns ::scidb::test::progress
	set ${ns}::updates 0
	rename ::update ${ns}::realUpdate
	proc ::update {args} {
		if {![llength $args]} { incr ::scidb::test::progress::updates }
		tailcall ::scidb::test::progress::realUpdate {*}$args
	}
	try {
		set t0 [clock milliseconds]
		set rc [::progress::start .application [list ${ns}::Work] {} {-message Testing}]
		set ms [expr {[clock milliseconds] - $t0}]
	} finally {
		rename ::update {}
		rename ${ns}::realUpdate ::update
	}
	# one repaint per 50 ms of work, plus open/start/finish
	set limit [expr {$ms / 50 + 10}]
	list $rc [expr {[set ${ns}::updates] <= $limit}] $::progress::Priv(value)
} -result {done 1 1000}

tcltest::cleanupTests
