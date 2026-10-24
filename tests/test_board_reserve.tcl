# Run with tclsh: exercise production layout arithmetic without Tk/display.
package require tcltest 2.5
namespace eval ::application::board {
    variable MinimumReserveSquare 32
    variable ReserveSide {}
    variable ReservePixels 0
    variable ReserveKind auto
    variable ReserveMaxBoard 0
    variable RebuildCallbacks {}
    variable Vars
    array set Vars {layout Normal width 1500 height 850 widget:frame .canvas after {}}
    variable Dim
    array set Dim {}
}
namespace eval ::board {
    variable layout
    array set layout {side-to-move 1 material-values 1 border 1 coordinates 1 material-bar 1}
    proc computeGap {size} { return 0 }
}
namespace eval ::font { proc scaleFactor {} { return 1 } }
proc tk {args} { return 1.3333333333 }
set f [open [file join [file dirname [info script]] .. tcl app-board.tcl]]
set source [read $f]
close $f
set wanted {ComputeLayout reserveSquare reserveBorder unreservedSquare setReserve reserveRect afterRebuild ApplyReserve3D ConfigureReserve3D}
set definition {}
foreach line [split $source \n] {
    if {$definition eq {} && [regexp {^proc ([^ ]+) } $line -> name] && $name in $wanted} {
        set definition "$line\n"
    } elseif {$definition ne {}} { append definition "$line\n" }
    if {$definition ne {} && [info complete $definition]} {
        namespace eval ::application::board $definition
        set definition {}
    }
}
namespace eval ::application::board {
    proc RebuildBoard {canvas w h {force false}} {
        variable rebuildCount
        incr rebuildCount
        ComputeLayout $w $h
    }
    variable rebuildCount 0
}
proc brPureCheck {} {
    upvar #0 ::application::board::Dim d
    lassign [::application::board::reserveRect] x y w h
    # Board plus the complete side-to-move/material decoration allowance.
    set right [expr {$d(border:x2)+$d(gap:x)+$d(stm)}]
    expr {min($x+$w,$right) <= max($x,$d(border:x1)) || min($y+$h,$d(border:y2)) <= max($y,$d(border:y1))}
}
foreach side {right bottom left} {
    tcltest::test board-reserve-pure-$side {reserve excludes board and decorations; exact restoration} -body {
        set ::application::board::ReserveSide {}
        set ::application::board::Vars(width) 1500
        set ::application::board::Vars(height) 850
        ::application::board::ComputeLayout 1500 850
        set before [array get ::application::board::Dim]
        set original $::application::board::Dim(squaresize:Normal)
        set accepted [::application::board::setReserve $side 360 dialog]
        set clear [brPureCheck]
        puts "PURE $side reserve=[::application::board::reserveRect] square=$::application::board::Dim(squaresize:Normal) overlap-free=$clear"
        ::application::board::setReserve {} 0
        list $accepted $clear [expr {$original == $::application::board::Dim(squaresize:Normal)}]
    } -result {1 1 1}
}
tcltest::test board-reserve-probe {candidate measurements preserve the accepted state and fit the default canvas} -body {
    ::application::board::setReserve right 300
    set before [lsort [array get ::application::board::Dim]]
    set count $::application::board::rebuildCount
    set square [::application::board::reserveSquare right 168 500 405 dialog]
    list [expr {$square >= 32}] \
        [expr {$before eq [lsort [array get ::application::board::Dim]]}] \
        [expr {$count == $::application::board::rebuildCount}] \
        $::application::board::ReserveSide $::application::board::ReservePixels
} -result {1 1 1 right 300}
tcltest::test board-reserve-border-probe {border probes preserve dimensions and every live reserve field} -body {
    ::application::board::setReserve right 300
    set before [lsort [array get ::application::board::Dim]]
    set count $::application::board::rebuildCount
    set state [list $::application::board::ReserveSide $::application::board::ReservePixels \
        $::application::board::ReserveKind $::application::board::ReserveMaxBoard]
    set border [::application::board::reserveBorder left 168 squeeze 500]
    set absent [::application::board::reserveBorder right 1500 auto]
    list [expr {[llength $border] == 3 && [lindex $border 2] > 0}] \
        [expr {$absent eq {}}] \
        [expr {$before eq [lsort [array get ::application::board::Dim]]}] \
        [expr {$state eq [list $::application::board::ReserveSide $::application::board::ReservePixels \
            $::application::board::ReserveKind $::application::board::ReserveMaxBoard]}] \
        [expr {$count == $::application::board::rebuildCount}]
} -result {1 1 1 1 1}
tcltest::test board-reserve-pure-refusal {refusal leaves dimensions and accepted reserve unchanged} -body {
    ::application::board::setReserve right 300
    set before [lsort [array get ::application::board::Dim]]
    set count $::application::board::rebuildCount
    list [::application::board::setReserve right 1400] \
        [expr {$before eq [lsort [array get ::application::board::Dim]]}] \
        [expr {$count == $::application::board::rebuildCount}] \
        $::application::board::ReservePixels
} -result {0 1 1 300}
tcltest::test board-reserve-pure-resize {resize sequence and minimum fallback} -body {
    set results {}
    foreach size {{1100 750} {1000 700} {1300 900}} {
        ::application::board::ComputeLayout {*}$size
        lappend results [brPureCheck]
        puts "PURE resize=$size rect=[::application::board::reserveRect] square=$::application::board::Dim(squaresize:Normal)"
    }
    ::application::board::ComputeLayout 350 300
    lappend results [expr {[::application::board::reserveRect] eq {0 0 0 0}}]
    set results
} -result {1 1 1 1}
tcltest::test board-reserve-pure-callbacks {idempotent callback registration and removal} -body {
    ::application::board::afterRebuild {example callback}
    ::application::board::afterRebuild {example callback}
    set count [llength $::application::board::RebuildCallbacks]
    ::application::board::afterRebuild {example callback} true
    list $count [llength $::application::board::RebuildCallbacks]
} -result {1 0}
tcltest::test board-reserve-pure-idempotent {inset callbacks can re-request an existing reserve} -body {
    ::application::board::setReserve right 300
    set count $::application::board::rebuildCount
    list [::application::board::setReserve right 300] [expr {$count == $::application::board::rebuildCount}]
} -result {1 1}
proc pack {args} { set ::brPack $args }
tcltest::test board-reserve-pure-3d {visible 3D frame reserves each side and reports full pane resize dimensions} -body {
    set ::application::board::Vars(3d) 1
    set ::application::board::Vars(3dwin) .visible3d
    set result {}
    foreach side {right bottom left} {
        set ::application::board::ReserveSide $side
        set ::application::board::ReservePixels 300
        ::application::board::ApplyReserve3D
        lappend result $::brPack
    }
    set count $::application::board::rebuildCount
    ::application::board::ConfigureReserve3D 900 800
    ::application::board::ConfigureReserve3D 900 800
    lappend result [list $::application::board::Vars(width) $::application::board::Vars(height)]
    lappend result [expr {$::application::board::rebuildCount-$count}]
    update idletasks
    lappend result [expr {$::application::board::rebuildCount-$count}]
    update
    lappend result [expr {$::application::board::rebuildCount-$count}]
    set ::application::board::ReserveSide {}
    set ::application::board::ReservePixels 0
    ::application::board::ApplyReserve3D
    lappend result $::brPack
    set ::application::board::Vars(3d) 0
    set result
} -result {{configure .visible3d -padx {0 300} -pady {0 0}} {configure .visible3d -padx {0 0} -pady {0 300}} {configure .visible3d -padx {300 0} -pady {0 0}} {1200 800} 0 0 1 {configure .visible3d -padx {0 0} -pady {0 0}}}

# VAL-MED-012: compare the reserved square with unreservedSquare whenever a reserve
# is set or considered (ComputeLayout and FitStrip), not only below MinimumReserveSquare.
# Validator counterexamples that must keep the square equal to unreserved:
# 1000x640 (33 vs 38), 1000x700 (33 vs 43), 1100x700 (39 vs 43).
tcltest::test board-reserve-val-med-012-counterexamples {reserves shrinking board square are rejected} -body {
    set results {}
    # Case 1: 1000x640: unreserved 38 vs right reserve (which would be 33)
    set w 497; set h 340
    set unreserved [::application::board::unreservedSquare $w $h]
    set reserved [::application::board::reserveSquare right 170 $w $h auto]
    lappend results [list $unreserved $reserved]

    # Case 2: 1000x700: unreserved 43 vs right reserve (which would be 33)
    set w 497; set h 382
    set unreserved [::application::board::unreservedSquare $w $h]
    set reserved [::application::board::reserveSquare right 170 $w $h auto]
    lappend results [list $unreserved $reserved]

    # Case 3: 1100x700: unreserved 43 vs right reserve (which would be 39)
    set w 547; set h 382
    set unreserved [::application::board::unreservedSquare $w $h]
    set reserved [::application::board::reserveSquare right 170 $w $h auto]
    lappend results [list $unreserved $reserved]

    set results
} -result {{38 0} {43 0} {43 0}}

tcltest::cleanupTests
