# Explicit oracle inputs from copies of native databases; nulls stay null moves.
proc cql6exportNop {args} {return 0}
if {![info exists ::env(CQL6_NATIVE_DIR)] || ![info exists ::env(CQL6_EXPORT_DIR)]} {
    error "set CQL6_NATIVE_DIR and CQL6_EXPORT_DIR"
}
file mkdir $::env(CQL6_EXPORT_DIR)
foreach name {twic_complete CCRL-4040 LumbrasGigabase_OTB} {
    set base [file normalize [file join $::env(CQL6_NATIVE_DIR) $name.sci]]
    ::scidb::db::load $base cql6exportNop {} -readonly yes
    set view [::scidb::view::new $base Normal unused unused unused unused master slave]
    set indices {}
    for {set index 0} {$index<20000} {incr index} {lappend indices $index}
    ::scidb::view::setGames $base Normal $view $indices
    set mapping [open [file join $::env(CQL6_EXPORT_DIR) $name.indices] w]
    for {set row 0} {$row<20000} {incr row} {
        puts $mapping [::scidb::db::get gameNumber $base Normal $row $view]
    }
    close $mapping
    set output [file join $::env(CQL6_EXPORT_DIR) $name.pgn]
    set start [clock milliseconds]
    set result [::scidb::view::export $base Normal $view $output 8191 0 utf-8 0 {} {} \
        cql6exportNop {} cql6exportNop {}]
    puts "$name export=$result elapsed_ms=[expr {[clock milliseconds]-$start}] bytes=[file size $output]"
    flush stdout
    ::scidb::view::close $base Normal $view
    ::scidb::db::close $base
}
