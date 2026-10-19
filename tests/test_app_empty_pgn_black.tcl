# ======================================================================
# Scidb App Test Suite -- empty PGN database (G27): black rectangle
# ======================================================================
# Windows run 2 report: opening an empty (0 bytes) PGN database shows a
# black rectangle at the top left of the toolbar strip (cosmetic).  The
# test opens an empty PGN through the real loader, walks the whole widget
# tree and flags every widget which renders (nearly) black, and every
# canvas without content or with black-filled items.  The collected dump
# goes into tmp-app/finish/g27/widgets-dump.txt (and -control.txt when
# the dump is taken with a one-game database).
# ======================================================================

package require Tcl 8.5
package require tcltest 2.5

namespace eval ::scidb::test::emptyblack {
	variable opened {}
	variable dump {}
	variable dumpFile [file join [file dirname [info script]] \
		tmp-app finish g27 widgets-dump.txt]
}

proc ::scidb::test::emptyblack::ignore {args} { return 0 }

proc ::scidb::test::emptyblack::emit {line} {
	variable dump
	append dump $line \n
}

# Walk <w>: widgets rendering (nearly) black, and canvases (item count,
# black filled items, empty canvases, zero sizes).
proc ::scidb::test::emptyblack::walk {w} {
	if {![winfo exists $w]} { return }
	set class [winfo class $w]
	set path [winfo name $w]
	catch {
		if {[string match {#[0-9a-fA-F]*} [set bg [$w cget -background]]]} {
			lassign [winfo rgb $w r g b]
			if {$r < 40 && $g < 40 && $b < 40} {
				emit "DARK $class $w $bg [winfo width $w]x[winfo height $w]"
			}
		}
	}
	if {$class in {TCanvas Canvas}} {
		set items [$w find all]
		foreach i $items {
			set type ""
			catch { set type [$w type $i] }
			if {$type eq "text"} { continue } ;# black text is no black rectangle
			set fill ""
			catch { set fill [$w itemcget $i -fill] }
			if {$fill eq "black" || $fill eq "#000000"} {
				catch { emit "CANVASFILL $w $i $type [$w itemcget $i -tags]" }
			}
		}
		emit "CANVAS $w [llength $items] [winfo width $w]x[winfo height $w] @[winfo rootx $w]+[winfo rooty $w]"
	}
	foreach c [winfo children $w] { ::scidb::test::emptyblack::walk $c }
}

proc ::scidb::test::emptyblack::mapWindow {} {
	catch {
		wm state .application normal
		wm geometry .application "[winfo screenwidth .]x[winfo screenheight .]+0+0"
	}
	update idletasks
	after 1200
	update idletasks
	update
}

proc ::scidb::test::emptyblack::flush {suffix} {
	variable dump
	variable dumpFile
	set dir [file dirname $dumpFile]
	if {![file isdirectory $dir]} { file mkdir $dir }
	if {[string length $suffix]} {
		set target ${dumpFile}$suffix
	} else {
		set target $dumpFile
	}
	set fh [open $target w]
	fconfigure $fh -encoding utf-8
	if {[string length $dump]} { puts $fh [string trimright $dump \n] }
	close $fh
}

proc ::scidb::test::emptyblack::openFile {path} {
	variable opened
	foreach file $opened { catch { ::scidb::db::close $file } }
	set opened {}
	::scidb::db::open $path ::scidb::test::emptyblack::ignore {} ::scidb::test::emptyblack::ignore {}
	catch { ::application::switchTab database }
	::scidb::test::emptyblack::mapWindow
	update idletasks
	update
	after 500
	update idletasks
	update
	lappend opened $path
	return $path
}

proc ::scidb::test::emptyblack::makeEmpty {} {
	variable opened
	set dir [file join [::tcltest::temporaryDirectory] g27]
	file mkdir $dir
	set file [file join $dir empty.pgn]
	set fh [open $file w]
	close $fh
	return $file
}

proc ::scidb::test::emptyblack::makeOneGame {} {
	variable opened
	set dir [file join [::tcltest::temporaryDirectory] g27]
	file mkdir $dir
	set file [file join $dir one.pgn]
	set fh [open $file w]
	fconfigure $fh -encoding utf-8
	puts $fh {[Event "G1"]}
	puts $fh {[Site "X"]}
	puts $fh {[Date "2024.01.01"]}
	puts $fh {[Round "1"]}
	puts $fh {[White "W"]}
	puts $fh {[Black "B"]}
	puts $fh {[Result "1-0"]}
	puts $fh ""
	puts $fh "1.e4 e5 2.Nf3 Nc6 3.Bb5 a6 1-0"
	close $fh
	return $file
}

# In the empty PGN database no widget of the application renders black,
# and no canvas item is filled black (the reported black rectangle).
tcltest::test emptyblack-no-black {no black rendering widget or canvas item exists with an empty PGN database open} -setup {
	set file [::scidb::test::emptyblack::makeEmpty]
	::scidb::test::emptyblack::openFile $file
} -body {
	variable ::scidb::test::emptyblack::dump ""
	::scidb::test::emptyblack::walk .application
	::scidb::test::emptyblack::flush {}
	set report $::scidb::test::emptyblack::dump
	set bad {}
	foreach line [split $report \n] {
		if {[string match {DARK*} $line]} { lappend bad $line; continue }
		if {![string match {CANVASFILL*} $line]} { continue }
		# the dotted drag handles of the toolbars, the keyboard focus
		# ring of the switcher card and the media LCD (video controls)
		# are black by design
		if {[regexp {\.handle\.c \d+ rectangle (rect|border)} $line]} { continue }
		if {[regexp { \d+ rectangle active\d+} $line]} { continue }
		if {[regexp {mediaBackend.*rectangle lcd} $line]} { continue }
		lappend bad $line
	}
	set ::scidb::test::emptyblack::badReport $bad
	expr {[llength $bad] == 0}
} -cleanup {
	catch {
		file delete -force [file join [::tcltest::temporaryDirectory] g27]
		file delete -force [file join [::tcltest::temporaryDirectory] tmp-book]
	}
	foreach file $::scidb::test::emptyblack::opened {
		catch { ::scidb::db::close $file }
	}
	set ::scidb::test::emptyblack::opened {}
	set ::scidb::test::emptyblack::dump {}
} -result 1

tcltest::test emptyblack-control-dump {the one-game control is dumped for comparison} -setup {
	set file [::scidb::test::emptyblack::makeOneGame]
	::scidb::test::emptyblack::openFile $file
} -body {
	variable ::scidb::test::emptyblack::dump ""
	::scidb::test::emptyblack::walk .application
	::scidb::test::emptyblack::flush -control
	expr {[string length $::scidb::test::emptyblack::dump] > 0}
} -cleanup {
	catch {
		file delete -force [file join [::tcltest::temporaryDirectory] g27]
		file delete -force [file join [::tcltest::temporaryDirectory] tmp-book]
	}
	foreach file $::scidb::test::emptyblack::opened {
		catch { ::scidb::db::close $file }
	}
	set ::scidb::test::emptyblack::opened {}
	set ::scidb::test::emptyblack::dump {}
} -result 1

tcltest::cleanupTests