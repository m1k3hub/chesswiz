# Headless lifecycle checks of the CQL 6.2 dialog's virtual match list.
package require tcltest 2.5
source [file join [file dirname [info script]] .. tcl app-database-search-cql6.tcl]
namespace eval ::cql6ui { variable rows {}; variable released {}; variable scroll {} }
# paged results of the glue: results id 5 holds {game ply} pairs
namespace eval ::scidb::cql6 {}
proc ::scidb::cql6::matches {id first count} {
    lrange $::cql6ui::pairs($id) [expr {2*$first}] [expr {2*($first+$count)-1}]
}
proc ::scidb::cql6::release {id} { lappend ::cql6ui::released $id; return 1 }
proc ::scidb::cql6::cancel {id} { return 0 }
# a fake treeview that records its items
proc .cql6test.results {command args} {
    switch -- $command {
        children { return [dict keys $::cql6ui::rows] }
        delete { foreach id [lindex $args 0] { dict unset ::cql6ui::rows $id } }
        insert { dict set ::cql6ui::rows [lindex $args 3] [lindex $args 5] }
        exists { return [dict exists $::cql6ui::rows [lindex $args 0]] }
        default {}
    }
}
proc .cql6test.options.run {args} {}
proc .cql6test.options.cancel {args} {}
proc .cql6test.output {args} {}
proc .cql6test.scroll {command args} { set ::cql6ui::scroll $args }

proc ::cql6ui::reset {} {
    array set ::application::database::Cql6SearchData {
        .cql6test,epoch 1 .cql6test,job 17 .cql6test,timer {} .cql6test,results {}
        .cql6test,count 0 .cql6test,top 0 .cql6test,visible 10 .cql6test,selected -1
    }
    set ::cql6ui::rows {}; set ::cql6ui::released {}
    set ::cql6ui::pairs(5) {}
    for {set i 0} {$i < 1000000} {incr i} {lappend ::cql6ui::pairs(5) $i 2}
}

tcltest::test cql6-ui-virtual {a million matches fill only the visible rows} -setup ::cql6ui::reset -body {
    ::application::database::Cql6Finished .cql6test 1 \
        [dict create ok 1 results 5 count 1000000 games 1000000 cancelled 0 messages {}]
    list [dict size $::cql6ui::rows] [lindex [dict get $::cql6ui::rows 0] 0] $::cql6ui::scroll \
        $::application::database::Cql6SearchData(.cql6test,job)
} -result {10 1 {0.0 1e-5} {}}

tcltest::test cql6-ui-scroll {scrolling and keys page through the retained matches} -body {
    ::application::database::Cql6Scroll .cql6test moveto 0.5
    set middle [lindex [dict keys $::cql6ui::rows] 0]
    ::application::database::Cql6Move .cql6test end
    set last [list [lindex [dict keys $::cql6ui::rows] end] \
        $::application::database::Cql6SearchData(.cql6test,selected)]
    ::application::database::Cql6Scroll .cql6test scroll 5 pages
    list $middle $last [dict size $::cql6ui::rows] [lindex [dict keys $::cql6ui::rows] 0]
} -result {500000 {999999 999999} 10 999990}

tcltest::test cql6-ui-rerun {a new search releases the previous results} -body {
    ::application::database::Cql6Release .cql6test
    ::application::database::Cql6Fill .cql6test
    list $::cql6ui::released [dict size $::cql6ui::rows] $::cql6ui::scroll
} -result {5 0 {0 1}}

tcltest::test cql6-ui-stale {old completion cannot alter a reopened dialog, and is released} -setup ::cql6ui::reset -body {
    set ::application::database::Cql6SearchData(.cql6test,epoch) 2
    set ::application::database::Cql6SearchData(.cql6test,status) reopened
    ::application::database::Cql6Finished .cql6test 1 [dict create ok 1 results 9 count 3]
    list $::application::database::Cql6SearchData(.cql6test,status) $::cql6ui::released
} -result {reopened 9}

foreach command {.cql6test.results .cql6test.options.run .cql6test.options.cancel .cql6test.output .cql6test.scroll} {
    rename $command {}
}
array unset ::application::database::Cql6SearchData .cql6test,*
tcltest::cleanupTests
