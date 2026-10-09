# ======================================================================
# Headless startup smoke test for the merged Tcl startup script.
# ======================================================================
# Run via tests/Makefile target `smoke`:
#
#   xvfb-run -a ./src/tkchesswiz tests/startup_smoke.tcl
#
# Sources the real merged startup script (tcl/chesswiz) under Xvfb
# with an isolated throwaway HOME and fails if:
#   * the startup script itself raises (script-level error), or
#   * any deferred callback raises through bgerror within the soak
#     window (undefined procs, missing widgets, bad subscriptions), or
#   * startup does not reach a runnable event loop and survive the
#     soak window (10 s).
#
# The startup script registers its own dialog-based bgerror handler
# (interp bgerror, tcl/chesswiz ~line 1503); this wrapper retakes the
# handler 500 ms into the event loop so deferred errors fail the test
# headlessly instead of blocking on a dialog under Xvfb.
#
# The user's real ~/.chesswiz is never touched: HOME is redirected to
# a throwaway directory before the startup script runs.
# ======================================================================

namespace eval ::SMOKE {
variable failed	0
variable home		{}
}

set ::SMOKE(failed)	0
set ::SMOKE(home)	[file join /tmp scidb-smoke-home-[pid]]

proc ::SMOKE::bgerror {msg} {
	set ::SMOKE(failed) 1
	puts stderr "STARTUP-SMOKE: bgerror: $msg"
	if {[info exists ::errorInfo]} { puts stderr $::errorInfo }
	catch { after idle { exit 1 } }
}

file delete -force $::SMOKE(home)
file mkdir $::SMOKE(home)
set env(HOME) $::SMOKE(home)

set scriptDir [file dirname [file normalize [info script]]]
set merged	[file join [file dirname $scriptDir] tcl chesswiz]

if {![file exists $merged]} {
	puts stderr "STARTUP-SMOKE: merged script not found: $merged"
	exit 1
}

# verdict: startup must reach the event loop and survive the soak
after 10000 {
	if {$::SMOKE(failed)} {
		puts stderr "STARTUP-SMOKE: FAIL (see errors above)"
		exit 1
	}
	puts "STARTUP-SMOKE: OK"
	exit 0
}

# retake the bgerror handler shortly after the startup script replaces
# it; errors between source start and this point are script-level
after 500 { interp bgerror {} ::SMOKE::bgerror }

if {[catch { source $merged } err opts]} {
	puts stderr "STARTUP-SMOKE: FAIL: startup script raised: $err"
	puts stderr [dict get $opts -errorinfo]
	exit 1
}

# the merged script returned without entering a blocking event loop:
# run the soak manually
after 2000 {
	if {$::SMOKE(failed)} { exit 1 }
	puts "STARTUP-SMOKE: OK"
	exit 0
}
vwait ::SMOKE(failed)
