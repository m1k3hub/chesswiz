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
unset -nocomplain env(SCIDB_AI_MODEL)
set env(SCIDB_AI_CLASSIFIER) off
set env(SCIDB_AI_ROUTE) off
set env(SCIDB_AI_TRIAGE) 0
set f [open [file join $env(SCIDB_USERDIR) config options.dat] w]
puts $f {namespace eval ::application {array set Options {assistant:startup 1}}}
puts $f {namespace eval ::tips {array set Options {mode neverShow}}}
close $f
# Observe this machine's real discovery result; a Unix fake executable is
# neither portable nor representative of a machine without new engines.
set argv {--single-process}
set argc 1
set scanMapped -1
set scanViolations {}
set scanSamples 0
set scanInteraction 0
set scanPrevious 0
set scanMaxGap 0
proc scanCheck {{event sample}} {
    if {$::scanMapped < 0} {return}
    set elapsed [expr {[clock milliseconds]-$::scanMapped}]
    set target [focus]
    set grab [grab current]
    puts [list OBSERVE $event ms $elapsed focus $target grab $grab]
    if {$grab ne {}} {lappend ::scanViolations [list grab $elapsed $grab]}
    if {$target ne {}} {
        set top [winfo toplevel $target]
        # The startup splash and Tk's hidden root window belong to this
        # application.  The splash exists only while the main window loads
        # and accepts no input (noActivates on Aqua), so the keyboard
        # returning to it is not another window stealing the user's focus.
        set ownSplash [expr {$top eq {.splash} && [winfo exists .splash]}]
        if {$top ne {.application} && $top ne {.} && !$ownSplash} {
            lappend ::scanViolations [list focus $elapsed $target]
        }
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
proc scanCandidates {command code result op} {
    if {$code != 0} {return}
    set ::scanCandidates $result
    set ::scanListed [string tolower [lmap e $::engine::Engines {
        set n [expr {[dict exists $e Name] ? [dict get $e Name] : ""}]
        if {[dict exists $e Identifier]} {append n " " [dict get $e Identifier]}
        set n
    }]]
}
proc scanDiscoveryReported {text} {
    if {![info exists ::scanCandidates]} {return 0}
    set names {}
    foreach {kind path} $::scanCandidates {
        if {[string first $kind $::scanListed] < 0} {lappend names [file tail $path]}
    }
    if {![llength $names]} {
        return [expr {[string first {Chess engines: no new engine found;} $text] >= 0}]
    }
    return [expr {[string first "Chess engines: found [join $names {, }]." $text] >= 0}]
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
        [scanDiscoveryReported $text] \
        [expr {[string first {Done. Run this again any time from the Information tab.} $text] >= 0}] \
        [expr {[$::scanEntry get] eq {x} && [focus] eq $::scanEntry}] \
        [expr {$::scanMaxGap < 1000}]]
    puts [list DISCOVERY candidates [expr {[info exists ::scanCandidates] ? $::scanCandidates : {unobserved}}] pane $text]
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
trace add execution ::application::setupscan::EngineCandidates leave scanCandidates
# Optional diagnostic timing, without replacing any startup operation.
if {[info exists env(STARTUP_SCAN_TRACE)]} {
    proc scanTrace {args} {puts [list TIMING [clock milliseconds] {*}$args]}
    foreach cmd {::application::sample::maybeOpen ::application::database::openBase ::scidb::db::load ::application::setupscan::EngineCandidates ::application::setupscan::Glob ::application::setupscan::StepSpeech ::application::setupscan::StepDatabases ::application::setupscan::StepFonts ::application::Startup2 ::load::startBackgroundData ::load::resumeBackgroundData ::load::backgroundData ::load::ensureEco ::load::LoadData ::load::load ::knowledge::Ensure ::scanSample} {
        trace add execution $cmd {enter leave} scanTrace
    }
}
vwait scanForever
