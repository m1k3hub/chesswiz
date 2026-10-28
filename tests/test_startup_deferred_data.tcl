# Headless orchestration test using the real startup loader.
package require tcltest
namespace eval ::ttk {
    proc style {args} {
        if {$args ne {theme names}} {error "unexpected theme call: $args"}
        return {clearlooks dark scidblue}
    }
}
namespace eval util {proc source {args} {}}
namespace eval splash {proc print {args} {}}
namespace eval log {proc open {args} {}}
namespace eval debuglog {proc log {args} {}}
namespace eval scidb::themes {proc update {} {}}
namespace eval process {proc testOption {name} {return 0}}
namespace eval scidb::app {
    proc load {type args} {
        lappend ::calls $type
        if {$type eq {cache-read}} {return $::hit}
        return 1
    }
}
namespace eval scidb::db {
    proc open {args} {lappend ::calls consumer; return opened}
}
namespace eval scidb::game {proc new {args} {lappend ::calls game}}
namespace eval scidb::dir {}
set fixture [file normalize [file join [file dirname [info script]] tmp-app deferred-data-[pid]]]
file mkdir $fixture
foreach dir {data user config share} {set ::scidb::dir::$dir $fixture}
set loader [file join [file dirname [info script]] .. tcl load.tcl]
set mapped 0
proc winfo {option w} {
    if {$w ne {.application}} {return 0}
    return [expr {$option eq {exists} || $::mapped}]
}
rename after realAfter
proc after {args} {lappend ::pending [lindex $args end]}
proc drain {} {
    for {set i 0} {$i < 5 && [llength $::pending]} {incr i} {
        set scripts $::pending
        set ::pending {}
        foreach script $scripts {uplevel #0 $script}
    }
}
proc startLoader {hit} {
    set ::hit $hit
    set ::calls {}
    set ::pending {}
    set ::mapped 0
    uplevel #0 [list source $::loader]
}
tcltest::test deferred-data-before-map {no dictionary reads before map or first use} -body {
    startLoader 0
    drain
    set ::calls
} -result {}
tcltest::test deferred-data-first-game {ECO precedes native empty-game initialization} -body {
    ::scidb::game::new
    set ::calls
} -result {eco game}
tcltest::test deferred-data-after-map {miss preserves load order and writes after finalization} -body {
    set ::mapped 1
    drain
    lrange $::calls 2 end
} -result {cache-read ssp ssp comp fide ips dwz ecf iccf wiki wiki cgdc site done cache-write}
tcltest::test deferred-data-first-use {database consumer gets complete cached data before entry} -body {
    startLoader 1
    set result [::scidb::db::open fixture]
    set ::mapped 1
    drain
    list $result $::calls
} -result {opened {eco cache-read done consumer}}
rename after {}
rename realAfter after
file delete -force $fixture
tcltest::cleanupTests
