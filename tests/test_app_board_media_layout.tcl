# Production inset geometry. Only the player backend is replaced; Tk, board
# drawing, reserve/rebuild and the application model run unchanged.
package require tcltest 2.5

# Embedded 3D requires Togl, which the Aqua bundle does not ship. Probe the
# capability before calling show3D, whose unavailable-feature warning is modal.
tcltest::testConstraint embedded3D [::board3d::LoadToglLib]
tcltest::testConstraint x11Pointer [expr {
    [tk windowingsystem] eq "x11" && [llength [auto_execok xdotool]] > 0}]
namespace eval ::w1 {
    # Resolve fixtures from the runner, rather than an undefined global root.
    variable root [file dirname $::scidb::test::app::testDir]
    variable dir [file normalize $::w1::root/tests/tmp-app/w1c]
    if {[info exists ::env(W1_EVIDENCE_DIR)]} {set dir [file normalize $::env(W1_EVIDENCE_DIR)]}
    variable stubs {}
    variable calls {}
    variable now 0
    variable aspect [expr {16.0/9}]
    variable fail 0
    variable available 1
}
proc ::w1::wait {{ms 350}} {
    set ::w1::waiting 0
    after $ms {set ::w1::waiting 1}
    vwait ::w1::waiting
    update idletasks
}
# Fullscreen attributes can change before Cocoa finishes its Space animation.
# Observe window and child geometry, rather than sampling after a fixed sleep.
# This readiness wait is separate from BRD-005's unchanged resize measurement.
proc ::w1::fullscreenSettled {enabled} {
    set deadline [expr {[clock milliseconds]+10000}]
    set previous {}
    set quietSince [clock milliseconds]
    while {[clock milliseconds] < $deadline} {
        wait 50
        set full [expr {[winfo width .application] == [winfo screenwidth .application]
            && [winfo height .application] == [winfo screenheight .application]}]
        set pane [::mediainset::Pane]
        set snapshot [list [rect .application] [rect $pane] [rect [::mediainset::BoardView]]]
        if {[winfo exists $pane.mediainset.expand]} {
            lappend snapshot [rect $pane.mediainset.expand]
        }
        if {$snapshot ne $previous || $full != $enabled
            || [wm attributes .application -fullscreen] != $enabled} {
            set quietSince [clock milliseconds]
            set previous $snapshot
        } elseif {[clock milliseconds]-$quietSince >= 500} {
            log fullscreen-settled [list enabled $enabled geometry $snapshot]
            return
        }
    }
    error "fullscreen transition did not settle: enabled=$enabled geometry=$snapshot"
}
proc ::w1::log {target data} {
    variable dir
    file mkdir $dir
    set f [open $dir/$target-[winfo screenwidth .]x[winfo screenheight .].txt a]
    puts $f $data
    close $f
    puts "$target $data"
}
proc ::w1::assert {condition message} {
    if {![uplevel 1 [list expr $condition]]} { error $message }
}
proc ::w1::stub {name args body} {
    variable stubs
    rename ::media::mpv::$name ::w1::saved_$name
    proc ::media::mpv::$name $args $body
    lappend stubs $name
}
# Replace only a managed game slot. A fresh app is in independent slot 9,
# which is not an entry in game::List and must use the normal add path.
proc ::w1::game {args} {
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

proc ::w1::setup {{shape wide}} {
    variable calls {}
    variable now 0
    variable fail 0
    variable available 1
    variable aspect [expr {16.0/9}]
    set ::tips::Options(mode) neverShow
    update
    wait 650
    catch {destroy .tipoftheday}
    ::application::switchTab board
    ::application::media::Ensure
    ::application::media::Stop
    stub available? {} {return $::w1::available}
    stub launch {path wid {ms 0}} {
        lappend ::w1::calls [list launch $path $wid $ms]
        return [expr {!$::w1::fail}]
    }
    stub state {} {return playing}
    stub time {} {return $::w1::now}
    stub duration {} {return 120}
    stub stop {} {lappend ::w1::calls stop}
    stub aspect {} {return $::w1::aspect}
    stub chapters {} {return {}}
    set ::w1::geometry [wm geometry .application]
    set ::w1::twm [::application::twm board]
    set ::w1::paneLayout [::application::twm::inspectLayout $::w1::twm]
    set ::w1::insetOptions [array get ::mediainset::Options]
    set ::w1::layout [array get ::board::layout]
    array set ::board::layout {side-to-move 1 material-values 1 material-bar 1}
    set ::w1::minimum [wm minsize .application]
    wm minsize .application 1 1
    if {$shape eq "default"} {
        set default $::application::BoardLayout
        foreach name [array names ::application::PaneOptions] {
            set default [string map [list %${name}% [list $::application::PaneOptions($name)]] $default]
        }
        $::w1::twm load $default
        wm geometry .application 1007x718+0+0
        wait
    } else { ::w1::size $shape }
    set base [file normalize $::w1::root/tests/tmp-app/media-test/MediaTest.sci]
    if {![::scidb::db::get open? $base]} {::scidb::db::load $base {apply {args {return 0}}} {} -readonly 1}
    set pos [::w1::game -base $base -variant Normal -number 1]
    assert {$pos >= 0 && $pos != 9} "could not load generated media game"
    ::application::media::Update $pos
    wait
}
proc ::w1::cleanup {} {
    ::menu::setFullscreen 0
    ::application::media::Stop
    ::application::board::show3D 0
    foreach name $::w1::stubs {
        rename ::media::mpv::$name {}
        rename ::w1::saved_$name ::media::mpv::$name
    }
    set ::w1::stubs {}
    array set ::mediainset::Options $::w1::insetOptions
    array set ::board::layout $::w1::layout
    wm minsize .application {*}$::w1::minimum
    place forget [::mediainset::Pane]
    ::application::reflow::reset
    $::w1::twm load $::w1::paneLayout
    wm geometry .application $::w1::geometry
    wait
}
proc ::w1::size {shape} {
    set sw [winfo screenwidth .]; set sh [winfo screenheight .]
    set t [::application::twm board]
    if {$shape eq "small"} {
        set w [expr {min(400,$sw-40)}]; set h [expr {min(380,$sh-60)}]
    } else {
        if {$shape eq "wide"} {
            set w [expr {min(1800,$sw-40)}]; set h [expr {min(950,$sh-80)}]
        } else {
            set h [expr {min(1750,$sh-60)}]; set w [expr {min(720,$sw-40,$h-180)}]
        }
    }
    wm geometry .application ${w}x${h}+0+0
    # Let the session reflow (debounced) settle first: its layout load
    # re-manages the board pane and would drop the forced placement below.
    wait
    # A forced pane size is an allowed contract precondition. Preserve every
    # other live pane and its subscriptions, temporarily placing the board
    # over the workspace; its production canvas still packs normally.
    place [::mediainset::Pane] -in $t -x 0 -y 0 -relwidth 1 -relheight 1 -width 0 -height 0
    wait
}
proc ::w1::play {{path {}}} {
    if {$path eq ""} {set path [file normalize $::w1::root/tests/tmp-app/media-test/MediaTest.media/video/analysis.mp4]}
    assert {[::application::media::PlayInProcess $path]} "player start failed"
    wait
    return [::mediainset::Pane].mediainset
}
proc ::w1::rect {widget} {
    list [winfo rootx $widget] [winfo rooty $widget] [winfo width $widget] [winfo height $widget]
}
# VAL-MED-009: the inset frame, the video, the board view and the pane.
proc ::w1::rects {w} {
    list [rect $w] [rect $w.video] [rect [::mediainset::BoardView]] [rect [winfo parent $w]]
}
proc ::w1::near {a b} {
    set a [concat {*}$a]
    set b [concat {*}$b]
    if {[llength $a] != [llength $b]} { return 0 }
    foreach x $a y $b { if {abs($x-$y) > 1} { return 0 } }
    return 1
}
# The state-aware size control: face, tooltip and the video's hover tooltip.
proc ::w1::control {w} {
    list [$w.expand cget -text] $::mediainset::mc::ExpandTooltip $::mediainset::mc::VideoTooltip
}
# Earlier tests may leave their own toplevel log or notice cards over the
# board pane. They are not part of the inset geometry under test.
proc ::w1::quiet {} {
    catch {wm withdraw .application.log}
    if {[llength [info commands ::dialog::notice::Dismiss]]} {
        foreach card $::dialog::notice::Cards {
            catch {::dialog::notice::Dismiss [lindex $card 0]}
        }
    }
    update idletasks
}
# VAL-MED-009: what Tk window is on top at the centre of the Expand/Restore
# control, and at the centre of the small board while it is swapped in.
proc ::w1::topAtControl {w} {
    set cx [expr {[winfo rootx $w.expand] + [winfo width $w.expand]/2}]
    set cy [expr {[winfo rooty $w.expand] + [winfo height $w.expand]/2}]
    return [list $cx $cy [winfo containing $cx $cy]]
}
proc ::w1::topAtBoard {} {
    set view [::mediainset::BoardView]
    set cx [expr {[winfo rootx $view] + [winfo width $view]/2}]
    set cy [expr {[winfo rooty $view] + [winfo height $view]/2}]
    return [list $cx $cy [winfo containing $cx $cy]]
}
# The control is never underneath the board. While the board is the small
# overlay, the transport cluster must not cover its squares either.
proc ::w1::unoccluded {tag w} {
    lassign [::w1::topAtControl $w] cx cy top
    lassign [::w1::topAtBoard] bx by btop
    set board [::mediainset::BoardView]
    set small [expr {$::mediainset::Swapped && !$::mediainset::Audio}]
    set control [set w].expand
    set controlTop [expr {$top eq $control}]
    set boardTop [expr {!$small || [string first $board $btop] == 0}]
    set overlap [expr {!$small ? 0 : [::w1::overlap [::w1::rect $w.controls] [::w1::rect $board]]}]
    ::w1::log VAL-MED-009-unoccluded [list state $tag button [::w1::rect $w.expand] \
        board [::w1::rect $board] controlCentre $cx $cy controlTop $top onControl $controlTop \
        boardCentre $bx $by boardTop $btop onBoard $boardTop controlsBoardOverlap $overlap]
    return [expr {$controlTop && $boardTop && $overlap == 0}]
}
proc ::w1::shot {name} {
    # Screenshot evidence uses X11 import. Aqua still records all geometry;
    # taking desktop screenshots there requires separate OS permissions.
    if {[tk windowingsystem] eq "aqua"} {return}
    variable dir
    file mkdir $dir
    catch { ::util::execSafe import -window root $dir/$name-[winfo screenwidth .]x[winfo screenheight .].png }
}
# The inset's own visible frame, and whether it sits inside its pane (its
# outer edge, and so the ridge border, is never clipped by the pane).
proc ::w1::frameStyle {w} {
    list [$w cget -relief] [$w cget -borderwidth] [$w cget -highlightthickness]
}
proc ::w1::inside {w} {
    set pane [winfo parent $w]
    expr {[winfo x $w] >= 0 && [winfo y $w] >= 0 \
        && [winfo x $w]+[winfo width $w] <= [winfo width $pane] \
        && [winfo y $w]+[winfo height $w] <= [winfo height $pane]}
}
# Each gesture that toggles the layout: the button, a double-click on the
# video and Escape while the inset has focus.
proc ::w1::trigger {w mode} {
    switch -- $mode {
        button { $w.expand invoke }
        double {
            event generate $w.video <ButtonPress-1>
            event generate $w.video <ButtonRelease-1>
            event generate $w.video <ButtonPress-1>
            event generate $w.video <ButtonRelease-1>
        }
        escape { focus -force $w.video; update idletasks; event generate $w.video <Escape> }
    }
    wait
}
proc ::w1::overlap {a b} {
    lassign $a x y w h; lassign $b xx yy ww hh
    expr {max(0,min($x+$w,$xx+$ww)-max($x,$xx))*max(0,min($y+$h,$yy+$hh)-max($y,$yy))}
}
proc ::w1::measure {target {shot 0}} {
    set p [::mediainset::Pane]; set w $p.mediainset; set c $p.c
    # Non-empty material bbox from the real decoration renderer, using generated data.
    $c delete material
    ::application::board::AddMaterial 1 p $c 0 1
    set data [dict create window [winfo geometry .application] square $::application::board::Dim(squaresize:Normal) canvas [rect $c] inset [rect $w] controls [rect $w.controls] \
        video [rect $w.video] mapped [winfo ismapped $w] videoManager [winfo manager $w.video] \
        reserve [::application::board::reserveRect] side $::application::board::ReserveSide]
    foreach tag {board stm material} {
        set box [$c bbox $tag]
        assert {[llength $box] == 4} "missing production canvas tag $tag"
        lassign $box x y xx yy
        set r [list [expr {$x+[winfo rootx $c]}] [expr {$y+[winfo rooty $c]}] [expr {$xx-$x}] [expr {$yy-$y}]]
        dict set data bbox:$tag $box
        dict set data overlap:$tag [overlap [rect $w] $r]
    }
    dict set data allowances [list stm $::application::board::Dim(stm) material-bar $::board::layout(material-bar) gap:x $::application::board::Dim(gap:x)]
    log $target $data
    # Required states always get screenshots, including callers that omit
    # the optional flag. Other states keep rectangle/status evidence only.
    if {[regexp {^VAL-BRD-00[126]} $target]} {set shot 1}
    if {$shot} {::w1::shot $target}
    return $data
}
proc ::w1::clear {target} {
    set c $::application::board::Vars(widget:frame)
    assert {[::application::board::reserveRect] eq {0 0 0 0}} "stale reserve"
    set actual [$c bbox board]
    set saved [array get ::application::board::Dim]
    ::application::board::ComputeLayout [winfo width $c] [winfo height $c]
    upvar #0 ::application::board::Dim d
    set expected [list $d(border:x1) $d(border:y1) $d(border:x2) $d(border:y2)]
    array set ::application::board::Dim $saved
    log $target [list actual $actual reference $expected]
    foreach a $actual b $expected {assert {abs($a-$b)<=1} "board differs from no-reserve layout"}
}
proc ::w1::reserved {target {side {}} {shot 0}} {
    set d [measure $target $shot]
    assert {[dict get $d mapped]} "production inset unmapped"
    if {$side ne ""} {assert {[dict get $d side] eq $side} "wrong reserve side"}
    foreach tag {board stm material} {assert {[dict get $d overlap:$tag]==0} "inset overlaps $tag"}
    lassign [dict get $d reserve] x y rw rh
    lassign [dict get $d inset] ix iy iw ih
    if {[dict get $d side] eq "right"} {assert {abs($rw-$iw)<=2} "wrong reserve width"} else {assert {abs($rh-$ih)<=2} "wrong reserve height"}
    set w [::mediainset::Pane].mediainset
    assert {[winfo manager $w.video] eq "pack"} "production video unmanaged"
    assert {abs(double([winfo width $w.video])/[winfo height $w.video] - $::w1::aspect)<0.02} "video aspect lost"
    return $d
}

# Run before any other test creates the embedded view. In particular, the
# tall, docked pane must not inherit geometry from an earlier 3D toggle.
tcltest::test brd-3d-first {BRD-007 first 3D toggle during playback uses the realised frame including its toolbar} -constraints embedded3D -setup {::w1::setup default} -body {
    ::w1::assert {$::application::board::Vars(3dwin) eq "" || ![winfo exists $::application::board::Vars(3dwin)]} "first-toggle test requires an uncreated 3D view"
    set sw [winfo screenwidth .]; set sh [winfo screenheight .]
    wm geometry .application [expr {min(1800,$sw-30)}]x[expr {$sh-150}]+0+0
    ::w1::wait
    set w [::w1::play]
    ::w1::assert {[::application::board::show3D 1]} "Blocked: 3D view unavailable"
    set start [clock milliseconds]
    set view [::mediainset::BoardView]
    for {set ms 100} {$ms <= 3000} {incr ms 100} {
        ::w1::wait [expr {max(1,$start+$ms-[clock milliseconds])}]
        set overlap [::w1::overlap [::w1::rect $view] [::w1::rect $w]]
        set toolbarOverlap [::w1::overlap [::w1::rect $view.camera] [::w1::rect $w]]
        ::w1::log VAL-BRD-007-first [list elapsed [expr {[clock milliseconds]-$start}] view [::w1::rect $view] \
            inset [::w1::rect $w] toolbar [::w1::rect $view.camera] reserve [::application::board::reserveRect] \
            overlap $overlap toolbarOverlap $toolbarOverlap]
        ::w1::assert {[winfo ismapped $view] && [winfo ismapped $view.camera] && [winfo ismapped $w] && [winfo manager $w.video] eq "pack"} "production views not mapped"
        ::w1::assert {$overlap == 0 && $toolbarOverlap == 0} "first 3D view/toolbar overlaps inset"
    }
    ::w1::shot VAL-BRD-007-first
    ::application::board::show3D 0
    ::w1::wait
    ::w1::reserved VAL-BRD-007-first-restored
    return ok
} -cleanup {::w1::cleanup} -result ok

tcltest::test brd-wide {BRD-001 reserves a right strip including all decorations} -setup {::w1::setup default} -body {
    # The old saved preferred width must shrink to the 160px lower bound.
    set ::mediainset::Options(minWidth) 200
    ::w1::play
    set c $::application::board::Vars(widget:frame)
    ::w1::assert {[winfo width $c]>[winfo height $c]} "wide precondition"
    ::w1::reserved VAL-BRD-001 right 1
    ::w1::assert {$::application::board::Dim(squaresize:Normal) >= 32} "board below minimum square"
    set w [::mediainset::Pane].mediainset
    ::w1::assert {[winfo width $w.video] >= 160} "video below minimum width"
    # Exercise the media's own aspect, rather than a hard-coded 16:9 frame.
    set ::w1::aspect [expr {4.0/3}]
    ::mediainset::RefreshAspect
    update idletasks
    ::w1::reserved VAL-BRD-001-aspect right
    return ok
} -cleanup {::w1::cleanup} -result ok

tcltest::test brd-tall {BRD-002 bottom strip on a measured tall canvas} -setup {::w1::setup; ::w1::size tall} -body {
    ::w1::play
    set c $::application::board::Vars(widget:frame)
    ::w1::assert {[winfo height $c]>[winfo width $c]} "tall precondition"
    ::w1::reserved VAL-BRD-002 bottom 1
    return ok
} -cleanup {::w1::cleanup} -result ok

tcltest::test brd-stop {BRD-003A Stop restores the no-reserve board} -setup {::w1::setup} -body {
    set w [::w1::play]
    $w.controls.stop invoke
    ::w1::wait
    ::w1::clear VAL-BRD-003A
    ::w1::assert {![winfo ismapped $w]} "stopped inset still mapped"
    return ok
} -cleanup {::w1::cleanup} -result ok

tcltest::test brd-no-media {BRD-003B loading a generated game without media clears the inset} -setup {::w1::setup} -body {
    set base [file normalize $::w1::root/tests/tmp-app/media-test/MediaTest.sci]
    if {![::scidb::db::get open? $base]} {::scidb::db::load $base {apply {args {return 0}}} {} -readonly 1}
    ::w1::game -base $base -variant Normal -number 1
    ::w1::wait
    ::w1::play
    set pos [::w1::game]
    ::w1::assert {$pos >= 0 && $pos != 9} "empty game switch failed"
    ::w1::wait
    ::w1::clear VAL-BRD-003B
    return ok
} -cleanup {::w1::cleanup} -result ok

tcltest::test brd-close-db {BRD-003C closing the playing database restores the board} -setup {::w1::setup} -body {
    set base [file normalize $::w1::root/tests/tmp-app/media-test/MediaTest.sci]
    if {![::scidb::db::get open? $base]} {::scidb::db::load $base {apply {args {return 0}}} {} -readonly 1}
    ::scidb::db::switch $base Normal
    ::w1::game -base $base -variant Normal -number 1
    ::w1::wait
    ::w1::play
    ::scidb::db::close $base
    ::w1::wait
    ::w1::clear VAL-BRD-003C
    return ok
} -cleanup {::w1::cleanup} -result ok

tcltest::test brd-minimum {BRD-004 refusal keeps square size and uses the corner} -setup {::w1::setup; ::w1::size small} -body {
    set before $::application::board::Dim(squaresize:Normal)
    set w [::w1::play]
    ::w1::measure VAL-BRD-004 1
    ::w1::assert {$::application::board::ReserveSide eq ""} "small reserve was accepted"
    ::w1::assert {$before==$::application::board::Dim(squaresize:Normal)} "refusal resized squares"
    ::w1::assert {[dict get [place info $w] -anchor] eq "se"} "fallback is not in corner"
    ::w1::log VAL-BRD-004 [list before $before after $::application::board::Dim(squaresize:Normal) minimum $::application::board::MinimumReserveSquare]
    return ok
} -cleanup {::w1::cleanup} -result ok

proc ::w1::count {name cmd op} {incr ::w1::count($name)}
proc ::w1::settled {args} {set ::w1::settledAt [clock milliseconds]}
proc ::w1::configured {args} {set ::w1::configuredAt [clock milliseconds]}
tcltest::test brd-resize {BRD-005 rebuild hook settles once without the old timer} -setup {::w1::setup} -body {
    ::w1::play
    foreach name {Relayout RebuildBoard} ns {::mediainset ::application::board} {
        trace add execution ${ns}::$name enter [list ::w1::count $name]
    }
    trace add execution ::mediainset::Relayout leave ::w1::settled
    trace add execution ::application::board::ConfigureWindow enter ::w1::configured
    try {
        foreach fraction {0.83 0.90 0.95} {
            array set ::w1::count {Relayout 0 RebuildBoard 0}
            set width [expr {int([winfo screenwidth .]*$fraction)}]
            # Stay wide of the reflow threshold: BRD-005 times a plain
            # resize; a wide/tall reflow is a layout load (pane-video-*).
            set height [expr {int(min(950,[winfo screenheight .]*0.85,$width/1.3))}]
            set ::w1::configuredAt 0
            set ::w1::settledAt 0
            wm geometry .application ${width}x${height}
            update
            # Suppress the old independent resize timer if one is present.
            foreach id [after info] {
                if {[lindex [after info $id] 0] eq "::mediainset::Relayout"} {after cancel $id}
            }
            ::w1::wait 450
            set elapsed [expr {$::w1::settledAt-$::w1::configuredAt}]
            ::w1::reserved VAL-BRD-005
            ::w1::log VAL-BRD-005 [list configure $::w1::configuredAt settled $::w1::settledAt elapsed $elapsed counts [array get ::w1::count] width $width height $height]
            ::w1::assert {$::w1::configuredAt>0 && $elapsed>=0 && $elapsed<500 && $::w1::count(Relayout)==1 && $::w1::count(RebuildBoard)<=2} "resize callback not bounded"
        }
    } finally {
        trace remove execution ::mediainset::Relayout leave ::w1::settled
        trace remove execution ::application::board::ConfigureWindow enter ::w1::configured
        foreach name {Relayout RebuildBoard} ns {::mediainset ::application::board} {trace remove execution ${ns}::$name enter [list ::w1::count $name]}
    }
    ::application::media::Stop
    ::w1::assert {"::mediainset::BoardRebuilt" ni $::application::board::RebuildCallbacks} "hook not removed"
    return ok
} -cleanup {::w1::cleanup} -result ok

tcltest::test brd-swap {BRD-006 swap clears the reserve and return restores it} -setup {::w1::setup} -body {
    set w [::w1::play]
    $w.expand invoke
    ::w1::wait
    ::w1::measure VAL-BRD-006-swapped 1
    ::w1::assert {$::mediainset::Swapped && $::application::board::ReserveSide eq ""} "swap kept reserve"
    # Expanded video is inset by its frame margin so the frame is not clipped,
    # rather than placed flush at the pane's 0,0 with relwidth 1.
    set pane [::mediainset::Pane]
    set m $::mediainset::FrameMargin
    ::w1::assert {[winfo x $w]==$m && [winfo y $w]==$m} "video not inset from the pane edge"
    ::w1::assert {[winfo width $w]==[winfo width $pane]-2*$m && [winfo height $w]==[winfo height $pane]-2*$m} "video not inset by the frame margin"
    $w.expand invoke
    ::w1::wait
    ::w1::reserved VAL-BRD-006-restored right 1
    return ok
} -cleanup {::w1::cleanup} -result ok

tcltest::test brd-failure {BRD-008 failed start releases the inset and a following file works} -setup {::w1::setup} -body {
    ::w1::play
    set ::w1::fail 1
    set tree $::application::media::Priv(tree)
    set row [::application::media::InsertEntry 3 Failure [file normalize $::w1::root/tests/tmp-app/media-test/MediaTest.media/video/lecture2.mp4] -1]
    ::mediainset::Choose $row
    ::w1::wait
    ::w1::clear VAL-BRD-008
    ::w1::assert {!$::mediainset::Shown && ![winfo ismapped [::mediainset::Pane].mediainset]} "failed inset mapped"
    ::w1::log VAL-BRD-008 [list status $::application::media::Priv(statusbar) notices $::dialog::notice::Cards]
    ::w1::assert {[winfo ismapped $::dialog::notice::Holder]} "failure notice invisible"
    ::w1::assert {[string match *Cannot* $::application::media::Priv(statusbar)] || [string match *Could* $::application::media::Priv(statusbar)]} "failure status absent"
    set ::w1::fail 0
    ::w1::play
    ::w1::reserved VAL-BRD-008-recovered right
    set ::w1::available 0
    ::w1::assert {![::application::media::PlayInProcess /bad.mp4]} "missing backend succeeded"
    ::w1::wait
    ::w1::clear VAL-BRD-008-unavailable
    return ok
} -cleanup {::w1::cleanup} -result ok

tcltest::test brd-types {BRD-010 reserve follows audio and video surfaces} -setup {::w1::setup} -body {
    set w [::w1::play [file normalize $::w1::root/tests/tmp-app/media-test/MediaTest.media/audio/interview.wav]]
    set aw [winfo width $w]
    ::w1::measure VAL-BRD-010-audio
    ::w1::assert {$::mediainset::Audio && [winfo manager $w.video] eq ""} "audio has video"
    ::w1::assert {[winfo height $w]==[winfo reqheight $w.controls]+8} "audio strip exceeds control margin"
    ::w1::play
    ::w1::reserved VAL-BRD-010-video right
    ::w1::assert {[winfo width $w]>=$aw && [winfo height $w]>[winfo reqheight $w.controls]+8} "video did not grow strip"
    ::w1::play [file normalize $::w1::root/tests/tmp-app/media-test/MediaTest.media/audio/interview.wav]
    ::w1::assert {[winfo height $w]==[winfo reqheight $w.controls]+8} "audio did not shrink strip"
    return ok
} -cleanup {::w1::cleanup} -result ok

# Cocoa's native fullscreen transition re-manages panes. Use the actual
# managed board there, rather than the X11 fixture's forced place overlay.
tcltest::test brd-fullscreen {BRD-009 menu fullscreen drives reserve placement} -setup {
    ::w1::setup [expr {[tk windowingsystem] eq "aqua" ? "default" : "wide"}]
} -body {
    ::w1::play
    ::w1::reserved VAL-BRD-009-windowed
    set before [winfo geometry .application]
    ::menu::viewFullscreen toggle
    # Cocoa animates a native fullscreen/Space transition asynchronously.
    ::w1::fullscreenSettled 1
    ::w1::reserved VAL-BRD-009-fullscreen
    set full [winfo geometry .application]
    ::menu::viewFullscreen toggle
    ::w1::fullscreenSettled 0
    ::w1::reserved VAL-BRD-009-restored
    ::w1::log VAL-BRD-009 [list before $before full $full after [winfo geometry .application] binding [bind .application <<Fullscreen>>]]
    if {$before eq $full} {error "Blocked: WM did not realise fullscreen geometry (event path exercised)"}
    return ok
} -cleanup {::w1::cleanup} -result ok

tcltest::test brd-3d {BRD-007 and BRD-003D visible 3D geometry and toggle restoration} -constraints embedded3D -setup {::w1::setup default} -body {
    # LIBGL_ALWAYS_SOFTWARE=1 on the runner keeps the film GPUs untouched.
    ::w1::play
    ::w1::assert {[::application::board::show3D 1]} "Blocked: 3D view unavailable"
    ::w1::wait
    set w [::mediainset::Pane].mediainset
    set view [::mediainset::BoardView]
    ::w1::log VAL-BRD-007 [list view $view rect [::w1::rect $view] inset [::w1::rect $w]]
    ::w1::assert {[winfo ismapped $view] && ![winfo ismapped $::application::board::Vars(widget:frame)]} "wrong visible presentation"
    ::w1::assert {[::w1::overlap [::w1::rect $view] [::w1::rect $w]]==0} "3D overlaps inset"
    ::application::board::show3D 0
    ::w1::wait
    ::w1::reserved VAL-BRD-007-2d
    ::application::media::Stop
    foreach flag {1 0} {
        ::application::board::show3D $flag
        ::w1::wait
        # While 3D is embedded the 2D board is hidden and was last laid out
        # for the 3D slot (which carries its own reserve padding); compare
        # its layout only once it is visible again.
        if {!$flag} { ::w1::clear VAL-BRD-003D }
    }
    return ok
} -cleanup {::w1::cleanup} -result ok

tcltest::test brd-teardown {BRD-005 inset destruction unregisters the rebuild callback} -setup {::w1::setup} -body {
    set w [::w1::play]
    destroy $w
    ::w1::wait
    ::w1::assert {"::mediainset::BoardRebuilt" ni $::application::board::RebuildCallbacks} "destroy kept callback"
    ::w1::clear VAL-BRD-005-teardown
    return ok
} -cleanup {::w1::cleanup} -result ok

# VAL-MED-009: the size control names its state and its tooltips follow it.
tcltest::test inset-009-control {VAL-MED-009 the control reads Expand and Restore with matching tooltips} -setup {::w1::setup} -body {
    set w [::w1::play]
    set normal [::w1::control $w]
    ::w1::trigger $w button
    set swapped [::w1::control $w]
    ::w1::trigger $w button
    set restored [::w1::control $w]
    ::w1::log VAL-MED-009-control [list normal $normal swapped $swapped restored $restored \
        margin $::mediainset::FrameMargin]
    list \
        [expr {[lindex $normal 0] eq $::mediainset::mc::Expand}] \
        [string match {*Expand*} [lindex $normal 1]] \
        [string match {*expand*} [lindex $normal 2]] \
        [expr {[lindex $swapped 0] eq $::mediainset::mc::Restore}] \
        [expr {[lindex $normal 0] ne [lindex $swapped 0]}] \
        [string match {*Restore*} [lindex $swapped 1]] \
        [string match {*restore*} [lindex $swapped 2]] \
        [expr {$restored eq $normal}]
} -cleanup {::w1::cleanup} -result {1 1 1 1 1 1 1 1}

# VAL-MED-009: the button, a double-click and Escape each return the video and
# the board to the geometry they had before expanding.
tcltest::test inset-009-restore {VAL-MED-009 button, double-click and Escape restore the prior geometry} -setup {::w1::setup} -body {
    set w [::w1::play]
    set out {}
    foreach mode {button double escape} {
        if {$::mediainset::Swapped} { ::w1::trigger $w button }
        set before [::w1::rects $w]
        ::w1::trigger $w button
        set expanded $::mediainset::Swapped
        ::w1::trigger $w $mode
        set after [::w1::rects $w]
        set equal [::w1::near $before $after]
        ::w1::log VAL-MED-009-restore [list mode $mode before $before expanded $expanded \
            after $after equal $equal]
        lappend out [list $mode $expanded $equal]
    }
    set out
} -cleanup {::w1::cleanup} -result {{button 1 1} {double 1 1} {escape 1 1}}

# VAL-MED-009: the Expand/Restore control is the topmost window at its own
# centre in every state, including the small-board overlay after a resize.
# The small board must be offset from the transport cluster, not merely
# raised under it (V9 failure: the board covered the Restore control).
tcltest::test inset-009-unoccluded {VAL-MED-009 the size control is never covered by the small board} -setup {::w1::setup} -body {
    ::w1::quiet
    set states {}
    foreach {sw sh} [list 1024 700 1280 800] {
        if {$sw > [winfo screenwidth .] || $sh > [winfo screenheight .]} { continue }
        wm geometry .application ${sw}x${sh}+0+0
        ::w1::wait
        set w [::w1::play]
        lappend states [::w1::unoccluded "$sw-$sh-normal" $w]
        ::w1::trigger $w button
        lappend states [::w1::unoccluded "$sw-$sh-expanded" $w]
        wm geometry .application [expr {$sw-120}]x[expr {$sh-60}]
        ::w1::wait
        lappend states [::w1::unoccluded "$sw-$sh-expanded-resized" $w]
        if {![catch {::menu::viewFullscreen toggle}]} {
            ::w1::fullscreenSettled 1
            lappend states [::w1::unoccluded "$sw-$sh-expanded-fullscreen" $w]
            catch {::menu::viewFullscreen toggle}
            ::w1::fullscreenSettled 0
        }
        ::w1::trigger $w button
        lappend states [::w1::unoccluded "$sw-$sh-restored" $w]
        # leave the next size in the normal state
        if {$::mediainset::Swapped} { ::w1::trigger $w button }
    }
    ::w1::assert {[llength $states]} "no window size exercised"
    expr {[llength [lsearch -all $states 0]] == 0}
} -cleanup {::w1::cleanup} -result 1

# VAL-MED-009: the same topmost-control guarantee holds in the corner overlay,
# audio-only and 3D board states.
tcltest::test inset-009-unoccluded-states {VAL-MED-009 the control is unoccluded in corner, audio and 3D states} -constraints embedded3D -setup {::w1::setup; ::w1::size small} -body {
    ::w1::quiet
    set states {}
    set w [::w1::play]
    lappend states [::w1::unoccluded corner $w]
    ::w1::trigger $w button
    lappend states [::w1::unoccluded corner-expanded $w]
    ::w1::trigger $w button
    set w [::w1::play [file normalize $::w1::root/tests/tmp-app/media-test/MediaTest.media/audio/interview.wav]]
    lappend states [::w1::unoccluded audio $w]
    ::w1::trigger $w button
    lappend states [::w1::unoccluded audio-expanded $w]
    ::w1::trigger $w button
    wm geometry .application 1024x700+0+0
    ::w1::wait
    set w [::w1::play]
    lappend states [::w1::unoccluded 3d-pre $w]
    ::w1::assert {[::application::board::show3D 1]} "Blocked: 3D view unavailable"
    ::w1::wait
    lappend states [::w1::unoccluded 3d-normal $w]
    ::w1::trigger $w button
    lappend states [::w1::unoccluded 3d-expanded $w]
    ::w1::trigger $w button
    ::application::board::show3D 0
    ::w1::wait
    expr {[llength [lsearch -all $states 0]] == 0}
} -cleanup {::w1::cleanup} -result 1

# VAL-MED-009: a real pointer (Xvfb + xdotool), not a Tcl invoke, must reach
# the Restore control and restore the previous geometry.
tcltest::test inset-009-real-pointer {VAL-MED-009 a real pointer click on Restore restores} -constraints x11Pointer -setup {::w1::setup} -body {
    if {[auto_execok xdotool] eq ""} { error "xdotool is required for the real-pointer test" }
    ::w1::quiet
    wm geometry .application 1024x700+0+0
    ::w1::wait
    set w [::w1::play]
    set before [::w1::rects $w]
    ::w1::trigger $w button
    set expanded $::mediainset::Swapped
    lassign [::w1::topAtControl $w] cx cy top
    set control [set w].expand
    ::w1::assert {$top eq $control} "Restore control is covered by $top"
    set rc [catch {::util::execSafe xdotool mousemove $cx $cy click 1} err]
    ::w1::assert {$rc == 0} "xdotool click failed: $err"
    ::w1::wait 500
    set restored [expr {!$::mediainset::Swapped}]
    set equal [::w1::near $before [::w1::rects $w]]
    ::w1::log VAL-MED-009-real-pointer [list centre $cx $cy top $top expanded $expanded \
        restored $restored equal $equal button [::w1::rect $w.expand]]
    list $expanded [expr {$top eq $control}] $restored $equal
} -cleanup {::w1::cleanup} -result {1 1 1 1}

# VAL-MED-009: the ridge+highlight frame stays fully inside the pane in the
# normal strip, the expanded layout (inset by its margin) and audio-only, and
# the small board is framed while expanded.
tcltest::test inset-009-frame {VAL-MED-009 the frame is visible and inside the pane in every state} -setup {::w1::setup} -body {
    set w [::w1::play]
    set m $::mediainset::FrameMargin
    set view [::mediainset::BoardView]
    set original [[set view] cget -highlightthickness]
    set normal [list [::w1::inside $w] [::w1::frameStyle $w]]
    ::w1::shot VAL-MED-009-2d-normal
    ::w1::trigger $w button
    set board [::mediainset::BoardView]
    set swapped [list [::w1::inside $w] [::w1::frameStyle $w] \
        [expr {[winfo x $w] == $m && [winfo y $w] == $m}] \
        [expr {[winfo width $w] == [winfo width [winfo parent $w]] - 2*$m}] \
        [[set board] cget -highlightthickness] [winfo manager $board]]
    ::w1::shot VAL-MED-009-2d-expanded
    # a resize while expanded must keep the frame
    wm geometry .application [expr {[winfo width .application]-120}]x[expr {[winfo height .application]-60}]
    ::w1::wait
    set resized [list [::w1::inside $w] [expr {[winfo x $w] == $m && [winfo y $w] == $m}]]
    ::w1::shot VAL-MED-009-2d-expanded-resized
    ::w1::trigger $w button
    set restored [list [::w1::inside $w] [[set board] cget -highlightthickness] $original]
    ::w1::shot VAL-MED-009-2d-restored
    # audio-only keeps the inset frame around the transport strip
    set w [::w1::play [file normalize $::w1::root/tests/tmp-app/media-test/MediaTest.media/audio/interview.wav]]
    set audio [list [::w1::inside $w] [::w1::frameStyle $w] [winfo manager $w.video]]
    ::w1::shot VAL-MED-009-2d-audio
    ::w1::log VAL-MED-009-frame [list margin $m normal $normal swapped $swapped resized $resized \
        restored $restored audio $audio]
    list \
        [lindex $normal 0] [lindex $normal 1] \
        [lindex $swapped 0] [lindex $swapped 2] [lindex $swapped 3] [lindex $swapped 4] [lindex $swapped 5] \
        [lindex $resized 0] [lindex $resized 1] \
        [lindex $restored 0] [lindex $restored 1] [lindex $restored 2] \
        [lindex $audio 0] [lindex $audio 1] [lindex $audio 2]
} -cleanup {::w1::cleanup} -result {1 {ridge 3 1} 1 1 1 3 place 1 1 1 0 0 1 {ridge 3 1} {}}

# VAL-MED-009: a board pane too small for a strip keeps the frame in the
# BRD-004 corner overlay.
tcltest::test inset-009-frame-corner {VAL-MED-009 the corner overlay keeps the inset frame inside the pane} -setup {::w1::setup; ::w1::size small} -body {
    set w [::w1::play]
    set inside [::w1::inside $w]
    ::w1::log VAL-MED-009-frame-corner [list rect [::w1::rect $w] pane [::w1::rect [winfo parent $w]] \
        style [::w1::frameStyle $w] inside $inside reserve [::application::board::reserveRect]]
    list $inside [::w1::frameStyle $w]
} -cleanup {::w1::cleanup} -result {1 {ridge 3 1}}

# VAL-MED-009: the same state control, restore and frame hold for the 3D board.
tcltest::test inset-009-3d {VAL-MED-009 the 3D board keeps the control, the restore and the frame} -constraints embedded3D -setup {::w1::setup default} -body {
    set w [::w1::play]
    ::w1::assert {[::application::board::show3D 1]} "Blocked: 3D view unavailable"
    ::w1::wait
    set view [::mediainset::BoardView]
    set m $::mediainset::FrameMargin
    set normal [::w1::control $w]
    set before [::w1::rects $w]
    ::w1::shot VAL-MED-009-3d-normal
    ::w1::trigger $w button
    set expanded $::mediainset::Swapped
    set swapped [list [::w1::inside $w] [[set view] cget -highlightthickness] \
        [expr {[winfo x $w] == $m && [winfo y $w] == $m}] [winfo manager $view]]
    ::w1::shot VAL-MED-009-3d-expanded
    ::w1::trigger $w escape
    set after [::w1::rects $w]
    set restControl [::w1::control $w]
    ::w1::shot VAL-MED-009-3d-restored
    ::w1::log VAL-MED-009-3d [list view $view normal $normal before $before swapped $swapped \
        after $after expanded $expanded restored [::w1::near $before $after]]
    list \
        [expr {[lindex $normal 0] eq $::mediainset::mc::Expand}] \
        $expanded [lindex $swapped 0] [lindex $swapped 1] [lindex $swapped 2] [lindex $swapped 3] \
        [::w1::near $before $after] \
        [expr {[lindex $restControl 0] eq $::mediainset::mc::Expand}] \
        [::w1::inside $w]
} -cleanup {::w1::cleanup} -result {1 1 1 3 1 place 1 1 1}

tcltest::cleanupTests
