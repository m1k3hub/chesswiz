#!/usr/bin/env tclsh
# mpv backend acceptance: launch + playback + seek + pause/state + clean
# stop, against the round-08 fixture, through the panel's own wrapper
# layer (application::media::Media*).  Exit 0 iff all gates pass.

package require Tk

namespace eval ::util { proc source {args} {} }
set here [file dirname [file normalize [info script]]]
source [file join $here app-media-decode.tcl]
source [file join $here app-media-lesson.tcl]
source [file join $here app-media-sync.tcl]
source [file join $here app-media-mpv.tcl]
source [file join $here app-media.tcl]

set fails 0
proc gate {name got want} {
	if {$got eq $want} {
		puts "  ok  $name"
	} else {
		puts "FAIL  $name\n      got:  $got\n      want: $want"
		incr ::fails
	}
}

wm withdraw .
frame .c -width 320 -height 240 -bg black
canvas .c.canvas -bg black -highlightthickness 0
pack .c; pack .c.canvas; update idletasks
array set ::application::media::Priv {
	tree {} viewer {} position 0 inprocess 0
	backend tkvlc interactive {} userInteractive {} dbInteractive {}
}
set ::application::media::Priv(viewer) .c

set video "/media/michael-g-thomas/sas_mirror/fixt/cbm168/Festival Biel 2015.html/Biel 2015 round 08 MVL-Adams.wmv"

set ::application::media::Priv(backend) tkvlc
set ok [::application::media::PlayInProcess $video 0]
gate "mpv launch through PlayInProcess" $ok 1
gate "backend selected = mpv" $::application::media::Priv(backend) mpv

for {set i 0} {$i < 6} {incr i} {
	after 500
	puts "poll $i: state=[::application::media::MediaState] rawpause=[::media::mpv::_get pause] time=[::media::mpv::time]"
	flush stdout
}
set st [::application::media::MediaState]
gate "state after 3s = playing" $st playing
set t1 [::application::media::MediaTime]
gate "time-pos advances (>= 1.0s)" [expr {$t1 >= 1.0 ? 1 : 0}] 1

::application::media::MediaSeek 60.0
after 1200
set t2 [::application::media::MediaTime]
gate "seek to 60s landed (57..65)" [expr {$t2 >= 57.0 && $t2 <= 65.0 ? 1 : 0}] 1

::application::media::MediaPause
after 800
gate "pause holds" [::application::media::MediaState] paused

::application::media::MediaPlay
after 800
gate "resume plays" [::application::media::MediaState] playing

set dur [::application::media::MediaDuration]
gate "duration sane (400..500s)" [expr {$dur > 400 && $dur < 500 ? 1 : 0}] 1

::application::media::Stop
after 800
set left 0
catch { set left [llength [exec pgrep -x mpv]] }
gate "no mpv process left after Stop" $left 0

if {$fails} { puts "\nmpv-backend: $fails gate(s) FAILED"; exit 1 }
puts "\nmpv-backend: all gates pass"
exit 0
