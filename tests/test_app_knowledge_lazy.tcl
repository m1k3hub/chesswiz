# Startup must expose operators before descriptive knowledge is first used.
# The approved missing-leaf ruling removes four unsupported leaves, their
# empty source group and the later unsupported print-report tool alias.
# The resulting independently generated pack contains exactly 698 records.
package require tcltest 2.5

namespace eval ::scidb::test::knowledgeLazy {
    proc ready {} {
        set deadline [expr {[clock milliseconds] + 20000}]
        while {![info exists ::application::Vars(ready)] || !$::application::Vars(ready)} {
            update
            if {[clock milliseconds] > $deadline} {error {startup timed out}}
            after 10
        }
        update
    }
}

# A combined suite may already have requested knowledge in an earlier file.
# the number of actions in the generated pack (README.txt says it), so a
# new action does not need a test edit: the pack is checked against the
# registry by `make knowledge-check`
# The tests use the pack of this tree, not one installed on the machine
# (which may be older), and the count is taken from that same pack.
set ::scidb::test::knowledgeLazy::packDir [file join [file dirname [file dirname [file normalize [info script]]]] share knowledge]
set ::knowledge::PackDir $::scidb::test::knowledgeLazy::packDir

proc ::scidb::test::knowledgeLazy::packCount {} {
    set f [open [file join $::scidb::test::knowledgeLazy::packDir README.txt]]
    regexp {Actions: (\d+)} [read $f] -> n
    close $f
    return $n
}
set ::scidb::test::knowledgeLazy::count [::scidb::test::knowledgeLazy::packCount]

tcltest::testConstraint knowledgeFreshStartup [expr {!$::knowledge::Built && !$::knowledge::PackLoaded}]

tcltest::test knowledge-lazy-startup {all operators exist before knowledge synthesis} -constraints knowledgeFreshStartup -body {
    ::scidb::test::knowledgeLazy::ready
    set missing {}
    set exposed 0
    foreach id [::action::list] {
        set rec [::action::get $id]
        if {![::knowledge::InScope $id $rec]} continue
        incr exposed
        if {$id ni $::knowledge::Exempt && ![dict get $rec operator]} {lappend missing $id}
    }
    set state [::knowledge::RunAction app_state {}]
    list $::knowledge::Built $::knowledge::PackLoaded [expr {$exposed == $::scidb::test::knowledgeLazy::count}] $missing [string match error:* $state]
} -result {0 0 1 {} 0}

tcltest::test knowledge-lazy-first-help {first public help request synthesizes complete knowledge} -body {
    ::scidb::test::knowledgeLazy::ready
    set k [::knowledge::For find_capability en]
    set missing {}
    foreach id [::knowledge::PackIds] {
        set rec [::action::get $id]
        if {[dict get $rec purpose] eq {} || [llength [dict get $rec examples]] < 2} {lappend missing $id}
    }
    list $::knowledge::Built [expr {[dict get $k purpose] ne {}}] $missing
} -result {1 1 {}}

tcltest::test knowledge-lazy-first-search {first search loads the real pack and returns capabilities} -body {
    ::scidb::test::knowledgeLazy::ready
    set caps [::knowledge::Search {open a database} 4]
    list $::knowledge::PackLoaded [expr {[llength $::knowledge::PackActions] == $::scidb::test::knowledgeLazy::count}] [expr {[llength $caps] > 0}]
} -result {1 1 1}

tcltest::test knowledge-lazy-first-pack {pack enumeration also initializes knowledge when used first} -body {
    ::scidb::test::knowledgeLazy::ready
    set ids [::knowledge::PackIds]
    list $::knowledge::Built [expr {[llength $ids] == $::scidb::test::knowledgeLazy::count}]
} -result {1 1}

tcltest::cleanupTests
