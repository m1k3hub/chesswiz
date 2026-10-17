#!/usr/bin/env tclsh
# ======================================================================
# media-console end-to-end (e2e) fixture: per-game media linkage.
#
# Opens a media-rich ChessBase database and drives ::scidb::db::mediaFiles
# across every game, asserting that the new guiding-text HTML extraction
# fallback:
#   1. returns per-game media for the documented guiding-text entries
#   2. resolves each reference to a real file in the sibling `<DB>.html`
#      media folder (the "per-game media linkage" solved in
#      docs/formats/CBM_FORMAT_DESIGN.md §7)
#   3. reports correct media type codes and the expected reference counts.
#
# Run with the headless media-console under Xvfb:
#   xvfb-run -a ./src/media_console media-console/run-e2e.tcl \
#       "/path/to/CB Light Database.cbh"   [optional]
#
# Exit status:  0 = PASS, 1 = FAIL.
# ======================================================================

package require Tcl 8.6

# Ground truth for the bundled fixture (index -> {count, known files}).
# A lone "<B><DB>" entry (game 0 = Intro) carries CBL_Logo.jpg; each
# tournament report carries its tournament images. Counts + key filenames
# verified against docs/formats/CBM_FORMAT_DESIGN.md §7.3 (which used 1-based "Rec N";
# scidb's ::scidb::db::mediaFiles is 0-based, hence index = RecN - 1).
set expected(index-0)     {1 {CBL_Logo.jpg}}
set expected(index-12059) {7 {CBL_Logo.jpg "Bilbao Topalov-Anand.jpg" tournaments.jpg turniere.jpg}}
set expected(index-12128) {7 {Linares1.jpg Linares2.jpg tournaments.jpg turniere.jpg}}
set expected(index-12645) {4 {"Tal memorial logo.gif" tournaments.jpg turniere.jpg}}
set expected(index-12676) {4 {Ivanchuk.jpg tournaments.jpg turniere.jpg}}
set expected(index-12768) {4 {11590093p0.jpg tournaments.jpg turniere.jpg}}
set expected(index-12980) {5 {"Three winners.jpg" tournaments.jpg turniere.jpg}}
set expected(index-13138) {6 {"Logo Foros.jpg" "Carlsen vs Ivanchuk2.jpg" tournaments.jpg turniere.jpg}}

# --- run connectivity / setup -----------------------------------------
proc ::mcProgress {args} {}
# load() requires a valid progress command (empty string crashes Progress).
proc ::mcNoop {args} {}

set dbFile [lindex $argv 0]
if {$dbFile eq ""} {
    set dbFile [file join $::env(HOME) Documents ChessBase Bases "CB Light Database.cbh"]
}
set base [file nativename $dbFile]
set variant Normal

# The fixture (CB Light Database.cbh) is a local, media-rich ChessBase
# corpus. If it is not present, skip rather than fail.
if {![file exists $base]} {
    puts "SKIP: fixture not found: $base"
    exit 0
}

set failures 0
proc check {cond msg} {
    variable failures
    if {[catch {uplevel 1 [list expr $cond]} ok]} {
        set ok 0
        puts "  FAIL $msg   (EVAL: $ok)"
    } else {
        puts "  [expr {$ok ? "OK  " : "FAIL"}] $msg"
    }
    if {!$ok} { incr failures }
}

puts "== media-console e2e fixture =="
puts "DB: $base"

set err [catch { ::scidb::db::load $base ::mcProgress progress-arg -readonly 1 } cursor]
check {$err == 0} "open database (load) : $cursor"
if {$err} { puts "LOAD FAILED: $cursor"; exit 1 }

set err [catch { ::scidb::db::count games $base $variant } n]
check {$err == 0 && $n >= 14831} "game count = $n (>= 14831 expected)"
if {$err || $n == 0} { exit 1 }

# Scan every game; collect per-game media and _all_ media files that must
# exist on disk.
set totGames 0            ;# games for which mediaFiles reports >= 1 entry
set totRefs 0             ;# total (path,type) rows across all games
set missingPictures 0     ;# referenced pictures (type 1) absent from <DB>.html
set absentStreams {}      ;# stream (type 4) refs absent on disk (CBM disc media)
set badType 0
array set gotCount {}     ;# gotCount(index) = number of media rows

for {set i 0} {$i < $n} {incr i} {
    if {[catch { ::scidb::db::mediaFiles $base $variant $i } rows]} {
        # mediaFiles errors only for out-of-range; treat as no-media.
        set rows {}
    }
    if {[llength $rows] == 0} { continue }

    set gotCount($i) [llength $rows]
    incr totGames
    incr totRefs [llength $rows]

    foreach row $rows {
        lassign $row path type title mediaId inline
        if {$type != 1 && $type != 2 && $type != 3 && $type != 4} { incr badType }
        if {![file exists $path]} {
            if {$type == 1} {
                incr missingPictures
            } elseif {$type == 4} {
                lappend absentStreams [file tail $path]
            }
        }
    }
}

# With the tag_game anchor mapping (doc §7.6), regular games of the linked
# tournament sections also carry media: 10 guiding-text records + 25 mapped
# regular games (one per section that anchors a game of this database), 54
# guiding rows + 71 mapped rows (fixture-stable counts).
check {$totGames == 35} "games carrying media = $totGames (10 guiding + 25 tag_game-mapped, expected)"
check {$totRefs == 125} "total media references = $totRefs (54 guiding + 71 mapped, expected)"

# per-index expected checks (doc §7.3 ground truth — guiding-text records)
puts "  per-game media counts (index -> n): [lsort -integer [array names gotCount]]"
foreach idx [array names expected] {
    set idx [string range $idx 6 end]
    lassign $expected(index-$idx) expCount files
    set got [expr {[info exists gotCount($idx)] ? $gotCount($idx) : 0}]
    check {$got == $expCount} "index $idx: $got/$expCount media (doc §7.3)"
}

# tag_game anchor mapping ground truth (doc §7.6): game 12038 = Topalov,
# Veselin - Anand, Viswanathan (Grand Slam Final 2008 round 4) is the first
# anchored game of the Bilbao report; its section carries the report header
# art plus the game's FEN thumbnail and players photo.
set mrows [::scidb::db::mediaFiles $base $variant 12038]
check {[llength $mrows] == 4} "game 12038 (Topalov-Anand, gsf r4): 4 mapped rows"
set mtitles {}
set mnames {}
foreach r $mrows {
    lappend mtitles [lindex $r 2]
    lappend mnames [file tail [lindex $r 0]]
}
set mtitles [lsort -unique $mtitles]
check {[llength $mtitles] == 1 && [lindex $mtitles 0] eq "Grand Slam Final"} \
    "mapped rows carry the anchor event in the title column"
set mnames [lsort $mnames]
set mwant [lsort [list cblogo.gif tournaments.jpg 29461125p0.jpg "Bilbao Topalov-Anand.jpg"]]
check {[llength $mnames] == 4 && $mnames eq $mwant} \
    "game 12038 media = Bilbao report section (header art + FEN thumb + players photo)"

check {$missingPictures == 0} "all referenced pictures exist in <DB>.html (0 missing, got $missingPictures)"
check {$badType == 0}         "all media types in {1..4} (got $badType bad)"

# Stream refs come from <IMG>... no, from CBLink(tag_stream,...) and point at
# .wmv clips shipped on the ChessBase Magazine disc (documented absent from
# <DB>.html). Assert they are exactly the known-absent set (CBM #125/#126).
set expectAbsent {
    {CBM 125 Gustafsson - Naiditsch.wmv}
    {CBM 126 Aronian - Grischuk.wmv}
    {CBM 126 Ftacnik on Jakovenko - Gashimov.wmv}
}
set absentSorted [lsort -unique $absentStreams]
set expectSorted [lsort $expectAbsent]
check {[string equal $absentSorted $expectSorted]} \
    "absent stream refs == known CBM-disc set (mapped + guiding, de-duplicated)"

puts ""
if {$failures == 0} {
    puts "RESULT: PASS  ($totGames games, $totRefs media refs, all on disk)"
    exit 0
} else {
    puts "RESULT: FAIL  ($failures failed checks)"
    exit 1
}
