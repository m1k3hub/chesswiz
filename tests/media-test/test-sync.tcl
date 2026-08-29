#!/usr/bin/env tclsh8.6
# Headless test of the media <-> board playback synchronization state
# machine (tcl/app-media-sync.tcl). Stub delegates record the transport
# and board commands instead of driving tkvlc/scidb; no Tk needed.
#
# Run: tclsh8.6 test-sync.tcl

set scriptdir [file normalize [file dirname [info script]]]
set sourceRoot [file join $scriptdir ../..]

# minimal util::source stub (the real one belongs to the application)
namespace eval ::util {
	proc source {what} { return }
}

source [file join $sourceRoot tcl app-media-sync.tcl]

namespace eval test {
	variable transportLog {}
	variable boardLog {}
	variable ply 0
	variable length 40
}

proc ::test::transportLog {} { return $::test::transportLog }
proc ::test::boardLog {} { return $::test::boardLog }
proc ::test::reset {} {
	# teardown the playing state FIRST so config/autoplay notifications
	# during cleanup never touch the (stale) transport delegate.
	::media::sync::onPlaybackStopped
	::media::sync::set-config 1 0
	::media::sync::autoplay 0
	set ::test::transportLog {}
	set ::test::boardLog {}
	::test::SetPly 0
}

proc ::test::SetPly {p} { set ::test::ply $p }

# --- stub delegates -----------------------------------------------------

proc ::test::transport {what} { lappend ::test::transportLog $what }
proc ::test::boardforward {} {
	incr ::test::ply
	lappend ::test::boardLog forward
}
proc ::test::boardstart {} {
	::test::SetPly 0
	lappend ::test::boardLog start
}
proc ::test::boardlength {} { return $::test::length }
proc ::test::boardply {} { return $::test::ply }

::media::sync::configure \
	transport-cmd	::test::transport \
	boardforward-cmd	::test::boardforward \
	boardstart-cmd	::test::boardstart \
	boardlength-cmd	::test::boardlength \
	boardply-cmd	::test::boardply \
	;

# --- helpers -------------------------------------------------------------

set Failures 0
proc assertEqual {actual expected label} {
	if {$actual ne $expected} {
		puts stderr "FAIL $label: expected [list $expected], got [list $actual]"
		incr ::Failures
	} else {
		puts "ok $label"
	}
}

# --- 1. transport sync: autoplay start plays, stop pauses ----------------
::test::reset
::media::sync::onPlaybackStarted
::media::sync::autoplay 1
assertEqual [::test::transportLog] {play} "autoplay start -> media plays"
::media::sync::step       ;# a step under autoplay must not pause
assertEqual [::test::transportLog] {play} "step under autoplay keeps playing"
::media::sync::autoplay 0
assertEqual [::test::transportLog] {play pause} "autoplay stop -> media pauses"

# --- 2. manual step pauses the media ------------------------------------
::test::reset
::media::sync::onPlaybackStarted
::media::sync::step
assertEqual [::test::transportLog] {pause} "manual navigation pauses media"

# --- 3. transport sync disabled: no transport traffic -------------------
::test::reset
::media::sync::set-config 0 0
::media::sync::onPlaybackStarted
::media::sync::autoplay 1
::media::sync::autoplay 0
::media::sync::step
assertEqual [::test::transportLog] {} "transport sync off -> no traffic"

# --- 4. follow mode: board advances with the media timeline -------------
::test::reset
::media::sync::set-config 1 1
::test::SetPly 0
set ::test::length 40
::media::sync::onPlaybackStarted
# t=0 of 40000ms -> ply 0
::media::sync::drive 0 40000
assertEqual [::test::boardLog] {} "t=0 does not step the board"
# halfway (20000/40000 -> goal 20): board jumps from 0 to 20 (4/tick max)
::media::sync::drive 20000 40000
set got $::test::ply
if {$got > 4} {
	puts stderr "FAIL follow tick advances at most 4 plies per tick: got $got"
	incr ::Failures
} else {
	puts "ok follow tick advances <= 4 plies (ply $got)"
}
set ::test::boardLog {}
::media::sync::drive 20000 40000 ;# more ticks catch up
::media::sync::drive 20000 40000
if {$::test::ply >= 10} {
	puts "ok follow ticks converge to mapped goal (ply $::test::ply)"
} else {
	puts stderr "FAIL follow ticks should converge (ply $::test::ply)"
	incr ::Failures
}

# --- 5. follow rewind: media seeked back -> game restarts ---------------
set ::test::boardLog {}
::media::sync::drive 30000 40000 ;# establish lastgoal at ~ply 30 (board steps 4/tick)
::test::SetPly 30                 ;# emulate the board having caught up
::media::sync::drive 100 40000    ;# ~ply 1, far below current 30: a rewind
if {$::test::ply < 5} {
	puts "ok media rewind restarts the game (ply $::test::ply)"
	if {[lsearch -exact [::test::boardLog] {start}] >= 0} {
		puts "ok rewind issues board start"
	} else {
		puts stderr "FAIL rewind should issue board start ([::test::boardLog])"
		incr ::Failures
	}
} else {
	puts stderr "FAIL media rewind should restart the game (ply $::test::ply)"
	incr ::Failures
}

# --- 6. follow mode off: drive is a no-op -------------------------------
::test::reset
::test::SetPly 5
::media::sync::drive 30000 40000
assertEqual [::test::boardLog] {} "follow off -> drive ignored"
assertEqual $::test::ply 5 "follow off -> board untouched"

# --- 7. not playing: transport sync inert -------------------------------
::test::reset
::media::sync::autoplay 1
assertEqual [::test::transportLog] {} "media not playing -> autoplay ignored"

# --- summary ------------------------------------------------------------
if {$Failures == 0} {
	puts "PASS: all media-sync tests"
	exit 0
} else {
	puts stderr "FAILED: $Failures test(s)"
	exit 1
}