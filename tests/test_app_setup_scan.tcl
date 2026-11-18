package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
::scidb::test::actions::ready

# These cases save and restore product option arrays. Keep the snapshot in
# this file's namespace: a global array named "saved" would collide with the
# scalar many later files use for the same purpose (same process, one ::).
namespace eval ::scidb::test::setupscan {}

tcltest::test setup-scan-engine-subfolder {an engine unpacked in a folder named after it is found} -setup {
	set dir [file join [file normalize ~] engines igel-3.5 bin]
	file mkdir $dir
	set ::ext [expr {$::tcl_platform(platform) eq "windows" ? ".exe" : ""}]
	set exe [file join $dir igel-3.5$::ext]
	set f [open $exe w]; puts $f "#!/bin/sh"; close $f
	if {$::ext eq ""} { file attributes $exe -permissions 0755 }
	array set ::scidb::test::setupscan::saved [array get ::application::setupscan::Options]
	set ::application::setupscan::Options(rejected) {}
	set savedEngines $::engine::Engines
	set ::engine::Engines {}
} -body {
	dict get [::application::setupscan::EngineCandidates] igel
} -cleanup {
	set ::engine::Engines $savedEngines
	array set ::application::setupscan::Options [array get ::scidb::test::setupscan::saved]
	file delete -force [file join [file normalize ~] engines igel-3.5]
	unset ::ext
} -result [file join [file normalize ~] engines igel-3.5 bin igel-3.5[expr {$::tcl_platform(platform) eq "windows" ? ".exe" : ""}]]

tcltest::test setup-scan-engine-where {the scan names the folders of this platform} -body {
	expr {[string match *Program\ Files* [::application::setupscan::EngineWhere]] == ($::tcl_platform(platform) eq "windows")}
} -result 1


# Use a real, slow UCI subprocess so a modal probe is observable. Candidate
# enumeration has its own filesystem test; isolate this scan from host engines.
tcltest::testConstraint setupScanUnix [expr {$::tcl_platform(platform) eq "unix"}]
proc setupScanWatch {} {
    if {[winfo exists .application.wait] && [grab current] eq ".application.wait"} {
        set ::setupScanSawModal 1
    }
    set ::setupScanWatchId [after 20 setupScanWatch]
}
tcltest::test setup-scan-discover-then-explicit {startup reports candidates; explicit rerun still probes modally and adds the engine} -constraints setupScanUnix -setup {
    set savedEngines $::engine::Engines
    set savedOptions [array get ::application::setupscan::Options]
    set savedPriv [array get ::application::setupscan::Priv]
    set ::setupScanExe [file join [file normalize ~] scan-test-engine]
    set f [open $::setupScanExe w]
    puts $f {#!/bin/sh
sleep 1
while read line; do
    case "$line" in
        uci) printf 'id name SetupScanTest\nuciok\n';;
        isready) printf 'readyok\n';;
        quit|xboard) exit 0;;
    esac
done}
    close $f
    file attributes $::setupScanExe -permissions 0755
    rename ::application::setupscan::EngineCandidates ::application::setupscan::SavedEngineCandidates
    proc ::application::setupscan::EngineCandidates {} {return [list igel $::setupScanExe]}
    set ::setupScanSawModal 0
    setupScanWatch
} -body {
    ::application::setupscan::run 1
    set deadline [expr {[clock milliseconds]+15000}]
    while {$::application::setupscan::Priv(running) && [clock milliseconds]<$deadline} {update; after 10}
    set discovery [list [expr {$::engine::Engines eq $savedEngines}] $::setupScanSawModal]
    # Default run is what Information invokes; it must reset discovery-only.
    ::application::setupscan::run
    while {$::application::setupscan::Priv(running) && [clock milliseconds]<$deadline} {update; after 10}
    set found 0
    foreach e $::engine::Engines {
        if {[dict get $e Command] eq $::setupScanExe && "UCI" in [dict get $e Protocol]} {set found 1}
    }
    list $discovery $::setupScanSawModal $found $::application::setupscan::Priv(running) [grab current]
} -cleanup {
    after cancel $::setupScanWatchId
    rename ::application::setupscan::EngineCandidates {}
    rename ::application::setupscan::SavedEngineCandidates ::application::setupscan::EngineCandidates
    set ::engine::Engines $savedEngines
    ::engine::SaveEngineList
    array unset ::application::setupscan::Options
    array set ::application::setupscan::Options $savedOptions
    array unset ::application::setupscan::Priv
    array set ::application::setupscan::Priv $savedPriv
    file delete $::setupScanExe
} -result {{1 0} 1 1 0 {}}

# The startup pane must report an actual result even on machines with no
# candidates. Exercise both result branches, independent of host installs.
foreach discovery {empty found} {
    tcltest::test setup-scan-report-$discovery {discovery and rerun advice reach the assistant pane} -setup {
        ::application::openPane assistant false
        update
        set savedEngines $::engine::Engines
        set savedPriv [array get ::application::setupscan::Priv]
        set ::engine::Engines {}
        rename ::application::setupscan::EngineCandidates ::application::setupscan::SavedEngineCandidates
        set ::setupScanCandidates {}
        if {$discovery eq "found"} {
            set ::setupScanCandidates {stockfish {/example/stockfish-17.exe} crafty {/example/crafty.exe}}
        }
        proc ::application::setupscan::EngineCandidates {} {return $::setupScanCandidates}
        set textWidget $::application::assistant::Priv(text)
        set start [$textWidget index end-1c]
    } -body {
        ::application::setupscan::run 1
        set deadline [expr {[clock milliseconds]+15000}]
        while {$::application::setupscan::Priv(running) && [clock milliseconds]<$deadline} {update; after 10}
        set text [$textWidget get $start end]
        set expected {Chess engines: no new engine found; 0 already in the engine list.}
        if {$discovery eq "found"} {set expected {Chess engines: found stockfish-17.exe, crafty.exe.}}
        list [expr {[string first $expected $text]>=0}] \
            [expr {[string first {Done. Run this again any time from the Information tab.} $text]>=0}] \
            [expr {$::engine::Engines eq {}}] $::application::setupscan::Priv(running)
    } -cleanup {
        rename ::application::setupscan::EngineCandidates {}
        rename ::application::setupscan::SavedEngineCandidates ::application::setupscan::EngineCandidates
        set ::engine::Engines $savedEngines
        array unset ::application::setupscan::Priv
        array set ::application::setupscan::Priv $savedPriv
        unset ::setupScanCandidates
    } -result {1 1 1 0}
}

tcltest::cleanupTests
