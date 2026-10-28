# Run with tkchesswiz under Xvfb: probe_installed_knowledge.tcl BUNDLE SHAREDIR
# No runtime directory variables or knowledge cache are overridden.
lassign $argv installedBundle installedShare
set expected [file normalize [file join $installedShare knowledge]]
set installedProbeReads {}
proc installedProbeOpen {command op} {
    set path [lindex $command 1]
    if {[file tail $path] in {actions.json topics.json}} {
        lappend ::installedProbeReads [file normalize $path]
    }
}
trace add execution ::open enter installedProbeOpen
set argv {--single-process}; set argc 1
source -encoding utf-8 $installedBundle
set ::scidb::dir::setup 0
set deadline [expr {[clock milliseconds]+20000}]
while {![info exists ::application::Vars(ready)] || !$::application::Vars(ready)} {
    update
    after 10
    if {[clock milliseconds] > $deadline} {error {installed startup timed out}}
}
::knowledge::Load
if {[::knowledge::Dir] ne $expected} {error "wrong pack directory: [::knowledge::Dir]"}
trace remove execution ::open enter installedProbeOpen
foreach name {actions topics} {
    if {[file join $expected $name.json] ni $installedProbeReads} {
        error "runtime never read installed $name.json"
    }
}
package require json
foreach {name variable} {actions PackActions topics PackTopics} {
    set f [open [file join $expected $name.json] r]
    set disk [::json::json2dict [read $f]]
    close $f
    if {[set ::knowledge::$variable] ne $disk} {error "$name was not loaded from the installed pack"}
}
puts "INSTALLED_PACK_OK $expected actions=[llength $::knowledge::PackActions]"
bind .application <Destroy> {}
exit 0
