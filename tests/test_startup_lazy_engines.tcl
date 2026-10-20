package require tcltest
set path [file join [file dirname [info script]] .. tcl engine.tcl]
if {[info exists env(STARTUP_ENGINE_SOURCE)]} {set path $env(STARTUP_ENGINE_SOURCE)}
set fd [open $path]
set script [read $fd]
close $fd
set start [string first {# --- Setup engines} $script]
if {$start < 0} {error {missing engine startup section}}
namespace eval engine {
    variable Engines {}
    proc setup {} {
        incr ::setupCalls
        set ::engine::Engines {fixture-engine}
    }
}
namespace eval load {variable Log {}; namespace eval mc {variable EngineSetupFailed failed}}
set setupCalls 0
# Exercise the actual startup section with a counted configuration reader.
eval [string range $script $start end]
tcltest::test lazy-engines-before-use {configuration is not parsed without a consumer} -body {
    set ::setupCalls
} -result 0
tcltest::test lazy-engines-first-read {the first list read initializes it exactly once} -body {
    set before $::setupCalls
    set engines $::engine::Engines
    list [expr {$::setupCalls - $before}] $engines $::engine::Engines $::setupCalls
} -result {1 fixture-engine fixture-engine 1}
tcltest::cleanupTests
