#!/usr/bin/env tclsh
# ======================================================================
# media-console end-to-end (e2e) fixture: native scid .sci/.scm path.
#
# Generates a media-rich .sci database (via make_media_test) and drives
# ::scidb::db::mediaFiles across every game, asserting that the native
# media companion (.scm) returns the correct per-game entries with the
# right type codes and resolvable, existing paths.
#
# Ground truth (from make_media_test):
#   gam 0 (Topalov-Anand): bilbao2008.png (picture 1) + interview.wav (audio 2)
#   gam 1 (Carlsen-Kramnik): linares2009.png (picture 1) + analysis.mp4 (video 3)
#   gam 2 (Carlsen-Kramnik): london2012.png (picture 1)
#
# Run with the headless media-console under Xvfb:
#   cd src && make make_media_test
#   make_media_test /tmp/media_fixture <eco.bin>
#   xvfb-run -a ./media_console ../media-console/sci-e2e.tcl
#
# Exit status: 0 = PASS, 1 = FAIL.
# ======================================================================

package require Tcl 8.6

proc ::mcProgress {args} {}
proc ::mcNoop {args} {}

set base [file nativename "/tmp/media_fixture.sci"]
set variant Normal

set failures 0
proc check {cond msg} {
    variable failures
    if {[catch {uplevel 1 [list expr $cond]} ok]} { set ok 0 }
    puts "  [expr {$ok ? "OK  " : "FAIL"}] $msg"
    if {!$ok} { incr failures }
}

puts "== media-console e2e: native .sci/.scm =="
puts "DB: $base"
if {![file exists $base]} {
    puts "SKIP: run make_media_test first to generate /tmp/media_fixture.sci"
    exit 0
}

set err [catch { ::scidb::db::load $base ::mcProgress progress-arg -readonly 1 } cursor]
check {$err == 0} "open .sci (load): $cursor"
if {$err} { puts "LOAD FAILED: $cursor"; exit 1 }

set err [catch { ::scidb::db::count games $base $variant } n]
check {$err == 0 && $n == 3} "game count = $n (3 expected)"
if {$err || $n == 0} { exit 1 }

# expected per game: {filename typeLabel ...}; type 1=picture 2=audio 3=video
set exp(0) {{bilbao2008.png picture} {interview.wav audio}}
set exp(1) {{linares2009.png picture} {analysis.mp4 video}}
set exp(2) {{london2012.png picture}}

for {set i 0} {$i < $n} {incr i} {
    set err [catch { ::scidb::db::mediaFiles $base $variant $i } rows]
    if {$err} { set rows {} }
    set got {}
    foreach row $rows {
        lassign $row path type title mediaId inline
        lappend got [list [file tail $path] [lindex {0 picture audio video stream} $type]]
        check {[file exists $path]} "game $i file exists on disk: [file tail $path]"
    }
    check {[string equal $got $exp($i)]} "game $i media == expected ($got)"
}

puts ""
if {$failures == 0} { puts "RESULT: PASS"; exit 0 } else { puts "RESULT: FAIL"; exit 1 }
