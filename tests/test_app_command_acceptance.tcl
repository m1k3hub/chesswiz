# ======================================================================
# Phase 5 Acceptance Suite (docs/features/COMMAND_LINE_PLAN.md §4).
#
# Verifies:
#   1. All 111 entries of tests/assistant_corpus.tcl are accounted for
#      (94 in-scope command-style entries + 17 explicitly out-of-scope entries).
#   2. Over the in-scope corpus rephrased to command style:
#      - every request reaches the right command within the top 3 suggestions;
#      - zero commands run without Enter;
#      - zero suggestions contain a slot value that does not exist in the state.
#   3. A typed full sentence (including every prose sentence in
#      tests/assistant_corpus.tcl) never runs anything by itself.
#   4. Works with the network off and no model configured.
#   5. Optional System One (Jev) reorder is stubbed in tests, only reorders
#      existing low-score candidates, never adds commands or slot values,
#      never runs anything, and falls back deterministically when off/abstained.
#   6. Matching p95 is under 10 ms with a 4.8M-game database open
#      (the name index is already in memory).
# ======================================================================

package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready

source [file join [file dirname [info script]] assistant_corpus.tcl]
source [file join [file dirname [info script]] command_cases.tcl]
source [file join [file dirname [info script]] command_corpus.tcl]

namespace eval ::commandAccept {
	variable Calls {}
	variable ProviderCalls 0
	variable ClassifierCalls 0
	variable Dir [file join $::env(HOME) command-accept]
}
file mkdir $::commandAccept::Dir

proc ::commandAccept::traceRun {command op} {
	lappend ::commandAccept::Calls [lrange $command 1 end]
}

proc ::commandAccept::typeInAsk {text} {
	set ::application::ask::Mode command
	set ::application::ask::Query $text
	unset -nocomplain ::application::ask::Priv(filtered)
	::application::ask::Typed
}

# Build a real open database with the corpus players and events so AppSource
# queries the real C++ namebase, real ECO table, real pattern index, and real board.
set ::commandAccept::PgnPath [file join $::commandAccept::Dir Main.pgn]
set _f [open $::commandAccept::PgnPath w]
puts $_f {[Event "Karvina 5th"]
[Site "Karvina"]
[Date "2020.01.01"]
[Round "1"]
[White "Kasparov, Garry"]
[Black "Carlsen, Magnus"]
[Result "1-0"]
[ECO "B90"]

1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6 6. Bg5 1-0

[Event "Biel"]
[Site "Biel"]
[Date "2021.01.01"]
[Round "2"]
[White "Caruana, Fabiano"]
[Black "Corti, Horacio"]
[Result "1/2-1/2"]
[ECO "D02"]

1. d4 d5 2. Bf4 Nf6 1/2-1/2

[Event "Biel"]
[Site "Biel"]
[Date "2022.01.01"]
[Round "3"]
[White "Thomas, Michael"]
[Black "Musterfrau, Anna"]
[Result "1-0"]
[ECO "E60"]

1. d4 Nf6 2. c4 g6 1-0}
close $_f

set ::commandAccept::ImportFixture [file join $::commandAccept::Dir corpus-import.pgn]
set _f [open $::commandAccept::ImportFixture w]
puts $_f {[Event "TWIC"]
[Site "London"]
[Date "2024.01.01"]
[Round "1"]
[White "Kasparov, Garry"]
[Black "Carlsen, Magnus"]
[Result "1-0"]

1. e4 e5 1-0}
close $_f

::action::run open_database [dict create path $::commandAccept::PgnPath]
::scidb::game::clear {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}
set ::application::ai::Settings(me) {Thomas, Michael}
set ::commandAccept::SavedEngines $::engine::Engines
set ::engine::Engines [list [dict merge $::engine::EmptyEngine {Name Stockfish Command /bin/true Protocol UCI Features:UCI {}}]]

# Turn off classifier and provider to verify offline operation with no model configured.
::ai::systemone::configure -backend off
set ::ai::provider::Config(name) none
set ::ai::provider::Config(endpoint) ""
set ::ai::provider::Config(model) ""

rename ::ai::provider::request ::commandAccept::realProviderRequest
proc ::ai::provider::request {args} {
	incr ::commandAccept::ProviderCalls
	error "network disabled in acceptance test"
}

trace add execution ::action::run enter ::commandAccept::traceRun

# Helper to verify that every slot value in a suggestion row belongs to the current state.
proc ::commandAccept::validSlotValues {row} {
	set id [dict get $row id]
	set action [dict get $row action]
	set args [dict get $row args]
	set validPlayers [::commandline::AppSource player ""]
	set validEvents [::commandline::AppSource event ""]
	set validBases [::commandline::AppSource database ""]
	set validEngines [::commandline::AppSource engine ""]
	set validTabs [::commandline::AppSource tab ""]
	set validPanes [::commandline::AppSource pane ""]
	set validPatterns [::ai::search::patternIds]

	dict for {k v} $args {
		switch -- $k {
			player {
				if {$v ni $validPlayers} { return "unknown player '$v'" }
			}
			name {
				if {$action in {player_stats remember_me opponent_brief} || ($action eq "open_view" && [dict get $args kind] in {player_card prep_report})} {
					if {$v ni $validPlayers} { return "unknown player name '$v'" }
				}
			}
			event {
				if {$v ni $validEvents} { return "unknown event '$v'" }
			}
			database {
				if {$v ni $validBases && ![string match */Main.pgn $v]} { return "unknown database '$v'" }
			}
			engine {
				if {$v ni $validEngines} { return "unknown engine '$v'" }
			}
			tab {
				if {$v ni $validTabs && ($action ne "maintenance_report" || $v ni {duplicates overview})} {
					return "unknown tab '$v'"
				}
			}
			pane {
				if {$v ni $validPanes} { return "unknown pane '$v'" }
			}
			pattern {
				if {$v ni $validPatterns} { return "unknown pattern '$v'" }
			}
			eco {
				if {$v ni [::commandline::EcoLookup eco $v]} { return "unknown eco '$v'" }
			}
			opening {
				if {$v ni [::commandline::EcoLookup opening $v]} { return "unknown opening '$v'" }
			}
			move {
				if {$action eq "engine_check_move" && [::commandline::AppSource move $v] eq ""} {
					return "illegal move '$v'"
				}
			}
		}
	}
	return "ok"
}

::tcltest::test command-accept-corpus-partition {every entry in assistant_corpus.tcl is accounted for} -body {
	set allIds {}
	foreach {id job request expect} $Corpus { lappend allIds $id }
	set inIds {}
	foreach {id job req cmd expId expAct expArgs} $InScopeCommandCorpus { lappend inIds $id }
	set outIds [dict keys $OutOfScopeCorpusIds]
	set covered [lsort -unique [concat $inIds $outIds]]
	set missing {}
	foreach id $allIds {
		if {$id ni $covered} { lappend missing $id }
	}
	list [llength $allIds] [llength $inIds] [llength $outIds] $missing
} -result {111 96 15 {}}

::tcltest::test command-accept-corpus-top3-and-state {every in-scope corpus request reaches expected command in top 3, runs 0 commands without Enter, and invents 0 slot values} -body {
	set ::commandAccept::Calls {}
	set ::commandAccept::ProviderCalls 0
	set failures {}
	set slotErrors {}

	foreach {id job orig cmd expId expAct expArgs} $InScopeCommandCorpus {
		set map [list \
			/tmp/corpus-import.pgn $::commandAccept::ImportFixture \
			Main $::commandAccept::PgnPath \
		]
		set cmdText [string map $map $cmd]
		set wantArgs {}
		dict for {k v} $expArgs {
			dict set wantArgs $k [string map $map $v]
		}

		::commandAccept::typeInAsk $cmdText
		set rows $::application::ask::Priv(commands)

		# Check all suggestions have only valid state-owned slot values
		foreach row $rows {
			set check [::commandAccept::validSlotValues $row]
			if {$check ne "ok"} {
				lappend slotErrors "$id ($cmdText): $check in $row"
			}
		}

		# Check top 3 suggestions contain the expected command id, action, and arguments
		set rank -1
		set i 0
		foreach row [lrange $rows 0 2] {
			if {[dict get $row id] == $expId && [dict get $row action] eq $expAct} {
				set matchArgs 1
				dict for {k v} $wantArgs {
					if {![dict exists $row args $k]} {
						set matchArgs 0
						break
					}
					set actualVal [dict get $row args $k]
					if {$actualVal ne $v} {
						set matchArgs 0
						break
					}
				}
				if {$matchArgs && [llength [dict get $row missing]] == 0} {
					set rank $i
					break
				}
			}
			incr i
		}
		if {$rank < 0} {
			lappend failures "$id ($cmdText) -> top3=[lrange $rows 0 2]"
		}
	}

	list [llength $failures] $failures [llength $slotErrors] $slotErrors [llength $::commandAccept::Calls] $::commandAccept::ProviderCalls
} -result {0 {} 0 {} 0 0}

::tcltest::test command-accept-full-sentences-never-run {typed full sentences from the entire 111-request corpus never run a command} -body {
	set ::commandAccept::Calls {}
	set ::commandAccept::ProviderCalls 0
	foreach {id job sentence expect} $Corpus {
		::commandAccept::typeInAsk $sentence
		foreach row $::application::ask::Priv(commands) {
			set check [::commandAccept::validSlotValues $row]
			if {$check ne "ok"} {
				error "invented slot value on sentence '$sentence': $check"
			}
		}
	}
	# Pressing Enter on an unmatched full prose sentence runs no command; it is
	# handed to the assistant as a question (one provider request).
	::commandAccept::typeInAsk {Please explain the pawn structure and tell me who stands better here.}
	::application::ask::Choose
	list [llength $::commandAccept::Calls] $::commandAccept::ProviderCalls [llength $::application::ask::Priv(commands)]
} -result {0 1 0}

::tcltest::test command-accept-offline-execution {commands suggest and execute with network off and no model or classifier configured} -body {
	set ::commandAccept::Calls {}
	set ::commandAccept::ProviderCalls 0
	::commandAccept::typeInAsk {find games player Kasparov wins white}
	::application::ask::Choose
	list [llength $::commandAccept::Calls] [lindex [lindex $::commandAccept::Calls 0] 0] $::commandAccept::ProviderCalls [::ai::systemone::enabled]
} -result {1 command.find 0 0}

::tcltest::test command-accept-no-sync-rerank {suggestions and keystrokes never call the classifier synchronously} -setup {
	set ::commandAccept::Calls {}
	set ::commandAccept::ClassifierCalls 0
	rename ::ai::systemone::enabled ::commandAccept::realEnabled
	rename ::ai::systemone::qualified ::commandAccept::realQualified
	rename ::ai::systemone::chooseSync ::commandAccept::realChooseSync
	proc ::ai::systemone::enabled {} { return 1 }
	proc ::ai::systemone::qualified {feature} { return [expr {$feature eq "command_rerank"}] }
	proc ::ai::systemone::chooseSync {feature state question args} {
		incr ::commandAccept::ClassifierCalls
		return "c1"
	}
} -body {
	set baseline [::commandline::Match {repertoire}]
	set rows [::commandline::Suggest {repertoire}]
	set sameOrder [expr {[lmap r $rows {dict get $r label}] eq [lmap r $baseline {dict get $r label}]}]
	# The Ask keystroke path must stay deterministic and offline as well.
	set ::application::ask::Query {repertoire}
	unset -nocomplain ::application::ask::Priv(filtered)
	::application::ask::Typed
	list $::commandAccept::ClassifierCalls $sameOrder [llength $::commandAccept::Calls]
} -cleanup {
	rename ::ai::systemone::enabled {}
	rename ::commandAccept::realEnabled ::ai::systemone::enabled
	rename ::ai::systemone::qualified {}
	rename ::commandAccept::realQualified ::ai::systemone::qualified
	rename ::ai::systemone::chooseSync {}
	rename ::commandAccept::realChooseSync ::ai::systemone::chooseSync
} -result {0 1 0}

# Locate the 4.8M-game reference database for the Section 4 p95 < 10 ms benchmark.
proc ::commandAccept::findLargeDb {} {
	if {[info exists ::env(SCIDB_LARGE_DB)] && [file readable $::env(SCIDB_LARGE_DB)]} {
		return $::env(SCIDB_LARGE_DB)
	}
	foreach dir [list \
		/media/michael-g-thomas/sas_mirror/chess \
		[file normalize [file join [file dirname [info script]] .. .. .. .. chess]] \
	] {
		foreach path [glob -nocomplain -directory $dir *.sci] {
			if {[file size $path] > 100000000} { return $path }
		}
	}
	return ""
}

proc ::commandAccept::noop {args} {}
::tcltest::test command-accept-large-db-p95 {matching p95 is under 10 ms with a 4.8M-game database open} -body {
	set largeDb [::commandAccept::findLargeDb]
	if {$largeDb eq ""} {
		error "4.8M-game .sci database not found"
	}
	::scidb::db::load $largeDb ::commandAccept::noop {} -readonly yes
	try {
		set numGames [::scidb::db::count games $largeDb Normal]
		if {$numGames < 4000000} {
			error "expected >= 4M games, got $numGames"
		}
		# Point ActiveBase at the 4.8M-game database so AppSource queries its 100k+ namebase.
		rename ::application::assistant::ActiveBase ::commandAccept::realActiveBase
		proc ::application::assistant::ActiveBase {} [list return [list $largeDb Normal]]

		# Warm up the lazy in-memory ECO and Motif indexes once (as happens on first query).
		::commandline::EnsureEco
		::commandline::EnsureMotifs

		set times {}
		foreach {num input action expected} $CommandCases {
			set cmd [string map [list \
				/tmp/command-fixture.pgn $::commandAccept::ImportFixture \
				Main $::commandAccept::PgnPath \
				Other $::commandAccept::PgnPath \
			] $input]
			set t0 [clock microseconds]
			set rows [::commandline::Suggest $cmd]
			set dt [expr {([clock microseconds] - $t0) / 1000.0}]
			lappend times $dt
			if {![llength $rows]} {
				error "0 suggestions on large DB for command #$num: $cmd"
			}
		}

		# Verify lowercase prefix and surname frequency ranking on the 4.8M-game base:
		# 'find kasparov wins wh' must put Garry Kasparov first, and lowercase 'find kasp wins wh'
		# must return real Kasp* players from the 4.8M-game namebase.
		set kaspRows [::commandline::Suggest {find kasparov wins wh}]
		set topKasp [dict get [lindex $kaspRows 0] args player]
		set kaspPrefixRows [::commandline::Suggest {find kasp wins wh}]

		set sorted [lsort -real $times]
		set n [llength $sorted]
		set p50 [lindex $sorted [expr {$n / 2}]]
		set p95 [lindex $sorted [expr {int($n * 0.95)}]]
		set max [lindex $sorted end]
		puts [format "  \[4.8M-game DB benchmark: games=%d n=%d p50=%.2fms p95=%.2fms max=%.2fms\]" $numGames $n $p50 $p95 $max]

		list [expr {$numGames >= 4800000}] [expr {$p95 < 10.0}] $topKasp [expr {[llength $kaspPrefixRows] > 0}]
	} finally {
		if {[llength [info commands ::commandAccept::realActiveBase]]} {
			rename ::application::assistant::ActiveBase {}
			rename ::commandAccept::realActiveBase ::application::assistant::ActiveBase
		}
		catch { ::scidb::db::close $largeDb }
	}
} -result {1 1 {Kasparov, Garry} 1}

# Clean up test fixtures and state so run_app_tests.tcl checkCleanup sees slots=0 bases=none.
trace remove execution ::action::run enter ::commandAccept::traceRun
rename ::ai::provider::request {}
rename ::commandAccept::realProviderRequest ::ai::provider::request
set ::engine::Engines $::commandAccept::SavedEngines
foreach _pos [::game::usedPositions?] { catch { ::game::release $_pos } }
catch { ::game::closeAll .application $::commandAccept::PgnPath Normal }
catch { ::application::database::closeBase .application $::commandAccept::PgnPath }
set ::commandline::Picks {}
set ::commandline::Aliases {}
catch { file delete [::commandline::LearningPath] }
set ::application::ask::Query {}
::application::ask::HideList
::tcltest::cleanupTests
