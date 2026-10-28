# Real dialog placement: run with -match 'dlg-*' on each required Xvfb screen.
package require tcltest 2.5
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready
namespace eval ::scidb::test::dlgplace {
    variable testDir [file dirname [file normalize [info script]]]
    variable calls
    variable workareaCalls 0
    variable placing 0
    variable waitSerial 0
    variable unowned {}
}
proc ::scidb::test::dlgplace::waitFor {ms} {
    variable waitSerial
    set flag [namespace current]::settled[incr waitSerial]
    after $ms [list set $flag 1]
    vwait $flag
    unset $flag
    update idletasks
}
proc ::scidb::test::dlgplace::widgetRect {w} {
    list [winfo rootx $w] [winfo rooty $w] [winfo width $w] [winfo height $w]
}
proc ::scidb::test::dlgplace::boardRect {} {
    # Independent oracle: the full drawn board. Include the border and
    # coordinates, plus any side bars drawn with the board (side-to-move,
    # material and holding bar), not just the inner board widget.
    set canvas $::application::board::Vars(widget:frame)
    set boxes {}
    foreach tag {board stm material holdingbar} {
        set box [$canvas bbox $tag]
        if {[llength $box] == 4} {lappend boxes $box}
    }
    if {![llength $boxes]} {return {}}
    lassign [lindex $boxes 0] x0 y0 x1 y1
    foreach box [lrange $boxes 1 end] {
        lassign $box a b c d
        set x0 [expr {min($x0,$a)}]; set y0 [expr {min($y0,$b)}]
        set x1 [expr {max($x1,$c)}]; set y1 [expr {max($y1,$d)}]
    }
    return [list [expr {[winfo rootx $canvas] + $x0 - int([$canvas canvasx 0])}] \
        [expr {[winfo rooty $canvas] + $y0 - int([$canvas canvasy 0])}] \
        [expr {$x1-$x0}] [expr {$y1-$y0}]]
}
# The main window's own work area, not the whole X display: the decorated
# application frame, clipped to the WM work area. A dialog outside the
# configured 1280x720 window is clipped on that display even when the Xvfb
# root is 1920x1080 (VAL-DLG-014f).
proc ::scidb::test::dlgplace::windowWorkArea {} {
    set wa [winfo workarea .application]
    # Native frames account for Openbox's X border/title-bar differences;
    # Tk's extents alone can shift the inferred top edge by several pixels.
    set outer [outerRect .application]
    lassign $wa wx wy ww wh
    lassign $outer ox oy ow oh
    set x0 [expr {max($wx,$ox)}]; set y0 [expr {max($wy,$oy)}]
    set x1 [expr {min($wx+$ww,$ox+$ow)}]; set y1 [expr {min($wy+$wh,$oy+$oh)}]
    return [list $x0 $y0 [expr {max(0,$x1-$x0)}] [expr {max(0,$y1-$y0)}]]
}
# A main-window geometry that fits the live work area: the request clamped to
# the WM work area minus the window's decorations, so a test asks for a size
# the WM will really grant (VAL-DLG-015d). A fraction below 1 scales the
# usable work area instead.
proc ::scidb::test::dlgplace::fitSize {w h} {
    lassign [winfo workarea .application] wx wy ww wh
    lassign [winfo extents .application] el er et eb
    if {$el+$er+$et+$eb == 0} { set el 4; set er 4; set et 24; set eb 4 }
    if {$w <= 1.0} { set w [expr {int(($ww-$el-$er)*$w)}] }
    if {$h <= 1.0} { set h [expr {int(($wh-$et-$eb)*$h)}] }
    return "[expr {min($w, $ww-$el-$er)}]x[expr {min($h, $wh-$et-$eb)}]"
}
proc ::scidb::test::dlgplace::fitGeometry {w h} {
    lassign [winfo workarea .application] wx wy
    return "[fitSize $w $h]+$wx+$wy"
}
# Move within the current work area, leaving the current client size intact.
proc ::scidb::test::dlgplace::movedGeometry {} {
    lassign [winfo workarea .application] x y w h
    lassign [winfo extents .application] l r t b
    set dx [expr {max(0,($w-[winfo width .application]-$l-$r)/2)}]
    set dy [expr {max(0,($h-[winfo height .application]-$t-$b)/2)}]
    return "+[expr {$x+$dx}]+[expr {$y+$dy}]"
}
proc ::scidb::test::dlgplace::overlapArea {a b} {
    lassign $a ax ay aw ah
    lassign $b bx by bw bh
    expr {max(0,min($ax+$aw,$bx+$bw)-max($ax,$bx))*max(0,min($ay+$ah,$by+$bh)-max($ay,$by))}
}
proc ::scidb::test::dlgplace::inside {a b} {
    lassign $a x y w h
    lassign $b bx by bw bh
    expr {$x >= $bx && $y >= $by && $x+$w <= $bx+$bw && $y+$h <= $by+$bh}
}
proc ::scidb::test::dlgplace::require {value message} {
    if {!$value} {error $message}
}
# Observe production calls and their return values, without replacing geometry.
proc ::scidb::test::dlgplace::placing {command op} {
    variable placing 1
    variable workareaCalls 0
}
proc ::scidb::test::dlgplace::placed {command code result op} {
    variable calls
    variable placing 0
    variable workareaCalls
    if {$code} {return}
    set dlg [lindex $command 1]
    # VAL-DLG-017B: every call registers a live reserve owner at once.
    variable unowned
    set owners {}
    foreach e $::util::place::BesideReserves {lappend owners [lindex $e 0]}
    if {$dlg ni $owners} {lappend unowned [list $dlg $result]}
    dict set calls $dlg [dict create plan $result workareaCalls $workareaCalls board [boardRect] \
        workarea [winfo workarea $dlg] extents [winfo extents $dlg]]
}
proc ::scidb::test::dlgplace::workareaTrace {command op} {
    variable workareaCalls
    variable placing
    # A transaction can reuse its native WM query. Observe consumption of
    # the work-area snapshot; check() independently verifies live geometry.
    if {$placing} {incr workareaCalls}
}
proc ::scidb::test::dlgplace::setupBoard {} {
    variable calls
    variable workareaCalls
    # Tcl permits duplicate execution traces. Remove this suite's previous
    # observers before installing them, including after an interrupted test.
    stopTrace
    ::application::switchTab board
    wm state .application normal
    wm geometry .application [::scidb::test::dlgplace::fitGeometry 1.0 1.0]
    waitFor 1200
    ::scidb::game::clear {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}
    foreach san {e4 e5 Nf3 Nc6} {::move::addMove menu $san}
    ::scidb::game::go -1 start
    waitFor 300
    set calls {}
    set workareaCalls 0
    trace add execution ::util::place::besideBoard enter ::scidb::test::dlgplace::placing
    trace add execution ::util::place::besideBoard leave ::scidb::test::dlgplace::placed
    trace add execution ::util::place::besideWorkArea enter ::scidb::test::dlgplace::workareaTrace
}
proc ::scidb::test::dlgplace::stopTrace {} {
    foreach {command op callback} {
        ::util::place::besideBoard enter ::scidb::test::dlgplace::placing
        ::util::place::besideBoard leave ::scidb::test::dlgplace::placed
        ::util::place::besideWorkArea enter ::scidb::test::dlgplace::workareaTrace
    } {
        # Remove only our own observers; leave any independent probe intact.
        while {[list $op $callback] in [trace info execution $command]} {
            trace remove execution $command $op $callback
        }
    }
}

proc ::scidb::test::dlgplace::buttons {w} {
    set result {}
    foreach child [winfo children $w] {
        if {[winfo toplevel $child] ne [winfo toplevel $w]} {continue}
        if {[winfo class $child] in {Button TButton Checkbutton TCheckbutton Radiobutton TRadiobutton}
            && [winfo ismapped $child]} {lappend result $child}
        lappend result {*}[buttons $child]
    }
    return $result
}
proc ::scidb::test::dlgplace::controls {w} {
    set result {}
    foreach child [winfo children $w] {
        if {[winfo toplevel $child] ne [winfo toplevel $w]} {continue}
        # The viewport's canvas and outer bars are navigation chrome, not
        # content controls. Still recurse through the canvas to its body.
        set shell [winfo toplevel $child].__viewport
        if {$child ni [list $shell.canvas $shell.x $shell.y]
            && [winfo ismapped $child]
            && ([winfo class $child] in {Button TButton Checkbutton TCheckbutton Radiobutton TRadiobutton Entry TEntry TCombobox Spinbox TSpinbox Scale TScale Listbox TListbox Scrollbar TScrollbar Text Treeview TTreeview Menubutton TMenubutton Canvas TNotebook Panedwindow TPanedwindow}
                || [tk::FocusOK $child])} {
            lappend result $child
        }
        lappend result {*}[controls $child]
    }
    return $result
}
# Oversized controls expose their leading edge on focus; both ends must be
# reachable by explicit scrolling, including after Configure settles.
proc ::scidb::test::dlgplace::requireReachable {w c} {
    focus -force $w
    update
    require [expr {[focus] eq $w}] "focus failed $w"
    foreach axis {x y} size {width height} {
        set start [expr {[winfo root$axis $w]-[winfo root$axis $c]}]
        set length [winfo $size $w]
        set visible [winfo $size $c]
        require [expr {$start >= 0 && $start+min($length,$visible) <= $visible+1}] \
            "focused control clipped $w axis=$axis start=$start length=$length viewport=$visible"
        if {$length > $visible} {
            foreach end {1 0} {
                $c ${axis}view moveto $end
                waitFor 60
                set start [expr {[winfo root$axis $w]-[winfo root$axis $c]}]
                require [expr {$end ? $start+$length <= $visible : $start >= 0}] \
                    "explicit scroll cannot expose $w axis=$axis end=$end"
            }
        }
    }
}
# The contract requires every control at least its requested width and height.
proc ::scidb::test::dlgplace::requireControls {target dlg} {
    set found 0
    foreach c [controls $dlg] {
        incr found
        require [expr {[winfo width $c] >= [winfo reqwidth $c]
            && [winfo height $c] >= [winfo reqheight $c]}] \
            "$target: control $c [winfo width $c]x[winfo height $c] is below requested [winfo reqwidth $c]x[winfo reqheight $c]"
    }
    require [expr {$found > 0}] "$target: no controls found in $dlg"
}
proc ::scidb::test::dlgplace::outerRect {dlg} {
 if {![catch {::scidb::tk::wm frame $dlg} native] && [llength $native] == 4} {
  return $native
 }
 lassign [widgetRect $dlg] x y w h
 lassign [winfo extents $dlg] l r t b
 list [expr {$x-$l}] [expr {$y-$t}] [expr {$w+$l+$r}] [expr {$h+$t+$b}]
}
proc ::scidb::test::dlgplace::check {target dlg {wantRule ""}} {
    variable calls
    variable workareaCalls
    waitFor 500
    require [dict exists $calls $dlg] "$target: shared helper did not place $dlg"
    set call [dict get $calls $dlg]
    set plan [dict get $call plan]
    set board [dict get $call board]
    set wa [dict get $call workarea]
    set ext [dict get $call extents]
    set rule [dict get $plan rule]
    require [expr {[dict get $call workareaCalls] > 0}] "$target: no work-area snapshot consumed by helper"
    require [expr {$wa eq [winfo workarea $dlg]}] "$target: work area changed"
    require [expr {$ext eq [winfo extents $dlg]}] "$target: frame changed after planning"
    require [expr {$board eq [boardRect]}] "$target: board changed after planning"
    if {$wantRule ne ""} {require [expr {$rule eq $wantRule}] "$target: expected $wantRule, got $rule"}
    require [regexp {^([0-9]+)x([0-9]+)\+(-?[0-9]+)\+(-?[0-9]+)$} [wm geometry $dlg] -> w h x y] "invalid geometry"
    set actual [list $x $y [winfo width $dlg] [winfo height $dlg]]
    foreach a $actual p [dict get $plan geometry] {
        require [expr {abs($a-$p) <= 1}] "$target: final $actual != helper [dict get $plan geometry]"
    }
    require [expr {$w == [winfo width $dlg] && $h == [winfo height $dlg]}] "$target: unsettled client size"
    set requested [list [winfo reqwidth $dlg] [winfo reqheight $dlg]]
    # A below-minimum strip (shrink/no-room) must stay usable; a reserved or
    # fitting placement keeps the requested size.
    if {$rule eq "scroll"} {
        require [expr {$w >= min(240,[lindex $requested 0]) && $h >= min(180,[lindex $requested 1])}] "$target: below scrolling minimum"
    } elseif {$rule in {shrink no-room}} {
        require [expr {$w >= 1 && $h >= 1}] "$target: degenerate ${w}x${h}"
    } else {
        require [expr {$w >= [lindex $requested 0] && $h >= [lindex $requested 1]}] \
            "$target: final ${w}x${h} clips requested $requested"
    }
    lassign $ext el er et eb
    set outer [outerRect $dlg]
    require [inside $outer $wa] "$target: outer frame $outer outside $wa"
    set area [overlapArea $outer $board]
    # Independent candidate oracle, evaluated at FINAL dimensions, including frame.
    lassign $board bx by bw bh
    lassign $wa wx wy ww wh
    lassign $outer _ _ fw fh
    set areas {}
    foreach {side cx cy} [list right [expr {$bx+$bw+12}] $by left [expr {$bx-12-$fw}] $by below $bx [expr {$by+$bh+12}]] {
        set cx [expr {max($wx,min($cx,$wx+$ww-$fw))}]
        set cy [expr {max($wy,min($cy,$wy+$wh-$fh))}]
        dict set areas $side [overlapArea [list $cx $cy $fw $fh] $board]
    }
    if {$rule ni {shrink scroll}} {
        require [expr {$area == [tcl::mathfunc::min {*}[dict values $areas]]}] "$target: overlap $area is not minimum of $areas"
    }
    if {$rule ne "shrink"} {require [expr {$area == 0}] "$target: $rule overlaps $area"}
    if {$rule eq "no-room"} {
        # No strip holds the minimum: this is the largest overlap-free forced
        # strip, never an overlap allowance.
        require [expr {$area == 0}] "$target: no-room plan overlaps $area"
    }
    set buttonRects {}
    foreach button [buttons $dlg] {
        if {[winfo exists $dlg.__viewport]} {focus -force $button; update}
        set r [widgetRect $button]
        require [inside $r $wa] "$target: offscreen button $button $r"
        require [inside $r [widgetRect $dlg]] "$target: clipped button $button $r"
        for {set ancestor [winfo parent $button]} {$ancestor ne $dlg} {set ancestor [winfo parent $ancestor]} {
            require [inside $r [widgetRect $ancestor]] "$target: button clipped by $ancestor"
        }
        require [expr {[winfo width $button] >= [winfo reqwidth $button] && [winfo height $button] >= [winfo reqheight $button]}] "$target: clipped label $button"
        lappend buttonRects [list $button $r [$button cget -text]]
    }
    require [expr {[llength $buttonRects] > 0}] "$target: no buttons tested"
    requireControls $target $dlg
    puts "DLG $target screen=[winfo screenwidth .]x[winfo screenheight .] main=[wm geometry .application] board=$board workarea=$wa extents=$ext rule=$rule resized=[dict get $plan resized] helper=[dict get $plan geometry] final=$actual requested=$requested minsize=[wm minsize $dlg] overlap=$area candidates=$areas buttons=$buttonRects"
    if {[info exists ::env(DLG_EVIDENCE_DIR)]} {
        file mkdir $::env(DLG_EVIDENCE_DIR)
        ::util::execSafe import -window root [file join $::env(DLG_EVIDENCE_DIR) $target.png]
    }
    return 1
}
proc ::scidb::test::dlgplace::openInsightsFixture {} {
	variable testDir
	set dir [file join $testDir tmp-app dlgplace_ins_[pid]]
	file mkdir $dir
	set pgn [file join $dir fixture.pgn]
	set ch [open $pgn w]
	puts $ch {[Event "Test"]}
	puts $ch {[Site "?"]}
	puts $ch {[Date "2024.01.01"]}
	puts $ch {[Round "1"]}
	puts $ch {[White "Me"]}
	puts $ch {[Black "Opp"]}
	puts $ch {[Result "1-0"]}
	puts $ch {[ECO "C60"]}
	puts $ch ""
	puts $ch "1. e4 e5 2. Nf3 Nc6 3. Bb5 1-0"
	close $ch
	proc nop {args} { return 0 }
	catch { ::scidb::db::close $pgn }
	::scidb::db::open $pgn ::scidb::test::dlgplace::nop {} ::scidb::test::dlgplace::nop {}
	set n [::scidb::db::count players $pgn Normal]
	set meIdx -1
	for {set i 0} {$i < $n} {incr i} {
		set k [::scidb::db::get playerKey $pgn Normal $i]
		if {[lindex $k 0] eq "Me"} { set meIdx $i; break }
	}
	return [list $pgn $meIdx]
}

tcltest::test dlg-frame-bounds {placement rectangle includes the drawn frame and coordinates} -setup {
    ::scidb::test::dlgplace::setupBoard
} -body {
    expr {[::util::place::besideBoardRect] eq [::scidb::test::dlgplace::boardRect]}
} -cleanup {
    ::scidb::test::dlgplace::stopTrace
} -result 1

foreach {target openScript dialog closeScript} {
    002A {::playengine::open .application} {.application.playengine} {::playengine::Close}
    002B {::guessmove::start white} {.application.__guessmove__} {::guessmove::stop; catch {destroy .application.__guessmove__}}
    002C {::reptrainer::open .application} {.application.__reptrainer__} {::reptrainer::Close .application.__reptrainer__}
    003B {set review [::gamereview::classify {{san e4 before 0 after 0 best 1} {san e5 before 0 after -250 best 0}}]; ::gamereview::ShowWindow .application $review {} 0} {.application.__gamereview} {destroy .application.__gamereview}
    003C {lassign [::scidb::test::dlgplace::openInsightsFixture] insBase insIdx; set insDlg [::insights::show .application $insBase Normal $insIdx]} {$insDlg} {destroy $insDlg; ::scidb::db::close $insBase; file delete -force [file dirname $insBase]}
    003D {set savedPos $::annotation::Position; set ::annotation::Position {}; ::annotation::open .application} {.application.__annotation__} {::annotation::close; destroy .application.__annotation__; set ::annotation::Vars(dialog) {}; set ::annotation::Position $savedPos}
    endgame {::endtrainer::open .application} {.application.__endtrainer__} {::endtrainer::Close}
    engine-match {::enginematch::open .application} {.application.enginematch} {::enginematch::Close}
} {
    tcltest::test dlg-$target {final dialog geometry equals shared helper plan, with frame and buttons inside work area} -setup {
        ::scidb::test::dlgplace::setupBoard
    } -body [format {
        %s
        ::scidb::test::dlgplace::check %s %s
    } $openScript $target $dialog] -cleanup [format {
        %s
        ::scidb::test::dlgplace::stopTrace
    } $closeScript] -result 1
}
# Use the normal review entry and NextPly/Progress/Finish lifecycle. Only the
# engine is replaced, so measurement is independent of engine speed/availability.
proc ::scidb::test::dlgplace::reviewMove {args} {
    variable reviewCheck
    set reviewCheck [catch {
        set dlg .application.__gamereview_progress
        require [expr {[[::util::place::playingBody $dlg].top.status cget -text] ne ""}] "review did not populate its status"
        check 003A $dlg
        # A later, longer status must grow the same window and update its plan.
        set before [winfo reqwidth $dlg]
        ::gamereview::Progress "Reviewing move 100 of 120: O-O-O+"
        check 003A-growth $dlg
        require [expr {[winfo reqwidth $dlg] > $before}] "status did not exercise content growth"
    } ::scidb::test::dlgplace::reviewError]
    ::gamereview::cancel
    return {evalBeforeCp 0 evalAfterCp 0 uci e2e4 bestMove e2e4}
}
tcltest::test dlg-003A {normal review status and later growth fit, then results use the shared plan} -setup {
    ::scidb::test::dlgplace::setupBoard
    rename ::ai::engine::available ::scidb::test::dlgplace::realAvailable
    rename ::ai::engine::classify ::scidb::test::dlgplace::realClassify
    proc ::ai::engine::available {} {return 1}
    proc ::ai::engine::classify {args} {::scidb::test::dlgplace::reviewMove {*}$args}
    set ::scidb::test::dlgplace::reviewCheck -1
} -body {
    ::scidb::test::dlgplace::require [::gamereview::run .application -depth 6] "review did not start"
    for {set i 0} {$i < 50 && $::gamereview::Priv(running)} {incr i} {
        ::scidb::test::dlgplace::waitFor 100
    }
    ::scidb::test::dlgplace::require [expr {$::scidb::test::dlgplace::reviewCheck == 0}] \
        "review status check failed: $::scidb::test::dlgplace::reviewError"
    ::scidb::test::dlgplace::check 003B-run .application.__gamereview
} -cleanup {
    ::gamereview::cancel
    catch {destroy .application.__gamereview_progress}
    catch {destroy .application.__gamereview}
    rename ::ai::engine::available {}
    rename ::ai::engine::classify {}
    rename ::scidb::test::dlgplace::realAvailable ::ai::engine::available
    rename ::scidb::test::dlgplace::realClassify ::ai::engine::classify
    ::scidb::test::dlgplace::stopTrace
} -result 1
# The report body scrolls, so its own request is a sliver; the dialog must
# still request its declared usable minimum, and placement must keep it. This
# is what keeps a narrow strip beside the board from shrinking Insights below
# 780x480 (and remembering that capped size for later placements).
tcltest::test dlg-insights-usable-minimum {the Insights report requests and keeps its usable minimum} -setup {
    ::scidb::test::dlgplace::setupBoard
} -body {
    lassign [::scidb::test::dlgplace::openInsightsFixture] insBase insIdx
    set dlg [::insights::show .application $insBase Normal $insIdx]
    ::scidb::test::dlgplace::waitFor 500
    set result [list \
        [expr {[winfo reqwidth $dlg] >= 780 && [winfo reqheight $dlg] >= 480}] \
        [expr {[wm minsize $dlg] eq {780 480}}] \
        [expr {[winfo width $dlg] >= 780 && [winfo height $dlg] >= 480}] \
        [expr {[::util::place::besideMinSize $dlg] eq {780 480}}]]
    destroy $dlg
    ::scidb::db::close $insBase
    file delete -force [file dirname $insBase]
    set result
} -cleanup {
    catch {destroy $dlg}
    ::scidb::test::dlgplace::stopTrace
} -result {1 1 1 1}

# A real content-sized dialog too large for all three strips at each screen.
# No workarea, board, or geometry procedures are replaced.
tcltest::test dlg-004 {no-room fallback minimises measured board overlap and exposes every button label} -setup {
    ::scidb::test::dlgplace::setupBoard
} -body {
    toplevel .application.dlgNoRoom
    wm withdraw .application.dlgNoRoom
    wm transient .application.dlgNoRoom .application
    set b [::scidb::test::dlgplace::boardRect]
    lassign $b bx by bw bh
    lassign [winfo workarea .application] wx wy ww wh
    lassign [winfo extents .application.dlgNoRoom] el er et eb
    set cw [expr {max($bx-$wx,$wx+$ww-$bx-$bw)+20}]
    set ch [expr {$wy+$wh-$by-$bh+20}]
    ttk::frame .application.dlgNoRoom.content -width $cw -height $ch
    pack .application.dlgNoRoom.content -fill both -expand yes
    ttk::button .application.dlgNoRoom.ok -text "Keep playing"
    ttk::button .application.dlgNoRoom.cancel -text "Close dialog"
    pack .application.dlgNoRoom.ok .application.dlgNoRoom.cancel -side left -padx 6 -pady 6
    ::util::place::besideBoard .application.dlgNoRoom .application
    wm deiconify .application.dlgNoRoom
    ::scidb::test::dlgplace::check 004 .application.dlgNoRoom
    .application.dlgNoRoom.content configure -width [expr {$cw+30}] -height [expr {$ch+30}]
    ::scidb::test::dlgplace::check 004-growth .application.dlgNoRoom
} -cleanup {
    catch {destroy .application.dlgNoRoom}
    ::scidb::test::dlgplace::stopTrace
} -result 1

# VAL-DLG-011: when no free strip holds the dialog, besideBoard reserves board
# room (the video-inset mechanism); closing the dialog restores the board.
tcltest::test dlg-no-room-board-restore {reserved strip shrinks the board and restores it on close} -setup {
    ::scidb::test::dlgplace::setupBoard
} -body {
    toplevel .application.dlgRestore
    wm withdraw .application.dlgRestore
    wm transient .application.dlgRestore .application
    set b [::scidb::test::dlgplace::boardRect]
    lassign $b bx by bw bh
    lassign [winfo workarea .application] wx wy ww wh
    set cw [expr {max($bx-$wx,$wx+$ww-$bx-$bw)+20}]
    set ch [expr {$wy+$wh-$by-$bh+20}]
    ttk::frame .application.dlgRestore.content -width $cw -height $ch
    pack .application.dlgRestore.content -fill both -expand yes
    ttk::button .application.dlgRestore.ok -text "Keep playing"
    pack .application.dlgRestore.ok -side left -padx 6 -pady 6
    set before [::scidb::test::dlgplace::boardRect]
    ::util::place::besideBoard .application.dlgRestore .application
    wm deiconify .application.dlgRestore
    ::scidb::test::dlgplace::waitFor 700
    set used [expr {$::application::board::ReservePixels > 0}]
    puts "DLG no-room-board-restore used=$used side=$::application::board::ReserveSide pixels=$::application::board::ReservePixels before=$before during=[::scidb::test::dlgplace::boardRect]"
    if {$used} {
        ::scidb::test::dlgplace::require [expr {[::scidb::test::dlgplace::boardRect] ne $before}] \
            "reserved strip did not shrink the board"
    }
    ::scidb::test::dlgplace::require [expr {[::scidb::test::dlgplace::overlapArea \
        [::scidb::test::dlgplace::widgetRect .application.dlgRestore] \
        [::scidb::test::dlgplace::boardRect]] == 0}] \
        "dialog covers the board even after reserving"
    destroy .application.dlgRestore
    ::scidb::test::dlgplace::waitFor 900
    ::scidb::test::dlgplace::require [expr {[::scidb::test::dlgplace::boardRect] eq $before}] \
        "board not restored after the dialog closed"
    ::scidb::test::dlgplace::require [expr {$::application::board::ReservePixels == 0}] \
        "board reserve not cleared after the dialog closed"
    return 1
} -cleanup {
    catch {destroy .application.dlgRestore}
    ::scidb::test::dlgplace::stopTrace
} -result 1

tcltest::test dlg-tactics {Tactics registers beside the drawn board at the live app size} -setup {
    ::scidb::test::dlgplace::setupBoard
    wm geometry .application [::scidb::test::dlgplace::fitGeometry 1100 850]
    ::scidb::test::dlgplace::waitFor 700
} -body {
    ::tactics::open .application
    ::scidb::test::dlgplace::waitFor 700
    ::scidb::test::dlgplace::require [dict exists $::scidb::test::dlgplace::calls .tactics] "tactics bypassed shared helper"
    set owners {}
    foreach entry $::util::place::BesideReserves {lappend owners [lindex $entry 0]}
    ::scidb::test::dlgplace::require [expr {".tactics" in $owners}] "tactics not registered"
    set frame [::scidb::test::dlgplace::outerRect .tactics]
    set board [::scidb::test::dlgplace::boardRect]
    set overlap [::scidb::test::dlgplace::overlapArea $frame $board]
    puts "DLG020 app=[wm geometry .application] native=$frame board=$board overlap=$overlap"
    # Include labels and the canvas, and never filter out unmapped controls.
    # Exercise the longer prompt as well as the initial empty-session state.
    foreach message [list $::tactics::message "White to move. Click source and destination, then Play move; or enter SAN / UCI (append q/r/b/n to promote)."] {
        set ::tactics::message $message
        ::scidb::test::dlgplace::waitFor 700
        foreach name {open build board status move play retry show next score} {
            set w [::util::place::playingBody .tactics].$name
            puts "TACTICS control=$name mapped=[winfo ismapped $w] actual=[winfo width $w]x[winfo height $w] requested=[winfo reqwidth $w]x[winfo reqheight $w]"
            ::scidb::test::dlgplace::require [winfo ismapped $w] "$w is unmapped"
            ::scidb::test::dlgplace::require [expr {[winfo width $w] >= [winfo reqwidth $w] && [winfo height $w] >= [winfo reqheight $w]}] "$w is clipped"
            ::scidb::test::dlgplace::require [::scidb::test::dlgplace::inside [::scidb::test::dlgplace::widgetRect $w] [::scidb::test::dlgplace::widgetRect .tactics]] "$w lies outside trainer"
        }
        ::scidb::test::dlgplace::require [expr {[::scidb::test::dlgplace::overlapArea [::scidb::test::dlgplace::outerRect .tactics] [::scidb::test::dlgplace::boardRect]] == 0}] "trainer controls overlap board"
    }
    # Rendering and hit testing must use the same compact square size.
    set fen {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}
    ::tactics::start [::tactics::puzzle $fen {e4}]
    ::tactics::render
    set cell [expr {[[::util::place::playingBody .tactics].board cget -width]/8}]
    ::tactics::click [expr {4*$cell+$cell/2}] [expr {6*$cell+$cell/2}]
    ::tactics::click [expr {4*$cell+$cell/2}] [expr {4*$cell+$cell/2}]
    ::scidb::test::dlgplace::require [expr {$::tactics::move eq "e2e4"}] "compact board hit testing disagrees with rendering"
    set ::tactics::session {}
    list $overlap [winfo ismapped [::util::place::playingBody .tactics].board]
} -cleanup {
    catch {::tactics::close}
    ::scidb::test::dlgplace::stopTrace
} -result {0 1}

# --- VAL-DLG-010: placed dialogs follow the board --------------------
# While a dialog is open, a main-window resize (including the wide/tall
# reflow), a pure window move and fullscreen all move/resize the board; the
# shared helper must re-plan the dialog so it never covers the board, with
# one debounced re-place per settle.


proc ::scidb::test::dlgplace::dialogOverlap {dlg} {
    return [overlapArea [widgetRect $dlg] [boardRect]]
}
proc ::scidb::test::dlgplace::freeCorner {dlg} {
    # The first decorated-corner position that leaves the board untouched.
    lassign [boardRect] bx by bw bh
    lassign [winfo workarea $dlg] wx wy ww wh
    lassign [winfo extents $dlg] el er et eb
    set fw [expr {[winfo width $dlg] + $el + $er}]
    set fh [expr {[winfo height $dlg] + $et + $eb}]
    set candidates [list \
        [list [expr {$wx+10}] [expr {$wy+10}]] \
        [list [expr {$wx+$ww-$fw-10}] [expr {$wy+10}]] \
        [list [expr {$wx+10}] [expr {$wy+$wh-$fh-10}]] \
        [list [expr {$wx+$ww-$fw-10}] [expr {$wy+$wh-$fh-10}]]]
    foreach corner $candidates {
        lassign $corner x y
        if {[overlapArea [list $x $y $fw $fh] [boardRect]] == 0} {
            return $corner
        }
    }
    return {}
}
proc ::scidb::test::dlgplace::replaceDelta {script} {
    ::util::place::besideResetReplaceCount
    uplevel 1 $script
    return [::util::place::besideReplaceCount]
}
proc ::scidb::test::dlgplace::noOverlap {target dlg} {
    set area [overlapArea [outerRect $dlg] [boardRect]]
    puts "DLG $target main=[wm geometry .application] board=[boardRect] dlg=[widgetRect $dlg] overlap=$area replaces=[::util::place::besideReplaceCount]"
    require [expr {$area == 0}] "$target: dialog covers board by $area px2"
    return 1
}
# Wait for the actual board/window transition and the placement debounce.
# Cocoa fullscreen and the twm rebuild can finish after the initial Configure.
proc ::scidb::test::dlgplace::followSettled {dlg before {timeout 6000}} {
    set deadline [expr {[clock milliseconds] + $timeout}]
    set previous {}
    set changedAt [clock milliseconds]
    while {[clock milliseconds] < $deadline} {
        waitFor 20
        set snapshot [list [widgetRect .application] [boardRect] [widgetRect $dlg]]
        set now [clock milliseconds]
        if {$snapshot ne $previous} { set previous $snapshot; set changedAt $now }
        if {($before eq {} || [boardRect] ne $before) && !$::application::Vars(loading)
            && $::util::place::BesideTimer eq {} && $now - $changedAt >= 300} { return }
    }
    error "dialog transition did not settle: before=$before final=$previous"
}
proc ::scidb::test::dlgplace::follow {target dlg} {
    # Start wide enough to open normally, then force the tall reflow with the
    # contract's 1274x900 -> 800x900 resize.
	wm geometry .application [fitGeometry 1274 900]
	followSettled $dlg {}
    noOverlap $target-open $dlg
    # Aqua may move/resize native transients with their owner without an
    # explicit re-place. The movement and overlap checks remain mandatory.
    set nativeFollow [expr {[tk windowingsystem] eq "aqua"}]
    set before [widgetRect $dlg]

	set boardBefore [boardRect]
	set delta [replaceDelta {wm geometry .application [fitGeometry 800 900]; followSettled $dlg $boardBefore}]
    require [expr {$delta == 1 || ($nativeFollow && $delta == 0)}] "$target-resize: expected 1 re-place, got $delta"
    require [expr {[widgetRect $dlg] ne $before}] "$target-resize: dialog did not follow the board"
    noOverlap $target-resize $dlg

    set before [widgetRect $dlg]
    set boardBefore [boardRect]
    set delta [replaceDelta {wm geometry .application [::scidb::test::dlgplace::movedGeometry]; followSettled $dlg $boardBefore}]
    require [expr {$delta == 1 || ($nativeFollow && $delta == 0)}] "$target-move: expected 1 re-place, got $delta"
    require [expr {[widgetRect $dlg] ne $before}] "$target-move: dialog did not follow the board"
    noOverlap $target-move $dlg

    set boardBefore [boardRect]
    set delta [replaceDelta {::menu::viewFullscreen toggle; followSettled $dlg $boardBefore}]
    require [expr {$delta == 1 || ($nativeFollow && $delta == 0)}] "$target-fullscreen: expected 1 re-place, got $delta"
    noOverlap $target-fullscreen $dlg
    # Leaving fullscreen moves the board back; the dialog follows again.
    set boardBefore [boardRect]
    set delta [replaceDelta {::menu::viewFullscreen toggle; followSettled $dlg $boardBefore}]
    require [expr {$delta == 1 || ($nativeFollow && $delta == 0)}] "$target-unfullscreen: expected 1 re-place, got $delta"
    noOverlap $target-unfullscreen $dlg

    # Nothing else moves once settled: no repeated re-place/jitter.
    set count [::util::place::besideReplaceCount]
    waitFor 900
    require [expr {[::util::place::besideReplaceCount] == $count}] "$target: re-placed on an idle window"
    return 1
}
proc ::scidb::test::dlgplace::followCleanup {dlg closeScript} {
    catch {wm attributes .application -fullscreen 0}
    catch {uplevel 1 $closeScript}
    catch {destroy $dlg}
    ::util::place::besideResetReplaceCount
    set ::application::Vars(loading) 0
    stopTrace
    waitFor 200
}

foreach {target openScript dialog closeScript} {
    follow-tactics {::tactics::open .application} {.tactics} {::tactics::close}
    follow-playengine {::playengine::open .application} {.application.playengine} {::playengine::Close}
    follow-guessmove {::guessmove::start white} {.application.__guessmove__} {::guessmove::stop}
    follow-gamereview {set review [::gamereview::classify {{san e4 before 0 after 0 best 1} {san e5 before 0 after -250 best 0}}]; ::gamereview::ShowWindow .application $review {} 0} {.application.__gamereview} {destroy .application.__gamereview}
    follow-trainer {::endtrainer::open .application} {.application.__endtrainer__} {::endtrainer::Close}
} {
    tcltest::test dlg-$target {dialog follows board on resize, move and fullscreen without covering it} -setup {
        ::scidb::test::dlgplace::setupBoard
    } -body [format {
        %s
        ::scidb::test::dlgplace::waitFor 700
        ::scidb::test::dlgplace::follow %s %s
    } $openScript $target $dialog] -cleanup [format {
        ::scidb::test::dlgplace::followCleanup %s {%s}
    } $dialog $closeScript] -result 1
}

# A dialog the user moved away from the board is left where it is, even when
# the board moves; once that move puts it over the board it is re-placed.
tcltest::test dlg-follow-user-move {user-moved dialog is respected, even over the board (VAL-DLG-018C)} -setup {
    ::scidb::test::dlgplace::setupBoard
} -body {
    wm geometry .application [::scidb::test::dlgplace::fitGeometry 1274 900]
    ::playengine::open .application
    ::scidb::test::dlgplace::waitFor 800
    set dlg .application.playengine
    # A decorated corner that does not already cover the board (bottom-left
    # can be inside the board on a 1280x720 work area).
    lassign [::scidb::test::dlgplace::freeCorner $dlg] fx fy
    ::scidb::test::dlgplace::require [expr {$fx ne ""}] "no free corner for the user-move probe"
    wm geometry $dlg "+$fx+$fy"
    ::scidb::test::dlgplace::waitFor 800
    set moved [::scidb::test::dlgplace::widgetRect $dlg]
    ::scidb::test::dlgplace::noOverlap user-move-safe $dlg

    set delta [::scidb::test::dlgplace::replaceDelta {
        wm geometry .application [::scidb::test::dlgplace::fitGeometry 900 1000]
        ::scidb::test::dlgplace::waitFor 1400
    }]
    ::scidb::test::dlgplace::require [expr {$delta == 0}] "user-moved dialog was re-placed ($delta)"
    ::scidb::test::dlgplace::require [expr {[::scidb::test::dlgplace::widgetRect $dlg] eq $moved}] \
        "user-moved dialog changed position"
    ::scidb::test::dlgplace::noOverlap user-move-respected $dlg

    ::scidb::test::dlgplace::require [expr {[::util::place::besidePlacedBy $dlg] eq "user"}] \
        "user-moved dialog reads placed_by [::util::place::besidePlacedBy $dlg]"
    # Moving it onto the board is the user's choice too: the planner does
    # not re-place it (decision 2026-10-21).
    lassign [::scidb::test::dlgplace::boardRect] bx by bw bh
    wm geometry $dlg "+[expr {$bx+20}]+[expr {$by+20}]"
    ::scidb::test::dlgplace::waitFor 900
    set onBoard [::scidb::test::dlgplace::widgetRect $dlg]
    set delta [::scidb::test::dlgplace::replaceDelta {
        wm geometry .application [::scidb::test::dlgplace::fitGeometry 1274 900]
        ::scidb::test::dlgplace::waitFor 1400
    }]
    ::scidb::test::dlgplace::require [expr {$delta == 0 && [::scidb::test::dlgplace::widgetRect $dlg] eq $onBoard}] \
        "user-placed dialog was re-placed ($delta)"
    ::scidb::test::dlgplace::require [expr {[dict get [::util::place::besidePlacement $dlg] placed_by] eq "user"}] \
        "placement record does not read user"
    return 1
} -cleanup {
    catch {::playengine::Close}
    catch {destroy .application.playengine}
    catch {wm attributes .application -fullscreen 0}
    ::util::place::besideResetReplaceCount
    set ::application::Vars(loading) 0
    ::scidb::test::dlgplace::stopTrace
} -result 1

# Actual WM moves, with the native frame as the independent oracle. A user
# position is constrained by the monitor, never by the application's frame.
tcltest::testConstraint nativeDialogDrag [expr {[tk windowingsystem] eq "x11" && [auto_execok xdotool] ne {}}]
foreach edge {right bottom left top oversized} {
    tcltest::test dlg-user-workarea-$edge {user frame stays in monitor after drag and main resize} -constraints nativeDialogDrag -setup {
        ::scidb::test::dlgplace::setupBoard
        ::playengine::open .application
        ::scidb::test::dlgplace::waitFor 900
    } -body [format {
        set dlg .application.playengine
        lassign [winfo workarea $dlg] ax ay aw ah
        lassign [::scidb::tk::wm frame $dlg] x y w h
        set cw [winfo width $dlg]; set ch [winfo height $dlg]
        set px [expr {$ax+($aw-$w)/2}]
        set py [expr {$ay+($ah-$h)/2}]
        switch %s {
            right {set px [expr {$ax+$aw-40}]}
            bottom {set py [expr {$ay+$ah-40}]}
            left {set px [expr {$ax-40}]}
            top {set py [expr {$ay-40}]}
            oversized {set cw [expr {$aw+100}]; set ch [expr {$ah+100}]}
        }
        if {"%s" eq "oversized"} {
            wm geometry $dlg "${cw}x${ch}+$px+$py"
        } else {
            # Openbox's Alt+Button1 gesture moves the native frame. Start
            # safely in the centre; moving the pointer to the screen edge
            # leaves half the dialog beyond it; sample native frames during the drag.
            wm geometry $dlg "+[expr {$ax+($aw-$w)/2}]+[expr {$ay+($ah-$h)/2}]"
            ::scidb::test::dlgplace::waitFor 500
            raise $dlg
            focus -force $dlg
            ::scidb::test::dlgplace::waitFor 200
            set sx [expr {[winfo rootx $dlg]+$cw/2}]
            set sy [expr {[winfo rooty $dlg]+$ch/2}]
            set tx $sx; set ty $sy
            switch %s {
                right {set tx [expr {$ax+$aw-1}]}
                bottom {set ty [expr {$ay+$ah-1}]}
                left {set tx $ax}
                top {set ty $ay}
            }
            exec xdotool mousemove $sx $sy keydown Alt_L sleep 0.1 mousedown 1 sleep 0.1 \
                mousemove [expr {$sx+10}] [expr {$sy+10}] sleep 0.15 \
                mousemove $tx $ty sleep 0.15 mouseup 1 keyup Alt_L &
            set escaped {}
            for {set sample 0} {$sample < 40} {incr sample} {
                ::scidb::test::dlgplace::waitFor 20
                set observed [::scidb::tk::wm frame $dlg]
                if {![::scidb::test::dlgplace::inside $observed [winfo workarea $dlg]]} {
                    set escaped $observed
                }
            }
            ::scidb::test::dlgplace::require [expr {$escaped ne {}}] "native drag did not escape"
            puts "USER_DRAG edge=%s escaped=$escaped"
        }
        ::scidb::test::dlgplace::waitFor 1200
        set frame [::scidb::tk::wm frame $dlg]
        ::scidb::test::dlgplace::require \
            [::scidb::test::dlgplace::inside $frame [winfo workarea $dlg]] "escaped after %s: $frame"
        ::scidb::test::dlgplace::require \
            [expr {[::util::place::besidePlacedBy $dlg] eq "user"}] "lost user placement"
        if {"%s" ne "oversized"} {
            ::scidb::test::dlgplace::require \
                [expr {[winfo width $dlg] == $cw && [winfo height $dlg] == $ch}] "unnecessary shrink"
        } else {
            ::scidb::test::dlgplace::require \
                [expr {[winfo width $dlg] >= 240 && [winfo height $dlg] >= 180}] "lost viewport minimum"
        }
        wm geometry .application [::scidb::test::dlgplace::fitGeometry 900 600]
        ::scidb::test::dlgplace::waitFor 1400
        set resized [::scidb::tk::wm frame $dlg]
        ::scidb::test::dlgplace::require \
            [::scidb::test::dlgplace::inside $resized [winfo workarea $dlg]] "escaped after main resize: $resized"
        ::scidb::test::dlgplace::require [expr {$resized eq $frame}] "main resize changed user's safe frame"
        puts "USER_FRAME edge=%s frame=$frame resized=$resized area=[winfo workarea $dlg]"
        return 1
    } $edge $edge $edge $edge $edge $edge $edge] -cleanup {
        ::scidb::test::dlgplace::followCleanup .application.playengine {::playengine::Close}
    } -result 1
}

# Exercise real widgets with only OS work-area/frame reports substituted.
proc ::scidb::test::dlgplace::areaSetup {} {
 update
 waitFor 200
 ::application::switchTab board
 ::application::reflow::reset
 set ::application::reflow::S(override) {}
 wm geometry .application [::scidb::test::dlgplace::fitGeometry 800 900]
 waitFor 1600
 ::application::scalingChanged
 waitFor 500
 set dlg .application.areaDialog
 toplevel $dlg
 wm withdraw $dlg
 wm transient $dlg .application
 ttk::frame $dlg.content -width 700 -height 100
 pack $dlg.content
 ::util::place::besideBoard $dlg .application
 wm deiconify $dlg
 waitFor 700
 return $dlg
}

tcltest::test dlg-display-workarea {watcher repositions on area-only change and preserves safe user placement} -setup {
 set dlg [::scidb::test::dlgplace::areaSetup]
 set board [::util::place::besideBoardRect]
 lassign [winfo workarea .application] ax ay aw ah
 rename ::util::place::getWmWorkArea ::scidb::test::dlgplace::realArea
 proc ::util::place::getWmWorkArea {w} {return $::scidb::test::dlgplace::area}
 set wide [expr {int($aw*0.96)}]
 set narrow [expr {int($aw*0.88)}]
 set ::scidb::test::dlgplace::area [list $ax $ay $wide $ah]
} -body {
 ::util::place::besideResetReplaceCount
 ::application::displayWatch
 ::scidb::test::dlgplace::waitFor 1500
 set results [list [expr {$board eq [::util::place::besideBoardRect]}] \
  [::scidb::test::dlgplace::inside [::scidb::test::dlgplace::outerRect $dlg] $::scidb::test::dlgplace::area] \
  [::util::place::besideReplaceCount]]
 # A user move clear of the board remains safe in the next area.
 lassign [::scidb::test::dlgplace::outerRect $dlg] dx dy dw dh
 lassign [::util::place::getWmFrameExtents $dlg] el er et eb
 set margin [expr {max(1,int($ah*0.02))}]
 lassign [::scidb::test::dlgplace::windowWorkArea] mx my mw mh
 set bottomY [expr {min($ay+$ah,$my+$mh)-$dh-$margin}]
 lassign [::scidb::test::dlgplace::boardRect] bx by bw bh
 ::scidb::test::dlgplace::require [expr {$bottomY >= $by+$bh}] \
  "no space below the live board for the user-move probe"
 wm geometry $dlg +[expr {$ax+$margin+$el}]+[expr {$bottomY+$et}]
 ::scidb::test::dlgplace::waitFor 500
 set moved [::util::place::besideRect $dlg]
 ::util::place::besideResetReplaceCount
 set ::scidb::test::dlgplace::area [list $ax $ay $narrow $ah]
 ::application::displayWatch
 ::scidb::test::dlgplace::waitFor 1500
 lappend results [expr {$moved eq [::util::place::besideRect $dlg]}] [::util::place::besideReplaceCount]
 # The same user position must be recovered when the area excludes it.
 set short [expr {$bottomY-$ay+int($dh/2)}]
 set ::scidb::test::dlgplace::area [list $ax $ay $narrow $short]
 ::application::displayWatch
 ::scidb::test::dlgplace::waitFor 1500
 lappend results [::scidb::test::dlgplace::inside [::scidb::test::dlgplace::outerRect $dlg] $::scidb::test::dlgplace::area]
 set results
} -cleanup {
 destroy $dlg
 rename ::util::place::getWmWorkArea {}
 rename ::scidb::test::dlgplace::realArea ::util::place::getWmWorkArea
 ::application::displayWatch
 ::application::reflow::reset
} -result {1 1 1 1 0 1}

tcltest::test dlg-frame-request-invalidation {unchanged board still replans for frame and requested-size changes} -setup {
 set dlg [::scidb::test::dlgplace::areaSetup]
 rename ::util::place::getWmFrameExtents ::scidb::test::dlgplace::realExtents
 set ::scidb::test::dlgplace::extents [::scidb::test::dlgplace::realExtents $dlg]
 proc ::util::place::getWmFrameExtents {w} {return $::scidb::test::dlgplace::extents}
} -body {
 set board [::util::place::besideBoardRect]
 lassign $::scidb::test::dlgplace::extents l r t b
 set ::scidb::test::dlgplace::extents [list $l [expr {$r+20}] $t $b]
 ::util::place::besideResetReplaceCount
 ::util::place::besideSchedule
 ::scidb::test::dlgplace::waitFor 700
 set frameCount [::util::place::besideReplaceCount]
 # Suppress only the Configure callback to exercise settle's size key.
 bind $dlg <Configure> {}
 $dlg.content configure -width 750
 update idletasks
 ::util::place::besideResetReplaceCount
 ::util::place::besideSchedule
 ::scidb::test::dlgplace::waitFor 700
 list $frameCount [::util::place::besideReplaceCount] [expr {$board eq [::util::place::besideBoardRect]}]
} -cleanup {
 destroy $dlg
 rename ::util::place::getWmFrameExtents {}
 rename ::scidb::test::dlgplace::realExtents ::util::place::getWmFrameExtents
 ::application::reflow::reset
} -result {1 1 1}

# --- VAL-DLG-012: board-only and move-then-open no-room placement -----
# The same six playing dialogs must keep every control usable and never touch
# the drawn board when the board pane is zoomed or the main window was moved.
set ::scidb::test::dlgplace::closeScripts [dict create \
    playengine {::playengine::Close} \
    guessmove {::guessmove::stop; catch {destroy .application.__guessmove__}} \
    gamereview {catch {destroy .application.__gamereview}} \
    reptrainer {::reptrainer::Close .application.__reptrainer__} \
    endtrainer {::endtrainer::Close} \
    enginematch {::enginematch::Close}]

proc ::scidb::test::dlgplace::noRoomState {state} {
    set t [::application::reflow::boardTwm]
    if {$t ne ""} { catch { $t zoom "" } }
    catch { ::application::board::setReserve {} 0 }
    catch { wm attributes .application -fullscreen 0 }
    catch { wm state .application normal }
    wm geometry .application [::scidb::test::dlgplace::fitGeometry 1.0 1.0]
    waitFor 1000
    switch -- $state {
        board-only {
            if {$t ne ""} { catch { $t zoom [$t leaf board] } }
        }
        moved {
            lassign [winfo workarea .application] wx wy ww wh
            set w [expr {min(1274, $ww-70)}]
            set h [expr {min(698, $wh-60)}]
            wm geometry .application "${w}x${h}+[expr {$wx+57}]+[expr {$wy+41}]"
        }
        default { error "bad no-room state: $state" }
    }
    waitFor 1200
}
proc ::scidb::test::dlgplace::noRoomCheck {target dlg before} {
    waitFor 900
    set during [boardRect]
    set client [widgetRect $dlg]
    lassign [winfo extents $dlg] el er et eb
    # wm geometry reports the frame position, while winfo rootx/rooty report the
    # client inside the decorations. Build the decorated frame from the former.
    require [regexp {^([0-9]+)x([0-9]+)\+(-?[0-9]+)\+(-?[0-9]+)$} \
        [wm geometry $dlg] -> fw fh fx fy] "invalid geometry [wm geometry $dlg]"
    set outer [list $fx $fy [expr {$fw+$el+$er}] [expr {$fh+$et+$eb}]]
    set wa [winfo workarea $dlg]
    puts "DLG-NOROOM $target boardBefore=$before boardDuring=$during dlg=$client outer=$outer wa=$wa requested=[list [winfo reqwidth $dlg] [winfo reqheight $dlg]] reserve=$::application::board::ReserveSide/$::application::board::ReservePixels"
    require [expr {[overlapArea $client $during] == 0}] \
        "$target: client $client overlaps board $during"
    require [expr {[overlapArea $outer $during] == 0}] \
        "$target: decorated frame $outer overlaps board $during"
    require [inside $outer $wa] "$target: frame $outer outside $wa"
    require [expr {[winfo width $dlg] >= [winfo reqwidth $dlg]
        && [winfo height $dlg] >= [winfo reqheight $dlg]}] \
        "$target: dialog [winfo width $dlg]x[winfo height $dlg] clips requested [list [winfo reqwidth $dlg] [winfo reqheight $dlg]]"
    requireControls $target $dlg
    return 1
}
proc ::scidb::test::dlgplace::noRoomClose {dlg short before} {
    variable closeScripts
    puts "DLG-NOROOM-CLOSE $dlg before=$before board=[boardRect] reserve=$::application::board::ReserveSide/$::application::board::ReservePixels entries=$::util::place::BesideReserves"
    uplevel 1 [dict get $closeScripts $short]
    catch {destroy $dlg}
    waitFor 1000
    puts "DLG-NOROOM-CLOSE $dlg after board=[boardRect] reserve=$::application::board::ReserveSide/$::application::board::ReservePixels entries=$::util::place::BesideReserves"
    require [expr {[boardRect] eq $before}] \
        "board not restored after close: [boardRect] != $before"
    require [expr {$::application::board::ReservePixels == 0}] \
        "reserve not released after close: $::application::board::ReservePixels"
    return 1
}
proc ::scidb::test::dlgplace::noRoomCleanup {} {
    set t [::application::reflow::boardTwm]
    if {$t ne ""} { catch { $t zoom "" } }
    catch { ::application::board::setReserve {} 0 }
    catch { wm attributes .application -fullscreen 0 }
    catch { wm state .application normal }
    wm geometry .application [::scidb::test::dlgplace::fitGeometry 1.0 1.0]
    waitFor 700
    set ::application::Vars(loading) 0
    ::util::place::besideResetReplaceCount
}

foreach {short openScript dialog} {
    playengine {::playengine::open .application} {.application.playengine}
    guessmove {::guessmove::start white} {.application.__guessmove__}
    gamereview {set review [::gamereview::classify {{san e4 before 0 after 0 best 1} {san e5 before 0 after -250 best 0}}]; ::gamereview::ShowWindow .application $review {} 0} {.application.__gamereview}
    reptrainer {::reptrainer::open .application} {.application.__reptrainer__}
    endtrainer {::endtrainer::open .application} {.application.__endtrainer__}
    enginematch {::enginematch::open .application} {.application.enginematch}
} {
    foreach state {board-only moved} {
        tcltest::test dlg-noroom-$state-$short {board-only and move-then-open keep controls usable and the board uncovered} -setup {
            ::scidb::test::dlgplace::setupBoard
        } -body [format {
            ::scidb::test::dlgplace::noRoomState %s
            set before [::scidb::test::dlgplace::boardRect]
            %s
            ::scidb::test::dlgplace::noRoomCheck dlg-noroom-%s-%s %s $before
            ::scidb::test::dlgplace::noRoomClose %s %s $before
        } $state $openScript $state $short $dialog $dialog $short] -cleanup {
            ::scidb::test::dlgplace::noRoomCleanup
            ::scidb::test::dlgplace::stopTrace
        } -result 1
    }
}

# VAL-DLG-013: while a lesson video plays in the board inset, dialogs used
# during play must stay clear of both the drawn board and the visible inset.
namespace eval ::scidb::test::dlgplace {
    variable videoSaved {}
    variable videoStubs {}
}
proc ::scidb::test::dlgplace::videoStub {name args body} {
    variable videoSaved
    variable videoStubs
    rename ::media::mpv::$name [namespace current]::saved_$name
    lappend videoSaved $name
    proc ::media::mpv::$name $args $body
    lappend videoStubs $name
}
proc ::scidb::test::dlgplace::startVideo {} {
    ::application::switchTab board
    ::application::media::Ensure
    ::application::media::Stop
    ::scidb::test::dlgplace::videoStub available? {} {return 1}
    ::scidb::test::dlgplace::videoStub launch {path wid {ms 0}} {return 1}
    ::scidb::test::dlgplace::videoStub state {} {return playing}
    ::scidb::test::dlgplace::videoStub time {} {return 5}
    ::scidb::test::dlgplace::videoStub duration {} {return 120}
    ::scidb::test::dlgplace::videoStub stop {} {}
    ::scidb::test::dlgplace::videoStub aspect {} {return [expr {16.0/9}]}
    ::scidb::test::dlgplace::videoStub chapters {} {return {}}
    update
    waitFor 300
    set path [file normalize [file join $::scidb::test::dlgplace::testDir \
        tmp-app media-test MediaTest.media video analysis.mp4]]
    require [::application::media::PlayInProcess $path] "video did not start"
    waitFor 700
    require [expr {$::mediainset::Shown}] "video inset is not shown"
    set pane [::mediainset::Pane]
    require [winfo ismapped $pane.mediainset] "video inset is not mapped"
    return [widgetRect $pane.mediainset]
}
proc ::scidb::test::dlgplace::stopVideo {} {
    variable videoSaved
    variable videoStubs
    catch { ::application::media::Stop }
    foreach name $videoStubs {
        rename ::media::mpv::$name {}
        rename [namespace current]::saved_$name ::media::mpv::$name
    }
    set videoStubs {}
    set videoSaved {}
    waitFor 300
}
proc ::scidb::test::dlgplace::videoDialogCheck {target dlg insBefore} {
    waitFor 800
    set pane [::mediainset::Pane]
    set insetWidget $pane.mediainset
    require [winfo exists $insetWidget] "$target: inset disappeared"
    require [winfo ismapped $insetWidget] "$target: inset is not visible"
    set video [widgetRect $insetWidget]
    set board [boardRect]
    set client [widgetRect $dlg]
    lassign [winfo extents $dlg] el er et eb
    require [regexp {^([0-9]+)x([0-9]+)\+(-?[0-9]+)\+(-?[0-9]+)$} \
        [wm geometry $dlg] -> fw fh fx fy] "$target: invalid geometry [wm geometry $dlg]"
    set outer [list $fx $fy [expr {$fw+$el+$er}] [expr {$fh+$et+$eb}]]
    set wa [windowWorkArea]
    puts "DLG-VIDEO $target main=[wm geometry .application] board=$board video=$video dlg=$client outer=$outer wa=$wa requested=[list [winfo reqwidth $dlg] [winfo reqheight $dlg]] reserve=$::application::board::ReserveSide/$::application::board::ReservePixels"
    require [expr {[overlapArea $client $board] == 0}] \
        "$target: dialog $client overlaps board $board"
    require [expr {[overlapArea $outer $board] == 0}] \
        "$target: frame $outer overlaps board $board"
    require [expr {[overlapArea $client $video] == 0}] \
        "$target: dialog $client overlaps video $video"
    require [expr {[overlapArea $outer $video] == 0}] \
        "$target: frame $outer overlaps video $video"
    require [inside $outer $wa] "$target: frame $outer outside $wa"
    # A strip narrower than the dialog's request makes besideBoard shrink it
    # (VAL-DLG-012). What must never clip is an individual control.
    requireControls $target $dlg
    return [list $board $video]
}
proc ::scidb::test::dlgplace::videoRestoreCheck {target insBefore boardBefore} {
    waitFor 1100
    set pane [::mediainset::Pane]
    set insetWidget $pane.mediainset
    require [winfo exists $insetWidget] "$target: inset disappeared after close"
    require [winfo ismapped $insetWidget] "$target: inset is not visible after close"
    set video [widgetRect $insetWidget]
    puts "DLG-VIDEO-RESTORE $target before=$insBefore after=$video boardBefore=$boardBefore boardAfter=[boardRect] reserve=$::application::board::ReserveSide/$::application::board::ReservePixels"
    foreach a $video b $insBefore {
        require [expr {abs($a-$b) <= 1}] \
            "$target: inset not restored: $video != $insBefore"
    }
    require [expr {[boardRect] eq $boardBefore}] \
        "$target: board not restored: [boardRect] != $boardBefore"
    return 1
}
foreach {target openScript dialog closeScript} {
    playengine-video {::playengine::open .application} {.application.playengine} {::playengine::Close}
    guessmove-video {::guessmove::start white} {.application.__guessmove__} {::guessmove::stop; catch {destroy .application.__guessmove__}}
    gamereview-video {set review [::gamereview::classify {{san e4 before 0 after 0 best 1} {san e5 before 0 after -250 best 0}}]; ::gamereview::ShowWindow .application $review {} 0} {.application.__gamereview} {destroy .application.__gamereview}
    reptrainer-video {::reptrainer::open .application} {.application.__reptrainer__} {::reptrainer::Close .application.__reptrainer__}
    endtrainer-video {::endtrainer::open .application} {.application.__endtrainer__} {::endtrainer::Close}
    enginematch-video {::enginematch::open .application} {.application.enginematch} {::enginematch::Close}
} {
    foreach size {1280x720 1250x570 1920x1080} {
        lassign [split $size x] reqW reqH
        if {$reqW > [winfo screenwidth .] || $reqH > [winfo screenheight .]} { continue }
        tcltest::test dlg-video-$target-$size {playing video and board both stay clear of the dialog and the inset is restored} -setup {
            ::scidb::test::dlgplace::setupBoard
        } -body [format {
            wm geometry .application [::scidb::test::dlgplace::fitGeometry {*}[split %s x]]
            ::scidb::test::dlgplace::waitFor 1300
            set insBefore [::scidb::test::dlgplace::startVideo]
            set boardBefore [::scidb::test::dlgplace::boardRect]
            %s
            ::scidb::test::dlgplace::videoDialogCheck %s-%s %s $insBefore
            %s
            ::scidb::test::dlgplace::videoRestoreCheck %s-%s $insBefore $boardBefore
        } $size $openScript $target $size $dialog $closeScript $target $size] -cleanup {
            catch {::scidb::test::dlgplace::stopVideo}
            catch {destroy .application.playengine}
            catch {destroy .application.__guessmove__}
            catch {destroy .application.__gamereview}
            catch {destroy .application.__reptrainer__}
            catch {destroy .application.__endtrainer__}
            catch {destroy .application.enginematch}
            ::scidb::test::dlgplace::stopTrace
            ::scidb::test::dlgplace::noRoomCleanup
        } -result 1
    }
}

# -------------------------------------------------------------------------
# VAL-DLG-014 items (a)-(f) GUI tests
# -------------------------------------------------------------------------
namespace eval ::scidb::test::dlgplace { variable reserves {} }
proc ::scidb::test::dlgplace::reserveState {} {
    list $::application::board::ReserveSide $::application::board::ReservePixels \
        $::application::board::MinimumReserveSquare $::application::board::ReserveKind
}
proc ::scidb::test::dlgplace::reserveTrace {command code result op} {
    variable reserves
    if {!$code && [llength $result]} { lappend reserves [list [lindex $command 1] [dict get $result geometry]] }
}
proc ::scidb::test::dlgplace::zoomBoard {on} {
    set twm [::application::reflow::boardTwm]
    if {$on} { $twm zoom [$twm leaf board] } else { catch {$twm zoom ""} }
    waitFor 900
}
# A plain toplevel whose content is wider than either strip beside the board
# but small enough for two to fit in reserves (all from the live geometry).
proc ::scidb::test::dlgplace::syntheticSize {wa} {
    lassign [boardRect] bx by bw bh
    lassign $wa wx wy ww wh
    set strip [expr {max($wx+$ww-$bx-$bw, $bx-$wx)}]
    list [expr {$strip + max(24, $bw/10)}] [expr {min(220, $wh/2)}]
}
proc ::scidb::test::dlgplace::syntheticDialog {dlg size} {
    lassign $size fw fh
    toplevel $dlg
    wm transient $dlg .application
    frame $dlg.f -width $fw -height $fh
    pack $dlg.f
    update idletasks
}

# (a) When no strip outside the board fits a playing dialog, the video inset
# really moves or shrinks inside the board pane so the dialog covers neither
# the drawn board nor the inset (the inset dodge chooses a candidate; it is not a no-op).
tcltest::test dlg-v14-a-inset-dodge {inset dodge keeps a feasible board clear and moves when a clear candidate exists} -setup {
    ::scidb::test::dlgplace::setupBoard
    toplevel .application.dlgVideoDodgeOwner
    wm withdraw .application.dlgVideoDodgeOwner
} -body {
    wm geometry .application [::scidb::test::dlgplace::fitGeometry 1000 600]
    ::scidb::test::dlgplace::waitFor 1200
    set insBefore [::scidb::test::dlgplace::startVideo]
    set videoBefore [::util::place::besideVideoRect]
    lassign $videoBefore vx vy vw vh
    set testRect [list [expr {$vx - 10}] [expr {$vy - 10}] [expr {$vw + 20}] [expr {$vh + 20}]]
    # Keep the original full-video obstruction as a negative/safety case.
    # MED-013 forbids choosing a candidate over the board when a strip is
    # already accepted; a genuine lack of a clear candidate may return zero.
    set wholeMoved [::mediainset::DodgeForDialog .application.dlgVideoDodgeOwner $testRect]
    ::scidb::test::dlgplace::waitFor 400
    set wholeAfter [::util::place::besideVideoRect]
    set wholeSafe [expr {
        [::scidb::test::dlgplace::overlapArea $wholeAfter [::scidb::test::dlgplace::boardRect]] == 0
        && ($wholeMoved ? [::scidb::test::dlgplace::overlapArea $wholeAfter $testRect] == 0 : $wholeAfter eq $videoBefore)}]
    ::mediainset::RestoreAfterDialog .application.dlgVideoDodgeOwner
    ::scidb::test::dlgplace::waitFor 400
    # A small obstruction through the centre leaves a safe vertical move
    # within the strip. The positive path must still choose a real move.
    set testRect [list [expr {$vx+$vw/2-5}] [expr {$vy+$vh/2-5}] 10 10]
    set dodged [::mediainset::DodgeForDialog .application.dlgVideoDodgeOwner $testRect]
    ::scidb::test::dlgplace::waitFor 400
    set videoAfter [::util::place::besideVideoRect]
    set overlap [::scidb::test::dlgplace::overlapArea $videoAfter $testRect]
    ::scidb::test::dlgplace::require [expr {[::scidb::test::dlgplace::overlapArea $videoAfter [::scidb::test::dlgplace::boardRect]] == 0}] "safe dodge covered the board"
    ::mediainset::RestoreAfterDialog .application.dlgVideoDodgeOwner
    ::scidb::test::dlgplace::waitFor 400
    set videoRestored [::util::place::besideVideoRect]
    list $wholeSafe $dodged [expr {$overlap == 0}] [expr {$videoAfter ne $videoBefore}] [expr {$videoRestored eq $videoBefore}]
} -cleanup {
    catch {destroy .application.dlgVideoDodgeOwner}
    catch {::scidb::test::dlgplace::stopVideo}
    ::scidb::test::dlgplace::stopTrace
    ::scidb::test::dlgplace::noRoomCleanup
} -result {1 1 1 1 1}

# (b) Opening two beside-board dialogs that each reserve a strip and closing
# them in either order leaves no reserve behind: after both close,
# ReserveSide/ReservePixels and the square floor equal their values before the first opened.
tcltest::test dlg-v14-b-reserves-both-orders {two dialogs share a real reserve, close in either order and restore exact reserve state} -setup {
    ::scidb::test::dlgplace::setupBoard
    ::scidb::test::dlgplace::zoomBoard 1
} -body {
    set wa [::scidb::test::dlgplace::windowWorkArea]
    set out {}
    foreach order {{.dlg1 .dlg2} {.dlg2 .dlg1}} {
        set before [::scidb::test::dlgplace::reserveState]
        set boardBefore [::scidb::test::dlgplace::boardRect]
        set ::scidb::test::dlgplace::reserves {}
        trace add execution ::util::place::besideReserve leave ::scidb::test::dlgplace::reserveTrace
        trace add execution ::util::place::besideRequestedReserve leave ::scidb::test::dlgplace::reserveTrace
        # Wider than either free strip beside the zoomed board, so each
        # dialog only fits by registering a reserve (live geometry, measured
        # before the first reserve moves the board).
        set size [::scidb::test::dlgplace::syntheticSize $wa]
        foreach dlg {.dlg1 .dlg2} {
            ::scidb::test::dlgplace::syntheticDialog $dlg $size
            ::util::place::besideBoard $dlg .application
            ::scidb::test::dlgplace::waitFor 500
        }
        trace remove execution ::util::place::besideReserve leave ::scidb::test::dlgplace::reserveTrace
        trace remove execution ::util::place::besideRequestedReserve leave ::scidb::test::dlgplace::reserveTrace
        set owners {}
        foreach e $::util::place::BesideReserves { lappend owners [lindex $e 0] }
        puts "DLG-V14B order=$order before=$before during=[::scidb::test::dlgplace::reserveState] owners=$owners reserves=$::scidb::test::dlgplace::reserves board=[::scidb::test::dlgplace::boardRect] d1=[::scidb::test::dlgplace::outerRect .dlg1] d2=[::scidb::test::dlgplace::outerRect .dlg2]"
        # Require a real reserve and both live owners. At the 32px floor,
        # the second dialog may share a column without growing the strip.
        ::scidb::test::dlgplace::require [expr {[llength $::scidb::test::dlgplace::reserves] >= 1}] \
            "expected a real accepted reserve, got $::scidb::test::dlgplace::reserves"
        ::scidb::test::dlgplace::require [expr {$owners eq {.dlg1 .dlg2}}] "reserve owners $owners"
        set board [::scidb::test::dlgplace::boardRect]
        foreach dlg {.dlg1 .dlg2} {
            set o [::scidb::test::dlgplace::outerRect $dlg]
            ::scidb::test::dlgplace::require [expr {[::scidb::test::dlgplace::overlapArea $o $board] == 0}] \
                "$dlg $o covers board $board"
            ::scidb::test::dlgplace::require [::scidb::test::dlgplace::inside $o $wa] "$dlg $o outside $wa"
        }
        ::scidb::test::dlgplace::require [expr {[::scidb::test::dlgplace::overlapArea \
            [::scidb::test::dlgplace::outerRect .dlg1] [::scidb::test::dlgplace::outerRect .dlg2]] == 0}] \
            "stacked dialogs overlap each other"
        foreach dlg $order { destroy $dlg; ::scidb::test::dlgplace::waitFor 500 }
        set after [::scidb::test::dlgplace::reserveState]
        puts "DLG-V14B-RESTORE order=$order before=$before after=$after boardBefore=$boardBefore boardAfter=[::scidb::test::dlgplace::boardRect]"
        lappend out [expr {$after eq $before && [::scidb::test::dlgplace::boardRect] eq $boardBefore}]
    }
    set out
} -cleanup {
    catch {trace remove execution ::util::place::besideReserve leave ::scidb::test::dlgplace::reserveTrace}
    catch {trace remove execution ::util::place::besideRequestedReserve leave ::scidb::test::dlgplace::reserveTrace}
    catch {destroy .dlg1}
    catch {destroy .dlg2}
    ::scidb::test::dlgplace::zoomBoard 0
    ::scidb::test::dlgplace::stopTrace
    ::scidb::test::dlgplace::noRoomCleanup
} -result {1 1}

# (c) Maximise, restore and a scripted window resize re-plan an open playing
# dialog (it follows the board); only a real user move/resize of the dialog stops following.
tcltest::test dlg-v14-c-resize-and-user-move {window resize follows board; a user move stops following, even onto the board (VAL-DLG-018C)} -setup {
    ::scidb::test::dlgplace::setupBoard
} -body {
    wm geometry .application [::scidb::test::dlgplace::fitGeometry 1.0 1.0]
    ::scidb::test::dlgplace::waitFor 1000
    ::playengine::open .application
    ::scidb::test::dlgplace::waitFor 800
    set dlg .application.playengine
    # Follows board on a resize the WM really grants (both sizes derived from
    # the live work area, so this holds at 1000x600 too):
    set g0 [wm geometry .application]
    set deltaResize [::scidb::test::dlgplace::replaceDelta {
        wm geometry .application [::scidb::test::dlgplace::fitGeometry 0.9 1.0]
        ::scidb::test::dlgplace::waitFor 1000
    }]
    ::scidb::test::dlgplace::require [expr {[wm geometry .application] ne $g0}] \
        "resize was not granted: $g0"
    # Now simulate user move to safe corner:
    lassign [::scidb::test::dlgplace::freeCorner $dlg] fx fy
    wm geometry $dlg "+$fx+$fy"
    ::scidb::test::dlgplace::waitFor 800
    # Subsequent window resize must NOT re-plan while safe:
    set deltaUserSafe [::scidb::test::dlgplace::replaceDelta {
        wm geometry .application [::scidb::test::dlgplace::fitGeometry 0.85 1.0]
        ::scidb::test::dlgplace::waitFor 1000
    }]
    # Dragging it onto the board is the user's choice too (decision
    # 2026-10-21): the planner leaves it there.
    lassign [::scidb::test::dlgplace::boardRect] bx by bw bh
    set deltaCollision [::scidb::test::dlgplace::replaceDelta {
        wm geometry $dlg "+[expr {$bx+20}]+[expr {$by+20}]"
        ::scidb::test::dlgplace::waitFor 1000
    }]
    list [expr {$deltaResize > 0}] [expr {$deltaUserSafe == 0}] [expr {$deltaCollision == 0}]
} -cleanup {
    catch {::playengine::Close}
    ::scidb::test::dlgplace::stopTrace
    ::scidb::test::dlgplace::noRoomCleanup
} -result {1 1 1}

# (d) Stopping or hiding the video while a dialog is open re-plans the dialog
# and releases the video's strip so the board regrows.
tcltest::test dlg-v14-d-video-stop-regrows-board {stopping video replans dialog and regrows board} -setup {
    ::scidb::test::dlgplace::setupBoard
} -body {
    lassign [winfo workarea .application] wx wy ww wh
    # Zoom the real board pane so saved split proportions cannot turn the
    # above-floor fixture into an overlay on a larger display.
    ::scidb::test::dlgplace::noRoomState board-only
    wm geometry .application [::scidb::test::dlgplace::fitGeometry 1000 [expr {min(640,$wh)}]]
    ::scidb::test::dlgplace::waitFor 1000
    # Compare equivalent dialog states: Game Review may reserve space even
    # without video, so its settled no-video board is the restoration baseline.
    set review [::gamereview::classify {{san e4 before 0 after 0 best 1} {san e5 before 0 after -250 best 0}}]
    ::gamereview::ShowWindow .application $review {} 0
    ::scidb::test::dlgplace::waitFor 1000
    set squareBefore $::application::board::Dim(squaresize:Normal)
    set boardBefore [::scidb::test::dlgplace::boardRect]
    ::scidb::test::dlgplace::startVideo
    set videoSquare $::application::board::Dim(squaresize:Normal)
    ::scidb::test::dlgplace::require [expr {$::application::board::ReservePixels > 0 && $videoSquare >= $::application::board::MinimumReserveSquare && $videoSquare < $squareBefore}] "above-floor fixture did not shrink for video: app=[wm geometry .application] before=$squareBefore square=$videoSquare reserve=$::application::board::ReserveSide/$::application::board::ReservePixels"
    puts "VIDEO-RESERVE live=[winfo workarea .application] side=$::application::board::ReserveSide pixels=$::application::board::ReservePixels before=$squareBefore square=$videoSquare baseline={$boardBefore}"
    set boardDuring [::scidb::test::dlgplace::boardRect]
    set dlgDuring [::scidb::test::dlgplace::widgetRect .application.__gamereview]
    set reserveDuring [list $::application::board::ReserveSide $::application::board::ReservePixels]

    # Stop video:
    ::scidb::test::dlgplace::stopVideo
    ::scidb::test::dlgplace::waitFor 1000
    set boardAfter [::scidb::test::dlgplace::boardRect]
    set dlgAfter [::scidb::test::dlgplace::widgetRect .application.__gamereview]
    set reserveAfter [list $::application::board::ReserveSide $::application::board::ReservePixels]
    # The surviving dialog may still own a strip after video releases its own.
    set videoReleased [expr {$reserveAfter eq {{} 0} || $::application::board::ReserveKind eq "dialog"}]
    set overlap [::scidb::test::dlgplace::overlapArea $dlgAfter $boardAfter]

    puts "VIDEO-STOP live=[winfo workarea .application] reserve=$reserveDuring before=$squareBefore after=$::application::board::Dim(squaresize:Normal)"
    ::scidb::test::dlgplace::require [expr {$::application::board::Dim(squaresize:Normal) == $squareBefore}] "Stop did not restore exact board square"
    ::scidb::test::dlgplace::require [expr {$boardAfter eq $boardBefore}] "Stop did not restore exact board rectangle: before=$boardBefore after=$boardAfter"
    list [expr {$reserveDuring ne {{} 0}}] \
         $videoReleased \
         [expr {$boardAfter ne $boardDuring}] \
         [expr {$overlap == 0}]
} -cleanup {
    catch {::scidb::test::dlgplace::stopVideo}
    catch {destroy .application.__gamereview}
    ::scidb::test::dlgplace::stopTrace
    ::scidb::test::dlgplace::noRoomCleanup
} -result {1 1 1 1}

tcltest::test dlg-v14-d-video-below-floor-reserve {below-floor video takes a non-shrinking strip when available and Stop restores exactly} -setup {
    ::scidb::test::dlgplace::setupBoard
} -body {
    wm geometry .application [::scidb::test::dlgplace::fitGeometry 1250 570]
    ::scidb::test::dlgplace::waitFor 1000
    set before [::scidb::test::dlgplace::boardRect]
    set squareBefore $::application::board::Dim(squaresize:Normal)
    ::scidb::test::dlgplace::startVideo
    set reserve [list $::application::board::ReserveSide $::application::board::ReservePixels]
    set canvas $::application::board::Vars(widget:frame)
    set width [winfo width $canvas]; set height [winfo height $canvas]
    set best [expr {max(
        [::application::board::reserveSquare right 168 $width $height],
        [::application::board::reserveSquare bottom [expr {int(round(160/(16.0/9)))+[winfo reqheight [::mediainset::Pane].mediainset.controls]+8}] $width $height])}]
    ::scidb::test::dlgplace::require [expr {$best < $::application::board::MinimumReserveSquare}] "fixture no longer below floor: $best"
    if {$best > 0} {
        ::scidb::test::dlgplace::require [expr {$::application::board::Dim(squaresize:Normal) == $squareBefore}] "below-floor video shrank board"
        set inset [::scidb::test::dlgplace::widgetRect [::mediainset::Pane].mediainset]
        foreach tag {board stm material} {
            set bbox [$canvas bbox $tag]
            if {[llength $bbox] != 4} {continue}
            lassign $bbox x1 y1 x2 y2
            set rect [list [expr {[winfo rootx $canvas]+$x1}] [expr {[winfo rooty $canvas]+$y1}] [expr {$x2-$x1}] [expr {$y2-$y1}]]
            ::scidb::test::dlgplace::require [expr {[::scidb::test::dlgplace::overlapArea $rect $inset] == 0}] "below-floor video overlaps $tag"
        }
    }
    ::scidb::test::dlgplace::stopVideo
    puts "VIDEO-BELOW-FLOOR live=[winfo workarea .application] best=$best reserve=$reserve"
    list [expr {($best > 0) == ([lindex $reserve 0] ne "")}] [expr {[::scidb::test::dlgplace::boardRect] eq $before}] \
        [expr {$::application::board::Dim(squaresize:Normal) == $squareBefore}]
} -cleanup {
    catch {::scidb::test::dlgplace::stopVideo}
    ::scidb::test::dlgplace::stopTrace
    ::scidb::test::dlgplace::noRoomCleanup
} -result {1 1 1}

# (e) A dialog-owned left reserve centres the board in the remaining area like a right reserve does.
tcltest::test dlg-v14-e-left-reserve-centering {dialog-owned left reserve centers board like right reserve} -setup {
    ::scidb::test::dlgplace::setupBoard
} -body {
    wm geometry .application [::scidb::test::dlgplace::fitGeometry 1280 720]
    ::scidb::test::dlgplace::waitFor 800
    # A strip the live board frame can afford (a fixed 200 px is refused on a
    # 1000x600 screen): a sixth of the frame width.
    set px [expr {[winfo width $::application::board::Vars(widget:frame)] / 6}]
    set floor $::application::board::MinimumReserveSquare
    set ::application::board::MinimumReserveSquare 1

    set canvas $::application::board::Vars(widget:frame)
    set offsets {}
    foreach side {left right} {
        ::scidb::test::dlgplace::require [::application::board::setReserve $side $px dialog] "$side $px refused"
        lassign [::scidb::test::dlgplace::boardRect] bx by bw bh
        set origin [expr {$side eq "left" ? $px : 0}]
        set offset [expr {$bx-[winfo rootx $canvas]+$bw/2.0
            -($origin+([winfo width $canvas]-$px)/2.0)}]
        puts "DLG-019C side=$side workarea=[winfo workarea .application] source=winfo-workarea reserve=[::scidb::test::dlgplace::reserveState] offset=$offset"
        lappend offsets [expr {abs($offset) <= 1}]
    }
    set leftCentered [expr {$offsets eq {1 1}}]

    # Test squeeze left reserve (flush against originX)
    ::scidb::test::dlgplace::require [::application::board::setReserve left $px squeeze] "squeeze $px refused"
    set squeezeBrdX $::application::board::Dim(border:x1)
    set squeezeFlush [expr {$squeezeBrdX == $px}]
    set ::application::board::MinimumReserveSquare $floor

    ::application::board::setReserve {} 0
    list $leftCentered $squeezeFlush
} -cleanup {
    if {[info exists floor]} {set ::application::board::MinimumReserveSquare $floor}
    ::application::board::setReserve {} 0
    ::scidb::test::dlgplace::stopTrace
    ::scidb::test::dlgplace::noRoomCleanup
} -result {1 1}

# (f) Tests assert the dialog frame inside the main window's work area (not just the screen),
# and the drawn board rectangle includes any side bars drawn with the board.
tcltest::test dlg-v14-f-workarea-and-sidebars {dialog inside window workarea and boardRect includes sidebars} -setup {
    ::scidb::test::dlgplace::setupBoard
} -body {
    wm geometry .application [::scidb::test::dlgplace::fitGeometry 1280 720]
    ::scidb::test::dlgplace::waitFor 800
    set canv $::application::board::Vars(widget:frame)
    set rawBoard [$canv bbox board]
    set fullBoard [::scidb::test::dlgplace::boardRect]
    lassign $fullBoard bx by bw bh
    lassign $rawBoard rx0 ry0 rx1 ry1
    set rawW [expr {$rx1 - $rx0}]

    # Full drawn board must include side-to-move, material etc. so width is > raw board
    set includesSideBars [expr {$bw >= $rawW}]

    # windowWorkArea bounds
    set wa [::scidb::test::dlgplace::windowWorkArea]
    lassign $wa wx wy ww wh
    set waValid [expr {$ww > 0 && $wh > 0 && $ww <= [winfo width .application] + 20}]

    ::playengine::open .application
    ::scidb::test::dlgplace::waitFor 800
    set dlg .application.playengine
    lassign [winfo extents $dlg] el er et eb
    regexp {^([0-9]+)x([0-9]+)\+(-?[0-9]+)\+(-?[0-9]+)$} [wm geometry $dlg] -> fw fh fx fy
    set outer [list $fx $fy [expr {$fw+$el+$er}] [expr {$fh+$et+$eb}]]
    set inWa [::scidb::test::dlgplace::inside $outer $wa]

    list $includesSideBars $waValid $inWa
} -cleanup {
    catch {::playengine::Close}
    ::scidb::test::dlgplace::stopTrace
    ::scidb::test::dlgplace::noRoomCleanup
} -result {1 1 1}

# -------------------------------------------------------------------------
# VAL-DLG-015: real playback; maximize and two playing dialogs
# -------------------------------------------------------------------------
tcltest::testConstraint haveWmctrl [expr {[auto_execok wmctrl] ne ""}]
proc ::scidb::test::dlgplace::realVideo {} {
    ::application::switchTab board
    ::application::media::Ensure
    ::application::media::Stop
    set path [file normalize [file join $::scidb::test::dlgplace::testDir \
        tmp-app media-test MediaTest.media video analysis.mp4]]
    require [::application::media::PlayInProcess $path] "video did not start"
    waitFor 900
    set t0 [::media::mpv::time]
    # mpv can report playing while its first software-rendered frame is
    # still starting on a fresh X server. Require actual progress, bounded.
    set deadline [expr {[clock milliseconds]+5000}]
    while {[clock milliseconds] < $deadline
        && ([::media::mpv::state] ne "playing" || [::media::mpv::time] <= $t0)} {
        waitFor 100
    }
    require [expr {[::media::mpv::state] eq "playing" && [::media::mpv::time] > $t0}] \
        "real playback is not advancing: [::media::mpv::state] $t0 -> [::media::mpv::time]"
    require [winfo ismapped [::mediainset::Pane].mediainset] "video inset is not mapped"
}
proc ::scidb::test::dlgplace::clearOf {target dlg} {
    set board [boardRect]
    set video [widgetRect [::mediainset::Pane].mediainset]
    set outer [outerRect $dlg]
    set client [widgetRect $dlg]
    set wa [windowWorkArea]
    set ob [expr {[overlapArea $outer $board] + [overlapArea $client $board]}]
    set ov [expr {[overlapArea $outer $video] + [overlapArea $client $video]}]
    puts "DLG-V15 $target main=[wm geometry .application] zoomed=[wm attributes .application -zoomed] board=$board video=$video frame=$outer wa=$wa overlapBoard=$ob overlapVideo=$ov reserve=[reserveState] mpv=[::media::mpv::state]/[::media::mpv::time] replaces=[::util::place::besideReplaceCount]"
    require [expr {$ob == 0}] "$target: frame $outer covers board $board"
    require [expr {$ov == 0}] "$target: frame $outer covers video $video"
    require [inside $outer $wa] "$target: frame $outer outside $wa"
    # VAL-DLG-016: clear of board and inset is not enough; no control may be
    # squeezed below its requested size to get there.
    requireControls $target $dlg
    return 1
}
# VAL-DLG-017B: one of two playing dialogs either is clear of board and inset,
# or, when the pair cannot both fit, its last plan names the no-room rule:
# smallest board overlap of the right/left/below candidates that do not
# cover the peer, inside the work area, controls at requested size. Never
# on top of the peer either way.
proc ::scidb::test::dlgplace::pairClearOf {target dlg peer {second 1}} {
    set outer [outerRect $dlg]
    set po [outerRect $peer]
    require [expr {[overlapArea $outer $po] == 0}] "$target: frame $outer is under/over peer $po"
    set plan {}
    if {[info exists ::util::place::BesideLastPlan($dlg)]} { set plan $::util::place::BesideLastPlan($dlg) }
    set rule [expr {[dict exists $plan rule] ? [dict get $plan rule] : ""}]
    if {$rule ne "no-room"} { return [clearOf $target $dlg] }
    # Recompute the minimum from the raw candidate rectangles: the second
    # dialog of a pair takes the least board overlap among candidates clear
    # of the peer, a first/single dialog the plain three-candidate minimum.
    require [dict exists $plan record] "$target: no-room plan has no candidate record"
    set board [boardRect]
    set allowed {}
    set chosen {}
    dict for {side rec} [dict get $plan record] {
        set rect [dict get $rec rect]
        set ob [overlapArea $rect $board]
        if {[dict get $rec chosen]} { set chosen $ob }
        if {$second && [overlapArea $rect $po] > 0} { continue }
        lappend allowed $ob
    }
    puts "DLG-V17B $target rule=no-room frame=$outer peer=$po board=$board record=[dict get $plan record] chosen=$chosen allowed=$allowed"
    require [llength $allowed] "$target: no peer-free no-room candidate"
    require [expr {$chosen ne {} && $chosen == [tcl::mathfunc::min {*}$allowed]}] \
        "$target: no-room overlap $chosen is not the minimum of $allowed"
    require [inside $outer [windowWorkArea]] "$target: frame $outer outside [windowWorkArea]"
    requireControls $target $dlg
    return 1
}
proc ::scidb::test::dlgplace::wmctrlMax {on} {
    set id [wm frame .application]
    exec wmctrl -ir $id -b [expr {$on ? "add" : "remove"}],maximized_vert,maximized_horz
}
proc ::scidb::test::dlgplace::realCleanup {} {
    catch {::playengine::Close}
    catch {::enginematch::Close}
    catch {destroy .application.playengine}
    catch {destroy .application.enginematch}
    catch {wm attributes .application -zoomed 0}
    catch {::application::media::Stop}
    zoomBoard 0
    stopTrace
    noRoomCleanup
}

# (a) A real maximize (Tk and WM-initiated) re-plans the playing dialog within
# 500 ms; restore re-plans again; a user's own move then stops following.
tcltest::test dlg-v15-a-maximize-playing {real maximize and restore re-plan a playing dialog clear of board and inset} -setup {
    ::scidb::test::dlgplace::setupBoard
    catch {wm minsize .application 1 1}
} -constraints haveWmctrl -body {
    wm geometry .application [::scidb::test::dlgplace::fitGeometry 0.72 0.8]
    ::scidb::test::dlgplace::waitFor 1000
    ::scidb::test::dlgplace::realVideo
    ::playengine::open .application
    ::scidb::test::dlgplace::waitFor 1300
    set dlg .application.playengine
    ::scidb::test::dlgplace::clearOf v15a-open $dlg
    set small [wm geometry .application]
    foreach {step trigger script} {
        tk-maximize   maximize {wm attributes .application -zoomed 1}
        tk-restore    restore  {wm attributes .application -zoomed 0}
        wm-maximize   maximize {::scidb::test::dlgplace::wmctrlMax 1}
        wm-restore    restore  {::scidb::test::dlgplace::wmctrlMax 0}
    } {
        set g [wm geometry .application]
        set seq $::util::place::BesideRecordSeq
        set t0 [clock milliseconds]
        set delta [::scidb::test::dlgplace::replaceDelta "$script; ::scidb::test::dlgplace::waitFor 1000"]
        ::scidb::test::dlgplace::require [expr {[wm geometry .application] ne $g}] "$step: window did not change ($g)"
        ::scidb::test::dlgplace::require [expr {$delta >= 1}] "$step: dialog was not re-planned within 1 s"
        # VAL-DLG-018A: the helper records the re-plan with its trigger.
        set late {}
        foreach r [::util::place::besidePlacementLog $seq] {
            if {[dict get $r dialog] eq $dlg && [dict get $r trigger] eq $trigger
                && [dict get $r placed_by] eq "planner"} { lappend late [expr {[dict get $r time] - $t0}] }
        }
        ::scidb::test::dlgplace::require [expr {[llength $late] && [lindex $late 0] <= 500}] \
            "$step: no $trigger placement record within 500 ms ($late)"
        ::scidb::test::dlgplace::clearOf v15a-$step $dlg
    }
    # A user's own move to a safe spot stops following.
    lassign [::scidb::test::dlgplace::freeCorner $dlg] fx fy
    ::scidb::test::dlgplace::require [expr {$fx ne ""}] "no free corner for the user move"
    wm geometry $dlg "+$fx+$fy"
    ::scidb::test::dlgplace::waitFor 900
    set moved [::scidb::test::dlgplace::widgetRect $dlg]
    set delta [::scidb::test::dlgplace::replaceDelta {
        wm geometry .application [::scidb::test::dlgplace::fitGeometry 0.68 0.8]
        ::scidb::test::dlgplace::waitFor 1000
    }]
    set safe [expr {[::scidb::test::dlgplace::dialogOverlap $dlg] == 0
        && [::scidb::test::dlgplace::overlapArea [::scidb::test::dlgplace::outerRect $dlg] \
            [::scidb::test::dlgplace::widgetRect [::mediainset::Pane].mediainset]] == 0}]
    puts "DLG-V15 user-move moved=$moved after=[::scidb::test::dlgplace::widgetRect $dlg] delta=$delta safe=$safe"
    # VAL-DLG-018C: the user's place is kept, whatever the resize does.
    ::scidb::test::dlgplace::require [expr {$delta == 0 && [::scidb::test::dlgplace::widgetRect $dlg] eq $moved}] \
        "user-moved dialog was re-placed ($delta)"
    ::scidb::test::dlgplace::require [expr {[::util::place::besidePlacedBy $dlg] eq "user"}] \
        "user-moved dialog reads placed_by [::util::place::besidePlacedBy $dlg]"
    return 1
} -cleanup {
    ::scidb::test::dlgplace::realCleanup
} -result 1

# (b) Two playing dialogs open at once, board zoomed or not: neither covers
# the drawn board or the inset, or the pair's named no-room rule applies
# (VAL-DLG-017B); never one under the other; both close orders restore
# reserve and board.
foreach zoom {0 1} {
    tcltest::test dlg-v15-b-two-playing-zoom$zoom {two playing dialogs never cover board or inset; either close order restores} -setup {
        ::scidb::test::dlgplace::setupBoard
        catch {wm minsize .application 1 1}
    } -body [format {
        wm geometry .application [::scidb::test::dlgplace::fitGeometry 1000 600]
        ::scidb::test::dlgplace::waitFor 900
        ::scidb::test::dlgplace::zoomBoard %d
        ::scidb::test::dlgplace::realVideo
        set out {}
        set ::scidb::test::dlgplace::unowned {}
        foreach order {{playengine enginematch} {enginematch playengine}} {
            set before [::scidb::test::dlgplace::reserveState]
            set boardBefore [::scidb::test::dlgplace::boardRect]
            ::playengine::open .application
            ::scidb::test::dlgplace::waitFor 900
            ::enginematch::open .application
            ::scidb::test::dlgplace::waitFor 1100
            ::scidb::test::dlgplace::pairClearOf v15b-%d-playengine .application.playengine .application.enginematch 0
            ::scidb::test::dlgplace::pairClearOf v15b-%d-enginematch .application.enginematch .application.playengine
            ::scidb::test::dlgplace::require [expr {![llength $::scidb::test::dlgplace::unowned]}] \
                "besideBoard returned without a live owner: $::scidb::test::dlgplace::unowned"
            foreach short $order {
                if {$short eq "playengine"} { ::playengine::Close } else { ::enginematch::Close }
                catch {destroy .application.$short}
                ::scidb::test::dlgplace::waitFor 1000
            }
            set after [::scidb::test::dlgplace::reserveState]
            puts "DLG-V15-RESTORE order=$order before=$before after=$after boardBefore=$boardBefore boardAfter=[::scidb::test::dlgplace::boardRect]"
            lappend out [expr {$after eq $before && [::scidb::test::dlgplace::boardRect] eq $boardBefore}]
        }
        set out
    } $zoom $zoom $zoom] -cleanup {
        ::scidb::test::dlgplace::realCleanup
    } -result {1 1}
}

# W9h: the oracle uses the measured native frame's size and independently
# clamps all three raw candidates. It never consumes the planner's candidates.
proc ::scidb::test::dlgplace::nativeMinimum {dlg} {
    set frame [::scidb::tk::wm frame $dlg]
    if {[llength $frame] != 4} {return}
    set plan $::util::place::BesideLastPlan($dlg)
    if {[dict get $plan rule] ne "no-room"} {return}
    lassign $frame x y w h
    lassign [boardRect] bx by bw bh
    lassign [::scidb::tk::wm frame .application] ax ay aw ah
    lassign [winfo workarea .application] sx sy sw sh
    set rx [expr {min($ax+$aw,$sx+$sw)}]
    set ry [expr {min($ay+$ah,$sy+$sh)}]
    set ax [expr {max($ax,$sx)}]; set ay [expr {max($ay,$sy)}]
    set areas {}
    foreach {cx cy} [list [expr {$bx+$bw+12}] $by \
        [expr {$bx-12-$w}] $by $bx [expr {$by+$bh+12}]] {
        set cx [expr {max($ax,min($cx,$rx-$w))}]
        set cy [expr {max($ay,min($cy,$ry-$h))}]
        lappend areas [overlapArea [list $cx $cy $w $h] [boardRect]]
    }
    set minimum [tcl::mathfunc::min {*}$areas]
    set measured [overlapArea $frame [boardRect]]
    puts "W9H native=$frame overlap=$measured minimum=$minimum candidates=$areas"
    require [expr {$measured == $minimum}] "native overlap $measured != minimum $minimum"
}
proc ::scidb::test::dlgplace::pairReady {dialogs} {
    set deadline [expr {[clock milliseconds]+5000}]
    set previous {}
    set stableSince [clock milliseconds]
    while {[clock milliseconds] < $deadline} {
        # A playing video continuously queues events. An unbounded update
        # can stay inside placement callbacks forever and defeat this
        # fixture's five-second deadline. Yield to a timer instead.
        waitFor 1
        set state [list [::scidb::tk::wm frame .application] [boardRect]]
        foreach dialog $dialogs { lappend state [::scidb::tk::wm frame $dialog] }
        set pending $::application::Vars(loading)
        foreach variable {::application::board::Vars(after) ::application::reflow::S(afterId)} {
            if {[info exists $variable] && [set $variable] ne {} && ![catch {after info [set $variable]}]} {set pending 1}
        }
        if {$pending || $state ne $previous} {
            set stableSince [clock milliseconds]
            set previous $state
        } elseif {[clock milliseconds]-$stableSince >= 200} {return}
        waitFor 20
    }
    error {dialog deadline fixture did not settle within 5 seconds}
}

tcltest::test dlg-w9h-native-deadline {Engine Match native minimum and single settled replan by 500ms} -setup {
    ::scidb::test::dlgplace::setupBoard
    catch {wm minsize .application 1 1}
} -constraints haveWmctrl -body {
    ::scidb::test::dlgplace::noRoomState board-only
    ::scidb::test::dlgplace::realVideo
    ::enginematch::open .application
    set dlg .application.enginematch
    ::scidb::test::dlgplace::waitFor 1200
    set decoration $::util::place::BesideState($dlg,extents)
    foreach {trigger script} {
        maximize {wm attributes .application -zoomed 1}
        restore {wm attributes .application -zoomed 0}
        resize {wm geometry .application [::scidb::test::dlgplace::fitGeometry 0.96 0.88]}
    } {
        ::scidb::test::dlgplace::pairReady [list $dlg]
        set seq $::util::place::BesideRecordSeq
        set start [clock milliseconds]
        eval $script
        ::scidb::test::dlgplace::waitFor 500
        set stable [::scidb::tk::wm frame $dlg]
        ::scidb::test::dlgplace::require [expr {
            $decoration eq $::util::place::BesideState($dlg,extents)}] "lost native decoration cache"
        lassign $decoration left right top bottom
        ::scidb::test::dlgplace::require [expr {
            [lindex $stable 2] == [winfo width $dlg]+$left+$right
            && [lindex $stable 3] == [winfo height $dlg]+$top+$bottom}] "cache differs from native frame"
        set records {}
        foreach r [::util::place::besidePlacementLog $seq] {
            if {[dict get $r dialog] eq $dlg && [dict get $r trigger] eq $trigger
                && [dict get $r placed_by] eq "planner"} {lappend records $r}
        }
        ::scidb::test::dlgplace::require [expr {[llength $records] > 0}] "$trigger missing record"
        set elapsed [expr {[dict get [lindex $records 0] time]-$start}]
        ::scidb::test::dlgplace::require [expr {$elapsed <= 500}] "$trigger record at $elapsed ms"
        for {set i 0} {$i < 15} {incr i} {
            ::scidb::test::dlgplace::waitFor 100
            ::scidb::test::dlgplace::require [expr {[::scidb::tk::wm frame $dlg] eq $stable}] "$trigger moved after 500ms"
            ::scidb::test::dlgplace::nativeMinimum $dlg
        }
        puts "W9H $trigger record=$elapsed stable=$stable"
    }
    return 1
} -cleanup {
    catch {::enginematch::Close}
    catch {wm attributes .application -zoomed 0}
    ::scidb::test::dlgplace::realCleanup
} -result 1


# Observer overhead belongs to this test, not the timed production planner.
# Repeated setup must not add synchronous WM queries after every helper call.
tcltest::test dlg-w9i-observer-lifetime {repeated setup installs one copy of each geometry observer} -body {
    ::scidb::test::dlgplace::setupBoard
    ::scidb::test::dlgplace::setupBoard
    set info [trace info execution ::util::place::besideBoard]
    list [llength [lsearch -all -exact $info {enter ::scidb::test::dlgplace::placing}]] \
         [llength [lsearch -all -exact $info {leave ::scidb::test::dlgplace::placed}]]
} -cleanup {
    ::scidb::test::dlgplace::stopTrace
} -result {1 1}

# A queued native unmap can arrive inside the helper's initial idle drain.
# The entry must inspect mapping after that drain, rather than doing arithmetic
# on an obstacle that disappeared between its guard and its first read.
tcltest::test dlg-w9i-unmap-during-plan {helper returns a plan when a pending unmap hides the board} -setup {
    ::scidb::test::dlgplace::setupBoard
    ::playengine::open .application
    ::scidb::test::dlgplace::waitFor 800
} -body {
    after idle {wm withdraw .application}
    set code [catch {::util::place::besideBoard .application.playengine .application} plan]
    puts "W9I unmap code=$code plan=$plan"
    list $code [dict get $plan rule]
} -cleanup {
    wm deiconify .application
    ::scidb::test::dlgplace::waitFor 500
    ::scidb::test::dlgplace::realCleanup
} -result {0 center}

# Start each deadline measurement from a settled fixture. Under host load,
# an elapsed sleep does not establish that the WM/board have consumed their
# queued work. This wait is bounded and precedes the measured user trigger.

# Exercise the reported pair after both dialogs have measured native frames.
tcltest::test dlg-w9i-pair-deadline {both playing dialogs record and settle before 500ms} -setup {
    ::scidb::test::dlgplace::setupBoard
    catch {wm minsize .application 1 1}
} -constraints haveWmctrl -body {
    wm geometry .application [::scidb::test::dlgplace::fitGeometry 1920 1080]
    ::scidb::test::dlgplace::waitFor 900
    ::scidb::test::dlgplace::zoomBoard 1
    ::scidb::test::dlgplace::realVideo
    ::playengine::open .application
    ::scidb::test::dlgplace::waitFor 800
    ::enginematch::open .application
    ::scidb::test::dlgplace::waitFor 900
    set ds {.application.playengine .application.enginematch}
    foreach {trigger script} {
        maximize {wm attributes .application -zoomed 1}
        restore {wm attributes .application -zoomed 0}
        resize {wm geometry .application [::scidb::test::dlgplace::fitGeometry 0.93 0.90]}
    } {
        ::scidb::test::dlgplace::pairReady $ds
        set seq $::util::place::BesideRecordSeq
        set start [clock milliseconds]
        eval $script
        ::scidb::test::dlgplace::waitFor 500
        puts "W9I records $trigger [::util::place::besidePlacementLog $seq]"
        set stable {}
        foreach d $ds {
            dict set stable $d [::scidb::tk::wm frame $d]
            set found 0
            foreach r [::util::place::besidePlacementLog $seq] {
                if {[dict get $r dialog] eq $d && [dict get $r trigger] eq $trigger
                    && [dict get $r placed_by] eq "planner"} {
                    set elapsed [expr {[dict get $r time]-$start}]
                    ::scidb::test::dlgplace::require [expr {$elapsed <= 500}] "$trigger $d first record at $elapsed"
                    puts "W9I $trigger $d first=$elapsed frame=[dict get $stable $d]"
                    set found 1
                    break
                }
            }
            ::scidb::test::dlgplace::require $found "$trigger $d missing record"
        }
        for {set i 0} {$i < 15} {incr i} {
            ::scidb::test::dlgplace::waitFor 100
            foreach d $ds {
                ::scidb::test::dlgplace::require [expr {[::scidb::tk::wm frame $d] eq [dict get $stable $d]}] "$trigger $d moved after 500ms"
                set peer [lindex $ds [expr {$d eq [lindex $ds 0] ? 1 : 0}]]
                ::scidb::test::dlgplace::pairClearOf w9i-$trigger $d $peer [expr {$d ne [lindex $ds 0]}]
            }
        }
    }
    return 1
} -cleanup {
    ::scidb::test::dlgplace::realCleanup
} -result 1

# W9j: use the actual WM frames, including both borders, with no tolerance.
# Keep a measurement transaction alive over a queued resize, as a completed
# board callback can do when a helper's idle drain applies the parent request.
tcltest::test dlg-w9j-native-resize-containment {Game Review and Endgame Trainer stay inside the live main frame} -setup {
    ::scidb::test::dlgplace::setupBoard
    wm minsize .application 1 1
} -constraints haveWmctrl -body {
    wm geometry .application [::scidb::test::dlgplace::fitGeometry 1000 600]
    ::scidb::test::dlgplace::waitFor 900
    ::scidb::test::dlgplace::zoomBoard 0
    ::scidb::test::dlgplace::realVideo
    set review [::gamereview::classify {{san e4 before 0 after 0 best 1} {san e5 before 0 after -250 best 0}}]
    ::gamereview::ShowWindow .application $review {} 0
    ::scidb::test::dlgplace::waitFor 800
    ::endtrainer::open .application
    ::scidb::test::dlgplace::waitFor 900
    set ds {.application.__gamereview .application.__endtrainer__}
    set seq $::util::place::BesideRecordSeq
    set start [clock milliseconds]
    ::util::place::besideMeasureBegin
    try {
        set old [::util::place::besideNativeFrame .application]
        wm geometry .application [::scidb::test::dlgplace::fitGeometry 930 540]
        ::scidb::test::dlgplace::waitFor 500
        set measured [::scidb::tk::wm frame .application]
        set cached [::util::place::besideNativeFrame .application]
        ::scidb::test::dlgplace::require [expr {$cached eq $measured}] "stale native frame: $cached != $measured (before $old)"
    } finally {
        ::util::place::besideMeasureEnd
    }
    set stable {}
    foreach d $ds {
        dict set stable $d [::scidb::tk::wm frame $d]
        set found 0
        foreach r [::util::place::besidePlacementLog $seq] {
            if {[dict get $r dialog] ne $d || [dict get $r trigger] ne "resize"} {continue}
            ::scidb::test::dlgplace::require [::scidb::test::dlgplace::inside [dict get $r rect] $measured] "planned frame outside resized main: $r / $measured"
            if {[dict get $r time]-$start <= 500} {set found 1}
        }
        ::scidb::test::dlgplace::require $found "$d no resize record by 500ms"
    }
    for {set i 0} {$i < 15} {incr i} {
        ::scidb::test::dlgplace::waitFor 100
        set main [::scidb::tk::wm frame .application]
        lassign [winfo workarea .application] wx wy ww wh
        lassign $main mx my mw mh
        set wa [list [expr {max($wx,$mx)}] [expr {max($wy,$my)}] \
            [expr {min($wx+$ww,$mx+$mw)-max($wx,$mx)}] \
            [expr {min($wy+$wh,$my+$mh)-max($wy,$my)}]]
        foreach d $ds {
            set native [::scidb::tk::wm frame $d]
            ::scidb::test::dlgplace::require [::scidb::test::dlgplace::inside $native $wa] "sample $i native $native outside $wa"
            ::scidb::test::dlgplace::require [expr {$native eq [dict get $stable $d]}] "$d moved after 500ms"
            ::scidb::test::dlgplace::requireControls w9j-resize $d
        }
    }
    puts "W9J resize native=$stable workarea=$wa"
    return 1
} -cleanup {
    catch {destroy .application.__gamereview}
    catch {::endtrainer::Close}
    ::scidb::test::dlgplace::realCleanup
} -result 1

tcltest::test dlg-w9j-native-guard-edges {native containment guard corrects a one-pixel escape on every edge} -setup {
    ::scidb::test::dlgplace::setupBoard
    set dlg .application.w9jguard
    toplevel $dlg
    label $dlg.content -text {Native containment guard}
    pack $dlg.content
    lassign [winfo workarea .application] wx wy ww wh
    wm geometry $dlg "[expr {min(240,$ww/3)}]x[expr {min(100,$wh/3)}]+[expr {$wx+$ww/10}]+[expr {$wy+$wh/10}]"
    set ::util::place::BesideState($dlg,parent) .application
    ::scidb::test::dlgplace::waitFor 300
} -constraints haveWmctrl -body {
    set main [::scidb::tk::wm frame .application]
    lassign [winfo workarea .application] wx wy ww wh
    lassign $main mx my mw mh
    set ax [expr {max($wx,$mx)}]; set ay [expr {max($wy,$my)}]
    set right [expr {min($wx+$ww,$mx+$mw)}]; set bottom [expr {min($wy+$wh,$my+$mh)}]
    set wa [list $ax $ay [expr {$right-$ax}] [expr {$bottom-$ay}]]
    set results {}
    foreach side {left top right bottom} {
        lassign [::scidb::tk::wm frame $dlg] x y w h
        set tx [expr {$ax+20}]; set ty [expr {$ay+30}]
        switch $side {
            left {set tx [expr {$ax-1}]}
            top {set ty [expr {$ay-1}]}
            right {set tx [expr {$right-$w+1}]}
            bottom {set ty [expr {$bottom-$h+1}]}
        }
        regexp {^[0-9]+x[0-9]+\+(-?[0-9]+)\+(-?[0-9]+)$} [wm geometry $dlg] -> rx ry
        wm geometry $dlg "+[expr {$rx+$tx-$x}]+[expr {$ry+$ty-$y}]"
        ::scidb::test::dlgplace::waitFor 200
        set before [::scidb::tk::wm frame $dlg]
        ::scidb::test::dlgplace::require [expr {![::scidb::test::dlgplace::inside $before $wa]}] "$side did not escape: $before / $wa"
        set changed [::util::place::besideClampNative $dlg]
        ::scidb::test::dlgplace::waitFor 200
        set after [::scidb::tk::wm frame $dlg]
        puts "W9J guard $side before=$before after=$after workarea=$wa"
        lappend results [expr {$changed && [::scidb::test::dlgplace::inside $after $wa]}]
        unset -nocomplain ::util::place::BesideState($dlg,nativeClamp) ::util::place::BesideState($dlg,nativeClampFrame)
    }
    set results
} -cleanup {
    catch {destroy $dlg}
    array unset ::util::place::BesideState ${dlg},*
    ::scidb::test::dlgplace::realCleanup
} -result {1 1 1 1}

# VAL-DLG-019A: observe the real player and production geometry by the event
# deadline. Stop/hide must release the strip and produce a fresh helper record.
foreach event {close stop hide} {
    tcltest::test dlg-w9d-lifecycle-$event {real playback releases dialog/inset layout within 500 ms} -setup {
        ::scidb::test::dlgplace::setupBoard
        wm minsize .application 1 1
    } -body [string map [list @EVENT@ $event] {
        wm geometry .application [::scidb::test::dlgplace::fitGeometry 1.0 1.0]
        ::scidb::test::dlgplace::waitFor 700
        ::scidb::test::dlgplace::zoomBoard 1
        set normalSquare $::application::board::Dim(squaresize:Normal)
        ::scidb::test::dlgplace::realVideo
        set inset [::scidb::test::dlgplace::widgetRect [::mediainset::Pane].mediainset]
        set before [::scidb::test::dlgplace::reserveState]
        ::enginematch::open .application
        ::scidb::test::dlgplace::waitFor 700
        set during [::scidb::test::dlgplace::reserveState]
        set seq $::util::place::BesideRecordSeq
        set ::scidb::test::dlgplace::calls {}
        set start [clock milliseconds]
        switch @EVENT@ {
            close {destroy .application.enginematch}
            stop {::application::media::Stop}
            hide {::mediainset::hide}
        }
        puts "DLG-019A-EVENT @EVENT@ returnedMs=[expr {[clock milliseconds]-$start}] pending=$::util::place::BesideTimer state=[array get ::util::place::BesideState .application.enginematch,*]"
        ::scidb::test::dlgplace::waitFor [expr {max(1,500-([clock milliseconds]-$start))}]
        set after [::scidb::test::dlgplace::reserveState]
        set records [::util::place::besidePlacementLog $seq]
        puts "DLG-019A @EVENT@ workarea=[winfo workarea .application] before=$before during=$during after=$after elapsed=[expr {[clock milliseconds]-$start}] normalSquare=$normalSquare square=$::application::board::Dim(squaresize:Normal) records=$records"
        if {"@EVENT@" eq "close"} {
            ::scidb::test::dlgplace::require [expr {[::scidb::test::dlgplace::widgetRect [::mediainset::Pane].mediainset] eq $inset}] "inset failed to restore by 500ms"
            ::scidb::test::dlgplace::require [expr {$after eq $before}] "close left a reserve: $before -> $after"
        } else {
            ::scidb::test::dlgplace::require [expr {$::application::board::ReserveKind ne "squeeze" && !$::mediainset::Shown && $::application::board::Dim(squaresize:Normal) == $normalSquare}] "video strip not released/board not regrown"
            ::scidb::test::dlgplace::require [dict exists $::scidb::test::dlgplace::calls .application.enginematch] "stop/hide did not call the placement helper"
            set replanned 0
            foreach r $records {
                if {[dict get $r dialog] eq ".application.enginematch" && [dict get $r time]-$start <= 500} {set replanned 1}
            }
            ::scidb::test::dlgplace::require $replanned "dialog not replanned by 500ms"
        }
        return 1
    }] -cleanup {
        catch {destroy .application.enginematch}
        ::scidb::test::dlgplace::realCleanup
    } -result 1
}

# VAL-DLG-019B: every named pair, both opening and closing orders. The
# original synthetic reserve test remains above to exercise actual stacking.
tcltest::test dlg-w9d-pair-release {all playing pairs restore reserve side, pixels and floor in either close order} -setup {
    ::scidb::test::dlgplace::setupBoard
    wm minsize .application 1 1
} -body {
    wm geometry .application [::scidb::test::dlgplace::fitGeometry 1.0 1.0]
    ::scidb::test::dlgplace::waitFor 700
    ::scidb::test::dlgplace::zoomBoard 1
    ::scidb::test::dlgplace::realVideo
    set dialogs [dict create playengine .application.playengine enginematch .application.enginematch guessmove .application.__guessmove__ reptrainer .application.__reptrainer__ gamereview .application.__gamereview endtrainer .application.__endtrainer__]
    foreach pair {{playengine enginematch} {guessmove reptrainer} {gamereview endtrainer}} {
        foreach opening [list $pair [lreverse $pair]] {
            foreach closing [list $pair [lreverse $pair]] {
                set before [::scidb::test::dlgplace::reserveState]
                foreach short $opening {
                    switch $short {
                        playengine {::playengine::open .application}
                        enginematch {::enginematch::open .application}
                        guessmove {::guessmove::start white}
                        reptrainer {::reptrainer::open .application}
                        gamereview {
                            set review [::gamereview::classify {{san e4 before 0 after 0 best 1} {san e5 before 0 after -250 best 0}}]
                            ::gamereview::ShowWindow .application $review {} 0
                        }
                        endtrainer {::endtrainer::open .application}
                    }
                    ::scidb::test::dlgplace::waitFor 600
                }
                set during [::scidb::test::dlgplace::reserveState]
                foreach short $closing {
                    switch $short {
                        playengine {::playengine::Close}
                        enginematch {::enginematch::Close}
                        guessmove {::guessmove::stop}
                        reptrainer {::reptrainer::Close .application.__reptrainer__}
                        endtrainer {::endtrainer::Close}
                    }
                    catch {destroy [dict get $dialogs $short]}
                    ::scidb::test::dlgplace::waitFor 500
                }
                set after [::scidb::test::dlgplace::reserveState]
                puts "DLG-019B workarea=[winfo workarea .application] opening=$opening closing=$closing before=$before during=$during after=$after"
                ::scidb::test::dlgplace::require [expr {$before eq $after}] "reserve leak: $before -> $after"
            }
        }
    }
    return 1
} -cleanup {
    catch {::guessmove::stop}
    catch {::reptrainer::Close .application.__reptrainer__}
    ::scidb::test::dlgplace::realCleanup
} -result 1

# VAL-DLG-021: the terminal-review 800x600 app repro, requested-size
# dialogs, both opening/closing orders, with actual native-frame oracles.
# The runner supplies a fresh HOME/Openbox per repetition and app size.
# The 800x600 *client* fixture needs room for its native decorations.
# Smaller displays are covered by the existing no-room fallback tests.
lassign [winfo workarea .application] _ _ v21w v21h
lassign [::scidb::test::dlgplace::outerRect .application] _ _ v21mw v21mh
tcltest::testConstraint dlg021FullApp [expr {
    $v21w >= 800+$v21mw-[winfo width .application]
    && $v21h >= 600+$v21mh-[winfo height .application]}]
tcltest::test dlg-v21-reserve-before-overlap {playing dialogs reserve down to square32 before no-room; exact close restoration} -constraints dlg021FullApp -setup {
    ::scidb::test::dlgplace::setupBoard
    wm minsize .application 1 1
} -body {
    set size {800 600}
    if {[info exists ::env(DLG021_SIZE)]} { set size [split $::env(DLG021_SIZE) x] }
    wm geometry .application [::scidb::test::dlgplace::fitGeometry {*}$size]
    ::scidb::test::dlgplace::waitFor 1000
    set windows [dict create playengine .application.playengine gamereview .application.__gamereview enginematch .application.enginematch]
    # Real libmpv is loaded and advancing; include the ordinary no-video
    # reproduction as well as placement while playback owns a strip.
    foreach media {0 1} {
        if {$media} {::scidb::test::dlgplace::realVideo}
        foreach opening {{playengine gamereview} {gamereview playengine} {enginematch}} {
            foreach reverse {0 1} {
                set before [::scidb::test::dlgplace::reserveState]
                set boardBefore [::scidb::test::dlgplace::boardRect]
                set squareBefore $::application::board::Dim(squaresize:Normal)
                foreach short $opening {
                    switch $short {
                        playengine {::playengine::open .application}
                        enginematch {::enginematch::open .application}
                        gamereview {
                            set review [::gamereview::classify {{san e4 before 0 after 0 best 1} {san e5 before 0 after -250 best 0}}]
                            ::gamereview::ShowWindow .application $review {} 0
                        }
                    }
                    ::scidb::test::dlgplace::waitFor 650
                }
                set frames {}
                lassign [winfo workarea .application] wx wy ww wh
                lassign [::scidb::test::dlgplace::outerRect .application] mx my mw mh
                set ax [expr {max($wx,$mx)}]; set ay [expr {max($wy,$my)}]
                set wa [list $ax $ay [expr {min($wx+$ww,$mx+$mw)-$ax}] [expr {min($wy+$wh,$my+$mh)-$ay}]]
                set board [::scidb::test::dlgplace::boardRect]
                foreach short $opening {
                    set dlg [dict get $windows $short]
                    set outer [::scidb::test::dlgplace::outerRect $dlg]
                    set overlap [::scidb::test::dlgplace::overlapArea $outer $board]
                    puts "DLG021 size=$size media=$media opening=$opening reverse=$reverse dialog=$short frame=$outer board=$board overlap=$overlap square=$::application::board::Dim(squaresize:Normal) reserve=[::scidb::test::dlgplace::reserveState]"
                    if {$overlap && [llength $opening] == 1} {
                        # A single requested frame may be wider than the
                        # floor32 painted board leaves. Independently probe
                        # all accepted strips before allowing the fallback.
                        set frame $::application::board::Vars(widget:frame)
                        lassign $outer _ _ dw dh
                        lassign $wa ax ay aw ah
                        set feasible 0
                        foreach side {right left bottom} {
                            set extent [expr {$side eq "bottom" ? [winfo height $frame] : [winfo width $frame]}]
                            for {set px 1} {$px < $extent} {incr px} {
                                set sq [::application::board::reserveSquare $side $px [winfo width $frame] [winfo height $frame] dialog]
                                if {$sq < 32} {continue}
                                lassign [::application::board::reserveBorder $side $px dialog 0 1] x y bw bh
                                incr x [winfo rootx $frame]; incr y [winfo rooty $frame]
                                if {$dw <= $aw && $dh <= $ah
                                    && ($x-$ax >= $dw || $ax+$aw-$x-$bw >= $dw
                                        || $y-$ay >= $dh || $ay+$ah-$y-$bh >= $dh)} {set feasible 1; break}
                            }
                        }
                        puts "DLG021 FALLBACK dialog=$short exhaustiveFloor32Feasible=$feasible"
                        ::scidb::test::dlgplace::require [expr {!$feasible}] "$short overlaps despite a feasible floor32 reserve"
                    } else {
                        ::scidb::test::dlgplace::require [expr {$overlap == 0}] "$short covers board by $overlap"
                    }
                    ::scidb::test::dlgplace::require [::scidb::test::dlgplace::inside $outer $wa] "$short frame outside $wa"
                    ::scidb::test::dlgplace::requireControls $short $dlg
                    # Inspect all leaf controls, including unmapped ones.
                    set pending [winfo children $dlg]
                    while {[llength $pending]} {
                        set w [lindex $pending 0]; set pending [lrange $pending 1 end]
                        if {[winfo toplevel $w] ne $dlg} {continue}
                        lappend pending {*}[winfo children $w]
                        if {[winfo class $w] in {Button TButton Checkbutton TCheckbutton Radiobutton TRadiobutton Entry TEntry TCombobox Spinbox TSpinbox}} {
                            # Playing/stopped mode panels deliberately forget
                            # inactive controls (e.g. Resign before a game).
                            set active 1
                            for {set a $w} {$a ne $dlg} {set a [winfo parent $a]} {
                                if {[winfo manager $a] eq ""} {set active 0; break}
                            }
                            if {!$active} {continue}
                            if {[winfo exists $dlg.__viewport]} {focus -force $w; update}
                            ::scidb::test::dlgplace::require [winfo ismapped $w] "unmapped $w"
                            ::scidb::test::dlgplace::require [::scidb::test::dlgplace::inside [::scidb::test::dlgplace::widgetRect $w] [::scidb::test::dlgplace::widgetRect $dlg]] "clipped $w"
                        }
                    }
                    foreach peer $frames {
                        ::scidb::test::dlgplace::require [expr {![::scidb::test::dlgplace::overlapArea $outer $peer]}] "dialogs overlap"
                    }
                    lappend frames $outer
                }
                if {$media} {
                    set canvas $::application::board::Vars(widget:frame)
                    set pane [::mediainset::Pane]
                    set minW [::mediainset::MinimumStrip]
                    set minH [expr {int(round(($minW-8)/$::mediainset::Aspect)) + [winfo reqheight $pane.mediainset.controls] + 8}]
                    set videoSquare [expr {max(
                        [::application::board::reserveSquare right $minW [winfo width $canvas] [winfo height $canvas]],
                        [::application::board::reserveSquare bottom $minH [winfo width $canvas] [winfo height $canvas]])}]
                    set videoRect [::scidb::test::dlgplace::widgetRect $pane.mediainset]
                    set videoOverlap [::scidb::test::dlgplace::overlapArea $videoRect $board]
                    puts "DLG021 MEDIA size=$size opening=$opening rect=$videoRect board=$board overlap=$videoOverlap feasibleSquare=$videoSquare"
                    ::scidb::test::dlgplace::require [expr {$videoSquare < 32 || $videoOverlap == 0}] "dialog reserve regressed MED-013: video overlaps board despite floor32 strip"
                }
                if {[info exists ::env(DLG021_EVIDENCE)]} {
                    exec import -window root [file join $::env(DLG021_EVIDENCE) "media${media}-[join $opening -]-${reverse}.png"]
                }
                set closing [expr {$reverse ? [lreverse $opening] : $opening}]
                foreach short $closing {
                    switch $short {
                        playengine {::playengine::Close}
                        enginematch {::enginematch::Close}
                    }
                    catch {destroy [dict get $windows $short]}
                    ::scidb::test::dlgplace::waitFor 650
                }
                puts "DLG021 RESTORE size=$size media=$media closing=$closing before=$before after=[::scidb::test::dlgplace::reserveState] boardBefore=$boardBefore boardAfter=[::scidb::test::dlgplace::boardRect]"
                ::scidb::test::dlgplace::require [expr {$before eq [::scidb::test::dlgplace::reserveState]}] "reserve not restored exactly"
                ::scidb::test::dlgplace::require [expr {$boardBefore eq [::scidb::test::dlgplace::boardRect] && $squareBefore == $::application::board::Dim(squaresize:Normal)}] "board not restored exactly"
            }
        }
        if {$media} {::application::media::Stop}
        ::scidb::test::dlgplace::waitFor 650
    }
    return 1
} -cleanup {
    catch {destroy .application.__gamereview}
    ::scidb::test::dlgplace::realCleanup
} -result 1

# Starting playback after a requested-size group, then zooming its pane,
# must not retain the old below-floor video dodge over a newly feasible board.
tcltest::test dlg-v21-video-after-reserve-zoom {video recovers its strip when a dialog group no longer fits after board zoom} -constraints dlg021FullApp -setup {
    ::scidb::test::dlgplace::setupBoard
    wm minsize .application 1 1
} -body {
    wm geometry .application [::scidb::test::dlgplace::fitGeometry 800 600]
    ::scidb::test::dlgplace::waitFor 900
    set before [::scidb::test::dlgplace::boardRect]
    set reserveBefore [::scidb::test::dlgplace::reserveState]
    ::playengine::open .application
    ::scidb::test::dlgplace::waitFor 650
    set review [::gamereview::classify {{san e4 before 0 after 0 best 1} {san e5 before 0 after -250 best 0}}]
    ::gamereview::ShowWindow .application $review {} 0
    ::scidb::test::dlgplace::waitFor 650
    ::scidb::test::dlgplace::realVideo
    ::scidb::test::dlgplace::zoomBoard 1
    ::scidb::test::dlgplace::waitFor 700
    set pane [::mediainset::Pane]
    set video [::scidb::test::dlgplace::widgetRect $pane.mediainset]
    set board [::scidb::test::dlgplace::boardRect]
    set overlap [::scidb::test::dlgplace::overlapArea $video $board]
    puts "DLG021-ZOOM video=$video board=$board overlap=$overlap reserve=[::scidb::test::dlgplace::reserveState]"
    ::scidb::test::dlgplace::require [expr {$overlap == 0 && $::application::board::ReservePixels > 0 && $::application::board::Dim(squaresize:Normal) >= 32}] "stale dialog dodge covered the board despite a feasible video reserve"
    ::playengine::Close
    destroy .application.__gamereview
    ::application::media::Stop
    ::scidb::test::dlgplace::zoomBoard 0
    ::scidb::test::dlgplace::waitFor 700
    ::scidb::test::dlgplace::require [expr {$before eq [::scidb::test::dlgplace::boardRect] && $reserveBefore eq [::scidb::test::dlgplace::reserveState]}] "post-video-start zoom did not restore exactly"
    return 1
} -cleanup {
    catch {destroy .application.__gamereview}
    ::scidb::test::dlgplace::realCleanup
} -result 1


# VAL-DLG-022: native clipping, actual keyboard focus, and independent board
# intersections. Real video continues advancing even when only its handle fits.
tcltest::test dlg-v22-small-scroll {compact only after reserve exhaustion; all active controls reachable} -setup {
    ::scidb::test::dlgplace::setupBoard
    wm minsize .application 1 1
} -body {
    set size 800x600
    if {[info exists ::env(DLG022_SIZE)]} {set size $::env(DLG022_SIZE)}
    wm geometry .application [::scidb::test::dlgplace::fitGeometry {*}[split $size x]]
    ::scidb::test::dlgplace::waitFor 1000
    foreach scenario {{0 playengine enginematch} {0 enginematch} {1 playengine gamereview} {1 gamereview playengine}} {
        lassign $scenario video
        set opening [lrange $scenario 1 end]
        set before [::scidb::test::dlgplace::boardRect]
        if {$video} {::scidb::test::dlgplace::realVideo}
        set dialogs {}
        foreach kind $opening {
            switch $kind {
                playengine {::playengine::open .application; set dlg .application.playengine}
                enginematch {::enginematch::open .application; set dlg .application.enginematch}
                gamereview {
                    ::gamereview::ShowWindow .application [::gamereview::classify {{san e4 before 0 after 0 best 1}}] {} 0
                    set dlg .application.__gamereview
                }
            }
            lappend dialogs $dlg
            ::scidb::test::dlgplace::waitFor 900
        }
        set board [::scidb::test::dlgplace::boardRect]
        set frames {}
        foreach dlg $dialogs {
            set frame [::scidb::test::dlgplace::outerRect $dlg]
            puts "DLG022 size=$size scenario=$scenario dlg=$dlg frame=$frame board=$board plan=$::util::place::BesideLastPlan($dlg)"
            ::scidb::test::dlgplace::require [expr {![::scidb::test::dlgplace::overlapArea $frame $board]}] "dialog covers board"
            ::scidb::test::dlgplace::require [::scidb::test::dlgplace::inside $frame [::scidb::test::dlgplace::windowWorkArea]] "native frame outside main"
            foreach peer $frames {::scidb::test::dlgplace::require [expr {![::scidb::test::dlgplace::overlapArea $frame $peer]}] "peer overlap"}
            lappend frames $frame
            set body [::util::place::playingBody $dlg]
            set c [winfo parent $body]
            set compact [expr {[winfo width $dlg] < [winfo reqwidth $body] || [winfo height $dlg] < [winfo reqheight $body]}]
            if {$size in {1280x720 1920x1080}} {::scidb::test::dlgplace::require [expr {!$compact}] "unnecessary compaction"}
            ::scidb::test::dlgplace::require [expr {[winfo width $dlg]>=min(240,[winfo reqwidth $body]) && [winfo height $dlg]>=min(180,[winfo reqheight $body])}] "below usable minimum"
            lassign [wm minsize $dlg] minw minh
            ::scidb::test::dlgplace::require [expr {$minw>=min(240,[winfo reqwidth $body]) && $minh>=min(180,[winfo reqheight $body])}] "native resize minimum not enforced"
            set count 0
            foreach w [::scidb::test::dlgplace::controls $body] {
                ::scidb::test::dlgplace::requireReachable $w $c
                puts "DLG022 CONTROL class=[winfo class $w] path=$w"
                incr count
            }
            puts "DLG022 REACHABLE $dlg controls=$count compact=$compact"
            ::scidb::test::dlgplace::require [expr {$count>0}] "no controls checked"
        }
        if {$video} {
            set pane [::mediainset::Pane]
            set vr [::scidb::test::dlgplace::widgetRect $pane.mediainset]
            ::scidb::test::dlgplace::require [expr {![::scidb::test::dlgplace::overlapArea $vr $board]}] "native video covers board"
            if {$::mediainset::Collapsed} {
                ::scidb::test::dlgplace::require [winfo ismapped .application.videoHandle] "collapsed handle missing"
                set vr [::scidb::test::dlgplace::widgetRect .application.videoHandle]
            }
            puts "DLG022 VIDEO rect=$vr collapsed=$::mediainset::Collapsed"
            ::scidb::test::dlgplace::require [expr {![::scidb::test::dlgplace::overlapArea $vr $board]}] "video covers board"
            set pos [::media::mpv::time]
            ::scidb::test::dlgplace::waitFor 350
            ::scidb::test::dlgplace::require [expr {[::media::mpv::time]>$pos}] "playback stopped"
        }
        if {[info exists ::env(DLG022_EVIDENCE)]} {exec import -window root [file join $::env(DLG022_EVIDENCE) [join $scenario -].png]}
        foreach dlg [lreverse $dialogs] {catch {destroy $dlg}; ::scidb::test::dlgplace::waitFor 700}
        if {$video} {
            ::scidb::test::dlgplace::require [expr {!$::mediainset::Collapsed}] "video did not restore on dialog close"
            ::application::media::Stop
            ::scidb::test::dlgplace::waitFor 700
        }
        ::scidb::test::dlgplace::require [expr {$before eq [::scidb::test::dlgplace::boardRect]}] "board not restored"
    }
    return 1
} -cleanup {
    ::scidb::test::dlgplace::realCleanup
} -result 1

tcltest::test dlg-v22-return-space {compact viewport restores natural size and Tab reveals controls after resize} -setup {
    ::scidb::test::dlgplace::setupBoard
    wm minsize .application 1 1
} -body {
    wm geometry .application [::scidb::test::dlgplace::fitGeometry 800 600]
    ::scidb::test::dlgplace::waitFor 700
    ::enginematch::open .application
    ::scidb::test::dlgplace::waitFor 700
    set dlg .application.enginematch
    set body [::util::place::playingBody $dlg]
    set c [winfo parent $body]
    ::scidb::test::dlgplace::require [expr {[winfo width $dlg]<[winfo reqwidth $body]}] "fixture did not compact"
    focus -force $body.ok
    update
    for {set i 0} {$i < 25} {incr i} {
        event generate [focus] <KeyPress-Tab>
        update
        set w [focus]
        if {[string match $body.* $w]} {
            ::scidb::test::dlgplace::require [::scidb::test::dlgplace::inside [::scidb::test::dlgplace::widgetRect $w] [::scidb::test::dlgplace::widgetRect $c]] "Tab did not reveal $w"
        }
    }
    wm geometry .application [::scidb::test::dlgplace::fitGeometry 1280 720]
    ::scidb::test::dlgplace::waitFor 1000
    puts "DLG022 RETURN dialog=[wm geometry $dlg] body=[winfo reqwidth $body]x[winfo reqheight $body] bars=[winfo ismapped $dlg.__viewport.x]/[winfo ismapped $dlg.__viewport.y]"
    ::scidb::test::dlgplace::require [expr {[winfo width $dlg]>=[winfo reqwidth $body] && [winfo height $dlg]>=[winfo reqheight $body]}] "natural size not restored"
    ::scidb::test::dlgplace::require [expr {![winfo ismapped $dlg.__viewport.x] && ![winfo ismapped $dlg.__viewport.y]}] "scrollbars retained"
    ::enginematch::Close
    return 1
} -cleanup {
    ::scidb::test::dlgplace::realCleanup
} -result 1

tcltest::test dlg-v22-trainers {trainers use the native scrolling body} -setup {
    ::scidb::test::dlgplace::setupBoard
    wm minsize .application 1 1
} -body {
    wm geometry .application [::scidb::test::dlgplace::fitGeometry 800 600]
    ::scidb::test::dlgplace::waitFor 700
    foreach {open dlg close} {
        {::tactics::open .application} .tactics {::tactics::close}
        {::endtrainer::open .application} .application.__endtrainer__ {::endtrainer::Close}
        {::reptrainer::open .application} .application.__reptrainer__ {::reptrainer::Close .application.__reptrainer__}
        {::guessmove::start white} .application.__guessmove__ {::guessmove::stop; catch {destroy .application.__guessmove__}}
    } {
        eval $open
        ::scidb::test::dlgplace::waitFor 700
        ::scidb::test::dlgplace::require [winfo exists $dlg.__viewport.canvas.body] "missing trainer wrapper $dlg"
        set board [::scidb::test::dlgplace::boardRect]
        set frame [::scidb::test::dlgplace::outerRect $dlg]
        puts "DLG022 TRAINER dialog=$dlg frame=$frame board=$board"
        ::scidb::test::dlgplace::require [expr {![::scidb::test::dlgplace::overlapArea $frame $board]}] "trainer covers board"
        foreach w [::scidb::test::dlgplace::controls $dlg.__viewport.canvas.body] {
            ::scidb::test::dlgplace::requireReachable $w $dlg.__viewport.canvas
        }
        eval $close
        ::scidb::test::dlgplace::waitFor 700
    }
    return 1
} -cleanup {
    catch {::tactics::close}
    catch {::endtrainer::Close}
    catch {::reptrainer::Close .application.__reptrainer__}
    catch {::guessmove::stop}
    catch {destroy .application.__guessmove__}
    ::scidb::test::dlgplace::realCleanup
} -result 1

tcltest::test dlg-v22-minimum-fallback {infeasible minimum uses overlap fallback; default button remains keyboard reachable} -setup {
    ::scidb::test::dlgplace::setupBoard
    wm minsize .application 1 1
} -body {
    wm geometry .application [::scidb::test::dlgplace::fitGeometry 400 380]
    ::scidb::test::dlgplace::waitFor 700
    ::enginematch::open .application
    ::scidb::test::dlgplace::waitFor 700
    set dlg .application.enginematch
    set plan $::util::place::BesideLastPlan($dlg)
    set frame [::scidb::test::dlgplace::outerRect $dlg]
    set board [::scidb::test::dlgplace::boardRect]
    puts "DLG022 MINIMUM frame=$frame board=$board plan=$plan"
    ::scidb::test::dlgplace::require [expr {[dict get $plan rule] eq "no-room" && [winfo width $dlg]>=240 && [winfo height $dlg]>=180}] "unusable fallback"
    lassign [::scidb::test::dlgplace::windowWorkArea] wx wy ww wh
    lassign $board bx by bw bh
    lassign $frame _ _ fw fh
    set areas {}
    foreach {x y} [list [expr {$bx+$bw+12}] $by [expr {$bx-12-$fw}] $by $bx [expr {$by+$bh+12}]] {
        set x [expr {max($wx,min($x,$wx+$ww-$fw))}]
        set y [expr {max($wy,min($y,$wy+$wh-$fh))}]
        lappend areas [::scidb::test::dlgplace::overlapArea [list $x $y $fw $fh] $board]
    }
    ::scidb::test::dlgplace::require [expr {[::scidb::test::dlgplace::overlapArea $frame $board] == [tcl::mathfunc::min {*}$areas]}] "fallback did not minimise overlap"
    set body [::util::place::playingBody $dlg]
    set ::scidb::test::dlgplace::defaultInvoked 0
    $body.ok configure -command {set ::scidb::test::dlgplace::defaultInvoked 1}
    focus -force $body.top.setup.mode.match
    update
    event generate [focus] <KeyPress-Return>
    update
    ::scidb::test::dlgplace::require $::scidb::test::dlgplace::defaultInvoked "Return default binding lost"
    ::scidb::test::dlgplace::require [::scidb::test::dlgplace::inside [::scidb::test::dlgplace::widgetRect $body.ok] [::scidb::test::dlgplace::widgetRect $dlg.__viewport.canvas]] "default button not revealed"
    ::enginematch::Close
    return 1
} -cleanup {
    ::scidb::test::dlgplace::realCleanup
} -result 1

# Exercise the full native interactive class inventory, including classes not
# currently present in the playing dialogs. No geometry or focus stubs.
tcltest::test dlg-v22-interactive-classes {all interactive widget classes reveal and scroll without snapping back} -body {
    set dlg .playingViewportProbe
    toplevel $dlg
    set body [::util::place::playingBody $dlg]
    set c [winfo parent $body]
    set constructors {
        {button} {ttk::button} {checkbutton} {ttk::checkbutton}
        {radiobutton} {ttk::radiobutton} {entry} {ttk::entry}
        {ttk::combobox} {spinbox -from 0 -to 10} {ttk::spinbox -from 0 -to 10}
        {scale} {ttk::scale} {listbox -width 80 -height 20}
        {scrollbar} {ttk::scrollbar} {text -width 80 -height 20}
        {ttk::treeview -height 20} {menubutton} {ttk::menubutton}
        {canvas -width 650 -height 400 -takefocus 1}
        {ttk::notebook} {panedwindow} {ttk::panedwindow}
    }
    set row 0
    foreach constructor $constructors {
        set w $body.w$row
        {*}[lrange $constructor 0 0] $w {*}[lrange $constructor 1 end]
        if {[winfo class $w] in {TNotebook Panedwindow TPanedwindow}} {
            ttk::frame $w.pane -width 160 -height 60
            if {[winfo class $w] eq "TNotebook"} {
                $w add $w.pane -text Tab
            } else {
                $w add $w.pane
            }
        }
        grid $w -row $row -column 0 -sticky w
        incr row
    }
    wm geometry $dlg 300x220+0+0
    ::scidb::test::dlgplace::waitFor 300
    set controls [::scidb::test::dlgplace::controls $body]
    ::scidb::test::dlgplace::require [expr {[llength $controls] == [llength $constructors]}] "interactive inventory incomplete"
    foreach w $controls {
        ::scidb::test::dlgplace::requireReachable $w $c
        # A body Configure must preserve the user's view even with focus held.
        $c xview moveto 1
        $c yview moveto 1
        update
        set views [list [$c xview] [$c yview]]
        event generate $body <Configure>
        ::scidb::test::dlgplace::waitFor 80
        ::scidb::test::dlgplace::require [expr {$views eq [list [$c xview] [$c yview]]}] "Configure overrode explicit scroll for [winfo class $w]"
        puts "DLG022 CLASS [winfo class $w] scroll-preserved=$views"
    }
    return 1
} -cleanup {
    catch {destroy .playingViewportProbe}
} -result 1

tcltest::test dlg-v22-review-native-left {listbox and its scrollbar remain operable in compacted video/review pair} -setup {
 ::scidb::test::dlgplace::setupBoard
 wm minsize .application 1 1
 wm geometry .application [::scidb::test::dlgplace::fitGeometry 800 600]
 ::scidb::test::dlgplace::waitFor 700
} -body {
 ::scidb::test::dlgplace::realVideo
 ::playengine::open .application
 ::scidb::test::dlgplace::waitFor 700
 ::gamereview::ShowWindow .application [::gamereview::classify {{san e4 before 0 after -250 best 0} {san e5 before 0 after -300 best 0}}] {} 0
 ::scidb::test::dlgplace::waitFor 700
 set dlg .application.__gamereview
 set c $dlg.__viewport.canvas
 set lb $c.body.top.list.list
 focus -force $lb
 update
 exec xdotool key Home
 ::scidb::test::dlgplace::waitFor 100
 puts "REVIEW_LIST focus=[focus] selection=[$lb curselection] items=[$lb size] rect=[::scidb::test::dlgplace::widgetRect $lb] viewport=[::scidb::test::dlgplace::widgetRect $c]"
 ::scidb::test::dlgplace::require [expr {[focus] eq $lb && [$lb curselection] eq "0"}] "review listbox inaccessible to keyboard"
 ::scidb::test::dlgplace::waitFor 1000

 set bar $dlg.__viewport.x
 set before [$c xview]
 exec xdotool mousemove [expr {[winfo rootx $bar]+5}] [expr {[winfo rooty $bar]+[winfo height $bar]/2}] click --repeat 10 --delay 30 1
 ::scidb::test::dlgplace::waitFor 500
 lassign [::scidb::test::dlgplace::widgetRect $lb] x y w h
 lassign [::scidb::test::dlgplace::widgetRect $c] u v a d
 set leftVisible [expr {$x >= $u && $x < $u+$a && [focus] eq $lb}]
 puts "REVIEW_NATIVE_LEFT visible=$leftVisible focus=[focus] before=$before after=[$c xview] list=[::scidb::test::dlgplace::widgetRect $lb] viewport=[::scidb::test::dlgplace::widgetRect $c] bar=[::scidb::test::dlgplace::widgetRect $bar]"
 if {[info exists ::env(DLG022_EVIDENCE)]} {exec import -window root [file join $::env(DLG022_EVIDENCE) review-native-left.png]}
 ::scidb::test::dlgplace::require $leftVisible "native scrollbar cannot expose focused listbox left edge"
 set sb $c.body.top.list.vs
 focus -force $sb
 update
 ::scidb::test::dlgplace::require [::scidb::test::dlgplace::inside [::scidb::test::dlgplace::widgetRect $sb] [::scidb::test::dlgplace::widgetRect $c]] "review list scrollbar unreachable"
 if {[info exists ::env(DLG022_EVIDENCE)]} {exec import -window root [file join $::env(DLG022_EVIDENCE) review-list.png]}
 destroy $dlg
 ::playengine::Close
 ::application::media::Stop
 return 1
} -cleanup {::scidb::test::dlgplace::realCleanup} -result 1


tcltest::cleanupTests
