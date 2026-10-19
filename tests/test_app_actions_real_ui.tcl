# VAL-AI-001b: real assistant handlers with the real main window and widgets.
package require Tcl 8.5
package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]

namespace eval ::scidb::test::actions_real {
    variable Base ""
    variable Positions {}
    proc tool {name {argv {}}} {
        set reply [::application::assistant::runTool $name $argv]
        if {[string match "error:*" $reply]} { error "$name: $reply" }
        return $reply
    }
    proc setup {} {
        variable Base
        variable Positions {}
        ::scidb::test::actions::ready
        set Base [::scidb::test::actions::fixture]
    }
    proc openBase {} {
        variable Base
        tool open_database [list path $Base]
        update
        if {[::scidb::db::get name] ne $Base} { error "generated database is not active" }
    }
    proc rememberPosition {} {
        variable Positions
        lappend Positions [::scidb::game::current]
    }
    proc cleanup {} {
        variable Base
        variable Positions
        foreach pos [lsort -unique $Positions] {
            ::application::pgn::release $pos
            ::game::release $pos
        }
        set Positions {}
        if {$Base ne "" && [::scidb::db::get open? $Base]} {
            ::application::database::closeBase .application $Base
        }
        set Base ""
        file delete -force $::scidb::test::actions::Dir
    }
}

tcltest::test real-load-game-changes-board {open_game updates the model and the rendered board} -setup {
    ::scidb::test::actions_real::setup
    ::scidb::test::actions_real::openBase
    set before [::scidb::pos::fen]
} -body {
    ::scidb::test::actions_real::tool open_game {number 1 move 1 after white}
    ::scidb::test::actions_real::rememberPosition
    update
    list [expr {[::scidb::pos::fen] ne $before}] \
        [::scidb::test::actions::boardMatches $::scidb::test::actions::Fen]
} -cleanup {
    ::scidb::test::actions_real::cleanup
} -result {1 1}

tcltest::test real-open-database-changes-state {open_database adds a generated database to the actual switcher} -setup {
    ::scidb::test::actions_real::setup
    set switcher [::application::database::switcherWidget]
    set before [$switcher bases]
} -body {
    ::scidb::test::actions_real::openBase
    set base $::scidb::test::actions_real::Base
    list [expr {$base ni $before}] [expr {$base in [$switcher bases]}] \
        [::scidb::db::count games $base Normal]
} -cleanup {
    ::scidb::test::actions_real::cleanup
} -result {1 1 1}

tcltest::test real-game-list-row-selection {the generated database has a selectable real game-list row} -setup {
    ::scidb::test::actions_real::setup
    ::scidb::test::actions_real::openBase
    ::scidb::test::actions_real::tool switch_tab {tab database}
    update
    set twm $::application::database::Vars(games).twm
    set table [set ::application::database::games::${twm}::Priv(table)]
} -body {
    # This is the real game-list number control, including row selection and
    # its TableSelected event; no table or game-loading callbacks are stubbed.
    ::application::database::games::Goto $table 1
    ::scidb::test::actions_real::rememberPosition
    update
    list [::gamestable::selection $table] \
        [expr {[::scidb::game::fen] eq $::ai::setup::Start}] \
        [llength [::scidb::game::query mainline]]
} -cleanup {
    ::scidb::test::actions_real::cleanup
} -result {0 1 4}

tcltest::test real-start-engine-changes-state {start_engine starts a real UCI process and analysis search} -setup {
    ::scidb::test::actions_real::setup
    set savedEngines $::engine::Engines
    set savedFile $::scidb::file::engines
    set savedConfirm $::application::assistant::Priv(confirm)
    set runningBefore [::application::analysis::Running]
    set ::engine::Engines {}
    set ::scidb::file::engines [file join $::scidb::test::actions::Dir engines.dat]
    set ::application::assistant::Priv(confirm) ::scidb::test::actions::yes
    set program [expr {[info exists ::env(SCIDB_TEST_ENGINE)] ? $::env(SCIDB_TEST_ENGINE) : "/usr/games/stockfish"}]
    if {![file executable $program]} { error "real UCI engine unavailable: set SCIDB_TEST_ENGINE" }
    ::scidb::test::actions_real::tool add_engine [list path $program]
    set name [dict get [lindex $::engine::Engines 0] Name]
} -body {
    ::scidb::test::actions_real::tool start_engine [list engine $name lines 1 threads 1 hash 16]
    set running [::application::analysis::Running]
    set number [lindex $running end]
    ::scidb::test::actions::waitUntil {[llength [::application::analysis::lines $number]] > 0} 10000
    list [expr {[llength $running] == [llength $runningBefore] + 1}] \
        [::engine::active? $number] \
        [expr {[llength [::application::analysis::lines $number]] > 0}] \
        [winfo viewable $::application::analysis::NumberToTree($number)]
} -cleanup {
    foreach n [::application::analysis::Running] {
        if {$n ni $runningBefore} { ::application::analysis::stopEngine $n }
    }
    set ::engine::Engines $savedEngines
    set ::scidb::file::engines $savedFile
    set ::application::assistant::Priv(confirm) $savedConfirm
    ::options::hookWriter ::engine::WriteEngineOptions engines
    ::scidb::test::actions_real::cleanup
} -result {1 1 1 1}

# A nonzero initial ply is essential: clear(FEN) previously left the old
# navigation key behind, and PGN See/FindRange looked up a nonexistent mark.
foreach {suffix fen expected} {
    white {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 17}
          {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 17}
    black {rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 17}
          {rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 17}
} {
    tcltest::test real-set-position-fen-only-$suffix {FEN-only initializes board and PGN navigation together} -setup {
        ::scidb::test::actions_real::setup
    } -body [string map [list @FEN@ [list $fen] @EXPECTED@ [list $expected]] {
        ::scidb::test::actions_real::tool set_position [list fen @FEN@]
        ::scidb::test::actions_real::rememberPosition
        update
        set pos [::scidb::game::current]
        set key [::scidb::game::position key]
        set start [::scidb::game::position startKey]
        # Invoke the unguarded PGN routines: missing marks must still throw.
        set w $::application::pgn::Vars(pgn:$pos)
        ::application::pgn::FindRange $w $key $pos
        ::application::pgn::See $pos $key
        # The engine omits an en-passant square when no pawn can capture.
        list [::scidb::test::actions::boardMatches @EXPECTED@] \
            [expr {$key eq $start}] [llength [::scidb::game::query mainline]]
    }] -cleanup {
        ::scidb::test::actions_real::cleanup
    } -result {1 1 0}
}

tcltest::test real-set-position-with-moves {FEN plus moves still builds navigable PGN marks} -setup {
    ::scidb::test::actions_real::setup
} -body {
    set fen {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 17}
    set target [dict get [::ai::setup::validate -fen $fen -moves {e4 e5}] fen]
    ::scidb::test::actions_real::tool set_position [list fen $fen moves {e4 e5}]
    ::scidb::test::actions_real::rememberPosition
    update
    set pos [::scidb::game::current]
    set key [::scidb::game::position key]
    set w $::application::pgn::Vars(pgn:$pos)
    list [::scidb::test::actions::boardMatches $target] \
        [expr {$key in [$w mark names]}] [llength [::scidb::game::query mainline]] \
        [regexp {17\.} [$w get 1.0 end]]
} -cleanup {
    ::scidb::test::actions_real::cleanup
} -result {1 1 2 1}

tcltest::test real-open-dialog-maps-window {open_search maps its own advanced-search dialog} -setup {
    ::scidb::test::actions_real::setup
    set base [::scidb::db::get name]
    set variant [::application::database::currentVariant]
    set dialog [::application::database::AdvancedDialogName $base $variant]
    if {[winfo exists $dialog]} { error "test requires its own search dialog" }
} -body {
    ::scidb::test::actions_real::tool open_search {kind advanced}
    update
    list [winfo exists $dialog] [winfo viewable $dialog] [winfo viewable .application]
} -cleanup {
    if {[winfo exists $dialog]} { destroy $dialog }
    ::scidb::test::actions_real::cleanup
} -result {1 1 1}

tcltest::test real-switch-tab-changes-view {switch_tab selects and maps the requested notebook page} -setup {
    ::scidb::test::actions_real::setup
} -body {
    set result {}
    foreach tab {database board} {
        ::scidb::test::actions_real::tool switch_tab [list tab $tab]
        update
        lappend result [expr {[.application.nb select] eq ".application.nb.$tab"}] \
            [winfo viewable .application.nb.$tab]
    }
    set result
} -cleanup {
    ::scidb::test::actions_real::cleanup
} -result {1 1 1 1}

tcltest::test real-set-position-clean-baseline {repeated setup reuses slots and leaves no setup undo or stale checksum} -setup {
    ::scidb::test::actions_real::setup
    set slotsBefore [llength $::game::List]
} -body {
    set clean 1
    for {set i 0} {$i < 12} {incr i} {
        ::ai::setup::position -moves [expr {$i % 2 ? "e4 e5" : ""}]
        ::scidb::test::actions_real::rememberPosition
        set pos [::scidb::game::current]
        if {[::scidb::game::query undo] ne "" || [::scidb::game::query modified?]
            || [lindex $::game::List $pos 1] || [lindex $::game::List $pos 2]
            || [lindex $::game::List $pos 5] ne [::scidb::game::query checksum]} { set clean 0 }
    }
    list $clean [expr {[llength $::game::List] <= $slotsBefore + 1}]
} -cleanup {
    ::scidb::test::actions_real::cleanup
} -result {1 1}

tcltest::test real-set-position-variant-validation {validation uses the requested variant and preserves the active game} -setup {
    ::scidb::test::actions_real::setup
    set fen {4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1}
    set before [::scidb::pos::fen]
    set current [::scidb::game::current]
} -body {
    set normal [::ai::setup::validate -variant Normal -fen $fen -moves e5]
    set illegal [catch {::ai::setup::validate -variant Suicide -fen $fen -moves e5}]
    set suicide [::ai::setup::validate -variant Suicide -fen $fen -moves exd5]
    set checkedOpponent {4k3/8/8/8/8/8/4R3/4K3 w - - 0 1}
    set normalFen [catch {::ai::setup::validate -variant Normal -fen $checkedOpponent}]
    set suicideFen [catch {::ai::setup::validate -variant Suicide -fen $checkedOpponent}]
    list [dict get $normal plies] $illegal [dict get $suicide plies] $normalFen $suicideFen \
        [expr {[::scidb::pos::fen] eq $before && [::scidb::game::current] == $current}]
} -cleanup {
    ::scidb::test::actions_real::cleanup
} -result {1 1 1 1 0 1}

source [file join [file dirname [info script]] app_actions_real_probes.tcl]
::tcltest::cleanupTests
