# ======================================================================
# VAL-KNOW-007: discovery adds no clutter.
#
# A fresh start must show the same window and no new dialog. Screenshots
# of the same run are captured by scripts/capture-knowledge-clutter.sh and
# compared with tests/tmp-app/know-eval/g3b-snapshot/.
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::kclutter {
    proc ready {} {
        set deadline [expr {[clock milliseconds] + 20000}]
        while {![info exists ::application::Vars(ready)] || !$::application::Vars(ready)} {
            update
            if {[clock milliseconds] > $deadline} { error {startup timed out} }
            after 10
        }
        update
        catch { destroy .tipoftheday }
        update
    }

    proc mappedToplevels {} {
        set out {}
        foreach w [winfo children .] {
            if {[winfo toplevel $w] eq $w && [winfo ismapped $w]} { lappend out $w }
        }
        return [lsort $out]
    }
}

tcltest::test knowledge-clutter-toplevels {a fresh start adds no dialog} -body {
    ::scidb::test::kclutter::ready
    set tops [::scidb::test::kclutter::mappedToplevels]
    puts "KNOW-007 toplevels mapped: $tops"
    set extra {}
    foreach w $tops {
        if {$w ne ".application"} { lappend extra $w }
    }
    set extra
} -result {}

tcltest::test knowledge-clutter-geometry {the default window keeps its G3-b size} -body {
    ::scidb::test::kclutter::ready
    set geometry [wm geometry .application]
    regexp {^(\d+)x(\d+)} $geometry -> width height
    puts "KNOW-007 geometry: $geometry (G3-b main=1007x718+453+170)"
    list $width $height
} -result {1007 718}

tcltest::test knowledge-clutter-no-new-toolbar {no toolbar was added for discovery} -body {
    ::scidb::test::kclutter::ready
    # The toolbars live in the panes; count every Toolbar widget.
    set all {}
    set queue [list .]
    while {[llength $queue]} {
        set w [lindex $queue 0]
        set queue [lrange $queue 1 end]
        if {[winfo class $w] eq "Toolbar"} { lappend all $w }
        foreach child [winfo children $w] { lappend queue $child }
    }
    puts "KNOW-007 toolbars: [llength $all]"
    # G3-b had no discovery toolbar; the assistants only reach discovery
    # through the Ask field. A regression would add a toolbar named *ask*.
    set ask {}
    foreach w $all {
        if {[string match -nocase *ask* $w]} { lappend ask $w }
    }
    set ask
} -result {}

tcltest::cleanupTests
