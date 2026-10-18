#!/bin/bash
# Multimedia test database for the media panel (2026-10-17). Rerunnable.
#   tests/tmp-app/media-test/make.sh   -> MediaTest.sci + MediaTest.scm + MediaTest.media/
# Base: src/make_media_test (3 games, fingerprint linkage). Added here: a 90 s
# video with a burned-in clock and tone, a second video, a live stream entry,
# position-keyed [Interactive] range segments and a [BoardSync] timeline for
# the Carlsen-Kramnik game (1.e4 ... 9...Nb8, 18 plies).
set -euo pipefail
cd "$(dirname "$0")"; ROOT=$(cd ../../.. && pwd)
rm -rf MediaTest.*; "$ROOT/src/make_media_test" "$PWD/MediaTest" >/dev/null
mkdir -p MediaTest.media/reports
cat > MediaTest.media/reports/opening.html <<'HTML'
<!doctype html><html><head><meta charset="utf-8"><title>Generated opening report</title></head>
<body><h1>Generated opening report</h1><p>Develop the pieces and castle.</p></body></html>
HTML
V=MediaTest.media/video
ffmpeg -hide_banner -loglevel error -y -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=90" \
  -f lavfi -i "sine=frequency=440:beep_factor=4:duration=90" \
  -vf "drawtext=text='Chesswiz media test  %{pts\:hms}':fontsize=48:fontcolor=white:box=1:boxcolor=black@0.6:x=40:y=40" \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest $V/analysis.mp4
ffmpeg -hide_banner -loglevel error -y -f lavfi -i "smptebars=size=1280x720:rate=30:duration=30" \
  -f lavfi -i "sine=frequency=660:duration=30" \
  -vf "drawtext=text='Second video  %{pts\:hms}':fontsize=48:fontcolor=white:box=1:boxcolor=black@0.6:x=40:y=40" \
  -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest $V/lecture2.mp4
FP=$(grep -B0 -A1 '^\[Game "a3727a90366adc96"\]' MediaTest.scm >/dev/null && echo a3727a90366adc96)
# Get the generated game's mainline positions from Chesswiz's own engine.
# This keeps the fixture rerunnable without a separate python-chess install.
cat > mainline.tcl <<'TCL'
set fixture [file dirname [file normalize [info script]]]
set root [file normalize [file join $fixture ../../..]]
cd $root
set argv {--single-process}; set argc 1
set ::env(SCIDB_AI_TRIAGE) 0
set ::env(SCIDB_AI_CLASSIFIER) off
source -encoding utf-8 [file join $root tcl chesswiz]
set ::scidb::dir::setup 0
set ::tips::Options(mode) neverShow
update
if {[catch {
set base [file join $fixture MediaTest.sci]
::scidb::db::load $base {apply {args {return 0}}} {} -readonly 1
::scidb::game::load 0 $base Normal 1
::scidb::game::go 0 start
set f [open [file join $fixture mainline.fens] w]
for {set i 0} {$i < 18} {incr i} {
    ::scidb::game::go 0 1
    puts $f [join [lrange [split [::scidb::game::fen 0]] 0 1] " "]
}
close $f
} error]} {puts stderr $::errorInfo; exit 1}
exit
TCL
HOME="$PWD/fixture-home" timeout -k 3 20 xvfb-run -a "$ROOT/src/tkchesswiz" "$PWD/mainline.tcl"
python3 - "$FP" >> MediaTest.scm <<'PY'
import sys
fp = sys.argv[1]
with open("mainline.fens") as source:
    fens = source.read().splitlines()
assert len(fens) == 18, fens
print('\n[Media "M06"]\nType: video\nPath: video/lecture2.mp4\nTitle: "Second video (30 s, colour bars)"')
print('\n[Media "M07"]\nType: stream\nPath: https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8\nTitle: "Live stream test (HLS)"')
print('\n[Media "M08"]\nType: report\nPath: reports/opening.html\nTitle: "Generated opening report"')
print(f'\n[Game "{fp}"]\nMedia: M06, M07, M08')
# position-keyed segments: after 3.Bb5 (ply 5), 5.O-O (ply 9), 9...Nb8 (ply 18)
for i, (ply, start, end, label) in enumerate([(5, 10, 25, "Ruy Lopez: 3.Bb5"), (9, 30, 45, "Castling: 5.O-O"), (18, 70, 88, "Breyer: 9...Nb8")], 1):
    print(f'\n[Interactive "I{i}"]\nMedia: M04\nFen: {fens[ply-1]}\nKind: range\nStart: {start}.0\nEnd: {end}.0\nLabel: "{label}"')
# board follows the video: one step every 4 s from 6 s, 18 plies
print('\n[BoardSync "M04"]')
for k in range(18): print(f"Step: {6000 + 4000*k}")
print("Arrow: 7000, green, e2-e4\nMark: 23000, red, b5\nComment: 40000, post, , \"White castles: the plan is d4\"")
PY
echo "made $(pwd)/MediaTest.sci"
