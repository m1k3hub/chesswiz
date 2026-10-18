# Board transport shares the Media pane's model and playback delegates.
package require tcltest 2.5

proc ::scidb::test::foldRecord {target data} {
    file mkdir tests/tmp-app/w1c
    set f [open tests/tmp-app/w1c/$target-media.txt a]
    puts $f $data
    close $f
    puts "$target $data"
}


proc ::scidb::test::foldStub {name args body} {
    if {[llength [info commands ::media::mpv::$name]]} {
        rename ::media::mpv::$name ::media::mpv::foldSaved_$name
        lappend ::scidb::test::foldStubs [list rename $name]
    } else {
        lappend ::scidb::test::foldStubs [list delete $name]
    }
    proc ::media::mpv::$name $args $body
}
# Replace only a managed game slot. A fresh app is in independent slot 9,
# which is not an entry in game::List and must use the normal add path.
proc ::scidb::test::foldGame {args} {
    set count [llength $::game::List]
    set current [::scidb::game::current]
    if {$count && ($current < 0 || $current >= $count || $current == 9)} {
        for {set slot 0} {$slot < $count && $slot < 9} {incr slot} {
            if {[::scidb::game::query $slot open?]} {
                ::application::pgn::select $slot
                ::scidb::game::switch $slot
                set current $slot
                break
            }
        }
    }
    set replace [expr {$current >= 0 && $current < $count && $current != 9}]
    set pos [::game::new .application -replace $replace {*}$args]
    if {$pos < 0 || $pos == 9} {error "could not load test game"}
    return $pos
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
    # Tests using synthetic rows/owners must give the real model back.
    ::application::media::Update [::scidb::game::current]
    update
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
    ::mediainset::Layout
    update idletasks
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
    ::scidb::test::foldRecord VAL-MED-001B [list controls {play pause seek stop} calls $::scidb::test::foldCalls time $time fraction $fraction]
    list $::scidb::test::foldCalls $time [expr {$fraction == 250}] $swapped $unswapped $::mediainset::Shown
} -cleanup {::scidb::test::foldCleanup} -result {{play pause play pause {seek 60000.0} stop} {0:30 / 2:00} 1 1 0 0}

tcltest::test mediafold-chapters {only the playing item supplies chapters; each button seeks within it} -setup {
    set ::scidb::test::foldStubs {}
    set ::scidb::test::foldChapters {}
    set ::scidb::test::foldTime 30
    set ::scidb::test::foldCalls {}
    set ::scidb::test::foldChapterSteps {}
    ::scidb::test::foldStub chapters {} {return $::scidb::test::foldChapters}
    ::scidb::test::foldStub time {} {return $::scidb::test::foldTime}
    ::scidb::test::foldStub seek {ms} {
        lappend ::scidb::test::foldCalls [list seek $ms]
        set ::scidb::test::foldTime [expr {$ms/1000.0}]
    }
    proc ::scidb::test::foldChapterTrace {cmd op} {
        lappend ::scidb::test::foldChapterSteps [lindex $cmd 1]
    }
    trace add execution ::application::media::ChapterStep enter ::scidb::test::foldChapterTrace
} -body {
    set video [::mediainset::surface .unused]
    set controls [winfo parent $video].controls
    set ::application::media::Priv(inprocess) 1
    set ::application::media::Priv(lastMedia) /same-item.mp4
    ::mediainset::RefreshControls
    set singleMgr [list [winfo manager $controls.prev] [winfo manager $controls.next]]
    # Separate files are never chapters, irrespective of gallery size.
    ::application::media::InsertEntry 3 One /one.mp4 -1
    ::application::media::InsertEntry 3 Two /two.mp4 -1
    ::mediainset::RefreshControls
    set separateMgr [list [winfo manager $controls.prev] [winfo manager $controls.next]]
    set ::scidb::test::foldChapters {0 60000}
    ::mediainset::RefreshControls
    update idletasks
    set multiMgr [list [winfo manager $controls.prev] [winfo manager $controls.next]]
    $controls.next invoke
    $controls.prev invoke
    ::scidb::test::foldRecord VAL-MED-002 [list chapterSource ::media::mpv::chapters stubStarts $::scidb::test::foldChapters single $singleMgr separateFiles $separateMgr chaptered $multiMgr steps $::scidb::test::foldChapterSteps seekLog $::scidb::test::foldCalls lastMedia $::application::media::Priv(lastMedia)]
    list $singleMgr $separateMgr $multiMgr $::scidb::test::foldChapterSteps \
        $::scidb::test::foldCalls $::application::media::Priv(lastMedia)
} -cleanup {
    trace remove execution ::application::media::ChapterStep enter ::scidb::test::foldChapterTrace
    ::scidb::test::foldCleanup
} -result {{{} {}} {{} {}} {grid grid} {1 -1} {{seek 60000.0} {seek 0.0}} /same-item.mp4}

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
} -result {{place 1} {place 1} 0 {Lesson one (Video)} {Commentary (Audio)} {Open stream...}}

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
    update idletasks
    set w [winfo parent $video]
    list [winfo manager $video] [expr {[winfo height $w] == [winfo reqheight $w.controls]+8}] \
        [winfo manager $w.controls]
} -cleanup {::mediainset::hide; ::mediainset::AudioOnly 0} -result {{} 1 pack}

tcltest::test mediafold-pane-reopen {Media pane is absent by default and reopenable via the pane menu} -body {
    .application.nb select .application.nb.board
    update
    set twm [::application::twm board]
    set defaultDocked [$twm isdocked media]
    set defaultInspect [regexp {frame media} [::application::twm::inspectLayout $twm]]
    ::application::twm::ChangeState $twm media
    update
    set openedDocked [$twm isdocked media]
    set openedMapped [winfo ismapped .application.mediaBackend]
    set openedInspect [regexp {frame media} [::application::twm::inspectLayout $twm]]
    ::application::twm::ChangeState $twm media
    update
    set closedDocked [$twm isdocked media]
    list $defaultDocked $defaultInspect $openedDocked $openedInspect $closedDocked $openedMapped
} -result {0 0 1 1 0 1}

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
    set pos [::scidb::test::foldGame -base $sciPath -variant Normal -number 1]
    if {$pos < 0 || $pos == 9} {error "could not load MediaTest game"}
    ::application::media::Update $pos
    # Build the independent native mainline oracle before playback. Native
    # navigation emits board notifications, so it must not run inside ticks.
    set slot [::game::nextGamePosition]
    ::scidb::game::load $slot $sciPath Normal 1
    ::scidb::game::go $slot start
    set expectedFens [list [::scidb::game::fen $slot]]
    for {set ply 1} {$ply <= 18} {incr ply} {
        ::scidb::game::go $slot 1
        lappend expectedFens [::scidb::game::fen $slot]
    }
    ::scidb::game::release $slot
    ::scidb::game::go -1 end
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

    # Start at the end, as when selecting a lesson after manual navigation.
    # Bare BoardSync steps must rewind to the actual goal, not assume ply 0.
    set fenStart [lindex [split [::scidb::game::fen -1] " "] 0]
    set ::scidb::test::foldTime 7.0
    ::application::media::FollowTick
    set fenAt7 [lindex [split [::scidb::game::fen -1] " "] 0]
    set ::scidb::test::foldTime 15.0
    ::application::media::FollowTick
    set fenAt15 [lindex [split [::scidb::game::fen -1] " "] 0]
    set checks {}
    foreach time {0 6 10 14 18 22 26 30 34 38 42 46 50 54 58 62 66 70 74 7 15 31} ply {0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 1 3 7} {
        set ::scidb::test::foldTime $time
        ::application::media::FollowTick
        set actual [::scidb::game::fen -1]
        set expected [lindex $expectedFens $ply]
        # Position FEN includes board, turn, castling and en-passant. The
        # native incremental replay does not retain halfmove clock history.
        lappend checks [expr {[lrange $actual 0 3] eq [lrange $expected 0 3]}]
        ::scidb::test::foldRecord VAL-MED-006 [list time $time ply $ply actual $actual expected $expected]
    }
    if {0 in $checks} {error "BoardSync FEN differs at a step timestamp"}

    # Interactive segments: step board to 3.Bb5 (ply 5) and verify InteractiveFollow triggers clip range 10000ms
    ::application::media::Stop
    ::scidb::game::go -1 start
    ::scidb::game::go -1 +5
    array unset ::application::media::Priv "interactive:played:*"
    set ::scidb::test::foldCalls {}
    ::application::media::InteractiveFollow $::application::media::Priv(position)
    set interactiveLoad $::scidb::test::foldCalls
    # Range playback must retain M04's board timeline and follow the clock.
    set ::scidb::test::foldTime 15
    ::application::media::FollowTick
    if {[::scidb::game::ply] != 3} {error "interactive range lost BoardSync"}

    # No game/database with media: the button stays for Open stream (VAL-MED-008)
    ::application::media::Stop
    set ::application::media::Priv(lastBase) ""
    ::application::media::Update -1
    update
    set noMediaBtn [list [winfo manager $pane.mediaButton] [winfo ismapped $pane.mediaButton]]

    ::scidb::test::foldRecord VAL-MED-006 [list time7 $fenAt7 time15 $fenAt15 start $fenStart segmentLaunch $interactiveLoad]
    list $g1Btn [expr {$g1Count >= 4}] $chapterBtns \
        [expr {$fenStart ne $fenAt7}] [expr {$fenAt7 ne $fenAt15}] \
        $interactiveLoad $noMediaBtn
} -cleanup {
    ::scidb::test::foldCleanup
} -result {{place 1} 1 {{} {}} 1 1 {{launch analysis.mp4 10000.0}} {place 1}}

tcltest::test mediafold-backend {closing a Media pane leaves the shared model alive} -body {
    ttk::frame .application.foldPane
    ::application::media::build {} .application.foldPane 400 300
    set tree $::application::media::Priv(tree)
    ::application::media::closed .application.foldPane
    destroy .application.foldPane
    list [winfo exists $tree] [winfo manager .application.mediaBackend]
} -result {1 {}}

# Contract evidence from the live widget/model surface.
proc ::scidb::test::foldRect {w} {
    list [winfo rootx $w] [winfo rooty $w] [winfo width $w] [winfo height $w]
}
proc ::scidb::test::foldWait {} {
    set ::scidb::test::foldWaiting 0
    after 350 {set ::scidb::test::foldWaiting 1}
    vwait ::scidb::test::foldWaiting
    update idletasks
}
tcltest::test mediafold-control-rects {MED-001A controls below video in normal and swapped modes} -body {
    wm geometry .application 1200x720
    ::scidb::test::foldWait
    set video [::mediainset::surface .unused]
    set w [winfo parent $video]
    set results {}
    foreach mode {normal swapped} {
        if {$mode eq "swapped"} {$w.expand invoke}
        ::scidb::test::foldWait
        ::scidb::test::foldRecord VAL-MED-001A [list mode $mode inset [::scidb::test::foldRect $w] \
            video [::scidb::test::foldRect $video] controls [::scidb::test::foldRect $w.controls] \
            order [pack slaves $w] videoPack [pack info $video] barPack [pack info $w.controls]]
        lappend results [expr {[winfo y $w.controls]>=[winfo y $video]+[winfo height $video]}]
    }
    set results
} -cleanup {::mediainset::hide} -result {1 1}

tcltest::test mediafold-focus-time {MED-001C time advances and Space is local to inset focus} -setup {
    set ::scidb::test::foldStubs {}
    set ::scidb::test::foldCalls {}
    set ::scidb::test::foldTime 30
    ::scidb::test::foldStub state {} {return playing}
    ::scidb::test::foldStub time {} {return $::scidb::test::foldTime}
    ::scidb::test::foldStub duration {} {return 120}
    ::scidb::test::foldStub pause {} {lappend ::scidb::test::foldCalls pause}
    ::scidb::test::foldStub stop {} {}
} -body {
    ::application::switchTab board
    ::application::media::Update [::scidb::game::current]
    ::scidb::test::foldWait
    set w [winfo parent [::mediainset::surface .unused]]
    ::scidb::test::foldWait
    set ::application::media::Priv(inprocess) 1
    ::application::media::SeekTick
    set first [$w.controls.time cget -text]
    set ::scidb::test::foldTime 65
    ::application::media::SeekTick
    set second [$w.controls.time cget -text]
    focus -force $w.controls.play
    update
    if {![winfo ismapped $w.controls.play] || [focus] ne "$w.controls.play"} {error "inset focus precondition failed"}
    event generate $w.controls.play <KeyPress-space>
    update
    set inside $::scidb::test::foldCalls
    entry .application.foldOutside
    place .application.foldOutside -x 0 -y 0 -width 100 -height 24
    focus -force .application.foldOutside
    update
    if {[focus] ne ".application.foldOutside" || ![winfo ismapped .application.foldOutside]} {error "outside focus precondition failed"}
    event generate .application.foldOutside <KeyPress-space>
    update
    if {[.application.foldOutside get] ne " "} {error "outside key event was not delivered"}
    ::scidb::test::foldRecord VAL-MED-001C [list first $first second $second inside $inside outside $::scidb::test::foldCalls]
    list $first $second $inside $::scidb::test::foldCalls
} -cleanup {destroy .application.foldOutside; ::scidb::test::foldCleanup} -result {{0:30 / 2:00} {1:05 / 2:00} pause pause}

tcltest::test mediafold-real-menu {MED-003/004 real MediaTest rows dispatch picture/video/stream/audio} -setup {
    set ::scidb::test::foldStubs {}
    set ::scidb::test::foldCalls {}
    ::scidb::test::foldStub available? {} {return 1}
    ::scidb::test::foldStub launch {path wid {ms 0}} {lappend ::scidb::test::foldCalls [list launch $path $wid $ms]; return 1}
    ::scidb::test::foldStub state {} {return playing}
    ::scidb::test::foldStub time {} {return 0}
    ::scidb::test::foldStub duration {} {return 90}
    ::scidb::test::foldStub stop {} {}
} -body {
    set base [file normalize tests/tmp-app/media-test/MediaTest.sci]
    if {![::scidb::db::get open? $base]} {::scidb::db::load $base {apply {args {return 0}}} {} -readonly 1}
    ::scidb::db::switch $base Normal
    set pos [::scidb::test::foldGame -base $base -variant Normal -number 1]
    # The legacy test above simulates independent mode with Update -1 while
    # keeping this same game open. Restore the real model before this case.
    if {$pos < 0 || $pos == 9} {error "could not load MediaTest game"}
    ::application::media::Update $pos
    ::scidb::test::foldWait
    set pane [::mediainset::Pane]
    set menu $pane.mediaButton.menu
    ::mediainset::PopulateMenu $menu
    set labels {}; set entries [::mediainset::Entries]
    set matches [expr {[llength [::application::media::MediaRows]] == [llength [::scidb::db::mediaFiles $base Normal 1]]}]; set index 0
    ::scidb::test::foldRecord VAL-MED-003B [list slot $pos current [::scidb::game::current] modelPosition $::application::media::Priv(position) modelBase $::application::media::Priv(base) modelIndex $::application::media::Priv(index) link [::scidb::game::link? $pos] expected [::scidb::db::mediaFiles $base Normal 1]]
    foreach entry $entries {
        lassign $entry row type title path owner
        set label [$menu entrycget $index -label]
        lappend labels $label
        if {$label ne "$title ($type)"} {set matches 0}
        incr index
    }
    ::scidb::test::foldRecord VAL-MED-003A [list withMedia [winfo ismapped $pane.mediaButton]]
    ::scidb::test::foldRecord VAL-MED-003B [list entries $entries menu $labels openStream [$menu entrycget end -label]]
    set states {}
    foreach type {Video Stream Picture} id {VAL-MED-004A VAL-MED-004B VAL-MED-004C} {
        set index 0
        foreach entry $entries {
            if {[lindex $entry 1] eq $type} {break}
            incr index
        }
        $menu invoke $index
        ::scidb::test::foldWait
        if {$type eq "Picture"} {
            set state [list [winfo exists .mediaPicture] [expr {[llength [.mediaPicture.canvas find all]]>0}]]
            ::scidb::test::foldRecord $id [list viewer .mediaPicture class [winfo class .mediaPicture] source [lindex $entry 3] state $state]
            destroy .mediaPicture
        } else {
            set state [list $::mediainset::Shown [winfo manager $pane.mediainset.video]]
            ::scidb::test::foldRecord $id [list state $state lastMedia $::application::media::Priv(lastMedia) calls $::scidb::test::foldCalls]
        }
        lappend states $state
    }
    ::scidb::test::foldGame -base $base -variant Normal -number 0
    ::scidb::test::foldWait
    ::mediainset::PopulateMenu $menu
    set index 0
    foreach entry [::mediainset::Entries] {
        if {[lindex $entry 1] eq "Audio"} {break}
        incr index
    }
    $menu invoke $index
    ::scidb::test::foldWait
    set w $pane.mediainset
    set audio [list $::mediainset::Shown $::mediainset::Audio [winfo manager $w.video] \
        [expr {[winfo height $w]==[winfo height $w.controls]+8}]]
    ::scidb::test::foldRecord VAL-MED-004D [list audio $audio rect [::scidb::test::foldRect $w] controls [::scidb::test::foldRect $w.controls] calls $::scidb::test::foldCalls]
    ::scidb::test::foldGame
    ::scidb::test::foldWait
    set hidden [winfo ismapped $pane.mediaButton]
    ::scidb::test::foldRecord VAL-MED-003A [list noMedia $hidden current [::scidb::game::current] position $::application::media::Priv(position) entries [::mediainset::Entries]]
    list $matches $states $audio $hidden
} -cleanup {::scidb::test::foldCleanup} -result {1 {{1 pack} {1 pack} {1 1}} {1 1 {} 1} 1}

tcltest::test mediafold-report-file {MED-004E generated report entry opens the existing HTML viewer} -body {
    set base [file normalize tests/tmp-app/media-test/MediaTest.sci]
    if {![::scidb::db::get open? $base]} {::scidb::db::load $base {apply {args {return 0}}} {} -readonly 1}
    set pos [::scidb::test::foldGame -base $base -variant Normal -number 1]
    if {$pos < 0 || $pos == 9} {error "could not load MediaTest game"}
    ::application::media::Update $pos
    ::scidb::test::foldWait
    set tree $::application::media::Priv(tree)
    set row {}
    foreach item [::application::media::MediaRows] {
        lassign [$tree item $item -values] type title path owner
        if {$type eq $::application::media::mc::SectionReports} {set row $item; set report $path; break}
    }
    if {$row eq ""} {error "MediaTest HTML report fixture missing; run tests/tmp-app/media-test/make.sh"}
    ::mediainset::RefreshMediaButton
    ::mediainset::PopulateMenu [::mediainset::Pane].mediaButton.menu
    set index [lsearch -index 0 [::mediainset::Entries] $row]
    [::mediainset::Pane].mediaButton.menu invoke $index
    update
    set win $::application::report::Priv(window)
    ::scidb::test::foldRecord VAL-MED-004E [list fixture $report viewer $win toplevel [winfo toplevel $win] class [winfo class $win] document $::application::report::Priv(data)]
    list [winfo ismapped $win] [string match *Generated* [dict get $::application::report::Priv(data) html]]
} -cleanup {
    set t [::application::twm board]
    if {[$t isdocked report]} {::application::twm::ChangeState $t report}
} -result {1 1}

tcltest::test mediafold-saved-pane {MED-005 saved Media pane survives an empty game refresh} -setup {
    set twm [::application::twm board]
    set original [::application::twm::inspectLayout $twm]
} -body {
    if {![$twm isdocked media]} {::application::twm::ChangeState $twm media}
    update
    # A saved fixture with Media in its own pane, rather than behind a tab.
    set saved [string map {{frame tree} {frame media {-width 400 -height 300 -minwidth 250 -minheight 200 -expand y} frame tree}} $original]
    ::application::twm::ChangeState $twm media
    update
    $twm load $saved
    update
    ::application::media::Update -1
    update
    ::scidb::test::foldRecord VAL-MED-005 [list default $::application::BoardLayout saved $saved realised [::application::twm::inspectLayout $twm] docked [$twm isdocked media]]
    list [$twm isdocked media] [winfo ismapped .application.mediaBackend]
} -cleanup {$twm load $original; update} -result {1 1}

# VAL-MED-008: Open stream is reachable with the Media pane hidden, for a
# game without media and with no game, and the menu never blocks a script.
proc ::scidb::test::med008State {tag} {
    set w [::mediainset::Pane].mediaButton
    set labels {}
    for {set i 0} {$i <= [$w.menu index end]} {incr i} {
        if {[$w.menu type $i] eq "command"} {lappend labels [$w.menu entrycget $i -label]}
    }
    set state [list [winfo manager $w] [winfo ismapped $w] [winfo class $w] $labels [expr {$labels eq [::mediainset::MediaMenuLabels]}]]
    ::scidb::test::foldRecord VAL-MED-008 [list $tag mediaPaneMapped [winfo ismapped .application.mediaBackend] button $state]
    return $state
}
tcltest::test mediafold-008-visible {Media button is mapped with a no-media game and with no game; menu lists game media and Open stream...} -setup {
    set ::scidb::test::foldStubs {}
    .application.nb select .application.nb.board
    update
} -body {
    set base [file normalize tests/tmp-app/media-test/MediaTest.sci]
    if {![::scidb::db::get open? $base]} {::scidb::db::load $base {apply {args {return 0}}} {} -readonly 1}
    set pos [::scidb::test::foldGame -base $base -variant Normal -number 1]
    ::application::media::Update $pos
    ::scidb::test::foldWait
    set media [::scidb::test::med008State with-media]
    set pos [::scidb::test::foldGame]
    ::application::media::Update $pos
    ::scidb::test::foldWait
    set plain [::scidb::test::med008State no-media-game]
    ::application::media::Update -1
    ::scidb::test::foldWait
    set none [::scidb::test::med008State no-game]
    list [lrange $media 0 2] [expr {[llength [lindex $media 3]] > 1}] [lindex [lindex $media 3] end] [lindex $media 4] \
        [winfo ismapped .application.mediaBackend] $plain $none
} -cleanup {::scidb::test::foldCleanup} -result {{place 1 TButton} 1 {Open stream...} 1 0 {place 1 TButton {{Open stream...}} 1} {place 1 TButton {{Open stream...}} 1}}

tcltest::test mediafold-008-stream {choosing Open stream... and entering a URL plays it in the board inset (stub player)} -setup {
    set ::scidb::test::foldStubs {}
    set ::scidb::test::foldCalls {}
    ::scidb::test::foldStub available? {} {return 1}
    ::scidb::test::foldStub launch {path wid {ms 0}} {lappend ::scidb::test::foldCalls [list launch $path]; return 1}
    ::scidb::test::foldStub state {} {return playing}
    ::scidb::test::foldStub time {} {return 1}
    ::scidb::test::foldStub duration {} {return 60}
    ::scidb::test::foldStub stop {} {}
    ::scidb::test::foldStub aspect {} {return 1.7778}
    ::scidb::test::foldStub chapters {} {return {}}
    .application.nb select .application.nb.board
    wm geometry .application [expr {min(1200,[winfo screenwidth .]-40)}]x780+0+0
    ::application::media::Update [::scidb::test::foldGame]
    ::scidb::test::foldWait
    ::scidb::test::foldWait
} -body {
    set w [::mediainset::Pane].mediaButton
    set url https://test-videos.example/vids/bigbuckbunny.mp4
    $w.menu invoke [$w.menu index end]
    update
    set dlg .application.__mediastream__
    set opened [winfo exists $dlg]
    $dlg.top.url set $url
    $dlg.ok invoke
    ::scidb::test::foldWait
    ::scidb::test::foldWait
    set inset [::mediainset::Pane].mediainset
    set c $::application::board::Vars(widget:frame)
    lassign [$c bbox board] x0 y0 x1 y1
    set board [list [expr {[winfo rootx $c]+$x0}] [expr {[winfo rooty $c]+$y0}] [expr {$x1-$x0}] [expr {$y1-$y0}]]
    lassign $board bx by bw bh; lassign [::scidb::test::foldRect $inset] ix iy iw ih
    set overlap [expr {max(0,min($bx+$bw,$ix+$iw)-max($bx,$ix))*max(0,min($by+$bh,$iy+$ih)-max($by,$iy))}]
    ::scidb::test::foldRecord VAL-MED-008 [list stream calls $::scidb::test::foldCalls shown $::mediainset::Shown inset [::scidb::test::foldRect $inset] canvas [::scidb::test::foldRect $c] window [wm geometry .application] board $board overlap $overlap reserve [::application::board::reserveRect] status $::application::media::Priv(statusbar)]
    if {[info exists ::env(W1_EVIDENCE_DIR)]} {catch {exec import -window root [file join $::env(W1_EVIDENCE_DIR) VAL-MED-008-stream.png]}}
    # A board pane too small for a strip uses the BRD-004 corner overlay.
    list $opened [winfo exists $dlg] $::scidb::test::foldCalls $::mediainset::Shown [winfo ismapped $inset] [expr {$overlap == 0 || [::application::board::reserveRect] eq {0 0 0 0}}]
} -cleanup {
    catch {after cancel $::application::media::Priv(checkid)}
    catch {destroy .application.__mediastream__}
    ::scidb::test::foldCleanup
} -result {1 0 {{launch https://test-videos.example/vids/bigbuckbunny.mp4}} 1 1 1}

tcltest::test mediafold-008-no-hang {scripted button post/unpost and entry reads complete within 1 s, 20 times each, leaving no grab} -setup {
    set ::scidb::test::foldStubs {}
    ::application::media::Update [::scidb::test::foldGame]
    ::scidb::test::foldWait
} -body {
    set w [::mediainset::Pane].mediaButton
    set posts {}; set reads {}; set posted 0
    for {set i 0} {$i < 20} {incr i} {
        set t0 [clock milliseconds]
        $w invoke
        update
        if {[winfo ismapped $w.menu]} {incr posted}
        $w.menu unpost
        ::tk::MenuUnpost $w.menu
        update
        lappend posts [expr {[clock milliseconds]-$t0}]
        set t0 [clock milliseconds]
        set labels {}
        for {set k 0} {$k <= [$w.menu index end]} {incr k} {
            if {[$w.menu type $k] eq "command"} {lappend labels [$w.menu entrycget $k -label]}
        }
        lappend labels [$w cget -command] [::mediainset::MediaMenuLabels]
        lappend reads [expr {[clock milliseconds]-$t0}]
    }
    set maxPost [tcl::mathfunc::max {*}$posts]; set maxRead [tcl::mathfunc::max {*}$reads]
    ::scidb::test::foldRecord VAL-MED-008 [list no-hang posts $posts reads $reads posted $posted grab [grab current] unmapped [expr {![winfo ismapped $w.menu]}]]
    list [expr {$maxPost < 1000}] [expr {$maxRead < 1000}] $posted [grab current] [winfo ismapped $w.menu]
} -cleanup {::scidb::test::foldCleanup} -result {1 1 20 {} 0}

# VAL-MED-010: the Media pane is dropped from a pre-fold saved layout once, at
# the fist start after the upgrade, and stays an optional library afterwards.
# Each phase is a separate fresh app process, so the real startup path
# (::application::twm::load -> RemoveLegacyMedia) runs.
proc ::scidb::test::migRun {dir phase} {
    set log [file join $dir phase$phase.log]
    set bin [file normalize src/tkchesswiz]
    set script [file join [file normalize tests] fixtures media-mig phase.tcl]
    set home [file join $dir home]
    if {[catch {
        exec {*}[list timeout 120 env HOME=$home MIG_PHASE=$phase MIG_ROOT=[file normalize .] \
            LIBGL_ALWAYS_SOFTWARE=1 SCIDB_AI_UNCALIBRATED=1 \
            $bin $script] > $log 2>@1
    } msg]} {
        return -code error "migration phase $phase failed: $msg"
    }
    set f [open $log]
    set data [read $f]
    close $f
    return $data
}

tcltest::test mediafold-010-migration {VAL-MED-010 a pre-fold layout loses Media once and stays an optional library} -setup {
    set ::scidb::test::migDir [file join $::scidb::test::app::testDir tmp-app media-mig-[pid]]
    file delete -force $::scidb::test::migDir
    file mkdir [file join $::scidb::test::migDir home]
} -body {
    set dir $::scidb::test::migDir
    set p1 [::scidb::test::migRun $dir 1]
    set p2 [::scidb::test::migRun $dir 2]
    set p3 [::scidb::test::migRun $dir 3]
    ::scidb::test::foldRecord VAL-MED-010 [list phase1 $p1 phase2 $p2 phase3 $p3]
    list \
        [regexp {MIG P1 prefold 1 marker 0} $p1] \
        [regexp {MIG P2 media 0 marker 1} $p2] \
        [regexp {MIG P2 .* tree 1 analysis 1 board 1 editor 1 games 1 dbgames 1} $p2] \
        [regexp {MIG P2 reopened 1 mapped 1} $p2] \
        [regexp {MIG P3 media 1 docked 1 marker 1} $p3]
} -cleanup {file delete -force $::scidb::test::migDir} -result {1 1 1 1 1}

tcltest::cleanupTests
