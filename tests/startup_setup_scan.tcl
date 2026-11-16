# Ordinary fresh startup: run outside run_app_tests, which suppresses scans.
# xvfb-run -a -s '-screen 0 1920x1080x24' src/tkchesswiz tests/startup_setup_scan.tcl
# Start a WM in the Xvfb display to exercise real focus events.
set scanRoot [file normalize [file join [file dirname [info script]] ..]]
set scanHome [file join $scanRoot tests tmp-app startup-setup-scan-[pid]]
file mkdir [file join $scanHome .chesswiz config]
set env(HOME) $scanHome
set env(SCIDB_USERDIR) [file join $scanHome .chesswiz]
foreach key [array names env] {
    if {[string match *API_KEY $key] || [string match CHESSWIZ_NO_* $key]} {unset env($key)}
}
set env(SCIDB_AI_PROVIDER) openai
set env(SCIDB_AI_MODEL) {}
set env(SCIDB_AI_CLASSIFIER) off
set env(SCIDB_AI_ROUTE) off
set env(SCIDB_AI_TRIAGE) 0
set f [open [file join $env(SCIDB_USERDIR) config options.dat] w]
puts $f {namespace eval ::application {array set Options {assistant:startup 1}}}
puts $f {namespace eval ::tips {array set Options {mode neverShow}}}
close $f
# Discoverable on hosts without engines. Deliberately slow: startup should
# report this executable, leaving the protocol probe for explicit setup.
file mkdir [file join $scanHome bin]
set f [open [file join $scanHome bin igel] w]
puts $f {#!/bin/sh
sleep 2
while read line; do
    case "$line" in
        uci) printf 'id name Startup Test Engine\nuciok\n';;
        isready) printf 'readyok\n';;
        quit) exit 0;;
        xboard) exit 0;;
    esac
done}
close $f
file attributes [file join $scanHome bin igel] -permissions 0755
set argv {--single-process}
set argc 1
set scanMapped -1
set scanViolations {}
set scanSamples 0
set scanInteraction 0
set scanPrevious -1
set scanMaxGap 0
proc scanCheck {{event sample}} {
    if {$::scanMapped < 0} {return}
    set elapsed [expr {[clock milliseconds]-$::scanMapped}]
    set target [focus]
    set grab [grab current]
    puts [list OBSERVE $event ms $elapsed focus $target grab $grab]
    if {$grab ne {}} {lappend ::scanViolations [list grab $elapsed $grab]}
    if {$target ne {} && [winfo toplevel $target] ne {.application}} {
        lappend ::scanViolations [list focus $elapsed $target]
    }
    if {[winfo exists .application.wait]} {lappend ::scanViolations [list wait $elapsed]}
}
proc scanSample {} {
    scanCheck
    incr ::scanSamples
    set elapsed [expr {[clock milliseconds]-$::scanMapped}]
    if {$::scanPrevious >= 0} {set ::scanMaxGap [expr {max($::scanMaxGap,$elapsed-$::scanPrevious)}]}
    set ::scanPrevious $elapsed
    if {$elapsed >= 6000 && !$::scanInteraction} {
        set ::scanInteraction 1
        set ::scanEntry [::application::ask::Entry]
        focus -force $::scanEntry
        event generate $::scanEntry <KeyPress-x>
        ::menu::Do board-flip
        scanCheck interaction
    }
    if {$elapsed >= 15000} {scanFinish; return}
    after 25 scanSample
}
proc scanMap {w} {
    if {$w ne {.application} || $::scanMapped >= 0} {return}
    set ::scanMapped [clock milliseconds]
    scanCheck first-map
    after 0 scanSample
}
proc scanFinish {} {
    set text [$::application::assistant::Priv(text) get 1.0 end]
    set checks [list \
        [expr {$::scanMapped >= 0 && $::scanSamples >= 100}] \
        [expr {![llength $::scanViolations]}] \
        [::application::assistant::panel::NoModel] \
        [::menu::PaneChecked assistant] \
        $::application::setupscan::Options(done) \
        [expr {!$::application::setupscan::Priv(running)}] \
        [expr {[string first {Chess engines: found} $text] >= 0 && [string first igel $text] >= 0}] \
        [expr {[string first {run setup again from the Information tab} $text] >= 0}] \
        [expr {[$::scanEntry get] eq {x} && [focus] eq $::scanEntry}] \
        [expr {$::scanMaxGap < 1000}]]
    puts [list STARTUP-SCAN checks $checks samples $::scanSamples max_gap_ms $::scanMaxGap violations $::scanViolations]
    flush stdout
    exit [expr {0 in $checks}]
}
bind all <Map> {+scanMap %W}
bind all <FocusIn> {+scanCheck focus-in}
after 30000 {puts stderr {STARTUP-SCAN timeout}; exit 1}
set scanBundle [file join $scanRoot tcl chesswiz]
if {[info exists env(STARTUP_SCAN_BUNDLE)]} {set scanBundle $env(STARTUP_SCAN_BUNDLE)}
source $scanBundle
# Suppress only the unrelated first-language wizard, as startup_timing does.
# Greet, firstStart and every scan step remain intact.
set ::scidb::dir::setup 0
vwait scanForever
