# Standalone UI regressions: xvfb-run -a tclsh tests/test_media_panel.tcl
package require Tk
package require tcltest 2.5
namespace eval ::util { proc source {args} {} }
set root [file dirname [file normalize [info script]]]
source [file join $root app-media-sync.tcl]
source [file join $root app-media.tcl]

namespace eval ::scidb::db {
    proc mediaGallery {base variant} {
        return {{/tmp/lesson.mp4 video Lesson 0 0}}
    }
}
# Lesson construction is unrelated to gallery selection and needs the backend.
rename ::application::media::PrebuildLessons ::application::media::RealPrebuildLessons
proc ::application::media::PrebuildLessons {} {}

proc setupPanel {} {
    ttk::frame .panel
    ttk::treeview .panel.tree
    frame .panel.viewer
    canvas .panel.viewer.canvas
    array set ::application::media::Priv {
        tree .panel.tree viewer .panel.viewer position 0 inprocess 0
        interactive {} userInteractive {} dbInteractive {}
    }
}
proc cleanupPanel {} {
    ::application::media::Stop
    foreach key {afterid seekid interactiveid} {
        catch {after cancel $::application::media::Priv($key)}
    }
    set ::media::sync::State(driving) 0
    destroy .panel
}

tcltest::test media-panel-independent-gallery {gallery retains its database and hint without a game} -setup {
    setupPanel
    set ::application::media::Priv(lastBase) [info script]
    set ::application::media::Priv(lastVariant) Normal
} -body {
    ::application::media::Update -1
    list [expr {$::application::media::Priv(base) eq [info script]}] \
        $::application::media::Priv(variant) \
        [.panel.viewer.canvas itemcget [lindex [.panel.viewer.canvas find all] 0] -text]
} -cleanup {cleanupPanel} -result {1 Normal {Media gallery

Select a media entry to play.}}

tcltest::test media-panel-close-refresh {closing cancels queued game refresh} -setup {
    setupPanel
} -body {
    ::application::media::GameSwitched 0 1
    set pending $::application::media::Priv(afterid)
    ::application::media::closed .panel
    expr {$pending ni [after info]}
} -cleanup {cleanupPanel} -result 1

tcltest::test media-panel-follow-feedback {video-driven board updates must not schedule a reverse seek} -setup {
    setupPanel
    set ::application::media::Priv(inprocess) 1
    set ::media::sync::State(driving) 1
} -body {
    ::application::media::BoardUpdated 0
    set ::media::sync::State(driving) 0
    set pending {}
    catch {set pending $::application::media::Priv(seekid)}
    expr {$pending eq "" || $pending ni [after info]}
} -cleanup {cleanupPanel} -result 1

proc ::panelPlayer {command args} {
    switch $command {
        duration {return 120.0}
        time {
            if {[llength $args]} {set ::panelSeekSeconds [lindex $args 0]}
            return 30.0
        }
    }
}
tcltest::test media-panel-time-units {tkvlc seconds are displayed as minutes and seconds} -setup {
    setupPanel
    ttk::scale .panel.seek
    set ::application::media::Priv(seekbar) .panel.seek
    set ::application::media::Priv(vlc_handle) ::panelPlayer
    set ::application::media::Priv(inprocess) 1
} -body {
    ::application::media::SeekTick
    set ::application::media::Priv(seeklabel)
} -cleanup {cleanupPanel} -result {0:30 / 2:00}

tcltest::test media-panel-timeline-seek-units {timeline milliseconds seek the backend in seconds} -setup {
    setupPanel
    set ::application::media::Priv(vlc_handle) ::panelPlayer
    set ::application::media::Priv(inprocess) 1
    rename ::application::media::SyncBoardPly ::application::media::RealSyncBoardPly
    proc ::application::media::SyncBoardPly {} {return 1}
    ::media::sync::load-timeline {{5000 1}}
    set ::panelSeekSeconds -1
} -body {
    ::application::media::PlySeek 0
    expr {$::panelSeekSeconds == 5.0}
} -cleanup {
    rename ::application::media::SyncBoardPly {}
    rename ::application::media::RealSyncBoardPly ::application::media::SyncBoardPly
    ::media::sync::load-timeline {}
    cleanupPanel
} -result 1

set ::mediaPanelFailureCount $::tcltest::numTests(Failed)
tcltest::cleanupTests
destroy .
exit [expr {$::mediaPanelFailureCount > 0}]
