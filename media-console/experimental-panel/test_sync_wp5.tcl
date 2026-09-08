#!/usr/bin/env tclsh
# WP5 acceptance harness: sync v2 node-goal model (MEDIA_LESSON_V2_PLAN.md
# WP5). Sources only app-media-sync.tcl — the state machine is UI-free and
# runs against stub delegates.
#
# Gates:
#   - drive 12500 -> goto node 1; drive 50800 -> goto 88
#   - drive 94900 -> goto 44 as a REWIND: goto + annotation clear
#   - node goal 114 with a 40-node main line is NOT clamped (R6)
#   - same-node drive ticks fire no repeated gotos (R9, board side)
#   - a driving goto echoed back through step() registers no user touch
#     and triggers no Transport pause (R7)
#   - a manual step re-syncs lastgoal (R8)
#   - legacy bare-int timelines still clamp to the board length
# Exit 0 iff all gates pass.

package require Tcl 8.5

namespace eval ::util { proc source {args} {} }
set here [file dirname [file normalize [info script]]]
source [file join $here app-media-sync.tcl]

set fails 0
proc gate {name got want} {
	if {$got eq $want} {
		puts "  ok  $name"
	} else {
		puts "FAIL  $name\n      got:  $got\n      want: $want"
		incr ::fails
	}
}

# stub board: goto-model, "node" is a recorded integer; boardlength is
# deliberately 40 so a node goal of 114 proves no clamping (R6)
proc setup {} {
	::media::sync::set-config 1 1
	set ::gotos {}
	set ::calls {}
	set ::clears 0
	set ::node -1
	set ::ply 0
	::media::sync::configure \
		transport-cmd  {::apply {{what} {lappend ::calls $what}}} \
		boardgoto-cmd  {::apply {{node} {
			lappend ::gotos $node
			set ::node $node
		}}} \
		clearann-cmd   {::apply {{} {incr ::clears}}} \
		boardnode-cmd  {::apply {{} {return $::node}}} \
		boardlength-cmd {::apply {{} {return 40}}} \
		boardply-cmd   {::apply {{} {return $::ply}}} \
		boardforward-cmd {::apply {{} {incr ::ply}}}
	::media::sync::load-timeline {{12500 1} {50800 88} {76000 96} {94900 44}}
	::media::sync::load-events {}
	::media::sync::onPlaybackStarted
}

proc reset {} {
	::media::sync::set-config 1 0
	::media::sync::onPlaybackStopped
}

# 1. forward node goals jump directly
setup
::media::sync::drive 12500 100000
set g1 [llength $::gotos]
::media::sync::drive 50800 100000
gate "drive 12500 -> goto 1; drive 50800 -> goto 88" \
	[list $::gotos] {{1 88}}
gate "no BoardStart on forward gotos" [incr g1 -1] 0
reset

# 2. rewind = goto + clear annotations
setup
::media::sync::drive 50800 100000
::media::sync::drive 94900 100000
gate "drive 94900 -> rewind goto 44 + clear" [list $::gotos $::clears] {{88 44} 1}
reset

# 3. R6: node goal 114 is not clamped to the 40-node main line
setup
::media::sync::load-timeline {{12500 114}}
::media::sync::drive 12500 100000
gate "goto 114 unclamped (main line = 40)" [list $::gotos] 114
reset

# 4. R9: same-node ticks are no-ops
setup
::media::sync::drive 50800 100000
::media::sync::drive 50900 100000
::media::sync::drive 51000 100000
gate "same-node ticks fire one goto only" [list $::gotos] 88
reset

# 5. R7: a driving goto echoed through step() is not a user touch and
#    does not pause the transport
setup
::media::sync::configure boardgoto-cmd {::apply {{node}}}
# cannot use a proc body referencing locals: use a global command instead
proc ::wp5-goto {node} {
	lappend ::gotos $node
	set ::node $node
	::media::sync::step		;# board subscription echo during the drive
}
::media::sync::configure boardgoto-cmd ::wp5-goto
::media::sync::drive 50800 100000
gate "no Transport pause from the driving goto" [list $::calls] {{}}
# the touch-holdoff did not engage: the very next tick still drives
::media::sync::load-timeline {{50800 88} {76000 96}}
::media::sync::drive 76100 100000
gate "next tick drives normally (no holdoff)" [list $::gotos] {{88 96}}
reset

# 6. R8: a manual step re-syncs lastgoal to the current node
setup
::media::sync::drive 50800 100000
set ::node 12
::media::sync::step
gate "manual navigation re-syncs lastgoal" \
	[list $::media::sync::State(lastgoal)] 12
reset

# 7. legacy count model still clamps (compat with .plytimes sidecars):
#    6 bare marks, a 3-ply board -> goal clamps to 2 plies
setup
::media::sync::configure boardlength-cmd {::apply {{} {return 3}}}
::media::sync::load-timeline {100 200 300 400 500 600}
::media::sync::set-config 1 1
::media::sync::onPlaybackStarted
::media::sync::drive 5000 10000
gate "legacy count model clamps to board length (2 plies)" \
	[list $::ply] 2
reset

if {$fails} {
	puts "\nWP5: $fails gate(s) FAILED"
	exit 1
}
puts "\nWP5: all gates pass"
exit 0
