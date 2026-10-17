# Multi-game export through the app dialog and native writers.
package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::appbook {

variable testDir [file dirname [file normalize [info script]]]
variable tmpDir [file join $testDir tmp-book]
variable pgn {}
variable haveTexEngine ""

tcltest::testConstraint tex 0

proc setup {} {
	variable tmpDir
	variable haveTexEngine
	file mkdir $tmpDir
	foreach bin {pdflatex lualatex} {
		if {![catch {exec which $bin} out]} {
			set out [string trim $out]
			if {$out ne "" && [file executable $out]} {
				set haveTexEngine $bin
				tcltest::testConstraint tex 1
				break
			}
		}
	}
}

proc tempPath {stem ext} {
	variable tmpDir
	return [file normalize [file join $tmpDir "${stem}_[pid]_[clock microseconds].${ext}"]]
}

# Three small but distinct games for the book. Different events, players
# and results so the body of each game is easy to grep in the produced
# file (one section per game).
proc makePgn {} {
	set path [tempPath book pgn]
	set fh [open $path w]
	puts $fh {[Event "Casablanca 1921"]}
	puts $fh {[Site "Casablanca"]}
	puts $fh {[Date "1921.??.??"]}
	puts $fh {[Round "1"]}
	puts $fh {[White "Alekhine, Alexander"]}
	puts $fh {[Black "Bogoljubow, Efim"]}
	puts $fh {[Result "1-0"]}
	puts $fh ""
	puts $fh {1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 4. Ba4 Nf6 5. O-O Be7 6. Re1 b5 7. Bb3 d6 8. c3 O-O 9. h3 Nb8 10. d4 Nbd7 1-0}
	puts $fh {}
	puts $fh {[Event "London 1922"]}
	puts $fh {[Site "London"]}
	puts $fh {[Date "1922.??.??"]}
	puts $fh {[Round "2"]}
	puts $fh {[White "Capablanca, Jose Raul"]}
	puts $fh {[Black "Tarrasch, Siegbert"]}
	puts $fh {[Result "0-1"]}
	puts $fh ""
	puts $fh {1. d4 d5 2. c4 e6 3. Nc3 Nf6 4. Bg5 Nbd7 5. e3 c6 6. Nf3 Qa5 7. Bd3 Be7 8. O-O O-O 9. Qc2 Re8 0-1}
	puts $fh {}
	puts $fh {[Event "New York 1924"]}
	puts $fh {[Site "New York"]}
	puts $fh {[Date "1924.??.??"]}
	puts $fh {[Round "3"]}
	puts $fh {[White "Lasker, Emanuel"]}
	puts $fh {[Black "Reti, Richard"]}
	puts $fh {[Result "1/2-1/2"]}
	puts $fh ""
	puts $fh {1. Nf3 Nf6 2. c4 g6 3. Nc3 Bg7 4. d4 O-O 5. Bf4 d6 6. Qb3 Nbd7 7. e3 c5 8. Be2 a6 9. O-O Qa5 1/2-1/2}
	close $fh
	return $path
}

proc openPgn {path} {
	if {[catch { ::scidb::db::open $path ::scidb::test::appbook::log log \
							::scidb::test::appbook::progress progress } msg]} {
		error "cannot open PGN: $msg"
	}
}

proc log {args} {}
proc progress {args} {}

proc readFile {path} {
	set fh [open $path r]
	fconfigure $fh -translation binary
	set data [read $fh]
	close $fh
	return $data
}

setup

# Exercise DoExport, including its preamble and command arguments. Only
# the progress window is stubbed; the native writer runs unchanged.
proc exportBook {type {index {}} {view 0}} {
	variable pgn
	set ::export::Info(base) $pgn
	set ::export::Info(name) Book
	set ::export::Info(variant) Normal
	set ::export::Info(view) $view
	set ::export::Info(languages) {*}
	unset -nocomplain ::export::Info(index)
	if {$index ne ""} { set ::export::Info(index) $index }
	set ::export::Values(Type) $type
	set path [tempPath dialog $type]
	catch {destroy .bookExport}
	toplevel .bookExport
	::export::DoExport .application .bookExport $path
	return $path
}

set pgn [makePgn]
openPgn $pgn
set savedShare $::scidb::dir::share
set ::scidb::dir::share [file normalize [file join $testDir .. .. .. tcl]]
rename ::progress::start ::scidb::test::appbook::realProgress
proc ::progress::start {parent cmd args options close} {
	return [{*}$cmd ::scidb::test::appbook::progress {} {*}$args]
}

tcltest::test appbook-view-tex {dialog exports one complete document with three game sections} -body {
	set book [exportBook tex]
	set data [readFile $book]
	list [regexp -all {\\begin\{document\}} $data] \
		[regexp -all {\\end\{document\}} $data] \
		[regexp -all {\\section\{} $data] \
		[regexp -all {\\mainline\{} $data] \
		[string match {*Alekhine*Bogoljubow*Casablanca 1921*1921*Capablanca*Tarrasch*London 1922*1922*Lasker*Reti*New York 1924*1924*} $data] \
		[string match {*\\tableofcontents*} $data]
} -result {1 1 3 3 1 1}

tcltest::test appbook-tex-compiles {the unmodified dialog export compiles with a populated contents page} -constraints tex -body {
	set book [exportBook tex]
	for {set i 0} {$i < 2} {incr i} {
		exec $haveTexEngine -interaction=nonstopmode -halt-on-error \
			-output-directory [file dirname $book] $book
	}
	list [file exists [file rootname $book].pdf] \
		[regexp -all {contentsline} [readFile [file rootname $book].toc]]
} -result {1 3}

tcltest::test appbook-single-tex {single-game export by index keeps the selected header and document wrapper} -body {
	set data [readFile [exportBook tex 1]]
	list [regexp -all {\\section\{} $data] \
		[string match {*Capablanca*Tarrasch*London*} $data] \
		[string match {*\\end\{document\}*} $data]
} -result {1 1 1}

tcltest::test appbook-view-pdf {dialog exports the database to a native PDF} -body {
	set data [readFile [exportBook pdf]]
	list [string range $data 0 4] [regexp {/Count ([0-9]+)} $data -> pages] [expr {$pages >= 3}]
} -result {%PDF- 1 1}

tcltest::test appbook-selection {only games in the selected view are exported} -setup {
	set view [::scidb::view::new $pgn Normal unused unused unused unused master slave]
	::scidb::view::setGames $pgn Normal $view {0 2}
} -body {
	set data [readFile [exportBook tex {} $view]]
	list [regexp -all {\\section\{} $data] \
		[string match {*Alekhine*Lasker*} $data] \
		[string match {*Capablanca*} $data]
} -cleanup {
	::scidb::view::close $pgn Normal $view
} -result {2 1 0}

tcltest::test appbook-warning-continue {the threshold is exclusive and Continue exports all games} -setup {
	set threshold $::export::ManyGamesThreshold
	set asked 0
	rename ::dialog::question ::scidb::test::appbook::realQuestion
	proc ::dialog::question {args} {
		incr ::scidb::test::appbook::asked
		return continue
	}
} -body {
	set ::export::ManyGamesThreshold 3
	exportBook tex
	set atLimit $asked
	set ::export::ManyGamesThreshold 2
	set data [readFile [exportBook tex]]
	list $atLimit $asked [regexp -all {\\section\{} $data]
} -cleanup {
	set ::export::ManyGamesThreshold $threshold
	rename ::dialog::question {}
	rename ::scidb::test::appbook::realQuestion ::dialog::question
} -result {0 1 3}

tcltest::test appbook-warning {large PDF and TeX exports can be cancelled before the dialog closes or a file is written} -setup {
	set threshold $::export::ManyGamesThreshold
	set ::export::ManyGamesThreshold 2
	rename ::dialog::question ::scidb::test::appbook::realQuestion
	proc ::dialog::question {args} {
		set ::scidb::test::appbook::warningParent [winfo exists [lindex $args 1]]
		return cancel
	}
} -body {
	set result {}
	foreach type {pdf tex} {
		set path [exportBook $type]
		lappend result $warningParent [winfo exists .bookExport] [file exists $path]
		destroy .bookExport
	}
	set result
} -cleanup {
	set ::export::ManyGamesThreshold $threshold
	rename ::dialog::question {}
	rename ::scidb::test::appbook::realQuestion ::dialog::question
} -result {1 1 0 1 1 0}

rename ::progress::start {}
rename ::scidb::test::appbook::realProgress ::progress::start
set ::scidb::dir::share $savedShare
::scidb::db::close $pgn
} ;# namespace

tcltest::cleanupTests
