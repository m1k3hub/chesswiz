package require tcltest 2.5

set syncSource [file normalize [file join [file dirname [info script]] .. tcl app-media-sync.tcl]]
interp create syncTest
syncTest eval {namespace eval util {proc source {args} {}}}
syncTest eval [list source $syncSource]

tcltest::test media-exact-node {node IDs are identities, not ordered ply numbers} -body {
    syncTest eval {
        ::media::sync::load-timeline {{1000 8} {2000 2} {3000 5}}
        list [::media::sync::ms-for-ply 2] [::media::sync::ms-for-ply 3] \
            [::media::sync::ms-for-ply -1]
    }
} -result {2000 -1 -1}

tcltest::test media-seek-rewind {explicit seeks update the board in both directions, including before the first move} -body {
    syncTest eval {
        set nodes {}
        ::media::sync::configure boardgoto-cmd {lappend ::nodes}
        ::media::sync::onPlaybackStarted
        ::media::sync::seek 2500 4000
        ::media::sync::seek 1500 4000
        ::media::sync::seek 0 4000
        set nodes
    }
} -result {2 8 0}

tcltest::test media-no-guessed-timing {missing timestamps never advance the board proportionally} -body {
    syncTest eval {
        set advanced 0
        ::media::sync::configure boardforward-cmd {incr ::advanced} \
            boardlength-cmd {expr 20} boardply-cmd {expr 0}
        ::media::sync::load-timeline {}
        ::media::sync::drive 5000 10000
        set advanced
    }
} -result 0

syncTest eval [list source [file join [file dirname $syncSource] app-media.tcl]]
syncTest eval {
    namespace eval ::application::media {
        proc SyncBoardNode {} {return 2}
        proc SyncBoardPly {} {return 12}
        proc MediaSeek {seconds} {set ::sought $seconds}
        proc MediaDuration {} {return 4}
        proc MediaPause {} {set ::paused 1}
        set Priv(position) 7
        set Priv(inprocess) 1
        set Priv(backend) mpv
        set Priv(vlc_handle) {}
        set Priv(lessonPositions) {start a b}
    }
}

tcltest::test media-mpv-board-seek {board navigation seeks by lesson identity without a VLC handle} -body {
    syncTest eval {
        ::media::sync::load-timeline {{1000 8} {2000 2} {3000 5}}
        ::application::media::PlySeek 7
        set sought
    }
} -result 2.0

tcltest::test media-paused-scrub {scrubbing updates both transport and board without a playback tick} -body {
    syncTest eval {
        set nodes {}
        ::application::media::SeekApply 0.375 4
        list $sought $nodes
    }
} -result {1.5 8}

interp delete syncTest
tcltest::cleanupTests
