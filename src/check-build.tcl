# check-build.tcl

set scriptDir [file dirname [file normalize [info script]]]

catch { destroy . }
if {![llength [info commands ::scidb::app::initialized?]]} {
	puts "FAILED: app layer not loaded (wrong interpreter?)"
	return
}

if {[catch {::scidb::app::initialized?} err]} {
	puts "FAILED"
	return
}
if {[catch {::scidb::app::load eco [file join $scriptDir data eco.bin]} err]} {
	puts "FAILED"
	return
}
puts "OK"

# vi:set ts=3 sw=3:
