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

tcltest::cleanupTests
