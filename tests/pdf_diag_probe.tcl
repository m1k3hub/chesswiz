#!/usr/bin/env tkscidb
# ======================================================================
# pdf_diag_probe - diagram/layout coverage: a synthetic game with a
# diagram NAG ($155), comments, and a variation, exported to PDF.
# ======================================================================

set ::pgn /tmp/diag-test.pgn
set fh [open $::pgn w]
puts $fh {[Event "Diagram Test"]}
puts $fh {[Site "Cyberspace"]}
puts $fh {[Date "2026.09.03"]}
puts $fh {[Round "1"]}
puts $fh {[White "Tester, White"]}
puts $fh {[Black "Tester, Black"]}
puts $fh {[Result "1-0"]}
puts $fh ""
puts $fh {1. e4 {A kingside start with a long comment to exercise the word wrapping of the comment placement code across the right margin of the page.} e5 2. Nf3 $155 Nc6 3. Bb5 (3. Bc4 {Italian game.} Bc5 4. c3 Nf6 5. d3 d6) a6 4. Ba4 Nf6 5. O-O Be7 6. Re1 b5 7. Bb3 d6 8. c3 O-O 1-0}
close $fh

proc ::mylog {args} {}
proc ::myprogress {args} {}

# ECO table (required by the export path)
if {[catch { ::scidb::app::load eco src/data/eco.bin } msg]} {
	puts "ECO-ERR: $msg"; exit 1
}

# open the PGN as a database
if {[catch { ::scidb::db::open $::pgn ::mylog log ::myprogress progress } msg]} {
	puts "OPEN-ERR: $msg"; exit 1
}
puts "OPENED: $msg"

set n 0
catch { set n [::scidb::db::count games $::pgn Normal] }
puts "GAMES: $n"
if {$n < 1} { exit 1 }

set out /tmp/pdf-diag.pdf
file delete -force $out
set rc [catch { ::scidb::game::printPdf $::pgn Normal 0 $out 63 } msg opts]
puts "DIAG-PDF: rc=$rc msg=[string range $msg 0 200]"
if {!$rc && [file exists $out]} { puts "DIAG-PDF-SIZE: [file size $out]" }
exit 0