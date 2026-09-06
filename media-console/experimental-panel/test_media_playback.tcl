# Real VLC smoke test, run in a fresh interpreter:
# xvfb-run -a /usr/bin/tclsh tests/test_media_playback.tcl /path/to/video.wmv
package require Tk
namespace eval ::util {proc source {args} {}}
set root [file dirname [file normalize [info script]]]
source [file join $root app-media-sync.tcl]
source [file join $root app-media.tcl]
source [file join $root app-media-lesson.tcl]
set video [file normalize [lindex $argv 0]]
if {![file isfile $video]} {error "Pass a real video file"}
# Isolate transport from script extraction using the real lesson cache.
set ::media::lesson::Cache($video) [dict create valid 1 video $video timeline {} events {}]
frame .viewer
canvas .viewer.canvas -width 640 -height 360
pack .viewer.canvas
pack .viewer
update
set ::application::media::Priv(viewer) .viewer
set ::application::media::Priv(index) 0
ttk::scale .seek
set ::application::media::Priv(seekbar) .seek

set started [::application::media::PlayLesson $video 0]
if {!$started} {
    puts stderr "FAIL: $::application::media::Priv(statusbar)"
    destroy .
    exit 1
}
set deadline [expr {[clock milliseconds] + 10000}]
set firstTime -1
set advanced 0
while {[clock milliseconds] < $deadline} {
    after 250 {set ::tick 1}
    vwait ::tick
    set handle $::application::media::Priv(vlc_handle)
    if {$handle eq ""} {break}
    set state [$handle state]
    set time [$handle time]
    if {$state eq "playing" && $time > 0} {
        if {$firstTime < 0} {set firstTime $time}
        if {$time > $firstTime + 0.5} {set advanced 1; break}
    }
}
::application::media::Stop
destroy .
if {!$advanced} {puts stderr "FAIL: video clock did not advance"; exit 1}
puts "PASS: lesson started in a fresh interpreter and VLC playback time advanced"
exit 0
