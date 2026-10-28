# P6: deterministic UI dispatch plus a real engine/board/repertoire-copy loop.
package require tcltest 2.5
namespace eval ::scidb::test::p6 {
    variable program /usr/games/stockfish
    if {[info exists ::env(SCIDB_TEST_ENGINE)]} {set program $::env(SCIDB_TEST_ENGINE)}
    if {![file executable $program]} {set program [lindex [auto_execok stockfish] 0]}
}
tcltest::testConstraint p6Engine [file executable $::scidb::test::p6::program]
proc ::scidb::test::p6::waitUntil {condition {timeout 20000}} {
    for {set elapsed 0} {$elapsed < $timeout} {incr elapsed 50} {
        if {[uplevel 1 [list expr $condition]]} { return 1 }
        after 50 {set ::scidb::test::p6::tick 1}
        vwait ::scidb::test::p6::tick
    }
    error "Timed out: $condition"
}

tcltest::test p6-pv-notation {full candidates accept move numbers and figurines} -body {
    list [::application::analysis::LineMoves {12...♞f6 13. ♘c3 e5}] \
        [::application::analysis::LineMoves {1.e4 e5 2.Nf3}]
} -result {{Nf6 Nc3 e5} {e4 e5 Nf3}}

tcltest::test p6-report-row {opening report dispatch uses its captured move} -setup {
    ttk::treeview .p6rows -columns {row identity move}
    .p6rows insert {} end -id row0 -values {0 identity e4}
    .p6rows selection set row0
    set ::application::database::OpeningPrepData(.p6,tv) .p6rows
    set ::application::database::OpeningPrepData(.p6,positionText) [::scidb::pos::fen]
    rename ::move::addMove ::scidb::test::p6::realAdd
    rename ::application::analysis::AnalyzeCurrentPosition ::scidb::test::p6::realAnalyze
    proc ::move::addMove {args} {set ::scidb::test::p6::played $args}
    proc ::application::analysis::AnalyzeCurrentPosition {} {set ::scidb::test::p6::analyzed 1}
} -body {
    ::application::database::OpeningPrepAnalyzeSelectedMove .p6
    list $::scidb::test::p6::played $::scidb::test::p6::analyzed
} -cleanup {
    rename ::move::addMove {}; rename ::scidb::test::p6::realAdd ::move::addMove
    rename ::application::analysis::AnalyzeCurrentPosition {}
    rename ::scidb::test::p6::realAnalyze ::application::analysis::AnalyzeCurrentPosition
    destroy .p6rows
    array unset ::application::database::OpeningPrepData .p6,*
} -result {{menu e4} 1}

tcltest::test p6-tree-novelty-row {tree and highlighted novelty rows share the analysis action} -setup {
    rename ::scidb::tree::move ::scidb::test::p6::treeMove
    rename ::move::addMove ::scidb::test::p6::realAdd
    rename ::application::analysis::AnalyzeCurrentPosition ::scidb::test::p6::realAnalyze
    proc ::scidb::tree::move {row} {return e4}
    proc ::move::addMove {args} {set ::scidb::test::p6::played $args}
    proc ::application::analysis::AnalyzeCurrentPosition {} {set ::scidb::test::p6::analyzed 1}
} -body {
    ::context::Command c8.analyze [dict create table .tree row 0]
    list $::scidb::test::p6::played $::scidb::test::p6::analyzed
} -cleanup {
    rename ::scidb::tree::move {}; rename ::scidb::test::p6::treeMove ::scidb::tree::move
    rename ::move::addMove {}; rename ::scidb::test::p6::realAdd ::move::addMove
    rename ::application::analysis::AnalyzeCurrentPosition {}
    rename ::scidb::test::p6::realAnalyze ::application::analysis::AnalyzeCurrentPosition
} -result {{menu e4} 1}

tcltest::test p6-text-report-stale {an old opening report cannot analyze a move on a different board} -setup {
    rename ::dialog::info ::scidb::test::p6::realInfo
    proc ::dialog::info {args} {set ::scidb::test::p6::notice $args}
    text .p6text
} -body {
    set fen [::scidb::pos::fen]
    ::application::tree::openingreport::AnalyzeRow .p6text e4 stale-fen
    list [expr {$fen eq [::scidb::pos::fen]}] \
        [string match {*board position changed*} $::scidb::test::p6::notice]
} -cleanup {
    destroy .p6text
    rename ::dialog::info {}; rename ::scidb::test::p6::realInfo ::dialog::info
} -result {1 1}

tcltest::test p6-live-loop {analysis starts, resumes, plays a PV and pins a complete candidate without changing the board game} -constraints p6Engine -setup {
    ::scidb::test::p6::waitUntil {$::application::Vars(ready)}
    catch {destroy .tipoftheday}
    set trialStarted [expr {![::game::trialMode?]}]
    if {$trialStarted} {::game::flipTrialMode}
    set oldEngines $::engine::Engines
    set oldFile $::scidb::file::engines
    set oldConfirm $::application::assistant::Priv(confirm)
    set ::engine::Engines {}
    set ::scidb::file::engines [file join [file dirname [info script]] tmp-app roadmap-partial p6 engines.dat]
    proc ::scidb::test::p6::confirm {args} {return 1}
    set ::application::assistant::Priv(confirm) ::scidb::test::p6::confirm
    set program $::scidb::test::p6::program
    ::application::assistant::runTool add_engine [list path $program]
    set name [dict get [lindex $::engine::Engines 0] Name]
    rename ::application::pgn::saveGame ::scidb::test::p6::realSave
    proc ::application::pgn::saveGame {mode base} {
        set ::scidb::test::p6::saved [::scidb::game::toPGN modified]
    }
} -body {
    ::application::analysis::AnalyzeCurrentPosition
    set number [lindex [::application::analysis::Running] 0]
    set tree $::application::analysis::NumberToTree($number)
    namespace upvar ::application::analysis ${tree}::Vars Vars
    ::scidb::test::p6::waitUntil {[llength [::application::analysis::BestLine $tree]] > 0}
    set Vars(engine:locked) 1
    ::application::analysis::Stop $tree
    ::application::analysis::AnalyzeCurrentPosition
    ::scidb::test::p6::waitUntil {[llength [::application::analysis::BestLine $tree]] > 0}
    set resumed [list $Vars(engine:locked) $Vars(engine:stopped) $Vars(engine:pause)]
    # The existing left-click binding plays the first move of the clicked PV row.
    ::application::openPane analysis:[::application::mapToTerminalNumber $number] false
    update
    set before [::scidb::pos::fen]
    lassign [$tree item bbox Line0 Moves] x1 y1 x2 y2
    ::application::analysis::AddMove $tree [expr {$x1+2}] [expr {($y1+$y2)/2}] 0
    set played [expr {[::scidb::pos::fen] ne $before}]
    ::scidb::test::p6::waitUntil {[::scidb::engine::bound? [::engine::id $number]]}
    ::scidb::test::p6::waitUntil {[llength [::application::analysis::BestLine $tree]] > 0}
    # A first depth-one UCI result may contain just one ply. Wait for the
    # multi-move candidate this test pins, rather than sampling that first PV.
    ::scidb::test::p6::waitUntil {[llength [::application::analysis::LineMoves [lindex [lindex [::application::analysis::BestLine $tree] 1] 8]]] > 1}
    ::application::analysis::Stop $tree
    set fen [::scidb::pos::fen]
    set pgn [::scidb::game::toPGN modified]
    # Exercise the selected-row context action, including the existing destination chooser.
    rename ::application::database::repertoireBases ::scidb::test::p6::realBases
    proc ::application::database::repertoireBases {args} {return {p6-repertoire}}
    lassign [::application::analysis::BestLine $tree] row line
    set moves [::application::analysis::LineMoves [lindex $line 8]]
    ::context::Command c6.pin_repertoire [dict create tree $tree lineId $row]
    set saved $::scidb::test::p6::saved
    list $resumed $played [expr {[llength $moves] > 1}] \
        [expr {[string first [lindex $moves end] $saved] >= 0}] \
        [expr {$fen eq [::scidb::pos::fen]}] \
        [expr {$pgn eq [::scidb::game::toPGN modified]}]
} -cleanup {
    if {[info exists number]} {::application::analysis::stopEngine $number}
    if {[llength [info commands ::scidb::test::p6::realBases]]} {
        rename ::application::database::repertoireBases {}
        rename ::scidb::test::p6::realBases ::application::database::repertoireBases
    }
    rename ::application::pgn::saveGame {}; rename ::scidb::test::p6::realSave ::application::pgn::saveGame
    file delete -force $::scidb::file::engines
    set ::engine::Engines $oldEngines
    set ::scidb::file::engines $oldFile
    set ::application::assistant::Priv(confirm) $oldConfirm
    ::options::hookWriter ::engine::WriteEngineOptions engines
    if {$trialStarted} {::game::flipTrialMode}
} -result {{0 0 0} 1 1 1 1 1}

tcltest::cleanupTests
