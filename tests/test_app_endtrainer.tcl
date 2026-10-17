# ======================================================================
# Scidb App Test -- endgame trainer (tcl/endgame-trainer.tcl)
# ======================================================================
# The tablebase is stubbed through ::application::download::Get (no
# network); the engine is never started. The session tests drive the
# trainer on the board the way a drag would.
# ======================================================================

package require tcltest 2.5
package require json

namespace eval ::scidb::test::et {
	variable Dir [file join [file dirname [file normalize [info script]]] tmp-app et_[pid]]
	variable savedHome {}
}

# The 4-field position key out of a tablebase URL.
proc ::scidb::test::et::keyFromUrl {url} {
	set enc [lindex [split $url "="] end]
	set fen [string map {_ " "} $enc]
	return [join [lrange $fen 0 3] " "]
}

# ::application::download::Get replaced by a per-position tablebase answer
# (unmatched positions answer a draw).  An answer is a JSON string.
proc ::scidb::test::et::stubTablebase {answers} {
	rename ::application::download::Get ::scidb::test::et::realGet
	set ::scidb::test::et::answers $answers
	proc ::application::download::Get {url done} {
		set key [::scidb::test::et::keyFromUrl $url]
		set data {{"category":"draw","moves":[]}}
		if {[dict exists $::scidb::test::et::answers $key]} {
			set data [dict get $::scidb::test::et::answers $key]
		}
		after 0 [list {*}$done [list ok 1 data $data code 200]]
	}
}

proc ::scidb::test::et::unstubTablebase {} {
	if {[llength [info commands ::scidb::test::et::realGet]]} {
		catch { rename ::application::download::Get {} }
		catch { rename ::scidb::test::et::realGet ::application::download::Get }
	}
}

# One event-loop turn (enough for the after-0 probe and engine reply).
proc ::scidb::test::et::pump {{ms 200}} {
	set ::scidb::test::et::pumpFlag 0
	after $ms {set ::scidb::test::et::pumpFlag 1}
	vwait ::scidb::test::et::pumpFlag
}

# A scratch Scidb home (the progress file lives under it).
proc ::scidb::test::et::setHome {} {
	set ::scidb::test::et::savedHome $::scidb::dir::home
	file mkdir $::scidb::test::et::Dir
	set ::scidb::dir::home $::scidb::test::et::Dir
}

proc ::scidb::test::et::restoreHome {} {
	if {$::scidb::test::et::savedHome ne ""} {
		set ::scidb::dir::home $::scidb::test::et::savedHome
	}
}

proc ::scidb::test::et::cleanupDir {} {
	catch { file delete -force $::scidb::test::et::Dir }
}

# End the running session and free its game slot (max 9 games).
proc ::scidb::test::et::release {} {
	set pos $::endtrainer::Priv(pos)
	catch { ::endtrainer::Finish }
	catch { ::endtrainer::Close }
	if {$pos ne "" && $pos != 0} {
		catch { ::application::pgn::release $pos }
		catch { ::game::release $pos }
	}
	::scidb::test::et::unstubTablebase
}

# A fresh Normal scratch game, making room first if every game slot is taken
# (the suite runs all its files in one process).  Returns its position.
proc ::scidb::test::et::freshGame {} {
	set before [::scidb::game::current]
	::menu::gameNew .application
	if {[::scidb::game::current] eq $before} {
		# the slots are full: free the current game and open one again
		catch { ::application::pgn::release $before }
		catch { ::game::release $before }
		::menu::gameNew .application
	}
	return [::scidb::game::current]
}

# ----------------------------------------------------------------------
# The catalog
# ----------------------------------------------------------------------

tcltest::test endtrainer-catalog {the built-in endings are well formed} -body {
	set ids {}
	set counts {}
	set bad {}
	foreach theme [::endtrainer::Themes] {
		foreach e [::endtrainer::Endings [lindex $theme 0]] {
			lappend ids [dict get $e id]
			set positions [dict get $e positions]
			lappend counts [llength $positions]
			set goal [dict get $e goal]
			foreach p $positions {
				lassign $p fen verdict
				if {$goal eq "win" && $verdict ne "win"} { lappend bad [list [dict get $e id] $fen $verdict] }
				if {$goal eq "draw" && $verdict ne "draw"} { lappend bad [list [dict get $e id] $fen $verdict] }
			}
		}
	}
	set span [expr {[llength $counts] && [lindex [lsort -integer $counts] 0] >= 3 \
		&& [lindex [lsort -integer $counts] end] <= 5}]
	list [llength [::endtrainer::Themes]] [llength $ids] [llength [lsort -unique $ids]] $span $bad
} -result {4 10 10 1 {}}

tcltest::test endtrainer-fens {every built-in FEN parses and is legal} -setup {
	set ::scidb::test::et::fensGame [::scidb::test::et::freshGame]
} -body {
	set bad {}
	foreach theme [::endtrainer::Themes] {
		foreach e [::endtrainer::Endings [lindex $theme 0]] {
			foreach p [dict get $e positions] {
				lassign $p fen verdict
				if {[catch { ::scidb::pos::setup $fen; set got [::scidb::pos::fen] } err]} {
					lappend bad [list $fen $err]
				} elseif {$got ne $fen} {
					lappend bad [list $fen $got]
				}
			}
		}
	}
	set bad
} -cleanup {
	catch { ::application::pgn::release $::scidb::test::et::fensGame }
	catch { ::game::release $::scidb::test::et::fensGame }
} -result {}

# ----------------------------------------------------------------------
# Pure helpers
# ----------------------------------------------------------------------

tcltest::test endtrainer-verdict {categories map to a side-to-move verdict} -body {
	list \
		[::endtrainer::VerdictOf [dict create category win]] \
		[::endtrainer::VerdictOf [dict create category loss]] \
		[::endtrainer::VerdictOf [dict create category draw]] \
		[::endtrainer::VerdictOf [dict create category cursed-win]] \
		[::endtrainer::VerdictOf [dict create category blessed-loss]] \
		[::endtrainer::VerdictOf ""] \
		[::endtrainer::VerdictOf [dict create checkmate true]] \
		[::endtrainer::VerdictOf [dict create stalemate true]]
} -result {win loss draw draw draw {} loss draw}

tcltest::test endtrainer-fault {a move that changes the result is flagged} -body {
	list \
		[::endtrainer::MoveFault win loss] \
		[::endtrainer::MoveFault win draw] \
		[::endtrainer::MoveFault win win] \
		[::endtrainer::MoveFault draw draw] \
		[::endtrainer::MoveFault draw loss] \
		[::endtrainer::MoveFault draw win] \
		[::endtrainer::MoveFault win ""] \
		[::endtrainer::FaultText letWinSlip] \
		[::endtrainer::FaultText letDrawSlip] \
		[::endtrainer::FaultText nowLosing]
} -result {{} letWinSlip nowLosing {} {} letDrawSlip {} {This move lets the win slip.} {This move lets the draw slip.} {This move loses the position.}}

tcltest::test endtrainer-bestmove {the engine prefers the tablebase-best defence} -body {
	set withDraw [::json::json2dict {{"category":"loss","moves":[
		{"san":"Kd4","category":"win","dtm":8},
		{"san":"Ke6","category":"win","dtm":20},
		{"san":"Kd5","category":"draw","dtm":0}]}}]
	set lost [::json::json2dict {{"category":"loss","moves":[
		{"san":"Kd4","category":"win","dtm":8},
		{"san":"Ke6","category":"win","dtm":20}]}}]
	set winning [::json::json2dict {{"category":"win","moves":[
		{"san":"Qa8","category":"loss","dtm":-3},
		{"san":"Qb6","category":"loss","dtm":-11}]}}]
	list \
		[::endtrainer::BestMoveSan $withDraw] \
		[::endtrainer::BestMoveSan $lost] \
		[::endtrainer::BestMoveSan $winning] \
		[::endtrainer::BestMoveSan [dict create moves {}]] \
		[::endtrainer::BestMoveSan ""]
} -result {Kd5 Ke6 Qa8 {} {}}

tcltest::test endtrainer-progress {progress round-trips through the file} -setup {
	::scidb::test::et::setHome
} -body {
	set e1 [::endtrainer::RecordResult kqk 1]
	set e2 [::endtrainer::RecordResult kqk 0]
	set e3 [::endtrainer::RecordResult krk 1]
	set reloaded [::endtrainer::LoadProgress]
	set missing [::endtrainer::LoadProgress [file join $::scidb::dir::home training nope.dat]]
	list $e1 $e2 $e3 [dict get $reloaded kqk] [dict get $reloaded krk] \
		[llength $missing] [file exists [::endtrainer::ProgressPath]]
} -cleanup {
	::scidb::test::et::restoreHome
	::scidb::test::et::cleanupDir
} -result {{attempts 1 done 1} {attempts 2 done 1} {attempts 1 done 1} {attempts 2 done 1} {attempts 1 done 1} 0 1}

# ----------------------------------------------------------------------
# A session on the board
# ----------------------------------------------------------------------

tcltest::test endtrainer-engine-reply {the engine plays the tablebase-best defence} -setup {
	::scidb::test::et::setHome
	::scidb::test::et::stubTablebase [dict create \
		"8/8/8/4k3/8/8/5Q2/4K3 b - -" {{"category":"loss","moves":[
			{"san":"Kd5","category":"win","dtm":16},
			{"san":"Ke4","category":"win","dtm":24},
			{"san":"Ke6","category":"win","dtm":8}]}}]
} -body {
	set started [::endtrainer::Start kqk]
	set ok [::endtrainer::UserMove Qf2]
	::scidb::test::et::pump 250
	set pgn [::scidb::game::toPGN modified -position [::scidb::game::current]]
	list $started $ok \
		[::scidb::game::query length] \
		[expr {[string first {Ke4} $pgn] >= 0}] \
		$::endtrainer::Priv(phase) \
		[::scidb::pos::stm]
} -cleanup {
	::scidb::test::et::release
	::scidb::test::et::restoreHome
	::scidb::test::et::cleanupDir
} -result {1 1 2 1 user w}

tcltest::test endtrainer-fault-retry {a move that lets the win slip is flagged and Retry takes it back} -setup {
	::scidb::test::et::setHome
	::scidb::test::et::stubTablebase [dict create \
		"8/8/8/4kQ2/8/8/8/4K3 b - -" {{"category":"draw","moves":[]}}]
} -body {
	::endtrainer::Start kqk
	set ok [::endtrainer::UserMove Qf5+]
	::scidb::test::et::pump 150
	set fault $::endtrainer::Priv(fault)
	set message $::endtrainer::Priv(status)
	set pliesBefore [::scidb::game::query length]
	::endtrainer::Retry
	list $ok $fault [string match {*lets the win slip*} $message] $pliesBefore \
		[::scidb::game::query length] $::endtrainer::Priv(phase)
} -cleanup {
	::scidb::test::et::release
	::scidb::test::et::restoreHome
	::scidb::test::et::cleanupDir
} -result {1 letWinSlip 1 1 0 user}

tcltest::test endtrainer-mate {mate reaches the goal and is recorded} -setup {
	::scidb::test::et::setHome
} -body {
	::endtrainer::Start kqk
	::scidb::pos::setup {7k/Q7/6K1/8/8/8/8/8 w - - 0 1}
	set ok [::endtrainer::UserMove Qb8#]
	::scidb::test::et::pump 100
	set progress [::endtrainer::LoadProgress]
	list $ok $::endtrainer::Priv(phase) [dict get $progress kqk] $::endtrainer::Priv(status)
} -cleanup {
	::scidb::test::et::release
	::scidb::test::et::restoreHome
	::scidb::test::et::cleanupDir
} -result {1 over {attempts 1 done 1} {Checkmate - the goal is reached.}}

tcltest::test endtrainer-hold-draw {holding the draw for the target reaches the goal} -setup {
	::scidb::test::et::setHome
	set saved $::endtrainer::HoldMoves
	set ::endtrainer::HoldMoves 1
	::scidb::test::et::stubTablebase [dict create \
		"8/8/8/3k4/3P4/8/3K4/8 b - -" {{"category":"draw","moves":[
			{"san":"Kd5","category":"draw","dtz":0}]}}]
} -body {
	::endtrainer::Start kpk-draw
	set ok [::endtrainer::UserMove Kd2]
	::scidb::test::et::pump 200
	set progress [::endtrainer::LoadProgress]
	list $ok $::endtrainer::Priv(phase) [dict get $progress kpk-draw] $::endtrainer::Priv(status)
} -cleanup {
	set ::endtrainer::HoldMoves $saved
	::scidb::test::et::release
	::scidb::test::et::restoreHome
	::scidb::test::et::cleanupDir
} -result {1 over {attempts 1 done 1} {Draw held - the goal is reached.}}

# ----------------------------------------------------------------------
# The window
# ----------------------------------------------------------------------

tcltest::test endtrainer-dialog {the window lists the themes and endings} -setup {
	::scidb::test::et::setHome
} -body {
	set dlg [::endtrainer::open .application]
	update
	set tree $::endtrainer::Priv(widget:tree)
	set themes [$tree children {}]
	set endings 0
	foreach node $themes { incr endings [llength [$tree children $node]] }
	list [winfo exists $dlg] [llength $themes] $endings
} -cleanup {
	catch { ::endtrainer::Close }
	::scidb::test::et::restoreHome
	::scidb::test::et::cleanupDir
} -result {1 4 10}

tcltest::cleanupTests
