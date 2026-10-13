# Headless checks of startup orchestration; persistence is tested by the native
# production-adapter integration test, and parity by test_player_cache.cpp.
package require tcltest
namespace eval ::util { proc source {args} {} }
namespace eval ::splash { proc print {args} {} }
namespace eval ::log { proc open {args} {} }
namespace eval ::debuglog { proc log {args} {} }
namespace eval ::scidb::themes { proc update {} {} }
namespace eval ::process {
    proc testOption {name} { expr {$name in $::cacheTestOptions} }
}
namespace eval ::scidb::app {
    proc load {type args} {
        lappend ::cacheTestCalls [linsert $args 0 $type]
        switch $type {
            cache-read { return $::cacheTestHit }
            cache-write { return 1 }
        }
        if {$type eq $::cacheTestError} { error "fixture read error" }
    }
}
set cacheTestRoot [file join [tcltest::temporaryDirectory] cache-load-[pid]]
file mkdir $cacheTestRoot
namespace eval ::scidb::dir {}
foreach n {user config data share} { set ::scidb::dir::$n $cacheTestRoot }
set cacheTestScript [file join [file dirname [info script]] .. tcl load.tcl]
proc runCacheLoad {options hit {error {}}} {
    set ::cacheTestOptions $options
    set ::cacheTestHit $hit
    set ::cacheTestError $error
    set ::cacheTestCalls {}
    uplevel #0 [list source $::cacheTestScript]
    return [lmap row $::cacheTestCalls { lindex $row 0 }]
}
tcltest::test cache-load-miss {miss retains every parse and writes after done} -body {
    runCacheLoad {} 0
} -result {eco cache-read ssp ssp comp fide ips dwz ecf iccf wiki wiki cgdc site done cache-write}
tcltest::test cache-load-hit {hit bypasses player/site parsing} -body {
    runCacheLoad {} 1
} -result {eco cache-read done}
tcltest::test cache-load-fast {fast-load neither reads nor writes player cache} -body {
    runCacheLoad fast-load 1
} -result {eco done}
tcltest::test cache-load-elo {elo-only keeps its original parse behavior} -body {
    runCacheLoad elo-only 0
} -result {eco cache-read ssp ssp comp fide wiki wiki cgdc site done cache-write}
tcltest::test cache-load-manifest {own FIDE, engine, links and city sources tracked} -body {
    runCacheLoad {} 1
    lmap p $::load::CacheSources { file tail $p }
} -result {ratings_utf8.ssp.zip ratings-additional.ssp engines.txt players_list.zip fide-players.txt ips-ratings.txt dwz-ratings.txt ecf-ratings.txt iccf-ratings.txt wikipedia-de.txt wikipedia-en.txt chessgames.com.zip cities.txt}
tcltest::test cache-load-option-manifest {elo-only omits other ratings from fingerprint} -body {
    runCacheLoad elo-only 1
    lmap p $::load::CacheSources { file tail $p }
} -result {ratings_utf8.ssp.zip ratings-additional.ssp engines.txt players_list.zip fide-players.txt wikipedia-de.txt wikipedia-en.txt chessgames.com.zip cities.txt}
tcltest::test cache-load-errors {parse failures do not produce reusable partial caches} -body {
    runCacheLoad {} 0 fide
} -result {eco cache-read ssp ssp comp fide ips dwz ecf iccf wiki wiki cgdc site done}
tcltest::test cache-load-user-fide {readable user list replaces shipped FIDE input} -body {
    file mkdir [file join $cacheTestRoot ratings]
    close [open [file join $cacheTestRoot ratings fide-players.txt] w]
    runCacheLoad {} 0
    file tail [lindex [lsearch -inline -index 0 $::cacheTestCalls fide] 1]
} -result fide-players.txt
file delete -force $cacheTestRoot
tcltest::cleanupTests
