package require tcltest 2.5

# Regression coverage for the pure media-panel helpers that the heavier
# media suites do not exercise: the .cms x/y selector decoder and the
# game-coupled lesson predicate.

namespace eval ::mediaCmsTest {
    variable sourceDir [file normalize [file join [file dirname [info script]] .. tcl]]

    proc setup {} {
        variable sourceDir
        interp create cmsTest
        cmsTest eval {namespace eval ::util {proc source {args} {}}}
        # The headless interpreter has no options persistence service.
        cmsTest eval {namespace eval ::options {proc hookWriter {args} {}}}
        cmsTest eval [list source [file join $sourceDir app-media.tcl]]
    }

    proc cleanup {} {
        interp delete cmsTest
    }
}

# .cms x/y selectors are file-major 0-based: square = file*8 + rank, so
# a1=0, b1=8, a2=1, h8=63.  This is the same mapping as
# media-console/probe_cms_selectors.py square_name_filemajor0, verified
# against python-chess on the CBM168 corpus (109/109 legal moves).  The
# previous rank-major reading decoded only 13/136 existing-clip hotspots
# to legal moves.
tcltest::test media-cms-square-file-major {x/y selectors decode file-major} -setup {
    ::mediaCmsTest::setup
} -body {
    cmsTest eval {
        list \
            [::application::media::CmsSquare 0] \
            [::application::media::CmsSquare 1] \
            [::application::media::CmsSquare 8] \
            [::application::media::CmsSquare 63]
    }
} -cleanup {::mediaCmsTest::cleanup} -result {a1 a2 b1 h8}

# docs/formats/CHESSBASE_MEDIA_RE.md worked example: clip
# "...8 b - - 0 1x46y54v3u2.wmv" is the key move f7-g7.
tcltest::test media-cms-square-corpus-example {CBM168 x46y54 -> f7-g7} -setup {
    ::mediaCmsTest::setup
} -body {
    cmsTest eval {
        list [::application::media::CmsSquare 46] [::application::media::CmsSquare 54]
    }
} -cleanup {::mediaCmsTest::cleanup} -result {f7 g7}

# Audio (2) and video (3) owned by a game both play as coupled lessons
# (MEDIA_PANEL_DESIGN.md 3.2); pictures and unowned rows do not.
tcltest::test media-coupled-lesson-audio {audio and video owned by a game are coupled} -setup {
    ::mediaCmsTest::setup
} -body {
    cmsTest eval {
        set ::application::media::Priv(base) /tmp/db
        list \
            [::application::media::CoupledLesson? 3 5] \
            [::application::media::CoupledLesson? 2 5] \
            [::application::media::CoupledLesson? 1 5] \
            [::application::media::CoupledLesson? 3 -1]
    }
} -cleanup {::mediaCmsTest::cleanup} -result {1 1 0 0}

tcltest::test media-coupled-lesson-needs-database {coupling requires an open database} -setup {
    ::mediaCmsTest::setup
} -body {
    cmsTest eval {
        set ::application::media::Priv(base) {}
        list \
            [::application::media::CoupledLesson? 3 5] \
            [::application::media::CoupledLesson? 2 5]
    }
} -cleanup {::mediaCmsTest::cleanup} -result {0 0}

tcltest::cleanupTests
