# Explicit integration gate. Run from the repository root with the headless
# application runner; CQL6_NATIVE_DIR must contain copied native triplets.
namespace eval ::cql6native { variable done {}; variable timer {}; variable last 0; variable gaps {} }
proc ::cql6native::nop {args} { return 0 }
proc ::cql6native::receive {result} { variable done; set done $result }
proc ::cql6native::tick {} {
    variable last; variable gaps; variable timer
    set now [clock milliseconds]
    lappend gaps [expr {$now-$last}]
    set last $now
    set timer [after 20 ::cql6native::tick]
}
proc ::cql6native::run {base threads variations} {
    variable done; variable timer; variable last; variable gaps
    set done {}; set gaps {}; set last [clock milliseconds]
    set start $last
    set job [::scidb::cql6::search $base Normal {cql(gamenumber 1 20000) check} \
        -threads $threads -variations $variations -command ::cql6native::receive]
    set timer [after 20 ::cql6native::tick]
    set timeout [after 300000 {set ::cql6native::done timeout}]
    vwait ::cql6native::done
    after cancel $timeout; after cancel $timer
    if {$done eq "timeout"} {::scidb::cql6::cancel $job; error "native search timed out"}
    if {![dict get $done ok]} {error [dict get $done error]}
    set elapsed [expr {[clock milliseconds]-$start}]
    set gap [expr {[llength $gaps] ? [tcl::mathfunc::max {*}$gaps] : 0}]
    puts "[file tail $base] threads=$threads variations=$variations games=[dict get $done games] matches=[llength [dict get $done matches]] elapsed_ms=$elapsed max_timer_gap_ms=$gap"
    flush stdout
    return [dict get $done matches]
}
if {![info exists ::env(CQL6_NATIVE_DIR)]} {error "set CQL6_NATIVE_DIR to copied native databases"}
foreach name {twic_complete CCRL-4040 LumbrasGigabase_OTB} {
    set file [file normalize [file join $::env(CQL6_NATIVE_DIR) $name.sci]]
    ::scidb::db::load $file ::cql6native::nop {} -readonly yes
    foreach variations {0 1} {
        set one [::cql6native::run $file 1 $variations]
        set eight [::cql6native::run $file 8 $variations]
        if {$one ne $eight} {error "native matches/first_ply differ at 1/8 threads: $name variations=$variations"}
    }
    ::scidb::db::close $file
}
puts {PASS: native match identity and first_ply agree across worker counts}
