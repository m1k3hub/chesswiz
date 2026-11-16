# Real menu windows must remain reachable on laptop workareas.
package require tcltest 2.5
namespace eval ::scidb::test::menuarea {}
proc ::scidb::test::menuarea::settle {} {
    after 800 {set ::scidb::test::menuarea::settled 1}
    vwait ::scidb::test::menuarea::settled
    update
}
foreach {name script window} {
    stream {::stream::open .application} .stream
    tournament {::td::ui::Open {}} .application.tournamentDirector
} {
    tcltest::test menu-workarea-$name {menu window fits and its full body is scrollable} -body {
        catch {destroy .tipoftheday}
        ::application::switchTab board
        uplevel #0 $script
        ::scidb::test::menuarea::settle
        set frame [::scidb::tk::wm frame $window]
        if {[llength $frame] != 4} {
            # The X11 frame extension returns no frame on native Tk.
            lassign [winfo extents $window] left right top bottom
            set frame [list [expr {[winfo rootx $window]-$left}] \
                [expr {[winfo rooty $window]-$top}] \
                [expr {[winfo width $window]+$left+$right}] \
                [expr {[winfo height $window]+$top+$bottom}]]
        }
        lassign $frame x y w h
        lassign [winfo workarea $window] ax ay aw ah
        set fits [expr {$x >= $ax && $y >= $ay && $x+$w <= $ax+$aw && $y+$h <= $ay+$ah}]
        set canvas $window.__viewport.canvas
        $canvas xview moveto 1
        $canvas yview moveto 1
        update
        set reaches [expr {[lindex [$canvas xview] 1] == 1.0 && [lindex [$canvas yview] 1] == 1.0}]
        puts [list WINDOW $window frame [list $x $y $w $h] workarea [list $ax $ay $aw $ah] scroll [$canvas xview] [$canvas yview]]
        list $fits [expr {$window in [::application::FloatingWindows]}] $reaches \
            [expr {$x != 0 || $y != 0}]
    } -cleanup {destroy $window; update} -result {1 1 1 1}
}
tcltest::cleanupTests
