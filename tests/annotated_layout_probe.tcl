#!/usr/bin/env tkscidb
# Probe: import an annotated PGN into game slot 0, subscribe to the pgn
# layout stream, and dump the edit-node list the C++ core emits.


proc ::mylog {args} { puts "LOG: $args" }

# Boot the full application; game slots crash without it.
set probeDir [file dirname [file normalize [info script]]]
set argvSave $argv; set argv {}; set argc 0
source [file join $probeDir .. tcl chesswiz]
set argv $argvSave; set argc [llength $argv]

set probePgn {[Event "Annotation probe"]
[Site "?"]
[Date "2026.09.06"]
[Round "?"]
[White "Annotator"]
[Black "Tester"]
[Result "1-0"]

{Pre-game comment with [%csl Gd4,Re5] squares and [%cal Ge2e4] arrow.}
1. e4 $1 {Good start [%clk 0:05:00]} e5 $6 (1... c5 $5 {Sicilian
[%eval -0.30]} 2. Nf3 d6 (2... Nc6 3. d4 {deep} (3. Bb5 {deeper}
3... g6 (3... a6 $2)))) 2. Nf3 $14 $36 Nc6 3. Bb5 $220 a6
{[%emt 0:00:30] after think} 4. Ba4 Nf6 5. O-O $10 $13 1-0}

if {[catch { ::scidb::game::new 0 } msg]} { puts "NEW-ERR: $msg"; exit 1 }
if {[catch { ::scidb::game::import 0 $probePgn ::mylog {} -encoding utf-8 -variation 0 } msg]} {
	puts "IMPORT-ERR: $msg"; exit 1
}
puts "IMPORT-OK: $msg"

proc ::dumpNode {node depth} {
	set pad [string repeat {  } $depth]
	set type [lindex $node 0]
	switch -- $type {
		begin - end - move - header - languages - result - action -
		diagram - start - merge {
			puts "$pad$type: [lrange $node 1 end]"
			if {$type eq "move"} {
				foreach sub [lindex $node 2] { ::dumpNode $sub [expr {$depth+1}] }
			}
		}
		default { puts "$pad?$node" }
	}
}

proc ::capture {position data} {
	puts "== layout for position $position: [llength $data] nodes =="
	foreach node $data {
		if {[catch { ::dumpNode $node 0 } err]} { puts "RAW: $node ($err)" }
	}
}

if {[catch { ::scidb::game::subscribe pgn 0 ::capture } msg]} {
	puts "SUBSCRIBE-ERR: $msg"; exit 1
}
if {[catch { ::scidb::game::layout 0 } msg]} { puts "LAYOUT-ERR: $msg"; exit 1 }

catch { puts "MARKS-QUERY: [::scidb::game::query 0 marks]" }
catch { destroy .application }
catch { destroy . }
