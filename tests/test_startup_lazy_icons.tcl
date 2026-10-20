package require tcltest
namespace eval util {proc source {args} {}}
namespace eval splash {proc print {args} {}}
namespace eval load::mc {variable Loading {%s}; variable Icons icons}
namespace eval scidb::tk {proc image {args} {}}
set created 0
proc image {operation args} {
    if {$operation ne {create}} {return 16}
    incr ::created
    return image$::created
}
source [file join [file dirname [info script]] .. tcl icons.tcl]
tcltest::test lazy-icons-unread {unused icons are not decoded during startup} -body {
    set ::created
} -result 0
tcltest::test lazy-icons-first-use {first read creates a photo; repeat reads share it} -body {
    set before $::created
    set first $::icon::48x48::logo
    list [expr {$::created - $before}] [expr {$first eq $::icon::48x48::logo}]
} -result {1 1}
tcltest::test lazy-icons-toolbar {toolbar images and aliases retain their shared values} -body {
    set first $::icon::toolbarStart
    list [expr {$first eq $::icon::toolbarResume}] [llength $first]
} -result {1 3}
proc readIconAlias {} {
    upvar #0 ::icon::64x64::logo icon
    set first $icon
    return [expr {$first eq $icon}]
}
tcltest::test lazy-icons-upvar {a local alias still decodes its asset only once} -body {
    set before $::created
    list [readIconAlias] [expr {$::created - $before}]
} -result {1 1}
tcltest::test lazy-icons-array {array aliases retain identity and decode once} -body {
    set first $::icon::32x32::variant(Antichess)
    list [expr {$first eq $::icon::32x32::variant(Suicide)}] \
        [expr {$first eq $::icon::32x32::variant(Giveaway)}]
} -result {1 1}
tcltest::cleanupTests
