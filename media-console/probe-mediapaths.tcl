#!/usr/bin/env tclsh
# ======================================================================
# probe-mediapaths — verify .cbm/.cms manifest stream references resolve
# to existing files across every .html folder of the ChessBase release
# (the cross-database media resolution of tcl_media_resolve.h).
#
# Usage:
#   xvfb-run -a ./src/media_console media-console/probe-mediapaths.tcl \
#       "/path/to/<base>.cbh" \[variant\]
# ======================================================================

proc ::mcProgress {args} {}
set base "/media/michael-g-thomas/sas_mirror/fixt/cbm168/Data Collect/CBM168.cbh"
set err [catch { ::scidb::db::load $base ::mcProgress progress-arg -readonly 1 } m]
puts "load=$err $m"
set variant Normal
set rows ""
catch { set rows [::scidb::db::mediaGallery $base $variant] }
puts "gallery rows=[llength $rows]"
foreach r $rows {
	lassign $r path type title mid
	if {$type == 3 || $type == 4} { puts "  type=$type exists=[file exists $path] path=$path" }
}
catch { ::scidb::db::close $base }
exit 0

