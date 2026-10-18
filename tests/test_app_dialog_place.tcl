# Real dialog placement: run with -match 'dlg-*' on each required Xvfb screen.
package require tcltest 2.5
namespace eval ::scidb::test::dlgplace {
    variable testDir [file dirname [file normalize [info script]]]
    variable calls
    variable workareaCalls 0
    variable placing 0
}
proc ::scidb::test::dlgplace::waitFor {ms} {
    after $ms {set ::scidb::test::dlgplace::settled 1}
    vwait ::scidb::test::dlgplace::settled
    update idletasks
}
proc ::scidb::test::dlgplace::widgetRect {w} {
    list [winfo rootx $w] [winfo rooty $w] [winfo width $w] [winfo height $w]
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
    dict set calls $dlg [dict create plan $result workareaCalls $workareaCalls board [widgetRect $::application::board::board] \
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
    require [expr {$board eq [widgetRect $::application::board::board]}] "$target: board changed after planning"
    if {$wantRule ne ""} {require [expr {$rule eq $wantRule}] "$target: expected $wantRule, got $rule"}
    require [regexp {^([0-9]+)x([0-9]+)\+(-?[0-9]+)\+(-?[0-9]+)$} [wm geometry $dlg] -> w h x y] "invalid geometry"
    set actual [list $x $y [winfo width $dlg] [winfo height $dlg]]
    foreach a $actual p [dict get $plan geometry] {
        require [expr {abs($a-$p) <= 1}] "$target: final $actual != helper [dict get $plan geometry]"
    }
    require [expr {$w == [winfo width $dlg] && $h == [winfo height $dlg]}] "$target: unsettled client size"
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
    puts "DLG $target screen=[winfo screenwidth .]x[winfo screenheight .] main=[wm geometry .application] board=$board workarea=$wa extents=$ext rule=$rule resized=[dict get $plan resized] helper=[dict get $plan geometry] final=$actual overlap=$area candidates=$areas buttons=$buttonRects"
    if {[info exists ::env(DLG_EVIDENCE_DIR)]} {
        file mkdir $::env(DLG_EVIDENCE_DIR)
        exec import -window root [file join $::env(DLG_EVIDENCE_DIR) $target.png]
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

foreach {target openScript dialog closeScript} {
    002A {::playengine::open .application} {.application.playengine} {::playengine::Close}
    002B {::guessmove::start white} {.application.__guessmove__} {::guessmove::stop; catch {destroy .application.__guessmove__}}
    002C {::reptrainer::open .application} {.application.__reptrainer__} {::reptrainer::Close .application.__reptrainer__}
    003A {set ::gamereview::Priv(total) 4; ::gamereview::ShowProgress .application} {.application.__gamereview_progress} {destroy .application.__gamereview_progress}
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
# A real content-sized dialog too large for all three strips at each screen.
# No workarea, board, or geometry procedures are replaced.
tcltest::test dlg-004 {no-room fallback minimises measured board overlap and exposes every button label} -setup {
    ::scidb::test::dlgplace::setupBoard
} -body {
    toplevel .application.dlgNoRoom
    wm withdraw .application.dlgNoRoom
    wm transient .application.dlgNoRoom .application
    set b [::scidb::test::dlgplace::widgetRect $::application::board::board]
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
} -cleanup {
    catch {destroy .application.dlgNoRoom}
    ::scidb::test::dlgplace::stopTrace
} -result 1

tcltest::test dlg-tactics {trainer with its own board stays centred and does not use besideBoard} -setup {
    ::scidb::test::dlgplace::setupBoard
} -body {
    ::tactics::open .application
    ::scidb::test::dlgplace::waitFor 500
    lassign [::util::place::geometry .tactics -parent .application -position center] x y w h
    puts "DLG tactics final=[wm geometry .tactics] centered-offsets=${x}${y} own-board=[winfo ismapped .tactics.board]"
    list [expr {![dict exists $::scidb::test::dlgplace::calls .tactics]}] \
        [string match "*${x}${y}" [wm geometry .tactics]] [winfo ismapped .tactics.board]
} -cleanup {
    ::tactics::close
    ::scidb::test::dlgplace::stopTrace
} -result {1 1 1}

tcltest::cleanupTests
