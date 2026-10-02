# Native half of the pristine comparison, using the exact exported selections.
proc cql6oracleNop {args} {return 0}
proc cql6oracleReceive {result} {set ::cql6oracleResult $result}
if {![info exists ::env(CQL6_NATIVE_DIR)] || ![info exists ::env(CQL6_COMPARE_DIR)]} {
    error "set CQL6_NATIVE_DIR and CQL6_COMPARE_DIR"
}
file mkdir $::env(CQL6_COMPARE_DIR)
set bodies {check mate initial terminal {[a]<=6} {move previous enpassant} {sort "material" ([a]<=6)}}
set scripts [lmap body $bodies {format {cql() %s} $body}]
foreach name {twic_complete CCRL-4040 LumbrasGigabase_OTB} {
    set base [file normalize [file join $::env(CQL6_NATIVE_DIR) $name.sci]]
    ::scidb::db::load $base cql6oracleNop {} -readonly yes
    set view [::scidb::view::new $base Normal unused unused unused unused master slave]
    set indices {}
    for {set i 0} {$i<20000} {incr i} {lappend indices $i}
    ::scidb::view::setGames $base Normal $view $indices
    foreach variations {0 1} {foreach threads {1 8} {
        unset -nocomplain ::cql6oracleResult
        set job [::scidb::cql6::search $base Normal [lindex $scripts 0] -scripts [lrange $scripts 1 end] \
            -view $view -threads $threads -variations $variations -command cql6oracleReceive]
        set timeout [after 300000 {set ::cql6oracleResult timeout}]
        vwait ::cql6oracleResult
        after cancel $timeout
        if {$::cql6oracleResult eq "timeout"} {::scidb::cql6::cancel $job;error "native comparison timed out"}
        if {![dict get $::cql6oracleResult ok]} {error [dict get $::cql6oracleResult error]}
        set files {}
        for {set s 0} {$s<[llength $scripts]} {incr s} {
            lappend files [open [file join $::env(CQL6_COMPARE_DIR) $name-$variations-$threads-$s.tsv] w]
        }
        foreach match [dict get $::cql6oracleResult matches] {
            puts [lindex $files [dict get $match script]] "[dict get $match game]\t[dict get $match first_ply]"
        }
        foreach file $files {close $file}
        puts "$name variations=$variations threads=$threads games=[dict get $::cql6oracleResult games] matches=[llength [dict get $::cql6oracleResult matches]]"
        flush stdout
    }}
    ::scidb::view::close $base Normal $view
    ::scidb::db::close $base
}
