package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
::scidb::test::actions::ready

tcltest::test setup-scan-engine-subfolder {an engine unpacked in a folder named after it is found} -setup {
	set dir [file join [file normalize ~] engines igel-3.5 bin]
	file mkdir $dir
	set ::ext [expr {$::tcl_platform(platform) eq "windows" ? ".exe" : ""}]
	set exe [file join $dir igel-3.5$::ext]
	set f [open $exe w]; puts $f "#!/bin/sh"; close $f
	if {$::ext eq ""} { file attributes $exe -permissions 0755 }
	array set saved [array get ::application::setupscan::Options]
	set ::application::setupscan::Options(rejected) {}
	set savedEngines $::engine::Engines
	set ::engine::Engines {}
} -body {
	dict get [::application::setupscan::EngineCandidates] igel
} -cleanup {
	set ::engine::Engines $savedEngines
	array set ::application::setupscan::Options [array get saved]
	file delete -force [file join [file normalize ~] engines igel-3.5]
	unset ::ext
} -result [file join [file normalize ~] engines igel-3.5 bin igel-3.5[expr {$::tcl_platform(platform) eq "windows" ? ".exe" : ""}]]

tcltest::test setup-scan-engine-where {the scan names the folders of this platform} -body {
	expr {[string match *Program\ Files* [::application::setupscan::EngineWhere]] == ($::tcl_platform(platform) eq "windows")}
} -result 1

tcltest::cleanupTests
