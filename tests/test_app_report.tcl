# ======================================================================
# Scidb App Test — HTML report stack (phase 2 render layer)
# ======================================================================
# Locks the ::scidb::db::guidingText / ::scidb::db::gameAnchor command
# contracts and the ::application::report viewer API (tcl/app-report.tcl)
# so a rename on either side cannot silently kill the report feature.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::appreport {}

tcltest::test report-guidingtext-command-exists {::scidb::db::guidingText is registered} -body {
	llength [info commands ::scidb::db::guidingText]
} -result 1

tcltest::test report-gameanchor-command-exists {::scidb::db::gameAnchor exists} -body {
	llength [info commands ::scidb::db::gameAnchor]
} -result 1

tcltest::test report-viewer-namespace-exists {::application::report::show is the entry point} -body {
	expr { [llength [info commands ::application::report::show]]
	     && [llength [info commands ::application::report::Load]]
	     && [llength [info commands ::application::report::LinkClick]] }
} -result 1

tcltest::test report-guidingtext-bad-index {guidingText rejects a negative game index} -body {
	set rc [catch { ::scidb::db::guidingText [::scidb::db::get clipbase name] Normal -1 } msg]
	expr { $rc == 1 }
} -result 1

tcltest::test report-guidingtext-nonreport-index {guidingText returns isGuiding=0 for out-of-range} -body {
	set data [::scidb::db::guidingText [::scidb::db::get clipbase name] Normal 999999]
	list [dict get $data isGuiding] [dict get $data html]
} -result {0 {}}

tcltest::test report-gameanchor-out-of-range {gameAnchor returns -1 for garbage args} -body {
	::scidb::db::gameAnchor [::scidb::db::get clipbase name] Normal \
		{Nobody,First,Nobody2,Second,NoEvent,NoSite,0,0}
} -result -1

tcltest::test report-viewer-image-fallback {Image returns {} for missing files} -body {
	llength [::application::report::Image /nonexistent/file.jpg]
} -result 0

# ---------------------------------------------------------------------
# Lesson sidecar persistence (::media::lesson sidecarPath/persist/load)
# ---------------------------------------------------------------------

namespace eval ::scidb::test::appreport::lesson {
	variable tmpDir {}
	variable video {}
	variable key {}
}

proc ::scidb::test::appreport::lesson::setup {} {
	variable tmpDir
	variable video
	variable key
	if {![string length $tmpDir]} {
		set tmpDir [file normalize [file join [file dirname [info script]] tmp-lesson]]
	}
	file mkdir $tmpDir
	set video [file join $tmpDir "fake-video-[pid].wmv"]
	set fh [open $video w]
	puts $fh "not a real video"
	close $fh
	# age the video so a freshly written sidecar counts as fresh
	file mtime $video [expr {[clock seconds] - 3600}]
	set key [::media::lesson::key $video]
	# start clean: no cache entry, no sidecar
	catch { unset ::media::lesson::Cache($key) }
	set p [::media::lesson::sidecarPath $video]
	file delete -force $p
	return $video
}

proc ::scidb::test::appreport::lesson::teardown {} {
	variable tmpDir
	variable video
	variable key
	if {[info exists video] && [string length $video]} {
		catch { ::media::lesson::flush $video }
	}
	if {[info exists tmpDir] && [file isdirectory $tmpDir]} {
		catch { file delete -force $tmpDir }
	}
	catch { unset video }
}

proc ::scidb::test::appreport::lesson::sampleLesson {video} {
	set k [::media::lesson::key $video]
	return [dict create \
		valid 1 \
		reason {} \
		video $k \
		timeline {{1000 1} {2000 2}} \
		events {{1500 arrow e2 e4 good {}}} \
		source sidecar-test]
}

tcltest::test report-lesson-sidecar-path {sidecarPath is deterministic, normalized, slash-free in the name part, ends with .lesson} -setup {
	::scidb::test::appreport::lesson::setup
} -cleanup {
	::scidb::test::appreport::lesson::teardown
} -body {
	set v $::scidb::test::appreport::lesson::video
	set p1 [::media::lesson::sidecarPath $v]
	set p2 [::media::lesson::sidecarPath $v]
	set alt [file dirname $v]/./[file tail $v]
	set p3 [::media::lesson::sidecarPath $alt]
	set other [file join [file dirname $v] other.wmv]
	list \
		[expr {$p1 eq $p2}] \
		[expr {$p1 eq $p3}] \
		[expr {[string match *.lesson $p1]}] \
		[expr {[string first / [file tail $p1]] == -1}] \
		[expr {[string first "/" [string map {/ X} [file tail $p1]]] == -1}] \
		[expr {[string length [file tail $p1]] > 0 && [string first "_media_" [file tail $p1]] >= 0}] \
		[expr {[::media::lesson::sidecarPath [file join [file dirname $v] zzz.wmv]] ne $p1}]
} -result {1 1 1 1 1 1 1}

tcltest::test report-lesson-sidecar-roundtrip {persist + loadFromSidecar round-trips a valid lesson and populates the cache} -setup {
	::scidb::test::appreport::lesson::setup
} -cleanup {
	::scidb::test::appreport::lesson::teardown
} -body {
	set v $::scidb::test::appreport::lesson::video
	set k $::scidb::test::appreport::lesson::key
	set lesson [::scidb::test::appreport::lesson::sampleLesson $v]

	set persisted [::media::lesson::persist $v $lesson]
	set loaded [::media::lesson::loadFromSidecar $v]

	# cache is populated by the load
	set cached [expr {[info exists ::media::lesson::Cache($k)]}]

	# and get() returns the sidecar content without a decode
	catch { unset ::media::lesson::Cache($k) }
	set got [::media::lesson::get $v]

	list \
		$persisted \
		[expr {[dict size $loaded] > 0}] \
		[expr {[dict get $loaded valid] == 1}] \
		[expr {[dict get $loaded video] eq $k}] \
		[expr {[dict get $loaded timeline] eq {{1000 1} {2000 2}}}] \
		[expr {[dict get $loaded source] eq "sidecar-test"}] \
		$cached \
		[expr {[dict get $got valid] == 1}]
} -result {1 1 1 1 1 1 1 1}

tcltest::test report-lesson-sidecar-invalidated-by-newer-video {a newer video mtime invalidates the sidecar} -setup {
	::scidb::test::appreport::lesson::setup
} -cleanup {
	::scidb::test::appreport::lesson::teardown
} -body {
	set v $::scidb::test::appreport::lesson::video
	set k $::scidb::test::appreport::lesson::key
	set lesson [::scidb::test::appreport::lesson::sampleLesson $v]
	::media::lesson::persist $v $lesson

	# sanity: load works before the video changes
	set before [::media::lesson::loadFromSidecar $v]

	# touch the video to clearly AFTER the sidecar's mtime (mtime
	# granularity is whole seconds: same-second updates are not stale)
	file mtime $v [expr {[file mtime [::media::lesson::sidecarPath $v]] + 120}]

	set after [::media::lesson::loadFromSidecar $v]
	list \
		[expr {[dict size $before] > 0}] \
		[string length $after]
} -result {1 0}

tcltest::test report-lesson-sidecar-invalid-not-persisted {invalid lessons are never persisted} -setup {
	::scidb::test::appreport::lesson::setup
} -cleanup {
	::scidb::test::appreport::lesson::teardown
} -body {
	set v $::scidb::test::appreport::lesson::video
	set bad [dict create valid 0 reason "decode failed" video [::media::lesson::key $v] timeline {} events {}]

	set persisted [::media::lesson::persist $v $bad]
	set path [::media::lesson::sidecarPath $v]
	set exists [file exists $path]
	# and load returns nothing
	set loaded [::media::lesson::loadFromSidecar $v]
	list $persisted $exists [string length $loaded]
} -result {0 0 0}

tcltest::test report-lesson-flush-removes-sidecar {flush deletes the in-memory cache AND the sidecar} -setup {
	::scidb::test::appreport::lesson::setup
} -cleanup {
	::scidb::test::appreport::lesson::teardown
} -body {
	set v $::scidb::test::appreport::lesson::video
	set k $::scidb::test::appreport::lesson::key
	set lesson [::scidb::test::appreport::lesson::sampleLesson $v]
	::media::lesson::persist $v $lesson
	set path [::media::lesson::sidecarPath $v]
	set existed [file exists $path]
	::media::lesson::flush $v
	list \
		$existed \
		[expr {![file exists $path]}] \
		[expr {![info exists ::media::lesson::Cache($k)]}]
} -result {1 1 1}

# ----------------------------------------------------------------------

::tcltest::cleanupTests
return