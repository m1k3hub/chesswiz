package require tcltest 2.5

namespace eval ::mediaLessonTest {
    variable sourceDir [file normalize [file join [file dirname [info script]] .. tcl]]
    variable tempDir

    proc setup {} {
        variable sourceDir
        variable tempDir
        set tempDir [tcltest::makeDirectory media-lesson-regressions]
        interp create lessonTest
        lessonTest eval {namespace eval ::util {proc source {args} {}}}
        lessonTest eval {namespace eval ::options {proc hookWriter {args} {}}}
        foreach file {actions.tcl app-media-decode.tcl app-media-lesson.tcl app-media-sync.tcl app-media.tcl} {
            lessonTest eval [list source [file join $sourceDir $file]]
        }
        lessonTest eval [list set tempDir $tempDir]
        lessonTest eval {
            namespace eval ::scidb::dir {}
            set ::scidb::dir::user [file join $tempDir user]
            set video [file join $tempDir lesson.wmv]
            close [open $video w]
            set txt [file rootname $video].txt
            set probeFile [file join $tempDir probe.json]
            set probeCalls 0
            # Only replace the external ffprobe process, retaining the decoder.
            proc ::media::decoder::open {path args} {
                if {[lindex $path 0] eq "|"} {
                    incr ::probeCalls
                    return [::open $::probeFile r]
                }
                return [::open $path {*}$args]
            }
            proc encode {bytes} {
                binary scan $bytes B* bits
                append bits [string repeat 0 [expr {(6 - [string length $bits] % 6) % 6}]]
                set result GA:
                foreach chunk [regexp -all -inline {.{6}} $bits] {
                    scan $chunk %b value
                    append result [format %c [expr {$value + 63}]]
                }
                return $result
            }
            # Ten legal knight moves, encoded as file-major checkpoint edges.
            set checkpoint [binary format iiii 2 0 0 0]
            append checkpoint [string repeat "\x01\x00" 6] [binary format i 0]
            append checkpoint [binary format H* 5f9000000bb803e803] [binary format i 10]
            foreach {from to} {48 42 15 21 42 48 21 15 48 42 15 21 42 48 21 15 48 42 15 21} {
                append checkpoint [binary format ccsc $from $to 0 0]
            }
            proc writeProbe {{withCheckpoint 1}} {
                set packets {}
                set records {}
                if {$withCheckpoint} {lappend records [list 0 $::checkpoint]}
                foreach {ms node} {1000 1 2000 3 3000 1} {
                    lappend records [list $ms [binary format ii 3 $node]]
                }
                foreach record $records {
                    lassign $record ms bytes
                    set hex [binary encode hex [encode $bytes]]
                    set dump "00000000: [join [regexp -all -inline {..} $hex] { }]  payload"
                    lappend packets [format {{"pts_time":"%.3f","data":"%s"}} [expr {$ms/1000.0}] $dump]
                }
                set fh [open $::probeFile w]
                puts $fh [format {{"packets":[%s]}} [join $packets ,]]
                close $fh
            }
            proc writeSidecar {{node 2}} {
                set fh [open $::txt w]
                puts $fh "0:00:00.0:\n[encode $::checkpoint]"
                puts $fh "0:00:01.0:\n[encode [binary format ii 3 $node]]"
                close $fh
            }
            writeProbe
        }
    }
    proc cleanup {} {
        interp delete lessonTest
        tcltest::removeDirectory media-lesson-regressions
    }
}

tcltest::test media-backend-selection {plain media reaches the libmpv player} -setup {
    ::mediaLessonTest::setup
} -body {
    lessonTest eval {
        namespace eval ::application::media {
            proc PlayInProcess {args} {incr ::attempts; return 1}
        }
        set attempts 0
        ::application::media::PlayMedia $video
        set attempts
    }
} -cleanup {::mediaLessonTest::cleanup} -result 1

tcltest::test media-wmv-navigation {real WMV packet decoding resolves nodes and rewinds} -setup {
    ::mediaLessonTest::setup
} -body {
    lessonTest eval {
        set lesson [::media::lesson::get $video]
        set positions [dict get $lesson positions]
        set ::application::media::Priv(lessonPositions) $positions
        namespace eval ::scidb::game {
            # a mock engine that behaves like the real one: the board is where
            # "go position" last sent it (SyncBoardGoto verifies that)
            proc fen {args} {return [expr {[info exists ::lastFen] ? $::lastFen : {}}]}
            proc go {args} {lappend ::visited [lindex $args end]; set ::lastFen [lindex $args end]}
        }
        set visited {}
        ::media::sync::configure boardgoto-cmd ::application::media::SyncBoardGoto
        ::media::sync::load-timeline [dict get $lesson timeline]
        ::media::sync::onPlaybackStarted
        foreach ms {1500 2500 3500 0} {::media::sync::seek $ms 4000}
        list [dict get $lesson valid] [llength $positions] \
            [dict get $lesson timeline] \
            [expr {$visited eq [list [lindex $positions 1] [lindex $positions 3] [lindex $positions 1] [lindex $positions 0]]}]
    }
} -cleanup {::mediaLessonTest::cleanup} -result {1 11 {{1000 1} {2000 3} {3000 1}} 1}

tcltest::test media-wmv-missing-checkpoint {unresolvable lessons fail explicitly} -setup {
    ::mediaLessonTest::setup
} -body {
    lessonTest eval {
        writeProbe 0
        set lesson [::media::lesson::get $video]
        list [dict get $lesson valid] [string match {*checkpoint*} [dict get $lesson reason]]
    }
} -cleanup {::mediaLessonTest::cleanup} -result {0 1}

foreach cache {memory disk} {
    tcltest::test media-cache-add-$cache {adding a text sidecar invalidates the decoded lesson} -setup {
        ::mediaLessonTest::setup
    } -body {
        lessonTest eval [list set cache $cache]
        lessonTest eval {
            ::media::lesson::get $video
            writeSidecar
            if {$cache eq "disk"} {array unset ::media::lesson::Cache}
            set lesson [::media::lesson::get $video]
            list [dict get $lesson source] [dict get $lesson timeline]
        }
    } -cleanup {::mediaLessonTest::cleanup} -result {sidecar {{1000 2}}}

    tcltest::test media-cache-edit-$cache {editing a sidecar invalidates the decoded lesson} -setup {
        ::mediaLessonTest::setup
    } -body {
        lessonTest eval [list set cache $cache]
        lessonTest eval {
            writeSidecar
            set oldTime [file mtime $txt]
            ::media::lesson::get $video
            writeSidecar 3
            file mtime $txt [expr {$oldTime + 10}]
            if {$cache eq "disk"} {array unset ::media::lesson::Cache}
            dict get [::media::lesson::get $video] timeline
        }
    } -cleanup {::mediaLessonTest::cleanup} -result {{1000 3}}

    tcltest::test media-cache-remove-$cache {removing a text sidecar switches back to WMV} -setup {
        ::mediaLessonTest::setup
    } -body {
        lessonTest eval [list set cache $cache]
        lessonTest eval {
            writeSidecar
            ::media::lesson::get $video
            file delete $txt
            if {$cache eq "disk"} {array unset ::media::lesson::Cache}
            set lesson [::media::lesson::get $video]
            list [dict get $lesson source] [dict get $lesson timeline]
        }
    } -cleanup {::mediaLessonTest::cleanup} -result {wmv {{1000 1} {2000 3} {3000 1}}}
}

tcltest::test media-cache-stable {unchanged lessons survive memory and disk cache hits} -setup {
    ::mediaLessonTest::setup
} -body {
    lessonTest eval {
        set first [::media::lesson::get $video]
        set second [::media::lesson::get $video]
        array unset ::media::lesson::Cache
        set third [::media::lesson::get $video]
        list [expr {$first eq $second && $first eq $third}] $probeCalls
    }
} -cleanup {::mediaLessonTest::cleanup} -result {1 1}

tcltest::test media-cache-video-edit {video edits invalidate a warm cache} -setup {
    ::mediaLessonTest::setup
} -body {
    lessonTest eval {
        ::media::lesson::get $video
        set fh [open $video a]
        puts $fh changed
        close $fh
        ::media::lesson::get $video
        set probeCalls
    }
} -cleanup {::mediaLessonTest::cleanup} -result 2

tcltest::test media-cache-legacy {old persisted lessons are decoded again} -setup {
    ::mediaLessonTest::setup
} -body {
    lessonTest eval {
        set lesson [::media::lesson::get $video]
        dict unset lesson inputs
        ::media::lesson::persist $video $lesson
        array unset ::media::lesson::Cache
        ::media::lesson::get $video
        set probeCalls
    }
} -cleanup {::mediaLessonTest::cleanup} -result 2

tcltest::test media-cache-repair {a newly supplied sidecar repairs an invalid cached lesson} -setup {
    ::mediaLessonTest::setup
} -body {
    lessonTest eval {
        writeProbe 0
        set before [dict get [::media::lesson::get $video] valid]
        writeSidecar
        set lesson [::media::lesson::get $video]
        list $before [dict get $lesson valid] [dict get $lesson source]
    }
} -cleanup {::mediaLessonTest::cleanup} -result {0 1 sidecar}

tcltest::test media-wmv-corrupt-checkpoint {malformed checkpoints are not playable lessons} -setup {
    ::mediaLessonTest::setup
} -body {
    lessonTest eval {
        set checkpoint [binary format i 2]
        writeProbe
        set lesson [::media::lesson::get $video]
        list [dict get $lesson valid] [string match {*checkpoint too short*} [dict get $lesson reason]]
    }
} -cleanup {::mediaLessonTest::cleanup} -result {0 1}

tcltest::test media-mainline-timeline {variation cursors are projected onto the main-line table} -setup {
    ::mediaLessonTest::setup
} -body {
    lessonTest eval {
        # 7 detours off ply 3 (snaps back) and 12 is out of range: both
        # dropped; sequential advances, backtracks and the final ply
        # are kept, so the board follows the main line without jumping
        # to an unrelated ply when the lecture branches.
        ::media::lesson::_mainline-timeline \
            {{100 1} {200 2} {300 3} {400 7} {500 3} {600 4} \
             {700 5} {800 12} {900 5} {1000 6}} 10
    }
} -cleanup {::mediaLessonTest::cleanup} \
  -result {{100 1} {200 2} {300 3} {500 3} {600 4} {700 5} {900 5} {1000 6}}

tcltest::test media-mainline-timeline-skip {a genuine forward skip is kept} -setup {
    ::mediaLessonTest::setup
} -body {
    lessonTest eval {
        ::media::lesson::_mainline-timeline {{100 1} {200 4} {300 5}} 10
    }
} -cleanup {::mediaLessonTest::cleanup} -result {{100 1} {200 4} {300 5}}

tcltest::cleanupTests
