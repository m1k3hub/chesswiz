# Production inset geometry. Only the player backend is replaced; Tk, board
# drawing, reserve/rebuild and the application model run unchanged.
package require tcltest 2.5
namespace eval ::w1 {
    variable dir [file normalize tests/tmp-app/w1]
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
    set ::w1::layout [array get ::board::layout]
    array set ::board::layout {side-to-move 1 material-values 1 material-bar 1}
    set ::w1::minimum [wm minsize .application]
    wm minsize .application 1 1
    if {$shape eq "default"} {
        wm geometry .application 1800x950+0+0
        wait
    } else { ::w1::size wide }
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
    array set ::board::layout $::w1::layout
    wm minsize .application {*}$::w1::minimum
    update
}
proc ::w1::size {shape} {
    set sw [winfo screenwidth .]; set sh [winfo screenheight .]
    set t [::application::twm board]
    if {$shape eq "small"} {
        set w [expr {min(550,$sw-40)}]; set h [expr {min(520,$sh-60)}]
    } else {
        if {$shape eq "wide"} {
            set w [expr {min(1800,$sw-40)}]; set h [expr {min(950,$sh-80)}]
        } else {
            set h [expr {min(1750,$sh-60)}]; set w [expr {min(720,$sw-40,$h-180)}]
        }
    }
    wm geometry .application ${w}x${h}+0+0
    # A forced pane size is an allowed contract precondition. Preserve every
    # other live pane and its subscriptions, temporarily placing the board
    # over the workspace; its production canvas still packs normally.
    place [::mediainset::Pane] -in $t -x 0 -y 0 -relwidth 1 -relheight 1 -width 0 -height 0
    wait
}
proc ::w1::play {{path {}}} {
    if {$path eq ""} {set path [file normalize tests/tmp-app/media-test/MediaTest.media/video/analysis.mp4]}
    assert {[::application::media::PlayInProcess $path]} "player start failed"
    wait
    return [::mediainset::Pane].mediainset
}
proc ::w1::rect {widget} {
    list [winfo rootx $widget] [winfo rooty $widget] [winfo width $widget] [winfo height $widget]
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
    set data [dict create canvas [rect $c] inset [rect $w] controls [rect $w.controls] \
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
    if {$shot} {exec import -window root $::w1::dir/$target-[winfo screenwidth .]x[winfo screenheight .].png}
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

tcltest::test brd-wide {BRD-001 reserves a right strip including all decorations} -setup {::w1::setup [expr {[winfo screenwidth .]>=1500 ? "default" : "wide"}]} -body {
    ::w1::play
    set c $::application::board::Vars(widget:frame)
    ::w1::assert {[winfo width $c]>[winfo height $c]} "wide precondition"
    ::w1::reserved VAL-BRD-001 right 1
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
    ::w1::play
    ::game::new .application
    ::w1::wait
    ::w1::clear VAL-BRD-003B
    return ok
} -cleanup {::w1::cleanup} -result ok

tcltest::test brd-close-db {BRD-003C closing the playing database restores the board} -setup {::w1::setup} -body {
    set base [file normalize tests/tmp-app/media-test/MediaTest.sci]
    if {![::scidb::db::get open? $base]} {::scidb::db::load $base {apply {args {return 0}}} {} -readonly 1}
    ::scidb::db::switch $base Normal
    ::game::new .application -base $base -variant Normal -number 1
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
tcltest::test brd-resize {BRD-005 rebuild hook settles once without the old timer} -setup {::w1::setup} -body {
    ::w1::play
    foreach name {Relayout RebuildBoard} ns {::mediainset ::application::board} {
        trace add execution ${ns}::$name enter [list ::w1::count $name]
    }
    trace add execution ::mediainset::Relayout leave ::w1::settled
    try {
        foreach fraction {0.83 0.90 0.95} {
            array set ::w1::count {Relayout 0 RebuildBoard 0}
            set width [expr {int([winfo screenwidth .]*$fraction)}]
            set height [expr {int(min(950,[winfo screenheight .]*0.85))}]
            set start [clock milliseconds]
            set ::w1::settledAt $start
            wm geometry .application ${width}x${height}
            update
            # Suppress the old independent resize timer if one is present.
            foreach id [after info] {
                if {[lindex [after info $id] 0] eq "::mediainset::Relayout"} {after cancel $id}
            }
            ::w1::wait 450
            set elapsed [expr {$::w1::settledAt-$start}]
            ::w1::reserved VAL-BRD-005
            ::w1::log VAL-BRD-005 [list elapsed $elapsed counts [array get ::w1::count] width $width height $height]
            ::w1::assert {$elapsed<500 && $::w1::count(Relayout)==1 && $::w1::count(RebuildBoard)<=2} "resize callback not bounded"
        }
    } finally {
        trace remove execution ::mediainset::Relayout leave ::w1::settled
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
    ::w1::assert {[winfo width $w]==[winfo width [::mediainset::Pane]]} "video not expanded"
    $w.expand invoke
    ::w1::wait
    ::w1::reserved VAL-BRD-006-restored right 1
    return ok
} -cleanup {::w1::cleanup} -result ok

tcltest::test brd-failure {BRD-008 failed start releases the inset and a following file works} -setup {::w1::setup} -body {
    ::w1::play
    set ::w1::fail 1
    ::w1::assert {![::application::media::PlayInProcess /bad.mp4]} "failed backend returned success"
    ::w1::wait
    ::w1::clear VAL-BRD-008
    ::w1::assert {!$::mediainset::Shown && ![winfo ismapped [::mediainset::Pane].mediainset]} "failed inset mapped"
    ::w1::log VAL-BRD-008 [list status $::application::media::Priv(statusbar)]
    ::w1::assert {[string match *Could* $::application::media::Priv(statusbar)]} "failure status absent"
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
    set w [::w1::play [file normalize tests/tmp-app/media-test/MediaTest.media/audio/interview.wav]]
    set aw [winfo width $w]
    ::w1::measure VAL-BRD-010-audio
    ::w1::assert {$::mediainset::Audio && [winfo manager $w.video] eq ""} "audio has video"
    ::w1::assert {[winfo height $w]==[winfo reqheight $w.controls]+8} "audio strip exceeds control margin"
    ::w1::play
    ::w1::reserved VAL-BRD-010-video right
    ::w1::assert {[winfo width $w]>=$aw && [winfo height $w]>[winfo reqheight $w.controls]+8} "video did not grow strip"
    ::w1::play [file normalize tests/tmp-app/media-test/MediaTest.media/audio/interview.wav]
    ::w1::assert {[winfo height $w]==[winfo reqheight $w.controls]+8} "audio did not shrink strip"
    return ok
} -cleanup {::w1::cleanup} -result ok

tcltest::test brd-fullscreen {BRD-009 menu fullscreen drives reserve placement} -setup {::w1::setup} -body {
    ::w1::play
    ::w1::reserved VAL-BRD-009-windowed
    set before [winfo geometry .application]
    ::menu::viewFullscreen toggle
    ::w1::wait
    ::w1::reserved VAL-BRD-009-fullscreen
    set full [winfo geometry .application]
    ::menu::viewFullscreen toggle
    ::w1::wait
    ::w1::reserved VAL-BRD-009-restored
    ::w1::log VAL-BRD-009 [list before $before full $full after [winfo geometry .application] binding [bind .application <<Fullscreen>>]]
    if {$before eq $full} {error "Blocked: WM did not realise fullscreen geometry (event path exercised)"}
    return ok
} -cleanup {::w1::cleanup} -result ok

tcltest::test brd-3d {BRD-007 and BRD-003D visible 3D geometry and toggle restoration} -setup {::w1::setup} -body {
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
    ::w1::reserved VAL-BRD-007-2d right
    ::application::media::Stop
    foreach flag {1 0} {
        ::application::board::show3D $flag
        ::w1::wait
        ::w1::clear VAL-BRD-003D
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

tcltest::cleanupTests
