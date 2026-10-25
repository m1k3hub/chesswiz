# Headless regression tests: tclsh tests/test_startup_geometry.tcl
package require tcltest
# place.tcl wraps winfo at source time; no Tk/display is needed by clampGeometry.
proc winfo {args} { error "unexpected Tk call: $args" }
source [file join [file dirname [info script]] .. tcl utils place.tcl]
foreach {name input expected} {
    laptop 1898x964+849+382 1898x964+22+68
    old-screen-2560x1440 2500x1380+30+40 1920x1032+0+0
    negative 800x600+-200+-100 800x600+0+0
    fits 800x600+100+150 800x600+100+150
    far-edge 800x600-10-20 800x600+1110+412
} {
    tcltest::test geometry-$name {clamp to 1920x1032 work area} -body {
        ::util::place::clampGeometry $input {0 0 1920 1032}
    } -result $expected
}
tcltest::test geometry-frame {frame and taskbar both fit} -body {
    ::util::place::clampGeometry 1898x1060+849+382 {0 0 1920 1032} {8 8 31 8}
} -result 1898x993+6+0
tcltest::test geometry-monitor {negative monitor origin is an absolute Tk offset} -body {
    ::util::place::clampGeometry 800x600+-1800+50 {-1920 0 1920 1032}
} -result 800x600+-1800+50

# VAL-DLG-001: Shared placement helper arithmetic (right, else left, else below,
# clamped to real work area incl. taskbar and multi-monitor negative origins;
# includes Run 37 layout).
foreach {name args expected} {
    run37-right-has-room {300 100 600 600 323 215 {0 0 1920 1080}}              {912 100 323 215}
    run37-board-right    {1000 200 860 860 323 215 {0 0 1920 1080}}             {649 200 323 215}
    run37-board-fills    {0 0 1920 1000 323 215 {0 0 1920 1080}}                {0 1012 323 28}
    below-board          {0 0 1920 800 323 215 {0 0 1920 1080}}                 {0 812 323 215}
    taskbar-clamp        {100 850 500 500 323 215 {0 28 1920 1012} {6 6 30 6}}  {612 789 323 215}
    multimon-right       {-1600 120 600 600 320 220 {-1920 0 1920 1040} {6 6 30 6}} {-988 120 320 220}
    multimon-left        {-900 120 860 860 320 220 {-1920 0 1920 1040} {6 6 30 6}}  {-1244 120 320 220}
    no-room-right-wider  {100 20 800 560 360 260 {0 0 1024 600} {6 6 30 6}}     {912 20 100 260}
    no-room-left-wider   {200 20 750 560 360 260 {0 0 1024 600} {6 6 30 6}}     {0 20 176 260}
} {
    tcltest::test beside-$name {besidePosition arithmetic} -body {
        ::util::place::besidePosition {*}$args
    } -result $expected
}

# Load the real layout callback without loading the rest of the application.
proc loadProc {file name ns} {
    set f [open $file]; set source [read $f]; close $f
    set start [string first "proc $name " $source]
    set body ""
    foreach line [split [string range $source $start end] \n] {
        append body $line \n
        if {[info complete $body]} { break }
    }
    namespace eval $ns $body
}
set root [file join [file dirname [info script]] ..]
namespace eval ::application { variable Vars; array set Vars {fullscreen 0 need:maxsize 0 ready 1 window:state:last {} last:normal:geometry {} restoring:normal 0} }
namespace eval ::application::twm {}
namespace eval ::theme {
    proc notebookBorderwidth {} { return 0 }
    proc notebookTabPaneSize {w} { return 0 }
}
namespace eval ::widget { proc checkIsKDE {} { return 0 } }
namespace eval ::menu { proc fullscreen? {} { return 0 } }
loadProc [file join $root tcl app-twm.tcl] geometry ::application::twm
loadProc [file join $root tcl application.tcl] LayoutMinimum ::application
loadProc [file join $root tcl application.tcl] GeometrySize ::application
loadProc [file join $root tcl application.tcl] BelowMinimum? ::application
loadProc [file join $root tcl application.tcl] DefaultNormalGeometry ::application
loadProc [file join $root tcl application.tcl] ApplyLayoutMinimum ::application
loadProc [file join $root tcl application.tcl] RestoreNormalGeometry ::application
loadProc [file join $root tcl application.tcl] RememberWindowGeometry ::application
loadProc [file join $root tcl application.tcl] RestoreWindowGeometry ::application
# Mock only the Tk boundary, retaining the actual callback and fitWindow.
rename ::winfo ::wrapped_winfo
proc ::winfo {cmd w} {
    switch $cmd {
        workarea { return {0 0 1920 1032} }
        extents { return {8 8 31 8} }
        ismapped { return 0 }
        default { error "unexpected winfo $cmd" }
    }
}
proc wm {cmd w args} {
    switch $cmd {
        geometry {
            if {[llength $args]} { set ::geom [lindex $args 0] }
            return $::geom
        }
        state {
            if {[llength $args]} { set ::state [lindex $args 0] }
            return $::state
        }
        deiconify { set ::state normal }
        minsize { return {300 300} }
        default { error "unexpected wm $cmd" }
    }
}
tcltest::test geometry-layout-resize {late resize uses new size, not stale mapped dimensions} -body {
    set ::state normal
    set ::geom 200x200+849+382
    ::application::twm::geometry {1898 964 0 0 0 0}
    set ::geom
} -result 1898x964+6+29
tcltest::test geometry-layout-zoomed {layout updates preserve maximization} -body {
    set ::state zoomed
    set ::geom 1898x993+0+0
    ::application::twm::geometry {800 600 0 0 0 0}
    set ::geom
} -result 1898x993+0+0
tcltest::test geometry-save-state {zoomed and iconified keep the normal restore geometry} -body {
    set ::state normal
    set ::geom 800x600+100+150
    ::application::RememberWindowGeometry .application
    set ::state zoomed
    set ::geom 1904x993+0+0
    ::application::RememberWindowGeometry .application
    set ::state iconic
    ::application::RememberWindowGeometry .application
    list $::application::Options(window:geometry) $::application::Options(window:state)
} -result {800x600+100+150 zoomed}
proc tk {cmd} { return win32 }
tcltest::test geometry-layout-minimum {VAL-RSZ-006 computed layout minimum wins over a lowered wm minsize} -body {
    set ::application::Vars(board:twm) ::fakeTwm
    proc ::fakeTwm {cmd args} {
        if {$cmd eq "dimension"} { return {500 400 300 250 0 0} }
        error "unexpected $cmd"
    }
    ::application::LayoutMinimum
} -cleanup {
    unset -nocomplain ::application::Vars(board:twm)
} -result {300 250}
tcltest::test geometry-zoomed-small-restore {VAL-RSZ-006 a 200x200 normal geometry saved while zoomed derives a sane one} -body {
    set ::application::Options(window:geometry) 200x200+849+382
    set ::application::Options(window:state) zoomed
    set ::state withdrawn
    ::application::RestoreWindowGeometry .application
    list [::application::GeometrySize $::geom] $::state \
        $::application::Options(window:geometry)
} -result {{1536 825} zoomed 1536x825+192+103}
tcltest::test geometry-zoomed-normal-restore {VAL-RSZ-006 zoomed -> normal below the minimum re-applies the remembered geometry} -body {
    set ::application::Options(window:geometry) 900x700+100+100
    set ::application::Options(window:state) normal
    set ::state normal
    ::application::RestoreWindowGeometry .application
    # Windows hands back the stale pre-maximise rect (200x200) on Restore.
    set ::application::Vars(window:state:last) zoomed
    set ::geom 200x200+100+100
    ::application::RememberWindowGeometry .application
    list $::geom $::application::Options(window:geometry)
} -result {900x700+100+100 900x700+100+100}
tcltest::test geometry-restore-move-before-size {a native move notification preserves the restore transition until its size arrives} -body {
    set ::state normal
    set ::application::Vars(window:size:last) {900 700}
    set ::application::Vars(window:state:last) zoomed
    set ::application::Vars(last:normal:geometry) 900x700+100+100
    set ::geom 900x700+120+120
    ::application::RememberWindowGeometry .application
    set pending $::application::Vars(window:state:last)
    set ::geom 200x200+120+120
    ::application::RememberWindowGeometry .application
    list $pending $::geom $::application::Options(window:geometry)
} -result {zoomed 900x700+120+120 900x700+120+120}
tcltest::test geometry-restore {saved oversized geometry is fitted before opening zoomed} -body {
    set ::application::Options(window:geometry) 2500x1380+849+382
    set ::application::Options(window:state) zoomed
    set ::state withdrawn
    ::application::RestoreWindowGeometry .application
    list $::geom $::state
} -result {1904x993+0+0 zoomed}
tcltest::test geometry-restore-normal {a fitting saved geometry stays unchanged} -body {
    set ::application::Options(window:geometry) 800x600+100+150
    set ::application::Options(window:state) normal
    ::application::RestoreWindowGeometry .application
    list $::geom $::state
} -result {800x600+100+150 normal}
tcltest::test geometry-fresh-start {a fresh user's computed placement is clamped too} -setup {
    rename ::util::place ::util::originalPlace
    proc ::util::place {path args} {
        set ::geom 1898x964+849+382
    }
} -body {
    set ::application::Options(window:geometry) {}
    set ::application::Options(window:state) normal
    ::application::RestoreWindowGeometry .application
    list $::geom $::state
} -cleanup {
    rename ::util::place {}
    rename ::util::originalPlace ::util::place
} -result {1898x964+6+29 normal}
set failed $::tcltest::numTests(Failed)
tcltest::cleanupTests
if {$failed} { exit 1 }
