# Real dialog placement: run with -match 'dlg-*' on each required Xvfb screen.
package require tcltest 2.5
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
    # Independent oracle: include the drawn border and coordinates, not just
    # the inner board widget used by the old placement helper.
    set canvas $::application::board::Vars(widget:frame)
    lassign [$canvas bbox board] x0 y0 x1 y1
    return [list [expr {[winfo rootx $canvas] + $x0 - int([$canvas canvasx 0])}] \
        [expr {[winfo rooty $canvas] + $y0 - int([$canvas canvasy 0])}] \
        [expr {$x1-$x0}] [expr {$y1-$y0}]]
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
    require [expr {$w >= [lindex $requested 0] && $h >= [lindex $requested 1]}] \
        "$target: final ${w}x${h} clips requested $requested"
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
    require [expr {$area == [tcl::mathfunc::min {*}[dict values $areas]]}] "$target: overlap $area is not minimum of $areas"
    if {$rule ne "no-room"} {require [expr {$area == 0}] "$target: $rule overlaps $area"}
    if {$rule eq "no-room"} {require [expr {$area > 0}] "$target: spurious no-room rule"}
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
    ::scidb::test::dlgplace::check 004 .application.dlgNoRoom no-room
    .application.dlgNoRoom.content configure -width [expr {$cw+30}] -height [expr {$ch+30}]
    ::scidb::test::dlgplace::check 004-growth .application.dlgNoRoom no-room
} -cleanup {
    catch {destroy .application.dlgNoRoom}
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
proc ::scidb::test::dlgplace::follow {target dlg} {
    # Start wide enough to open normally, then force the tall reflow with the
    # contract's 1274x900 -> 800x900 resize.
    wm geometry .application 1274x900+10+10
    waitFor 1200
    noOverlap $target-open $dlg
    set before [widgetRect $dlg]

    set delta [replaceDelta {wm geometry .application 800x900+10+10; waitFor 1300}]
    require [expr {$delta == 1}] "$target-resize: expected 1 re-place, got $delta"
    require [expr {[widgetRect $dlg] ne $before}] "$target-resize: dialog did not follow the board"
    noOverlap $target-resize $dlg

    set before [widgetRect $dlg]
    set delta [replaceDelta {wm geometry .application +180+120; waitFor 1300}]
    require [expr {$delta == 1}] "$target-move: expected 1 re-place, got $delta"
    require [expr {[widgetRect $dlg] ne $before}] "$target-move: dialog did not follow the board"
    noOverlap $target-move $dlg

    set delta [replaceDelta {::menu::viewFullscreen toggle; waitFor 1800}]
    require [expr {$delta == 1}] "$target-fullscreen: expected 1 re-place, got $delta"
    noOverlap $target-fullscreen $dlg
    # Leaving fullscreen moves the board back; the dialog follows again.
    set delta [replaceDelta {::menu::viewFullscreen toggle; waitFor 1500}]
    require [expr {$delta == 1}] "$target-unfullscreen: expected 1 re-place, got $delta"
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
    wm geometry .application 1274x900+10+10
    ::playengine::open .application
    ::scidb::test::dlgplace::waitFor 800
    set dlg .application.playengine
    lassign [winfo workarea $dlg] wx wy ww wh
    set h [winfo height $dlg]
    lassign [winfo extents $dlg] el er et eb
    # Bottom-left corner, with the entire decorated frame inside the area.
    wm geometry $dlg "+[expr {$wx+10}]+[expr {$wy+$wh-$h-$et-$eb-10}]"
    ::scidb::test::dlgplace::waitFor 800
    set moved [::scidb::test::dlgplace::widgetRect $dlg]
    ::scidb::test::dlgplace::noOverlap user-move-safe $dlg

    set delta [::scidb::test::dlgplace::replaceDelta {
        wm geometry .application 900x1000+10+10
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

tcltest::cleanupTests
