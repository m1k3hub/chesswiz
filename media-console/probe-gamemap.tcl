# Validation probe: per-game media for REGULAR games via tag_game anchors
# (docs/formats/CBM_FORMAT_DESIGN.md §7.6). Run via:
#   xvfb-run -a ./src/media_console media-console/probe-gamemap.tcl
package require Tcl 8.6

proc ::mcProgress {args} {}

set base [file nativename [file join $::env(HOME) Documents ChessBase Bases "CB Light Database.cbh"]]
set variant Normal

set err [catch { ::scidb::db::load $base ::mcProgress progress-arg -readonly 1 } cursor]
puts "load err=$err $cursor"
if {$err} { exit 1 }

set n [::scidb::db::count games $base $variant]
puts "games=$n"
set failures 0
proc check {cond msg} {
	if {[catch {uplevel 1 [list expr $cond]} ok]} { set ok 0 }
	if {$ok} { puts "  OK  $msg" } else { puts "  FAIL $msg"; incr ::failures }
}

# Ground truth from C++ probe: regular game 12038 = Topalov, Veselin -
# Anand, Viswanathan, event="Grand Slam Final", 2008.9, round 4 — the exact
# game the Bilbao report anchors via CBLink (§7.3 table + .cbg strings).
set i 12038
set rows {}
catch { set rows [::scidb::db::mediaFiles $base $variant $i] }
check {[llength $rows] > 0} "game 12038 (Topalov-Anand, Grand Slam Final 2008 r4) carries media ([llength $rows] rows)"
set title [lindex [lindex $rows 0] 2]
check {$title eq "Grand Slam Final"} "mapped rows carry the anchor event (title='$title')"

# Every mapped picture must exist on disc in the .html sibling folder.
set missing 0
foreach r $rows {
	lassign $r path type title2 mediaId inline
	if {$type == 1 && ![file exists $path]} { incr missing }
}
check {$missing == 0} "all mapped pictures exist on disc (missing=$missing)"

# The mapped subset must come from the Bilbao report (rec 12059): its block
# media (after the Topalov-Anand anchor) is a subset of the report's media.
set gtrows [::scidb::db::mediaFiles $base $variant 12059]
foreach r $rows {
	lassign $r path type t m inline
	if {[lsearch -glob [concat {*}[lmap g $gtrows {list [lindex $g 0]}]] $path] < 0} {
		check {0} "row $path stems from the Bilbao report"
	}
}
puts "  (report rec 12059 has [llength $gtrows] refs incl. header media)"

# Sweep: count regular games mapped via tag_game anchors.
set mapped 0
array set byTitle {}
set mappedIdx {}
set t0 [clock milliseconds]
for {set i2 0} {$i2 < $n} {incr i2} {
	if {$i2 == 0 || $i2 == 12059 || $i2 == 12128 || $i2 == 12645 || $i2 == 12676
		|| $i2 == 12768 || $i2 == 12980 || $i2 == 13138 || $i2 == 13236 || $i2 == 13442} {
		continue	;# guiding-text records themselves
	}
	set rr [::scidb::db::mediaFiles $base $variant $i2]
	if {[llength $rr]} {
		incr mapped
		lappend mappedIdx $i2
	}
}
set dt [expr {[clock milliseconds] - $t0}]
puts "sweep: $mapped regular games carry tag_game-mapped media (${dt}ms)"
puts "mapped indices: [lrange $mappedIdx 0 24]"
puts "mapped indices: [lrange $mappedIdx 0 24]"
foreach i3 [lrange $mappedIdx 0 5] {
	set rr [::scidb::db::mediaFiles $base $variant $i3]
}
check {$mapped == 25} "sweep found the fixture mapping population (25; got $mapped)"
exit 0