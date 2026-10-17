# Board transport shares the Media pane's model and playback delegates.
package require tcltest 2.5

proc ::scidb::test::foldStub {name args body} {
    if {[llength [info commands ::media::mpv::$name]]} {
        rename ::media::mpv::$name ::media::mpv::foldSaved_$name
        lappend ::scidb::test::foldStubs [list rename $name]
    } else {
        lappend ::scidb::test::foldStubs [list delete $name]
    }
    proc ::media::mpv::$name $args $body
}
proc ::scidb::test::foldCleanup {} {
    ::application::media::Stop
    foreach item $::scidb::test::foldStubs {
        lassign $item mode name
        catch {rename ::media::mpv::$name {}}
        if {$mode eq "rename"} {
            catch {rename ::media::mpv::foldSaved_$name ::media::mpv::$name}
        }
    }
    set ::scidb::test::foldStubs {}
}

::application::media::Ensure
catch {
    update
    .application.nb select .application.nb.board
    update
}

tcltest::test mediafold-default {new layouts omit Media but retain its pane definition} -body {
    list [regexp {frame media} $::application::BoardLayout] \
        [info exists ::application::PaneOptions(media)]
} -result {0 1}

tcltest::test mediafold-controls {controls live below the video and move with the inset} -body {
    .application.nb select .application.nb.board
    update
    set pane [::mediainset::Pane]
    if {[winfo width $pane] < 200 || [winfo height $pane] < 200} {
        place $pane -width 500 -height 500
    }
    set video [::mediainset::surface .unused]
    set w [winfo parent $video]
    update
    list [winfo exists $w.controls.play] [winfo exists $w.controls.seek] \
        [dict get [pack info $video] -side] [dict get [pack info $w.controls] -side] \
        [expr {[winfo y $w.controls] >= [winfo y $video] + [winfo height $video]}] \
        [winfo manager $w.expand] [string match *TogglePlayback* [bind $w <space>]]
} -cleanup {::mediainset::hide} -result {1 1 top bottom 1 grid 1}

tcltest::test mediafold-transport {play pause seek stop swap and space key use the existing mpv delegates} -setup {
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
    .application.nb select .application.nb.board
    update
    set video [::mediainset::surface .unused]
    set w [winfo parent $video]
    set controls $w.controls
    set ::application::media::Priv(inprocess) 1
} -body {
    $controls.play invoke
    $controls.play invoke
    focus -force $w
    update
    event generate $w <space>
    event generate $w <space>
    ::application::media::SeekTick
    set time $::application::media::Priv(seeklabel)
    set fraction [$controls.seek get]
    $controls.seek set 500
    ::application::media::SeekRelease $controls.seek
    set done 0
    after 250 {set done 1}
    vwait done
    $w.expand invoke
    set swapped $::mediainset::Swapped
    $w.expand invoke
    set unswapped $::mediainset::Swapped
    $controls.stop invoke
    list $::scidb::test::foldCalls $time [expr {$fraction == 250}] $swapped $unswapped $::mediainset::Shown
} -cleanup {::scidb::test::foldCleanup} -result {{play pause play pause {seek 60000.0} stop} {0:30 / 2:00} 1 1 0 0}

tcltest::test mediafold-chapters {chapter prev and next appear only with multiple chapters and step chapters} -setup {
    rename ::mediainset::Entries ::mediainset::foldSavedChapterEntries
    rename ::application::media::ChapterStep ::application::media::foldSavedChapterStep
    set ::scidb::test::foldChapterEntries {{item0 Video {Chapter 1} /ch1.mp4 0}}
    set ::scidb::test::foldChapterSteps {}
    proc ::mediainset::Entries {} {return $::scidb::test::foldChapterEntries}
    proc ::application::media::ChapterStep {delta} {lappend ::scidb::test::foldChapterSteps $delta}
} -body {
    set video [::mediainset::surface .unused]
    set controls [winfo parent $video].controls
    ::mediainset::RefreshControls
    set singleMgr [list [winfo manager $controls.prev] [winfo manager $controls.next]]
    set ::scidb::test::foldChapterEntries {
        {item0 Video {Chapter 1} /ch1.mp4 0}
        {item1 Video {Chapter 2} /ch2.mp4 0}
        {item2 Audio {Commentary} /ch3.mp3 0}
    }
    ::mediainset::RefreshControls
    set multiMgr [list [winfo manager $controls.prev] [winfo manager $controls.next]]
    $controls.prev invoke
    $controls.next invoke
    list $singleMgr $multiMgr $::scidb::test::foldChapterSteps
} -cleanup {
    rename ::mediainset::Entries {}
    rename ::mediainset::foldSavedChapterEntries ::mediainset::Entries
    rename ::application::media::ChapterStep {}
    rename ::application::media::foldSavedChapterStep ::application::media::ChapterStep
    ::mediainset::hide
} -result {{{} {}} {grid grid} {-1 1}}

tcltest::test mediafold-button-menu {board button follows the shared entry list and builds a typed menu} -setup {
    rename ::mediainset::Entries ::mediainset::foldSavedEntries
    proc ::mediainset::Entries {} {return $::scidb::test::foldEntries}
} -body {
    .application.nb select .application.nb.board
    update
    set pane [::mediainset::Pane]
    set ::scidb::test::foldEntries {}
    ::mediainset::RefreshMediaButton
    update
    set hidden [list [winfo manager $pane.mediaButton] [winfo ismapped $pane.mediaButton]]
    set ::scidb::test::foldEntries {{item0 Video {Lesson one} /test.mp4 0} {item1 Audio Commentary /test.mp3 0}}
    ::mediainset::RefreshMediaButton
    update
    ::mediainset::PopulateMenu $pane.mediaButton.menu
    lassign [$pane.c bbox board] bx0 by0 bx1 by1
    set cx [winfo x $pane.c]
    set cy [winfo y $pane.c]
    set bx0 [expr {$bx0 + $cx}]
    set by0 [expr {$by0 + $cy}]
    set bx1 [expr {$bx1 + $cx}]
    set by1 [expr {$by1 + $cy}]
    set btnX [winfo x $pane.mediaButton]
    set btnY [winfo y $pane.mediaButton]
    set btnW [winfo width $pane.mediaButton]
    set btnH [winfo height $pane.mediaButton]
    set overlapsSquares [expr {
        $btnX < $bx1 && ($btnX + $btnW) > $bx0 &&
        $btnY < $by1 && ($btnY + $btnH) > $by0
    }]
    list $hidden [list [winfo manager $pane.mediaButton] [winfo ismapped $pane.mediaButton]] \
        $overlapsSquares \
        [$pane.mediaButton.menu entrycget 0 -label] \
        [$pane.mediaButton.menu entrycget 1 -label] \
        [$pane.mediaButton.menu entrycget 3 -label]
} -cleanup {
    rename ::mediainset::Entries {}
    rename ::mediainset::foldSavedEntries ::mediainset::Entries
    ::mediainset::RefreshMediaButton
} -result {{{} 0} {place 1} 0 {Lesson one (Video)} {Commentary (Audio)} {Open stream...}}

tcltest::test mediafold-actions-by-type {menu actions dispatch video stream picture audio and report correctly} -setup {
    set ::scidb::test::foldStubs {}
    set ::scidb::test::foldCalls {}
    ::scidb::test::foldStub available? {} {return 1}
    ::scidb::test::foldStub launch {path wid {startMs 0}} {
        lappend ::scidb::test::foldCalls [list launch [file tail $path] $startMs]
        return 1
    }
    ::scidb::test::foldStub state {} {return playing}
    ::scidb::test::foldStub stop {} {lappend ::scidb::test::foldCalls stop}
    ::scidb::test::foldStub duration {} {return 60}
    ::scidb::test::foldStub time {} {return 5}
    rename ::scidb::db::guidingText ::scidb::db::foldSavedGuidingText
    proc ::scidb::db::guidingText {base variant index} {
        return {isGuiding 1 title "Opening Report" html "<html><body><h3>Ruy Lopez Report</h3></body></html>" media {} anchors {} warnings {} unresolved 0 converted 0}
    }
    .application.nb select .application.nb.board
    update
} -body {
    set fixtureDir [file normalize [file join [pwd] tests tmp-app media-test MediaTest.media]]
    set vidPath [file join $fixtureDir video analysis.mp4]
    set audPath [file join $fixtureDir audio interview.wav]
    set picPath [file join $fixtureDir images bilbao2008.png]
    set tree $::application::media::Priv(tree)
    $tree delete [$tree children {}]
    set ::application::media::Priv(base) ""
    set ::application::media::Priv(variant) Normal
    set ::application::media::Priv(index) -1
    set vItem [$tree insert {} end -values [list $::application::media::mc::TypeVideo "Carlsen Clip" $vidPath -1]]
    set sItem [$tree insert {} end -values [list $::application::media::mc::TypeStream "Live Broadcast" "https://stream.example/live.m3u8" -1]]
    set pItem [$tree insert {} end -values [list $::application::media::mc::TypePicture "Position Diagram" $picPath -1]]
    set aItem [$tree insert {} end -values [list $::application::media::mc::TypeAudio "Commentary Track" $audPath -1]]
    set rItem [$tree insert {} end -values [list $::application::media::mc::SectionReports "Opening Guide" "" 0]]

    # 1. Video -> plays in inset with video canvas packed
    ::mediainset::Choose $vItem
    update
    set videoWidget [::mediainset::Pane].mediainset
    set vidState [list $::mediainset::Shown $::mediainset::Audio [winfo manager $videoWidget.video]]

    # 2. Stream -> plays in inset via PlayStream
    ::mediainset::Choose $sItem
    update
    set streamState [list $::mediainset::Shown $::mediainset::Audio $::application::media::Priv(lastMedia)]

    # 3. Picture -> opens .mediaPicture toplevel with image
    ::mediainset::Choose $pItem
    update
    set picState [list [winfo exists .mediaPicture] [expr {[llength [.mediaPicture.canvas find all]] > 0}]]
    destroy .mediaPicture

    # 4. Audio -> plays in inset with only control bar (video unpacked)
    ::mediainset::Choose $aItem
    update
    set audHeight [winfo height $videoWidget]
    set expectedAudHeight [expr {[winfo reqheight $videoWidget.controls] + 8}]
    set audState [list $::mediainset::Shown $::mediainset::Audio [winfo manager $videoWidget.video] [winfo manager $videoWidget.controls] [expr {$audHeight == $expectedAudHeight}]]

    # 5. Report -> opens report viewer pane in board TWM
    set ::application::media::Priv(base) $vidPath
    set twm [::application::twm board]
    ::mediainset::Choose $rItem
    update
    set repState [$twm isdocked report]
    if {$repState} {
        ::application::twm::ChangeState $twm report
        update
    }

    list $vidState $streamState $picState $audState $repState
} -cleanup {
    catch {
        rename ::scidb::db::guidingText {}
        rename ::scidb::db::foldSavedGuidingText ::scidb::db::guidingText
    }
    ::scidb::test::foldCleanup
    ::mediainset::AudioOnly 0
} -result {{1 0 pack} {1 0 https://stream.example/live.m3u8} {1 1} {1 1 {} pack 1} 1}

tcltest::test mediafold-audio {audio hides the video through relayout and swap} -body {
    .application.nb select .application.nb.board
    update
    set video [::mediainset::surface .unused]
    ::mediainset::AudioOnly 1
    ::mediainset::Layout
    ::mediainset::swap
    set w [winfo parent $video]
    list [winfo manager $video] [dict get [place info $w] -relheight] \
        [winfo manager $w.controls]
} -cleanup {::mediainset::hide; ::mediainset::AudioOnly 0} -result {{} 0 pack}

tcltest::test mediafold-pane-reopen {Media pane is absent by default and reopenable via the pane menu} -body {
    .application.nb select .application.nb.board
    update
    set twm [::application::twm board]
    set defaultDocked [$twm isdocked media]
    set defaultInspect [regexp {frame media} [::application::twm::inspectLayout $twm]]
    ::application::twm::ChangeState $twm media
    update
    set openedDocked [$twm isdocked media]
    set openedInspect [regexp {frame media} [::application::twm::inspectLayout $twm]]
    ::application::twm::ChangeState $twm media
    update
    set closedDocked [$twm isdocked media]
    list $defaultDocked $defaultInspect $openedDocked $openedInspect $closedDocked
} -result {0 0 1 1 0}

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

tcltest::test mediafold-mediatest-sci {MediaTest.sci drives button visibility chapters BoardSync and Interactive segments in the inset} -setup {
    set ::scidb::test::foldStubs {}
    set ::scidb::test::foldCalls {}
    set ::scidb::test::foldTime 0.0
    ::scidb::test::foldStub available? {} {return 1}
    ::scidb::test::foldStub launch {path wid {startMs 0}} {
        lappend ::scidb::test::foldCalls [list launch [file tail $path] $startMs]
        return 1
    }
    ::scidb::test::foldStub state {} {return playing}
    ::scidb::test::foldStub stop {} {lappend ::scidb::test::foldCalls stop}
    ::scidb::test::foldStub duration {} {return 90}
    ::scidb::test::foldStub time {} {return $::scidb::test::foldTime}
    proc ::scidb::test::foldProgress {args} {}
    .application.nb select .application.nb.board
    update
} -body {
    set sciPath [file normalize [file join [pwd] tests tmp-app media-test MediaTest.sci]]
    if {![::scidb::db::get open? $sciPath]} {
        ::scidb::db::load $sciPath ::scidb::test::foldProgress {} -readonly 1
    }
    ::scidb::db::switch $sciPath Normal
    set pane [::mediainset::Pane]

    # Game 1 (Carlsen-Kramnik) has M03 (Picture), M04 (Video), M06 (Video), M07 (Stream) -> Media button placed & mapped
    ::game::new .application -base $sciPath -variant Normal -number 1
    update
    set done 0
    after 30 {set done 1}
    vwait done
    update
    set g1Btn [list [winfo manager $pane.mediaButton] [winfo ismapped $pane.mediaButton]]
    set g1Count [llength [::mediainset::Entries]]

    # Find M04 (analysis.mp4) row in tree and play it in the inset
    set tree $::application::media::Priv(tree)
    set m04Item ""
    foreach row [::application::media::MediaRows] {
        if {[string match "*analysis.mp4" [lindex [$tree item $row -values] 2]]} {
            set m04Item $row
            break
        }
    }
    ::mediainset::Choose $m04Item
    update
    set w $pane.mediainset
    set chapterBtns [list [winfo manager $w.controls.prev] [winfo manager $w.controls.next]]

    # Step playback clock through BoardSync timestamps (6.0s -> 1.e4, 14.0s -> 2.Nf3)
    set fenStart [lindex [split [::scidb::game::fen -1] " "] 0]
    set ::scidb::test::foldTime 7.0
    ::application::media::FollowTick
    set fenAt7 [lindex [split [::scidb::game::fen -1] " "] 0]
    set ::scidb::test::foldTime 15.0
    ::application::media::FollowTick
    set fenAt15 [lindex [split [::scidb::game::fen -1] " "] 0]

    # Interactive segments: step board to 3.Bb5 (ply 5) and verify InteractiveFollow triggers clip range 10000ms
    ::application::media::Stop
    ::scidb::game::go -1 start
    ::scidb::game::go -1 +5
    array unset ::application::media::Priv "interactive:played:*"
    set ::scidb::test::foldCalls {}
    ::application::media::InteractiveFollow $::application::media::Priv(position)
    set interactiveLoad $::scidb::test::foldCalls

    # When no game/database with media is open -> Media button hidden
    ::application::media::Stop
    set ::application::media::Priv(lastBase) ""
    ::application::media::Update -1
    update
    set noMediaBtn [list [winfo manager $pane.mediaButton] [winfo ismapped $pane.mediaButton]]

    list $g1Btn [expr {$g1Count >= 4}] $chapterBtns \
        [expr {$fenStart ne $fenAt7}] [expr {$fenAt7 ne $fenAt15}] \
        $interactiveLoad $noMediaBtn
} -cleanup {
    ::scidb::test::foldCleanup
} -result {{place 1} 1 {grid grid} 1 1 {{launch analysis.mp4 10000.0}} {{} 0}}

tcltest::test mediafold-backend {closing a Media pane leaves the shared model alive} -body {
    ttk::frame .application.foldPane
    ::application::media::build {} .application.foldPane 400 300
    set tree $::application::media::Priv(tree)
    ::application::media::closed .application.foldPane
    destroy .application.foldPane
    list [winfo exists $tree] [winfo manager .application.mediaBackend]
} -result {1 {}}

tcltest::cleanupTests
