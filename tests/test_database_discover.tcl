package require tcltest 2.5

namespace eval ::discoverTest {
    variable sourceDir [file normalize [file join [file dirname [info script]] .. tcl]]
    variable tempDir

    proc setup {} {
        variable sourceDir
        variable tempDir
        set tempDir [tcltest::makeDirectory database-discover]
        interp create discover
        discover eval {namespace eval ::util {proc source {args} {}}}
        discover eval [list source [file join $sourceDir app-database-discover.tcl]]
        discover eval [list set tempDir $tempDir]
        discover eval {
            namespace eval ::scidb::dir {}
            set ::scidb::dir::home $tempDir
            namespace eval ::scidb::misc {}
            # The real command reads the database header; the scanner only
            # needs a stable value for the Games column.
            proc ::scidb::misc::size {path} { return 42 }
            proc writeFile {path data} {
                file mkdir [file dirname $path]
                set fh [open $path wb]
                fconfigure $fh -translation binary
                puts -nonewline $fh $data
                close $fh
            }
            set root [file join $tempDir tree]
            file mkdir $root
            writeFile [file join $root a.sci] "Scidb.i\x00\x01\x02"
            writeFile [file join $root a.scg] "companion, not a database"
            writeFile [file join $root b.pgn] "\[Event \"x\"\]\n1. e4 e5\n"
            writeFile [file join $root c.cbh] "\x00\x00\x2c\x00\x2e\x01payload"
            writeFile [file join $root bad.sci] "not a database at all"
            writeFile [file join $root sub d.si4] "Scid.si4\x00"
            writeFile [file join $root sub deeper e.si3] "Scid.si3\x00"
            writeFile [file join $root .git f.sci] "Scidb.i\x00"
        }
    }

    proc cleanup {} {
        interp delete discover
        tcltest::removeDirectory database-discover
    }
}

tcltest::test discover-ext {multi-part suffixes are recognised} -setup {
    ::discoverTest::setup
} -body {
    discover eval {
        list \
            [::application::database::discover::_ext a.pgn] \
            [::application::database::discover::_ext a.PGN.GZ] \
            [::application::database::discover::_ext a.si4] \
            [::application::database::discover::_ext a.bpgn.gz]
    }
} -cleanup {::discoverTest::cleanup} -result {pgn pgn.gz si4 bpgn.gz}

tcltest::test discover-classify-magic {binary formats are confirmed by magic bytes; companions are not databases} -setup {
    ::discoverTest::setup
} -body {
    discover eval {
        set root [file join $tempDir tree]
        list \
            [expr {[llength [::application::database::discover::classify [file join $root a.sci]]] > 0}] \
            [expr {[llength [::application::database::discover::classify [file join $root bad.sci]]] > 0}] \
            [expr {[llength [::application::database::discover::classify [file join $root a.scg]]] > 0}] \
            [expr {[llength [::application::database::discover::classify [file join $root c.cbh]]] > 0}]
    }
} -cleanup {::discoverTest::cleanup} -result {1 0 0 1}

tcltest::test discover-classify-pgn {PGN files are only listed when enabled} -setup {
    ::discoverTest::setup
} -body {
    discover eval {
        set p [file join $tempDir tree b.pgn]
        list \
            [expr {[llength [::application::database::discover::classify $p 1]] > 0}] \
            [expr {[llength [::application::database::discover::classify $p 0]] > 0}]
    }
} -cleanup {::discoverTest::cleanup} -result {1 0}

tcltest::test discover-scan {the walk finds primary databases, honours depth and the denylist} -setup {
    ::discoverTest::setup
} -body {
    discover eval {
        set root [file join $tempDir tree]
        set names {}
        foreach e [::application::database::discover::scanSync [list $root] 6 1] {
            lappend names [file tail [lindex $e 2]]
        }
        lsort $names
    }
} -cleanup {::discoverTest::cleanup} -result {a.sci b.pgn c.cbh d.si4 e.si3}

tcltest::test discover-scan-depth {maximum depth prunes deeper directories} -setup {
    ::discoverTest::setup
} -body {
    discover eval {
        set root [file join $tempDir tree]
        set names {}
        foreach e [::application::database::discover::scanSync [list $root] 1 1] {
            lappend names [file tail [lindex $e 2]]
        }
        lsort $names
    }
} -cleanup {::discoverTest::cleanup} -result {a.sci b.pgn c.cbh d.si4}

tcltest::test discover-scan-pgn-off {PGN files can be excluded from a scan} -setup {
    ::discoverTest::setup
} -body {
    discover eval {
        set root [file join $tempDir tree]
        set names {}
        foreach e [::application::database::discover::scanSync [list $root] 6 0] {
            lappend names [file tail [lindex $e 2]]
        }
        lsort $names
    }
} -cleanup {::discoverTest::cleanup} -result {a.sci c.cbh d.si4 e.si3}

tcltest::test discover-denied {pseudo-filesystems and VCS directories are skipped} -setup {
    ::discoverTest::setup
} -body {
    discover eval {
        list \
            [::application::database::discover::_denied /proc/sys] \
            [::application::database::discover::_denied /sys/devices] \
            [::application::database::discover::_denied [file join $tempDir tree .git]] \
            [::application::database::discover::_denied [file join $tempDir tree sub]]
    }
} -cleanup {::discoverTest::cleanup} -result {1 1 1 0}

tcltest::test discover-results-shape {a result carries ext, label, path, size and games} -setup {
    ::discoverTest::setup
} -body {
    discover eval {
        set e [::application::database::discover::classify \
            [file join $tempDir tree a.sci] 1]
        list [lindex $e 0] [lindex $e 1] \
            [file tail [lindex $e 2]] [expr {[lindex $e 3] > 0}] [lindex $e 4]
    }
} -cleanup {::discoverTest::cleanup} -result {sci {Scidb database} a.sci 1 42}

tcltest::cleanupTests
