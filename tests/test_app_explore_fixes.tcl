# Regression tests for the bugs found by the explore-* bug hunts
# (tests/tmp-app/explore-fixes/REPORT.md).
package require Tcl 8.5
package require tcltest 2.5
::dialog::nonInteractive 1

namespace eval ::scidb::test::xfix {
	variable tmpDir [file join [file dirname [file normalize [info script]]] tmp-app xfix_[pid]]
	file mkdir $tmpDir
}

proc ::scidb::test::xfix::nop {args} { return 0 }
proc ::scidb::test::xfix::path {stem ext} {
	variable tmpDir
	return [file normalize [file join $tmpDir "${stem}_[clock microseconds].$ext"]]
}
proc ::scidb::test::xfix::writePgn {file n} {
	set fh [open $file w]
	fconfigure $fh -encoding utf-8
	for {set i 0} {$i < $n} {incr i} {
		puts $fh "\[Event \"X$i\"\]\n\[Site \"S\"\]\n\[White \"W$i\"\]\n\[Black \"B$i\"\]\n\[Result \"1-0\"\]\n"
		puts $fh "1. d4 d5 2. c4 e6 3. Nc3 Nf6 1-0\n"
	}
	close $fh
}
# collect background errors raised while the body runs
proc ::scidb::test::xfix::withBgErrors {script} {
	variable BgErrors {}
	set old [interp bgerror {}]
	interp bgerror {} [list apply {{msg opts} {
		lappend ::scidb::test::xfix::BgErrors $msg
	}}]
	try {
		uplevel 1 $script
		update
	} finally {
		interp bgerror {} $old
	}
	return $BgErrors
}

# Wait for the modal grab, not a fixed build time: Aqua can still be
# constructing the file list after 1500 ms. Keep the timer scoped to this test.
proc ::scidb::test::xfix::exportWhenReady {out deadline} {
    if {[grab current] eq ".application.export"} {
        set ::scidb::test::xfix::rc [catch {::export::DoExport .application .application.export $out} msg]
        lappend ::scidb::test::xfix::rc $msg
        catch {destroy .application.export}
    } elseif {[clock milliseconds] >= $deadline} {
        set ::scidb::test::xfix::rc {1 {export dialog did not become modal}}
        catch {destroy .application.export}
    } else {
        set ::scidb::test::xfix::exportTimer [after 20 [list ::scidb::test::xfix::exportWhenReady $out $deadline]]
    }
}

tcltest::test xfix-export-savemode {database export to PGN reads the save mode before the dialog is gone} -setup {
	set pgn [::scidb::test::xfix::path src pgn]
	set out [::scidb::test::xfix::path out pgn]
	::scidb::test::xfix::writePgn $pgn 3
	::scidb::db::open $pgn ::scidb::test::xfix::nop {} ::scidb::test::xfix::nop {}
	set ::export::Values(Type) pgn
} -body {
	set ::scidb::test::xfix::rc {}
	set ::scidb::test::xfix::exportTimer [after 20 [list ::scidb::test::xfix::exportWhenReady $out [expr {[clock milliseconds]+20000}]]]
	try {
		::export::open .application -base $pgn -variant Normal -view 0 -name src -extension pgn
	} finally {
		after cancel $::scidb::test::xfix::exportTimer
	}
	list [lindex $::scidb::test::xfix::rc 0] [file exists $out]
} -cleanup {
	catch { ::scidb::db::close $pgn }
	file delete -force $pgn $out
} -result {0 1}

tcltest::test xfix-export-savemode-game {single-game export to PGN reads the save mode before the dialog is gone} -setup {
	set pgn [::scidb::test::xfix::path src pgn]
	set out [::scidb::test::xfix::path out pgn]
	::scidb::test::xfix::writePgn $pgn 3
	::scidb::db::open $pgn ::scidb::test::xfix::nop {} ::scidb::test::xfix::nop {}
	set ::export::Values(Type) pgn
} -body {
	set ::scidb::test::xfix::rc {}
	set ::scidb::test::xfix::exportTimer [after 20 [list ::scidb::test::xfix::exportWhenReady $out [expr {[clock milliseconds]+20000}]]]
	try {
		::export::open .application -base $pgn -variant Normal -view 0 -index 0 -name src -extension pgn
	} finally {
		after cancel $::scidb::test::xfix::exportTimer
	}
	list [lindex $::scidb::test::xfix::rc 0] [file exists $out]
} -cleanup {
	catch { ::scidb::db::close $pgn }
	file delete -force $pgn $out
} -result {0 1}


# F1: closing a base before the switcher has been laid out (its subset
# is still empty) must fall back to the clipbase, not read Vars(map:)
tcltest::test xfix-switcher-close {closing a new database leaves the clipbase current, no error} -body {
	set base [::scidb::test::xfix::path sw sci]
	set errs [::scidb::test::xfix::withBgErrors {
		::application::database::newBase .application Normal $base
		set r [catch { ::application::database::CloseBase .application $base } msg]
	}]
	list $r [::scidb::db::get name] [llength $errs]
} -cleanup {
	foreach f [glob -nocomplain [file rootname $base].*] { file delete -force $f }
} -result [list 0 $::scidb::clipbaseName 0]

# F3: a games/events/players list update still pending when its base is
# closed must not read the base's (now removed) state
tcltest::test xfix-event-update-after-close {pending event-tab updates of a closed base raise no error} -body {
	set base [::scidb::test::xfix::path ev sci]
	::application::database::newBase .application Normal $base
	set path .application.nb.database.contents.event.twm
	set ns ::application::database::event
	${ns}::InitBase $path $base Normal
	set view [${ns}::View $path $base Normal]
	set errs [::scidb::test::xfix::withBgErrors {
		${ns}::games::Update $path 999 $base Normal $view
		${ns}::event::Update $path 999 $base Normal $view
		${ns}::player::Update $path 999 $base Normal $view
		# what closing the base does to the event tab, then the close itself
		${ns}::Close $path $base Normal
		catch { $::application::database::Vars(switcher) remove $base }
		::scidb::db::close $base
		update
	}]
	list [llength $errs] [lmap e $errs { string range $e 0 60 }]
} -cleanup {
	catch { ::application::database::CloseBase .application $base }
	foreach f [glob -nocomplain [file rootname $base].*] { file delete -force $f }
} -result {0 {}}

# F4: games copied from a PGN file into a new .sci database are stored:
# after closing and reopening, the .sci exports them with their moves
tcltest::test xfix-copy-pgn-to-sci {PGN games copied into .sci survive close and reopen} -setup {
	set pgn [::scidb::test::xfix::path cp pgn]
	set sci [::scidb::test::xfix::path cp sci]
	set out [::scidb::test::xfix::path cpout pgn]
	::scidb::test::xfix::writePgn $pgn 4
	::scidb::db::open $pgn ::scidb::test::xfix::nop {} ::scidb::test::xfix::nop {}
	set ::export::Values(Type) pgn
} -body {
	::application::database::newBase .application Normal $sci
	::scidb::view::copy $pgn 0 $sci Normal {} ::scidb::test::xfix::nop {} ::scidb::test::xfix::nop {}
	set n1 [::scidb::db::count games $sci Normal]
	::application::database::CloseBase .application $sci
	set scg [file size [file rootname $sci].scg]
	::application::database::openBase .application $sci no
	set n2 [::scidb::db::count games $sci Normal]
	after 1500 [list apply {{out} {
		catch {::export::DoExport .application .application.export $out}
		catch { destroy .application.export }
	}} $out]
	after 20000 { catch { destroy .application.export } }
	::export::open .application -base $sci -variant Normal -view 0 -name cp -extension pgn
	set fh [open $out]; set text [read $fh]; close $fh
	list $n1 [expr {$scg > 11}] $n2 [regexp -all {Nc3} $text]
} -cleanup {
	catch { ::application::database::CloseBase .application $sci }
	catch { ::scidb::db::close $pgn }
	foreach f [glob -nocomplain [file rootname $sci].* $pgn $out] { file delete -force $f }
} -result {4 1 4 4}

# F5: the ::scidb::view::print usage text separates arguments by one space
tcltest::test xfix-view-print-usage {view::print usage has no doubled space} -body {
	catch { ::scidb::view::print } msg
	list [string match "*<flags> <options>*" $msg] [string first "  " $msg]
} -result {1 -1}

tcltest::cleanupTests
