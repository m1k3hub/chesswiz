# Database > Maintenance > Convert copies every game into a new .sci database
# (the copy and save commands need their progress and log callbacks).
package require tcltest 2.5
tcltest::test convert {Convert database copies every game into a new .sci} -setup {
	set dir [file join $::scidb::test::app::testDir tmp-app convert]
	file delete -force $dir; file mkdir $dir
	set src [file join $dir src.pgn]
	set fh [open $src w]
	for {set i 1} {$i <= 7} {incr i} { puts $fh "\[Event \"C\"\]\n\[White \"W$i\"\]\n\[Black \"B$i\"\]\n\[Result \"1-0\"\]\n\n1. e4 e5 2. Nf3 1-0\n" }
	close $fh
	::scidb::db::open $src {apply {args {return 0}}} {} {apply {args {return 0}}} {}
	set dst [file join $dir out.sci]
	rename ::dialog::question ::zq; proc ::dialog::question args { return no }
	rename ::dialog::saveFile ::zs; proc ::dialog::saveFile args [list return [list $dst utf-8]]
	rename ::dialog::info ::zi; proc ::dialog::info args { set ::zinfo $args }
} -body {
	set rc [catch {::application::database::ConvertDatabase .application $src Normal} r]
	list $rc [file exists $dst] [string match "*7*" $::zinfo]
} -cleanup {
	catch { ::scidb::db::close $src }
	rename ::dialog::question {}; rename ::zq ::dialog::question
	rename ::dialog::saveFile {}; rename ::zs ::dialog::saveFile
	rename ::dialog::info {}; rename ::zi ::dialog::info
} -result {0 1 1}

tcltest::testConstraint cbhFixturePresent [file exists [file join $::scidb::test::app::testDir tmp-app cbh-p0 in "C45 Scotch Opening-168.cbh"]]

tcltest::test cbh-raw-copy {::scidb::db::copy copies a .cbh fixture into a new .cbh and reopens it} -constraints cbhFixturePresent -setup {
	set dir [file join $::scidb::test::app::testDir tmp-app cbh-copy-test]
	file delete -force $dir; file mkdir $dir
	set fixtRoot [file join $::scidb::test::app::testDir tmp-app cbh-p0 in "C45 Scotch Opening-168"]
	foreach f [glob -nocomplain "${fixtRoot}.*"] {
		file copy -force $f [file join $dir "src[file extension $f]"]
	}
	set src [file normalize [file join $dir src.cbh]]
	set dst [file normalize [file join $dir dst.cbh]]
	set nop {apply {args {return 0}}}
} -body {
	::scidb::db::load $src $nop {} -readonly 1
	set srcCount [::scidb::db::count games $src Normal]
	set srcInfos {}
	for {set i 0} {$i < $srcCount} {incr i} {
		lappend srcInfos [::scidb::db::get gameInfo $i -1 $src Normal]
	}

	::scidb::db::new $dst Normal [::application::database::lookupType Unspecific]
	::scidb::db::attach $dst $dst
	set copyRes [::scidb::db::copy $src $dst {} $nop {} $nop {}]
	::scidb::db::save $dst $nop {}
	::scidb::db::close $dst
	::scidb::db::close $src

	::scidb::db::load $dst $nop {} -readonly 1
	set dstCount [::scidb::db::count games $dst Normal]
	set dstInfos {}
	for {set i 0} {$i < $dstCount} {incr i} {
		lappend dstInfos [::scidb::db::get gameInfo $i -1 $dst Normal]
	}
	::scidb::db::close $dst

	list [lindex $copyRes 0] [expr {$srcCount == $dstCount}] $srcCount [expr {$srcInfos eq $dstInfos}]
} -cleanup {
	catch { ::scidb::db::close $dst }
	catch { ::scidb::db::close $src }
} -result {10 1 10 1}

tcltest::test cbh-reencode-refused {::scidb::db::copy refuses non-ChessBase source into a .cbh destination} -setup {
	set dir [file join $::scidb::test::app::testDir tmp-app cbh-refuse-test]
	file delete -force $dir; file mkdir $dir
	set src [file normalize [file join $dir src.pgn]]
	set dst [file normalize [file join $dir dst.cbh]]
	set fh [open $src w]
	puts $fh "\[Event \"RefuseTest\"\]\n\[White \"W\"\]\n\[Black \"B\"\]\n\[Result \"1-0\"\]\n\n1. e4 e5 1-0\n"
	close $fh
	set nop {apply {args {return 0}}}
	::scidb::db::open $src $nop {} $nop {}
	::scidb::db::new $dst Normal [::application::database::lookupType Unspecific]
	::scidb::db::attach $dst $dst
} -body {
	set rc [catch {::scidb::db::copy $src $dst {} $nop {} $nop {}} err]
	list $rc [expr {[string match "*ChessBase*" $err] || [string match "*Write_Failed*" $err] || [string match "*write*" [string tolower $err]]}]
} -cleanup {
	catch { ::scidb::db::close $dst }
	catch { ::scidb::db::close $src }
} -result {1 1}

tcltest::cleanupTests
