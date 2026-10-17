# ======================================================================
# Scidb App Test — Game Review: move classes and accuracy
# (tcl/game-review.tcl)
# ======================================================================
# The pure core (win probability, accuracy, classification, summaries) is
# tested against the documented formulas; the run path is driven with a
# stubbed engine (no real UCI, no network).
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::gamereview {}

# ----------------------------------------------------------------------
# Pure core: win probability and accuracy.
# ----------------------------------------------------------------------

tcltest::test gamereview-wp {win probability from centipawns and mate scores} -body {
	list \
		[::gamereview::wp 0] \
		[::gamereview::wp {#3}] \
		[::gamereview::wp {#-3}] \
		[::gamereview::wp 10000] \
		[::gamereview::wp -10000] \
		[format %.2f [::gamereview::wp 100]] \
		[format %.2f [::gamereview::wp -100]] \
		[::gamereview::wp {not-a-score}]
} -result {50.0 100.0 0.0 100.0 0.0 59.10 40.90 50.0}

tcltest::test gamereview-accuracy {move accuracy from a win-probability loss} -body {
	list \
		[format %.2f [::gamereview::accuracy 0]] \
		[format %.2f [::gamereview::accuracy 10]] \
		[format %.2f [::gamereview::accuracy 100]] \
		[format %.2f [::gamereview::accuracy -5]]
} -result {100.00 63.58 0.00 100.00}

tcltest::test gamereview-loss-classes {loss buckets and the best/not-best split} -body {
	# before/after are the mover's view; a loss under 2 with the engine's
	# best move is Best, without it Excellent, then the loss buckets.
	lmap {before after best} {0 0 1  0 0 0  0 -50 0  0 -100 0  0 -200 0  0 -500 0} {
		::gamereview::classFor [::gamereview::loss $before $after] $best
	}
} -result {Best Excellent Good Inaccuracy Mistake Blunder}

# ----------------------------------------------------------------------
# Classification of a synthetic sequence.
# ----------------------------------------------------------------------

tcltest::test gamereview-classify {a synthetic eval sequence classifies and counts} -body {
	set plies {
		{san e4   before 0 after 0     best 1}
		{san e5   before 0 after -200  best 0}
		{san Nf3  before 0 after -500  best 0}
		{san Nc6  before 0 after -50   best 0}
		{san Bc4  before 0 after 0     best 0}
		{san Nf6  before 0 after -100  best 0}
	}
	set r [::gamereview::classify $plies]
	set classes [lmap m [dict get $r moves] { dict get $m class }]
	set wc [dict get $r white counts]
	set bc [dict get $r black counts]
	list $classes \
		[dict get $r white n] [dict get $r black n] \
		[dict get $wc Best] [dict get $wc Excellent] [dict get $wc Blunder] \
		[dict get $bc Mistake] [dict get $bc Good] [dict get $bc Inaccuracy]
} -result {{Best Mistake Blunder Good Excellent Inaccuracy} 3 3 1 1 1 1 1 1}

tcltest::test gamereview-classify-carry {per-move dicts carry the input fields through} -body {
	set r [::gamereview::classify {
		{san e4 before 0 after 0 best 1 uci e2e4 bestMove e2e4 key m1}
		{san e5 before 0 after 0 best 1 uci e7e5 bestMove e7e5 key m2}
	}]
	set m0 [lindex [dict get $r moves] 0]
	set m1 [lindex [dict get $r moves] 1]
	list [dict get $m0 ply] [dict get $m0 side] [dict get $m0 key] \
		[dict get $m1 ply] [dict get $m1 side] [dict get $m1 key]
} -result {0 White m1 1 Black m2}

tcltest::test gamereview-mate {mate scores map to certainty and a mate is a blunder} -body {
	set r [::gamereview::classify {
		{san Qh5 before 0 after {#-3} best 0}
		{san hxg7 before {#3} after {#3} best 1}
	}]
	set classes [lmap m [dict get $r moves] { dict get $m class }]
	list $classes [format %.2f [dict get [lindex [dict get $r moves] 0] loss]]
} -result {{Blunder Best} 50.00}

# ----------------------------------------------------------------------
# The run path, with a stubbed engine.
# ----------------------------------------------------------------------

proc ::scidb::test::gamereview::stubEngine {results} {
	rename ::ai::engine::available ::scidb::test::gamereview::realAvailable
	rename ::ai::engine::classify ::scidb::test::gamereview::realClassify
	set ::scidb::test::gamereview::classifyResults $results
	set ::scidb::test::gamereview::classifyCalls 0
	proc ::ai::engine::available {} { return 1 }
	proc ::ai::engine::classify {fen san args} {
		incr ::scidb::test::gamereview::classifyCalls
		set r [lindex $::scidb::test::gamereview::classifyResults 0]
		if {[llength $::scidb::test::gamereview::classifyResults] > 1} {
			set ::scidb::test::gamereview::classifyResults \
				[lrange $::scidb::test::gamereview::classifyResults 1 end]
		}
		return $r
	}
}

proc ::scidb::test::gamereview::unstubEngine {} {
	catch { rename ::ai::engine::available {} }
	catch { rename ::ai::engine::classify {} }
	catch { rename ::scidb::test::gamereview::realAvailable ::ai::engine::available }
	catch { rename ::scidb::test::gamereview::realClassify ::ai::engine::classify }
}

tcltest::test gamereview-run {run analyses the mainline and reports classes} -setup {
	::menu::gameNew .application
	update
	foreach m {e4 e5 Nf3 Nc6} {
		::scidb::game::move $m
		::scidb::game::go 1
	}
	update
	# a per-ply engine answer: {evalBeforeCp evalAfterCp uci bestMove}
	::scidb::test::gamereview::stubEngine [list \
		[dict create evalBeforeCp 0 evalAfterCp 0    uci a bestMove a] \
		[dict create evalBeforeCp 0 evalAfterCp -300 uci b bestMove c] \
		[dict create evalBeforeCp 0 evalAfterCp 0    uci d bestMove d] \
		[dict create evalBeforeCp 0 evalAfterCp 0    uci e bestMove e]]
	set ::scidb::test::gamereview::doneFlag 0
	set ::scidb::test::gamereview::result {}
} -body {
	::gamereview::run .application -done \
		{apply {{r} {set ::scidb::test::gamereview::result $r; set ::scidb::test::gamereview::doneFlag 1}}}
	vwait ::scidb::test::gamereview::doneFlag
	set r $::scidb::test::gamereview::result
	set review [dict get $r review]
	set classes [lmap m [dict get $review moves] { dict get $m class }]
	set wc [dict get $review white counts]
	set bc [dict get $review black counts]
	list [dict get $r plies] [dict get $r cancelled] $classes \
		[dict get $wc Best] [dict get $bc Best] [dict get $bc Blunder] \
		$::scidb::test::gamereview::classifyCalls
} -cleanup {
	::scidb::test::gamereview::unstubEngine
	catch { destroy .application.__gamereview }
	catch { destroy .application.__gamereview_progress }
	unset -nocomplain ::scidb::test::gamereview::doneFlag ::scidb::test::gamereview::result
} -result {4 0 {Best Blunder Best Best} 2 1 1 4}

tcltest::test gamereview-nags {NAG symbols for the classes and mark merging} -body {
	list \
		[::gamereview::nagFor Inaccuracy] [::gamereview::nagFor Mistake] \
		[::gamereview::nagFor Blunder] [::gamereview::nagFor Best] \
		[::gamereview::mergeNags {$1 $2} {$6}] \
		[::gamereview::mergeNags {$2} {$2}] \
		[::gamereview::mergeNags {} {$4}]
} -result {{$6} {$2} {$4} {} {$1 $2 $6} {$2} {$4}}

tcltest::cleanupTests
