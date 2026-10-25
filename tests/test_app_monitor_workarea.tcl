# Real X11 monitor tests. Set CW_TEST_MONITORS to x/y/w/h rectangles from
# the xrandr fixture; without it this file safely skips on ordinary displays.
package require tcltest
source [file join [file dirname [info script]] app_wait.tcl]
::scidb::test::wait::ready
namespace eval ::monitorTest {
proc settle {} {
    set until [expr {[clock milliseconds]+2200}]
    while {[clock milliseconds] < $until} { update; after 25 }
}
proc inside {frame area} {
    lassign $frame x y w h
    lassign $area ax ay aw ah
    expr {$x >= $ax && $y >= $ay && $x+$w <= $ax+$aw && $y+$h <= $ay+$ah}
}
}
tcltest::testConstraint monitorFixture [info exists ::env(CW_TEST_MONITORS)]
tcltest::test monitor-workarea-move {moving between RandR monitors changes signature, relayout and native clamp} -constraints monitorFixture -setup {
    set saved [wm geometry .application]
    set minsize [wm minsize .application]
    wm minsize .application 1 1
} -body {
    set signatures {}
    set results {}
    foreach monitor $::env(CW_TEST_MONITORS) {
        lassign $monitor x y w h
        set property [exec xprop -root _NET_WORKAREA]
        set values [regexp -all -inline -- {-?[0-9]+} [lindex [split $property =] 1]]
        lassign $values rx ry rw rh
        if {$rx >= 2147483648} {incr rx -4294967296}
        if {$ry >= 2147483648} {incr ry -4294967296}
        set ax [expr {max($rx,$x)}]; set ay [expr {max($ry,$y)}]
        set aw [expr {min($rx+$rw,$x+$w)-$ax}]
        set ah [expr {min($ry+$rh,$y+$h)-$ay}]
        set area [list $ax $ay $aw $ah]
        set changes [::application::displayChangeCount]
        wm geometry .application "600x400+[expr {$ax+40}]+[expr {$ay+40}]"
        ::monitorTest::settle
        set actual [::scidb::tk::wm workarea .application]
        set found [::scidb::tk::wm monitor .application]
        lappend signatures [::application::displaySignature]
        set frame [::scidb::tk::wm frame .application]
        puts "monitor=$monitor native=$found area=$actual frame=$frame changes=[::application::displayChangeCount]"
        lappend results [expr {$actual eq $area && $found eq $monitor && [::monitorTest::inside $frame $area]}]
        if {[llength $signatures] > 1} {
            lappend results [expr {[::application::displayChangeCount] > $changes}]
        }
        # Clamp an oversized client whose centre is in this monitor.
        wm geometry .application "[expr {$aw+80}]x[expr {$ah+80}]+$ax+$ay"
        ::monitorTest::settle
        lappend results [::monitorTest::inside [::scidb::tk::wm frame .application] $area]
        toplevel .monitorDialog
        wm geometry .monitorDialog "300x200+[expr {$ax+20}]+[expr {$ay+20}]"
        ::monitorTest::settle
        ::util::place::fitWindow .monitorDialog
        ::monitorTest::settle
        lappend results [::monitorTest::inside [::scidb::tk::wm frame .monitorDialog] $area]
        destroy .monitorDialog
    }
    list [expr {[lindex $signatures 0] ne [lindex $signatures 1]}] [expr {0 ni $results}]
} -cleanup {
    catch {destroy .monitorDialog}
    wm minsize .application {*}$minsize
    wm geometry .application $saved
    ::monitorTest::settle
} -result {1 1}
foreach mode {taskbar absent} {
    tcltest::test monitor-workarea-$mode {desktop property is intersected, absent property uses full root} -constraints monitorFixture -setup {
        set property [exec xprop -root _NET_WORKAREA]
        set savedProperty [string trim [lindex [split $property =] 1]]
        toplevel .monitorProbe
        wm geometry .monitorProbe 200x100+100+100
        ::monitorTest::settle
    } -body {
        if {$mode eq "absent"} {
            exec xprop -root -remove _NET_WORKAREA
            set rootArea [list 0 0 [winfo screenwidth .application] [winfo screenheight .application]]
        } else {
            set rootArea [list 0 30 [winfo screenwidth .application] [expr {[winfo screenheight .application]-30}]]
            exec xprop -root -f _NET_WORKAREA 32c -set _NET_WORKAREA [join $rootArea ,]
        }
        lassign [lindex $::env(CW_TEST_MONITORS) 0] x y w h
        lassign $rootArea rx ry rw rh
        set ax [expr {max($x,$rx)}]; set ay [expr {max($y,$ry)}]
        set expected [list $ax $ay [expr {min($x+$w,$rx+$rw)-$ax}] [expr {min($y+$h,$ry+$rh)-$ay}]]
        set actual [::scidb::tk::wm workarea .monitorProbe]
        puts "property=$mode expected=$expected actual=$actual"
        expr {$actual eq $expected}
    } -cleanup {
        exec xprop -root -f _NET_WORKAREA 32c -set _NET_WORKAREA $savedProperty
        destroy .monitorProbe
    } -result 1
}
tcltest::cleanupTests
