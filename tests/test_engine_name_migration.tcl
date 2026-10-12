# Headless startup tests; run with tclsh tests/test_engine_name_migration.tcl.
package require Tcl 8.5
package require tcltest 2.5

# Load the real procedures without engine.tcl's Tk bindings and automatic setup.
set fp [open [file join [file dirname [info script]] .. tcl engine.tcl]]
set source [read $fp]
close $fp
namespace eval ::engine {}
foreach name {MigrateEngineCommands setup WriteEngineOptions} {
    set start [string first "proc $name " $source]
    if {$start < 0} { error "missing engine procedure $name" }
    set script ""
    foreach line [split [string range $source $start end] \n] {
        append script $line \n
        if {[info complete $script]} { break }
    }
    namespace eval ::engine $script
}
namespace eval ::options {
    variable Writer {}
    proc hookWriter {writer section} { set ::options::Writer [list $writer $section] }
    proc writeList {chan name} { puts $chan [list set $name [set $name]] }
}
namespace eval ::load {
    namespace eval mc { variable ReadingFile; set ReadingFile(engines) engines }
    proc source {file args} { uplevel #0 [list ::source $file] }
}
namespace eval ::scidb::file {}
namespace eval ::scidb::dir {}

proc sameEntry {actual expected} {
    if {[dict size $actual] != [dict size $expected]} { return 0 }
    dict for {key value} $expected {
        if {![dict exists $actual $key] || [dict get $actual $key] ne $value} { return 0 }
    }
    return 1
}

set scratch [file join [::tcltest::temporaryDirectory] engname-[pid]]
file mkdir $scratch
proc program {path} {
    set fp [open $path w]; puts $fp "fixture"; close $fp
    if {$::tcl_platform(platform) eq "unix"} { file attributes $path -permissions 0755 }
    return $path
}
proc entry {command} {
    dict create Name Custom Command $command Parameters {--hash 128} UserDefined 1 \
        Profiles:UCI {Personal {{Hash spin 128 16 1 1024}}} \
        Profiles:WB {Personal {hash 128}} Script:Default {} Directory /custom/workdir
}

foreach suffix {{} .exe} {
    tcltest::test migration-startup$suffix {startup repairs missing commands, retains profiles and persists} -setup {
        set old [file join $scratch "engine-scidb$suffix"]
        set new [program [file join $scratch "engine-chesswiz$suffix"]]
        set original [entry $old]
        set ::scidb::file::engines [file join $scratch engines.dat]
        set ::scidb::dir::share [file join $scratch absent-share]
        set fp [open $::scidb::file::engines w]
        puts $fp [list set ::engine::Engines [list $original]]
        close $fp
        set ::engine::Engines {}
        set ::options::Writer {}
    } -body {
        ::engine::setup
        set expected [list [dict replace $original Command $new]]
        set first [expr {$::engine::Engines eq $expected}]
        set writer $::options::Writer
        set fp [open $::scidb::file::engines w]
        [lindex $writer 0] $fp
        close $fp
        set ::engine::Engines {}
        source $::scidb::file::engines
        list $first $writer [sameEntry [lindex $::engine::Engines 0] [dict remove [lindex $expected 0] Script:Default]] \
            [::engine::MigrateEngineCommands]
    } -cleanup {
        file delete -force $new $::scidb::file::engines
    } -result {1 {::engine::WriteEngineOptions engines} 1 0}
}

tcltest::test migration-newer-defaults {migration also runs before merging newer bundled defaults} -setup {
    set old [file join $scratch newer-scidb]
    set new [program [file join $scratch newer-chesswiz]]
    set original [entry $old]
    set ::scidb::file::engines [file join $scratch engines.dat]
    set ::scidb::dir::share [file join $scratch share]
    file mkdir [file join $::scidb::dir::share engines]
    set shared [file join $::scidb::dir::share engines engines.dat]
    set fp [open $::scidb::file::engines w]
    puts $fp [list set ::engine::Engines [list $original]]
    close $fp
    set fp [open $shared w]; close $fp
    file mtime $shared [expr {[file mtime $::scidb::file::engines] + 10}]
    proc ::engine::LoadSharedConfiguration {file} { return {} }
    set ::engine::Engines {}
    set ::options::Writer {}
} -body {
    ::engine::setup
    list [sameEntry [lindex $::engine::Engines 0] [dict replace $original Command $new]] \
        $::options::Writer
} -cleanup {
    rename ::engine::LoadSharedConfiguration {}
    file delete -force $new $::scidb::file::engines $::scidb::dir::share
} -result {1 {::engine::WriteEngineOptions engines}}

tcltest::test migration-keeps-existing {a working old program wins over the sibling} -setup {
    set old [program [file join $scratch keep-scidb]]
    set new [program [file join $scratch keep-chesswiz]]
    set original [list [entry $old]]
    set ::engine::Engines $original
    set ::options::Writer {}
} -body {
    list [::engine::MigrateEngineCommands] [expr {$::engine::Engines eq $original}] $::options::Writer
} -cleanup {
    file delete -force $old $new
} -result {0 1 {}}

tcltest::test migration-guards {missing siblings, unrelated names and directories stay untouched} -setup {
    set new [program [file join $scratch unrelated-chesswiz]]
    file mkdir [file join $scratch directory-chesswiz]
    set original [list [entry [file join $scratch missing-scidb]] \
        [entry [file join $scratch unrelated]] [entry [file join $scratch directory-scidb]] \
        [entry [file join $scratch embedded-scidb-other]]]
    set ::engine::Engines $original
    set ::options::Writer {}
} -body {
    list [::engine::MigrateEngineCommands] [expr {$::engine::Engines eq $original}] $::options::Writer
} -cleanup {
    file delete -force $new [file join $scratch directory-chesswiz]
} -result {0 1 {}}

file delete -force $scratch
tcltest::cleanupTests
