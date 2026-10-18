# Headless placement arithmetic: tclsh tests/test_dialog_place.tcl
package require tcltest
proc winfo {args} {error "unexpected Tk call: $args"}
source [file join [file dirname [info script]] .. tcl utils place.tcl]
foreach {name args expected} {
    run37-right {300 100 600 600 323 215 {0 0 1920 1080}} {912 100 323 215}
    run37-left {1000 200 860 860 323 215 {0 0 1920 1080}} {649 200 323 215}
    run37-full {0 0 1920 1000 323 215 {0 0 1920 1080}} {0 825 323 215}
    below {0 0 1920 800 323 215 {0 0 1920 1080}} {0 812 323 215}
    taskbar {100 850 500 500 323 215 {0 28 1920 1012} {6 6 30 6}} {612 789 323 215}
    negative-right {-1600 120 600 600 320 220 {-1920 0 1920 1040} {6 6 30 6}} {-988 120 320 220}
    negative-left {-900 120 860 860 320 220 {-1920 0 1920 1040} {6 6 30 6}} {-1244 120 320 220}
    negative-top {-1100 -900 1000 500 200 150 {-1280 -1024 1280 984} {6 6 30 6}} {-1100 -388 200 150}
    no-room-right {100 20 800 560 360 260 {0 0 1024 600} {6 6 30 6}} {652 20 360 260}
    no-room-left {200 20 750 560 360 260 {0 0 1024 600} {6 6 30 6}} {0 20 360 260}
    below-beats-widest-margin {100 100 800 500 600 100 {0 0 1024 650} {6 6 30 6}} {100 514 600 100}
    oversized-frame {0 0 800 500 900 600 {0 28 800 472} {6 6 30 6}} {0 28 788 436}
} {
    tcltest::test dlg-arithmetic-$name {clamped right/left/below candidates, frames included} -body {
        ::util::place::besidePosition {*}$args
    } -result $expected
}
tcltest::test dlg-insights-1280 {requested size fits after reducing the 780x480 minimum} -body {
    set plan [::util::place::besidePlan 91 112 456 456 780 480 {0 0 1280 800} {3 3 16 6} 12 {583 177}]
    list [dict get $plan geometry] [dict get $plan rule] [dict get $plan resized] [dict get $plan overlap]
} -result {{559 112 583 177} right 1 0}
tcltest::test dlg-insights-1920 {retain current/minimum size when it fits} -body {
    set plan [::util::place::besidePlan 91 112 456 456 780 480 {0 0 1920 1080} {3 3 16 6} 12 {583 177}]
    list [dict get $plan geometry] [dict get $plan rule] [dict get $plan resized]
} -result {{559 112 780 480} right 0}
tcltest::test dlg-requested-no-room {fallback only after retry at requested size; below beats the wider right margin} -body {
    set plan [::util::place::besidePlan 100 100 800 500 780 480 {0 0 1024 650} {6 6 30 6} 12 {600 100}]
    list [dict get $plan geometry] [dict get $plan rule] [dict get $plan areas]
} -result {{100 514 600 100} no-room {right 66368 left 69632 below 52632}}
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
                if {[dict get $plan geometry] ne $expected || [dict get $plan overlap] != $minimum} {error "oracle mismatch $wa $board $size: $plan vs $expected"}
                incr checked
            }
        }
    }
    set checked
} -result 36
set failed $::tcltest::numTests(Failed)
tcltest::cleanupTests
if {$failed} {exit 1}
