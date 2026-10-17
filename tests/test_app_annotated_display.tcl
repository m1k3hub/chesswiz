# ======================================================================
# Scidb App Test Suite - Annotated Game Display (layout pipeline audit)
# ======================================================================
# Phase 1 of docs/planning/annotated-game-display-plan.md: import
# adversarial annotated PGNs and assert on the edit-node layout stream
# the C++ core pushes to the PGN display (the same data DoLayout renders).

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::annotated {

variable testDir [file dirname [file normalize [info script]]]
variable slot 7
variable slotCreated 0
variable layout {}
variable importLog {}

source [file join $testDir corpus annotated_games.tcl]

proc Log {unused entry} {
	variable importLog
	lappend importLog $entry
}

proc Capture {position data} {
	variable layout $data
}

# Import a corpus game into the test slot and capture its layout.
proc loadGame {key} {
	variable slot
	variable slotCreated
	variable layout {}
	variable importLog {}
	if {!$slotCreated} {
		::scidb::game::new $slot
		set slotCreated 1
	}
	set rc [::scidb::game::import $slot \
		[set ::scidb::test::corpus::annotated($key)] \
		[namespace current]::Log {} -encoding utf-8 -variation 0]
	::scidb::game::subscribe pgn $slot [namespace current]::Capture
	::scidb::game::layout $slot
	::scidb::game::unsubscribe pgn $slot [namespace current]::Capture
	return $rc
}

proc importErrors {} {
	variable importLog
	set errs {}
	foreach entry $importLog {
		if {[lindex $entry 0] eq "error"} { lappend errs $entry }
	}
	return $errs
}

# Collect all move sub-nodes of a given type from the captured layout.
proc collect {type} {
	variable layout
	set found {}
	foreach node $layout {
		if {[lindex $node 0] ne "move"} { continue }
		foreach sub [lindex $node 2] {
			if {[lindex $sub 0] eq $type} { lappend found [lrange $sub 1 end] }
		}
	}
	return $found
}

proc topNodes {type} {
	variable layout
	set found {}
	foreach node $layout {
		if {[lindex $node 0] eq $type} { lappend found [lrange $node 1 end] }
	}
	return $found
}

proc allNagValues {} {
	set nags {}
	foreach ann [collect annotation] {
		foreach group $ann {
			foreach nag $group { lappend nags $nag }
		}
	}
	return $nags
}

tcltest::test annotated-import-01 {adversarial ChessBase-style game imports cleanly} -body {
	list [loadGame chessbase] [importErrors]
} -result {1 {}}

tcltest::test annotated-comments-02 {comments reach the layout with command tags stripped} -body {
	loadGame chessbase
	set texts {}
	foreach c [collect comment] { lappend texts [lindex $c 1] }
	set leak 0
	foreach t $texts {
		if {[string match {*\[%*} $t]} { set leak 1 }
	}
	list $leak \
		[expr {[lsearch -glob $texts {*Pre-game comment*}] >= 0}] \
		[expr {[lsearch -exact $texts {Good start}] >= 0}] \
		[expr {[lsearch -exact $texts {after think}] >= 0}]
} -result {0 1 1 1}

tcltest::test annotated-nags-03 {move and position NAGs survive with correct grouping} -body {
	loadGame chessbase
	set nags [allNagValues]
	set expected 1
	foreach want {{$1} {$6} {$5} {$2} {$14} {$36} {$10} {$13}} {
		if {[lsearch -exact $nags $want] < 0} { set expected 0 }
	}
	set expected
} -result 1

tcltest::test annotated-diagram-04 {ChessBase diagram NAG $220 maps to Scidb diagram NAG} -body {
	loadGame chessbase
	set nags [allNagValues]
	list [expr {[lsearch -exact $nags {$155}] >= 0}] \
		[expr {[lsearch -exact $nags {$220}] >= 0}]
} -result {1 0}

tcltest::test annotated-diagram-nag-export-04b {diagram NAG exports as $155 by default, $220/$221 opt-in} -body {
	variable slot
	loadGame chessbase
	set default [::scidb::game::toPGN original -position $slot]
	set chesspad [::scidb::game::toPGN original -position $slot -chesspad-diagram-nag 1]
	list [expr {[string first {$155} $default] >= 0}] \
		[expr {[string first {$220} $default] >= 0}] \
		[expr {[string first {$155} $chesspad] >= 0}] \
		[expr {[string first {$220} $chesspad] >= 0}]
} -result {1 0 0 1}

tcltest::test annotated-eval-parsing-04c {[%eval] extracts into structured, queryable move info with correct sign} -body {
	variable slot
	catch { ::scidb::game::new $slot }
	set pgn {[Event "e"]
[Site "?"]
[Date "2026.09.06"]
[Round "?"]
[White "A"]
[Black "B"]
[Result "1-0"]

1. e4 {[%eval 0.35]} e5 {[%eval -0.20]} 2. Nf3 Nc6 1-0}
	::scidb::game::import $slot $pgn {} {} -encoding utf-8 -variation 0
	set profile [::scidb::game::evalProfile $slot]
	set export [::scidb::game::toPGN original -position $slot -flags 9470975]
	list $profile \
		[expr {[string first {[%eval +0.35]} $export] >= 0}] \
		[expr {[string first {[%eval -0.20]} $export] >= 0}]
} -result {{{1 0.35} {2 -0.20}} 1 1}

tcltest::test annotated-eval-comment-stripped-04d {[%eval] tag does not leak into displayed comment text} -body {
	variable slot
	catch { ::scidb::game::new $slot }
	set pgn {[Event "e"]
[Site "?"]
[Date "2026.09.06"]
[Round "?"]
[White "A"]
[Black "B"]
[Result "1-0"]

1. e4 {A real comment. [%eval 0.35]} e5 1-0}
	variable layout {}
	::scidb::game::import $slot $pgn {} {} -encoding utf-8 -variation 0
	::scidb::game::subscribe pgn $slot [namespace current]::Capture
	::scidb::game::layout $slot
	::scidb::game::unsubscribe pgn $slot [namespace current]::Capture
	set texts {}
	foreach c [collect comment] { lappend texts [lindex $c 1] }
	list [expr {[lsearch -glob $texts {*A real comment*}] >= 0}] \
		[expr {[lsearch -glob $texts {*%eval*}] >= 0}]
} -result {1 0}

tcltest::test annotated-marks-05 {csl/cal command tags become board marks} -body {
	variable slot
	loadGame chessbase
	set marks [::scidb::game::query $slot marks]
	list [expr {[lsearch -glob $marks {*full,d4*green*}] >= 0}] \
		[expr {[lsearch -glob $marks {*full,e5*red*}] >= 0}] \
		[expr {[lsearch -glob $marks {*arrow,e2,e4*green*}] >= 0}]
} -result {1 1 1}

tcltest::test annotated-variations-06 {nested variations are balanced and reach depth 4} -body {
	variable layout
	loadGame chessbase
	set begins 0; set ends 0; set maxLevel 0
	foreach node $layout {
		switch -- [lindex $node 0] {
			begin {
				incr begins
				set level [lindex $node 3]
				if {$level > $maxLevel} { set maxLevel $level }
			}
			end { incr ends }
		}
	}
	list [expr {$begins == $ends}] $maxLevel
} -result {1 4}

tcltest::test annotated-result-07 {game result reaches the layout} -body {
	loadGame chessbase
	lindex [topNodes result] 0 0
} -result 1-0

tcltest::test annotated-scid-marks-08 {Scid-native draw/mark syntax becomes position-scoped marks} -body {
	variable slot
	set rc [loadGame scid]
	# marks are scoped to the annotated position: none at the start,
	# visible once the cursor reaches the move carrying the comment
	set atStart [::scidb::game::query $slot marks]
	::scidb::game::moveto $slot m-0.1
	set atD4 [::scidb::game::query $slot marks]
	::scidb::game::moveto $slot m-0.3
	set atC4 [::scidb::game::query $slot marks]
	set texts {}
	foreach c [collect comment] { lappend texts [lindex $c 1] }
	set leak 0
	foreach t $texts {
		if {[string match {*\[%*} $t]} { set leak 1 }
	}
	list $rc [llength $atStart] \
		[expr {[lsearch -glob $atD4 {*full,d4*green*}] >= 0}] \
		[expr {[lsearch -glob $atD4 {*arrow,d1,d4*red*}] >= 0}] \
		[expr {[lsearch -glob $atC4 {*full,c4*}] >= 0}] \
		$leak
} -result {1 0 1 1 1 0}

tcltest::test annotated-unicode-09 {multibyte comments and 7-NAG pile-up survive} -body {
	loadGame unicode
	set texts {}
	foreach c [collect comment] { lappend texts [lindex $c 1] }
	set nags [allNagValues]
	set pileup 1
	foreach want {{$1} {$14} {$36} {$40} {$44} {$132} {$140}} {
		if {[lsearch -exact $nags $want] < 0} { set pileup 0 }
	}
	list [expr {[lsearch -glob $texts {*Многоязычный*中文注释*♞♛*}] >= 0}] \
		$pileup \
		[expr {[lsearch -exact $nags {$22}] >= 0}]
} -result {1 1 1}

tcltest::test annotated-corpus-10 {corpus round-trips as a PGN file on disk} -body {
	variable testDir
	set path [file join $testDir tmp-app annotated_corpus_[pid].pgn]
	file mkdir [file dirname $path]
	::scidb::test::corpus::writeCorpusPgn $path
	set chan [open $path r]
	fconfigure $chan -encoding utf-8
	set content [read $chan]
	close $chan
	file delete $path
	list [expr {[string match {*$220*} $content]}] \
		[expr {[string first "Многоязычный" $content] >= 0}]
} -result {1 1}

tcltest::cleanupTests

} ;# namespace ::scidb::test::annotated
