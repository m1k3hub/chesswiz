# ======================================================================
# Scidb App Test — assistant tools for chess engines
# (tcl/app-assistant.tcl, engine list of tcl/engine.tcl, analysis panes)
# ======================================================================
# The engine list is swapped for an empty one and saved to a scratch file,
# so the user's engines are neither read nor written. The live tests need
# a UCI engine; SCIDB_TEST_ENGINE names one, else stockfish on PATH.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::engines {
	variable Asked {}
	variable Saved {}
	variable Program ""
	if {[info exists ::env(SCIDB_TEST_ENGINE)]} {
		set Program $::env(SCIDB_TEST_ENGINE)
	} else {
		set Program [lindex [auto_execok stockfish] 0]
	}
}

tcltest::testConstraint uciEngine [expr {
	[string length $::scidb::test::engines::Program] && [file executable $::scidb::test::engines::Program]}]

proc ::scidb::test::engines::confirm {what} {
	variable Asked
	lappend Asked $what
	return 1
}

proc ::scidb::test::engines::isolate {} {
	variable Saved
	variable Asked {}
	set Saved [list $::engine::Engines $::scidb::file::engines]
	set ::engine::Engines {}
	set ::scidb::file::engines [file join [::tcltest::temporaryDirectory] engines-[pid].dat]
	set ::application::assistant::Priv(confirm) ::scidb::test::engines::confirm
}

proc ::scidb::test::engines::restore {} {
	variable Saved
	foreach number [::application::assistant::RunningPanes] {
		::application::analysis::stopEngine $number
	}
	file delete -force $::scidb::file::engines
	lassign $Saved ::engine::Engines ::scidb::file::engines
	::options::hookWriter ::engine::WriteEngineOptions engines
}

# Waits <ms> milliseconds with the event loop running.
proc ::scidb::test::engines::wait {ms} {
	set ::scidb::test::engines::Tick 0
	after $ms { set ::scidb::test::engines::Tick 1 }
	vwait ::scidb::test::engines::Tick
}

proc ::scidb::test::engines::tool {name {cargs {}}} {
	return [::application::assistant::runTool $name $cargs]
}

tcltest::test engines-offered {the engine tools are offered to the model} -body {
	set json [::application::assistant::toolsJson]
	lmap t {list_engines engine_options start_engine engine_analysis stop_engine set_engine_option add_engine remove_engine} {
		expr {[string first "\"$t\"" $json] >= 0}
	}
} -result {1 1 1 1 1 1 1 1}

tcltest::test engines-none {with no engine the tools say so, without asking} -setup {
	::scidb::test::engines::isolate
} -body {
	list [string match "*No engine is installed*" [::scidb::test::engines::tool list_engines]] \
		[::scidb::test::engines::tool start_engine {engine stockfish}] \
		[::scidb::test::engines::tool stop_engine] \
		$::scidb::test::engines::Asked
} -cleanup {
	::scidb::test::engines::restore
} -result {1 {error: no engine is installed; add one with add_engine} {error: no engine is running} {}}

tcltest::test engines-names {engines are found by part of the name; unknown and ambiguous names are refused} -setup {
	::scidb::test::engines::isolate
	set ::engine::Engines [list \
		[dict merge $::engine::EmptyEngine {Name Stockfish Identifier {Stockfish 4 scidb} UserDefined 0}] \
		[dict merge $::engine::EmptyEngine {Name {Stockfish (2)} Identifier {Stockfish 18}}] \
		[dict merge $::engine::EmptyEngine {Name Sjeng Identifier {Sjeng 11.2 scidb} UserDefined 0}]]
} -body {
	list [::application::assistant::EngineNamed stockfish] \
		[::application::assistant::EngineNamed "stockfish 18"] \
		[::application::assistant::EngineNamed sjeng] \
		[catch { ::application::assistant::EngineNamed fish } err] $err \
		[catch { ::application::assistant::EngineNamed komodo } err] $err
} -cleanup {
	::scidb::test::engines::restore
} -result {Stockfish {Stockfish (2)} Sjeng 1 {'fish' matches several engines: Stockfish, Stockfish (2); give the exact name} 1 {no engine matches 'komodo'; the engines are: Stockfish, Stockfish (2), Sjeng}}

tcltest::test engines-bad-arguments {bad paths, panes and numbers are refused before asking} -setup {
	::scidb::test::engines::isolate
	set ::engine::Engines [list [dict merge $::engine::EmptyEngine {Name Stockfish}]]
} -body {
	list [::scidb::test::engines::tool add_engine {path /nonexistent/engine}] \
		[::scidb::test::engines::tool start_engine {engine Stockfish lines 0}] \
		[string match "error: no analysis pane 99*" [::scidb::test::engines::tool start_engine {engine Stockfish pane 99}]] \
		[::scidb::test::engines::tool engine_analysis {seconds 61}] \
		$::scidb::test::engines::Asked
} -cleanup {
	::scidb::test::engines::restore
} -result {{error: no such file: /nonexistent/engine} {error: lines must be a positive integer} 1 {error: seconds must be a whole number from 0 to 60} {}}

tcltest::test engines-add-and-options {add_engine probes a program; its options can be read and set, and bad values are refused} -constraints uciEngine -setup {
	::scidb::test::engines::isolate
} -body {
	set added [::scidb::test::engines::tool add_engine [list path $::scidb::test::engines::Program]]
	set name [dict get [lindex $::engine::Engines 0] Name]
	set listed [::scidb::test::engines::tool list_engines]
	set options [::scidb::test::engines::tool engine_options [list engine $name]]
	set bad [::scidb::test::engines::tool set_engine_option [list engine $name option "move overhead" value 999999]]
	set asked [llength $::scidb::test::engines::Asked]
	set set [::scidb::test::engines::tool set_engine_option [list engine $name option "move overhead" value 50]]
	list [string match "Added $name (*UCI) from *" $added] \
		[string match "*$name:*added by the user*UCI*hash *-* MB, up to * lines*program $::scidb::test::engines::Program*Analysis panes:*" \
			[string map {\n " "} $listed]] \
		[string match "*Move Overhead = * (whole number *" $options] \
		[expr {[string first "Threads" $options] < 0}] \
		$bad $asked \
		$set \
		[string match "*Move Overhead = 50 (*default *" [::scidb::test::engines::tool engine_options [list engine $name]]] \
		[file exists $::scidb::file::engines]
} -cleanup {
	::scidb::test::engines::restore
} -match glob -result {1 1 1 1 {error: Move Overhead must be a whole number from * to *} 1 {Set Move Overhead of * (profile 'Default') to 50; saved.} 1 1}

tcltest::test engines-analyse {start_engine analyses the board position; engine_analysis reads its lines; stop_engine ends it} -constraints uciEngine -setup {
	::scidb::test::engines::isolate
	::scidb::test::engines::tool add_engine [list path $::scidb::test::engines::Program]
	set name [dict get [lindex $::engine::Engines 0] Name]
} -body {
	set started [::scidb::test::engines::tool start_engine [list engine $name lines 2 threads 1 hash 16]]
	regexp {analysis pane (\d+)} $started _ pane
	::scidb::test::engines::wait 3000
	set report [::scidb::test::engines::tool engine_analysis [list pane $pane]]
	set busy [::scidb::test::engines::tool remove_engine [list engine $name]]
	set stopped [::scidb::test::engines::tool stop_engine]
	set after [::scidb::test::engines::tool engine_analysis]
	set removed [::scidb::test::engines::tool remove_engine [list engine $name]]
	list [string match "$name is analysing the board position in analysis pane $pane: 2 lines, 1 threads, 16 MB hash*" $started] \
		[regexp "Pane $pane, $name, depth \\d+:\n  1\\. \[-+#\]\[0-9.#\]+ \\(depth \\d+\\) \\S+.*\n  2\\. " $report] \
		[string match "error: '$name' is running in an analysis pane; stop it first" $busy] \
		$stopped $after $removed [llength $::engine::Engines]
} -cleanup {
	::scidb::test::engines::restore
} -match glob -result {1 1 1 {Stopped * in analysis pane *; the pane stays open.} {No engine is running. Start one with start_engine.} {Removed * from the engine list; its program is still on disk.} 0}

tcltest::test engines-start-twice {starting the engine that is already analysing reuses its pane} -constraints uciEngine -setup {
	::scidb::test::engines::isolate
	::scidb::test::engines::tool add_engine [list path $::scidb::test::engines::Program]
	set name [dict get [lindex $::engine::Engines 0] Name]
} -body {
	set first [::scidb::test::engines::tool start_engine [list engine $name lines 1]]
	::scidb::test::engines::wait 1000
	set second [::scidb::test::engines::tool start_engine [list engine $name lines 2]]
	regexp {analysis pane (\S+):} $first _ p1
	regexp {analysis pane (\S+):} $second _ p2
	set running [llength [::application::analysis::Running]]
	::scidb::test::engines::tool stop_engine
	list [expr {$p1 eq $p2}] $running [string match "*: 2 lines,*" $second]
} -cleanup {
	::scidb::test::engines::restore
} -result {1 1 1}

tcltest::test engines-lines-beyond-pane {more lines than the pane has rows are refused, not half shown} -constraints uciEngine -setup {
	::scidb::test::engines::isolate
	::scidb::test::engines::tool add_engine [list path $::scidb::test::engines::Program]
	set name [dict get [lindex $::engine::Engines 0] Name]
} -body {
	set first [::scidb::test::engines::tool start_engine [list engine $name lines 1]]
	::scidb::test::engines::wait 500
	set many [::scidb::test::engines::tool start_engine [list engine $name lines 9]]
	::scidb::test::engines::tool stop_engine
	list [string match "*doesn't exist*" $many] [string match "*at most 8 lines*" $many]
} -cleanup {
	::scidb::test::engines::restore
} -result {0 1}

tcltest::test engines-analysis-waits {engine_analysis with seconds answers later, through the tool loop} -constraints uciEngine -setup {
	::scidb::test::engines::isolate
	::scidb::test::engines::tool add_engine [list path $::scidb::test::engines::Program]
	set name [dict get [lindex $::engine::Engines 0] Name]
	::scidb::test::engines::tool start_engine [list engine $name lines 1]
	set cfg ::application::ai::Config
	set saved [array get $cfg provider]
	set ${cfg}(provider) stub
	::ai::provider::configure -name stub -chatResponses [list \
		[dict create role assistant content "" tool_calls [list [dict create function \
			[dict create name engine_analysis arguments {seconds 1}]]]] \
		[dict create role assistant content "White is slightly better."]]
} -body {
	::application::assistant::clear
	::application::assistant::ask "how does the engine see it?"
	if {$::application::assistant::Priv(busy)} { vwait ::application::assistant::Priv(busy) }
	set text [$::application::assistant::Priv(text) get 1.0 end-1c]
	list [string match "*engine_analysis: (working...)*engine_analysis: Board position: *depth*White is slightly better.*" $text]
} -cleanup {
	array set $cfg $saved
	::scidb::test::engines::restore
} -result {1}

# --- analysis panes: shared engine start, pin, comparison -----------------

tcltest::test analysis-first-move {the first move of an engine line, without its number, in letters} -body {
	lmap pv [list {1.e4 e5 2.Nf3} {12...Qxd5+ 13.Nc3} {Nf3 d5} {1. d4 Nf6} "1.\u2658f3 d5" "5...\u265bxd5+"] {
		::application::analysis::FirstMove $pv
	}
} -result {e4 Qxd5+ Nf3 d4 Nf3 Qxd5+}

tcltest::test analysis-comparison-summary {the comparison names the most chosen move, the dissent, the score spread and the deepest search} -body {
	::application::analysis::ComparisonSummary [list \
		[list A 1 {35 0 20 0 0 0 0 0 {1.e4 e5}}] \
		[list B 2 {20 0 24 0 0 0 0 0 {1.e4 c5}}] \
		[list C 3 {-10 0 18 0 0 0 0 0 {1.d4 d5}}] \
		[list D 4 {}]]
} -result "2 of 3 engines choose e4.
C: d4.
Scores from −0.10 to +0.35 (spread +0.45).
Deepest search: B (depth 24)."

tcltest::test analysis-default-engine {the default engine is the last chosen that can run, else the first} -setup {
	::scidb::test::engines::isolate
	set savedLast $::engine::Options(engine)
	set ::engine::Engines [list [dict merge $::engine::EmptyEngine \
		{Name Gone Command /nonexistent/engine Protocol UCI Features:UCI {analyze true}}]]
} -body {
	set none [::application::analysis::defaultEngine]
	lappend ::engine::Engines \
		[dict merge $::engine::EmptyEngine [list Name A Command [info nameofexecutable] Protocol UCI Features:UCI {analyze true}]] \
		[dict merge $::engine::EmptyEngine [list Name B Command [info nameofexecutable] Protocol UCI Features:UCI {analyze true}]] \
		[dict merge $::engine::EmptyEngine [list Name C Command [info nameofexecutable] Protocol UCI Features:UCI {}]]
	set ::engine::Options(engine) B
	set last [::application::analysis::defaultEngine]
	set ::engine::Options(engine) C
	list $none $last [::application::analysis::defaultEngine]
} -cleanup {
	set ::engine::Options(engine) $savedLast
	::scidb::test::engines::restore
} -result {{} B A}

tcltest::test analysis-pin {pin is enabled by a best line and saves the game up to the board with the engine's move and score} -constraints uciEngine -setup {
	::scidb::test::engines::isolate
	::scidb::test::engines::tool add_engine [list path $::scidb::test::engines::Program]
	set name [dict get [lindex $::engine::Engines 0] Name]
	rename ::application::pgn::saveGame ::scidb::test::engines::saveGame
	proc ::application::pgn::saveGame {args} {
		set ::scidb::test::engines::Saved [list $args [::scidb::game::toPGN modified]]
	}
} -body {
	set number [::application::analysis::startEngine $name "" {lines 2}]
	set tree $::application::analysis::NumberToTree($number)
	::scidb::test::engines::wait 2000
	set pin [set ::application::analysis::${tree}::Vars(widget:button:pin)]
	set enabled [::toolbar::childcget $pin -state]
	lassign [::application::analysis::BestLine $tree] row line
	set move [::application::analysis::FirstMove [lindex $line 8]]
	set fen [::scidb::pos::fen]
	::application::analysis::SaveBestLine .application base $move "$name: +0.10 (depth 9)"
	lassign $::scidb::test::engines::Saved saveArgs pgn
	::application::analysis::stopEngine $number
	list $enabled $saveArgs \
		[regexp "[regsub -all {[+]} $move {\\+}] \\{$name: \\+0.10 \\(depth 9\\)\\}" $pgn] \
		[expr {[::scidb::pos::fen] eq $fen}] \
		[::toolbar::childcget $pin -state]
} -cleanup {
	rename ::application::pgn::saveGame {}
	rename ::scidb::test::engines::saveGame ::application::pgn::saveGame
	::scidb::test::engines::restore
} -result {normal {add base} 1 1 disabled}

tcltest::test analysis-compare {the comparison runs the chosen engines side by side and sums up} -constraints uciEngine -setup {
	::scidb::test::engines::isolate
	::scidb::test::engines::tool add_engine [list path $::scidb::test::engines::Program]
	set name [dict get [lindex $::engine::Engines 0] Name]
	lappend ::engine::Engines [dict replace [lindex $::engine::Engines 0] Name "$name copy"]
	set ::application::analysis::compare::Seconds 3
} -body {
	::application::analysis::openComparison .application
	set dlg .compareEngines
	$dlg.top.engines selection set 0 end
	$dlg.start invoke
	set running [llength [::application::analysis::Running]]
	for {set i 0} {$i < 20 && [$dlg.start cget -state] eq "disabled"} {incr i} { ::scidb::test::engines::wait 500 }
	set depths [lmap item [$dlg.top.results children {}] { lindex [$dlg.top.results item $item -values] 1 }]
	set summary [$dlg.top.summary get 1.0 end-1c]
	set after [llength [::application::analysis::Running]]
	::application::analysis::CloseComparison
	list $running [llength $depths] [expr {[lindex $depths 0] > 0 && [lindex $depths 1] > 0}] \
		[string match "* of 2 engines choose *Deepest search: *" [string map {\n " "} $summary]] \
		$after [winfo exists $dlg]
} -cleanup {
	::scidb::test::engines::restore
} -result {2 2 1 1 0 0}

tcltest::cleanupTests
