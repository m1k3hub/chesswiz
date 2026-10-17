#!/usr/bin/env tclsh
# WP1 acceptance harness: sidecar-parse against the round-08 fixture.
# Gates (docs/MEDIA_LESSON_V2_PLAN.md WP1):
#   - exactly 380 events
#   - 99 gotos, cursors 1..114 (first 12 monotonic; then the
#     non-monotonic pattern incl. 44->88->96 and the ~94.9s rewind to 44)
#   - 108 board actions
#   - ms exact: goto 1 at 12500
#   - checkpoint census: 79 records, last = largest

set fixture "/media/michael-g-thomas/sas_mirror/fixt/cbm168/Festival Biel 2015.html/Biel 2015 round 08 MVL-Adams.txt"
source "/media/michael-g-thomas/sas_mirror/src/chess/scidb-code.codex/media-console/experimental-panel/app-media-decode.tcl"

set d [::media::decoder::sidecar-parse $fixture]
set counts [dict get $d counts]
puts "counts: $counts"

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

gate total-events [dict get $counts total] 380
gate gotos        [dict get $counts goto] 99
gate actions      [dict get $counts action] 108
gate syncs        [dict get $counts sync] 79
gate checkpoints  [dict get $counts checkpoint] 79
gate annotations  [dict get $counts annotation] 14

set gotos [dict get $d gotos]
set first [lindex $gotos 0]
gate goto1-ms     [lindex $first 0] 12500
gate goto1-cursor [lindex $first 1] 1

set cursors {}
foreach g $gotos { lappend cursors [lindex $g 1] }
set sorted [lsort -integer -unique $cursors]
gate cursor-min [lindex $sorted 0] 1
gate cursor-max [lindex $sorted end] 114

# first 12 monotonic
set mono 1
for {set i 1} {$i < 12} {incr i} {
	if {[lindex $cursors $i] <= [lindex $cursors [expr {$i-1}]]} { set mono 0 }
}
gate first-12-monotonic $mono 1

# rewind: a later goto with a smaller cursor than a previous max
set maxSeen 0
set rewinds 0
foreach c $cursors {
	if {$c < $maxSeen} { incr rewinds }
	if {$c > $maxSeen} { set maxSeen $c }
}
gate has-rewind [expr {$rewinds > 0}] 1

# rewind to 44 near 94.9s (find the first goto whose cursor drops to 44)
set rewMs 0
set prevMax 0
foreach g $gotos {
	lassign $g ms c
	if {$c < $prevMax && $c == 44} { set rewMs $ms; break }
	if {$c > $prevMax} { set prevMax $c }
}
puts "rewind-to-44 at ms=$rewMs ([expr {$rewMs/1000.0}]s)"
gate rewind-to-44 [expr {$rewMs > 90000 && $rewMs < 100000}] 1

# checkpoint census: last = largest
set cps [dict get $d checkpoints]
set last [lindex $cps end]
set maxSize 0
foreach c $cps {
	if {[lindex $c 1] > $maxSize} { set maxSize [lindex $c 1] }
}
gate last-checkpoint-is-largest [expr {[lindex $last 1] == $maxSize}] 1
puts "last checkpoint: ms=[lindex $last 0] size=[lindex $last 1] max=$maxSize"

if {$fails} { puts "\n$fails GATE(S) FAILED"; exit 1 }
puts "\nALL WP1 GATES PASSED"