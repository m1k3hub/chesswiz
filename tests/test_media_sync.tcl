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

tcltest::test media-nearest-occurrence {board-driven seeks pick the occurrence nearest the video} -body {
    syncTest eval {
        ::media::sync::load-timeline {{1000 1} {2000 2} {5000 2} {6000 3}}
        list [::media::sync::ms-for-ply 2] \
             [::media::sync::ms-for-ply 2 1500] \
             [::media::sync::ms-for-ply 2 4500] \
             [::media::sync::ms-for-ply 2 9000]
    }
} -result {2000 2000 5000 5000}

tcltest::test media-legacy-nearest-occurrence {legacy count timelines map a ply to its own mark, not a later one} -body {
    syncTest eval {
        ::media::sync::load-timeline {100 200 300 400}
        list [::media::sync::ms-for-ply 2] \
             [::media::sync::ms-for-ply 2 350] \
             [::media::sync::ms-for-ply 3 350] \
             [::media::sync::ms-for-ply 9]
    }
} -result {200 200 300 -1}

tcltest::test media-paused-tick {the follow tick does not drive a paused transport} -body {
    syncTest eval {
        set nodes {}
        ::media::sync::configure boardgoto-cmd {lappend ::nodes}
        ::media::sync::load-timeline {{1000 1} {2000 2}}
        ::media::sync::onPlaybackStopped
        ::media::sync::drive 2500 4000
        set nodes
    }
} -result {}

tcltest::test media-paused-seek {an explicit seek moves the board while the transport is paused} -body {
    syncTest eval {
        set nodes {}
        ::media::sync::configure boardgoto-cmd {lappend ::nodes}
        ::media::sync::load-timeline {{1000 1} {2000 2} {3000 3}}
        ::media::sync::onPlaybackStopped
        ::media::sync::seek 2500 4000
        set nodes
    }
} -result {2}

tcltest::test media-reach-tolerance {a seek landing just short of a mark still reaches it} -body {
    syncTest eval {
        set nodes {}
        ::media::sync::configure boardgoto-cmd {lappend ::nodes}
        ::media::sync::load-timeline {{1000 1} {2000 2}}
        ::media::sync::onPlaybackStarted
        ::media::sync::drive 1960 4000
        set nodes
    }
} -result {2}

interp delete syncTest
tcltest::cleanupTests
