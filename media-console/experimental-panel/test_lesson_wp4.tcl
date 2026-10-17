#!/usr/bin/env tclsh
# WP4 acceptance harness: ::media::lesson v2 against the round-08
# fixture (docs/MEDIA_LESSON_V2_PLAN.md WP4).
#
# Gates:
#   - lesson::get on round 08: valid=1, source=sidecar
#   - >= 99 timeline pairs {ms nodeIndex}, ascending by ms
#   - positions: per-node FEN list, index 0 = start; >= 114 is the
#     plan's gate — the walkable tree provides 88 (the remaining
#     off-mainline nodes live in patch slots whose per-slot semantics
#     are open, see docs/CHESSBASE_MEDIA_RE.md); reported honestly below.
#   - events: {ms arrow from to class modifier} shape, algebraic squares
#   - cache stable (second get identical); persisted lesson round-trips
#   - invalid video: valid=0 + reason
# Exit 0 iff all gates pass (the >=114 positions gate is reported as a
# documented failure and fails the exit code, per the honest-gate rule).

set fixture "/media/michael-g-thomas/sas_mirror/fixt/cbm168/Festival Biel 2015.html/Biel 2015 round 08 MVL-Adams.wmv"

# fresh user dir: no persisted lessons interfere with the build path
namespace eval ::scidb::dir {}
set ::scidb::dir::user [file join /tmp wp4test [pid]]
file mkdir $::scidb::dir::user

set here [file dirname [file normalize [info script]]]
source [file join $here app-media-decode.tcl]
source [file join $here app-media-lesson.tcl]

set fails 0
proc gate {name got want} {
	global fails
	if {$got == $want} {
		puts "PASS  $name = $got"
	} else {
		puts "FAIL  $name = $got (want $want)"
		incr fails
	}
}

set lesson [::media::lesson::get $fixture]
gate valid [dict get $lesson valid] 1
gate source [dict get $lesson source] sidecar
gate timeline-pairs [llength [dict get $lesson timeline]] 99
set positions [dict get $lesson positions]
gate positions-gte-114 [expr {[llength $positions] >= 114}] 1
puts "      (positions = [llength $positions]: the walkable main-line tree; \
the 51 off-mainline nodes are patch slots with open semantics - \
see docs/CHESSBASE_MEDIA_RE.md; gotos beyond the tree are a WP5 concern)"

# timeline ascending
set asc 1
set prev -1
foreach p [dict get $lesson timeline] {
	set ms [lindex $p 0]
	if {$ms < $prev} { set asc 0 }
	set prev $ms
}
gate timeline-ascending $asc 1

# events shape {ms arrow from to class modifier}, algebraic squares
set evOk 1
set n 0
foreach e [dict get $lesson events] {
	incr n
	if {[llength $e] != 6} { set evOk 0; break }
	if {[lindex $e 1] ne "arrow"} { set evOk 0; break }
	if {![regexp {^[a-h][1-8]$} [lindex $e 2]]} { set evOk 0; break }
	if {![regexp {^[a-h][1-8]$} [lindex $e 3]]} { set evOk 0; break }
}
gate events-shape $evOk 1
puts "      ($n board-action events)"

# fields exist
foreach f {edges positions nodeTimes cursor} {
	if {![dict exists $lesson $f]} { gate field-$f 0 1 }
}
if {[dict exists $lesson edges] && [dict exists $lesson positions] \
	&& [dict exists $lesson nodeTimes]} {
	gate fields-present 1 1
	gate edges-count [llength [dict get $lesson edges]] 87
	gate nodeTimes-count [llength [dict get $lesson nodeTimes]] 0
}

# cache stable
set lesson2 [::media::lesson::get $fixture]
gate cache-stable [string equal $lesson $lesson2] 1

# persist round-trip: drop the in-memory cache, get again (loads the
# persisted lesson sidecar), compare the dict
::media::lesson::flush $fixture
set lesson3 [::media::lesson::get $fixture]
gate persist-roundtrip [string equal $lesson $lesson3] 1

# invalid path
set bad [::media::lesson::get "/nonexistent/video.wmv"]
gate invalid-valid [dict get $bad valid] 0
gate invalid-reason [expr {[string length [dict get $bad reason]] > 0}] 1
puts "      (reason: [dict get $bad reason])"

if {$fails} { puts "\n$fails WP4 GATE(S) FAILED"; exit 1 }
puts "\nALL WP4 GATES PASSED"