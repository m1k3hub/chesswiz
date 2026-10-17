# ======================================================================
# Scidb App Test - which engine judges moves (tcl/ai-engine.tcl)
# ======================================================================
# The bundled Stockfish by default; any configured UCI engine can be
# chosen instead (Extras > Engine for Reviews and AI). No engine runs here.
# ======================================================================
package require tcltest 2.5

namespace eval ::scidb::test::aieng {}

proc ::scidb::test::aieng::with {body} {
	set savedOpt $::ai::engine::Options(engine)
	set savedCfg $::ai::engine::Config(engine)
	set savedEngines $::engine::Engines
	rename ::ai::engine::bundled ::scidb::test::aieng::realBundled
	proc ::ai::engine::bundled {} { return $::scidb::test::aieng::bundledPath }
	rename ::engine::Command ::scidb::test::aieng::realCommand
	proc ::engine::Command {cmd params} { expr {[string match *missing* $cmd] ? "" : [list $cmd {*}$params]} }
	set rc [catch { uplevel 1 $body } result]
	rename ::ai::engine::bundled {}
	rename ::scidb::test::aieng::realBundled ::ai::engine::bundled
	rename ::engine::Command {}
	rename ::scidb::test::aieng::realCommand ::engine::Command
	set ::engine::Engines $savedEngines
	set ::ai::engine::Options(engine) $savedOpt
	set ::ai::engine::Config(engine) $savedCfg
	if {$rc} { return -code error $result }
	return $result
}

proc ::scidb::test::aieng::engine {name command protocol} {
	dict create Name $name Command $command Parameters {} Protocol $protocol
}

tcltest::test aieng-default-bundled {the bundled Stockfish by default, even with other engines set up} -body {
	::scidb::test::aieng::with {
		set ::scidb::test::aieng::bundledPath /opt/cw/engines/stockfish-chesswiz
		set ::engine::Engines [list [::scidb::test::aieng::engine Komodo /e/komodo UCI]]
		set ::ai::engine::Config(engine) auto
		set ::ai::engine::Options(engine) ""
		::ai::engine::Resolve
	}
} -result {/opt/cw/engines/stockfish-chesswiz {}}

tcltest::test aieng-chosen {a chosen UCI engine replaces it; a WinBoard-only or missing one falls back} -body {
	::scidb::test::aieng::with {
		set ::scidb::test::aieng::bundledPath /opt/cw/engines/stockfish-chesswiz
		set ::engine::Engines [list \
			[::scidb::test::aieng::engine Komodo /e/komodo UCI] \
			[::scidb::test::aieng::engine Crafty /e/crafty WB] \
			[::scidb::test::aieng::engine Gone /e/missing UCI]]
		set ::ai::engine::Config(engine) auto
		set out {}
		foreach name {Komodo Crafty Gone} {
			set ::ai::engine::Options(engine) $name
			lappend out [::ai::engine::Resolve]
		}
		lappend out [::ai::engine::uciEngines]
	}
} -result {{/e/komodo Komodo} {/opt/cw/engines/stockfish-chesswiz {}} {/opt/cw/engines/stockfish-chesswiz {}} {Komodo Gone}}

tcltest::test aieng-no-bundled {without the bundled engine, a configured UCI engine is used} -body {
	::scidb::test::aieng::with {
		set ::scidb::test::aieng::bundledPath ""
		set ::engine::Engines [list [::scidb::test::aieng::engine Crafty /e/crafty WB] \
			[::scidb::test::aieng::engine Lc0 /e/lc0 UCI]]
		set ::ai::engine::Config(engine) auto
		set ::ai::engine::Options(engine) ""
		# a stockfish on PATH comes before the dictionary; hide it
		set path $::env(PATH); set ::env(PATH) /nonexistent
		set r [::ai::engine::Resolve]
		set ::env(PATH) $path
		set r
	}
} -result {/e/lc0 Lc0}

tcltest::cleanupTests
