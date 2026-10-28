package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
namespace eval ::scidb::test::dialogargs {
    proc call {id args} {
        set result [::knowledge::RunAction $id $args]
        if {[string match error:* $result]} { error $result }
        return $result
    }
}
tcltest::test dialog-args-keyboard {direct key edits change actual bindings, reset and list; invalid ids fail} -setup {
    ::scidb::test::actions::ready
} -body {
    set original [::application::keyEditor::CurrentKey app-help]
    ::scidb::test::dialogargs::call menu.edit.keyboard operation set action app-help key Control-Shift-F12
    set changed [::application::keyEditor::CurrentKey app-help]
    set binding [bind .application <Control-Shift-F12>]
    set listed [::scidb::test::dialogargs::call menu.edit.keyboard operation list]
    set bad [::knowledge::RunAction menu.edit.keyboard {operation reset action nonexistent}]
    ::scidb::test::dialogargs::call menu.edit.keyboard operation reset action app-help
    set reset [::application::keyEditor::CurrentKey app-help]
    ::scidb::test::dialogargs::call menu.edit.keyboard operation set action app-help key Control-Shift-F12
    ::scidb::test::dialogargs::call menu.edit.keyboard operation reset_all
    list $changed [expr {$binding ne ""}] [dict get $listed app-help] \
        [string match {error:*unknown key action*} $bad] [expr {$reset eq $original}] \
        [expr {[::application::keyEditor::CurrentKey app-help] eq $original}] \
        [winfo exists .application.shortcutPreferences]
} -cleanup {
    ::application::keyEditor::ResetAll
} -result {Control-Shift-F12 1 Control-Shift-F12 1 1 1 0}

tcltest::test dialog-args-pgn-flags {every export option changes native export bitmask without dialog; reset restores defaults} -setup {
    ::scidb::test::actions::ready
    set saved [array get ::export::Values]
} -body {
    set n 0
    foreach option [dict keys [::scidb::test::dialogargs::call menu.edit.preferences.pgn operation list]] {
        foreach other [dict keys [::scidb::test::dialogargs::call menu.edit.preferences.pgn operation list]] {
            ::scidb::test::dialogargs::call menu.edit.preferences.pgn operation set option $other value 0
        }
        set field $option
        if {$field eq "compatibility_format"} {set field use_chessbase_format}
        set mask [expr {1 << $::export::Flags(pgn,$field)}]
        ::scidb::test::dialogargs::call menu.edit.preferences.pgn operation set option $option value 0
        if {[::export::getPgnFlags] & $mask} {error "flag remains set: $option value=$::export::Values(pgn,flag,$field) bit=$::export::Flags(pgn,$field) flags=[::export::getPgnFlags]"}
        ::scidb::test::dialogargs::call menu.edit.preferences.pgn operation set option $option value 1
        if {!([::export::getPgnFlags] & $mask)} {error "flag missing: $option"}
        incr n
    }
    ::scidb::test::dialogargs::call menu.edit.preferences.pgn operation reset
    foreach field [array names ::export::Defaults pgn,flag,*] {
        if {$::export::Values($field) != $::export::Defaults($field)} {error "default not restored: $field"}
    }
    set bad [::knowledge::RunAction menu.edit.preferences.pgn {operation set option unknown value 1}]
    list [expr {$n >= 25}] [winfo exists .application.pgnOptions] [string match error:* $bad]
} -cleanup {
    array set ::export::Values $saved
} -result {1 0 1}

tcltest::test dialog-args-close {eight specific window controls close their actual windows through assistant dispatch} -setup {
    ::scidb::test::actions::ready
} -body {
    set windows {about .application.infoDialog correspondence .application.corrGames engine_dictionary .application.engineDict iccf .application.iccfSettings keyboard .application.shortcutPreferences pgn .application.pgnOptions player_dictionary .application.playerDict review_engine .application.__aiengine__}
    set closed 0
    foreach {dialog window} $windows {
        toplevel $window
        ::scidb::test::dialogargs::call view.dialog.close dialog $dialog
        if {[winfo exists $window]} {error "window remains: $window"}
        incr closed
    }
    list $closed [string match error:* [::knowledge::RunAction view.dialog.close {dialog unknown}]]
} -result {8 1}

tcltest::test dialog-args-log {clear deletes real log text; close withdraws the log and closes the native engine log} -setup {
    ::scidb::test::actions::ready
    ::log::open .application
    ::engine::openEngineLog .application
} -body {
    set text $::log::Log.top.text
    $text insert end "generated log entry"
    set engine .application.engineLog.top.text
    $engine configure -state normal
    $engine insert end "generated engine entry"
    $engine configure -state disabled
    ::scidb::test::dialogargs::call app-log operation clear
    ::scidb::test::dialogargs::call menu.tools.engine_console operation clear
    set empty [list [$text get 1.0 end-1c] [$engine get 1.0 end-1c]]
    ::scidb::test::dialogargs::call app-log operation close
    ::scidb::test::dialogargs::call menu.tools.engine_console operation close
    list $empty [wm state $::log::Log] [winfo exists .application.engineLog]
} -result {{{} {}} withdrawn 0}
tcltest::test dialog-args-tactics {real PGN load, legal move, solution, next and status run without trainer window} -setup {
    ::scidb::test::actions::ready
    set path [file join [file dirname [info script]] tmp-app puzzle-[pid].pgn]
    set f [open $path w]
    puts $f {[Event "Generated puzzle"]
[Result "*"]
[SetUp "1"]
[FEN "8/8/8/4k3/8/8/8/4KQ2 w - - 0 1"]

1. Qf5+ *}
    close $f
} -body {
    set started [::scidb::test::dialogargs::call menu.training.tactics operation open filename $path]
    set solved [::scidb::test::dialogargs::call menu.training.tactics operation move move Qf5+]
    ::scidb::test::dialogargs::call menu.training.tactics operation next
    set solution [::scidb::test::dialogargs::call menu.training.tactics operation solution]
    set status [::scidb::test::dialogargs::call menu.training.tactics operation status]
    set bad [::knowledge::RunAction menu.training.tactics {operation retry}]
    list [dict get $started state] [dict get $solved state] \
        [expr {[dict get $solution fen] ne [dict get $started fen]}] \
        [expr {$status eq $solution}] [string match {error:*no wrong move*} $bad] [winfo exists .tactics]
} -cleanup {
    file delete $path
} -result {playing done 1 1 1 0}
namespace eval ::scidb::test::dialogargs {
    variable closed 0
    proc closeWhenMapped {dialog window tries} {
        variable closed
        if {[winfo exists $window]} {
            call view.dialog.close dialog $dialog
            set closed 1
        } elseif {$tries > 0} {
            after 20 [list ::scidb::test::dialogargs::closeWhenMapped $dialog $window [expr {$tries-1}]]
        } else {set closed -1}
    }
}
tcltest::test dialog-args-native-close {assistant close control operates on the real keyboard and export preference windows} -setup {
    ::scidb::test::actions::ready
} -body {
    set result {}
    foreach {id dialog window} {
        menu.edit.keyboard keyboard .application.shortcutPreferences
        menu.edit.preferences.pgn pgn .application.pgnOptions
    } {
        set ::scidb::test::dialogargs::closed 0
        after 20 [list ::scidb::test::dialogargs::closeWhenMapped $dialog $window 200]
        ::scidb::test::dialogargs::call $id
        set deadline [expr {[clock milliseconds]+5000}]
        while {!$::scidb::test::dialogargs::closed && [clock milliseconds] < $deadline} {update; after 10}
        lappend result $::scidb::test::dialogargs::closed [winfo exists $window]
    }
    return $result
} -result {1 0 1 0}
tcltest::test dialog-args-repertoire {start a real generated deck, answer and persist all three grades; stop and close without chooser} -setup {
    ::scidb::test::actions::ready
    ::application::assistant::runTool open_database [list path [::scidb::test::actions::fixture]]
    ::application::assistant::runTool open_game {number 1}
    rename ::ai::decide ::ai::decide_dialogargs_saved
    set deck [::reptrainer::deckFile current-game]
    file delete $deck
} -body {
    set results {}
    foreach grade {1 2 3} {
        # Each trial owns a fresh deck but uses the real generated source game.
        ::reptrainer::stop
        file delete $deck
        ::application::assistant::runTool open_game {number 1}
        set start [::scidb::test::dialogargs::call menu.training.repertoire operation start side white]
        set card [dict get $start card]
        set answer [lindex [dict get $card moves] 0]
        set graded [::scidb::test::dialogargs::call menu.training.repertoire operation move move $answer]
        if {[dict get $graded state] ne "grade"} {error "answer did not reach grade state"}
        ::scidb::test::dialogargs::call menu.training.repertoire operation grade grade $grade
        set persisted [::reptrainer::loadDeck $deck]
        set record [dict get $persisted cards [::reptrainer::Key [dict get $card fen]]]
        lappend results [dict get $record interval] [dict get $record reps]
    }
    ::scidb::test::dialogargs::call menu.training.repertoire operation stop
    set stopped [::scidb::test::dialogargs::call menu.training.repertoire operation status]
    ::scidb::test::dialogargs::call menu.training.repertoire operation close
    list $results [dict get $stopped running] [winfo exists .application.__reptrainer__] \
        [string match {error:*no correct answer*} [::knowledge::RunAction menu.training.repertoire {operation grade grade 2}]]
} -cleanup {
    ::reptrainer::stop
    rename ::ai::decide_dialogargs_saved ::ai::decide
    file delete $deck
} -result {{1 1 1 1 4 1} 0 0 1}
tcltest::test dialog-args-tactics-retry {real CPU engine rejects a queen blunder; retry restores entire puzzle session position} -setup {
    ::scidb::test::actions::ready
    set path [file join [file dirname [info script]] tmp-app puzzle-retry-[pid].pgn]
    set f [open $path w]
    puts $f {[Event "Generated retry puzzle"]
[Result "*"]
[SetUp "1"]
[FEN "8/8/8/4k3/8/8/8/4KQ2 w - - 0 1"]

1. Qe2+ *}
    close $f
    set config [array get ::ai::engine::Config]
    ::ai::engine::configure -engine [::scidb::test::actions::engineProgram] -timeout 15000
} -body {
    set start [::scidb::test::dialogargs::call menu.training.tactics operation open filename $path]
    set wrong [::scidb::test::dialogargs::call menu.training.tactics operation move move Qf5+]
    set retried [::scidb::test::dialogargs::call menu.training.tactics operation retry]
    list [dict get $wrong state] [dict get $retried state] [dict get $retried retries] \
        [expr {[dict get $start fen] eq [dict get $retried fen]}] \
        [dict get [dict get $::tactics::progress [dict get $wrong puzzle id]] status]
} -cleanup {
    ::ai::engine::shutdown
    array set ::ai::engine::Config $config
    file delete $path
} -result {wrong playing 1 1 failed}
tcltest::cleanupTests
