# ======================================================================
# Scidb App Test — PDF export regressions (db_pdf_writer + printPdf)
# ======================================================================
# Locks the native PDF publish path (PdfWriter): font model (embedded
# figurine font + Helvetica), page flow (A4, page breaks, wrapping),
# diagram images, and the save-on-destructor contract of the export
# framework (which never calls finish()).
#
# Runs the engine-level commands against a synthetic PGN database:
#   ::scidb::db::open       (PGN intake)
#   ::scidb::game::printPdf (single game)
#   ::scidb::view::printPdf (view, all games)
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::apppdf {

variable testDir [file dirname [file normalize [info script]]]
variable tmpDir [file join $testDir tmp-pdf]

proc setup {} {
	variable tmpDir
	file mkdir $tmpDir
}

proc tempPath {stem ext} {
	variable tmpDir
	return [file normalize [file join $tmpDir "${stem}_[pid]_[clock microseconds].${ext}"]]
}

proc makePgn {} {
	set path [tempPath diag-test pgn]
	set fh [open $path w]
	puts $fh {[Event "PDF Regression"]}
	puts $fh {[Site "Cyberspace"]}
	puts $fh {[Date "2026.09.03"]}
	puts $fh {[Round "1"]}
	puts $fh {[White "Tester, White"]}
	puts $fh {[Black "Tester, Black"]}
	puts $fh {[Result "1-0"]}
	puts $fh ""
	puts $fh {1. e4 {A kingside start with a long comment to exercise the word wrapping of the comment placement code across the right margin of the page.} e5 2. Nf3 $155 Nc6 3. Bb5 (3. Bc4 {Italian game.} Bc5 4. c3 Nf6 5. d3 d6) a6 4. Ba4 Nf6 5. O-O Be7 6. Re1 b5 7. Bb3 d6 8. c3 O-O 1-0}
	close $fh
	return $path
}

proc openPgn {path} {
	# ::scidb::db::open <file> <log> <log-arg> <progress-cmd> <progress-arg>
	if {[catch { ::scidb::db::open $path ::scidb::test::apppdf::log log \
							::scidb::test::apppdf::progress progress } msg]} {
		error "cannot open PGN: $msg"
	}
}

proc log {args} {}
proc progress {args} {}

proc readPdf {path} {
	set fh [open $path r]
	fconfigure $fh -translation binary
	set data [read $fh]
	close $fh
	return $data
}

proc pdfHeader {path} {
	string range [readPdf $path] 0 7
}

# Number of pages (the /Pages tree dictionary is uncompressed).
proc pageCount {path} {
	if {![regexp {/Count (\d+)} [readPdf $path] -> n]} { return -1 }
	return $n
}

# Inflated content of all streams (page content is Flate-compressed).
# The blocks are located with string markers: a "(.*?)endstream" regexp
# would rescan the 470K of binary compressed data at every unmatched
# position (quadratic runtime), which looks like a hang.
proc streamText {path} {
	set data [readPdf $path]
	set out {}
	set pos 0
	while {[set s [string first "stream" $data $pos]] >= 0} {
		if {$s >= 3 && [string range $data [expr {$s - 3}] [expr {$s - 1}]] eq "end"} {
			set pos [expr {$s + 6}]	;# tail of "endstream"
			continue
		}
		set b [expr {$s + 6}]
		if {[string index $data $b] eq "\r"} { incr b }
		if {[string index $data $b] eq "\n"} { incr b }
		set e [string first "endstream" $data $b]
		if {$e < 0} { break }
		catch { append out [zlib decompress [string range $data $b [expr {$e - 1}]]] }
		set pos [expr {$e + 9}]
	}
	return $out
}

setup

tcltest::test apppdf-open-pgn {the synthetic PGN opens as a database with one game} -body {
	set ::scidb::test::apppdf::pgn [makePgn]
	openPgn $::scidb::test::apppdf::pgn
	::scidb::db::count games $::scidb::test::apppdf::pgn Normal
} -result 1

tcltest::test apppdf-single-game {single-game PDF is written with a valid header and one page} -match glob -body {
	set out [tempPath single pdf]
	set rc [catch { ::scidb::game::printPdf $::scidb::test::apppdf::pgn Normal 0 $out 63 } msg]
	if {$rc} { error $msg }
	list \
		[expr {[file size $out] > 0}] \
		[pdfHeader $out] \
		[pageCount $out] \
		;
} -result {1 %PDF-1.[0-9] 1}

tcltest::test apppdf-view {view PDF export covers the game and reports the count} -match glob -body {
	set out [tempPath view pdf]
	set rc [catch { ::scidb::view::printPdf $::scidb::test::apppdf::pgn Normal 0 $out 63 \
							::scidb::test::apppdf::progress progress \
							::scidb::test::apppdf::log log } msg]
	if {$rc} { error $msg }
	list $msg [pdfHeader $out]
} -result {1 %PDF-1.[0-9]}

tcltest::test apppdf-single-game-embedded-font {the figurine font is embedded (subset CID TrueType)} -body {
	set out [tempPath single pdf]
	catch { ::scidb::game::printPdf $::scidb::test::apppdf::pgn Normal 0 $out 63 }
	set data [readPdf $out]
	list \
		[expr {[string first "ScidbChessTraveller" $data] >= 0}] \
		[expr {[string first "/FontFile2" $data] >= 0}] \
		;
} -result {1 1}

tcltest::test apppdf-diagram-images {a diagram NAG ($155) embeds the board image set} -body {
	set out [tempPath diag pdf]
	catch { ::scidb::game::printPdf $::scidb::test::apppdf::pgn Normal 0 $out 63 }
	set data [readPdf $out]
	# all 34 loaded images are embedded (24 pieces, 2 empty squares,
	# 8 border segments/corners) as DCTDecode JPEG XObjects
	list \
		[expr {[string first "/DCTDecode" $data] >= 0}] \
		[regexp -all {/DCTDecode} $data] \
		;
} -result {1 34}

tcltest::test apppdf-rendered-content {header, wrapped comment, variation and result are rendered} -body {
	set out [tempPath text pdf]
	catch { ::scidb::game::printPdf $::scidb::test::apppdf::pgn Normal 0 $out 63 }
	set text [streamText $out]
	# the words are placed one by one (word wrapping), so they appear as
	# separate string literals, also across the line break: match the
	# words in order instead of a contiguous phrase
	regsub -all {\s+} $text " " text
	list \
		[string match "*Event: PDF Regression*" $text] \
		[string match "*word*wrapping*placement*code*" $text] \
		[string match "*1-0*" $text] \
		;
} -result {1 1 1}

}

# namespace ::scidb::test::apppdf

# ----------------------------------------------------------------------

if {[info exists ::scidb::test::apppdf::pgn]} {
	catch { ::scidb::db::close $::scidb::test::apppdf::pgn }
}

::tcltest::cleanupTests
return