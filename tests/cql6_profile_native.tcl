# A bounded native workload for callgrind. Run with the app-backed runner.
# Required: CQL6_NATIVE_DIR (copied triplets). Optional: CQL6_PROFILE_DATABASE,
# CQL6_PROFILE_GAMES, CQL6_PROFILE_SCRIPT, CQL6_PROFILE_VARIATIONS.
proc profileNop {args} {return 0}
proc profileReceive {result} {set ::profileResult $result}
if {![info exists ::env(CQL6_NATIVE_DIR)]} {error "set CQL6_NATIVE_DIR to copied triplets"}
set name twic_complete
set count 1200
set script {cql() check}
set variations 0
foreach {key variable} {CQL6_PROFILE_DATABASE name CQL6_PROFILE_GAMES count
                       CQL6_PROFILE_SCRIPT script CQL6_PROFILE_VARIATIONS variations} {
    if {[info exists ::env($key)]} {set $variable $::env($key)}
}
if {![string is integer -strict $count] || $count < 1} {error "invalid profile game count"}
set base [file normalize [file join $::env(CQL6_NATIVE_DIR) $name.sci]]
::scidb::db::load $base profileNop {} -readonly yes
if {$count > [::scidb::db::count games $base Normal]} {error "profile selection exceeds database"}
set view [::scidb::view::new $base Normal unused unused unused unused master slave]
set indices {}
for {set i 0} {$i < $count} {incr i} {lappend indices $i}
::scidb::view::setGames $base Normal $view $indices
set start [clock milliseconds]
set job [::scidb::cql6::search $base Normal $script -view $view -threads 1 \
    -variations $variations -command profileReceive]
set timeout [after 600000 {set ::profileResult timeout}]
vwait ::profileResult
after cancel $timeout
if {$::profileResult eq "timeout"} {::scidb::cql6::cancel $job;error "profile search timed out"}
if {![dict get $::profileResult ok]} {error [dict get $::profileResult error]}
if {[dict get $::profileResult games] != $count} {error "profile did not examine the selection"}
puts "$name games=$count matches=[llength [dict get $::profileResult matches]] elapsed_ms=[expr {[clock milliseconds]-$start}]"
::scidb::view::close $base Normal $view
::scidb::db::close $base
