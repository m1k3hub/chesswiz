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
    lassign [winfo extents .application] el er et eb
    set outer [list [expr {[winfo rootx .application]-$el}] \
        [expr {[winfo rooty .application]-$et}] \
        [expr {[winfo width .application]+$el+$er}] \
        [expr {[winfo height .application]+$et+$eb}]]
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
    dict set calls $dlg [dict create plan $result workareaCalls $workareaCalls board [boardRect] \
        workarea [winfo workarea $dlg] extents [winfo extents $dlg]]
}
proc ::scidb::test::dlgplace::workareaTrace {command op} {
    variable workareaCalls
    variable placing
    if {$placing && [lindex $command 1] eq "workarea"} {incr workareaCalls}
}
proc ::scidb::test::dlgplace::setupBoard {} {
    variable calls
    variable workareaCalls
    ::application::switchTab board
    wm state .application normal
    wm geometry .application "[winfo screenwidth .]x[winfo screenheight .]+0+0"
    waitFor 1200
    ::scidb::game::clear {rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1}
    foreach san {e4 e5 Nf3 Nc6} {::move::addMove menu $san}
    ::scidb::game::go -1 start
    waitFor 300
    set calls {}
    set workareaCalls 0
    trace add execution ::util::place::besideBoard enter ::scidb::test::dlgplace::placing
    trace add execution ::util::place::besideBoard leave ::scidb::test::dlgplace::placed
    trace add execution ::winfo enter ::scidb::test::dlgplace::workareaTrace
}
proc ::scidb::test::dlgplace::stopTrace {} {
    trace remove execution ::util::place::besideBoard enter ::scidb::test::dlgplace::placing
    trace remove execution ::util::place::besideBoard leave ::scidb::test::dlgplace::placed
    trace remove execution ::winfo enter ::scidb::test::dlgplace::workareaTrace
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
        if {[winfo ismapped $child]
            && [winfo class $child] in {Button TButton Checkbutton TCheckbutton Radiobutton TRadiobutton Entry TEntry TCombobox Spinbox TSpinbox Scale TScale Listbox TListbox}} {
            lappend result $child
        }
        lappend result {*}[controls $child]
    }
    return $result
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
    require [expr {[dict get $call workareaCalls] > 0}] "$target: no winfo workarea call from helper"
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
    if {$rule in {shrink no-room}} {
        require [expr {$w >= 1 && $h >= 1}] "$target: degenerate ${w}x${h}"
    } else {
        require [expr {$w >= [lindex $requested 0] && $h >= [lindex $requested 1]}] \
            "$target: final ${w}x${h} clips requested $requested"
    }
    lassign $ext el er et eb
    set outer [list $x $y [expr {$w+$el+$er}] [expr {$h+$et+$eb}]]
    require [inside $outer $wa] "$target: outer frame $outer outside $wa"
    set area [overlapArea $outer $board]
    # Independent candidate oracle, evaluated at FINAL dimensions, including frame.
    lassign $board bx by bw bh
    lassign $wa wx wy ww wh
    set fw [expr {$w+$el+$er}]
    set fh [expr {$h+$et+$eb}]
    set areas {}
    foreach {side cx cy} [list right [expr {$bx+$bw+12}] $by left [expr {$bx-12-$fw}] $by below $bx [expr {$by+$bh+12}]] {
        set cx [expr {max($wx,min($cx,$wx+$ww-$fw))}]
        set cy [expr {max($wy,min($cy,$wy+$wh-$fh))}]
        dict set areas $side [overlapArea [list $cx $cy $fw $fh] $board]
    }
    if {$rule ne "shrink"} {
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
        require [expr {[$dlg.top.status cget -text] ne ""}] "review did not populate its status"
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

tcltest::test dlg-tactics {trainer with its own board stays centred and does not use besideBoard} -setup {
    ::scidb::test::dlgplace::setupBoard
} -body {
    ::tactics::open .application
    ::scidb::test::dlgplace::waitFor 500
    ::scidb::test::dlgplace::require [expr {[winfo width .tactics] >= [winfo reqwidth .tactics]
        && [winfo height .tactics] >= [winfo reqheight .tactics]}] "tactics clips its requested size"
    lassign [::util::place::geometry .tactics -parent .application -position center] x y w h
    puts "DLG tactics final=[wm geometry .tactics] centered-offsets=${x}${y} own-board=[winfo ismapped .tactics.board]"
    list [expr {![dict exists $::scidb::test::dlgplace::calls .tactics]}] \
        [string match "*${x}${y}" [wm geometry .tactics]] [winfo ismapped .tactics.board]
} -cleanup {
    ::tactics::close
    ::scidb::test::dlgplace::stopTrace
} -result {1 1 1}

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
    set area [dialogOverlap $dlg]
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
    set delta [replaceDelta {wm geometry .application +180+120; followSettled $dlg $boardBefore}]
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
    waitFor 200
}

foreach {target openScript dialog closeScript} {
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
tcltest::test dlg-follow-user-move {user-moved dialog is respected until it covers the board} -setup {
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

    # Now drag it onto the board; it must be re-planned off the board.
    lassign [::scidb::test::dlgplace::boardRect] bx by bw bh
    wm geometry $dlg "+[expr {$bx+20}]+[expr {$by+20}]"
    ::scidb::test::dlgplace::waitFor 1200
    ::scidb::test::dlgplace::require [expr {[::scidb::test::dlgplace::dialogOverlap $dlg] == 0}] \
        "dialog covering the board was not re-placed"
    return 1
} -cleanup {
    catch {::playengine::Close}
    catch {destroy .application.playengine}
    catch {wm attributes .application -fullscreen 0}
    ::util::place::besideResetReplaceCount
    set ::application::Vars(loading) 0
} -result 1

# Exercise real widgets with only OS work-area/frame reports substituted.
proc ::scidb::test::dlgplace::areaSetup {} {
 update
 waitFor 200
 ::application::switchTab board
 ::application::reflow::reset
 set ::application::reflow::S(override) {}
 wm geometry .application 800x900+10+10
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
proc ::scidb::test::dlgplace::outerRect {dlg} {
 lassign [widgetRect $dlg] x y w h
 lassign [winfo extents $dlg] l r t b
 list [expr {$x-$l}] [expr {$y-$t}] [expr {$w+$l+$r}] [expr {$h+$t+$b}]
}
tcltest::test dlg-display-workarea {watcher repositions on area-only change and preserves safe user placement} -setup {
 set dlg [::scidb::test::dlgplace::areaSetup]
 set board [::util::place::besideBoardRect]
 rename ::util::place::getWmWorkArea ::scidb::test::dlgplace::realArea
 proc ::util::place::getWmWorkArea {w} {return $::scidb::test::dlgplace::area}
 set ::scidb::test::dlgplace::area {0 0 1200 1080}
} -body {
 ::util::place::besideResetReplaceCount
 ::application::displayWatch
 ::scidb::test::dlgplace::waitFor 1500
 set results [list [expr {$board eq [::util::place::besideBoardRect]}] \
  [::scidb::test::dlgplace::inside [::scidb::test::dlgplace::outerRect $dlg] $::scidb::test::dlgplace::area] \
  [::util::place::besideReplaceCount]]
 # A user move clear of the board remains safe in the next area.
 wm geometry $dlg +20+850
 ::scidb::test::dlgplace::waitFor 500
 set moved [::util::place::besideRect $dlg]
 ::util::place::besideResetReplaceCount
 set ::scidb::test::dlgplace::area {0 0 1100 1080}
 ::application::displayWatch
 ::scidb::test::dlgplace::waitFor 1500
 lappend results [expr {$moved eq [::util::place::besideRect $dlg]}] [::util::place::besideReplaceCount]
 # The same user position must be recovered when the area excludes it.
 set ::scidb::test::dlgplace::area {0 0 1100 800}
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
    wm geometry .application "[winfo screenwidth .]x[winfo screenheight .]+0+0"
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
    wm geometry .application "[winfo screenwidth .]x[winfo screenheight .]+0+0"
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
            wm geometry .application %s+0+0
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
tcltest::test dlg-v14-a-inset-dodge {inset dodge chooses candidate and is not a no-op} -setup {
    ::scidb::test::dlgplace::setupBoard
} -body {
    wm geometry .application [::scidb::test::dlgplace::fitGeometry 1000 600]
    ::scidb::test::dlgplace::waitFor 1200
    set insBefore [::scidb::test::dlgplace::startVideo]
    set videoBefore [::util::place::besideVideoRect]
    lassign $videoBefore vx vy vw vh
    set testRect [list [expr {$vx - 10}] [expr {$vy - 10}] [expr {$vw + 20}] [expr {$vh + 20}]]
    set dodged [::mediainset::DodgeForDialog .application.playengine $testRect]
    ::scidb::test::dlgplace::waitFor 400
    set videoAfter [::util::place::besideVideoRect]
    set overlap [::scidb::test::dlgplace::overlapArea $videoAfter $testRect]
    ::mediainset::RestoreAfterDialog .application.playengine
    ::scidb::test::dlgplace::waitFor 400
    set videoRestored [::util::place::besideVideoRect]
    list $dodged [expr {$overlap == 0}] [expr {$videoAfter ne $videoBefore}] [expr {$videoRestored eq $videoBefore}]
} -cleanup {
    catch {::scidb::test::dlgplace::stopVideo}
    ::scidb::test::dlgplace::stopTrace
    ::scidb::test::dlgplace::noRoomCleanup
} -result {1 1 1 1}

# (b) Opening two beside-board dialogs that each reserve a strip and closing
# them in either order leaves no reserve behind: after both close,
# ReserveSide/ReservePixels and the square floor equal their values before the first opened.
tcltest::test dlg-v14-b-reserves-both-orders {two dialogs that each register a real reserve close in either order and restore exact reserve state} -setup {
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
        set owners {}
        foreach e $::util::place::BesideReserves { lappend owners [lindex $e 0] }
        puts "DLG-V14B order=$order before=$before during=[::scidb::test::dlgplace::reserveState] owners=$owners reserves=$::scidb::test::dlgplace::reserves board=[::scidb::test::dlgplace::boardRect] d1=[::scidb::test::dlgplace::outerRect .dlg1] d2=[::scidb::test::dlgplace::outerRect .dlg2]"
        # A vacuous precondition fails: both calls must have returned plans
        # and both dialogs must own a registered reserve.
        ::scidb::test::dlgplace::require [expr {[llength $::scidb::test::dlgplace::reserves] == 2}] \
            "expected 2 besideReserve plans, got $::scidb::test::dlgplace::reserves"
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
    catch {destroy .dlg1}
    catch {destroy .dlg2}
    ::scidb::test::dlgplace::zoomBoard 0
    ::scidb::test::dlgplace::stopTrace
    ::scidb::test::dlgplace::noRoomCleanup
} -result {1 1}

# (c) Maximise, restore and a scripted window resize re-plan an open playing
# dialog (it follows the board); only a real user move/resize of the dialog stops following.
tcltest::test dlg-v14-c-resize-and-user-move {window resize follows board; user manual move stops following until collision} -setup {
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
    # But when dialog is dragged onto board, it MUST re-plan:
    lassign [::scidb::test::dlgplace::boardRect] bx by bw bh
    set deltaCollision [::scidb::test::dlgplace::replaceDelta {
        wm geometry $dlg "+[expr {$bx+20}]+[expr {$by+20}]"
        ::scidb::test::dlgplace::waitFor 1000
    }]
    list [expr {$deltaResize > 0}] [expr {$deltaUserSafe == 0}] [expr {$deltaCollision > 0}]
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
    wm geometry .application [::scidb::test::dlgplace::fitGeometry 1250 570]
    ::scidb::test::dlgplace::waitFor 1000
    set insBefore [::scidb::test::dlgplace::startVideo]
    set review [::gamereview::classify {{san e4 before 0 after 0 best 1} {san e5 before 0 after -250 best 0}}]
    ::gamereview::ShowWindow .application $review {} 0
    ::scidb::test::dlgplace::waitFor 800
    set boardDuring [::scidb::test::dlgplace::boardRect]
    set dlgDuring [::scidb::test::dlgplace::widgetRect .application.__gamereview]
    set reserveDuring [list $::application::board::ReserveSide $::application::board::ReservePixels]

    # Stop video:
    ::scidb::test::dlgplace::stopVideo
    ::scidb::test::dlgplace::waitFor 1000
    set boardAfter [::scidb::test::dlgplace::boardRect]
    set dlgAfter [::scidb::test::dlgplace::widgetRect .application.__gamereview]
    set reserveAfter [list $::application::board::ReserveSide $::application::board::ReservePixels]
    set overlap [::scidb::test::dlgplace::overlapArea $dlgAfter $boardAfter]

    list [expr {$reserveDuring ne {{} 0}}] \
         [expr {$reserveAfter eq {{} 0}}] \
         [expr {$boardAfter ne $boardDuring}] \
         [expr {$overlap == 0}]
} -cleanup {
    catch {::scidb::test::dlgplace::stopVideo}
    catch {destroy .application.__gamereview}
    ::scidb::test::dlgplace::stopTrace
    ::scidb::test::dlgplace::noRoomCleanup
} -result {1 1 1 1}

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

    # Test dialog left reserve centers remaining space exactly like right reserve
    ::scidb::test::dlgplace::require [::application::board::setReserve left $px dialog] "left $px refused"
    set leftDialogX $::application::board::Dim(border:x1)
    ::scidb::test::dlgplace::require [::application::board::setReserve right $px dialog] "right $px refused"
    set rightDialogX $::application::board::Dim(border:x1)
    set leftCentered [expr {$leftDialogX == $px + $rightDialogX}]

    # Test squeeze left reserve (flush against originX)
    ::scidb::test::dlgplace::require [::application::board::setReserve left $px squeeze] "squeeze $px refused"
    set squeezeBrdX $::application::board::Dim(border:x1)
    set squeezeFlush [expr {$squeezeBrdX == $px}]
    set ::application::board::MinimumReserveSquare $floor

    ::application::board::setReserve {} 0
    list $leftCentered $squeezeFlush
} -cleanup {
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
    waitFor 400
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
# 1 s; restore re-plans again; a user's own move then stops following.
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
    foreach {step script} {
        tk-maximize   {wm attributes .application -zoomed 1}
        tk-restore    {wm attributes .application -zoomed 0}
        wm-maximize   {::scidb::test::dlgplace::wmctrlMax 1}
        wm-restore    {::scidb::test::dlgplace::wmctrlMax 0}
    } {
        set g [wm geometry .application]
        set delta [::scidb::test::dlgplace::replaceDelta "$script; ::scidb::test::dlgplace::waitFor 1000"]
        ::scidb::test::dlgplace::require [expr {[wm geometry .application] ne $g}] "$step: window did not change ($g)"
        ::scidb::test::dlgplace::require [expr {$delta >= 1}] "$step: dialog was not re-planned within 1 s"
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
    # Left alone while it stays clear; re-planned only once the resize makes it collide.
    if {$delta == 0} {
        ::scidb::test::dlgplace::require [expr {$safe && [::scidb::test::dlgplace::widgetRect $dlg] eq $moved}] \
            "user-moved dialog left covering board or inset"
    } else {
        ::scidb::test::dlgplace::clearOf v15a-user-collision $dlg
    }
    return 1
} -cleanup {
    ::scidb::test::dlgplace::realCleanup
} -result 1

# (b) Two playing dialogs open at once, board zoomed or not: neither covers
# the drawn board or the inset; both close orders restore reserve and board.
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
        foreach order {{playengine enginematch} {enginematch playengine}} {
            set before [::scidb::test::dlgplace::reserveState]
            set boardBefore [::scidb::test::dlgplace::boardRect]
            ::playengine::open .application
            ::scidb::test::dlgplace::waitFor 900
            ::enginematch::open .application
            ::scidb::test::dlgplace::waitFor 1100
            ::scidb::test::dlgplace::clearOf v15b-%d-playengine .application.playengine
            ::scidb::test::dlgplace::clearOf v15b-%d-enginematch .application.enginematch
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
tcltest::cleanupTests
