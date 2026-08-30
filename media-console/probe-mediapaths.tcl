#!/usr/bin/env tclsh
# ======================================================================
# probe-mediapaths — verify .cbm/.cms manifest stream references resolve
# to existing files across every .html folder of the ChessBase release
# (the cross-database media resolution of tcl_media_resolve.h).
#
# Usage:
#   xvfb-run -a ./src/media_console media-console/probe-mediapaths.tcl \
#       ["/path/to/<base>.cbh" [variant]]
#
# Without arguments the CB Light Database fixture is used.
#
# Exit status:
#   0 = every in-release media reference (pictures/audio/video) resolved
#       exists=1; external stream refs (type 4, e.g. pointing at the CBM
#       disc) are reported but do not fail the run.
#   1 = at least one in-release reference missing, or the load failed.
# ======================================================================

package require Tcl 8.5

proc ::mcProgress {args} {}

set dbFile [lindex $argv 0]
if {$dbFile eq ""} {
    set dbFile [file nativename [file join $::env(HOME) Documents ChessBase Bases "CB Light Database.cbh"]]
}
set variant [lindex $argv 1]
if {$variant eq ""} { set variant Normal }
set base [file nativename $dbFile]

if {![file exists $base]} {
    puts "SKIP: fixture not found: $base"
    exit 0
}

set err [catch { ::scidb::db::load $base ::mcProgress progress-arg -readonly 1 } m]
puts "load=$err $m"
if {$err} { exit 1 }

set rows ""
set rc [catch { set rows [::scidb::db::mediaGallery $base $variant] } m2]
if {$rc} { puts "mediaGallery failed: $m2"; exit 1 }
puts "gallery rows=[llength $rows]"

set missing 0
set missingStream 0
set checked 0
foreach r $rows {
    lassign $r path type title mid
    set ex [file exists $path]
    incr checked
    if {!$ex} {
        if {$type == 4} {
            incr missingStream
            puts "  stream-missing (may live on the CBM disc): $path"
        } else {
            incr missing
            puts "  MISSING type=$type: $path"
        }
    }
}

puts "checked=$checked in-release-missing=$missing stream-missing=$missingStream"
if {$missing > 0} {
    puts "FAIL: $missing in-release media reference(s) unresolved"
    exit 1
}
puts "PASS: all in-release media references exist"
exit 0
