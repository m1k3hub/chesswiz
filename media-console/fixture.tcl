#!/usr/bin/env tclsh
# media-console e2e probe: open the real CB Light Database.cbh and exercise
# ::scidb::db::mediaFiles across all games, reporting guiding-text games that
# yield per-game media (the new guiding-text HTML extraction fallback).
#
# Run with the headless media-console under Xvfb:
#   xvfb-run -a ./src/media_console media-console/fixture.tcl

# load() requires a valid progress command (empty string crashes Progress).
# Provide a no-op that swallows every progress event/arg.
proc ::mcProgress {args} {}

set dbFile [lindex $argv 0]
if {$dbFile eq ""} {
    set dbFile [file join $::env(HOME) Documents ChessBase Bases "CB Light Database.cbh"]
}
set db [file nativename $dbFile]

puts "Opening: $db"
set err [catch { ::scidb::db::load $db ::mcProgress progress-arg -readonly 1 } cursor]
puts "load err=$err cursor=$cursor"
if {$err} {
    puts "LOAD FAILED: $cursor"
    exit 1
}

# db name is the path used to address the cursor
set base $db
set variant Normal

set err [catch { ::scidb::db::count games $base $variant } n]
puts "count err=$err n=$n"
if {$err || $n == 0} { puts "no games"; exit 0 }

set found 0
set withMedia 0
set totalMediaRefs 0
set mediaGameIndices {}
set detail {}

for {set i 0} {$i < $n} {incr i} {
    catch { ::scidb::db::get gameInfo $i -1 $base $variant } info
    # gameInfo is a flat list; fields: name white black elo... capture names
    set white [lindex $info 3]
    set black [lindex $info 5]
    set event [lindex $info 7]

    set entries [catch { ::scidb::db::mediaFiles $base $variant $i } ents]
    if {$entries || ![llength $ents]} { continue }

    lappend mediaGameIndices $i
    incr withMedia
    set refs {}
    set ok 0
    foreach row $ents {
        lassign $row path type title mediaId inline
        lappend refs "$type:$path"
        incr totalMediaRefs
        if {[file exists $path]} { incr ok }
    }
    lappend detail [list $i $white $black $event [llength $ents] $ok $refs]
    if {$found < 8} {
        puts "  game $i led-by $white vs $black ($event): [llength $ents] media, $ok on disk"
        foreach r $refs { puts "     $r" }
        incr found
    }
}

puts ""
puts "=== SUMMARY ==="
puts "  games scanned  : $n"
puts "  games w/ media : $withMedia"
puts "  total refs     : $totalMediaRefs"
puts "  indices        : $mediaGameIndices"
if {[llength $detail]} {
    puts ""
    puts "=== per-game detail (index white black event nrefs ok) ==="
    foreach d $detail {
        lassign $d i w b e tm ok
        if {$tm != $ok} {
            puts "  [$i] $w vs $b ($e): $tm refs but only $ok on disk"
        }
    }
    puts "(only mismatches listed; silent means all refs on disk)"
}
exit 0
