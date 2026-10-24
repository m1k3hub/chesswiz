# Headless placement arithmetic: tclsh tests/test_dialog_place.tcl
package require tcltest
proc winfo {args} {error "unexpected Tk call: $args"}
source [file join [file dirname [info script]] .. tcl utils place.tcl]
foreach {name args expected} {
    run37-right {300 100 600 600 323 215 {0 0 1920 1080}} {912 100 323 215}
    run37-left {1000 200 860 860 323 215 {0 0 1920 1080}} {649 200 323 215}
    run37-full {0 0 1920 1000 323 215 {0 0 1920 1080}} {0 1012 323 28}
    below {0 0 1920 800 323 215 {0 0 1920 1080}} {0 812 323 215}
    taskbar {100 850 500 500 323 215 {0 28 1920 1012} {6 6 30 6}} {612 789 323 215}
    negative-right {-1600 120 600 600 320 220 {-1920 0 1920 1040} {6 6 30 6}} {-988 120 320 220}
    negative-left {-900 120 860 860 320 220 {-1920 0 1920 1040} {6 6 30 6}} {-1244 120 320 220}
    negative-top {-1100 -900 1000 500 200 150 {-1280 -1024 1280 984} {6 6 30 6}} {-1100 -388 200 150}
    no-room-right {100 20 800 560 360 260 {0 0 1024 600} {6 6 30 6}} {912 20 100 260}
    no-room-left {200 20 750 560 360 260 {0 0 1024 600} {6 6 30 6}} {0 20 176 260}
    below-beats-widest-margin {100 100 800 500 600 100 {0 0 1024 650} {6 6 30 6}} {912 100 100 100}
} {
    tcltest::test dlg-arithmetic-$name {clamped candidates or the largest free strip, frames included} -body {
        ::util::place::besidePosition {*}$args
    } -result $expected
}
# VAL-DLG-011: no-room is no longer an overlap allowance. With no free strip
# that holds the requested size, the plan shrinks into the largest strip; with
# no strip at all it asks the caller to reserve board room.
foreach {name args rule} {
    no-room-shrink-right {100 20 800 560 360 260 {0 0 1024 600} {6 6 30 6}} shrink
    no-room-shrink-left {200 20 750 560 360 260 {0 0 1024 600} {6 6 30 6}} shrink
} {
    tcltest::test dlg-$name {no-room shrinks into a free strip with zero board intersection} -body {
        set plan [::util::place::besidePlan {*}$args]
        list [dict get $plan rule] [dict get $plan overlap] [dict get $plan side]
    } -result [list $rule 0 [expr {[string match *left* $name] ? "left" : "right"}]]
}
tcltest::test dlg-no-strip-reserve {board filling the work area asks for a reserved strip, never overlap} -body {
    set plan [::util::place::besidePlan 0 0 800 500 900 600 {0 28 800 472} {6 6 30 6}]
    list [dict get $plan rule] [dict get $plan needsReserve]
} -result {reserve 1}
tcltest::test dlg-insights-1280 {requested size fits after reducing the 780x480 minimum} -body {
    set plan [::util::place::besidePlan 91 112 456 456 780 480 {0 0 1280 800} {3 3 16 6} 12 {583 177}]
    list [dict get $plan geometry] [dict get $plan rule] [dict get $plan resized] [dict get $plan overlap]
} -result {{559 112 583 177} right 1 0}
tcltest::test dlg-insights-1920 {retain current/minimum size when it fits} -body {
    set plan [::util::place::besidePlan 91 112 456 456 780 480 {0 0 1920 1080} {3 3 16 6} 12 {583 177}]
    list [dict get $plan geometry] [dict get $plan rule] [dict get $plan resized]
} -result {{559 112 780 480} right 0}
tcltest::test dlg-requested-no-room {retry at requested size, then shrink into a strip with zero overlap} -body {
    set plan [::util::place::besidePlan 100 100 800 500 780 480 {0 0 1024 650} {6 6 30 6} 12 {600 100}]
    list [dict get $plan geometry] [dict get $plan rule] [dict get $plan overlap]
} -result {{912 100 100 480} shrink 0}
tcltest::test dlg-shrink-minimum {a declared usable minimum restricts the shrink target but still avoids overlap} -body {
    set plan [::util::place::besidePlan 100 20 800 560 360 260 {0 0 1024 600} {6 6 30 6} 12 {} {100 100}]
    list [dict get $plan rule] [dict get $plan overlap] [dict get $plan geometry]
} -result {shrink 0 {912 20 100 260}}
tcltest::test dlg-usable-strip-beats-sliver {a usable 248x678 strip wins over a 1018x7 sliver} -body {
    set plan [::util::place::besideShrinkPlan 250 151 508 508 248 678 {0 0 1024 700} {3 3 16 6} 12 {248 678}]
    list [dict get $plan side] [dict get $plan usable] [dict get $plan geometry]
} -result {right 1 {770 0 248 678}}
tcltest::test dlg-unusable-strip-never-wins {an unusable sliver is not a shrink target, so the caller reserves} -body {
    set plan [::util::place::besideShrinkPlan 250 151 508 508 690 328 {0 0 1024 700} {3 3 16 6} 12 {690 328}]
    llength $plan
} -result 0
# Independent oracle over varied origins, taskbars, board shapes and sizes.
tcltest::test dlg-candidate-grid {the chosen outer rectangle is contained and has minimum candidate intersection} -body {
    set checked 0
    foreach wa {{0 0 1280 800} {0 28 1920 1012} {-1280 -800 1280 760}} {
        lassign $wa wx wy ww wh
        foreach board {{100 100 800 500} {0 0 1100 650} {650 300 500 300}} {
            lassign $board bx by bw bh
            incr bx $wx
            incr by $wy
            foreach size {{600 100} {780 480} {1300 850} {200 150}} {
                lassign $size w h
                set w [expr {min($w,$ww-12)}]
                set h [expr {min($h,$wh-36)}]
                set fw [expr {$w+12}]
                set fh [expr {$h+36}]
                set expected {}
                set minimum 100000000
                foreach {x y} [list [expr {$bx+$bw+12}] $by [expr {$bx-12-$fw}] $by $bx [expr {$by+$bh+12}]] {
                    set x [expr {max($wx,min($x,$wx+$ww-$fw))}]
                    set y [expr {max($wy,min($y,$wy+$wh-$fh))}]
                    set area [expr {max(0,min($x+$fw,$bx+$bw)-max($x,$bx))*max(0,min($y+$fh,$by+$bh)-max($y,$by))}]
                    if {$area < $minimum} {set minimum $area; set expected [list $x $y $w $h]}
                }
                set plan [::util::place::besidePlan $bx $by $bw $bh {*}$size $wa {6 6 30 6}]
                if {$minimum == 0} {
                    if {[dict get $plan geometry] ne $expected || [dict get $plan overlap] != 0} {
                        error "oracle mismatch $wa $board $size: $plan vs $expected"
                    }
                } else {
                    # No candidate strip holds the request: shrink, or ask for
                    # a reserved strip. Never accept the overlapping geometry.
                    if {[dict get $plan rule] ni {shrink no-room reserve}} {
                        error "unexpected no-room rule $wa $board $size: $plan"
                    }
                    if {[dict get $plan rule] in {shrink no-room}
                        && [dict get $plan overlap] != 0} {
                        error "no-room plan overlaps $wa $board $size: $plan"
                    }
                    lassign [dict get $plan geometry] gx gy gw gh
                    if {$gx < $wx || $gy < $wy
                        || $gx + $gw + 12 > $wx + $ww
                        || $gy + $gh + 36 > $wy + $wh} {
                        error "shrink plan outside work area $wa $board $size: $plan"
                    }
                }
                incr checked
            }
        }
    }
    set checked
} -result 36
# VAL-DLG-021: joint requested-frame packing is independent of Tk/WM.
foreach {name board sizes area fits} {
    pair-column {8 151 331 306} {{361 219} {463 385}} {0 0 802 627} 1
    reverse-column {8 151 331 306} {{463 385} {361 219}} {0 0 802 627} 1
    no-room {0 0 750 550} {{463 385}} {0 0 802 627} 0
    negative-origin {-792 -449 331 306} {{361 219} {463 385}} {-800 -600 802 627} 1
    three-dialogs {0 0 300 300} {{400 180} {400 180} {400 180}} {0 0 800 600} 1
} {
    tcltest::test dlg-reserve-pack-$name {requested native frames clear drawing and one another within live bounds} -body {
        set packed [::util::place::besidePack $board $sizes $area 12]
        set valid [expr {[llength $packed] == [llength $sizes]}]
        set previous {}
        foreach rect $packed size $sizes {
            if {![::util::place::besideInside $rect $area]
                || [::util::place::besideOverlap $rect $board]
                || [lrange $rect 2 3] ne $size} {set valid 0}
            foreach peer $previous {
                if {[::util::place::besideOverlap $rect $peer]} {set valid 0}
            }
            lappend previous $rect
        }
        set valid
    } -result $fits
}
tcltest::test dlg-reserve-pack-video-bounds {joint video stays inside the canvas while the dialog can use the main work area} -body {
    set board {8 153 315 290}
    set canvas {0 148 994 437}
    set packed [::util::place::besidePack $board [list [list 168 182 $canvas] {493 447}] {0 0 996 600} 12]
    list [llength $packed] [::util::place::besideInside [lindex $packed 0] $canvas] \
        [::util::place::besideOverlap [lindex $packed 0] [lindex $packed 1]]
} -result {2 1 0}
set failed $::tcltest::numTests(Failed)
tcltest::cleanupTests
if {$failed} {exit 1}
