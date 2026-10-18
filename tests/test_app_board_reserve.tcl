package require tcltest 2.5

proc brOverlap {a b} {
    lassign $a x y w h
    lassign $b xx yy ww hh
    expr {max(0,min($x+$w,$xx+$ww)-max($x,$xx))*max(0,min($y+$h,$yy+$hh)-max($y,$yy))}
}
proc brInset {} {
    set c $::application::board::Vars(widget:frame)
    # Use the production decoration renderer with a generated one-pawn imbalance.
    $c delete material
    ::application::board::AddMaterial 1 p $c 0 1
    lassign [::application::board::reserveRect] x y w h
    if {$w && $h} {
        place $c.reserveTest -x $x -y $y -width $w -height $h
    } else { place forget $c.reserveTest }
    incr ::brCallbacks
}
proc brSize {w h} {
    set c $::application::board::Vars(widget:frame)
    place $c -x 0 -y 0 -width $w -height $h
    update
    set ::application::board::Vars(width) $w
    set ::application::board::Vars(height) $h
    ::application::board::RebuildBoard $c $w $h true
}
proc brCheck {label} {
    set c $::application::board::Vars(widget:frame)
    set rect [::application::board::reserveRect]
    set all {}
    foreach tag {board stm material} {
        set box [$c bbox $tag]
        if {$box eq {}} { continue }
        lassign $box x y xx yy
        set area [brOverlap $rect [list $x $y [expr {$xx-$x}] [expr {$yy-$y}]]]
        puts "RESERVE $label tag=$tag bbox=$box rect=$rect overlap=$area root=[winfo rootx $c],[winfo rooty $c]"
        lappend all $area
    }
    update idletasks
    puts "RESERVE $label inset=[winfo x $c.reserveTest],[winfo y $c.reserveTest],[winfo width $c.reserveTest],[winfo height $c.reserveTest] controls=[winfo rootx $c.reserveTest.controls],[winfo rooty $c.reserveTest.controls],[winfo width $c.reserveTest.controls],[winfo height $c.reserveTest.controls]"
    expr {[llength $all] && [lsearch -not -exact $all 0] < 0}
}
proc brResize {w h} {
    set c $::application::board::Vars(widget:frame)
    set count $::brCallbacks
    set start [clock milliseconds]
    place configure $c -width $w -height $h
    update
    ::application::board::ConfigureWindow $c $w $h
    while {$::brCallbacks == $count && [clock milliseconds]-$start < 500} {
        update
        after 5
    }
}
proc brSquare {} { set ::application::board::Dim(squaresize:$::application::board::Vars(layout)) }

# Exercise the actual canvas/diagram, temporarily giving it exact pane sizes.
tcltest::test board-reserve-contract {right/bottom/left, restore, refusal and resize callbacks} -body {
    update
    catch {destroy .tipoftheday}
    ::application::switchTab board
    update
    set savedLayout [array get ::board::layout]
    array set ::board::layout {side-to-move 1 material-values 1 material-bar 1}
    set c $::application::board::Vars(widget:frame)
    set packing [pack info $c]
    set original [list $::application::board::Vars(width) $::application::board::Vars(height)]
    pack forget $c
    frame $c.reserveTest -background navy
    label $c.reserveTest.video -text {Dummy video 16:9} -background navy -foreground white
    label $c.reserveTest.controls -text {Play  Pause  Stop} -background gray
    pack $c.reserveTest.controls -side bottom -fill x
    pack $c.reserveTest.video -fill both -expand yes
    set ::brCallbacks 0
    ::application::board::afterRebuild brInset
    set results {}
    try {
        brSize 1500 850
        set before [brSquare]
        lappend results [::application::board::setReserve right 420] [brCheck wide]
        set during [brSquare]
        catch {exec import -window root tests/tmp-app/board-reserve-wide.png}
        ::application::board::setReserve {} 0
        lappend results [expr {[brSquare] == $before}]
        puts "RESERVE restore before=$before during=$during after=[brSquare]"
        brSize 650 1000
        lappend results [::application::board::setReserve bottom 300] [brCheck tall]
        catch {exec import -window root tests/tmp-app/board-reserve-tall.png}
        ::application::board::setReserve {} 0
        brSize 420 400
        set before [brSquare]
        lappend results [expr {![::application::board::setReserve right 350] && [brSquare] == $before}]
        # Corner-overlay fallback is owned by the inset caller.
        place $c.reserveTest -relx 1 -rely 1 -anchor se -width 140 -height 100
        puts "RESERVE refusal square=$before minimum=$::application::board::MinimumReserveSquare overlay=[place info $c.reserveTest]"
        brSize 1200 800
        ::application::board::setReserve right 300
        foreach size {{1100 750} {1000 700} {1300 900}} {
            set count $::brCallbacks
            set start [clock milliseconds]
            brResize {*}$size
            set elapsed [expr {[clock milliseconds]-$start}]
            puts "RESERVE resize=$size elapsed=${elapsed}ms callbacks=[expr {$::brCallbacks-$count}]"
            lappend results [expr {$::brCallbacks > $count && $elapsed < 500 && [brCheck resize]}]
        }
        ::application::board::setReserve left 300
        lappend results [brCheck left]
        # Expand/swap callers clear the reserve, then restore it on return.
        ::application::board::setReserve {} 0
        lappend results [expr {[::application::board::reserveRect] eq {0 0 0 0}}]
        ::application::board::setReserve right 300
        lappend results [brCheck swap-back]
    } finally {
        ::application::board::afterRebuild brInset true
        array set ::board::layout $savedLayout
        ::application::board::setReserve {} 0
        destroy $c.reserveTest
        place forget $c
        pack $c {*}$packing
        ::application::board::RebuildBoard $c {*}$original true
        update
    }
    set results
} -result {1 1 1 1 1 1 1 1 1 1 1 1}

tcltest::cleanupTests
