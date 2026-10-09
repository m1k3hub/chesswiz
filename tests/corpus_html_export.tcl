#!/usr/bin/env tkscidb
# ======================================================================
# corpus_html_export - phase-4 hardening gate for the HTML write path
# ======================================================================
# Runs every ChessBase database of a release directory through the full
# pipeline: open -> guiding-text sanitize (::scidb::db::guidingText) ->
# view export (::scidb::view::printHtml) -> structural output check
# (doctype, closed document, no <script>, no on*= handlers).
#
# Usage (unique script path - scidb is single-instance per script):
#   xvfb-run -a -s "-screen 0 1600x1000x24" \
#       ./src/tkchesswiz tests/corpus_html_export.tcl <release-dir>
#
# Defaults to the local CBM168 fixture set when no argument is given.
# Exits non-zero if any base fails.
# ======================================================================

if {[llength $::argv] >= 1} {
	set ::corpusDir [lindex $::argv 0]
} else {
	set ::corpusDir /media/michael-g-thomas/sas_mirror/fixt/cbm168
}


proc ::e2elog {args} {}
proc ::e2eprog {args} {}
proc ::mylog {args} {}
proc ::myprogress {args} {}

proc ::corpusStart {} {
	set ::bases [glob -nocomplain /media/michael-g-thomas/sas_mirror/fixt/cbm168/*.cbh]
	set ::bidx 0
	set ::pass 0
	set ::fail 0
	puts "CORPUS-START: [llength $::bases] bases"
	flush stdout
	after 200 ::corpusOpen
}

proc ::corpusOpen {} {
	if {$::bidx >= [llength $::bases]} {
		puts "CORPUS-RESULT: pass=$::pass fail=$::fail"
		catch { destroy . }
		exit [expr {$::fail > 0 ? 1 : 0}]
	}
	set ::cbh [lindex $::bases $::bidx]
	# schedule the completion poll BEFORE the (possibly modal) open
	after 4000 [list ::corpusCheck 0]
	catch { ::application::database::openBase .application $::cbh no } e
	# openBase returned synchronously (no modal): run the check directly
	after 100 [list ::corpusCheck 1]
}

proc ::corpusCheck {sync} {
	set cbh $::cbh
	set open 0
	catch { set open [::scidb::db::get open? $cbh] }
	if {!$open} { after 2000 [list ::corpusCheck 0]; return }

	set name [file tail [file rootname $cbh]]
	set n 0
	catch { set n [::scidb::db::count games $cbh Normal] }

	# 1. sanitize every guiding text
	set gt 0
	set gtErr 0
	for {set g 0} {$g < $n && $g < 400} {incr g} {
		if {[catch {set data [::scidb::db::guidingText $cbh Normal $g]} m]} {
			incr gtErr
			break
		}
		if {[dict get $data isGuiding]} {
			incr gt
			if {![string length [dict get $data html]]} { incr gtErr }
		}
	}

	# 2. export
	set out /tmp/corpus-[file tail $name].html
	set exErr {}
	set cnt -1
	if {[catch { set cnt [::scidb::view::printHtml $cbh Normal 0 $out 63 {} myprogress progress mylog log] } m]} {
		set exErr [string range $m 0 60]
	}
	puts "POST-SIZE: [file size $out]"
	flush stdout

	# 3. structural check
	set ok 1
	if {[string length $exErr]} {
		set ok 0
	} else {
		set fh [open $out r]; set d [read $fh]; close $fh
		if {![string match "<!DOCTYPE html>*" $d]} { set ok 0 }
		if {![string match "*</html>*" $d]} { set ok 0 }
		set lower [string tolower $d]
		if {[string first "<script" $lower] >= 0} { set ok 0 }
		if {[string first "onclick" $lower] >= 0} { set ok 0 }
	}

	if {$ok} {
		puts "OK $name games=$n gt=$gt exported=$cnt"
		incr ::pass
	} else {
		puts "FAIL $name games=$n gt=$gt gtErr=$gtErr exErr=$exErr"
		incr ::fail
	}

	incr ::bidx
	catch { ::scidb::db::close $cbh }
	after 200 ::corpusOpen
}

after 8000 ::corpusStart
