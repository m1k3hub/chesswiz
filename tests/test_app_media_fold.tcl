# Board transport shares the Media pane's model and playback delegates.
package require tcltest 2.5

proc ::scidb::test::foldStub {name args body} {
    rename ::media::mpv::$name ::media::mpv::foldSaved_$name
    proc ::media::mpv::$name $args $body
    lappend ::scidb::test::foldStubs $name
}
proc ::scidb::test::foldCleanup {} {
    ::application::media::Stop
    foreach name $::scidb::test::foldStubs {
        rename ::media::mpv::$name {}
        rename ::media::mpv::foldSaved_$name ::media::mpv::$name
    }
    set ::scidb::test::foldStubs {}
}

::application::media::Ensure

tcltest::test mediafold-default {new layouts omit Media but retain its pane definition} -body {
    list [regexp {frame media} $::application::BoardLayout] \
        [info exists ::application::PaneOptions(media)]
} -result {0 1}

tcltest::test mediafold-controls {controls live below the video and move with the inset} -body {
    set video [::mediainset::surface .unused]
    set w [winfo parent $video]
    update idletasks
    list [winfo exists $w.controls.play] [winfo exists $w.controls.seek] \
        [expr {[winfo y $w.controls] >= [winfo y $video] + [winfo height $video]}] \
        [winfo manager $w.expand] [string match *TogglePlayback* [bind $w <space>]]
} -cleanup {::mediainset::hide} -result {1 1 1 grid 1}

tcltest::test mediafold-transport {play pause seek and stop use the existing mpv delegates} -setup {
    set ::scidb::test::foldStubs {}
    set ::scidb::test::foldCalls {}
    set ::scidb::test::foldState paused
    ::scidb::test::foldStub state {} {return $::scidb::test::foldState}
    ::scidb::test::foldStub play {} {lappend ::scidb::test::foldCalls play; set ::scidb::test::foldState playing}
    ::scidb::test::foldStub pause {} {lappend ::scidb::test::foldCalls pause; set ::scidb::test::foldState paused}
    ::scidb::test::foldStub stop {} {lappend ::scidb::test::foldCalls stop}
    ::scidb::test::foldStub seek {ms} {lappend ::scidb::test::foldCalls [list seek $ms]}
    ::scidb::test::foldStub duration {} {return 120}
    ::scidb::test::foldStub time {} {return 30}
    set video [::mediainset::surface .unused]
    set controls [winfo parent $video].controls
    set ::application::media::Priv(inprocess) 1
} -body {
    $controls.play invoke
    $controls.play invoke
    ::application::media::SeekTick
    set time $::application::media::Priv(seeklabel)
    set fraction [$controls.seek get]
    $controls.seek set 500
    ::application::media::SeekRelease $controls.seek
    set done 0
    after 250 {set done 1}
    vwait done
    $controls.stop invoke
    list $::scidb::test::foldCalls $time [expr {$fraction == 250}] $::mediainset::Shown
} -cleanup {::scidb::test::foldCleanup} -result {{play pause {seek 60000.0} stop} {0:30 / 2:00} 1 0}

tcltest::test mediafold-button-menu {board button follows the shared entry list and builds a typed menu} -setup {
    rename ::mediainset::Entries ::mediainset::foldSavedEntries
    proc ::mediainset::Entries {} {return $::scidb::test::foldEntries}
} -body {
    set pane [::mediainset::Pane]
    set ::scidb::test::foldEntries {}
    ::mediainset::RefreshMediaButton
    set hidden [winfo manager $pane.mediaButton]
    set ::scidb::test::foldEntries {{item0 Video {Lesson one} /test.mp4 0} {item1 Audio Commentary /test.mp3 0}}
    ::mediainset::RefreshMediaButton
    ::mediainset::PopulateMenu $pane.mediaButton.menu
    list $hidden [winfo manager $pane.mediaButton] \
        [$pane.mediaButton.menu entrycget 0 -label] \
        [$pane.mediaButton.menu entrycget 1 -label] \
        [$pane.mediaButton.menu entrycget 3 -label]
} -cleanup {
    rename ::mediainset::Entries {}
    rename ::mediainset::foldSavedEntries ::mediainset::Entries
    ::mediainset::RefreshMediaButton
} -result {{} place {Lesson one (Video)} {Commentary (Audio)} {Open stream...}}

tcltest::test mediafold-audio {audio hides the video through relayout and swap} -body {
    set video [::mediainset::surface .unused]
    ::mediainset::AudioOnly 1
    ::mediainset::Layout
    ::mediainset::swap
    set w [winfo parent $video]
    list [winfo manager $video] [dict get [place info $w] -relheight] \
        [winfo manager $w.controls]
} -cleanup {::mediainset::hide; ::mediainset::AudioOnly 0} -result {{} 0 pack}

tcltest::test mediafold-interactive-menu {authored segments keep their range conversion when chosen} -setup {
    rename ::application::media::PlayMedia ::application::media::foldSavedPlayMedia
    proc ::application::media::PlayMedia {path start end} {set ::scidb::test::foldClip [list $path $start $end]}
} -body {
    ::mediainset::Choose [list interactive [list fen /clip.mp4 1.5 3.0 Segment]]
    set ::scidb::test::foldClip
} -cleanup {
    rename ::application::media::PlayMedia {}
    rename ::application::media::foldSavedPlayMedia ::application::media::PlayMedia
} -result {/clip.mp4 1500.0 3000.0}

tcltest::test mediafold-backend {closing a Media pane leaves the shared model alive} -body {
    ttk::frame .application.foldPane
    ::application::media::build {} .application.foldPane 400 300
    set tree $::application::media::Priv(tree)
    ::application::media::closed .application.foldPane
    destroy .application.foldPane
    list [winfo exists $tree] [winfo manager .application.mediaBackend]
} -result {1 {}}

tcltest::cleanupTests
