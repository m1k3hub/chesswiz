package require tcltest 2.5
source [file join [file dirname [info script]] app_actions_support.tcl]
namespace eval ::scidb::test::inventoryhelp {
    proc call {args} {
        set result [::knowledge::RunAction help.viewer $args]
        if {[string match error:* $result]} {error $result}
        update
        return $result
    }
}
tcltest::test inventory-help-navigation {help operation navigates real installed pages and native history} -setup {
    ::scidb::test::actions::ready
    ::scidb::test::inventoryhelp::call operation open
    set first $::help::Priv(current:file)
    set topics [glob -directory [file dirname $first] *.html]
    set target [lindex [lsearch -all -inline -not -exact $topics $first] 0]
} -body {
    puts "HELP TOPICS: $first -> $target"
    ::scidb::test::inventoryhelp::call operation load topic [file tail $target]
    set second $::help::Priv(current:file)
    ::scidb::test::inventoryhelp::call operation back
    set back $::help::Priv(current:file)
    ::scidb::test::inventoryhelp::call operation forward
    set forward $::help::Priv(current:file)
    list [expr {$second eq $target}] [expr {$back eq $first}] [expr {$forward eq $second}] \
        [string match error:* [::knowledge::RunAction help.viewer {operation load topic missing-generated-topic}]]
} -result {1 1 1 1}

tcltest::test inventory-help-layout {native help expansion, alignment and index controls accept explicit operations} -body {
    set tree $::help::Priv(contents:tree)
    ::scidb::test::inventoryhelp::call operation expand
    set expanded [$tree item state get root open]
    ::scidb::test::inventoryhelp::call operation collapse
    set collapsed [$tree item state get root open]
    set good 1
    foreach alignment {justify left} {
        ::scidb::test::inventoryhelp::call operation alignment alignment $alignment
        set variable [format {::html::%s::Priv(textalign)} $::help::Priv(html)]
        if {[set $variable] ne $alignment} {set good 0}
    }
    set control $::help::Priv(control)
    set pw [winfo parent $control]
    ::scidb::test::inventoryhelp::call operation index show 0
    set hidden [expr {$control ni [$pw panes]}]
    ::scidb::test::inventoryhelp::call operation index show 1
    ::scidb::test::inventoryhelp::call operation index show 1
    list $expanded $collapsed $good $hidden [expr {$control in [$pw panes]}]
} -result {1 0 1 1 1}

tcltest::test inventory-help-topics {next and previous invoke native help topic navigation} -body {
    ::scidb::test::inventoryhelp::call operation open topic Database-Formats
    set first $::help::Priv(current:file)
    ::scidb::test::inventoryhelp::call operation next
    set second $::help::Priv(current:file)
    ::scidb::test::inventoryhelp::call operation previous
    list [expr {$second ne $first}] [expr {$::help::Priv(current:file) eq $first}]
} -result {1 1}

tcltest::test inventory-help-close {typed close shares native Help teardown and preserves the board application} -setup {
    ::scidb::test::actions::ready
    ::scidb::test::inventoryhelp::call operation open
    set help $::help::Priv(dlg)
    set ::scidb::test::inventoryhelp::destroyCalls 0
    proc ::scidb::test::inventoryhelp::observeDestroy {args} { incr ::scidb::test::inventoryhelp::destroyCalls }
    trace add execution ::help::Destroy enter ::scidb::test::inventoryhelp::observeDestroy
} -body {
    set result [::knowledge::RunAction help.close {}]
    update
    list $result [winfo exists $help] [winfo exists .application] $::scidb::test::inventoryhelp::destroyCalls
} -cleanup {
    trace remove execution ::help::Destroy enter ::scidb::test::inventoryhelp::observeDestroy
    rename ::scidb::test::inventoryhelp::observeDestroy {}
} -result {{Help closed} 0 1 1}

tcltest::cleanupTests
