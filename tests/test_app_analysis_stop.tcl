# ======================================================================
# Scidb App Test — the analysis pane's Lines spinner and its Stop button
# (tcl/app-analysis.tcl, tcl/engine.tcl)
# ======================================================================
# G18: the Lines spinner shows the number of lines the engine runs (its
#      MultiPV), and changing the spinner changes the engine's MultiPV.
# G19: the square Stop button stops the search ("stop", then "bestmove")
#      instead of powering the engine down; it never blocks the Tk event loop.
#      Closing (the separate button and the menu entry) still powers the
#      engine down, and does not wait for an engine which hangs.
#
# The engine list is replaced and saved to a scratch file, so the user's
# engines are neither read nor written. The Stockfish tests need SCIDB_TEST_ENGINE
# or stockfish on PATH; the hang tests use tests/fixtures/fake-uci-hung.tcl.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::pane {
	variable Asked {}
	variable Saved {}
	variable Log {}
	variable Program ""
}

# The UCI engine for the live tests. An earlier test file may have replaced
# PATH, so the usual installation directories are checked as well.
proc ::scidb::test::pane::findProgram {} {
	if {[info exists ::env(SCIDB_TEST_ENGINE)]} { return $::env(SCIDB_TEST_ENGINE) }
	set repoRoot [file normalize [file join [file dirname [info script]] ..]]
	set mainRoot [file normalize [file join [file dirname [file normalize [file join $repoRoot .git]]] ..]]
	foreach root [list $repoRoot $mainRoot] {
		foreach bin {stockfish-chesswiz stockfish-scidb stockfish.exe stockfish-chesswiz.exe stockfish} {
			set path [file join $root engines stockfish $bin]
			if {[file executable $path]} { return $path }
		}
	}
	if {[llength [auto_execok stockfish]]} { return [lindex [auto_execok stockfish] 0] }
	foreach dir {/usr/games /usr/local/games /usr/local/bin /usr/bin /opt/homebrew/bin} {
		set path [file join $dir stockfish]
		if {[file executable $path]} { return $path }
	}
	return ""
}

set ::scidb::test::pane::Program [::scidb::test::pane::findProgram]

tcltest::testConstraint uciEngine [expr {
	[string length $::scidb::test::pane::Program] && [file executable $::scidb::test::pane::Program]}]

proc ::scidb::test::pane::confirm {what} {
	variable Asked
	lappend Asked $what
	return 1
}

# The user's engines are neither read nor written, and the engine protocol log
# is captured into ::scidb::test::pane::Log (one line per engine message).
proc ::scidb::test::pane::isolate {} {
	variable Saved
	variable Log {}
	set Saved [list $::engine::Engines $::scidb::file::engines \
		$::application::analysis::GlobalOptions(engine:stopTimeout)]
	set ::engine::Engines {}
	set ::scidb::file::engines [file join [::tcltest::temporaryDirectory] engines-[pid].dat]
	set ::application::assistant::Priv(confirm) ::scidb::test::pane::confirm
	# a log left open by an earlier test would make engine::log open fail
	catch { ::scidb::engine::log close }
	::scidb::engine::log open ::scidb::test::pane::logLine {}
}

# Every test starts from a pane of its own: an engine and the pane it lives in
# carry state (the engine's MultiPV, a search which is still on its way) over
# to the next test, and a test must not depend on that.
proc ::scidb::test::pane::restore {} {
	variable Saved
	foreach number [::application::analysis::Running] {
		::application::analysis::stopEngine $number
	}
	foreach number [array names ::application::analysis::NumberToTree] {
		catch {
			set uid analysis:$::application::MapAnalysisToTerminal($number)
			set twm $::application::Vars(board:twm)
			$twm close [$twm leaf $uid]
		}
	}
	update idletasks
	# leave the application with the analysis pane it is started with: other
	# tests undock it, and ask for the pane numbers the assistant reports
	if {![llength [array names ::application::MapTerminalToAnalysis]]} {
		::application::newAnalysisPane 1
		update idletasks
	}
	# let the exit of a killed engine, and the signals it sends, be handled
	::scidb::test::pane::wait 100
	catch { ::scidb::engine::log close }
	file delete -force $::scidb::file::engines
	lassign $Saved engines file timeout
	set ::engine::Engines $engines
	set ::scidb::file::engines $file
	set ::application::analysis::GlobalOptions(engine:stopTimeout) $timeout
	::options::hookWriter ::engine::WriteEngineOptions engines
}

proc ::scidb::test::pane::addEngine {path} {
	::application::assistant::runTool add_engine [list path $path]
	return [dict get [lindex $::engine::Engines 0] Name]
}

proc ::scidb::test::pane::wait {ms} {
	set ::scidb::test::pane::Tick 0
	after $ms { set ::scidb::test::pane::Tick 1 }
	vwait ::scidb::test::pane::Tick
}

# Waits until <cond> holds, at most <ms> milliseconds: a loaded machine is slow
# to give the engine its first lines.
proc ::scidb::test::pane::waitUntil {cond {ms 30000}} {
	for {set t 0} {$t < $ms && ![uplevel 1 [list expr $cond]]} {incr t 50} {
		::scidb::test::pane::wait 50
	}
	return [uplevel 1 [list expr $cond]]
}

proc ::scidb::test::pane::logLine {arg line} {
	variable Log
	append Log $line "\n"
}

# true when the engine protocol log contains <text>
proc ::scidb::test::pane::logged {text} {
	variable Log
	return [expr {[string first $text $::scidb::test::pane::Log] >= 0}]
}

# The tree widget path of pane <number> (the pane's variables live below it).
proc ::scidb::test::pane::vars {number} {
	return $::application::analysis::NumberToTree($number)
}

# Starts an engine in a fresh pane and waits until it runs and its toolbar is
# usable. Returns {number tree}.
proc ::scidb::test::pane::start {name {lines 4}} {
	::application::switchTab board
	update idletasks
	set number [::application::analysis::startEngine $name "" [list lines $lines]]
	set tree [::scidb::test::pane::vars $number]
	namespace upvar ::application::analysis ${tree}::Vars Vars
	::scidb::test::pane::waitUntil {[llength [::application::analysis::lines $number]] > 0}
	# the toolbar stays disabled until the engine has started searching
	::scidb::test::pane::waitUntil {
		[::toolbar::childcget $Vars(widget:button:stop) -state] eq "normal"} 10000
	return [list $number $tree]
}

# The spinner is readonly and its command is what a user's arrow key runs:
# set the value, then run the command which is configured for the widget.
proc ::scidb::test::pane::spin {spinner value} {
	set command [$spinner cget -command]
	$spinner set $value
	uplevel #0 $command
}

proc ::scidb::test::pane::lineCount {number} {
	return [llength [::application::analysis::lines $number]]
}

# A toolbar button is only usable when the toolbar gave it a command: a
# disabled toolbar button keeps its state and loses its command.
proc ::scidb::test::pane::enabled {widget} {
	return [expr {[::toolbar::childcget $widget -state] eq "normal"
		&& [string length [$widget cget -command]]}]
}

# ======================================================================
# G18 — the Lines spinner is the engine's MultiPV
# ======================================================================

tcltest::test analysis-lines-spinner-shows-multipv {the Lines spinner shows the MultiPV the engine runs with} \
		-constraints uciEngine -setup {
	::scidb::test::pane::isolate
	set name [::scidb::test::pane::addEngine $::scidb::test::pane::Program]
	lassign [::scidb::test::pane::start $name 4] number tree
	namespace upvar ::application::analysis ${tree}::Vars Vars
	namespace upvar ::application::analysis ${number}::Options Options
	set spinner $Vars(widget:linesPerPV)
} -body {
	::scidb::test::pane::waitUntil {[::scidb::test::pane::lineCount $number] >= 4}
	list [$spinner get] $Options(engine:multiPV) [::scidb::test::pane::lineCount $number] \
		[::scidb::test::pane::logged "> setoption name MultiPV value 4"]
} -cleanup {
	::scidb::test::pane::restore
} -result {4 4 4 1}

tcltest::test analysis-lines-spinner-changes-multipv {changing the Lines spinner changes the engine's MultiPV} \
		-constraints uciEngine -setup {
	::scidb::test::pane::isolate
	set name [::scidb::test::pane::addEngine $::scidb::test::pane::Program]
	lassign [::scidb::test::pane::start $name 4] number tree
	namespace upvar ::application::analysis ${tree}::Vars Vars
	namespace upvar ::application::analysis ${number}::Options Options
	set spinner $Vars(widget:linesPerPV)
	::scidb::test::pane::waitUntil {[::scidb::test::pane::lineCount $number] >= 4}
	variable ::scidb::test::pane::Log {}
} -body {
	::scidb::test::pane::spin $spinner 2
	# a running engine is stopped for the option change and gets the new
	# "setoption" after it answered "isready"
	::scidb::test::pane::waitUntil {
		[::scidb::test::pane::logged "> setoption name MultiPV value 2"]} 10000
	set sent [::scidb::test::pane::logged "> setoption name MultiPV value 2"]
	::scidb::test::pane::waitUntil {[::scidb::test::pane::lineCount $number] == 2}
	list [$spinner get] $Options(engine:multiPV) $sent [::scidb::test::pane::lineCount $number]
} -cleanup {
	::scidb::test::pane::restore
} -result {2 2 1 2}

tcltest::test analysis-lines-spinner-clamps-to-engine {a spinner value above what the engine supports is clamped, and shown clamped} \
		-constraints uciEngine -setup {
	::scidb::test::pane::isolate
	set name [::scidb::test::pane::addEngine $::scidb::test::pane::Program]
	lassign [::scidb::test::pane::start $name 2] number tree
	namespace upvar ::application::analysis ${tree}::Vars Vars
	namespace upvar ::application::analysis ${number}::Options Options
	set spinner $Vars(widget:linesPerPV)
	# what the pane consults for the supported number of lines is the engine
	# record: make it claim two lines
	set index [::engine::FindIndex $name]
	set entry [lindex $::engine::Engines $index]
	dict set entry Features:UCI multiPV 2
	lset ::engine::Engines $index $entry
	variable ::scidb::test::pane::Log {}
} -body {
	::scidb::test::pane::spin $spinner 4
	::scidb::test::pane::waitUntil {[::scidb::test::pane::lineCount $number] == 2}
	list [$spinner get] $Options(engine:multiPV) [::application::analysis::MaxMultiPV $number] \
		[::scidb::test::pane::lineCount $number] \
		[expr {![::scidb::test::pane::logged "> setoption name MultiPV value 4"]}]
} -cleanup {
	::scidb::test::pane::restore
} -result {2 2 2 2 1}

tcltest::test analysis-lines-spinner-single-pv {while "multiple variations" is off the spinner shows one line and is disabled} \
		-constraints uciEngine -setup {
	::scidb::test::pane::isolate
	set name [::scidb::test::pane::addEngine $::scidb::test::pane::Program]
	lassign [::scidb::test::pane::start $name 3] number tree
	namespace upvar ::application::analysis ${tree}::Vars Vars
	namespace upvar ::application::analysis ${number}::Options Options
	set spinner $Vars(widget:linesPerPV)
} -body {
	set Options(engine:singlePV) 1
	::application::analysis::SetMultiPV $tree
	::scidb::test::pane::waitUntil {[::scidb::test::pane::lineCount $number] == 1} 10000
	set single [list [$spinner get] [::toolbar::childcget $spinner -state] \
		[::scidb::test::pane::lineCount $number]]
	set Options(engine:singlePV) 0
	::application::analysis::SetMultiPV $tree
	::scidb::test::pane::waitUntil {[::scidb::test::pane::lineCount $number] == 3} 10000
	list $single [$spinner get] [::toolbar::childcget $spinner -state] \
		[::scidb::test::pane::lineCount $number] $Options(engine:multiPV)
} -cleanup {
	::scidb::test::pane::restore
} -result {{1 disabled 1} 3 readonly 3 3}

tcltest::test analysis-lines-per-variation {how many plies of a line are wrapped is a separate setting} \
		-constraints uciEngine -setup {
	::scidb::test::pane::isolate
	set name [::scidb::test::pane::addEngine $::scidb::test::pane::Program]
	lassign [::scidb::test::pane::start $name 2] number tree
	namespace upvar ::application::analysis ${tree}::Vars Vars
	namespace upvar ::application::analysis ${number}::Options Options
	set spinner $Vars(widget:linesPerPV)
} -body {
	set Options(engine:nlines) 2
	::application::analysis::SetLinesPerPV $tree
	set wrapped [$tree item element cget Line0 Moves elemTextFig -lines]
	::scidb::test::pane::spin $spinner 3
	list $wrapped $Options(engine:nlines) $Options(engine:multiPV) \
		[$tree item element cget Line0 Moves elemTextFig -lines]
} -cleanup {
	::scidb::test::pane::restore
} -result {2 2 3 2}

# ======================================================================
# G19 — Stop stops the search instead of powering the engine down
# ======================================================================

tcltest::test analysis-stop-stops-the-search {Stop sends "stop", keeps the engine and the lines, and does not block} \
		-constraints uciEngine -setup {
	::scidb::test::pane::isolate
	set name [::scidb::test::pane::addEngine $::scidb::test::pane::Program]
	lassign [::scidb::test::pane::start $name 4] number tree
	namespace upvar ::application::analysis ${tree}::Vars Vars
	set stop $Vars(widget:button:stop)
	set enabled [::scidb::test::pane::enabled $stop]
	# the square button stops the search, the separate button closes the engine
	set wired [list [string match "*Stop *" [$stop cget -command]] \
		[string match "*CloseEngine *" [$Vars(widget:button:close) cget -command]]]
	variable ::scidb::test::pane::Log {}
} -body {
	::scidb::test::pane::waitUntil {[::scidb::test::pane::lineCount $number] == 4}
	set before [::scidb::test::pane::lineCount $number]
	# the event loop must stay alive while the stop is pending
	set ::scidb::test::pane::Alive 0
	after 50 { set ::scidb::test::pane::Alive 1 }
	set t0 [clock milliseconds]
	$stop invoke
	set elapsed [expr {[clock milliseconds] - $t0}]
	::scidb::test::pane::waitUntil {$::scidb::test::pane::Alive}
	::scidb::test::pane::wait 100
	set answered [::scidb::test::pane::waitUntil {
		[::scidb::test::pane::logged "< bestmove"]} 10000]
	set logAfterStop $::scidb::test::pane::Log
	set ::scidb::test::pane::Log {}
	::scidb::test::pane::wait 250
	set noFurtherInfo [expr {![::scidb::test::pane::logged "< info "]}]
	set ::scidb::test::pane::Log $logAfterStop
	list $enabled $wired [expr {$elapsed < 500}] $::scidb::test::pane::Alive $answered \
		[::scidb::test::pane::logged "> stop"] \
		$noFurtherInfo \
		[::engine::active? $number] $Vars(engine:stopped) $Vars(after:stop) \
		[::scidb::test::pane::lineCount $number] $before \
		[::toolbar::childcget $stop -state] \
		[::toolbar::childcget $Vars(widget:button:close) -state] \
		[$Vars(widget:mesg) cget -text]
} -cleanup {
	::scidb::test::pane::restore
} -result {1 {1 1} 1 1 1 1 1 1 1 {} 4 4 disabled normal stopped}

tcltest::test analysis-stop-start-again {the start button starts the stopped search again} \
		-constraints uciEngine -setup {
	::scidb::test::pane::isolate
	set name [::scidb::test::pane::addEngine $::scidb::test::pane::Program]
	lassign [::scidb::test::pane::start $name 2] number tree
	namespace upvar ::application::analysis ${tree}::Vars Vars
	variable ::scidb::test::pane::Log {}
} -body {
	$Vars(widget:button:stop) invoke
	# "stop" is sent at once, from the button, without waiting for anything
	set sent [::scidb::test::pane::logged "> stop"]
	set ::scidb::test::pane::Log {}
	set start [::scidb::test::pane::enabled $Vars(widget:button:pause)]
	set tip [::toolbar::childcget $Vars(widget:button:pause) -tooltipvar]
	$Vars(widget:button:pause) invoke
	set restarting [::scidb::test::pane::waitUntil {
		[::scidb::test::pane::logged "> go infinite"]} 20000]
	list $sent $start $restarting $Vars(engine:stopped) $Vars(engine:pause) \
		[expr {$tip eq "::application::analysis::mc::StartMotor"}] \
		[::toolbar::childcget $Vars(widget:button:stop) -state] \
		[::scidb::test::pane::waitUntil {[::scidb::test::pane::lineCount $number] >= 2} 20000]
} -cleanup {
	::scidb::test::pane::restore
} -result {1 1 1 0 0 1 normal 1}

tcltest::test analysis-close-powers-down {close powers the engine down at once, also an engine which hangs} \
		-constraints unix -setup {
	::scidb::test::pane::isolate
	set program [file join [file dirname [info script]] fixtures fake-uci-hung.tcl]
	set name [::scidb::test::pane::addEngine $program]
	lassign [::scidb::test::pane::start $name 4] number tree
	namespace upvar ::application::analysis ${tree}::Vars Vars
	# the engine answers nothing, not even "stop" or "quit"
	variable ::scidb::test::pane::Log {}
} -body {
	set active [::engine::active? $number]
	set t0 [clock milliseconds]
	$Vars(widget:button:close) invoke
	set elapsed [expr {[clock milliseconds] - $t0}]
	::scidb::test::pane::wait 300
	list $active [expr {$elapsed < 3000}] [::engine::active? $number] \
		[::toolbar::childcget $Vars(widget:button:close) -state] \
		[::toolbar::childcget $Vars(widget:button:stop) -state] \
		[llength [::application::analysis::Running]]
} -cleanup {
	::scidb::test::pane::restore
} -result {1 1 0 disabled disabled 0}

tcltest::test analysis-stop-timeout-powers-down {an engine which does not answer "stop" is powered down after the timeout} \
		-constraints unix -setup {
	::scidb::test::pane::isolate
	set program [file join [file dirname [info script]] fixtures fake-uci-hung.tcl]
	set name [::scidb::test::pane::addEngine $program]
	lassign [::scidb::test::pane::start $name 4] number tree
	namespace upvar ::application::analysis ${tree}::Vars Vars
	set ::application::analysis::GlobalOptions(engine:stopTimeout) 700
	variable ::scidb::test::pane::Log {}
} -body {
	set armed [expr {[::scidb::test::pane::enabled $Vars(widget:button:stop)]}]
	$Vars(widget:button:stop) invoke
	# the event loop is alive while the answer is awaited
	set ::scidb::test::pane::Alive 0
	after 100 { set ::scidb::test::pane::Alive 1 }
	set t0 [clock milliseconds]
	set closed [::scidb::test::pane::waitUntil {![::engine::active? $number]} 5000]
	set elapsed [expr {[clock milliseconds] - $t0}]
	::scidb::test::pane::waitUntil {$::scidb::test::pane::Alive}
	::scidb::test::pane::wait 100
	list $::scidb::test::pane::Alive $armed $closed \
		[expr {$elapsed >= 500 && $elapsed < 4000}] \
		[::engine::active? $number] $Vars(after:stop) \
		[string match "*did not stop*" [$Vars(widget:mesg) cget -text]]
} -cleanup {
	::scidb::test::pane::restore
} -result {1 1 1 1 0 {} 1}

tcltest::test analysis-stop-winboard-keeps-engine {Stop on a WinBoard engine sends "exit", keeps the engine, and does not arm the UCI bestmove timeout} \
		-constraints unix -setup {
	::scidb::test::pane::isolate
	set program [file join [file dirname [info script]] fixtures fake-wb.tcl]
	set name [::scidb::test::pane::addEngine $program]
	lassign [::scidb::test::pane::start $name 1] number tree
	namespace upvar ::application::analysis ${tree}::Vars Vars
	set ::application::analysis::GlobalOptions(engine:stopTimeout) 300
	variable ::scidb::test::pane::Log {}
} -body {
	set stop $Vars(widget:button:stop)
	set t0 [clock milliseconds]
	$stop invoke
	set elapsed [expr {[clock milliseconds] - $t0}]
	# wait past stopTimeout: a WinBoard engine never sends UCI "bestmove", so
	# StopSearch must not arm StopTimedOut and power the engine down.
	::scidb::test::pane::wait 450
	list [expr {$elapsed < 500}] \
		[::scidb::test::pane::logged "> exit"] \
		[::engine::active? $number] \
		$Vars(engine:stopped) \
		$Vars(after:stop) \
		[::toolbar::childcget $stop -state] \
		[::toolbar::childcget $Vars(widget:button:close) -state] \
		[$Vars(widget:mesg) cget -text]
} -cleanup {
	::scidb::test::pane::restore
} -result {1 1 1 1 {} disabled normal stopped}

tcltest::cleanupTests
