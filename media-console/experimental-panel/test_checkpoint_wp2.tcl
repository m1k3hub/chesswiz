#!/usr/bin/env tclsh
# WP2 acceptance harness: checkpoint node-table decoder gates.
#
# Gates (docs/MEDIA_LESSON_V2_PLAN.md WP2, byte-verified on the round-08
# fixture, all 79 checkpoints):
#   1. parse-checkpoint consumes the node table completely:
#      walked edges == the u32le entry-count word (83 first snapshot,
#      87 last snapshot)
#   2. identity strings, table location and the header-tail signature
#      locate the table in every snapshot
#   3. the python-chess legality oracle passes on the first and last
#      snapshots (100% legal main-line walk = the real MVL-Adams score)
#
# The checkpoint hex files are produced from the sidecar fixture via
# ::media::decoder::sidecar-parse (WP1); no external dump needed.

set here [file dirname [file normalize [info script]]]
source [file join $here app-media-decode.tcl]

set fixture "/media/michael-g-thomas/sas_mirror/fixt/cbm168/Festival Biel 2015.html/Biel 2015 round 08 MVL-Adams.txt"
if {![file exists $fixture]} {
	puts "SKIP: fixture not found: $fixture"
	exit 0
}

set fails 0
proc gate {name got want} {
	global fails
	if {$got eq $want} {
		puts "PASS  $name = $got"
	} else {
		puts "FAIL  $name = $got (want $want)"
		incr fails
	}
}

set d [::media::decoder::sidecar-parse $fixture]
set cps [dict get $d checkpoints]
gate checkpoint-census [llength $cps] 79

# every snapshot: table located, identity parsed, edges == entry-count
set allOk 1
set i 0
foreach cp $cps {
	set dd [::media::decoder::parse-checkpoint [lindex $cp 2]]
	if {[dict exists $dd error]} { puts "  cp$i: ERROR [dict get $dd error]"; set allOk 0; break }
	if {[dict get $dd edgeCount] != [dict get $dd entryCount]} {
		puts "  cp$i: edges [dict get $dd edgeCount] != count word [dict get $dd entryCount]"
		set allOk 0
	}
	incr i
}
gate all-snapshots-table-consumed $allOk 1

# first and last snapshot: exact expectations (byte-verified)
set first [::media::decoder::parse-checkpoint [lindex [lindex $cps 0] 2]]
gate first-entryCount [dict get $first entryCount] 83
gate first-edges [dict get $first edgeCount] 83
gate first-white [dict get $first white_last] "Vachier-Lagrave"
gate first-event [dict get $first event] "48th Biel Festival 2015"
gate first-date1 [dict get $first date1] [list 2015 0 0]

set last [::media::decoder::parse-checkpoint [lindex [lindex $cps end] 2]]
gate last-entryCount [dict get $last entryCount] 87
gate last-edges [dict get $last edgeCount] 87
gate last-cursor [dict get $last cursor] 87

# GATE 1+2 legality via the python-chess oracle (first + last snapshot)
set fh [open /tmp/_wp2_first.hex w]; puts $fh [lindex [lindex $cps 0] 2]; close $fh
set fh [open /tmp/_wp2_last.hex w];  puts $fh [lindex [lindex $cps end] 2]; close $fh
foreach f {_wp2_first _wp2_last} {
	if {[catch {exec python3 [file join $here wp2_checkpoint_oracle.py] /tmp/$f.hex} out]} {
		puts "FAIL  oracle-$f: $out"
		incr fails
	} else {
		set pass1 [regexp {GATE 1 .* PASS} $out]
		set pass2 [regexp {GATE 2 .* PASS} $out]
		gate oracle-$f-gate1 $pass1 1
		gate oracle-$f-gate2 $pass2 1
	}
}

if {$fails} { puts "\n$fails GATE(S) FAILED"; exit 1 }
puts "\nALL WP2 GATES PASSED"