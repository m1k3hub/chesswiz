# Regression: Stop button must not leave media state as "error".
#
# Root cause (run86): after ::mpv::close (called from Stop), every property
# reads as the empty string.  ::media::mpv::state mapped "" -> error, so any
# later probe saw a phantom failure.  All three native backends (Linux/libmpv,
# Windows/MF, macOS/AVF) behave identically: no player handle -> empty result.
#
# This test sources the real app-media-mpv.tcl with a stubbed ::mpv layer,
# then asserts the fix.  It fails on the old code (state returns "error"
# after stop) and passes once "no player" maps to "idle".

package require tcltest 2.5

# Isolate in a child interpreter so the stubs do not collide with other tests.
interp create mediaStopTest
mediaStopTest eval [list set testDir [file dirname [file normalize [info script]]]]
mediaStopTest eval {
	package require tcltest 2.5

	# Stub the native backend.  We cannot define ::mpv::set because Tcl
	# resolves bare "set" inside ::mpv::* procs to ::mpv::set, shadowing
	# the builtin.  Instead we provide ::mpv::open/close and override
	# ::media::mpv::_get to control property values per test case.
	namespace eval ::util { proc source {args} {} }
	namespace eval ::mpv { variable _playerOpen 0 }
	proc ::mpv::open {wid path {start 0}} { variable _playerOpen; ::set _playerOpen 1; return 1 }
	proc ::mpv::close {}                  { variable _playerOpen; ::set _playerOpen 0 }

	source -encoding utf-8 [file join $testDir .. tcl app-media-mpv.tcl]

	# Default _get: player open, all properties nominal (playing state).
	proc defaultGet {property} {
		switch -- $property {
			pause       { return no }
			core-idle   { return no }
			eof-reached { return no }
			load-error  { return no }
			time-pos    { return 1.5 }
			duration    { return 10.0 }
		}
		return {}
	}

	# closedGet: no player, every property empty (the real backend contract).
	proc closedGet {property} { return {} }

	tcltest::test media-state-playing {state is playing while transport is active} -setup {
		rename ::media::mpv::_get ::media::mpv::_savedGet
		proc ::media::mpv::_get {property} { return [defaultGet $property] }
	} -body {
		::media::mpv::launch dummy.m3u8 42 0
		::media::mpv::state
	} -cleanup {
		catch { ::media::mpv::stop }
		rename ::media::mpv::_get {}
		rename ::media::mpv::_savedGet ::media::mpv::_get
	} -result playing

	tcltest::test media-state-after-stop {after stop, state is idle not error} -setup {
		rename ::media::mpv::_get ::media::mpv::_savedGet
		# Start open, then close returns empty properties like real backends.
		proc ::media::mpv::_get {property} {
			if {$::mpv::_playerOpen} { return [defaultGet $property] }
			return [closedGet $property]
		}
	} -body {
		::media::mpv::launch dummy.m3u8 42 0
		::media::mpv::stop
		::media::mpv::state
	} -cleanup {
		rename ::media::mpv::_get {}
		rename ::media::mpv::_savedGet ::media::mpv::_get
	} -result idle

	tcltest::test media-time-after-stop {after stop, time is unknown} -setup {
		rename ::media::mpv::_get ::media::mpv::_savedGet
		proc ::media::mpv::_get {property} {
			if {$::mpv::_playerOpen} { return [defaultGet $property] }
			return [closedGet $property]
		}
	} -body {
		::media::mpv::launch dummy.m3u8 42 0
		::media::mpv::stop
		::media::mpv::time
	} -cleanup {
		rename ::media::mpv::_get {}
		rename ::media::mpv::_savedGet ::media::mpv::_get
	} -result {}

	tcltest::test media-state-load-error {real failure still reports error} -setup {
		rename ::media::mpv::_get ::media::mpv::_savedGet
		proc ::media::mpv::_get {property} {
			if {$property eq "load-error"} { return yes }
			if {$property eq "pause"}      { return no }
			return {}
		}
	} -body {
		::media::mpv::launch dummy.m3u8 42 0
		::media::mpv::state
	} -cleanup {
		catch { ::media::mpv::stop }
		rename ::media::mpv::_get {}
		rename ::media::mpv::_savedGet ::media::mpv::_get
	} -result error

	tcltest::test media-state-startup-race {unobserved pause during startup is idle not error} -setup {
		rename ::media::mpv::_get ::media::mpv::_savedGet
		# Player alive but pause not yet observed (cache miss -> empty).
		proc ::media::mpv::_get {property} {
			if {$property eq "core-idle"} { return yes }
			return {}
		}
	} -body {
		::media::mpv::launch dummy.m3u8 42 0
		::media::mpv::state
	} -cleanup {
		catch { ::media::mpv::stop }
		rename ::media::mpv::_get {}
		rename ::media::mpv::_savedGet ::media::mpv::_get
	} -result idle

	tcltest::test media-state-eof {eof-reached maps to ended} -setup {
		rename ::media::mpv::_get ::media::mpv::_savedGet
		proc ::media::mpv::_get {property} {
			if {$property eq "pause"}       { return no }
			if {$property eq "eof-reached"} { return yes }
			if {$property eq "load-error"}  { return no }
			return {}
		}
	} -body {
		::media::mpv::launch dummy.m3u8 42 0
		::media::mpv::state
	} -cleanup {
		catch { ::media::mpv::stop }
		rename ::media::mpv::_get {}
		rename ::media::mpv::_savedGet ::media::mpv::_get
	} -result ended

	tcltest::test media-state-paused {pause yes maps to paused} -setup {
		rename ::media::mpv::_get ::media::mpv::_savedGet
		proc ::media::mpv::_get {property} {
			if {$property eq "pause"}      { return yes }
			if {$property eq "load-error"} { return no }
			return {}
		}
	} -body {
		::media::mpv::launch dummy.m3u8 42 0
		::media::mpv::state
	} -cleanup {
		catch { ::media::mpv::stop }
		rename ::media::mpv::_get {}
		rename ::media::mpv::_savedGet ::media::mpv::_get
	} -result paused

	tcltest::cleanupTests
}
interp delete mediaStopTest
