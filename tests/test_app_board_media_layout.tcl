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
    set started [clock milliseconds]
    set deadline [expr {$started+10000}]
    set previous {}
    set quietSince $started
    while {[clock milliseconds] < $deadline} {
        wait 50
        set full [expr {[winfo width .application] == [winfo screenwidth .application]
            && [winfo height .application] == [winfo screenheight .application]}]
        set pane [::mediainset::Pane]
        set snapshot [list [rect .application] [rect $pane] [rect [::mediainset::BoardView]]]
        if {[winfo exists $pane.mediainset.expand]} {
            lappend snapshot [rect $pane.mediainset.expand]
        }
        # A WM that never sets _NET_WM_STATE_FULLSCREEN (a bare Xvfb) leaves
        # the attribute at 0 forever. Only a real transition that is still
        # pending is waited for; after the grace period the geometry alone
        # decides, so such a display settles instead of timing out.
        set realised [expr {$full == $enabled
            && [wm attributes .application -fullscreen] == $enabled}]
        if {$snapshot ne $previous || (!$realised && [clock milliseconds]-$started < 2000)} {
            set quietSince [clock milliseconds]
            set previous $snapshot
        } elseif {[clock milliseconds]-$quietSince >= 500} {
            log fullscreen-settled [list enabled $enabled realised $realised geometry $snapshot]
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

proc ::w1::setup {{shape wide} {backend stub}} {
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
    # VAL-BRD-017: the fold's "still playing" claim needs a real clock. The
    # stubbed backend freezes ::media::mpv::time, so the fold tests run the
    # native libmpv backend instead (real playback time is the oracle).
    if {$backend eq "real"} {
        assert {[::media::mpv::available?]} "real libmpv backend unavailable"
    } else {
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
    }
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
            set h [expr {min(1750,$sh-60)}]; set w [expr {min(720,$sw-40,$h-260)}]
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
# VAL-BRD-017: play through the native backend so ::media::mpv::time is the
# real playback clock (the fixture setup stubs launch/time and freezes it).
proc ::w1::playReal {{path {}}} {
    if {$path eq ""} {set path [file normalize $::w1::root/tests/tmp-app/media-test/MediaTest.media/video/analysis.mp4]}
    assert {[::media::mpv::available?]} "real libmpv backend unavailable"
    assert {[::application::media::PlayInProcess $path]} "real player start failed"
    wait
    return [::mediainset::Pane].mediainset
}
# Wait (bounded) for the real player to report a clock, then for it to move by
# at least delta seconds. Polling the actual event, never a longer sleep and
# never a retry of a failed assertion.
proc ::w1::clockStart {tag {deadline 15000}} {
    set started [clock milliseconds]
    while {[clock milliseconds] - $started < $deadline} {
        set t [::media::mpv::time]
        if {[string is double -strict $t]} { return $t }
        update
        wait 50
    }
    error "$tag: no real playback clock within ${deadline}ms ([::application::media::MediaState])"
}
proc ::w1::progressAdvance {tag {delta 0.3} {deadline 15000}} {
    set from [clockStart $tag $deadline]
    set started [clock milliseconds]
    while {[clock milliseconds] - $started < $deadline} {
        update
        set now [::media::mpv::time]
        if {[string is double -strict $now] && $now - $from >= $delta} {
            log $tag-playback [list from $from to $now advanced [expr {$now-$from}] \
                waited [expr {[clock milliseconds]-$started}]]
            return $now
        }
        wait 50
    }
    error "$tag: playback did not advance by $delta s within ${deadline}ms (clock $from -> [::media::mpv::time])"
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
# VAL-BRD-017: the drawn-board surfaces a fold must never cover, as root
# rectangles straight from the production canvas tags.
proc ::w1::drawnBoardRects {} {
    set c $::application::board::Vars(widget:frame)
    set rects {}
    foreach tag {board stm material} {
        set box [$c bbox $tag]
        if {[llength $box] != 4} { continue }
        lassign $box x y xx yy
        lappend rects [list [expr {[winfo rootx $c]+$x}] [expr {[winfo rooty $c]+$y}] \
            [expr {$xx-$x}] [expr {$yy-$y}]]
    }
    return $rects
}
proc ::w1::folded? {} {
    expr {[info exists ::mediainset::Collapsed] && $::mediainset::Collapsed}
}
proc ::w1::handleMapped? {} {
    set handle .application.videoHandle
    expr {[winfo exists $handle] && [winfo ismapped $handle]}
}
# VAL-BRD-017: the full fold state, not overlap alone. A hidden or unmapped
# video also scores zero overlap, so the oracle also demands the mapped
# handle at its defined rectangle and a playback clock that advances.
proc ::w1::foldState {tag} {
    set w [::mediainset::Pane].mediainset
    set handle .application.videoHandle
    assert {[folded?]} "$tag: video is not folded (Collapsed is 0 or absent)"
    assert {[winfo exists $handle] && [winfo ismapped $handle]} \
        "$tag: no mapped fold handle (a merely hidden video must not pass)"
    set hr [rect $handle]
    lassign $hr hx hy hw hh
    assert {$hw == 56 && $hh == 26} "$tag: handle is not at its defined 56x26 rectangle: $hr"
    assert {$hx >= 0 && $hy >= 0 && $hx+$hw <= [winfo width .application] \
        && $hy+$hh <= [winfo height .application]} "$tag: handle is not visible in the window: $hr"
    lassign [topAtHandle] cx cy top
    assert {$top eq $handle} "$tag: handle is not topmost at its centre (found $top)"
    foreach r [drawnBoardRects] {
        assert {[overlap $hr $r] == 0} "$tag: handle covers the drawn board $r"
        assert {[overlap [rect $w] $r] == 0} "$tag: inset covers the drawn board $r"
    }
    assert {$::application::board::ReserveSide eq ""} \
        "$tag: fold left reserve side '$::application::board::ReserveSide'"
    assert {$::application::board::ReservePixels == 0} \
        "$tag: fold left $::application::board::ReservePixels reserve pixels"
    set square $::application::board::Dim(squaresize:Normal)
    set unreserved [unreserved]
    assert {$square == $unreserved} \
        "$tag: folded board square $square is not the unreserved square $unreserved"
    assert {[winfo manager $w.video] eq "pack"} "$tag: folded native surface went unmanaged"
    set now [progressAdvance $tag]
    log VAL-BRD-017-fold [list state $tag handle $hr square $square unreserved $unreserved \
        side {} pixels 0 inset [rect $w] playback $now \
        drawn [drawnBoardRects] top $top]
    return $hr
}
proc ::w1::topAtHandle {} {
    set handle .application.videoHandle
    set cx [expr {[winfo rootx $handle] + [winfo width $handle]/2}]
    set cy [expr {[winfo rooty $handle] + [winfo height $handle]/2}]
    return [list $cx $cy [winfo containing $cx $cy]]
}
# VAL-BRD-017 audio branch: the opposite expectation. Audio never folds or
# gets a handle. Where a strip fits it keeps the VAL-MED-009 audio strip;
# where none fits it keeps the decision-5 bottom-right transport cluster
# (VAL-BRD-020) and the accepted board overlap is MEASURED and recorded.
proc ::w1::audioPlacement {tag w} {
    set handle .application.videoHandle
    set pane [winfo parent $w]
    set side $::application::board::ReserveSide
    assert {$::mediainset::Audio} "$tag: media was not classified audio-only"
    assert {![folded?]} "$tag: audio-only media folded"
    assert {![winfo exists $handle] || ![winfo ismapped $handle]} "$tag: a fold handle is shown for audio"
    assert {[winfo ismapped $w]} "$tag: audio inset is hidden"
    set ir [rect $w]
    lassign $ir ix iy iw ih
    set ch [expr {[winfo reqheight $w.controls]+8}]
    if {$side eq ""} {
        # No strip fits: production's bottom-right cluster, 6 px inside the pane.
        lassign [rect $pane] px py pw ph
        set cw [expr {[winfo reqwidth $w.controls]+8}]
        set ew [expr {min($cw, max(1, $pw-12))}]
        set expected [list [expr {$px+$pw-6-$ew}] [expr {$py+$ph-6-$ch}] $ew $ch]
        assert {[near $ir $expected]} \
            "$tag: audio is not at the VAL-BRD-020 bottom-right placement: got $ir expected $expected"
        assert {$::application::board::ReservePixels == 0} \
            "$tag: audio took reserve pixels without a strip"
    } else {
        assert {[winfo manager $w.video] eq ""} "$tag: audio has a video surface in a strip"
    }
    set overlap 0
    foreach r [drawnBoardRects] { incr overlap [overlap $ir $r] }
    if {$side eq ""} {
        # The accepted decision-5 outcome: measured, never assumed to be zero.
        assert {$overlap > 0} "$tag: tiny audio placement measured no board overlap"
    } else {
        assert {$overlap == 0} "$tag: audio strip covers the drawn board ($overlap px)"
    }
    log VAL-BRD-020-placement [list state $tag audio 1 collapsed 0 side $side \
        pixels $::application::board::ReservePixels inset $ir pane [rect $pane] \
        overlap $overlap drawn [drawnBoardRects]]
    return [list $ir $overlap]
}
# VAL-BRD-015: the Media button menu now carries exactly one Stop row between
# the media rows and Open stream..., enabled while a player holds the media.
# Invoke that row (not ::application::media::Stop) so the label is expected
# and exercised while the video is folded.
proc ::w1::stopViaMenu {tag} {
    set menu [::mediainset::Pane].mediaButton.menu
    ::mediainset::PopulateMenu $menu
    set labels {}
    set stopIdx -1
    set last [$menu index end]
    for {set i 0} {$i <= $last} {incr i} {
        if {[$menu type $i] eq "separator"} { lappend labels "<separator>"; continue }
        set label [$menu entrycget $i -label]
        lappend labels $label
        if {$label eq "Stop"} { set stopIdx $i }
    }
    assert {$stopIdx >= 0} "$tag: Media menu has no Stop row: $labels"
    assert {[$menu entrycget $stopIdx -state] eq "normal"} "$tag: Stop disabled while playing"
    assert {[$menu type [expr {$last-1}]] ne "separator" \
        && [$menu entrycget [expr {$last-1}] -label] eq "Stop"} \
        "$tag: Stop is not immediately before Open stream...: $labels"
    assert {[$menu entrycget $last -label] eq "Open stream..."} \
        "$tag: Open stream... is not the last row: $labels"
    $menu invoke $stopIdx
    wait 500
    log VAL-BRD-015-stop [list state $tag labels $labels stopIndex $stopIdx \
        collapsed [folded?] reserve [::application::board::reserveRect] \
        inprocess $::application::media::Priv(inprocess)]
    assert {![folded?]} "$tag: fold survived the Media-menu Stop"
    assert {$::application::board::ReserveSide eq "" && $::application::board::ReservePixels == 0} \
        "$tag: reserve survived the Media-menu Stop"
    set handle .application.videoHandle
    assert {![winfo exists $handle] || ![winfo ismapped $handle]} \
        "$tag: handle survived the Media-menu Stop"
    return ok
}
# VAL-BRD-011: with no feasible strip the video folds, so the reachable
# control is the fold handle; it must be mapped and topmost at its centre.
proc ::w1::foldUnoccluded {tag} {
    set handle .application.videoHandle
    set folded $::mediainset::Collapsed
    set mapped [expr {[winfo exists $handle] && [winfo ismapped $handle]}]
    if {!$mapped} {
        ::w1::log VAL-MED-009-unoccluded [list state $tag folded $folded handle missing]
        return 0
    }
    set cx [expr {[winfo rootx $handle] + [winfo width $handle]/2}]
    set cy [expr {[winfo rooty $handle] + [winfo height $handle]/2}]
    set top [winfo containing $cx $cy]
    ::w1::log VAL-MED-009-unoccluded [list state $tag folded $folded handle [::w1::rect $handle] \
        centre $cx $cy top $top onHandle [expr {$top eq $handle}]]
    return [expr {$folded && $top eq $handle}]
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
proc ::w1::unreserved {} {
    set saved [array get ::application::board::Dim]
    set side $::application::board::ReserveSide
    set pixels $::application::board::ReservePixels
    set c $::application::board::Vars(widget:frame)
    set ::application::board::ReserveSide {}
    set ::application::board::ReservePixels 0
    ::application::board::ComputeLayout [winfo width $c] [winfo height $c]
    set square $::application::board::Dim(squaresize:Normal)
    array unset ::application::board::Dim
    array set ::application::board::Dim $saved
    set ::application::board::ReserveSide $side
    set ::application::board::ReservePixels $pixels
    return $square
}
# What the same production layout would draw with a strip, forcing past the
# square-floor refusal so the test can tell "no strip fits" apart from "the
# strip fits and costs the board nothing".
proc ::w1::squareWithReserve {side pixels} {
    set saved [array get ::application::board::Dim]
    set oldSide $::application::board::ReserveSide
    set oldPixels $::application::board::ReservePixels
    set oldKind $::application::board::ReserveKind
    set oldFloor $::application::board::MinimumReserveSquare
    set c $::application::board::Vars(widget:frame)
    set ::application::board::MinimumReserveSquare -100000
    set ::application::board::ReserveSide $side
    set ::application::board::ReservePixels $pixels
    # Probe below the floor without changing the live reserve.
    set ::application::board::ReserveKind dialog
    ::application::board::ComputeLayout [winfo width $c] [winfo height $c]
    set square $::application::board::Dim(squaresize:Normal)
    array unset ::application::board::Dim
    array set ::application::board::Dim $saved
    set ::application::board::MinimumReserveSquare $oldFloor
    set ::application::board::ReserveSide $oldSide
    set ::application::board::ReservePixels $oldPixels
    set ::application::board::ReserveKind $oldKind
    return $square
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
    wm geometry .application [expr {min(1250,$sw-30)}]x[expr {min(570,$sh-150)}]+0+0
    ::w1::wait 600
    set c $::application::board::Vars(widget:frame)
    set baseline [list [$c bbox board] $::application::board::Dim(squaresize:Normal)]
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
    set restored [::w1::measure VAL-BRD-007-first-restored]
    set ch [expr {[winfo reqheight $w.controls]+8}]
    set best [expr {max([::w1::squareWithReserve right 168],
        [::w1::squareWithReserve bottom [expr {int(round(160/$::mediainset::Aspect))+$ch}]])}]
    if {$best >= min([::w1::unreserved], 32)} {
        ::w1::reserved VAL-BRD-007-first-restored
    } else {
        ::w1::assert {[dict get $restored side] eq ""} "below-floor reserve after 3D"
    }
    $w.controls.stop invoke
    ::w1::wait
    ::w1::clear VAL-BRD-007-first-stopped
    ::w1::assert {$baseline eq [list [$c bbox board] $::application::board::Dim(squaresize:Normal)]} "3D return Stop did not restore exact board"
    return ok
} -cleanup {::w1::cleanup} -result ok

tcltest::test brd-wide {BRD-001 reserves a right strip including all decorations} -setup {::w1::setup wide} -body {
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

# VAL-BRD-011 supersedes VAL-BRD-004's corner overlay for a playing video:
# when every candidate strip falls below the floor the video folds to its
# handle, leaving the unreserved board and its indicators uncovered.
# VAL-BRD-017: proved by the whole fold state and the real playback clock,
# never by overlap alone (a hidden video also scores zero overlap).
tcltest::test brd-minimum {BRD-011/VAL-BRD-017 refusal of every strip folds the video to its handle} -setup {::w1::setup small real} -body {
    set before $::application::board::Dim(squaresize:Normal)
    set w [::w1::playReal]
    set d [::w1::measure VAL-BRD-011-fold 1]
    set handle [::w1::foldState VAL-BRD-011-fold]
    ::w1::assert {$before == $::application::board::Dim(squaresize:Normal)} "fold resized squares"
    foreach tag {board stm material} {
        ::w1::assert {[dict get $d overlap:$tag] == 0} "folded video covers $tag"
    }
    # The same production arithmetic: every candidate strip is below the floor.
    set ch [expr {[winfo reqheight $w.controls]+8}]
    set minHeight [expr {int(round(160/$::mediainset::Aspect))+$ch}]
    set rightSquare [::w1::squareWithReserve right 168]
    set bottomSquare [::w1::squareWithReserve bottom $minHeight]
    ::w1::log VAL-BRD-011-fold [list before $before after $::application::board::Dim(squaresize:Normal) \
        minimum $::application::board::MinimumReserveSquare \
        rightSquare $rightSquare bottomSquare $bottomSquare handle $handle]
    ::w1::assert {$rightSquare < min($before,32) && $bottomSquare < min($before,32)} \
        "fold taken although a strip keeps squares at least 32 px"
    # VAL-BRD-015/VAL-BRD-017: the Stop row the Media menu now carries is the
    # one used to leave the folded state, and it restores the board.
    ::w1::stopViaMenu VAL-BRD-011
    ::w1::assert {![winfo ismapped $w]} "stopped folded inset still mapped"
    ::w1::assert {$before == $::application::board::Dim(squaresize:Normal)} "Stop changed the board square"
    return ok
} -cleanup {::w1::cleanup} -result ok

# VAL-BRD-014: in 3D the visible board is ::mediainset::BoardView (the 3D
# frame); the 2D canvas is unmapped. The fold handle must clear the visible
# board there too, and the fold must survive the 2D return unchanged.
tcltest::test brd-fold-3d-clear {BRD-014 the fold handle clears the visible 3D board} -constraints embedded3D -setup {::w1::setup; ::w1::size small} -body {
    set w [::w1::play]
    ::w1::assert {$::mediainset::Collapsed} "not folded in the small pane"
    ::w1::assert {[::application::board::show3D 1]} "Blocked: 3D view unavailable"
    ::w1::wait
    set view [::mediainset::BoardView]
    set handle .application.videoHandle
    ::w1::assert {[winfo ismapped $view] && ![winfo ismapped $::application::board::Vars(widget:frame)]} \
        "wrong visible presentation in 3D"
    ::w1::assert {[winfo exists $handle] && [winfo ismapped $handle]} "fold handle missing in 3D"
    set vr [::w1::rect $view]
    set hr [::w1::rect $handle]
    ::w1::log VAL-BRD-014-3d [list view $view viewRect $vr handle $hr \
        overlap [::w1::overlap $vr $hr] collapsed $::mediainset::Collapsed \
        reserve [::application::board::reserveRect] side $::application::board::ReserveSide \
        pixels $::application::board::ReservePixels]
    ::w1::assert {[::w1::overlap $vr $hr] == 0} "fold handle covers the visible 3D board"
    ::application::board::show3D 0
    ::w1::wait 1200
    ::w1::assert {$::mediainset::Collapsed} "fold lost on the 2D return"
    ::w1::assert {$::application::board::ReserveSide eq "" && $::application::board::ReservePixels == 0} \
        "reserve left behind by the 3D excursion"
    set br [::w1::rect [::mediainset::BoardView]]
    set hr2 [::w1::rect $handle]
    ::w1::log VAL-BRD-014-2d [list handle $hr2 board $br \
        overlap [::w1::overlap $br $hr2] collapsed $::mediainset::Collapsed \
        pane [::w1::rect [::mediainset::Pane]]]
    ::w1::assert {[::w1::overlap $br $hr2] == 0} "handle covers the 2D board after the 3D return"
    return ok
} -cleanup {::w1::cleanup} -result ok

# VAL-MED-013 / VAL-BRD-017: one resize case. Feasible strips keep their
# unchanged arithmetic assertions and must NOT fold; a formerly-infeasible
# size must now show the whole fold state (not merely side eq "").
proc ::w1::sweepCase {tag geom w {requireFloor 0} {logTarget VAL-MED-013}} {
    wm geometry .application ${geom}+0+0
    wait 450
    set unreserved [unreserved]
    set d [measure ${logTarget}-$tag]
    set square [dict get $d square]
    set side [dict get $d side]
    set canvas [dict get $d canvas]
    set ch [expr {[winfo reqheight $w.controls]+8}]
    set minHeight [expr {int(round(160/$::mediainset::Aspect))+$ch}]
    set rightSquare [squareWithReserve right 168]
    set bottomSquare [squareWithReserve bottom $minHeight]
    set best [expr {max($rightSquare,$bottomSquare)}]
    set feasible [expr {$best >= min($unreserved,32)}]
    assert {[dict get $d mapped]} "inset unmapped at $geom"
    log $logTarget [list geometry $geom square $square unreserved $unreserved \
        side $side reserve [dict get $d reserve] overlap [dict get $d overlap:board] \
        canvas $canvas rightSquare $rightSquare bottomSquare $bottomSquare feasible $feasible]
    if {$feasible} {
        assert {$square == $best} "did not choose largest square at $geom"
        assert {$side ne ""} "feasible strip ignored at $geom"
        if {$requireFloor} { assert {$best >= 32} "feasible largest strip is below 32 px at $geom" }
        assert {![folded?]} "video folded although a strip is feasible at $geom"
        set handle .application.videoHandle
        assert {![winfo exists $handle] || ![winfo ismapped $handle]} \
            "handle shown although a strip is feasible at $geom"
        foreach name {board stm material} {
            assert {[dict get $d overlap:$name] == 0} "reserved inset covers $name at $geom"
        }
    } else {
        assert {$side eq ""} "below-floor strip accepted at $geom"
        foldState $logTarget-$tag
    }
    return $feasible
}

# VAL-MED-013: sweep consecutive window heights across the reflow band.
tcltest::test brd-height-sweep {VAL-MED-013/VAL-BRD-017 reserves the side leaving the largest square, folds below the floor} -setup {::w1::setup default real} -body {
    set w [::w1::playReal]
    set reserved 0
    set overlays 0
    foreach h {520 530 540 550 560 570 580 590 600 610 620 630 640} {
        if {[::w1::sweepCase $h 1250x${h} $w]} {incr reserved} else {incr overlays}
    }
    # VAL-BRD-017: the formerly-infeasible branch. A narrow window cannot
    # carry the minimum strip at any of these heights, so every case proves
    # the full fold state instead of the old accepted corner overlay.
    foreach geom {700x520 700x600 700x640} {
        if {[::w1::sweepCase $geom $geom $w]} {incr reserved} else {incr overlays}
    }
    ::w1::log VAL-MED-013-summary [list reserved $reserved overlays $overlays]
    ::w1::assert {$reserved > 0} "no strip was reserved across the height sweep"
    ::w1::assert {$overlays > 0} "the formerly-infeasible branch was never exercised"
    return ok
} -cleanup {::w1::cleanup} -result ok

# Former no-shrink counterexamples must now reserve, including terminal GAP-001.
tcltest::test brd-width-counterexamples {VAL-MED-013/VAL-BRD-017 width-limited boards shrink to fit video} -setup {::w1::setup default real} -body {
    set w [::w1::playReal]
    set folds 0
    foreach geom {1000x640 1000x700 1100x700 1100x850 700x520 700x640} {
        if {![::w1::sweepCase $geom $geom $w 1 VAL-MED-013-width]} {incr folds}
    }
    ::w1::assert {$folds > 0} "the formerly-infeasible width branch was never exercised"
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

# VAL-BRD-020: audio-only media never folds. Where no strip fits it keeps its
# VAL-MED-009 bottom-right transport placement even though that covers a
# corner of the drawn board (user decision 5), and an open playing dialog must
# not fold it either. The accepted overlap is measured and logged rather than
# assumed to be zero.
tcltest::test brd-020-audio {BRD-020 audio keeps its placement and never folds} -setup {::w1::setup wide real} -body {
    # 400x380 window with wm minsize 1 1 (::w1::setup) and the board pane
    # forced to 300x300 is the tiny geometry where no video strip is feasible.
    wm geometry .application 400x380+0+0
    ::w1::wait 500
    place [::mediainset::Pane] -in $::w1::twm -x 0 -y 0 -width 300 -height 300 \
        -relwidth {} -relheight {}
    ::w1::wait 500
    ::application::media::Stop
    ::w1::wait 300
    set pane [::mediainset::Pane]
    set canvas [::mediainset::BoardView]
    set before [list [$canvas bbox board] $::application::board::Dim(squaresize:Normal) [::w1::rect $pane]]
    set w [::w1::playReal [file normalize $::w1::root/tests/tmp-app/media-test/MediaTest.media/audio/interview.wav]]
    set handle .application.videoHandle
    set audio [::w1::measure VAL-BRD-020-audio-tiny 1]
    ::w1::assert {$::mediainset::Audio && [winfo manager $w.video] eq ""} "audio has a video surface"
    ::w1::assert {![::w1::handleMapped?]} "handle shown for audio-only media"
    ::w1::assert {!$::mediainset::Collapsed} "audio-only media folded"
    ::w1::assert {[winfo ismapped $w]} "audio inset hidden"
    ::w1::assert {$::application::board::ReserveSide eq "" && $::application::board::ReservePixels == 0} \
        "audio requested a strip reserve where none fits"
    ::w1::assert {[dict get $audio mapped]} "audio inset unmapped at the tiny geometry"
    # VAL-BRD-017: the same expectation, asserted as a state and measured.
    ::w1::audioPlacement audio-tiny $w
    ::w1::progressAdvance VAL-BRD-020-audio
    # The measured overlap is the accepted decision-5 outcome: record it.
    ::w1::log VAL-BRD-020-measured [list inset [::w1::rect $w] board [dict get $audio bbox:board] \
        overlap [dict get $audio overlap:board] reserve [dict get $audio reserve] \
        side [dict get $audio side] squaresize [dict get $audio square]]

    # A dialog beside the board must not fold audio to its handle.
    toplevel .application.dlgAudioProbe
    wm withdraw .application.dlgAudioProbe
    wm transient .application.dlgAudioProbe .application
    ttk::frame .application.dlgAudioProbe.content -width 240 -height 160
    pack .application.dlgAudioProbe.content -fill both -expand yes
    ttk::button .application.dlgAudioProbe.ok -text "Keep playing"
    pack .application.dlgAudioProbe.ok -side left -padx 6 -pady 6
    ::util::place::besideBoard .application.dlgAudioProbe .application
    wm deiconify .application.dlgAudioProbe
    ::w1::wait 700
    set withDialog [::w1::measure VAL-BRD-020-audio-dialog 1]
    ::w1::assert {![::w1::handleMapped?]} "handle shown for audio with a dialog open"
    ::w1::assert {!$::mediainset::Collapsed} "audio folded with a dialog open"
    ::w1::assert {[winfo ismapped $w]} "audio inset hidden with a dialog open"
    ::w1::log VAL-BRD-020-dialog [list inset [::w1::rect $w] board [dict get $withDialog bbox:board] \
        overlap [dict get $withDialog overlap:board]]

    destroy .application.dlgAudioProbe
    ::w1::wait 500
    # VAL-BRD-015: leave through the Media-menu Stop row while audio plays.
    ::w1::stopViaMenu VAL-BRD-020
    ::w1::wait 500
    set after [list [$canvas bbox board] $::application::board::Dim(squaresize:Normal) [::w1::rect $pane]]
    ::w1::assert {$after eq $before} "board or pane left resized after stopping audio"
    ::w1::assert {![winfo ismapped $w]} "audio inset still mapped after stop"
    ::w1::assert {![::w1::handleMapped?]} "handle left mapped after stop"
    return ok
} -cleanup {
    catch {destroy .application.dlgAudioProbe}
    ::w1::cleanup
} -result ok

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

tcltest::test brd-3d {BRD-007 and BRD-003D visible 3D geometry and toggle restoration} -constraints embedded3D -setup {::w1::setup wide} -body {
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
    # Sizes larger than the live screen are clamped to it, so a small
    # (1000x600) display still exercises the control (VAL-DLG-015d).
    set seen {}
    foreach {sw sh} [list 1024 700 1280 800] {
        set sw [expr {min($sw, [winfo screenwidth .])}]
        set sh [expr {min($sh, [winfo screenheight .])}]
        if {"$sw $sh" in $seen} { continue }
        lappend seen "$sw $sh"
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
# audio-only and 3D board states. VAL-BRD-017: the video branch is proved by
# the whole fold state and the real playback clock; the audio-only branch by
# the opposite expectation (no fold, no handle) with the measured placement.
tcltest::test inset-009-unoccluded-states {VAL-MED-009/VAL-BRD-017 control unoccluded in corner, audio and 3D states} -constraints embedded3D -setup {::w1::setup small real} -body {
    ::w1::quiet
    set states {}
    set w [::w1::playReal]
    # VAL-BRD-011 replaces the corner overlay with the fold handle; VAL-BRD-017
    # wants the full folded state, not only a topmost control.
    ::w1::foldState VAL-BRD-011-unoccluded
    lappend states [::w1::foldUnoccluded corner]
    ::w1::trigger $w button
    lappend states [::w1::unoccluded corner-expanded $w]
    ::w1::trigger $w button
    set w [::w1::playReal [file normalize $::w1::root/tests/tmp-app/media-test/MediaTest.media/audio/interview.wav]]
    ::w1::audioPlacement audio-strip $w
    lappend states [::w1::unoccluded audio $w]
    ::w1::trigger $w button
    lappend states [::w1::unoccluded audio-expanded $w]
    ::w1::trigger $w button
    # VAL-BRD-020: the decision-5 geometry where no audio strip fits. Audio
    # must still not fold or show a handle; the bottom-right transport cluster
    # stays put and its accepted board overlap is measured and recorded.
    ::application::media::Stop
    ::w1::wait 300
    place [::mediainset::Pane] -in $::w1::twm -x 0 -y 0 -width 300 -height 300 \
        -relwidth {} -relheight {}
    ::w1::wait 500
    set w [::w1::playReal [file normalize $::w1::root/tests/tmp-app/media-test/MediaTest.media/audio/interview.wav]]
    ::w1::audioPlacement audio-tiny $w
    lappend states [::w1::unoccluded audio-tiny $w]
    # Restore the forced pane before the 3D state.
    place [::mediainset::Pane] -in $::w1::twm -x 0 -y 0 -relwidth 1 -relheight 1 -width 0 -height 0
    ::w1::wait 450
    wm geometry .application 1024x700+0+0
    ::w1::wait
    set w [::w1::playReal]
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

# VAL-BRD-011: a board pane too small for a strip folds the playing video to
# its handle. VAL-BRD-017: the whole fold state is asserted (handle rectangle,
# playback clock, cleared reserve, unreserved square), not the handle alone.
# The inset keeps its visible ridge frame for the restored strip.
tcltest::test inset-009-frame-corner {VAL-BRD-011/VAL-BRD-017 a too-small pane folds to a board-clear handle} -setup {::w1::setup small real} -body {
    set w [::w1::playReal]
    set handle [::w1::foldState VAL-BRD-011-corner]
    set style [::w1::frameStyle $w]
    set clear 1
    foreach r [::w1::drawnBoardRects] {
        if {[::w1::overlap $handle $r] != 0} { set clear 0 }
    }
    ::w1::log VAL-BRD-011-corner [list rect [::w1::rect $w] handle $handle \
        pane [::w1::rect [winfo parent $w]] style $style mapped [::w1::handleMapped?] \
        clear $clear reserve [::application::board::reserveRect]]
    list [::w1::handleMapped?] $clear $style
} -cleanup {::w1::cleanup} -result {1 1 {ridge 3 1}}

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
