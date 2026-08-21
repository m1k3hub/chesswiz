#!/usr/bin/env tclsh
# Import a PGN file into a .sci database using the tkscidb binary,
# then compute game fingerprints and write a .scm companion manifest.
#
# Usage: setup-test.tcl <tkscidb-binary> <pgn-file> <output-rootname>

package require Tk 8.6
package require tkscidb

set argv2 $argv
lassign $argv2 pgnFile outRoot

if {![info exists pgnFile] || ![info exists outRoot]} {
    puts stderr "usage: $argv0 <pgn-file> <output-rootname>"
    exit 1
}

# Create the database (sci format)
set dbPath ${outRoot}.sci
if {[file exists $dbPath]} { file delete -force ${outRoot}.sci ${outRoot}.scg ${outRoot}.scn }

# Open a new database for import
::scidb::db::create $outRoot sci Normal

# Import the PGN
set logFile /tmp/scidb-import-log.txt
::scidb::db::import $outRoot $pgnFile $logFile {} {} {} -encoding utf-8

# Read back game info and compute fingerprints
set nGames [::scidb::db::count $outRoot]
puts "Imported $nGames games"

# Collect game headers
set games {}
for {set i 0} {$i < $nGames} {incr i} {
    set info [::scidb::db::get gameInfo $i -1 $outRoot Normal]
    set white [lindex $info 3]
    set black [lindex $info 5]
    set event [lindex $info 7]
    set date  [lindex $info 9]
    set round [lindex $info 11]
    set result [lindex $info 13]
    lappend games [list $white $black $event $date $round $result]
    puts "Game $i: $white vs $black, $event, $date, R$round, $result"
}

# Compute fingerprints using the same FNV-1a-64 as the C++ code
proc normalize {s} {
    set s [string trim $s]
    return [string tolower $s]
}

proc fnv1a64 {h s} {
    for {set i 0} {$i < [string length $s]} {incr i} {
        scan [string index $s $i] %c c
        set h [expr {($h ^ $c) & 0xFFFFFFFFFFFFFFFF}]
        set h [expr {($h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF}]
    }
    return $h
}

proc fingerprint {white black event date round result} {
    set h 0xcbf29ce484222325
    set h [fnv1a64 $h [normalize $white]]
    set h [fnv1a64 $h "|"]
    set h [fnv1a64 $h [normalize $black]]
    set h [fnv1a64 $h "|"]
    set h [fnv1a64 $h [normalize $event]]
    set h [fnv1a64 $h "|"]
    set h [fnv1a64 $h [normalize $date]]
    set h [fnv1a64 $h "|"]
    set h [fnv1a64 $h "${round}|${result}"]
    return [format "%016llx" $h]
}

# Write the .scm manifest
set scmFile ${outRoot}.scm
set mediaDir ${outRoot}.media

# Create media directory with sample files
file mkdir $mediaDir/images
file mkdir $mediaDir/audio
file mkdir $mediaDir/video

# Create a sample image (tiny PNG)
set pngData [binary decode base64 \
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="]
set fd [open ${mediaDir}/images/bilbao2008.jpg wb]
puts -nonewline $fd $pngData
close $fd

set fd [open ${mediaDir}/images/linares2009.jpg wb]
puts -nonewline $fd $pngData
close $fd

set fd [open ${mediaDir}/images/london2012.jpg wb]
puts -nonewline $fd $pngData
close $fd

# Create dummy audio/video files (just text placeholders)
set fd [open ${mediaDir}/audio/interview.mp3 w]
puts $fd "dummy audio file"
close $fd

set fd [open ${mediaDir}/video/analysis.mp4 w]
puts $fd "dummy video file"
close $fd

# Write the .scm manifest
set fd [open $scmFile w]
puts $fd "\[Database \"Test Media Database\"\]"
puts $fd "\[MediaDir \"${outRoot}.media\"\]"
puts $fd "\[Encoding \"utf-8\"\]"
puts $fd ""

# Media library
puts $fd "\[Media \"M01\"\]"
puts $fd "Type: picture"
puts $fd "Path: images/bilbao2008.jpg"
puts $fd "Title: \"Bilbao 2008: Topalov-Anand\""
puts $fd ""

puts $fd "\[Media \"M02\"\]"
puts $fd "Type: audio"
puts $fd "Path: audio/interview.mp3"
puts $fd "Title: \"Post-game interview\""
puts $fd ""

puts $fd "\[Media \"M03\"\]"
puts $fd "Type: picture"
puts $fd "Path: images/linares2009.jpg"
puts $fd "Title: \"Linares 2009: Carlsen-Kramnik\""
puts $fd ""

puts $fd "\[Media \"M04\"\]"
puts $fd "Type: video"
puts $fd "Path: video/analysis.mp4"
puts $fd "Title: \"Game analysis video\""
puts $fd ""

puts $fd "\[Media \"M05\"\]"
puts $fd "Type: picture"
puts $fd "Path: images/london2012.jpg"
puts $fd "Title: \"London 2012: Carlsen-Kramnik\""
puts $fd ""

# Game linkages using fingerprints
set i 0
foreach game $games {
    lassign $game white black event date round result
    set fp [fingerprint $white $black $event $date $round $result]
    puts $fd "\[Game \"${fp}\"]"
    switch -- $i {
        0 { puts $fd "Media: M01, M02" }
        1 { puts $fd "Media: M03, M04" }
        2 { puts $fd "Media: M05" }
    }
    puts $fd ""
    incr i
}

close $fd

puts "Created $scmFile"
puts "Created media directory: $mediaDir"
puts ""
puts "To test: open ${outRoot}.sci in scidb, select a game, check the Media tab"