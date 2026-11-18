# Headless checks of startup orchestration; persistence is tested by the native
# production-adapter integration test, and parity by test_player_cache.cpp.
package require tcltest
namespace eval ::ttk {
    proc style {args} {
        if {$args ne {theme names}} {error "unexpected theme call: $args"}
        return {clearlooks dark scidblue}
    }
}
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
# The sharded dictionary is the default. Contents are never read here:
# ::scidb::app::load is stubbed.
foreach part {ratings_utf8-1.ssp.zip ratings_utf8-2.ssp.zip \
		ratings_utf8-3.ssp.zip ratings_utf8-4.ssp.zip} {
	close [open [file join $cacheTestRoot $part] w]
}
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

# --- Deferred cache write -------------------------------------------------
# The write is not part of the startup path: load.tcl schedules it, and the
# scheduler itself waits until the main window is on screen. These helpers run
# the scheduled callbacks the way the event loop would.
proc captureAfter {} {
    set ::cacheTestAfter {}
    rename after ::cacheTestAfterReal
    proc after {args} { lappend ::cacheTestAfter $args }
}
proc releaseAfter {} {
    rename after {}
    rename ::cacheTestAfterReal after
}
proc drainDeferred {{limit 20}} {
    for {set guard 0} {$guard < $limit && [llength $::cacheTestAfter]} {incr guard} {
        set scheduled $::cacheTestAfter
        set ::cacheTestAfter {}
        foreach callback $scheduled { uplevel #0 [lindex $callback end] }
    }
}
# The background dictionary load is complete when the coroutine has removed
# itself and DataLoaded is on; the deferred cache write is complete when the
# cache-write call has been recorded. Run the scheduled callbacks the event
# loop would run until the named signal holds, instead of guessing a number of
# turns. This is a completion signal, not a longer sleep.
proc drainUntil {condition {limit 500}} {
    for {set guard 0} {$guard < $limit} {incr guard} {
        if {[uplevel 1 [list expr $condition]]} { return 1 }
        if {![llength $::cacheTestAfter]} { break }
        drainDeferred 1
    }
    return [uplevel 1 [list expr $condition]]
}
proc cacheWritten? {} {
    expr {[lsearch -index 0 -exact $::cacheTestCalls cache-write] >= 0}
}
proc runCacheLoadDraining {options hit {error {}}} {
    captureAfter
    try {
        runCacheLoad $options $hit $error
        drainDeferred
    } finally {
        releaseAfter
    }
    return [lmap row $::cacheTestCalls { lindex $row 0 }]
}

tcltest::test cache-load-miss {miss retains every parse and defers the write} -body {
    runCacheLoad {} 0
} -result {eco cache-read ssp ssp ssp ssp ssp comp fide ips dwz ecf iccf wiki wiki cgdc site done}
tcltest::test cache-load-miss-write {the deferred write still writes the cache} -body {
    lrange [runCacheLoadDraining {} 0] end-1 end
} -result {done cache-write}
tcltest::test cache-load-write-after-window {the write waits for the mapped main window} -body {
    # Stand-in for Tk: the window exists but is not on screen yet.
    set ::cacheTestMapped 0
    proc winfo {option args} {
        switch $option {
            exists { return 1 }
            ismapped { return $::cacheTestMapped }
        }
        error "unexpected winfo $option"
    }
    captureAfter
    try {
        runCacheLoad {} 0
        drainDeferred
        set early [expr {[cacheWritten?] ? "wrote-too-early" : "waited"}]
        set ::cacheTestMapped 1
        if {![drainUntil {[cacheWritten?]}]} {
            error "deferred cache write did not complete"
        }
        list $early [expr {[cacheWritten?] ? "written" : "missing"}]
    } finally {
        rename winfo {}
        releaseAfter
    }
} -result {waited written}
tcltest::test cache-load-hit {hit bypasses player/site parsing} -body {
    runCacheLoad {} 1
} -result {eco cache-read done}
tcltest::test cache-load-fast {fast-load neither reads nor writes player cache} -body {
    runCacheLoad fast-load 1
} -result {eco done}
tcltest::test cache-load-elo {elo-only keeps its original parse behavior} -body {
    lrange [runCacheLoadDraining elo-only 0] end-1 end
} -result {done cache-write}
tcltest::test cache-load-manifest {shipped and user rating locations are both tracked} -body {
    runCacheLoad {} 1
    lmap p $::load::CacheSources { string range $p [expr {[string length $::cacheTestRoot]+1}] end }
} -result {ratings_utf8-1.ssp.zip ratings_utf8-2.ssp.zip ratings_utf8-3.ssp.zip ratings_utf8-4.ssp.zip ratings-additional.ssp engines.txt players_list.zip ratings/fide-players.txt ips-ratings.txt dwz-ratings.txt ecf-ratings.txt iccf-ratings.txt ratings/dwz-ratings.txt ratings/ecf-ratings.txt ratings/iccf-ratings.txt wikipedia-de.txt wikipedia-en.txt chessgames.com.zip cities.txt}
tcltest::test cache-load-option-manifest {elo-only omits other ratings from fingerprint} -body {
    runCacheLoad elo-only 1
    lmap p $::load::CacheSources { file tail $p }
} -result {ratings_utf8-1.ssp.zip ratings_utf8-2.ssp.zip ratings_utf8-3.ssp.zip ratings_utf8-4.ssp.zip ratings-additional.ssp engines.txt players_list.zip fide-players.txt wikipedia-de.txt wikipedia-en.txt chessgames.com.zip cities.txt}
tcltest::test cache-load-errors {parse failures do not produce reusable partial caches} -body {
    runCacheLoadDraining {} 0 fide
} -result {eco cache-read ssp ssp ssp ssp ssp comp fide ips dwz ecf iccf wiki wiki cgdc site done}
tcltest::test cache-load-user-fide {readable user list replaces shipped FIDE input} -body {
    file mkdir [file join $cacheTestRoot ratings]
    close [open [file join $cacheTestRoot ratings fide-players.txt] w]
    runCacheLoadDraining {} 0
    file tail [lindex [lsearch -inline -index 0 $::cacheTestCalls fide] 1]
} -result fide-players.txt
# Inspect actual loader calls, not the fingerprint's deliberately duplicated names.
tcltest::test cache-load-rating-precedence {each federation loads once, preferring the user copy} -body {
    set observed {}
    foreach installed {0 1 0} {
        foreach type {dwz ecf iccf} {
            set path [file join $cacheTestRoot ratings $type-ratings.txt]
            if {$installed} { close [open $path w] } else { file delete $path }
        }
        runCacheLoadDraining {} 0
        set ratings {}
        foreach call $::cacheTestCalls {
            if {[lindex $call 0] in {dwz ecf iccf installed}} {
                lappend ratings [list [lindex $call 0] [string range [lindex $call 1] \
                    [expr {[string length $::cacheTestRoot]+1}] end]]
            }
        }
        lappend observed $ratings
    }
    set observed
} -result {{{dwz dwz-ratings.txt} {ecf ecf-ratings.txt} {iccf iccf-ratings.txt}} {{installed ratings/dwz-ratings.txt} {installed ratings/ecf-ratings.txt} {installed ratings/iccf-ratings.txt}} {{dwz dwz-ratings.txt} {ecf ecf-ratings.txt} {iccf iccf-ratings.txt}}}
# Background startup yields between dictionary files, but a native consumer
# must still see the complete dictionary, never the partially loaded prefix.
foreach mode {background consumer} {
    tcltest::test cache-load-chunks-$mode {background chunks preserve load order and synchronous first use} -setup {
        proc winfo {args} {return 1}
        namespace eval ::scidb::engine {
            proc info {} {return $::load::DataLoaded}
        }
        captureAfter
    } -body {
        runCacheLoad {} 0
        ::load::ensureEco
        ::load::startBackgroundData
        # The deferral means no dictionary chunk has run yet: startBackgroundData
        # only handed the first turn to the event loop.
        set partial [list $::load::DataLoaded [lmap c $::cacheTestCalls {lindex $c 0}]]
        if {$mode eq "consumer"} {
            set complete [::scidb::engine::info]
        } else {
            if {![drainUntil {[llength [info commands ::load::DataLoader]] == 0 && $::load::DataLoaded}]} {
                error "background dictionary load did not complete"
            }
            set complete $::load::DataLoaded
        }
        if {![drainUntil {[cacheWritten?]}]} {
            error "deferred cache write did not complete"
        }
        list $partial $complete [llength [info commands ::load::DataLoader]] \
            [lmap c $::cacheTestCalls {lindex $c 0}] \
            [trace info execution ::scidb::engine::info]
    } -cleanup {
        rename winfo {}
        rename ::scidb::engine::info {}
        releaseAfter
} -result {{0 eco} 1 0 {eco cache-read ssp ssp ssp ssp ssp comp fide ips dwz ecf iccf wiki wiki cgdc site done cache-write} {}}

# Installs made before the shards existed only ship the monolithic file.
tcltest::test cache-load-legacy-dictionary {monolithic installs still load} -body {
    file delete [file join $cacheTestRoot ratings_utf8-1.ssp.zip]
    set calls [runCacheLoad {} 0]
    close [open [file join $cacheTestRoot ratings_utf8-1.ssp.zip] w]
    lrange $calls 0 6
} -result {eco cache-read ssp ssp comp fide ips}
}
file delete -force $cacheTestRoot
tcltest::cleanupTests
