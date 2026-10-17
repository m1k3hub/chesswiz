package require tcltest 2.5

# Also runnable headlessly, without booting the application.
if {![namespace exists ::application::database::discover]} {
    namespace eval ::util {proc source {args} {}}
    source [file join [file dirname [info script]] .. tcl app-database-discover.tcl]
}

set filterFixtures {
    {sci Scidb /Archive/World/Openings.sci 100 12}
    {pgn PGN /Archive/World/Finals.pgn 200 -1}
    {si4 Scid /Local/Tactics.si4 300 30}
}
foreach {name text expected} {
    substring pen /Archive/World/Openings.sci
    case WORLD {/Archive/World/Openings.sci /Archive/World/Finals.pgn}
    multiword {world OPEN} /Archive/World/Openings.sci
    empty {} {/Archive/World/Openings.sci /Archive/World/Finals.pgn /Local/Tactics.si4}
    whitespace {  world	 final  } /Archive/World/Finals.pgn
    literal {*} {}
    missing {world tactics} {}
} {
    tcltest::test discover-filter-$name {all words match literally in the full path} -body {
        set paths {}
        foreach entry [::application::database::discover::filterResults $filterFixtures $text] {
            lappend paths [lindex $entry 2]
        }
        set paths
    } -result $expected
}

tcltest::test discover-filter-growing-results {later arrivals are matched without changing scan state} -body {
    namespace eval ::application::database::discover {
        set Priv(scanning) 1
        set Priv(filter) world
        set Priv(results) [lrange $::filterFixtures 0 0]
        set before [llength [filterResults $Priv(results) $Priv(filter)]]
        lappend Priv(results) {*}[lrange $::filterFixtures 1 end]
        set after [llength [filterResults $Priv(results) $Priv(filter)]]
        set state $Priv(scanning)
        set Priv(scanning) 0
        set Priv(results) {}
        set Priv(filter) {}
        list $before $after $state
    }
} -result {1 2 1}

tcltest::testConstraint filterTk [expr {[llength [info commands winfo]] > 0}]
tcltest::test discover-filter-arrivals {progress filters new scan results and keeps the scan running} -constraints filterTk -setup {
    namespace eval ::application::database::discover {
        set Priv(dialog) .filterTest
        set Priv(tree) .filterTest.tree
        set Priv(progress) .filterTest.progress
        set Priv(filter) world
        set Priv(scanning) 1
        set Priv(results) {}
    }
    toplevel .filterTest
    ttk::treeview .filterTest.tree -columns {name games size path}
    ttk::progressbar .filterTest.progress
} -body {
    namespace eval ::application::database::discover {
        set Priv(results) [lrange $::filterFixtures 0 0]
        _progress 1 1
        set before [llength [$Priv(tree) children {}]]
        set Priv(results) $::filterFixtures
        _progress 2 3
        list $before [$Priv(tree) children {}] $Priv(scanning) \
            [string match {*2 of 3} $Priv(status)]
    }
} -cleanup {
    destroy .filterTest
    namespace eval ::application::database::discover {
        set Priv(dialog) {}
        set Priv(scanning) 0
        set Priv(results) {}
        set Priv(filter) {}
    }
} -result {1 {/Archive/World/Openings.sci /Archive/World/Finals.pgn} 1 1}

tcltest::test discover-filter-spaces {rows whose paths contain spaces are removed when filtered out} -constraints filterTk -setup {
    namespace eval ::application::database::discover {
        set Priv(dialog) .filterTest
        set Priv(tree) .filterTest.tree
        set Priv(statusBase) ""
        set Priv(filter) ""
    }
    toplevel .filterTest
    ttk::treeview .filterTest.tree -columns {name games size path}
} -body {
    namespace eval ::application::database::discover {
        set rows {
            {sci Scidb {/My Games/Best Games For Training.sci} 100 12}
            {sci Scidb {/My Games/Biel 2015.sci} 100 9}
            {pgn PGN /Other/plain.pgn 200 -1}
        }
        _populate $rows
        set all [llength [$Priv(tree) children {}]]
        set Priv(filter) "biel"
        _populate $rows
        list $all [$Priv(tree) children {}]
    }
} -cleanup {
    destroy .filterTest
    namespace eval ::application::database::discover { set Priv(dialog) {}; set Priv(filter) {} }
} -result {3 {{/My Games/Biel 2015.sci}}}

tcltest::cleanupTests
