# Standalone, offline System One presentation contract tests.
package require tcltest 2.5
namespace eval ::util { proc source args {} }
namespace eval ::options { proc hookWriter args {} }
source [file join [file dirname [info script]] .. tcl ai-systemone.tcl]
::ai::systemone::configure -backend off
source [file join [file dirname [info script]] .. tcl app-explorer.tcl]
proc winfo args { return 1 }
rename ::application::explorer::Fen ::application::explorer::OriginalFen
proc ::application::explorer::Fen {} { return test-fen }
foreach cmd {ShowStatus ShowRows ShowTopGames} {
    rename ::application::explorer::$cmd ::application::explorer::Original$cmd
}
proc ::application::explorer::ShowStatus text { set ::status $text }
proc ::application::explorer::ShowRows rows { set ::rows $rows }
proc ::application::explorer::ShowTopGames games { set ::games $games }
rename ::ai::systemone::evaluateAsync ::ai::systemone::OriginalAsync
proc ::ai::systemone::evaluateAsync {state questions callback} {
    incr ::calls
    set ::request [list $state $questions]
    set ::callback $callback
}
set ::entry {moves {{e4 100 50 30 20 2400}} topGames {{A B 2000}}}
set ::application::explorer::Pane .pane
set ::calls 0
proc reply {label confidence} {
    {*}$::callback [dict create ok 1 answers [dict create explorer_focus \
        [dict create choice $label confidence $confidence]]]
}

tcltest::test focus-off {disabled classifier preserves original presentation} -body {
    ::application::explorer::Show $::entry
    list $::calls $::status $::rows $::games
} -result {0 {} {{e4 100 50 30 20 2400}} {{A B 2000}}}

# Configure a cloud preset, but all requests are intercepted above.
::ai::systemone::configure -backend typesafe
set ::env(SCIDB_AI_EXPLORER_FOCUS_MIN_CONFIDENCE) 0.8

tcltest::test focus-async {only the callback adds a bounded study prompt} -body {
    ::application::explorer::Show $::entry
    set before $::status
    reply samples 0.9
    list $before $::status [expr {$::application::explorer::Shown eq $::entry}] \
        [dict get [lindex $::request 1] explorer_focus type]
} -result [list {} $::application::explorer::mc::FocusSamples 1 choice]

foreach {name label confidence} {low samples 0.79 unknown winning 1 malformed results NaN abstain none 1} {
    tcltest::test focus-$name {unusable answer retains original display} -body {
        ::application::explorer::Show $::entry
        reply $label $confidence
        set ::status
    } -result {}
}
foreach {label message} [list results $::application::explorer::mc::FocusResults examples $::application::explorer::mc::FocusExamples] {
    tcltest::test focus-success-$label {fixed prompt leaves table and games intact} -body {
        ::application::explorer::Show $::entry
        reply $label 1
        list $::status $::rows $::games
    } -result [list $message [dict get $::entry moves] [dict get $::entry topGames]]
}
tcltest::test focus-error {unreachable classifier keeps original display} -body {
    ::application::explorer::Show $::entry
    {*}$::callback {ok 0 error timeout}
    {*}$::callback {ok 1 answers {}}
    set ::status
} -result {}
tcltest::test focus-threshold {per-feature threshold is honored} -body {
    set ::env(SCIDB_AI_EXPLORER_FOCUS_MIN_CONFIDENCE) 0.95
    ::application::explorer::Show $::entry
    reply samples 0.9
    set ::status
} -cleanup {
    set ::env(SCIDB_AI_EXPLORER_FOCUS_MIN_CONFIDENCE) 0.8
} -result {}
foreach reason {generation source fen closed disabled} {
    tcltest::test focus-stale-$reason {late replies cannot alter another view} -body {
        ::application::explorer::Show $::entry
        switch $reason {
            generation { ::application::explorer::Show {} }
            source { set ::application::explorer::Options(source) lichess }
            fen { rename ::application::explorer::Fen {}; proc ::application::explorer::Fen {} { return other } }
            closed { set ::application::explorer::Pane {} }
            disabled { set ::application::explorer::Options(enabled) 0 }
        }
        reply examples 1
        set ::status
    } -cleanup {
        set ::application::explorer::Options(source) masters
        set ::application::explorer::Options(enabled) 1
        set ::application::explorer::Pane .pane
        rename ::application::explorer::Fen {}
        proc ::application::explorer::Fen {} { return test-fen }
    } -result {}
}
tcltest::test focus-no-examples {absent examples cannot be selected} -body {
    ::application::explorer::Show {moves {{e4 100 50 30 20 2400}} topGames {}}
    reply examples 1
    set ::status
} -result {}
tcltest::test focus-qualified {uncalibrated backend makes no request} -body {
    unset ::env(SCIDB_AI_EXPLORER_FOCUS_MIN_CONFIDENCE)
    set override [expr {[info exists ::env(SCIDB_AI_UNCALIBRATED)] ? $::env(SCIDB_AI_UNCALIBRATED) : ""}]
    unset -nocomplain ::env(SCIDB_AI_UNCALIBRATED)
    set before $::calls
    ::application::explorer::Show $::entry
    set result [list [expr {$before == $::calls}] $::status]
    if {$override ne ""} { set ::env(SCIDB_AI_UNCALIBRATED) $override }
    set result
} -result {1 {}}
tcltest::cleanupTests
