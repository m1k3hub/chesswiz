# Run headless: xvfb-run -a tclsh tests/test_sample_startup.tcl
package require tcltest 2.5
set root [file normalize [file join [file dirname [info script]] ..]]
set work [file join $root tests tmp-app sample-startup-[pid]]
file mkdir $work
set binary [expr {[info exists ::env(CHESSWIZ_TEST_BINARY)] ? $::env(CHESSWIZ_TEST_BINARY) : [file join $root src tkchesswiz]}]
set shared [file join $work share]
file mkdir $shared
# Use installed application resources, but install the sample into an isolated
# share directory. No files in the actual installation or profile are changed.
foreach f [glob -directory /usr/local/share/chesswiz *] {
    if {[file tail $f] ne "sample" && ![file exists [file join $shared [file tail $f]]]} {
        file link -symbolic [file join $shared [file tail $f]] $f
    }
}
exec make -s -C [file join $root tcl] install-sample SHAREDIR=$shared
set probe [file join $work probe.tcl]
set ch [open $probe w]
puts $ch {
proc check {condition message} {
    if {![uplevel 1 [list expr $condition]]} { error $message }
}
proc verify {} {
    if {[catch {
        set sample [file join $::scidb::dir::share sample "Sample games.sci"]
        check {[::scidb::db::get open? $sample]} "sample is not open after startup"
        check {[::scidb::db::get readonly? $sample]} "sample is writable"
        check {[$::application::database::Vars(switcher) contains? $sample]} "sample absent from switcher"
        set count [::scidb::db::count games $sample Normal]
        check {$count >= 2000 && $count <= 5000} "sample count $count"
        check {[::scidb::tree::get] eq $sample} "sample is not the explorer reference"
        ::application::tree::DoSearch $::application::tree::Vars(table)
        set deadline [expr {[clock milliseconds] + 15000}]
        while {![::scidb::tree::isUpToDate?] && [clock milliseconds] < $deadline} { after 50; update }
        set rows [::scidb::tree::fetch]
        check {[llength $rows] > 3} "explorer has no opening moves: $rows"
        ::reptrainer::open .application
        set sources $::reptrainer::Vars(sources)
        check {[lsearch -exact -index 1 $sources $sample] >= 0} "trainer does not list sample"
        check {[lindex $sources $::reptrainer::Vars(sourceIndex) 1] eq $sample} "trainer does not select sample"
        ::reptrainer::Close $::reptrainer::Vars(dlg)
        ::application::sample::maybeOpen .application
        set log [.application.log.top.text get 1.0 end]
        check {[regexp -all {Sample games: opened read-only} $log] == 1} "duplicate or missing sample log entry"
        if {$::env(SAMPLE_MODE) eq "fresh"} {
            set cards [::reptrainer::buildFromBase $sample Normal white [clock seconds]]
            check {[llength $cards] > 0} "sample produces no training cards"
        }
        if {$::env(SAMPLE_MODE) eq "remove"} {
            ::application::database::removeRecentFile $sample
            set ch [open [file join $::scidb::dir::config options.dat] w]
            ::application::sample::WriteOptions $ch
            close $ch
        }
        puts "SAMPLE OK games=$count rows=[llength $rows]"
    } message options]} {
        puts stderr "SAMPLE FAIL: $message\n[dict get $options -errorinfo]"
        exit 1
    }
    exit 0
}
proc acceptLanguage {} {
    if {[winfo exists .application.lang.top.en]} { .application.lang.top.en invoke } else { after 100 acceptLanguage }
}
proc ownCheck {} {
    set sample [::application::sample::location]
    if {[::scidb::db::get open? $sample]} { puts stderr "sample opened with a user database in history"; exit 1 }
    puts "OWN OK"
    exit 0
}
proc removedCheck {} {
    set sample [file join $::scidb::dir::share sample "Sample games.sci"]
    if {[::scidb::db::get open? $sample]} { puts stderr "removed sample reopened"; exit 1 }
    if {!$::application::sample::Removed} { puts stderr "removal flag was not loaded"; exit 1 }
    puts "REMOVAL OK"
    exit 0
}
set argv {--single-process}
set argc 1
source [file join $::env(SAMPLE_ROOT) tcl chesswiz]
if {$::env(SAMPLE_MODE) eq "own"} {
    set own [file join $::scidb::dir::home own.pgn]
    set ch [open $own w]; close $ch
    set ::application::database::RecentFiles [list [list PGNFile $own utf-8 1]]
}
after 100 acceptLanguage
# Startup2 is scheduled by the application itself, exactly once.
set callback verify
if {$::env(SAMPLE_MODE) eq "removed"} { set callback removedCheck }
if {$::env(SAMPLE_MODE) eq "own"} { set callback ownCheck }
after 6000 $callback
after 25000 { puts stderr "sample startup timed out"; exit 1 }
vwait forever
}
close $ch
proc launch {home mode} {
    global binary probe shared root
    file mkdir $home
    set output [exec env HOME=$home SCIDB_USERDIR=[file join $home profile] SCIDB_SHAREDIR=$shared \
        SCIDB_AI_CLASSIFIER=off SCIDB_AI_TRIAGE=0 SAMPLE_ROOT=$root SAMPLE_MODE=$mode \
        CHESSWIZ_LOG=debug SCIDB_ERROR_LOG=[file join $home errors.log] \
        timeout 35 $binary $probe 2>@1]
    puts $output
    return $output
}
tcltest::test sample-fresh-home {actual startup opens the installed sample, explorer moves and trainer source} -body {
    set home [file join $work fresh]
    file delete -force $home
    set output [launch $home fresh]
    string match {*SAMPLE OK*} $output
} -result 1
tcltest::test sample-existing-empty-profile {startup also works after initial language setup} -body {
    string match {*SAMPLE OK*} [launch [file join $work fresh] remove]
} -result 1
tcltest::test sample-removal-restart {removal persists into a separate application process} -body {
    string match {*REMOVAL OK*} [launch [file join $work fresh] removed]
} -result 1
tcltest::test sample-respects-own-database {a readable user database in history suppresses the sample} -body {
    set home [file join $work own]
    file delete -force $home
    string match {*OWN OK*} [launch $home own]
} -result 1
set failed $::tcltest::numTests(Failed)
tcltest::cleanupTests
exit [expr {$failed > 0}]
