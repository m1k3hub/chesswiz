package require tcltest 2.5

# G36 regression: the Discover Databases scan froze the UI on a large
# folder tree (run8: 40 s "Not Responding" at 289 folders on Windows).
# The incremental scanner's time budget must apply *inside* one folder's
# entry list too, or a folder that scans slowly (virus scanner, cloud
# folders) still locks the event loop for its whole duration.  These
# tests scan a ~2000-folder tree in which one folder holds 240 database
# candidates at ~3 ms per header probe (stubbed, non-yielding) and assert
# that an `after 0` probe is answered within 200 ms and a 1 ms heartbeat
# never starves, that the incremental results equal a synchronous scan,
# and that Stop cuts through a single slow folder promptly.

namespace eval ::discoverRespTest {
    variable sourceDir [file normalize [file join [file dirname [info script]] .. tcl]]
    variable tempDir

    proc writeFile {path data} {
        file mkdir [file dirname $path]
        set fh [open $path wb]
        fconfigure $fh -translation binary
        puts -nonewline $fh $data
        close $fh
    }

    proc buildTree {root} {
        file mkdir $root
        for {set g 0} {$g < 40} {incr g} {
            for {set d 0} {$d < 50} {incr d} {
                set dir [file join $root group$g dir$d]
                file mkdir $dir
                writeFile [file join $dir notes.txt] "hello"
            }
            writeFile [file join $root group$g dir0 base$g.sci] "Scidb.i\x00\x01\x02"
        }
        # the heavy folder: 240 database candidates within one folder visit
        for {set i 0} {$i < 240} {incr i} {
            writeFile [file join $root group10 dir25 f$i.sci] "Scidb.i\x00\x01\x02"
        }
    }

    # Builds the tree, loads the scanner into a stubbed interp, and sets
    # $root there to the scan root (the whole tree, or the slow folder).
    proc setup {{subtree {}}} {
        variable sourceDir
        variable tempDir
        set tempDir [file join [file dirname [info script]] tmp-app discover-resp-[pid]]
        buildTree [file join $tempDir tree]
        interp create discoverResp
        discoverResp eval {namespace eval ::util {proc source {args} {}}}
        discoverResp eval [list source [file join $sourceDir app-database-discover.tcl]]
        discoverResp eval {
            namespace eval ::scidb::dir {}
            set ::scidb::dir::home /nonexistent
            namespace eval ::scidb::misc {}
            # The real command reads the database header; the scanner only
            # needs a stable value for the Games column.
            proc ::scidb::misc::size {path} { return 42 }
            # A Windows folder with a virus scanner costs real, non-yielding
            # time per header probe; nothing here may run the event loop.
            rename ::application::database::discover::_header \
                ::application::database::discover::_realHeader
            proc ::application::database::discover::_header {path} {
                set t [clock milliseconds]
                while {[clock milliseconds] - $t < 3} {}
                return [::application::database::discover::_realHeader $path]
            }
        }
        set root [file join $tempDir tree]
        if {[llength $subtree]} { set root [file join $root {*}$subtree] }
        discoverResp eval [list set root $root]
    }

    proc cleanup {} {
        variable tempDir
        catch { interp delete discoverResp }
        catch { file delete -force $tempDir }
    }
}

tcltest::test discover-resp-gaps {scan yields inside one folder: probes answer within 200 ms, progress flows, results match the sync scan} -setup {
    ::discoverRespTest::setup
} -body {
    set report [discoverResp eval {
        set probes 0
        set maxLatency 0
        set beats 0
        set maxGap 0
        set probing 1
        set doneFlag 0
        proc ::probe {} {
            variable probing
            if {!$probing} { return }
            set t0 [clock milliseconds]
            after 0 [list ::probeAnswer $t0]
            after 10 ::probe
        }
        proc ::probeAnswer {t0} {
            variable probes
            variable maxLatency
            set d [expr {[clock milliseconds] - $t0}]
            if {$d > $maxLatency} { set maxLatency $d }
            incr probes
        }
        proc ::beat {} {
            variable probing
            variable beats
            variable maxGap
            variable lastBeat
            if {!$probing} { return }
            set now [clock milliseconds]
            if {[info exists lastBeat]} {
                set gap [expr {$now - $lastBeat}]
                if {$gap > $maxGap} { set maxGap $gap }
            }
            set lastBeat $now
            incr beats
            after 1 ::beat
        }
        set progressCalls 0
        proc ::progress {dirs found} {
            variable progressCalls
            incr progressCalls
        }
        proc ::scanDone {results} {
            variable incrResults
            variable doneFlag
            set incrResults $results
            set doneFlag 1
        }
        ::probe
        ::beat
        ::application::database::discover::start [list $root] 6 1 ::progress ::scanDone
        vwait doneFlag
        set probing 0
        set syncResults [::application::database::discover::scanSync [list $root] 6 1]
        list $probes $maxLatency $beats $maxGap $progressCalls \
            [llength $incrResults] \
            [expr {[lsort $incrResults] eq [lsort $syncResults]}]
    }]
    lassign $report probes maxLatency beats maxGap progressCalls count equal
    list \
        [expr {$probes >= 10 && $beats >= 10}] \
        [expr {$maxLatency < 200}] \
        [expr {$maxGap < 200}] \
        [expr {$progressCalls >= 2}] \
        [expr {$count > 0}] \
        $equal
} -cleanup {
    ::discoverRespTest::cleanup
} -result {1 1 1 1 1 1}

tcltest::test discover-resp-cancel {stop cuts through a single slow folder within 200 ms} -setup {
    ::discoverRespTest::setup {group10 dir25}
} -body {
    set report [discoverResp eval {
        set doneFlag 0
        proc ::progress {dirs found} {}
        proc ::scanDone {results} {
            variable doneFlag
            variable stoppedAt
            variable cancelLatency
            variable cancelResults
            set cancelLatency [expr {[clock milliseconds] - $stoppedAt}]
            set cancelResults $results
            set doneFlag 1
        }
        ::application::database::discover::start [list $root] 6 1 ::progress ::scanDone
        after 10 {
            set stoppedAt [clock milliseconds]
            ::application::database::discover::stop
        }
        vwait doneFlag
        list [expr {![::application::database::discover::scanning?]}] \
            [expr {$cancelLatency < 200}] \
            [expr {[llength $cancelResults] <= 240}]
    }]
    set report
} -cleanup {
    ::discoverRespTest::cleanup
} -result {1 1 1}

tcltest::cleanupTests
