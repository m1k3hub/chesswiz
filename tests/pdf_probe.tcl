#!/usr/bin/env tkscidb
# ======================================================================
# pdf_probe - reproduce the PdfWriter construction exception
# ======================================================================
# Engine-level probe (no Tk app): load a database, then run both the
# single-game and the view printPdf paths and report the exceptions.
#
# Usage:
#   xvfb-run -a ./src/tkchesswiz tests/pdf_probe.tcl <base-file>
# ======================================================================

if {[llength $::argv] >= 1} {
	set ::base [lindex $::argv 0]
} else {
	set ::base /media/michael-g-thomas/sas_mirror/fixt/cbm168/168Endgame.cbh
}

proc ::mylog {args} { puts "LOG: $args" }
proc ::myprogress {args} {}

if {![info exists ::env(PROBE_SCAN)]} { set ::env(PROBE_SCAN) "" }

# load the ECO table (the app bundle's load.tcl does this at startup;
# the headless shell does not - without it exportGame crashes in
# EcoTable::getOpening recursion)
if {[catch { ::scidb::app::load eco src/data/eco.bin } ecoErr]} {
	puts "PROBE-ECO-ERR: $ecoErr"
	exit 1
}
puts "PROBE-ECO: loaded"

after 30000 { puts "PROBE-WATCHDOG: timeout"; exit 2 }

puts "PROBE-LOAD: $::base"
flush stdout

if {[catch { ::scidb::db::load $::base ::myprogress progress -encoding auto -readonly yes } msg]} {
	puts "PROBE-LOAD-ERR: $msg"
	exit 1
}
puts "PROBE-LOADED: $msg"
flush stdout

set n 0
if {[catch { set n [::scidb::db::count games $::base Normal] } m]} {
	puts "PROBE-COUNT-ERR: $m"
	exit 1
}
puts "PROBE-GAMES: $n"
flush stdout

if {$n < 1} { puts "PROBE: no games"; exit 1 }

# find the first real (non-guiding) game (best effort; guidingText may
# crash on this path - separate issue)
set idx 0
if {$::env(PROBE_SCAN) ne ""} {
	for {set g 0} {$g < $n && $g < 40} {incr g} {
		if {[catch { set data [::scidb::db::guidingText $::base Normal $g] } m]} { break }
		if {![dict get $data isGuiding]} { set idx $g; break }
	}
}
puts "PROBE-GAME-IDX: $idx"
flush stdout

# single-game path (constructs PdfWriter directly)
set out /tmp/pdf-probe-game.pdf
file delete -force $out
set rc [catch { ::scidb::game::printPdf $::base Normal $idx $out 63 } msg opts]
puts "GAME-PDF: rc=$rc msg=[string range $msg 0 300]"
if {$rc} { puts "GAME-PDF-OPTS: $opts" }
if {!$rc && [file exists $out]} { puts "GAME-PDF-SIZE: [file size $out]" }
flush stdout

# view path (progress/log args are appended by ::progress::start)
set out2 /tmp/pdf-probe-view.pdf
file delete -force $out2
set rc2 [catch { ::scidb::view::printPdf $::base Normal 0 $out2 63 myprogress progress mylog log } msg2 opts2]
puts "VIEW-PDF: rc=$rc2 msg=[string range $msg2 0 300]"
if {$rc2} { puts "VIEW-PDF-OPTS: $opts2" }
if {!$rc2} {
	puts "VIEW-PDF-COUNT: $msg2"
	if {[file exists $out2]} { puts "VIEW-PDF-SIZE: [file size $out2]" }
}
flush stdout

exit 0