# Modified for Chesswiz, 2026; see docs/UPSTREAM.md
# check-build.tcl

set scriptDir [file dirname [file normalize [info script]]]

catch { destroy . }
if {![llength [info commands ::scidb::app::initialized?]]} {
	puts "FAILED: app layer not loaded (wrong interpreter?)"
	exit 1
}

if {[catch {::scidb::app::initialized?} err]} {
	puts stderr "FAILED: $err"
	exit 1
}
if {[catch {::scidb::app::load eco [file join $scriptDir data eco.bin]} err]} {
	puts stderr "FAILED: $err"
	exit 1
}
puts "OK"

# vi:set ts=3 sw=3:
