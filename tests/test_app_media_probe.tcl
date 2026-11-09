# ======================================================================
# Scidb App Test — background ffprobe for lesson prebuild
# (tcl/app-media-decode.tcl probeAsync; review findings NET-04/UI-06).
# A fake ffprobe on PATH stands in for the real one.
# ======================================================================

package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

namespace eval ::scidb::test::probe {
	variable dir [file join $::env(HOME) fake-ffprobe]
	variable savedPath $::env(PATH)
	variable result {}
	variable ticks 0
}

# <behaviour>: slow (answers after 1.5 s) or hang (never answers)
proc ::scidb::test::probe::Fake {behaviour} {
	variable dir
	variable savedPath
	file mkdir $dir
	set f [open [file join $dir ffprobe] w]
	puts $f "#!/bin/sh"
	puts $f "echo \$\$ > [file join $dir pid]"
	if {$behaviour eq "slow"} {
		puts $f "sleep 1.5"
		puts $f {echo '{"packets": []}'}
	} else {
		puts $f "exec sleep 600"
	}
	close $f
	file attributes [file join $dir ffprobe] -permissions 0755
	set ::env(PATH) "$dir:$savedPath"
}

proc ::scidb::test::probe::Done {ok} {
	variable result
	lappend result $ok
}

proc ::scidb::test::probe::Read {name} {
	variable dir
	set f [open [file join $dir $name]]
	set s [read $f]
	close $f
	return $s
}

proc ::scidb::test::probe::Tick {} {
	variable ticks
	incr ticks
	if {$ticks < 100} { after 50 ::scidb::test::probe::Tick }
}

tcltest::test media-probe-async {the GUI keeps running during ffprobe; decode reuses its output} -setup {
	::scidb::test::probe::Fake slow
	set ::scidb::test::probe::result {}
	set ::scidb::test::probe::ticks 0
} -body {
	set t0 [clock milliseconds]
	::media::decoder::probeAsync /tmp/lesson.wmv ::scidb::test::probe::Done
	set returned [expr {[clock milliseconds] - $t0 < 500}]
	after 50 ::scidb::test::probe::Tick
	::scidb::test::wait::until {[llength $::scidb::test::probe::result]} 10000
	set kept [info exists ::media::decoder::Probed([file normalize /tmp/lesson.wmv])]
	# decode must not start ffprobe again: make a second run fail loudly
	file delete [file join $::scidb::test::probe::dir ffprobe]
	set decoded [::media::decoder::decode /tmp/lesson.wmv]
	list $returned $::scidb::test::probe::result [expr {$::scidb::test::probe::ticks >= 10}] \
		$kept $decoded [info exists ::media::decoder::Probed([file normalize /tmp/lesson.wmv])]
} -cleanup {
	set ::env(PATH) $::scidb::test::probe::savedPath
} -result {1 1 1 1 {} 0}

tcltest::test media-probe-deadline {a hung ffprobe is killed at the deadline and reported as failed} -setup {
	::scidb::test::probe::Fake hang
	set ::scidb::test::probe::result {}
	set saved $::media::decoder::ProbeTimeout
	set ::media::decoder::ProbeTimeout 1000
} -body {
	::media::decoder::probeAsync /tmp/stuck.wmv ::scidb::test::probe::Done
	::scidb::test::wait::until {[llength $::scidb::test::probe::result]} 10000
	set pid [string trim [::scidb::test::probe::Read pid]]
	after 200
	list $::scidb::test::probe::result [file exists /proc/$pid] \
		[info exists ::media::decoder::Probed([file normalize /tmp/stuck.wmv])]
} -cleanup {
	set ::media::decoder::ProbeTimeout $saved
	set ::env(PATH) $::scidb::test::probe::savedPath
} -result {0 0 0}

tcltest::test media-probe-cancel {a new probe cancels the running one, which reports 0} -setup {
	::scidb::test::probe::Fake hang
	set ::scidb::test::probe::result {}
} -body {
	::media::decoder::probeAsync /tmp/a.wmv ::scidb::test::probe::Done
	::media::decoder::probeCancel
	::scidb::test::wait::until {[llength $::scidb::test::probe::result]} 3000
	list $::scidb::test::probe::result $::media::decoder::Probe(chan)
} -cleanup {
	set ::env(PATH) $::scidb::test::probe::savedPath
	file delete -force $::scidb::test::probe::dir
} -result {0 {}}

tcltest::cleanupTests
